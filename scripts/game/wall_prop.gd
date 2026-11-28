class_name WallProp
extends Node2D
## Препятствие с коллизией из данных раскладки (ArenaModel). Рисунок — только вид:
## основание + верх (y-sort по нижней грани), становится полупрозрачным, когда за ним
## находится герой/враг.

const HEIGHTS := {"logs": 42.0, "machine": 62.0, "crate": 40.0, "concrete": 52.0, "pipe": 30.0, "debris": 26.0, "block": 44.0}

var rect := Rect2()
var kind := "block"
var tint := Color(1, 1, 1)
var height := 44.0
var fade_target := 1.0


func setup(r: Rect2, k: String, t: Color) -> void:
	rect = r
	kind = k
	tint = t
	height = float(HEIGHTS.get(k, 44.0))
	position = Vector2(r.position.x + r.size.x * 0.5, r.end.y)


func _colors() -> Array:
	match kind:
		"logs": return [Color(0.52, 0.4, 0.26), Color(0.36, 0.26, 0.16)]
		"machine": return [Color(0.45, 0.5, 0.42), Color(0.28, 0.32, 0.28)]
		"crate": return [Color(0.55, 0.42, 0.28), Color(0.4, 0.29, 0.19)]
		"concrete": return [Color(0.58, 0.6, 0.58), Color(0.38, 0.4, 0.4)]
		"pipe": return [Color(0.5, 0.52, 0.55), Color(0.3, 0.32, 0.36)]
		"debris": return [Color(0.5, 0.36, 0.27), Color(0.34, 0.24, 0.18)]
	return [Color(0.52, 0.52, 0.5), Color(0.34, 0.34, 0.33)]


const PROP_FOR_KIND := {"logs": "prop.log_stack", "crate": "prop.crate", "fence": "prop.fence"}
## Несколько вариантов одного вида укрытия — чтобы мозаика не выглядела копипастой.
const VARIANTS := {
	"concrete": ["prop.concrete_block", "prop.concrete_block_b", "prop.concrete_block_c"],
	"debris": ["prop.wrecked_car", "prop.wrecked_car_b", "prop.wrecked_car_c"],
	"machine": ["prop.machine_a", "prop.machine_b"],
	"pipe": ["prop.pipe_long", "prop.pipe_long", "prop.pipe_tee"],
}
const DEPTH := {"concrete": 0.55, "debris": 0.6, "machine": 0.95, "pipe": 0.6}


func _variants_ready(k: String) -> bool:
	if not VARIANTS.has(k):
		return false
	for v in VARIANTS[k]:
		if not AssetRegistry.file_exists(v):
			return false
	return true


## Настоящий спрайт препятствия (если файл есть): только вид; коллизия остаётся прямоугольником данных.
func _draw_sprite(pid: String) -> void:
	var tex := AssetRegistry.get_texture(pid)
	var piv := AssetRegistry.get_pivot(pid)
	var base_scale := AssetRegistry.get_scale(pid)
	var cell := float(tex.get_size().x)
	var vis := cell * 0.8 * base_scale
	var n := maxi(int(ceil(rect.size.x / maxf(vis, 1.0))), 1)
	var s := minf(rect.size.x / n / (cell * 0.8), base_scale * 1.25)
	for i in n:
		var cx := -rect.size.x * 0.5 + (i + 0.5) * rect.size.x / n
		draw_set_transform(Vector2(cx, -rect.size.y * 0.35), 0.0, Vector2(s, s))
		draw_texture(tex, -piv)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Мозаика из ВАРИАНТОВ вида, покрывающая прямоугольник коллизии. Размер плитки берётся по реальной видимой рамке
## спрайта (bbox из метаданных), чтобы предмет стоял основанием на земле, а не «висел».
func _draw_pipes(vlist: Array) -> void:
	var long_id: String = vlist[0]
	var bb := AssetRegistry.bbox_px(long_id)
	var s_h := rect.size.y * 0.95 / maxf(bb.size.y, 1.0)
	var tile_w := bb.size.x * s_h
	var n := maxi(int(round(rect.size.x / tile_w)), 1)
	var fit_x := rect.size.x / n
	var seed_v := int(abs(hash(Vector2i(int(rect.position.x), int(rect.position.y)))))
	if rect.size.x < rect.size.y * 1.6:
		# короткий отрезок = тройник/стояк, стоит основанием на земле по центру
		var tid: String = vlist[vlist.size() - 1]
		var tbb := AssetRegistry.bbox_px(tid)
		var st := clampf(rect.size.x * 1.6 / maxf(tbb.size.x, 1.0), 0.3, 0.5)
		draw_set_transform(Vector2(0.0, -2.0), 0.0, Vector2(st, st))
		draw_texture(AssetRegistry.get_texture(tid), -AssetRegistry.get_pivot(tid))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	for i in n:
		var cx := -rect.size.x * 0.5 + (i + 0.5) * fit_x
		var use_tee := n >= 3 and i == (seed_v % n) and i != 0 and i != n - 1
		var vid: String = vlist[vlist.size() - 1] if use_tee else long_id
		var piv := AssetRegistry.get_pivot(vid)
		var sx := fit_x / maxf(bb.size.x, 1.0)
		var sy := s_h
		if use_tee:
			var tbb := AssetRegistry.bbox_px(vid)
			sx = fit_x * 0.9 / maxf(tbb.size.x, 1.0)
			sy = sx
		draw_set_transform(Vector2(cx, -2.0), 0.0, Vector2(sx, sy))
		draw_texture(AssetRegistry.get_texture(vid), -piv)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_variants(vlist: Array) -> void:
	if kind == "pipe":
		_draw_pipes(vlist)
		return
	var vid_first: String = vlist[0]
	var bb := AssetRegistry.bbox_px(vid_first)
	var seed_v := int(abs(hash(Vector2i(int(rect.position.x), int(rect.position.y)))))
	var depth_k: float = DEPTH.get(kind, 0.55)
	var long_kind := kind == "pipe"
	var target_w := minf(maxf(rect.size.x, rect.size.y * 0.6), 200.0) if not long_kind else rect.size.x
	var s := clampf((minf(target_w, 200.0) if not long_kind else (rect.size.x / maxi(int(ceil(rect.size.x / 190.0)), 1))) / maxf(bb.size.x, 1.0), 0.28, 1.0)
	var step_x := bb.size.x * s * 0.94
	var step_y := maxf(bb.size.y * s * depth_k, 26.0)
	var nx := maxi(int(ceil(rect.size.x / step_x)), 1)
	var ny := 1 if long_kind else maxi(int(ceil(rect.size.y / step_y)), 1)
	var fit_x := rect.size.x / nx
	for r in ny:
		var by := -rect.size.y + (r + 1) * rect.size.y / ny if not long_kind else -rect.size.y * 0.15
		for i in nx:
			var vid: String = vlist[(seed_v + r * 3 + i) % vlist.size()]
			var tex := AssetRegistry.get_texture(vid)
			var piv := AssetRegistry.get_pivot(vid)
			var cx := -rect.size.x * 0.5 + (i + 0.5) * fit_x
			draw_set_transform(Vector2(cx, by), 0.0, Vector2(s, s))
			draw_texture(tex, -piv)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Мягкая контактная тень под основанием (несколько слоёв эллипса), без длинных запечённых теней.
func _draw_shadow() -> void:
	if kind == "pipe":
		for i in 3:
			var pts_p := PackedVector2Array()
			for a in 24:
				var t := TAU * a / 24.0
				pts_p.append(Vector2(cos(t) * (rect.size.x * 0.5 + 4.0 + i * 3.0), -4.0 + sin(t) * (5.0 + i * 3.0)))
			draw_colored_polygon(pts_p, Color(0, 0, 0, 0.16))
		return
	var w := rect.size.x
	var h := rect.size.y
	for i in 4:
		var k := 1.0 + i * 0.12
		var pts := PackedVector2Array()
		for a in 28:
			var t := TAU * a / 28.0
			pts.append(Vector2(cos(t) * (w * 0.5 + 14.0) * k, -h * 0.5 + sin(t) * (h * 0.5 + 12.0) * k + 6.0))
		draw_colored_polygon(pts, Color(0, 0, 0, 0.10))


func _draw() -> void:
	_draw_shadow()
	if _variants_ready(kind):
		_draw_variants(VARIANTS[kind])
		return
	var pid: String = PROP_FOR_KIND.get(kind, "")
	if pid != "" and AssetRegistry.file_exists(pid):
		_draw_sprite(pid)
		return
	var cols := _colors()
	var top_c: Color = (cols[0] as Color) * tint
	var front_c: Color = (cols[1] as Color) * tint
	top_c.a = 1.0
	front_c.a = 1.0
	var w := rect.size.x
	var h := rect.size.y
	var outline := Color(0.05, 0.06, 0.05, 0.95)
	var front := Rect2(-w * 0.5, -height, w, height)
	var top := Rect2(-w * 0.5, -h - height, w, h)
	draw_rect(front, front_c)
	draw_rect(top, top_c)
	# детали (без запечённого света): полосы брёвен / планки / решётка
	match kind:
		"logs":
			var n := int(maxf(w / 26.0, 1.0))
			for i in n:
				var x := -w * 0.5 + (i + 0.5) * w / n
				draw_circle(Vector2(x, -height * 0.5), minf(w / n * 0.42, height * 0.42), front_c.lightened(0.12))
				draw_arc(Vector2(x, -height * 0.5), minf(w / n * 0.42, height * 0.42), 0.0, TAU, 14, outline, 1.5)
		"crate", "machine", "concrete":
			draw_line(Vector2(-w * 0.5, -height * 0.5), Vector2(w * 0.5, -height * 0.5), front_c.darkened(0.3), 2.0)
			draw_line(Vector2(0, -height), Vector2(0, 0), front_c.darkened(0.2), 2.0)
		"pipe":
			for i in 3:
				draw_line(Vector2(-w * 0.5, -height * (0.25 + 0.25 * i)), Vector2(w * 0.5, -height * (0.25 + 0.25 * i)), front_c.lightened(0.15), 3.0)
	draw_rect(front, outline, false, 2.0)
	draw_rect(top, outline, false, 2.0)


func update_fade(actors: Array, dt: float) -> void:
	var target := 1.0
	for p in actors:
		var ax: float = p.x
		var ay: float = p.y
		if ax >= rect.position.x - 22.0 and ax <= rect.end.x + 22.0 and ay >= rect.position.y - height - 8.0 and ay < rect.position.y + rect.size.y:
			target = 0.45
			break
	fade_target = target
	modulate.a = move_toward(modulate.a, fade_target, dt * 5.0)
