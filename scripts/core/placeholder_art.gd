class_name PlaceholderArt
extends RefCounted
## Процедурные временные спрайты ТОГО ЖЕ логического размера, что и в ART_CONTRACT.md.
## Это заглушки: они заменяются файлами из manifest без изменения баланса и коллизий.

static func _ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, col: Color) -> void:
	var y0 := int(maxf(cy - ry, 0.0))
	var y1 := int(minf(cy + ry, img.get_height() - 1.0))
	for y in range(y0, y1 + 1):
		var k := 1.0 - pow((y - cy) / ry, 2.0)
		if k <= 0.0:
			continue
		var half := rx * sqrt(k)
		var x0 := int(maxf(cx - half, 0.0))
		var x1 := int(minf(cx + half, img.get_width() - 1.0))
		if x1 >= x0:
			img.fill_rect(Rect2i(x0, y, x1 - x0 + 1, 1), col)


static func _blob(img: Image, cx: float, cy: float, rx: float, ry: float, col: Color, outline: Color, w: float = 4.0) -> void:
	_ellipse(img, cx, cy, rx + w, ry + w, outline)
	_ellipse(img, cx, cy, rx, ry, col)


static func _rect(img: Image, x: float, y: float, w: float, h: float, col: Color) -> void:
	img.fill_rect(Rect2i(int(x), int(y), int(w), int(h)), col)


static func _hash_color(id: String, s: float, v: float) -> Color:
	var h := float(abs(hash(id)) % 360) / 360.0
	return Color.from_hsv(h, s, v)


## Палитра врагов: красно-оранжевые и землистые тона, герой — светлее (контраст по светлоте).
const ENEMY_STYLE := {
	"drifter": {"col": Color(0.52, 0.42, 0.36), "size": 1.0, "head": Color(0.62, 0.55, 0.45)},
	"runner": {"col": Color(0.62, 0.38, 0.24), "size": 0.85, "head": Color(0.7, 0.5, 0.35)},
	"charger": {"col": Color(0.45, 0.2, 0.16), "size": 1.25, "head": Color(0.55, 0.3, 0.25)},
	"spitter": {"col": Color(0.36, 0.5, 0.26), "size": 0.95, "head": Color(0.5, 0.65, 0.3)},
	"gunner": {"col": Color(0.3, 0.34, 0.42), "size": 1.0, "head": Color(0.2, 0.22, 0.28)},
	"brute": {"col": Color(0.4, 0.3, 0.26), "size": 1.55, "head": Color(0.5, 0.4, 0.34)},
	"flanker": {"col": Color(0.48, 0.28, 0.42), "size": 0.95, "head": Color(0.6, 0.4, 0.55)},
	"carrier": {"col": Color(0.55, 0.52, 0.22), "size": 1.35, "head": Color(0.65, 0.62, 0.3)},
}


## Актёр 256x256, ноги в (128,208). dir: S/E/N.
static func make_actor(id: String, dir: String, frame_px: int = 256) -> Image:
	var img := Image.create(frame_px, frame_px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var is_boss := id.begins_with("boss.")
	var is_hero := id == "hero.body"
	var key := id.get_slice(".", 1)
	var style: Dictionary = ENEMY_STYLE.get(key, {"col": _hash_color(id, 0.5, 0.45), "size": 1.0, "head": Color(0.6, 0.55, 0.5)})
	var col: Color = style.col
	var head_col: Color = style.head
	var size: float = style.size
	var outline := Color(0.08, 0.09, 0.08, 1)
	if is_hero:
		col = Color(0.62, 0.7, 0.6)       # светлая серо-зелёная одежда
		head_col = Color(0.78, 0.8, 0.75)
		size = 1.0
	var px := float(frame_px) / 256.0
	var cx := 128.0 * px
	var feet_y := 208.0 * px
	if is_boss:
		size = 1.0
		cx = 256.0 * px / 2.0 * 2.0 / 2.0 * 1.0
		cx = frame_px * 0.5
		feet_y = frame_px * (416.0 / 512.0)
		match key:
			"cleaver": col = Color(0.55, 0.3, 0.2)
			"boilermaster": col = Color(0.45, 0.4, 0.38)
			"broodmother": col = Color(0.35, 0.5, 0.3)
		head_col = col.lightened(0.15)
	var s := size * px * (1.5 if is_boss else 1.0)
	# тень (простой ellipse)
	_ellipse(img, cx, feet_y, 46.0 * s, 14.0 * s, Color(0, 0, 0, 0.35))
	var shoulder_w := 34.0 * s
	var body_h := 54.0 * s
	var lean := 0.0
	if dir == "E":
		shoulder_w *= 0.7
		lean = 6.0 * s
	# ноги
	_rect(img, cx - 14.0 * s + lean, feet_y - 24.0 * s, 10.0 * s, 24.0 * s, outline)
	_rect(img, cx + 4.0 * s + lean, feet_y - 24.0 * s, 10.0 * s, 24.0 * s, outline)
	_rect(img, cx - 12.0 * s + lean, feet_y - 22.0 * s, 6.0 * s, 20.0 * s, col.darkened(0.35))
	_rect(img, cx + 6.0 * s + lean, feet_y - 22.0 * s, 6.0 * s, 20.0 * s, col.darkened(0.35))
	# торс
	_blob(img, cx + lean * 0.5, feet_y - 24.0 * s - body_h * 0.5, shoulder_w, body_h * 0.62, col, outline, 3.0 * s)
	# голова
	var head_y := feet_y - 24.0 * s - body_h - 6.0 * s
	var hx := cx + lean
	if dir == "E":
		hx += 6.0 * s
	_blob(img, hx, head_y, 17.0 * s, 17.0 * s, head_col, outline, 3.0 * s)
	if dir == "S":
		_rect(img, hx - 11.0 * s, head_y - 2.0 * s, 22.0 * s, 6.0 * s, Color(0.1, 0.12, 0.1))   # маска/глаза
	elif dir == "E":
		_rect(img, hx + 2.0 * s, head_y - 3.0 * s, 13.0 * s, 6.0 * s, Color(0.1, 0.12, 0.1))
	if is_hero:
		_rect(img, cx - 24.0 * s + lean, feet_y - 24.0 * s - body_h * 0.45, 48.0 * s, 4.0 * s, Color(0.35, 0.42, 0.34))   # ремень
	if is_boss:
		_blob(img, cx, feet_y - 140.0 * px * 1.0, 60.0 * px, 30.0 * px, col.lightened(0.1), outline, 5.0 * px)
	return img


static func make_armor_overlay(id: String, dir: String) -> Image:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col := Color(0.35, 0.55, 0.65)
	var w := 30.0
	match id:
		"armor.light": col = Color(0.35, 0.6, 0.7); w = 28.0
		"armor.field": col = Color(0.5, 0.55, 0.3); w = 34.0
		"armor.heavy": col = Color(0.45, 0.4, 0.38); w = 42.0
	var cx := 128.0
	var feet := 208.0
	var outline := Color(0.08, 0.09, 0.08, 1)
	var sw := w * (0.7 if dir == "E" else 1.0)
	var y := feet - 24.0 - 27.0
	_blob(img, cx, y, sw * 0.95, 20.0, col, outline, 3.0)
	_rect(img, cx - sw - 6.0, y - 24.0, 14.0, 12.0, col.lightened(0.1))
	_rect(img, cx + sw - 8.0, y - 24.0, 14.0, 12.0, col.lightened(0.1))
	return img


## Оружие 256x128: направление вправо, хват (64,64), дуло (224,64).
static func make_weapon(id: String) -> Image:
	var img := Image.create(256, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var key := id.get_slice(".", 1)
	var outline := Color(0.06, 0.07, 0.06)
	var steel := Color(0.55, 0.58, 0.6)
	var dark := Color(0.28, 0.3, 0.32)
	var barrel_len := 160.0
	var th := 14.0
	match key:
		"pistol": barrel_len = 100.0; th = 16.0
		"smg": barrel_len = 120.0; th = 18.0
		"carbine": barrel_len = 170.0; th = 14.0
		"shotgun": barrel_len = 175.0; th = 20.0
		"lmg": barrel_len = 175.0; th = 22.0
		"marksman": barrel_len = 175.0; th = 11.0
		"flamethrower": barrel_len = 160.0; th = 26.0; steel = Color(0.7, 0.45, 0.25)
	var x0 := 64.0
	_rect(img, x0 - 3.0, 64.0 - th * 0.5 - 3.0, barrel_len + 6.0, th + 6.0, outline)
	_rect(img, x0, 64.0 - th * 0.5, barrel_len, th, steel)
	_rect(img, x0, 64.0 - th * 0.5, barrel_len * 0.45, th, dark)
	_rect(img, x0 - 3.0, 64.0 + th * 0.5 - 3.0, 26.0, 36.0, outline)
	_rect(img, x0, 64.0 + th * 0.5, 20.0, 30.0, dark)
	if key == "lmg" or key == "smg":
		_rect(img, x0 + 40.0, 64.0 + th * 0.5, 22.0, 28.0, dark.darkened(0.2))
	return img


static func make_icon(id: String) -> Image:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var outline := Color(0.06, 0.07, 0.06)
	var parts := id.split(".")
	var cat := parts[1] if parts.size() > 1 else ""
	var key := parts[2] if parts.size() > 2 else (parts[1] if parts.size() > 1 else id)
	if cat == "weapon":
		var w := make_weapon("weapon." + key)
		# вписываем боевой спрайт в иконку (отдельный 256x256, безопасное поле 16 px)
		var sub := w.get_region(Rect2i(48, 40, 190, 70))
		sub.resize(224, 83, Image.INTERPOLATE_BILINEAR)
		img.blend_rect(sub, Rect2i(0, 0, 224, 83), Vector2i(16, 86))
	elif cat == "armor":
		var col := Color(0.4, 0.6, 0.7)
		if key == "field": col = Color(0.5, 0.58, 0.3)
		elif key == "heavy": col = Color(0.5, 0.42, 0.38)
		_blob(img, 128, 128, 80, 90, col, outline, 8)
		_rect(img, 64, 70, 128, 14, col.lightened(0.2))
		_ellipse(img, 128, 140, 28, 34, col.darkened(0.25))
	elif cat == "module":
		var col2 := _hash_color(key, 0.45, 0.7)
		_blob(img, 128, 128, 74, 74, col2, outline, 8)
		for i in 8:
			var a := TAU * i / 8.0
			_ellipse(img, 128 + cos(a) * 82, 128 + sin(a) * 82, 14, 14, col2)
		_blob(img, 128, 128, 28, 28, outline.lightened(0.15), col2.lightened(0.3), 4)
	elif key == "medkit":
		_blob(img, 128, 128, 88, 70, Color(0.85, 0.88, 0.9), outline, 8)
		_rect(img, 112, 76, 32, 104, Color(0.85, 0.25, 0.2))
		_rect(img, 76, 112, 104, 32, Color(0.85, 0.25, 0.2))
	elif key == "parts":
		_blob(img, 128, 128, 60, 60, Color(0.6, 0.6, 0.62), outline, 8)
		for i in 6:
			var a2 := TAU * i / 6.0
			_ellipse(img, 128 + cos(a2) * 72, 128 + sin(a2) * 72, 18, 18, Color(0.6, 0.6, 0.62))
		_blob(img, 128, 128, 22, 22, Color(0.15, 0.16, 0.15), outline, 2)
	else:
		_blob(img, 128, 128, 90, 90, _hash_color(id, 0.4, 0.6), outline, 8)
	return img


static func make_floor(id: String) -> Image:
	var img := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	var base := Color(0.34, 0.35, 0.33)
	match id:
		"floor.sawmill": base = Color(0.37, 0.33, 0.27)
		"floor.pumping": base = Color(0.33, 0.35, 0.36)
		"floor.flooded": base = Color(0.27, 0.32, 0.26)
	img.fill(base)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	for i in 900:
		var c := base.lightened(rng.randf_range(-0.08, 0.08))
		img.fill_rect(Rect2i(rng.randi() % 510, rng.randi() % 510, 1 + rng.randi() % 4, 1 + rng.randi() % 3), c)
	return img


static func make_prop(id: String) -> Image:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_blob(img, 128, 160, 80, 56, _hash_color(id, 0.3, 0.5), Color(0.06, 0.07, 0.06), 6)
	return img


static func make_fx(id: String) -> Image:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_ellipse(img, 64, 64, 40, 22, Color(1.0, 0.8, 0.4, 0.9))
	_ellipse(img, 64, 64, 22, 12, Color(1.0, 1.0, 0.85, 1.0))
	return img
