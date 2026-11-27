class_name FxLayer
extends Node2D
## Лёгкие эффекты одним _draw: сгруппированные числа урона (без сотен Label),
## искры, частицы огнемёта, вспышки. Не скрывают телеграфы.

const NUM_CAP := 36
const GROUP_WINDOW := 0.25

var numbers: Array = []           # {pos, value, t, key, crit}
var sparks: Array = []            # {pos, t}
var flames: Array = []            # {pos, vel, t, life}
var flashes: Array = []           # {pos, t, color, r}
var heals: Array = []
var motes: Array = []            # пыль/туман у камеры: {pos, vel, r, a, kind}
var muzzles: Array = []
var ambient_kind := "sawmill"           # {pos, ang, flip, t}
const MUZZLE_ANCHOR_DEFAULT := Vector2(29, 69)
const MUZZLE_SCALE := 0.3
const MUZZLE_LIFE := 0.07
var low_quality := false
var game


func _ready() -> void:
	z_index = 40


func configure(g) -> void:
	game = g
	low_quality = Settings.low_quality()


func clear() -> void:
	numbers.clear(); sparks.clear(); flames.clear(); flashes.clear(); heals.clear()
	queue_redraw()


func damage_number(pos: Vector2, value: float, key: int, crit: bool) -> void:
	for n in numbers:
		if n.key == key and n.t < GROUP_WINDOW:
			n.value += value
			n.crit = n.crit or crit
			n.t = 0.0
			return
	if numbers.size() >= NUM_CAP:
		numbers.pop_front()
	numbers.append({"pos": pos + Vector2(randf_range(-6, 6), -50), "value": value, "t": 0.0, "key": key, "crit": crit})


func spark(pos: Vector2) -> void:
	if low_quality and sparks.size() > 12:
		return
	if sparks.size() < 40:
		sparks.append({"pos": pos + Vector2(0, -ProjectileManager.HEIGHT), "t": 0.0})


## Настоящая вспышка выстрела: точка привязки к дулу из метаданных (по умолчанию (29,69)).
func muzzle(world_pos: Vector2, ang: float, flip: bool) -> void:
	if muzzles.size() < 10:
		muzzles.append({"pos": world_pos + Vector2(0, -ProjectileManager.HEIGHT), "ang": ang, "flip": flip, "t": 0.0})


func flash(pos: Vector2, color: Color, r: float = 18.0) -> void:
	if flashes.size() < 24:
		flashes.append({"pos": pos, "t": 0.0, "color": color, "r": r})


func flame_puff(pos: Vector2, dir: Vector2) -> void:
	var cap := 20 if low_quality else 60
	if flames.size() >= cap:
		return
	flames.append({"pos": pos + Vector2(0, -ProjectileManager.HEIGHT), "vel": dir * randf_range(150.0, 260.0) + Vector2(randf_range(-30, 30), randf_range(-30, 30)), "t": 0.0, "life": randf_range(0.25, 0.45)})


func step(dt: float) -> void:
	_ambient_step(dt)
	for n in numbers:
		n.t += dt
		n.pos.y -= 28.0 * dt
	numbers = numbers.filter(func(n): return n.t < 0.8)
	for s in sparks:
		s.t += dt
	sparks = sparks.filter(func(s): return s.t < 0.15)
	for f in flames:
		f.t += dt
		f.pos += f.vel * dt
	flames = flames.filter(func(f): return f.t < f.life)
	for fl in flashes:
		fl.t += dt
	flashes = flashes.filter(func(fl): return fl.t < 0.12)
	for m in muzzles:
		m.t += dt
	muzzles = muzzles.filter(func(m): return m.t < MUZZLE_LIFE)
	queue_redraw()


func _draw() -> void:
	_draw_ambient()
	for f in flames:
		var k: float = f.t / f.life
		var col := Color(1.0, 0.75 - 0.5 * k, 0.2, 0.75 * (1.0 - k))
		draw_circle(f.pos, 7.0 + 9.0 * k, col)
	for s in sparks:
		var k2: float = s.t / 0.15
		draw_circle(s.pos, 5.0 * (1.0 - k2) + 1.0, Color(1.0, 0.95, 0.7, 1.0 - k2))
	for fl in flashes:
		var k3: float = fl.t / 0.12
		draw_circle(fl.pos, fl.r * (1.0 - 0.4 * k3), Color(fl.color.r, fl.color.g, fl.color.b, 0.8 * (1.0 - k3)))
	if not muzzles.is_empty():
		var tex := AssetRegistry.get_texture("fx.muzzle")
		var anchor: Vector2 = AssetRegistry.get_muzzle_flash_anchor()
		for m in muzzles:
			var k: float = 1.0 - m.t / MUZZLE_LIFE
			var sc := MUZZLE_SCALE * (0.8 + 0.4 * k)
			draw_set_transform(m.pos, m.ang, Vector2(sc, sc * (-1.0 if m.flip else 1.0)))
			draw_texture(tex, -anchor, Color(1, 1, 1, clampf(k * 1.4, 0.0, 1.0)))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var font := ThemeDB.fallback_font
	for n in numbers:
		var a := 1.0 - clampf((n.t - 0.4) / 0.4, 0.0, 1.0)
		var txt := str(int(round(n.value)))
		var col2 := Color(1.0, 0.95, 0.5, a) if n.crit else Color(1, 1, 1, a)
		var sz := 24 if n.crit else 18
		draw_string(font, n.pos + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, sz, Color(0, 0, 0, a))
		draw_string(font, n.pos, txt, HORIZONTAL_ALIGNMENT_CENTER, -1, sz, col2)


## Лёгкая атмосфера: пылинки вокруг камеры; на Затопленном дворе — медленный туман, в Насосной — редкие клубы пара.
func _ambient_step(dt: float) -> void:
	if game == null or game.cam == null:
		return
	var cap := 0 if low_quality else 45
	var view: Rect2 = game.camera_rect().grow(120.0)
	while motes.size() < cap:
		var fog := ambient_kind == "flooded" and motes.size() % 6 == 0
		var steam := ambient_kind == "pumping" and motes.size() % 9 == 0
		var p := Vector2(randf_range(view.position.x, view.end.x), randf_range(view.position.y, view.end.y))
		motes.append({"pos": p, "vel": Vector2(randf_range(4, 14), randf_range(-6, 4)) * (0.4 if fog else 1.0), "r": randf_range(2, 4) if not (fog or steam) else randf_range(60, 110), "a": randf_range(0.10, 0.28) if not (fog or steam) else randf_range(0.03, 0.06), "fog": fog or steam})
	for m in motes:
		m.pos += m.vel * dt
	motes = motes.filter(func(m): return view.has_point(m.pos))


func _draw_ambient() -> void:
	var col := Color(1.0, 0.95, 0.8) if ambient_kind == "sawmill" else (Color(0.85, 0.92, 1.0) if ambient_kind == "pumping" else Color(0.75, 0.9, 0.75))
	for m in motes:
		draw_circle(m.pos, m.r, Color(col.r, col.g, col.b, m.a))
