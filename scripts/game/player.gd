class_name Player
extends Node2D
## Герой: движение, прицел (автонаведение с гистерезисом / ручной), оружие, аптечка,
## защита от многократного контакта, пассивная регенерация. Симуляция — через tick(dt).

var game
var radius := 12.0
var hp := 100.0
var max_hp := 100.0
var dead := false
var killer := ""
var vel := Vector2.ZERO
var move_input := Vector2.ZERO
var aim_input := Vector2.ZERO        # желаемое направление ручного прицела (0 — нет)
var manual_fire := false
var aim_dir := Vector2.RIGHT
var stats: Dictionary = {}
var wstats: Dictionary = {}
var weapon_def: Dictionary = {}
var ammo := 0.0
var reloading := false
var reload_left := 0.0
var cooldown := 0.0
var flame_tick := 0.0
var medkit := Medkit.new()
var contact_guard_left := 0.0
var since_damage := 99.0
var knock_vel := Vector2.ZERO
var target = null
var target_hold := 0.0
var retarget_t := 0.0
var firing := false
var hit_flash := 0.0
var walk_t := 0.0
var damage_done := 0.0

var body: Sprite2D
var armor_sprite: Sprite2D
var hands_sprite: Sprite2D      # тело поверх брони только вокруг руки/перчаток
var _hand_mat: ShaderMaterial
const HAND_MASK_RADIUS := 17.0
var weapon_sprite: Sprite2D
var _frame_key := ""
var _facing := "S"
var _anim := "idle"
var _anim_idx := 0
var _muzzle_vec := Vector2(40, 0)   # хват→дуло в мировых единицах для вправо-направленного спрайта
var death_t := 0.0
var debug_muzzle := false      # крестик в точке выхода пули (проверка хвата/дула)
const DEATH_FPS := 5.0


func setup(g, run: RunState) -> void:
	game = g
	stats = StatCalc.player_stats(run)
	max_hp = float(stats.max_hp)
	hp = max_hp                      # перед волной — полное ХП по текущему максимуму
	radius = float(stats.hit_radius)
	weapon_def = GameData.weapons[run.equipped_weapon]
	wstats = StatCalc.weapon_stats(run, run.equipped_weapon)
	ammo = float(wstats.magazine)    # полный магазин
	reloading = false
	reload_left = 0.0
	cooldown = 0.0
	medkit = Medkit.new()
	medkit.reset_for_wave(run.medkits)   # минимум одна; купленные и сохранённые переносятся
	contact_guard_left = 0.0
	since_damage = 99.0
	dead = false
	death_t = 0.0
	var wp := AssetRegistry.get_weapon_points(str(weapon_def.world_sprite_id))
	_muzzle_vec = (wp.muzzle - wp.grip) * AssetRegistry.get_scale(str(weapon_def.world_sprite_id))
	_build_visuals(run)


func _build_visuals(run: RunState) -> void:
	for c in get_children():
		c.queue_free()
	body = Sprite2D.new()
	body.centered = false
	add_child(body)
	armor_sprite = Sprite2D.new()
	armor_sprite.centered = false
	add_child(armor_sprite)
	hands_sprite = Sprite2D.new()
	hands_sprite.centered = false
	_hand_mat = ShaderMaterial.new()
	_hand_mat.shader = load("res://assets/shaders_hand_mask.gdshader")
	_hand_mat.set_shader_parameter("radius_px", HAND_MASK_RADIUS)
	hands_sprite.material = _hand_mat
	add_child(hands_sprite)
	weapon_sprite = Sprite2D.new()
	weapon_sprite.centered = false
	add_child(weapon_sprite)
	var wid := str(weapon_def.world_sprite_id)
	weapon_sprite.texture = AssetRegistry.get_texture(wid)
	weapon_sprite.offset = -AssetRegistry.get_weapon_points(wid).grip
	var ws := AssetRegistry.get_scale(wid)
	weapon_sprite.scale = Vector2(ws, ws)
	armor_sprite.visible = run.equipped_armor != ""
	_frame_key = ""
	_update_visuals(0.0)


func take_damage(amount: float, source: String, contact: bool) -> void:
	if dead or amount <= 0.0:
		return
	if contact:
		if contact_guard_left > 0.0:
			return                           # защита от многократного контакта
		contact_guard_left = float(stats.contact_guard)
	hp -= amount
	since_damage = 0.0
	hit_flash = 0.12
	killer = source
	game.on_player_hurt(amount, source)
	if hp <= 0.0:
		hp = 0.0
		dead = true
		medkit.clear_effect()                # после смерти аптечка не воскрешает


func push(dir: Vector2, strength: float) -> void:
	knock_vel += dir * strength * 6.0


func use_medkit() -> bool:
	if dead:
		return false
	var ok := medkit.try_use(hp, max_hp, BonusService.medkit_heal_mult(game.run))
	if ok:
		Sfx.play("heal")
		game.fx.flash(position, Color(0.55, 0.85, 1.0), 26.0)
	return ok


func start_reload() -> void:
	if reloading or dead:
		return
	if ammo >= float(wstats.magazine) - 0.001:
		return
	reloading = true
	reload_left = float(wstats.reload_time)
	Sfx.play("reload")


# ---- симуляция ------------------------------------------------------------
func tick(dt: float) -> void:
	if dead:
		death_t += dt
		_update_visuals(dt)
		return
	contact_guard_left = maxf(contact_guard_left - dt, 0.0)
	since_damage += dt
	hit_flash = maxf(hit_flash - dt, 0.0)
	_move(dt)
	_aim_and_fire(dt)
	# аптечка: непрерывно по накопленному времени, урон не прерывает
	var heal := medkit.tick(dt)
	if heal > 0.0:
		hp = minf(max_hp, hp + heal)
	# пассивная регенерация модуля: только в бою, после паузы без урона
	var rf := float(stats.regen_fraction)
	if rf > 0.0 and since_damage >= float(stats.regen_delay) and hp < max_hp:
		hp = minf(max_hp, hp + max_hp * rf * dt)
	_update_visuals(dt)


func _move(dt: float) -> void:
	var dir := move_input
	if dir.length() > 1.0:
		dir = dir.normalized()
	var spd: float = float(stats.move_speed)
	if game.arena.in_water(position):
		spd *= float(GameData.locations["flooded"].water_ground_move_speed_multiplier)
	vel = dir * spd
	var step := (vel + knock_vel) * dt
	knock_vel = knock_vel.move_toward(Vector2.ZERO, 900.0 * dt)
	if step.length() > 0.0:
		var np := position + step
		var res: Dictionary = game.arena.resolve_circle(np, radius)
		position = res.pos
	if vel.length() > 5.0:
		walk_t += dt * (vel.length() / float(stats.move_speed))


func _aim_and_fire(dt: float) -> void:
	cooldown = maxf(cooldown - dt, 0.0)
	if reloading:
		reload_left -= dt
		if reload_left <= 0.0:
			reloading = false
			ammo = float(wstats.magazine)
			Sfx.play("reload_done")
	var autoaim: bool = bool(Settings.data.autoaim)
	firing = false
	if manual_fire:
		if aim_input.length() > 0.1:
			aim_dir = aim_input.normalized()
		firing = true
		target = null
	elif autoaim:
		_update_target(dt)
		if target != null:
			aim_dir = (target.position - position).normalized()
			firing = true
	else:
		if aim_input.length() > 0.1:
			aim_dir = aim_input.normalized()
	if ammo <= 0.001 and not reloading:
		start_reload()                     # автоперезарядка при пустом магазине
	if firing and reloading and cooldown <= 0.0 and str(wstats.fire_mode) != "cone_ticks":
		cooldown = 0.35
		Sfx.play("empty")                      # пытаемся стрелять во время перезарядки
	if firing and not reloading and ammo > 0.001:
		if str(wstats.fire_mode) == "cone_ticks":
			_flame(dt)
		elif cooldown <= 0.0:
			_fire()
	else:
		flame_tick = 0.0


func _update_target(dt: float) -> void:
	target_hold = maxf(target_hold - dt, 0.0)
	retarget_t -= dt
	if target != null and (not is_instance_valid(target) or not target.targetable()):
		target = null
	if retarget_t > 0.0 and target != null:
		return
	retarget_t = 0.08
	var rng_limit := float(wstats.range)
	var best = null
	var best_d := 1e18
	for e in game.enemies:
		if not e.targetable():
			continue
		var d := position.distance_to(e.position)
		if d - e.radius > rng_limit:
			continue
		if d >= best_d:
			continue
		if not game.arena.line_of_sight(position, e.position):
			continue
		best_d = d
		best = e
	if best == null:
		if target != null:
			# текущую цель потеряли из виду/радиуса
			if position.distance_to(target.position) - target.radius > rng_limit or not game.arena.line_of_sight(position, target.position):
				target = null
		return
	if target == null:
		target = best
		target_hold = 0.25
		return
	if best == target:
		return
	# гистерезис: переключаемся, только если новая цель заметно ближе и задержка вышла
	var cur_d := position.distance_to(target.position)
	var cur_ok: bool = cur_d - target.radius <= rng_limit and game.arena.line_of_sight(position, target.position)
	if not cur_ok or (target_hold <= 0.0 and best_d < cur_d * 0.8 - 20.0):
		target = best
		target_hold = 0.25


## Дуло: вектор хват→дуло поворачивается вместе с оружием; слева спрайт отражён по вертикали.
func muzzle_point() -> Vector2:
	var v := _muzzle_vec
	if aim_dir.x < 0.0:
		v.y = -v.y
	return position + _hand_offset() + v.rotated(aim_dir.angle()) + Vector2(0, ProjectileManager.HEIGHT)


func _fire() -> void:
	ammo -= float(wstats.ammo_per_shot)
	cooldown = 1.0 / float(wstats.fire_rate)
	var rng: RandomNumberGenerator = game.rng_combat
	var crit := rng.randf() < float(wstats.crit_chance)   # крит — на выстрел, применяется ко всем дробинам
	var dmg := float(wstats.damage) * (float(wstats.crit_multiplier) if crit else 1.0)
	var origin := position
	var mz := muzzle_point()
	var blocked: bool = game.arena.raycast_walls(origin, mz) >= 0.0
	var spread := float(wstats.spread)
	var half := spread if str(wstats.spread_semantics) == "uniform_plus_minus" else spread * 0.5
	game.run.stats["shots"] = int(game.run.stats.get("shots", 0)) + 1
	var pellets := int(wstats.pellets)
	var kind := "pellet" if pellets > 1 else "bullet"
	for i in pellets:
		var ang := deg_to_rad(rng.randf_range(-half, half))
		var d := aim_dir.rotated(ang)
		if blocked:
			game.fx.spark(origin + aim_dir * 14.0)
			continue
		game.projectiles.spawn(true, mz, d, float(wstats.projectile_speed), dmg, float(wstats.range), 3.0, kind, int(wstats.pierce), crit)
	if AssetRegistry.file_exists("fx.muzzle"):
		game.fx.muzzle(mz, aim_dir.angle(), aim_dir.x < 0.0)
	else:
		game.fx.flash(mz + Vector2(0, -ProjectileManager.HEIGHT), Color(1.0, 0.9, 0.6), 12.0)
	Sfx.play("shot_" + str(weapon_def.id))


func _flame(dt: float) -> void:
	flame_tick += dt
	Sfx.play("flame")
	var tick_s := float(wstats.tick_seconds)
	ammo = maxf(ammo - float(wstats.fuel_per_second) * dt, 0.0)
	if randf() < 0.9:
		game.fx.flame_puff(position + aim_dir * 30.0, aim_dir)
	while flame_tick >= tick_s:
		flame_tick -= tick_s
		_flame_tick()


func _flame_tick() -> void:
	var rng: RandomNumberGenerator = game.rng_combat
	var origin := position + aim_dir * 20.0
	var half := deg_to_rad(float(wstats.spread) * 0.5)
	var rng_limit := float(wstats.range)
	game.run.stats["shots"] = int(game.run.stats.get("shots", 0)) + 0
	for e in game.enemies:
		if not e.targetable():
			continue
		var rel: Vector2 = e.position - origin
		var d := rel.length()
		if d - e.radius > rng_limit:
			continue
		var margin := atan2(e.radius, maxf(d, 1.0))
		if absf(rel.angle_to(aim_dir)) > half + margin:
			continue
		if not game.arena.line_of_sight(origin, e.position):
			continue
		var crit := rng.randf() < float(wstats.crit_chance)
		var dmg := float(wstats.damage) * (float(wstats.crit_multiplier) if crit else 1.0)
		e.take_damage(dmg, crit, "player")
		e.ignite(float(wstats.burn_dps), float(wstats.burn_duration))     # горение обновляет длительность


# ---- визуал ----------------------------------------------------------------
func _facing_name() -> String:
	if absf(aim_dir.x) > absf(aim_dir.y):
		return "E" if aim_dir.x >= 0.0 else "W"
	return "S" if aim_dir.y >= 0.0 else "N"


func _update_visuals(dt: float) -> void:
	if body == null:
		return
	_facing = _facing_name()
	var moving := vel.length() > 5.0 and not dead
	var anim := "death" if dead else ("hit" if hit_flash > 0.0 else ("walk" if moving else "idle"))
	var idx := int(walk_t * 8.0) % 4 if (moving and not dead) else 0
	if dead:
		idx = mini(int(death_t * DEATH_FPS), 3)           # последовательность смерти: 4 кадра, затем остаётся лежать
	_anim = anim
	_anim_idx = idx
	var key := "%s|%s|%d" % [anim, _facing, idx]
	var placeholder := true
	if key != _frame_key:
		_frame_key = key
		var fr := AssetRegistry.get_actor_frame("hero.body", anim, _facing, idx)
		placeholder = fr.placeholder
		_apply_frame(body, fr, "hero.body")
		armor_sprite.visible = game.run.equipped_armor != "" and not dead      # при смерти броню скрываем
		if armor_sprite.visible:
			var armor_id: String = "armor." + str(game.run.equipped_armor)
			var af := AssetRegistry.get_armor_frame(armor_id, _facing)
			_apply_frame(armor_sprite, af, armor_id)
		hands_sprite.visible = armor_sprite.visible and not placeholder
		if hands_sprite.visible:
			_apply_frame(hands_sprite, fr, "hero.body")
			var sk := AssetRegistry.get_weapon_socket(_facing, anim, idx)
			_hand_mat.set_shader_parameter("center_px", fr.region.position + sk)
	var bob := (sin(walk_t * TAU) * 1.5 if (moving and _frame_is_placeholder()) else 0.0)
	body.position.y = bob
	armor_sprite.position.y = bob
	hands_sprite.position.y = bob
	var tint := Color(1, 1, 1)
	if hit_flash > 0.0:
		tint = Color(1.6, 0.8, 0.8)
	body.modulate = tint
	armor_sprite.modulate = tint
	hands_sprite.modulate = tint
	# оружие: поворот непрерывный, тело не вращается; слой зависит от направления
	var hand := _hand_offset()
	weapon_sprite.position = hand + Vector2(0, bob)
	weapon_sprite.rotation = aim_dir.angle()
	var wsc := absf(weapon_sprite.scale.x)
	weapon_sprite.scale = Vector2(wsc, wsc * (-1.0 if aim_dir.x < 0.0 else 1.0))   # не вверх ногами слева
	weapon_sprite.z_index = -1 if _facing == "N" else 0
	weapon_sprite.visible = not dead
	queue_redraw()


func _frame_is_placeholder() -> bool:
	return not AssetRegistry.file_exists("hero.body")


func _apply_frame(spr: Sprite2D, fr: Dictionary, id: String) -> void:
	spr.texture = fr.texture
	var sc := AssetRegistry.get_scale(id)
	if fr.region.size != fr.texture.get_size():
		spr.region_enabled = true
		spr.region_rect = fr.region
	else:
		spr.region_enabled = false
	spr.offset = -fr.pivot
	spr.scale = Vector2(sc * (-1.0 if fr.flip_h else 1.0), sc)


func _hand_offset() -> Vector2:
	var f := _facing_name()
	var sock := AssetRegistry.get_weapon_socket(f, _anim, _anim_idx)
	var piv := AssetRegistry.get_pivot("hero.body")
	var off := (sock - piv) * AssetRegistry.get_scale("hero.body")
	if f == "W":
		off.x = -off.x
	return off


func _draw() -> void:
	# простая тень-эллипс; герой отделяется светлотой
	var pts := PackedVector2Array()
	for k in 24:
		var a := TAU * k / 24.0
		pts.append(Vector2(cos(a) * 20.0, sin(a) * 8.0))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.3))
	if contact_guard_left > 0.0 and not dead:
		draw_arc(Vector2.ZERO, radius + 4.0, 0.0, TAU, 20, Color(0.7, 0.9, 1.0, 0.5), 2.0)
	if debug_muzzle and not dead:
		var mp := muzzle_point() - position + Vector2(0, -ProjectileManager.HEIGHT)
		draw_line(mp + Vector2(-6, 0), mp + Vector2(6, 0), Color(1, 0, 1), 2.0)
		draw_line(mp + Vector2(0, -6), mp + Vector2(0, 6), Color(1, 0, 1), 2.0)
	# маркер цели автонаведения
	if target != null and is_instance_valid(target) and not manual_fire:
		var tp: Vector2 = target.position - position
		draw_arc(tp, target.radius + 8.0, 0.0, TAU, 20, Color(0.7, 0.9, 1.0, 0.7), 2.0)
