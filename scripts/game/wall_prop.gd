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


## Настоящий спрайт препятствия (если файл есть): только вид; коллизия остаётся прямоугольником данных.
func _draw_sprite(pid: String) -> void:
	var tex := AssetRegistry.get_texture(pid)
	var piv := AssetRegistry.get_pivot(pid)
	var base_scale := AssetRegistry.get_scale(pid)
	# видимая ширина по manifest-холсту ~ 0.8 клетки; подгоняем по ширине прямоугольника, не увеличивая сверх масштаба manifest
	var cell := float(tex.get_size().x)
	var vis := cell * 0.8 * base_scale
	var n := maxi(int(ceil(rect.size.x / maxf(vis, 1.0))), 1)
	var s := minf(rect.size.x / n / (cell * 0.8), base_scale * 1.25)
	for i in n:
		var cx := -rect.size.x * 0.5 + (i + 0.5) * rect.size.x / n
		draw_set_transform(Vector2(cx, -rect.size.y * 0.35), 0.0, Vector2(s, s))
		draw_texture(tex, -piv)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
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
