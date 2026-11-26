class_name Boss
extends Enemy
## Боссы: Секач, Котельщик, Матка. Каждая атака — отдельное действие из данных с
## телеграфом, фиксацией и восстановлением. Множители волны применяются один раз.
## Подкрепления ограничены (живых ≤ 8, конечный бюджет на фазу). Ни одна атака не
## закрывает всю арену: окна уклонения гарантируют слоты/углы и лимиты.

var bdef: Dictionary = {}
var phase := 1
var action_t := 1.6
var cur: Dictionary = {}
var last_attack := ""
var summon_budget := 0
var my_summons: Array = []
var charge_cur_dir := Vector2.RIGHT
var _fired := false
var _tele_dir := Vector2.RIGHT


func setup_boss(g, boss_id: String, p_gw: int, pos: Vector2) -> void:
	game = g
	id = boss_id
	bdef = GameData.bosses[boss_id]
	def = bdef
	role = "boss"
	is_boss = true
	position = pos
	max_hp = float(bdef.base_hp) * WaveMath.hp_mult(p_gw)      # множитель — один раз, не через обычный спавнер
	hp = max_hp
	dmg = float(bdef.base_damage) * WaveMath.damage_mult(p_gw)
	speed = float(bdef.move_speed)
	radius = float(bdef.hit_radius)
	warn_total = float(GameData.B.waves.spawn_warning_seconds)
	summon_budget = int(bdef.summon_total_threat_budget_per_phase)
	path_interval = 0.3
	stuck_ref = pos
	_build_sprite()
	action_t = 1.8


func _attack_def(aid: String) -> Dictionary:
	for a in bdef.attacks:
		if a.id == aid:
			return a
	return {}


func _check_stuck(_dt: float) -> void:
	pass                       # босса не перемещаем автоматически


func _summons_alive() -> int:
	my_summons = my_summons.filter(func(e): return is_instance_valid(e) and e.state != Enemy.S.DEAD)
	return my_summons.size()


func _check_phase() -> void:
	if phase == 1 and hp <= max_hp * float(bdef.phase_two_hp_fraction):
		phase = 2
		summon_budget = int(bdef.summon_total_threat_budget_per_phase)      # новый конечный бюджет фазы
		game.fx.flash(position, Color(1.0, 0.5, 0.2), radius + 30.0)


func take_damage(amount: float, crit: bool, source: String) -> void:
	super.take_damage(amount, crit, source)
	if state != Enemy.S.DEAD:
		_check_phase()


# ---- выбор атаки --------------------------------------------------------------
func _valid(a: Dictionary) -> bool:
	var h: HazardLayer = game.hazards
	match a.id:
		"call_runners":
			var cost := int(GameData.enemies[a.enemy_id].threat_cost)
			return summon_budget >= cost and _summons_alive() < int(bdef.summon_alive_cap)
		"steam":
			return game.projectiles.enemy_count == 0 and h.count_tag("boss_steam") == 0 and h.count() <= h.cap - int(a.max_active_zones)
		"fan":
			return h.count_tag("boss_steam") == 0 and game.projectiles.enemy_room() >= int(a.projectiles) + 4
		"triple_marks":
			return h.count() <= h.cap - int(a.count) - 1
		"acid":
			return h.count() < h.cap
		"sweep", "repulse":
			return h.has_room()
	return true


func _choose_attack() -> Dictionary:
	var pl = game.player
	var dist := position.distance_to(pl.position)
	var cands: Array = []
	var ws: Array = []
	for a in bdef.attacks:
		if a.id == last_attack and bdef.attacks.size() > 1:
			continue              # не повторяем подряд
		if not _valid(a):
			continue
		var w := 1.0
		match a.id:
			"sweep", "repulse": w = 3.0 if dist < 230.0 else 0.4
			"charge": w = 2.5 if dist > 200.0 else 1.0
			"call_runners": w = 1.2
			"triple_marks", "fan": w = 2.0
			"acid": w = 2.0
			"steam": w = 1.5
		cands.append(a)
		ws.append(w)
	if cands.is_empty():
		return {}
	return cands[ShopService._pick_weighted(game.rng_combat, ws)]


# ---- состояния ------------------------------------------------------------------
func _tick_move(dt: float) -> void:
	var pl = game.player
	if pl.dead:
		vel = Vector2.ZERO
		return
	var dist := position.distance_to(pl.position)
	var keep := 130.0 if id == "cleaver" else 260.0
	if dist > keep + 60.0 or not game.arena.line_of_sight(position, pl.position):
		_goto(pl.position, dt)
	elif dist < keep - 70.0 and id != "cleaver":
		_retreat(pl.position, dt, 0.8)
	else:
		vel = Vector2.ZERO
	action_t -= dt
	if action_t <= 0.0:
		if not game.coord.request_boss(self):
			action_t = 0.3
			return
		var a := _choose_attack()
		if a.is_empty():
			game.coord.release_boss(self)
			action_t = 0.4
			return
		_begin_attack(a)


func _begin_attack(a: Dictionary) -> void:
	var pl = game.player
	cur = a
	last_attack = a.id
	_set_state(Enemy.S.TELEGRAPH)
	telegraph_total = float(a.telegraph_seconds)          # телеграфы не сокращаются во второй фазе
	recovery_total = float(a.recovery_seconds) * (0.8 if phase == 2 else 1.0)
	locked = false
	_fired = false
	hit_applied = false
	vel = Vector2.ZERO
	lock_dir = (pl.position - position).normalized()
	face = lock_dir
	_tele_dir = lock_dir
	var dm := dmg
	var h: HazardLayer = game.hazards
	match a.id:
		"sweep":
			h.add({"shape": "cone", "pos": position, "dir": lock_dir, "radius": float(a.radius), "arc": float(a.cone_degrees), "delay": telegraph_total, "life": 0.25, "damage": dm * float(a.damage_multiplier), "once": true, "palette": "enemy", "source": id, "tag": "boss_attack"})
		"repulse":
			h.add({"shape": "circle", "pos": position, "radius": float(a.radius), "delay": telegraph_total, "life": 0.25, "damage": dm * float(a.damage_multiplier), "once": true, "palette": "enemy", "source": id, "knock": 140.0, "tag": "boss_attack"})
		"triple_marks":
			var pts := _mark_points(int(a.count), float(a.radius))
			for p in pts:
				h.add({"shape": "circle", "pos": p, "radius": float(a.radius), "delay": telegraph_total, "life": 0.25, "damage": dm * float(a.damage_multiplier), "once": true, "palette": "enemy", "source": id, "tag": "boss_attack"})
		"steam":
			_spawn_steam(a)
		"acid":
			_spawn_acid(a)


func _mark_points(n: int, r: float) -> Array:
	var pl = game.player
	var pts: Array = [pl.position]
	var guard := 0
	while pts.size() < n and guard < 40:
		guard += 1
		var c: Vector2 = pl.position + Vector2.from_angle(game.rng_combat.randf() * TAU) * game.rng_combat.randf_range(110.0, 190.0)
		c.x = clampf(c.x, 40.0, game.arena.size.x - 40.0)
		c.y = clampf(c.y, 40.0, game.arena.size.y - 40.0)
		var ok := true
		for p in pts:
			if p.distance_to(c) < r * 1.6:
				ok = false
		if ok:
			pts.append(c)
	return pts


func _spawn_steam(a: Dictionary) -> void:
	var slots: Array = game.arena.hazard_slots
	var cands: Array = []
	for s in slots:
		var c := Vector2(s.x, s.y)
		if c.distance_to(game.player.position) > 140.0:
			cands.append(c)
	var n := mini(int(a.max_active_zones), cands.size())
	for i in n:
		var idx: int = game.rng_combat.randi() % cands.size()
		var c2: Vector2 = cands[idx]
		cands.remove_at(idx)
		game.hazards.add({"shape": "circle", "pos": c2, "radius": 80.0, "delay": telegraph_total, "life": float(a.zone_duration_seconds), "damage": dmg * float(a.damage_multiplier), "tick": 0.5, "palette": "steam", "source": id, "hits_enemies": true, "enemy_damage": 4.0, "tag": "boss_steam"})


func _spawn_acid(a: Dictionary) -> void:
	var h: HazardLayer = game.hazards
	while h.count_tag("acid") >= int(a.max_active_pools):
		for i in h.items.size():
			if h.items[i].get("tag", "") == "acid":
				h.items.remove_at(i)       # старые лужи исчезают
				break
	var pos: Vector2 = game.player.position + Vector2.from_angle(game.rng_combat.randf() * TAU) * game.rng_combat.randf_range(0.0, 60.0)
	pos.x = clampf(pos.x, 40.0, game.arena.size.x - 40.0)
	pos.y = clampf(pos.y, 40.0, game.arena.size.y - 40.0)
	h.add({"shape": "circle", "pos": pos, "radius": float(a.radius), "delay": telegraph_total, "life": float(a.duration_seconds), "damage": dmg * float(a.damage_multiplier), "tick": float(a.tick_seconds), "palette": "acid", "source": id, "tag": "acid"})


func _tick_telegraph(dt: float) -> void:
	var pl = game.player
	vel = Vector2.ZERO
	if pl.dead:
		_finish_attack()
		return
	if cur.id == "charge" or cur.id == "fan":
		if not locked:
			lock_dir = (pl.position - position).normalized()
			face = lock_dir
			_tele_dir = lock_dir
			if t_state >= telegraph_total - 0.3:
				locked = true
	if t_state >= telegraph_total:
		_set_state(Enemy.S.ATTACK)
		_fired = false
		charge_travel = 0.0


func _tick_attack(dt: float) -> void:
	match cur.id:
		"charge":
			_boss_charge(dt)
		"fan":
			_fire_fan()
			_finish_attack()
		"call_runners":
			_call_runners()
			_finish_attack()
		_:
			_finish_attack()      # sweep / marks / repulse / steam / acid — поля уже работают в HazardLayer


func _finish_attack() -> void:
	game.coord.release_boss(self)
	action_t = (0.5 if phase == 2 else float(bdef.minimum_gap_between_actions_seconds))
	_set_state(Enemy.S.RECOVERY)


func _boss_charge(dt: float) -> void:
	var pl = game.player
	var step := lock_dir * float(cur.speed) * dt
	var wall_hit := false
	var tw: float = game.arena.raycast_walls(position, position + step, radius)
	if tw >= 0.0:
		step *= tw
		wall_hit = true
	var res: Dictionary = game.arena.resolve_circle(position + step, radius)
	if res.hit:
		wall_hit = true
	position = res.pos
	vel = step / maxf(dt, 0.0001)
	charge_travel += step.length()
	if not hit_applied and not pl.dead and position.distance_to(pl.position) <= radius + pl.radius:
		hit_applied = true
		pl.take_damage(dmg * float(cur.damage_multiplier), id, false)
	if wall_hit or charge_travel >= float(cur.max_distance):
		vel = Vector2.ZERO
		_finish_attack()          # после рывка — окно для стрельбы


func _fire_fan() -> void:
	var n := int(cur.projectiles)
	var cone := float(cur.cone_degrees)
	var spd := float(cur.projectile_speed) * WaveMath.projectile_speed_mult(game.gw)
	for i in n:
		var t := (float(i) / float(n - 1) - 0.5) * cone if n > 1 else 0.0
		var d := lock_dir.rotated(deg_to_rad(t))
		game.projectiles.spawn(false, position + d * (radius + 8.0), d, spd, dmg * float(cur.damage_multiplier), 1100.0, 9.0, "orb", 0, false, -1.0, id)


func _call_runners() -> void:
	var eid := str(cur.enemy_id)
	var cost := int(GameData.enemies[eid].threat_cost)
	var n := int(cur.count)
	for i in n:
		if summon_budget < cost or _summons_alive() >= int(bdef.summon_alive_cap):
			break
		var e: Enemy = game.spawn_summon(eid, position)
		if e != null:
			my_summons.append(e)
			summon_budget -= cost


# ---- визуал ----------------------------------------------------------------------
func _draw_telegraph() -> void:
	if state != Enemy.S.TELEGRAPH:
		return
	var k := clampf(t_state / maxf(telegraph_total, 0.01), 0.0, 1.0)
	var fill := Color(1.0, 0.35, 0.1, 0.12 + 0.22 * k)
	var edge := Color(1.0, 0.6, 0.15, 0.95)
	match cur.id:
		"charge":
			var tw: float = game.arena.raycast_walls(position, position + lock_dir * float(cur.max_distance), radius)
			var full: float = float(cur.max_distance) * (tw if tw >= 0.0 else 1.0)
			var perp := Vector2(-lock_dir.y, lock_dir.x) * radius
			var a := perp
			var b := lock_dir * full + perp
			var c3 := lock_dir * full - perp
			var d := -perp
			draw_colored_polygon(PackedVector2Array([a, b, c3, d]), Color(fill.r, fill.g, fill.b, 0.12 + 0.16 * k))
			var fp := lock_dir * full * k
			draw_colored_polygon(PackedVector2Array([a, a + fp, d + fp, d]), fill)
			draw_polyline(PackedVector2Array([a, b, c3, d, a]), edge if locked else Color(1.0, 0.8, 0.3, 0.9), 3.0)
		"fan":
			var cone := float(cur.cone_degrees)
			var pts := PackedVector2Array([Vector2.ZERO])
			for i in 21:
				var an := _tele_dir.angle() + deg_to_rad((float(i) / 20.0 - 0.5) * cone)
				pts.append(Vector2(cos(an), sin(an)) * 520.0)
			draw_colored_polygon(pts, Color(fill.r, fill.g, fill.b, 0.10 + 0.12 * k))
			var n := int(cur.projectiles)
			for i in n:
				var t := (float(i) / float(n - 1) - 0.5) * cone
				var dd := _tele_dir.rotated(deg_to_rad(t))
				draw_line(dd * radius, dd * 520.0, edge if locked else Color(1.0, 0.8, 0.3, 0.6), 2.0)
		"call_runners":
			draw_arc(Vector2.ZERO, radius + 12.0 + 20.0 * k, 0.0, TAU, 32, edge, 3.0)
