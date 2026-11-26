class_name ArenaModel
extends RefCounted
## Геометрия арены без узлов сцены: стены-прямоугольники, вода, навигационная
## сетка, лучи/коллизии. Коллизия задаётся данными раскладки, а не рисунком.

const CELL := 32.0
const NAV_MARGIN := 24.0          # центр ячейки обязан быть дальше от стен (хватает громиле/герою)

var layout: Dictionary = {}
var size := Vector2(1600, 1000)
var start := Vector2(800, 500)
var walls: Array[Rect2] = []
var wall_kinds: Array[String] = []
var water: Array[Rect2] = []
var hazard_slots: Array = []
var nav: AStarGrid2D
var grid_w := 0
var grid_h := 0
var _free_cells: Array[Vector2i] = []
var _blocked_extra: Array = []     # временные запреты (для проверок)


static func from_layout(layout_id: String) -> ArenaModel:
	GameData.ensure()
	var m := ArenaModel.new()
	m.load_layout(GameData.layouts[layout_id])
	return m


func load_layout(l: Dictionary) -> void:
	layout = l
	size = Vector2(l.size[0], l.size[1])
	start = Vector2(l.start[0], l.start[1])
	walls.clear(); wall_kinds.clear(); water.clear()
	for w in l.walls:
		walls.append(Rect2(w.x, w.y, w.w, w.h))
		wall_kinds.append(str(w.get("kind", "block")))
	for w in l.get("water", []):
		water.append(Rect2(w.x, w.y, w.w, w.h))
	hazard_slots = l.get("hazard_slots", [])
	build_nav()


func build_nav(extra_blocked_circles: Array = []) -> void:
	grid_w = int(ceil(size.x / CELL))
	grid_h = int(ceil(size.y / CELL))
	nav = AStarGrid2D.new()
	nav.region = Rect2i(0, 0, grid_w, grid_h)
	nav.cell_size = Vector2(CELL, CELL)
	nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	nav.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	nav.update()
	_free_cells.clear()
	for y in grid_h:
		for x in grid_w:
			var c := cell_center(Vector2i(x, y))
			var solid := not is_point_free(c, NAV_MARGIN)
			if not solid:
				for bc in extra_blocked_circles:
					if c.distance_to(Vector2(bc.x, bc.y)) < float(bc.r) + 10.0:
						solid = true
						break
			nav.set_point_solid(Vector2i(x, y), solid)
			if not solid:
				_free_cells.append(Vector2i(x, y))


func cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL, (c.y + 0.5) * CELL)


func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x / CELL), 0, grid_w - 1), clampi(int(p.y / CELL), 0, grid_h - 1))


func is_point_free(p: Vector2, margin: float) -> bool:
	if p.x < margin or p.y < margin or p.x > size.x - margin or p.y > size.y - margin:
		return false
	for r in walls:
		if _circle_hits_rect(p, margin, r):
			return false
	return true


static func _circle_hits_rect(c: Vector2, rad: float, r: Rect2) -> bool:
	var q := Vector2(clampf(c.x, r.position.x, r.end.x), clampf(c.y, r.position.y, r.end.y))
	return c.distance_squared_to(q) < rad * rad


## Нужна ли точка нава: ближайшая свободная ячейка к позиции.
func nearest_free_cell(p: Vector2) -> Vector2i:
	var c := world_to_cell(p)
	if not nav.is_point_solid(c):
		return c
	var best := c
	var bd := 1e18
	for fc in _free_cells:
		var d := cell_center(fc).distance_squared_to(p)
		if d < bd:
			bd = d
			best = fc
	return best


func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var a := nearest_free_cell(from)
	var b := nearest_free_cell(to)
	var ids := nav.get_id_path(a, b)
	var out := PackedVector2Array()
	for i in ids.size():
		out.append(cell_center(Vector2i(ids[i])))
	return out


## Все свободные ячейки, достижимые из start, одной связной компонентой?
func connectivity_ratio(from: Vector2) -> float:
	if _free_cells.is_empty():
		return 0.0
	var s := nearest_free_cell(from)
	var seen := {}
	var stack: Array[Vector2i] = [s]
	seen[s] = true
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= grid_w or n.y >= grid_h:
				continue
			if seen.has(n) or nav.is_point_solid(n):
				continue
			seen[n] = true
			stack.append(n)
	return float(seen.size()) / float(_free_cells.size())


func free_cell_count() -> int:
	return _free_cells.size()


func free_cells() -> Array[Vector2i]:
	return _free_cells


# ---- лучи и коллизии --------------------------------------------------------
## Пересекает ли отрезок прямоугольник (метод slab). Возвращает t∈[0,1] или -1.
static func segment_rect_t(a: Vector2, b: Vector2, r: Rect2) -> float:
	var d := b - a
	var tmin := 0.0
	var tmax := 1.0
	for axis in 2:
		var da: float = d[axis]
		var aa: float = a[axis]
		var lo: float = r.position[axis]
		var hi: float = r.end[axis]
		if absf(da) < 1e-9:
			if aa < lo or aa > hi:
				return -1.0
		else:
			var t1 := (lo - aa) / da
			var t2 := (hi - aa) / da
			if t1 > t2:
				var tmp := t1
				t1 = t2
				t2 = tmp
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return -1.0
	return tmin


## Первое пересечение отрезка со стенами → t (0..1) или -1. margin расширяет стены.
func raycast_walls(a: Vector2, b: Vector2, margin: float = 0.0) -> float:
	var best := -1.0
	for r in walls:
		var rr := r.grow(margin) if margin > 0.0 else r
		var t := segment_rect_t(a, b, rr)
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	# границы арены
	if b.x < 0 or b.y < 0 or b.x > size.x or b.y > size.y:
		var bt := _segment_bounds_t(a, b)
		if bt >= 0.0 and (best < 0.0 or bt < best):
			best = bt
	return best


func _segment_bounds_t(a: Vector2, b: Vector2) -> float:
	var d := b - a
	var best := 2.0
	if d.x < 0 and b.x < 0:
		best = minf(best, (0 - a.x) / d.x)
	if d.x > 0 and b.x > size.x:
		best = minf(best, (size.x - a.x) / d.x)
	if d.y < 0 and b.y < 0:
		best = minf(best, (0 - a.y) / d.y)
	if d.y > 0 and b.y > size.y:
		best = minf(best, (size.y - a.y) / d.y)
	return best if best <= 1.0 else -1.0


func line_of_sight(a: Vector2, b: Vector2) -> bool:
	for r in walls:
		if segment_rect_t(a, b, r) >= 0.0:
			return false
	return true


## Выталкивание круга из стен и границ. Возвращает новую позицию и признак касания.
func resolve_circle(p: Vector2, rad: float) -> Dictionary:
	var pos := p
	var hit := false
	pos.x = clampf(pos.x, rad, size.x - rad)
	pos.y = clampf(pos.y, rad, size.y - rad)
	if pos != p:
		hit = true
	for _i in 2:
		for r in walls:
			var q := Vector2(clampf(pos.x, r.position.x, r.end.x), clampf(pos.y, r.position.y, r.end.y))
			var diff := pos - q
			var d2 := diff.length_squared()
			if d2 < rad * rad:
				hit = true
				if d2 > 1e-6:
					var dl := sqrt(d2)
					pos += diff / dl * (rad - dl)
				else:
					# центр внутри прямоугольника: выталкиваем по ближайшей грани
					var dl2 := pos.x - r.position.x
					var dr := r.end.x - pos.x
					var dt := pos.y - r.position.y
					var db := r.end.y - pos.y
					var m := minf(minf(dl2, dr), minf(dt, db))
					if m == dl2:
						pos.x = r.position.x - rad
					elif m == dr:
						pos.x = r.end.x + rad
					elif m == dt:
						pos.y = r.position.y - rad
					else:
						pos.y = r.end.y + rad
	return {"pos": pos, "hit": hit}


func in_water(p: Vector2) -> bool:
	for w in water:
		if w.has_point(p):
			return true
	return false


## Круг пересекает стену?
func circle_blocked(p: Vector2, rad: float) -> bool:
	return not is_point_free(p, rad)
