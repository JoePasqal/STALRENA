class_name ProjectileManager
extends Node2D
## Все снаряды: пул объектов, непрерывная проверка отрезком (быстрая пуля не
## перескакивает тонкую стену), лимиты 180/120, отрисовка одним _draw.

const HEIGHT := 40.0              # визуальный подъём снаряда над «полом» (проекция сверху под углом)

class Proj:
	var active := false
	var friendly := true
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var damage := 0.0
	var radius := 3.0
	var max_dist := 500.0
	var traveled := 0.0
	var pierce := 0
	var crit := false
	var hit_ids := {}
	var kind := "bullet"
	var stop_at := -1.0
	var source_id := ""
	var ttl := 0.0

var game
var _pool: Array = []
var _active: Array = []
var player_count := 0
var enemy_count := 0
var cap_player := 180
var cap_enemy := 120
var hits_landed := 0


func configure(g) -> void:
	game = g
	var c: Dictionary = GameData.B.combat_coordinator
	cap_player = int(c.player_projectile_cap)
	cap_enemy = int(c.enemy_projectile_cap)
	z_index = 20


func clear_all() -> void:
	for p in _active:
		p.active = false
		_pool.append(p)
	_active.clear()
	player_count = 0
	enemy_count = 0
	queue_redraw()


func clear_enemy() -> void:
	var keep: Array = []
	for p in _active:
		if p.friendly:
			keep.append(p)
		else:
			p.active = false
			_pool.append(p)
	_active = keep
	enemy_count = 0
	queue_redraw()


func enemy_room() -> int:
	return cap_enemy - enemy_count


func spawn(friendly: bool, pos: Vector2, dir: Vector2, speed: float, damage: float, max_dist: float, radius: float, kind: String, pierce: int = 0, crit: bool = false, stop_at: float = -1.0, source_id: String = "") -> bool:
	if friendly and player_count >= cap_player:
		return false
	if not friendly and enemy_count >= cap_enemy:
		return false
	var p: Proj = _pool.pop_back() if not _pool.is_empty() else Proj.new()
	p.active = true
	p.friendly = friendly
	p.pos = pos
	p.vel = dir.normalized() * speed
	p.damage = damage
	p.radius = radius
	p.max_dist = max_dist
	p.traveled = 0.0
	p.pierce = pierce
	p.crit = crit
	p.hit_ids.clear()
	p.kind = kind
	p.stop_at = stop_at
	p.source_id = source_id
	_active.append(p)
	if friendly:
		player_count += 1
	else:
		enemy_count += 1
	return true


static func seg_circle_t(a: Vector2, b: Vector2, c: Vector2, r: float) -> float:
	var d := b - a
	var f := a - c
	var aa := d.dot(d)
	if aa < 1e-9:
		return 0.0 if f.length_squared() <= r * r else -1.0
	var bb := 2.0 * f.dot(d)
	var cc := f.dot(f) - r * r
	if cc <= 0.0:
		return 0.0                      # старт внутри круга
	var disc := bb * bb - 4.0 * aa * cc
	if disc < 0.0:
		return -1.0
	var sq := sqrt(disc)
	var t := (-bb - sq) / (2.0 * aa)
	if t >= 0.0 and t <= 1.0:
		return t
	return -1.0


func _release(i: int, p: Proj) -> void:
	if i >= _active.size() or _active[i] != p:
		return                           # список уже очищен (например, смерть босса во время шага)
	if p.friendly:
		player_count -= 1
	else:
		enemy_count -= 1
	p.active = false
	_pool.append(p)
	var last: Proj = _active.pop_back()
	if i < _active.size():
		_active[i] = last


func step(dt: float) -> void:
	var arena: ArenaModel = game.arena
	var i := _active.size() - 1
	while i >= 0:
		if i >= _active.size():
			i = _active.size() - 1       # список мог быть очищен внутри шага (смерть босса)
			continue
		var p: Proj = _active[i]
		var move := p.vel * dt
		var mlen := move.length()
		var remaining := p.max_dist - p.traveled
		if p.stop_at >= 0.0:
			remaining = minf(remaining, p.stop_at - p.traveled)
		var ended := false
		if mlen >= remaining:
			move = move * (remaining / maxf(mlen, 0.0001))
			mlen = remaining
			ended = true
		var np := p.pos + move
		# стены: непрерывная проверка по отрезку
		var tw := arena.raycast_walls(p.pos, np)
		var wall_hit := false
		if tw >= 0.0:
			np = p.pos + move * tw
			wall_hit = true
		if p.friendly:
			var hits: Array = []
			for e in game.enemies_along(p.pos, np, p.radius):
				if p.hit_ids.has(e.get_instance_id()) or not e.targetable():
					continue
				var t := seg_circle_t(p.pos, np, e.position, e.radius + p.radius)
				if t >= 0.0:
					hits.append([t, e])
			if hits.size() > 1:
				hits.sort_custom(func(x, y): return x[0] < y[0])
			for h in hits:
				var e2 = h[1]
				p.hit_ids[e2.get_instance_id()] = true
				e2.take_damage(p.damage, p.crit, "player")
				hits_landed += 1
				if p.pierce <= 0:
					np = p.pos + (np - p.pos) * h[0]
					ended = true
					wall_hit = false
					break
				p.pierce -= 1
		else:
			var pl = game.player
			if pl != null and not pl.dead:
				var tp := seg_circle_t(p.pos, np, pl.position, pl.radius + p.radius)
				if tp >= 0.0:
					pl.take_damage(p.damage, p.source_id, false)
					np = p.pos + (np - p.pos) * tp
					ended = true
					wall_hit = false
		p.traveled += mlen
		p.pos = np
		if wall_hit or ended or p.traveled >= p.max_dist - 0.001:
			if wall_hit and game.fx != null:
				game.fx.spark(np)
			_release(i, p)
		i -= 1
	queue_redraw()


func _draw() -> void:
	var off := Vector2(0, -HEIGHT)
	for p in _active:
		var c: Vector2 = p.pos + off
		if p.friendly:
			var tail: Vector2 = c - p.vel.normalized() * (14.0 if p.kind != "pellet" else 7.0)
			var col := Color(0.8, 0.95, 1.0, 0.95)
			if p.crit:
				col = Color(1.0, 0.95, 0.55, 1.0)
			draw_line(tail, c, col, 3.0 if p.kind != "pellet" else 2.0)
			draw_circle(c, 2.0, Color(1, 1, 1))
		else:
			match p.kind:
				"spit":
					draw_circle(c, 9.0, Color(0.1, 0.18, 0.05))
					draw_circle(c, 7.0, Color(0.55, 0.85, 0.2))
					draw_circle(c, 3.0, Color(0.85, 1.0, 0.5))
				"orb":
					draw_circle(c, 11.0, Color(0.25, 0.05, 0.02))
					draw_circle(c, 9.0, Color(1.0, 0.4, 0.1))
					draw_circle(c, 4.0, Color(1.0, 0.85, 0.5))
				_:
					draw_circle(c, 6.5, Color(0.2, 0.05, 0.02))
					draw_circle(c, 5.0, Color(1.0, 0.45, 0.15))
					draw_circle(c, 2.0, Color(1.0, 0.9, 0.6))
