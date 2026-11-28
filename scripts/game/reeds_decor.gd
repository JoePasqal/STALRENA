class_name ReedsDecor
extends Node2D
## Кусты камыша по краю воды (поверх воды, без коллизии); положение с лёгким разбросом по семени.

var _items: Array = []


func setup(water: Array, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	_items.clear()
	for w in water:
		var r: Rect2 = w
		var n := int((r.size.x + r.size.y) / 110.0)
		for i in n:
			var t := rng.randf() * (r.size.x + r.size.y) * 2.0
			var p: Vector2
			if t < r.size.x:
				p = r.position + Vector2(t, 0)
			elif t < r.size.x + r.size.y:
				p = r.position + Vector2(r.size.x, t - r.size.x)
			elif t < r.size.x * 2.0 + r.size.y:
				p = r.position + Vector2(r.size.x * 2.0 + r.size.y - t, r.size.y)
			else:
				p = r.position + Vector2(0, (r.size.x + r.size.y) * 2.0 - t)
			p += Vector2(rng.randf_range(-24, 24), rng.randf_range(-12, 14))
			_items.append([p, rng.randf_range(0.5, 0.85), rng.randf() < 0.5])
	queue_redraw()


func _draw() -> void:
	var rt := AssetRegistry.get_texture("prop.reeds")
	var rp := AssetRegistry.get_pivot("prop.reeds")
	var base := AssetRegistry.get_scale("prop.reeds")
	for it in _items:
		var sc: float = base * float(it[1])
		var fx := -1.0 if it[2] else 1.0
		draw_set_transform(it[0], 0.0, Vector2(sc * fx, sc))
		draw_texture(rt, -rp)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
