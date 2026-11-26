class_name BotInput
extends RefCounted
## Автопилот для автоматической проверки и замеров (tests/sim_*.gd). НЕ человек:
## держит дистанцию, уклоняется от телеграфов и пуль, использует аптечку.

var kite_dist := 240.0
var _strafe := 1.0
var _t := 0.0


func drive(game, dt: float) -> void:
	_t += dt
	var pl: Player = game.player
	var pos := pl.position
	var nearest = null
	var nd := 1e18
	for e in game.enemies:
		if not e.targetable():
			continue
		var d := pos.distance_to(e.position)
		if d < nd:
			nd = d
			nearest = e
	var move := Vector2.ZERO
	# уйти из опасных зон
	for h in game.hazards.items:
		if h.hits_player and game.hazards.contains(h, pos) or (h.hits_player and pos.distance_to(h.pos) < h.radius + 40.0):
			move += (pos - h.pos).normalized() * 2.0
	# уклонение от пуль
	for p in game.projectiles._active:
		if p.friendly:
			continue
		var rel: Vector2 = pos - p.pos
		if rel.length() < 140.0 and rel.normalized().dot(p.vel.normalized()) > 0.85:
			var side := Vector2(-p.vel.y, p.vel.x).normalized()
			move += side * (1.0 if side.dot(rel) > 0.0 else -1.0) * 2.5
	if nearest != null:
		var to: Vector2 = nearest.position - pos
		var want := kite_dist
		if nearest.is_boss:
			want = 260.0
		if nd < want - 20.0:
			move += -to.normalized() * 1.5 + Vector2(-to.y, to.x).normalized() * 0.6 * _strafe
		elif nd > want + 80.0:
			move += to.normalized()
		else:
			move += Vector2(-to.y, to.x).normalized() * 0.5 * _strafe
		if fmod(_t, 3.0) < dt:
			_strafe = -_strafe
		# не упираться в стену
		var probe := pos + move.normalized() * 50.0 if move.length() > 0.1 else pos
		if game.arena.raycast_walls(pos, probe, 14.0) >= 0.0:
			move = Vector2(-move.y, move.x) * _strafe
	else:
		move = (game.arena.start - pos).normalized() * 0.5 if pos.distance_to(game.arena.start) > 80.0 else Vector2.ZERO
	pl.move_input = move.limit_length(1.0)
	pl.manual_fire = false
	pl.aim_input = Vector2.ZERO
	if pl.hp < pl.max_hp * 0.5:
		pl.use_medkit()
