extends Node2D
## Оркестратор забега: Shop → WaveIntro → Combat → WaveComplete → Shop, GameOver.
## Симуляция идёт шагом sim_step(dt) на физическом тике (30/60/120 FPS одинаково).
## UI вызывает команды сервисов; монеты/ХП не меняются из нескольких мест.

enum St { SHOP, WAVE_INTRO, COMBAT, WAVE_COMPLETE, GAMEOVER }

var run: RunState
var state: int = St.SHOP
var arena: ArenaModel
var arena_view: ArenaView
var player: Player
var projectiles: ProjectileManager
var hazards: HazardLayer
var fx: FxLayer
var coord := CombatCoordinator.new()
var modifier := ModifierController.new()
var entities: Node2D
var cam: Camera2D
var enemies: Array = []
var walls_nodes: Array = []
var gw := 1
var plan: Dictionary = {}
var queue: Array = []
var rng_combat := RandomNumberGenerator.new()
var time_now := 0.0
var wave_time := 0.0
var spawn_timer := 0.0
var batch_size := 3
var boss = null
var intro_t := 0.0
var complete_t := 0.0
var pending_explosions: Array = []
var buckets := {}
var bot: BotInput = null
var auto_open_ui := true              # false — для тестов без UI-воркфлоу

var hud: HudView
var touch: TouchControls
var shop_ui: ShopScreen
var pause_ui: Control
var results_ui: Control
var _kill_count_wave := 0
var _damage_at_wave_start := 0.0
var _hits_at_wave_start := 0
var _last_hurt_source := ""
var wave_result := {}

signal wave_won(info)
signal player_died
signal shop_opened


func _ready() -> void:
	run = Session.run
	if run == null:
		var res := SaveService.load_run()
		if res.run != null:
			run = res.run
			Session.run = run
		else:
			Session.run = RunState.new_run()
			run = Session.run
	_build_world()
	_build_ui()
	if not auto_open_ui:
		return
	if run.over:
		Session.go_menu()
	elif run.phase == "combat":
		_launch_wave()          # закрытие в бою: повтор той же волны с контрольной точки, без второй выплаты
	else:
		_enter_shop()


# ---- построение -------------------------------------------------------------
func _build_world() -> void:
	projectiles = ProjectileManager.new()
	hazards = HazardLayer.new()
	fx = FxLayer.new()
	entities = Node2D.new()
	entities.y_sort_enabled = true
	player = Player.new()
	cam = Camera2D.new()
	arena_view = ArenaView.new()
	add_child(arena_view)
	add_child(hazards)
	add_child(entities)
	entities.add_child(player)
	add_child(projectiles)
	add_child(fx)
	add_child(cam)
	cam.enabled = true
	projectiles.configure(self)
	hazards.configure(self)
	fx.configure(self)
	player.game = self
	player.visible = false


func _build_ui() -> void:
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)
	touch = TouchControls.new()
	touch.game = self
	hud_layer.add_child(touch)
	hud = HudView.new()
	hud.game = self
	hud_layer.add_child(hud)
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	shop_ui = ShopScreen.new()
	shop_ui.game = self
	ui_layer.add_child(shop_ui)
	shop_ui.start_requested.connect(_on_start_wave)
	shop_ui.menu_requested.connect(_exit_to_menu)
	var over_layer := CanvasLayer.new()
	over_layer.layer = 20
	add_child(over_layer)
	pause_ui = load("res://scripts/ui/pause_screen.gd").new()
	pause_ui.game = self
	over_layer.add_child(pause_ui)
	pause_ui.visible = false
	results_ui = load("res://scripts/ui/results_screen.gd").new()
	results_ui.game = self
	over_layer.add_child(results_ui)
	results_ui.visible = false


func _clear_arena_nodes() -> void:
	for w in walls_nodes:
		if is_instance_valid(w):
			w.queue_free()
	walls_nodes.clear()
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()


func _build_arena(info: Dictionary) -> void:
	_clear_arena_nodes()
	arena = ArenaModel.from_layout(info.layout_id)
	var tint: Color = LocationService.TINTS[int(info.tint_index)]
	arena_view.setup(arena, info.location_id, tint, hash([run.seed_value, info.sector]))
	for i in arena.walls.size():
		var wp := WallProp.new()
		wp.setup(arena.walls[i], arena.wall_kinds[i], tint)
		entities.add_child(wp)
		walls_nodes.append(wp)
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(arena.size.x)
	cam.limit_bottom = int(arena.size.y)


# ---- состояния --------------------------------------------------------------
func _enter_shop() -> void:
	state = St.SHOP
	get_tree().paused = false
	_clear_arena_nodes()
	projectiles.clear_all()
	hazards.clear()
	fx.clear()
	player.visible = false
	run.hp = StatCalc.max_hp(run)
	Session.save()
	shop_ui.open()
	hud.visible = false
	touch.visible = false
	shop_opened.emit()


func _on_start_wave() -> void:
	if state != St.SHOP:
		return
	var res := ShopService.begin_wave(run)
	if not res.ok:
		return
	Session.save()                 # контрольная точка перед волной (снимок монет, экипировка, магазин)
	_launch_wave()


func _launch_wave() -> void:
	gw = run.next_wave()
	plan = WaveDirector.build_plan(run.seed_value, gw)
	_build_arena(plan.sector_info)
	rng_combat.seed = hash([run.seed_value, gw, "combat"])
	player.visible = true
	player.position = arena.start
	player.vel = Vector2.ZERO
	player.setup(self, run)
	projectiles.clear_all()
	hazards.clear()
	fx.clear()
	fx.configure(self)
	coord.configure(gw)
	pending_explosions.clear()
	queue = plan.queue.duplicate(true)
	var sz := queue.size()
	batch_size = clampi(int(ceil(sz / 6.0)), 2, 8)
	spawn_timer = 1.2
	wave_time = 0.0
	boss = null
	_kill_count_wave = 0
	_damage_at_wave_start = float(run.stats.get("damage", 0.0))
	_hits_at_wave_start = projectiles.hits_landed
	var kinds: Array = []
	var info: Dictionary = plan.sector_info
	if info.native_hazard != "":
		kinds.append(info.native_hazard)
	if info.modifier != "":
		kinds.append(info.modifier)
	modifier.setup(self, kinds)
	cam.position = player.position
	cam.reset_smoothing()
	_update_camera()
	state = St.WAVE_INTRO
	intro_t = 2.4
	hud.visible = true
	touch.visible = Settings.touch_ui_enabled()
	shop_ui.close()
	hud.show_wave_intro(run, gw, plan)
	Sfx.play("wave")
	if plan.boss:
		_spawn_boss()


func _spawn_boss() -> void:
	var b := Boss.new()
	var pos = _find_spawn_point(300.0, true)
	if pos == null:
		pos = arena.start + Vector2(400, 0)
	b.setup_boss(self, plan.boss_id, gw, pos)
	entities.add_child(b)
	enemies.append(b)
	boss = b


func _exit_to_menu() -> void:
	Session.save()
	Session.go_menu()


# ---- вход ---------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if state == St.COMBAT or state == St.WAVE_INTRO:
		if event.is_action_pressed("pause"):
			open_pause()
			get_viewport().set_input_as_handled()
		elif state == St.COMBAT and event.is_action_pressed("medkit"):
			player.use_medkit()
		elif state == St.COMBAT and event.is_action_pressed("reload"):
			player.start_reload()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			if state == St.COMBAT or state == St.WAVE_INTRO:
				open_pause()
			elif state == St.SHOP:
				Session.save()
		NOTIFICATION_WM_CLOSE_REQUEST:
			if state == St.SHOP:
				Session.save()


func open_pause() -> void:
	if pause_ui.visible or state == St.GAMEOVER or state == St.SHOP:
		return
	get_tree().paused = true
	pause_ui.open()


func close_pause() -> void:
	get_tree().paused = false
	pause_ui.visible = false


func _poll_input() -> void:
	if bot != null:
		return
	var mv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var ai := Vector2.ZERO
	var firing := false
	if touch.visible:
		if touch.move_vec.length() > 0.05:
			mv = touch.move_vec
		if touch.aim_active:
			ai = touch.aim_vec
			firing = true
	else:
		var m := get_global_mouse_position() - player.position
		if m.length() > 4.0:
			ai = m.normalized()
		firing = Input.is_action_pressed("fire")
	player.move_input = mv
	player.aim_input = ai
	player.manual_fire = firing


# ---- симуляция --------------------------------------------------------------
func _physics_process(delta: float) -> void:
	match state:
		St.WAVE_INTRO:
			intro_t -= delta
			_update_camera()
			fx.step(delta)
			if intro_t <= 0.0:
				state = St.COMBAT
		St.COMBAT:
			_poll_input()
			sim_step(delta)
		St.WAVE_COMPLETE:
			complete_t -= delta
			fx.step(delta)
			if complete_t <= 0.0:
				_enter_shop()


func sim_step(dt: float) -> void:
	if state != St.COMBAT:
		return
	time_now += dt
	wave_time += dt
	run.play_time += dt
	if bot != null:
		bot.drive(self, dt)
	_rebuild_buckets()
	player.tick(dt)
	for e in enemies.duplicate():
		if is_instance_valid(e):
			e.tick(dt)
	_spawner_tick(dt)
	_explosion_tick(dt)
	projectiles.step(dt)
	hazards.step(dt)
	modifier.tick(dt)
	fx.step(dt)
	_update_camera()
	_update_walls(dt)
	if player.dead:
		_on_player_dead()
	elif queue.is_empty() and enemies.is_empty() and (plan.boss == false or boss != null):
		_on_wave_won()


func _update_camera() -> void:
	if player == null or arena == null:
		return
	cam.position = player.position


func _update_walls(dt: float) -> void:
	var pts: Array = [player.position]
	for e in enemies:
		if e.targetable():
			pts.append(e.position)
	for w in walls_nodes:
		w.update_fade(pts, dt)


func camera_rect() -> Rect2:
	var vs := get_viewport_rect().size
	var c := cam.position if cam != null else Vector2.ZERO
	return Rect2(c - vs * 0.5, vs)


# ---- пространственный поиск ---------------------------------------------------
func _rebuild_buckets() -> void:
	buckets.clear()
	for e in enemies:
		var c := Vector2i(int(e.position.x / 64.0), int(e.position.y / 64.0))
		if not buckets.has(c):
			buckets[c] = []
		buckets[c].append(e)


func enemies_near(p: Vector2, r: float) -> Array:
	var out: Array = []
	var pad := r + 56.0
	var x0 := int((p.x - pad) / 64.0)
	var x1 := int((p.x + pad) / 64.0)
	var y0 := int((p.y - pad) / 64.0)
	var y1 := int((p.y + pad) / 64.0)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var c := Vector2i(x, y)
			if buckets.has(c):
				out.append_array(buckets[c])
	return out


func enemies_along(a: Vector2, b: Vector2, pad: float) -> Array:
	var out: Array = []
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(pad + 56.0, pad + 56.0)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(pad + 56.0, pad + 56.0)
	for y in range(int(lo.y / 64.0), int(hi.y / 64.0) + 1):
		for x in range(int(lo.x / 64.0), int(hi.x / 64.0) + 1):
			var c := Vector2i(x, y)
			if buckets.has(c):
				out.append_array(buckets[c])
	return out


# ---- спавн -------------------------------------------------------------------
func ranged_alive() -> int:
	var n := 0
	for e in enemies:
		if e.is_ranged():
			n += 1
	return n


func _find_spawn_point(min_dist: float, prefer_visible_ok: bool = false, around: Variant = null, ring: Vector2 = Vector2.ZERO) -> Variant:
	var cells: Array = arena.free_cells()
	if cells.is_empty():
		return null
	var view := camera_rect().grow(40.0)
	for pass_i in 2:
		for i in 50:
			var c: Vector2
			if around != null:
				var a := rng_combat.randf() * TAU
				c = (around as Vector2) + Vector2.from_angle(a) * rng_combat.randf_range(ring.x, ring.y)
				if not arena.is_point_free(c, ArenaModel.NAV_MARGIN):
					continue
			else:
				var cell: Vector2i = cells[rng_combat.randi() % cells.size()]
				c = arena.cell_center(cell) + Vector2(rng_combat.randf_range(-10, 10), rng_combat.randf_range(-10, 10))
			if c.distance_to(player.position) < min_dist:
				continue
			if pass_i == 0 and not prefer_visible_ok and view.has_point(c):
				continue
			var ok := true
			for e in enemies:
				if e.position.distance_to(c) < 44.0:
					ok = false
					break
			if not ok:
				continue
			return c
		if prefer_visible_ok and around != null:
			continue
	return null


func _spawner_tick(dt: float) -> void:
	if queue.is_empty():
		return
	spawn_timer -= dt
	if spawn_timer <= 0.0 or enemies.size() <= 2:
		_spawn_batch()
		if spawn_timer <= 0.0:
			spawn_timer = 3.2


func _spawn_batch() -> void:
	var w: Dictionary = GameData.B.waves
	var alive_cap := int(w.alive_cap)
	var ranged_cap := int(w.ranged_alive_cap)
	var n := 0
	var tries := 0
	while n < batch_size and not queue.is_empty() and tries < queue.size() + batch_size:
		tries += 1
		if enemies.size() >= alive_cap:
			break
		var entry: Dictionary = queue[0]
		var def: Dictionary = GameData.enemies[entry.id]
		if def.role == "ranged" and ranged_alive() >= ranged_cap:
			queue.push_back(queue.pop_front())
			continue
		var pt = _find_spawn_point(float(w.external_spawn_min_distance))
		if pt == null:
			spawn_timer = 0.5        # безопасной точки нет — откладываем, а не ставим моба в героя
			break
		queue.pop_front()
		_spawn_enemy(entry.id, entry.trait, pt, false)
		n += 1


func _spawn_enemy(id: String, trait_id: String, pos: Vector2, summoned: bool) -> Enemy:
	var e := Enemy.new()
	e.setup(self, id, trait_id, gw, pos, summoned)
	entities.add_child(e)
	enemies.append(e)
	return e


func spawn_summon(id: String, near: Vector2) -> Enemy:
	var min_d := float(GameData.B.waves.summoned_spawn_min_distance)
	var pt = _find_spawn_point(min_d, true, near, Vector2(60, 220))
	if pt == null:
		pt = _find_spawn_point(min_d, true)
	if pt == null:
		return null
	return _spawn_enemy(id, "", pt, true)


## Дети носителя: два бегуна с предупреждением, без дохода, новых носителей не создают.
func spawn_children(parent: Enemy) -> void:
	var cid := str(parent.def.children_id)
	var cnt := int(parent.def.children_count)
	for i in cnt:
		spawn_summon(cid, parent.position)


func request_relocate(e: Enemy) -> void:
	var pt = _find_spawn_point(260.0)
	if pt == null:
		return
	Session.diag("relocate-" + e.id, "моб застрял — перемещён с предупреждением")
	e.position = pt
	e.path = PackedVector2Array()
	e._set_state(Enemy.S.SPAWN_WARNING)
	e.sprite.visible = false


# ---- события -------------------------------------------------------------------
func on_player_hurt(amount: float, source: String) -> void:
	_last_hurt_source = source
	Sfx.play("hurt")
	hud.on_hurt()


func on_enemy_died(e: Enemy) -> void:
	enemies.erase(e)
	_kill_count_wave += 1
	run.stats["kills"] = int(run.stats.get("kills", 0)) + 1
	fx.flash(e.position, Color(1.0, 0.7, 0.4), e.radius + 6.0)
	if e.elite_trait == "unstable":
		_queue_explosion(e)
	if e.id == "carrier":
		spawn_children(e)
	if e.is_boss:
		_on_boss_killed(e)
	e.queue_free()


func _queue_explosion(e: Enemy) -> void:
	var tr: Dictionary = {}
	for t in GameData.B.elites.traits:
		if t.id == "unstable":
			tr = t
	pending_explosions.append({
		"pos": e.position, "radius": float(tr.death_explosion_radius), "warn": float(tr.death_explosion_warning_seconds),
		"damage": float(tr.death_explosion_base_damage) * WaveMath.damage_mult(gw),
	})


func _explosion_tick(_dt: float) -> void:
	if pending_explosions.is_empty():
		return
	var rest: Array = []
	for x in pending_explosions:
		if hazards.add({"shape": "circle", "pos": x.pos, "radius": x.radius, "delay": x.warn, "life": 0.25, "damage": x.damage, "once": true, "palette": "enemy", "source": "unstable", "tag": "explosion"}):
			continue
		rest.append(x)           # лимит опасных полей: откладываем
	pending_explosions = rest


func _on_boss_killed(b: Enemy) -> void:
	# после смерти босса убираем незавершённые атаки, поля, снаряды и подкрепления
	hazards.clear()
	projectiles.clear_all()
	for e in enemies.duplicate():
		if e != b and is_instance_valid(e):
			e.state = Enemy.S.DEAD
			e.release_token()
			e.queue_free()
	enemies.clear()
	queue.clear()
	pending_explosions.clear()
	coord.reset()
	call_deferred("_on_wave_won")


func _on_wave_won() -> void:
	if state != St.COMBAT:
		return                   # идемпотентность: двойное событие не начисляет награду дважды
	state = St.WAVE_COMPLETE
	hazards.clear()
	projectiles.clear_all()
	pending_explosions.clear()
	get_tree().paused = false
	var was_boss := run.is_boss_wave(run.next_wave())
	var shots := int(run.stats.get("shots", 0))
	var res := Economy.complete_wave(run)
	if res.is_empty():
		return
	wave_result = res
	_log_wave(res)
	Session.save()
	complete_t = 2.4
	hud.show_wave_complete(res)
	wave_won.emit(res)


func _log_wave(res: Dictionary) -> void:
	var dmg := float(run.stats.get("damage", 0.0)) - _damage_at_wave_start
	var entry := {
		"wave": res.wave, "secs": snappedf(wave_time, 0.1), "dps": snappedf(dmg / maxf(wave_time, 0.1), 0.1),
		"hits": projectiles.hits_landed - _hits_at_wave_start, "kills": _kill_count_wave, "reward": res.reward.total,
		"purchases": int(run.stats.get("purchases", 0)), "weapon": run.equipped_weapon,
	}
	var wl: Array = run.stats.get("wave_log", [])
	wl.append(entry)
	while wl.size() > 30:
		wl.pop_front()
	run.stats["wave_log"] = wl
	Session.balance_log(entry)


func _on_player_dead() -> void:
	if state != St.COMBAT:
		return
	state = St.GAMEOVER
	var src := player.killer if player.killer != "" else _last_hurt_source
	Economy.mark_defeat(run, src)          # забег помечается завершённым ДО показа результатов
	Session.save()
	var rec := SaveService.add_result(run.next_wave(), run.play_time, src)
	Session.balance_log({"death": true, "wave": run.next_wave(), "by": src, "secs": snappedf(wave_time, 0.1)})
	get_tree().paused = false
	hud.visible = false
	touch.visible = false
	results_ui.open(rec)
	player_died.emit()
