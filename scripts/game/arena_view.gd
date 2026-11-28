class_name ArenaView
extends Node2D
## Пол, вода и границы арены. Одна текстура на пол (бесшовная, 512×512, через AssetRegistry).

var model: ArenaModel
var floor_id := "floor.sawmill"
var tint := Color(1, 1, 1)
var _tex: Texture2D
var _marks: Array = []
var _decals: Array = []
var _water_nodes: Array = []


func setup(m: ArenaModel, location_id: String, p_tint: Color, seed_v: int) -> void:
	model = m
	floor_id = "floor." + location_id
	tint = p_tint
	_tex = AssetRegistry.get_texture(floor_id)
	z_index = -20
	_marks.clear()
	_decals.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var area_k := m.size.x * m.size.y / 1600000.0
	for i in int(70 * area_k):
		_marks.append([Vector2(rng.randf_range(20, m.size.x - 20), rng.randf_range(20, m.size.y - 20)), rng.randf_range(10, 40), rng.randf_range(0, TAU)])
	# декали по локации (код, без файлов): пятна, трещины, камешки; опилки / масло / ил
	for i in int(95 * area_k):
		var p := Vector2(rng.randf_range(30, m.size.x - 30), rng.randf_range(30, m.size.y - 30))
		if not m.is_point_free(p, 10.0):
			continue
		var kind := rng.randi() % 4
		var col := Color(0, 0, 0, 0.14)
		match location_id:
			"sawmill": col = [Color(0.85, 0.72, 0.5, 0.20), Color(0.1, 0.07, 0.04, 0.16), Color(0.7, 0.55, 0.35, 0.16), Color(0, 0, 0, 0.12)][kind]
			"pumping": col = [Color(0.05, 0.05, 0.07, 0.25), Color(0.4, 0.3, 0.2, 0.14), Color(0.02, 0.02, 0.03, 0.22), Color(0.55, 0.55, 0.55, 0.12)][kind]
			"flooded": col = [Color(0.12, 0.16, 0.08, 0.28), Color(0.2, 0.25, 0.12, 0.2), Color(0.05, 0.08, 0.05, 0.25), Color(0.3, 0.32, 0.2, 0.14)][kind]
		_decals.append({"p": p, "rx": rng.randf_range(14, 60), "ry": rng.randf_range(8, 34), "a": rng.randf() * PI, "col": col, "crack": kind == 3 and rng.randf() < 0.6, "seed": rng.randi()})
	for c in _water_nodes:
		c.queue_free()
	_water_nodes.clear()
	if floor_id == "floor.flooded" and AssetRegistry.file_exists("water.flooded"):
		for i in m.water.size():
			var wp := WaterPatch.new()
			add_child(wp)
			wp.setup(m.water[i], seed_v + i * 31)
			_water_nodes.append(wp)
		if AssetRegistry.file_exists("prop.reeds"):
			var rd := ReedsDecor.new()
			add_child(rd)
			rd.setup(m.water, seed_v)
			_water_nodes.append(rd)
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
	for d in _decals:
		var pts := PackedVector2Array()
		for i in 18:
			var t := TAU * i / 18.0
			var q := Vector2(cos(t) * d.rx, sin(t) * d.ry).rotated(d.a)
			pts.append(d.p + q)
		draw_colored_polygon(pts, d.col)
		if d.crack:
			var cr := RandomNumberGenerator.new()
			cr.seed = d.seed
			var pos: Vector2 = d.p
			for s in 6:
				var np: Vector2 = pos + Vector2.from_angle(cr.randf() * TAU) * cr.randf_range(10, 26)
				draw_line(pos, np, Color(0, 0, 0, 0.3), 1.5)
				pos = np
	var water_art := AssetRegistry.file_exists("water.flooded")
	for w in model.water:
		if water_art:
			continue
		draw_rect(w, Color(0.16, 0.3, 0.34, 0.62))
		draw_rect(w, Color(0.45, 0.65, 0.7, 0.55), false, 3.0)
		var yy := w.position.y + 18.0
		while yy < w.end.y - 6.0:
			draw_line(Vector2(w.position.x + 14, yy), Vector2(w.end.x - 14, yy), Color(0.6, 0.8, 0.85, 0.16), 2.0)
			yy += 26.0
	# декор без коллизии: паровые клапаны у слотов опасностей (Насосная), камыш по краям воды (Двор)
	if floor_id == "floor.pumping":
		# паровые выходы: решётка в полу (вместо одиноко стоящего клапана, который «висел в воздухе»)
		for sl in model.hazard_slots:
			var c := Vector2(sl.x, sl.y)
			draw_circle(c, 30.0, Color(0.03, 0.03, 0.04, 0.55))
			draw_arc(c, 30.0, 0.0, TAU, 28, Color(0.35, 0.3, 0.25, 0.8), 3.0)
			for k in range(-2, 3):
				var hw := 24.0 * cos(asin(k * 0.18))
				draw_line(c + Vector2(-hw, k * 9.0), c + Vector2(hw, k * 9.0), Color(0.3, 0.27, 0.24, 0.8), 2.0)
	# граница арены
	var b := 60.0
	var dark := Color(0.04, 0.045, 0.04, 1)
	draw_rect(Rect2(-b, -b, sz.x + b * 2, b), dark)
	draw_rect(Rect2(-b, sz.y, sz.x + b * 2, b), dark)
	draw_rect(Rect2(-b, 0, b, sz.y), dark)
	draw_rect(Rect2(sz.x, 0, b, sz.y), dark)
	draw_rect(Rect2(0, 0, sz.x, sz.y), Color(0.7, 0.6, 0.4, 0.55), false, 4.0)
