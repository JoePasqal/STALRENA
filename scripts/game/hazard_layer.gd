class_name HazardLayer
extends Node2D
## Опасные зоны: телеграф → активная фаза. Круги, конусы, кольца. Лимит активных — из данных.
## Телеграфы чёткие (контрастный красно-оранжевый край), не только полупрозрачный дым.

var game
var items: Array = []
var cap := 8

const PALETTES := {
	"enemy": {"fill": Color(1.0, 0.35, 0.1), "edge": Color(1.0, 0.55, 0.15)},
	"steam": {"fill": Color(0.85, 0.9, 0.92), "edge": Color(1.0, 0.55, 0.15)},
	"acid": {"fill": Color(0.55, 0.9, 0.2), "edge": Color(1.0, 0.55, 0.15)},
	"electric": {"fill": Color(0.55, 0.65, 1.0), "edge": Color(1.0, 0.55, 0.15)},
	"fire": {"fill": Color(1.0, 0.45, 0.1), "edge": Color(1.0, 0.8, 0.2)},
	"toxic": {"fill": Color(0.5, 0.75, 0.25), "edge": Color(1.0, 0.55, 0.15)},
}


func configure(g) -> void:
	game = g
	cap = int(GameData.B.combat_coordinator.hazard_cap)
	z_index = 5


func clear() -> void:
	items.clear()
	queue_redraw()


func clear_tag(tag: String) -> void:
	items = items.filter(func(h): return h.get("tag", "") != tag)


func count() -> int:
	return items.size()


func count_tag(tag: String) -> int:
	var n := 0
	for h in items:
		if h.get("tag", "") == tag:
			n += 1
	return n


func has_room() -> bool:
	return items.size() < cap


## Обязательные поля: shape, pos, radius, delay, life, damage. Возвращает false при достижении лимита.
func add(h: Dictionary) -> bool:
	if items.size() >= cap:
		return false
	var d := {
		"shape": "circle", "pos": Vector2.ZERO, "dir": Vector2.RIGHT, "radius": 60.0, "arc": 360.0,
		"delay": 1.0, "life": 0.2, "damage": 10.0, "tick": 1.0, "once": false,
		"hits_player": true, "hits_enemies": false, "enemy_damage": 0.0, "palette": "enemy",
		"source": "hazard", "knock": 0.0, "tag": "", "t": 0.0, "tick_t": 0.0, "fired": false,
	}
	for k in h:
		d[k] = h[k]
	items.append(d)
	return true


func contains(h: Dictionary, p: Vector2) -> bool:
	var rel: Vector2 = p - h.pos
	var dist := rel.length()
	if dist > h.radius:
		return false
	if h.shape == "cone":
		if dist < 1.0:
			return true
		var ang := absf(rad_to_deg(rel.angle_to(h.dir)))
		return ang <= h.arc * 0.5
	return true


func step(dt: float) -> void:
	var pl = game.player
	var i := items.size() - 1
	while i >= 0:
		var h: Dictionary = items[i]
		h.t += dt
		if h.t >= h.delay:
			if not h.get("started", false):
				h["started"] = true                 # момент активации зоны
				if h.palette == "fire":
					game.fx.anim_once("fx.fire_burst", h.pos + Vector2(0, -20), float(h.radius) * 2.2 / 256.0, 10.0)
			if h.once:
				if not h.fired:
					h.fired = true
					_apply(h, pl)
			else:
				h.tick_t += dt
				while h.tick_t >= h.tick:
					h.tick_t -= h.tick
					_apply(h, pl)
		if h.t >= h.delay + h.life:
			items.remove_at(i)
		i -= 1
	queue_redraw()


func _apply(h: Dictionary, pl) -> void:
	if h.once and str(h.get("tag", "")) == "explosion":
		Sfx.play("explosion")
		game.fx.anim_once("fx.explosion", h.pos + Vector2(0, -20), float(h.radius) * 2.6 / 256.0, 14.0)

	if h.hits_player and pl != null and not pl.dead and contains(h, pl.position):
		pl.take_damage(h.damage, h.source, false)
		if h.knock > 0.0:
			var away: Vector2 = (pl.position - h.pos)
			pl.push(away.normalized() if away.length() > 1.0 else Vector2.RIGHT, h.knock)
	if h.hits_enemies and h.enemy_damage > 0.0:
		for e in game.enemies:
			if e.targetable() and contains(h, e.position):
				e.take_damage(h.enemy_damage, false, "hazard")


func _poly_for(h: Dictionary, scale_r: float = 1.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var r: float = h.radius * scale_r
	if h.shape == "cone":
		pts.append(h.pos)
		var a0: float = h.dir.angle() - deg_to_rad(h.arc * 0.5)
		var segs := 20
		for k in segs + 1:
			var a := a0 + deg_to_rad(h.arc) * float(k) / segs
			pts.append(h.pos + Vector2(cos(a), sin(a)) * r)
	else:
		var segs2 := 40
		for k in segs2:
			var a2 := TAU * float(k) / segs2
			pts.append(h.pos + Vector2(cos(a2), sin(a2)) * r)
	return pts


func _draw() -> void:
	for h in items:
		var pal: Dictionary = PALETTES.get(h.palette, PALETTES.enemy)
		var fill: Color = pal.fill
		var edge: Color = pal.edge
		if h.t < h.delay:
			var k: float = h.t / h.delay
			draw_colored_polygon(_poly_for(h), Color(fill.r, fill.g, fill.b, 0.10 + 0.14 * k))
			draw_colored_polygon(_poly_for(h, maxf(k, 0.02)), Color(fill.r, fill.g, fill.b, 0.22 + 0.2 * k))
			var pts := _poly_for(h)
			pts.append(pts[0])
			draw_polyline(pts, edge, 3.0)
		else:
			var a := 0.5
			if not h.once and (h.palette == "fire" or h.palette == "steam") and AssetRegistry.file_exists("fx.fire_loop"):
				a = 0.22   # зона читается по контуру и анимации огня/пара, а не по плоской заливке
			if h.once:
				a = 0.7 * (1.0 - clampf((h.t - h.delay) / maxf(h.life, 0.01), 0.0, 1.0))
			draw_colored_polygon(_poly_for(h), Color(fill.r, fill.g, fill.b, a))
			var pts2 := _poly_for(h)
			pts2.append(pts2[0])
			draw_polyline(pts2, edge, 3.0)
			if not h.once and (h.palette == "fire" or h.palette == "steam"):
				_draw_loop_fx(h)


## Зацикленные спрайты огня/пара поверх зоны (8 точек по кругу, разные фазы кадров).
func _draw_loop_fx(h: Dictionary) -> void:
	var id := "fx.fire_loop" if h.palette == "fire" else "fx.steam_puff"
	if not AssetRegistry.file_exists(id):
		return
	var n := 7
	var sc: float = clampf(float(h.radius) / 60.0, 0.8, 1.6) * (1.0 if h.palette == "fire" else 1.2)
	for i in n:
		var a := TAU * i / n + float(hash(h.pos)) * 0.001
		var r: float = float(h.radius) * (0.0 if i == 0 else 0.55)
		var p: Vector2 = h.pos + Vector2(cos(a), sin(a) * 0.7) * r
		var idx := int(Time.get_ticks_msec() / 90.0 + i * 2) % 6
		var fr := AssetRegistry.strip_frame(id, idx)
		var fp: Vector2 = fr.frame_px
		draw_texture_rect_region(fr.texture, Rect2(p - Vector2(fp.x * 0.5, fp.y * 0.85) * sc, fp * sc), fr.region, Color(1, 1, 1, 0.9 if h.palette == "fire" else 0.55))
