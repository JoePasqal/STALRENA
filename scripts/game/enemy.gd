class_name Enemy
extends Node2D
## Враг. Конечный автомат: SpawnWarning → Enter → Move → Telegraph → Attack → Recovery → Dead.
## Урон и попадания считаются таймерами и геометрией, а не видимым кадром спрайта.
## Роли: melee/carrier (бродяга, бегун, загонщик, носитель), charge (таран),
## ranged (плевун, стрелок), area_melee (громила). Параметры — в balance_v1.json.

enum S { SPAWN_WARNING, ENTER, MOVE, TELEGRAPH, ATTACK, RECOVERY, DEAD }

var game
var id := ""
var def: Dictionary = {}
var role := ""
var hp := 1.0
var max_hp := 1.0
var dmg := 1.0
var speed := 50.0
var radius := 12.0
var state: int = S.SPAWN_WARNING
var t_state := 0.0
var warn_total := 1.0
var enter_total := 0.0
var elite_trait := ""
var summoned := false
var is_boss := false
var vel := Vector2.ZERO
var face := Vector2.DOWN
var since_attack := 99.0
var lock_pos := Vector2.ZERO
var lock_dir := Vector2.RIGHT
var locked := false
var burst_left := 0
var burst_t := 0.0
var wait_token := 0.0
var path := PackedVector2Array()
var path_i := 0
var path_t := 0.0
var path_interval := 0.25
var path_dest := Vector2(-9999, -9999)
var burn_left := 0.0
var burn_dps := 0.0
var burn_acc := 0.0
var flash_t := 0.0
var hit_applied := false
var charge_travel := 0.0
var flank_point := Vector2.ZERO
var flank_t := 0.0
var flank_age := 0.0
var flank_done := false
var strafe_dir := 1.0
var goal := Vector2.ZERO
var goal_valid := false
var goal_t := 0.0
var stuck_t := 0.0
var stuck_ref := Vector2.ZERO
var holds_token := false
var recovery_total := 0.5
var telegraph_total := 0.5

var sprite: Sprite2D
var _frame_dir := ""
var _anim_t := 0.0
var _dirty := true            # перерисовка _draw только при изменениях (экономия CPU на телефоне)


# ---- создание ---------------------------------------------------------------
func setup(g, p_id: String, p_trait: String, gw: int, pos: Vector2, p_summoned: bool = false) -> void:
	game = g
	id = p_id
	def = GameData.enemies[p_id]
	role = str(def.role)
	position = pos
	summoned = p_summoned
	elite_trait = p_trait
	max_hp = float(def.base_hp) * WaveMath.hp_mult(gw)
	dmg = float(def.base_damage) * WaveMath.damage_mult(gw)
	speed = float(def.base_move_speed) * WaveMath.speed_mult(gw)
	radius = float(def.hit_radius)
	if elite_trait != "":
		for tr in GameData.B.elites.traits:
			if tr.id != elite_trait:
				continue
			if elite_trait == "swift":
				max_hp *= float(tr.hp_multiplier)
				speed = minf(speed * float(tr.speed_multiplier), float(def.base_move_speed) * float(tr.final_speed_multiplier_cap))
			elif elite_trait == "sturdy":
				max_hp *= float(tr.hp_multiplier)
				speed *= float(tr.speed_multiplier)
	hp = max_hp
	var w: Dictionary = GameData.B.waves
	warn_total = float(w.summoned_warning_seconds) if summoned else float(w.spawn_warning_seconds)
	enter_total = float(w.attack_grace_after_summoned_enter_seconds) if summoned else 0.0
	telegraph_total = float(def.telegraph_seconds)
	recovery_total = float(def.recovery_seconds)
	path_interval = game.rng_combat.randf_range(0.2, 0.33)      # фазы 3–5 Гц
	path_t = game.rng_combat.randf() * path_interval
	strafe_dir = -1.0 if game.rng_combat.randf() < 0.5 else 1.0
	stuck_ref = pos
	_build_sprite()


func _build_sprite() -> void:
	sprite = Sprite2D.new()
	sprite.centered = false
	add_child(sprite)
	sprite.visible = false
	_set_dir_frame("S")


func _set_dir_frame(dname: String) -> void:
	if dname == _frame_dir:
		return
	_frame_dir = dname
	var vid := str(def.visual_id)
	var fr := AssetRegistry.get_actor_frame(vid, "idle", dname, 0)
	sprite.texture = fr.texture
	if fr.region.size != fr.texture.get_size():
		sprite.region_enabled = true
		sprite.region_rect = fr.region
	else:
		sprite.region_enabled = false
	sprite.offset = -fr.pivot
	var sc := AssetRegistry.get_scale(vid)
	sprite.scale = Vector2(sc * (-1.0 if fr.flip_h else 1.0), sc)


func targetable() -> bool:
	return state != S.SPAWN_WARNING and state != S.DEAD


func is_ranged() -> bool:
	return role == "ranged"


func counts_as_alive() -> bool:
	return state != S.DEAD


# ---- урон -------------------------------------------------------------------
func take_damage(amount: float, crit: bool, source: String) -> void:
	if state == S.SPAWN_WARNING or state == S.DEAD or amount <= 0.0:
		return
	hp -= amount
	_dirty = true
	flash_t = 0.1
	game.run.stats["damage"] = float(game.run.stats.get("damage", 0.0)) + amount
	if source == "player":
		game.fx.damage_number(position, amount, get_instance_id(), crit)
		Sfx.play("hit")
	elif source == "burn" or source == "hazard":
		game.fx.damage_number(position, amount, get_instance_id(), false)
	if hp <= 0.0:
		die()


func ignite(dps: float, duration: float) -> void:
	burn_left = duration         # одна копия: обновляем длительность, не суммируем
	burn_dps = dps


func _update_burn(dt: float) -> void:
	if burn_left <= 0.0:
		return
	burn_left -= dt
	burn_acc += dt
	if burn_acc >= 0.25:
		var amt := burn_dps * burn_acc
		burn_acc = 0.0
		take_damage(amt, false, "burn")


func die() -> void:
	if state == S.DEAD:
		return
	state = S.DEAD
	release_token()
	game.on_enemy_died(self)


func release_token() -> void:
	if holds_token:
		game.coord.release(self)
		holds_token = false


# ---- цикл -------------------------------------------------------------------
func tick(dt: float) -> void:
	if state == S.DEAD:
		return
	t_state += dt
	since_attack += dt
	flash_t = maxf(flash_t - dt, 0.0)
	_anim_t += dt
	_update_burn(dt)
	if state == S.DEAD:
		return
	match state:
		S.SPAWN_WARNING:
			if t_state >= warn_total:
				sprite.visible = true
				_set_state(S.ENTER if enter_total > 0.0 else S.MOVE)
		S.ENTER:
			if t_state >= enter_total:
				_set_state(S.MOVE)
		S.MOVE:
			_tick_move(dt)
			_check_stuck(dt)
		S.TELEGRAPH:
			_tick_telegraph(dt)
		S.ATTACK:
			_tick_attack(dt)
		S.RECOVERY:
			if t_state >= recovery_total:
				_set_state(S.MOVE)
	_update_visual(dt)


func _set_state(s: int) -> void:
	state = s
	t_state = 0.0
	_dirty = true


# ---- движение ---------------------------------------------------------------
func _speed_now(mult: float) -> float:
	var s := speed * mult
	if game.arena.in_water(position):
		s *= float(GameData.locations["flooded"].water_ground_move_speed_multiplier)
	return s


func _move_dir(dir: Vector2, dt: float, mult: float = 1.0) -> void:
	var before := position
	var sep := Vector2.ZERO
	for n in game.enemies_near(position, radius + 28.0):
		if n == self or not n.targetable():
			continue
		var d: Vector2 = position - n.position
		var dl := d.length()
		var min_d: float = radius + n.radius + 4.0
		if dl < min_d:
			if dl < 0.01:
				d = Vector2.from_angle(game.rng_combat.randf() * TAU)
				dl = 1.0
			sep += d / dl * (min_d - dl) / min_d * 70.0      # мягкое раздвижение
	var v := dir * _speed_now(mult) + sep
	var res: Dictionary = game.arena.resolve_circle(position + v * dt, radius)
	position = res.pos
	vel = (position - before) / maxf(dt, 0.0001)
	if dir.length() > 0.05:
		face = dir.normalized()


func _goto(dest: Vector2, dt: float, mult: float = 1.0) -> void:
	var tp := dest
	if game.arena.raycast_walls(position, dest, radius * 0.9) >= 0.0:
		path_t -= dt
		if path.size() == 0 or path_t <= 0.0 or path_dest.distance_to(dest) > 64.0:
			path = game.arena.find_path(position, dest)
			path_i = 0
			path_dest = dest
			path_t = path_interval
		while path_i < path.size() - 1 and position.distance_to(path[path_i]) < 22.0:
			path_i += 1
		# сглаживание: перескакиваем точки, если прямой путь свободен
		while path_i < path.size() - 1 and game.arena.raycast_walls(position, path[path_i + 1], radius * 0.9) < 0.0:
			path_i += 1
		if path_i < path.size():
			tp = path[path_i]
	else:
		path = PackedVector2Array()
	var d := tp - position
	_move_dir(d.normalized() if d.length() > 1.0 else Vector2.ZERO, dt, mult)


func _retreat(away_from: Vector2, dt: float, mult: float = 1.0) -> void:
	var dir := (position - away_from).normalized()
	for ang in [0.0, 0.9, -0.9, 1.6, -1.6]:
		var d: Vector2 = dir.rotated(ang * strafe_dir)
		if game.arena.raycast_walls(position, position + d * 44.0, radius) < 0.0:
			_move_dir(d, dt, mult)
			return
	vel = Vector2.ZERO


func _check_stuck(dt: float) -> void:
	if position.distance_to(stuck_ref) > 30.0:
		stuck_ref = position
		stuck_t = 0.0
		return
	stuck_t += dt
	if stuck_t > 6.0 and position.distance_to(game.player.position) > 140.0:
		stuck_t = 0.0
		game.request_relocate(self)


func _tick_move(dt: float) -> void:
	var pl = game.player
	if pl.dead:
		vel = Vector2.ZERO
		return
	var to: Vector2 = pl.position - position
	var dist := to.length()
	wait_token = maxf(wait_token - dt, 0.0)
	match role:
		"melee", "carrier":
			_move_melee(dt, dist)
		"charge":
			_move_charge(dt, dist)
		"ranged":
			if int(def.get("burst_count", 1)) > 1:
				_move_gunner(dt, dist)
			else:
				_move_spitter(dt, dist)
		"area_melee":
			_move_brute(dt, dist)
		_:
			_goto(pl.position, dt)


func _can_start() -> bool:
	return since_attack >= float(def.attack_cycle_min_seconds)


func _clear_shot(to_pos: Vector2) -> bool:
	return game.arena.line_of_sight(position, to_pos)


func _move_melee(dt: float, dist: float) -> void:
	var pl = game.player
	var reach := float(def.melee_range)
	if dist <= reach + 4.0 and _can_start() and _clear_shot(pl.position):
		_begin_telegraph()
		return
	var dest: Vector2 = pl.position
	if id == "flanker" and not flank_done:
		dest = _flank_dest(dt, dist)
	_goto(dest, dt)


func _flank_dest(dt: float, dist: float) -> Vector2:
	var pl = game.player
	flank_age += dt
	flank_t -= dt
	if flank_t <= 0.0:
		flank_t = float(def.retarget_seconds)
		var to: Vector2 = (pl.position - position).normalized()
		# боковая сторона относительно движения героя (если стоит — относительно подхода) и ближайших союзников
		var ref: Vector2 = pl.vel.normalized() if pl.vel.length() > 20.0 else to
		var perp := Vector2(-ref.y, ref.x)
		var crowd := Vector2.ZERO
		var cnt := 0
		for e in game.enemies_near(position, 300.0):
			if e != self and e.targetable():
				crowd += e.position - position
				cnt += 1
		var side := 1.0
		if cnt > 0 and (crowd / cnt).dot(perp) > 0.0:
			side = -1.0
		var p: Vector2 = pl.position + perp * side * float(def.flank_offset)
		var cell: Vector2i = game.arena.nearest_free_cell(p)
		flank_point = game.arena.cell_center(cell)
	if position.distance_to(flank_point) < 70.0 or dist < 220.0 or flank_age > 4.0:
		flank_done = true
		return game.player.position
	return flank_point


func _move_charge(dt: float, dist: float) -> void:
	var pl = game.player
	var amin := float(def.attack_range_min)
	var amax := float(def.attack_range_max)
	var dirv: Vector2 = (pl.position - position).normalized()
	var line_clear: bool = game.arena.raycast_walls(position, position + dirv * minf(dist, 400.0), radius) < 0.0
	if dist >= amin and dist <= amax and _can_start() and line_clear:
		_begin_telegraph()
		return
	if dist < amin:
		_retreat(pl.position, dt, 0.8)
	else:
		_goto(pl.position, dt)


func _move_spitter(dt: float, dist: float) -> void:
	var pl = game.player
	var pmin := float(def.preferred_distance_min)
	var pmax := float(def.preferred_distance_max)
	var los := _clear_shot(pl.position)
	if dist < pmin and los:
		_retreat(pl.position, dt, 0.9)
	elif dist > pmax or not los:
		_goto(pl.position, dt)
	else:
		vel = Vector2.ZERO
	if los and dist >= pmin * 0.8 and dist <= pmax * 1.15 and _can_start() and wait_token <= 0.0:
		_try_ranged_start(1)


func _move_gunner(dt: float, dist: float) -> void:
	var pl = game.player
	var pmin := float(def.preferred_distance_min)
	var pmax := float(def.preferred_distance_max)
	var los := _clear_shot(pl.position)
	var valid: bool = los and dist >= pmin and dist <= pmax
	if valid:
		goal_valid = false
		vel = Vector2.ZERO
		if _can_start() and wait_token <= 0.0:
			_try_ranged_start(int(def.burst_count))
		return
	if dist < pmin * 0.85 and los:
		_retreat(pl.position, dt, 0.9)
		return
	goal_t -= dt
	if not goal_valid or goal_t <= 0.0:
		goal_t = 1.2
		_pick_goal()
	if goal_valid:
		if position.distance_to(goal) < 18.0:
			goal_valid = false
			_goto(pl.position, dt, 0.5)
		else:
			_goto(goal, dt)
	else:
		_goto(pl.position, dt)


func _pick_goal() -> void:
	var pl = game.player
	var pmin := float(def.preferred_distance_min)
	var pmax := float(def.preferred_distance_max)
	var cells: Array = game.arena.free_cells()
	var best := Vector2.ZERO
	var best_d := 1e18
	for i in 14:
		var c: Vector2 = game.arena.cell_center(cells[game.rng_combat.randi() % cells.size()])
		var d := c.distance_to(pl.position)
		if d < pmin or d > pmax:
			continue
		if not game.arena.line_of_sight(c, pl.position):
			continue
		var s := position.distance_to(c)
		if s < best_d:
			best_d = s
			best = c
	goal_valid = best_d < 1e17
	goal = best


func _try_ranged_start(shots: int) -> void:
	if game.projectiles.enemy_room() < shots + 2:
		wait_token = 0.3                  # лимит снарядов: откладываем, невидимых не создаём
		return
	if not game.coord.request(self):
		wait_token = CombatCoordinator.retry_delay(game.rng_combat)
		return
	holds_token = true
	_begin_telegraph()


func _move_brute(dt: float, dist: float) -> void:
	var pl = game.player
	var ar := float(def.area_radius)
	if dist <= ar * 0.85 and _can_start() and _clear_shot(pl.position):
		_begin_telegraph()
		return
	_goto(pl.position, dt)


# ---- телеграф ---------------------------------------------------------------
func _begin_telegraph() -> void:
	var pl = game.player
	_set_state(S.TELEGRAPH)
	since_attack = 0.0            # цикл атаки считается от начала телеграфа
	locked = false
	hit_applied = false
	vel = Vector2.ZERO
	lock_dir = (pl.position - position).normalized()
	face = lock_dir
	lock_pos = pl.position
	if role == "area_melee":
		lock_pos = position + lock_dir * 30.0
		locked = true


func _lead() -> float:
	return float(def.get("aim_lock_lead_seconds", 0.0))


func _tick_telegraph(dt: float) -> void:
	var pl = game.player
	vel = Vector2.ZERO
	if pl.dead:
		release_token()
		_set_state(S.RECOVERY)
		return
	match role:
		"melee", "carrier":
			if not locked:
				lock_dir = (pl.position - position).normalized()
				face = lock_dir
			if t_state >= telegraph_total:
				_melee_strike()
		"area_melee":
			if t_state >= telegraph_total:
				if pl.position.distance_to(lock_pos) <= float(def.area_radius):
					pl.take_damage(dmg, id, false)
				game.fx.flash(lock_pos, Color(1.0, 0.6, 0.2), float(def.area_radius) * 0.8)
				_end_attack()
		"charge":
			if not locked:
				lock_dir = (pl.position - position).normalized()
				face = lock_dir
				if t_state >= telegraph_total - _lead():
					locked = true
			if t_state >= telegraph_total:
				_set_state(S.ATTACK)
				charge_travel = 0.0
				hit_applied = false
		"ranged":
			var burst := int(def.get("burst_count", 1))
			if not locked:
				if not _clear_shot(pl.position):
					# при потере видимости до фиксации — отмена подготовки
					release_token()
					_set_state(S.MOVE)
					since_attack = float(def.attack_cycle_min_seconds) - 0.8
					return
				lock_pos = pl.position
				if burst > 1 and game.gw >= int(GameData.B.scaling.late_predictive_aim_after_wave):
					var lead := minf(float(GameData.B.scaling.late_predictive_aim_max_seconds), _lead() * 1.0)
					lock_pos = pl.position + pl.vel * lead      # частичное упреждение, направление фиксируется заранее
				face = (lock_pos - position).normalized()
				if t_state >= telegraph_total - _lead():
					locked = true
					lock_dir = (lock_pos - position).normalized()
			if t_state >= telegraph_total:
				_set_state(S.ATTACK)
				burst_left = burst
				burst_t = 0.0


func _melee_strike() -> void:
	var pl = game.player
	# дистанция проверяется в момент нанесения, а не в начале замаха
	var reach: float = float(def.melee_range) + pl.radius
	if position.distance_to(pl.position) <= reach and not pl.dead:
		pl.take_damage(dmg, id, true)
	game.fx.flash(position + lock_dir * 18.0, Color(1.0, 0.5, 0.2), 14.0)
	_end_attack()


func _end_attack() -> void:
	release_token()
	_set_state(S.RECOVERY)


# ---- атака ------------------------------------------------------------------
func _tick_attack(dt: float) -> void:
	match role:
		"charge":
			_tick_charge(dt)
		"ranged":
			_tick_ranged_attack(dt)
		_:
			_end_attack()


func _tick_charge(dt: float) -> void:
	var pl = game.player
	var cs := WaveMath.charge_speed(def, game.gw)
	var step := lock_dir * cs * dt
	var wall_hit := false
	var tw: float = game.arena.raycast_walls(position, position + step, radius)
	if tw >= 0.0:
		step *= tw
		wall_hit = true
	var np := position + step
	var res: Dictionary = game.arena.resolve_circle(np, radius)
	if res.hit:
		wall_hit = true
	position = res.pos
	vel = step / maxf(dt, 0.0001)
	charge_travel += step.length()
	if not hit_applied and not pl.dead and position.distance_to(pl.position) <= radius + pl.radius:
		hit_applied = true
		pl.take_damage(dmg, id, false)
	if wall_hit or charge_travel >= float(def.charge_max_distance):
		vel = Vector2.ZERO
		_end_attack()           # после рывка — восстановление (окно уязвимости)


func _shoot(dir: Vector2, speed_v: float, kind: String, spread_deg: float, stop_at: float = -1.0) -> void:
	var ang := deg_to_rad(game.rng_combat.randf_range(-spread_deg, spread_deg))
	var d := dir.rotated(ang)
	var spawn_p := position + d * (radius + 6.0)
	if game.arena.raycast_walls(position, spawn_p) >= 0.0:
		return
	var maxd := 900.0 if stop_at < 0.0 else stop_at
	game.projectiles.spawn(false, spawn_p, d, speed_v * WaveMath.projectile_speed_mult(game.gw), dmg, maxd, 6.0 if kind != "spit" else 8.0, kind, 0, false, stop_at, id)


func _tick_ranged_attack(dt: float) -> void:
	vel = Vector2.ZERO
	var burst := int(def.get("burst_count", 1))
	burst_t -= dt
	if burst_left > 0 and burst_t <= 0.0:
		burst_left -= 1
		burst_t = float(def.get("burst_interval_seconds", 0.0))
		if burst == 1:
			var dist := maxf(lock_pos.distance_to(position) - radius, 60.0)
			_shoot(lock_dir, float(def.projectile_speed), "spit", float(def.spread_degrees_plus_minus), dist)
		else:
			var spread := float(def.spread_degrees_plus_minus)
			if game.gw > int(GameData.B.scaling.late_predictive_aim_after_wave):
				var k := clampf((game.gw - 24.0) / 36.0, 0.0, 1.0)
				spread = lerpf(spread, float(def.late_min_spread_degrees_plus_minus), k)
			spread = maxf(spread, float(def.get("late_min_spread_degrees_plus_minus", 0.0)))
			_shoot(lock_dir, float(def.projectile_speed), "bullet", spread)
	if burst_left <= 0 and burst_t <= 0.0:
		_end_attack()


# ---- визуал -----------------------------------------------------------------
func _dir_name() -> String:
	if absf(face.x) > absf(face.y):
		return "E" if face.x >= 0.0 else "W"
	return "S" if face.y >= 0.0 else "N"


func _update_visual(dt: float) -> void:
	if sprite == null:
		return
	if sprite.visible:
		_set_dir_frame(_dir_name())
		var moving := vel.length() > 5.0
		var bob := sin(_anim_t * 14.0) * 1.6 if moving else 0.0
		var squash := 1.0
		if state == S.TELEGRAPH:
			squash = 0.92 + 0.06 * sin(_anim_t * 30.0)
		sprite.position = Vector2(0, bob)
		var sc := AssetRegistry.get_scale(str(def.visual_id))
		sprite.scale = Vector2(sc * (-1.0 if _frame_dir == "W" else 1.0), sc * squash)
		sprite.modulate = Color(1.7, 1.4, 1.4) if flash_t > 0.0 else (Color(1.0, 0.8, 0.5) if burn_left > 0.0 else Color(1, 1, 1))
	if _dirty or state == S.SPAWN_WARNING or state == S.TELEGRAPH:
		_dirty = false
		queue_redraw()


func _draw() -> void:
	if state == S.DEAD:
		return
	if state == S.SPAWN_WARNING:
		var k := clampf(t_state / warn_total, 0.0, 1.0)
		var r := radius + 14.0
		draw_circle(Vector2.ZERO, r, Color(1.0, 0.4, 0.1, 0.12 + 0.2 * k))
		draw_arc(Vector2.ZERO, r, 0.0, TAU * k, 28, Color(1.0, 0.55, 0.15, 0.95), 4.0)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 28, Color(1.0, 0.55, 0.15, 0.4), 2.0)
		return
	# тень
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(Vector2(cos(a) * radius * 1.4, sin(a) * radius * 0.55))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.28))
	_draw_telegraph()
	_draw_elite_marker()
	if hp < max_hp - 0.01:
		var w := maxf(radius * 2.2, 30.0)
		var y := -radius * 2.6 - 22.0
		draw_rect(Rect2(-w * 0.5, y, w, 5), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(-w * 0.5, y, w * clampf(hp / max_hp, 0.0, 1.0), 5), Color(0.9, 0.35, 0.2))


func _draw_telegraph() -> void:
	if state != S.TELEGRAPH:
		return
	var k := clampf(t_state / maxf(telegraph_total, 0.01), 0.0, 1.0)
	var fill := Color(1.0, 0.35, 0.1, 0.12 + 0.22 * k)
	var edge := Color(1.0, 0.6, 0.15, 0.95)
	match role:
		"melee", "carrier":
			var r: float = float(def.melee_range) + 12.0
			var c := lock_dir * 6.0
			draw_circle(c, r, Color(fill.r, fill.g, fill.b, 0.12))
			draw_circle(c, r * k, fill)
			draw_arc(c, r, 0.0, TAU, 28, edge, 3.0)
		"area_melee":
			var ar := float(def.area_radius)
			var c2 := lock_pos - position
			draw_circle(c2, ar, Color(fill.r, fill.g, fill.b, 0.12))
			draw_circle(c2, ar * k, fill)
			draw_arc(c2, ar, 0.0, TAU, 40, edge, 4.0)
		"charge":
			var tw: float = game.arena.raycast_walls(position, position + lock_dir * float(def.charge_max_distance), radius)
			var full: float = float(def.charge_max_distance) * (tw if tw >= 0.0 else 1.0)
			var perp := Vector2(-lock_dir.y, lock_dir.x) * radius
			var a := perp
			var b := lock_dir * full + perp
			var c3 := lock_dir * full - perp
			var d := -perp
			draw_colored_polygon(PackedVector2Array([a, b, c3, d]), Color(fill.r, fill.g, fill.b, 0.12 + 0.16 * k))
			var fp := lock_dir * full * k
			draw_colored_polygon(PackedVector2Array([a, a + fp, d + fp, d]), fill)
			draw_polyline(PackedVector2Array([a, b, c3, d, a]), edge if locked else Color(1.0, 0.8, 0.3, 0.9), 3.0)
		"ranged":
			var target_l: Vector2 = (lock_pos if locked else game.player.position) - position
			var aim := target_l.normalized()
			var lenv: float = minf(target_l.length(), 700.0)
			draw_line(aim * radius, aim * lenv, edge if locked else Color(1.0, 0.8, 0.3, 0.55), 3.0 if locked else 2.0)
			if int(def.get("burst_count", 1)) == 1:
				draw_arc(target_l, 22.0, 0.0, TAU, 20, edge, 3.0)
				draw_circle(target_l, 22.0 * k, fill)
			else:
				draw_circle(aim * lenv, 8.0 + 4.0 * k, Color(1.0, 0.5, 0.15, 0.8))


func _draw_elite_marker() -> void:
	if elite_trait == "":
		return
	var col := Color(1.0, 0.8, 0.2)
	var top := Vector2(0, -radius * 2.6 - 38.0)
	match elite_trait:
		"swift": col = Color(0.4, 0.9, 1.0)
		"sturdy": col = Color(1.0, 0.75, 0.25)
		"unstable": col = Color(1.0, 0.3, 0.2)
	draw_arc(Vector2.ZERO, radius + 9.0, 0.0, TAU, 24, col, 3.0)       # контур под ногами
	var poly := PackedVector2Array([top + Vector2(0, -9), top + Vector2(8, 0), top + Vector2(0, 9), top + Vector2(-8, 0)])
	draw_colored_polygon(poly, col)
	draw_polyline(PackedVector2Array([poly[0], poly[1], poly[2], poly[3], poly[0]]), Color(0, 0, 0, 0.8), 1.5)
