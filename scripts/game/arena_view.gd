class_name ArenaView
extends Node2D
## Пол, вода и границы арены. Одна текстура на пол (бесшовная, 512×512, через AssetRegistry).

var model: ArenaModel
var floor_id := "floor.sawmill"
var tint := Color(1, 1, 1)
var _tex: Texture2D
var _marks: Array = []


func setup(m: ArenaModel, location_id: String, p_tint: Color, seed_v: int) -> void:
	model = m
	floor_id = "floor." + location_id
	tint = p_tint
	_tex = AssetRegistry.get_texture(floor_id)
	z_index = -20
	_marks.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for i in 70:
		_marks.append([Vector2(rng.randf_range(20, m.size.x - 20), rng.randf_range(20, m.size.y - 20)), rng.randf_range(10, 40), rng.randf_range(0, TAU)])
	queue_redraw()


func _draw() -> void:
	if model == null:
		return
	var sz := model.size
	var ts := _tex.get_size()
	var y := 0.0
	while y < sz.y:
		var x := 0.0
		while x < sz.x:
			var w := minf(ts.x, sz.x - x)
			var h := minf(ts.y, sz.y - y)
			draw_texture_rect_region(_tex, Rect2(x, y, w, h), Rect2(0, 0, w, h), tint)
			x += ts.x
		y += ts.y
	# мелкие пятна/трещины — только для разнообразия, без собственного света
	for m in _marks:
		var p: Vector2 = m[0]
		var l: float = m[1]
		var a: float = m[2]
		draw_line(p, p + Vector2(cos(a), sin(a)) * l, Color(0, 0, 0, 0.12), 2.0)
	for w in model.water:
		draw_rect(w, Color(0.16, 0.3, 0.34, 0.62))
		draw_rect(w, Color(0.45, 0.65, 0.7, 0.55), false, 3.0)
		var yy := w.position.y + 18.0
		while yy < w.end.y - 6.0:
			draw_line(Vector2(w.position.x + 14, yy), Vector2(w.end.x - 14, yy), Color(0.6, 0.8, 0.85, 0.16), 2.0)
			yy += 26.0
	# граница арены
	var b := 60.0
	var dark := Color(0.04, 0.045, 0.04, 1)
	draw_rect(Rect2(-b, -b, sz.x + b * 2, b), dark)
	draw_rect(Rect2(-b, sz.y, sz.x + b * 2, b), dark)
	draw_rect(Rect2(-b, 0, b, sz.y), dark)
	draw_rect(Rect2(sz.x, 0, b, sz.y), dark)
	draw_rect(Rect2(0, 0, sz.x, sz.y), Color(0.7, 0.6, 0.4, 0.55), false, 4.0)
