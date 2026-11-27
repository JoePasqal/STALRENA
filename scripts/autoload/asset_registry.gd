extends Node
## AssetRegistry: ID → текстура, кадры, pivot, масштаб, сокеты.
## manifest (assets/asset_manifest_v1.json) — спецификация, а не доказательство наличия файла.
## Нет файла → читаемый placeholder того же логического размера и ОДНА запись в диагностике.
## Статусы: planned → source_received → prepared → integrated → verified.
## Здесь для найденного файла выдаётся "source_received"; повышение до prepared/integrated/verified
## — ручное решение после проверки размера, прозрачности, pivot (поле status_override в assets/art_status.json).

const MANIFEST := "res://assets/asset_manifest_v1.json"
const STATUS_OVERRIDE := "res://assets/art_status.json"
const ACTOR_DIRS := ["S", "E", "N"]
## Раскладка атласа актёра по умолчанию: строка на направление S,E,N; колонки idle, walk0..3, hit. Строка 3 — смерть (4 кадра).
const ATLAS_COLUMNS := {"idle": [0], "walk": [1, 2, 3, 4], "hit": [5]}

var entries := {}
var _tex_cache := {}
var _status_override := {}
var _used_placeholder := {}


func _ready() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if typeof(parsed) == TYPE_DICTIONARY:
		for a in parsed.get("assets", []):
			entries[a.id] = a
	_load_meta()
	if FileAccess.file_exists(STATUS_OVERRIDE):
		var so = JSON.parse_string(FileAccess.get_file_as_string(STATUS_OVERRIDE))
		if typeof(so) == TYPE_DICTIONARY:
			_status_override = so


func has_entry(id: String) -> bool:
	return entries.has(id)


func entry(id: String) -> Dictionary:
	return entries.get(id, {})


func file_exists(id: String) -> bool:
	var e := entry(id)
	return not e.is_empty() and ResourceLoader.exists(str(e.target_path))


## Фактический статус: planned (файла нет) / source_received (файл найден) / override из art_status.json.
func status(id: String) -> String:
	if _status_override.has(id) and file_exists(id):
		return str(_status_override[id])
	return "source_received" if file_exists(id) else "placeholder"


func _load_or_null(id: String) -> Texture2D:
	var e := entry(id)
	if e.is_empty():
		return null
	var path := str(e.target_path)
	if ResourceLoader.exists(path):
		var t = load(path)
		if t is Texture2D:
			return t
	return null


func _note_placeholder(id: String) -> void:
	if not _used_placeholder.has(id):
		_used_placeholder[id] = true
		var sess := get_node_or_null("/root/Session")
		if sess:
			sess.diag("art:" + id, "нет файла, используется placeholder")


func get_texture(id: String, variant: String = "") -> Texture2D:
	var key := id + "|" + variant
	if _tex_cache.has(key):
		return _tex_cache[key]
	var tex: Texture2D = _load_or_null(id)
	if tex == null:
		_note_placeholder(id)
		tex = ImageTexture.create_from_image(_placeholder_image(id, variant))
	_tex_cache[key] = tex
	return tex


func _placeholder_image(id: String, variant: String) -> Image:
	var kind := str(entry(id).get("kind", ""))
	match kind:
		"actor_atlas", "boss_atlas":
			return PlaceholderArt.make_actor(id, variant if variant != "" else "S", int(entry(id).get("canvas_px", [256, 256])[0]))
		"armor_overlay": return PlaceholderArt.make_armor_overlay(id, variant if variant != "" else "S")
		"weapon_sprite": return PlaceholderArt.make_weapon(id)
		"icon": return PlaceholderArt.make_icon(id)
		"floor_texture": return PlaceholderArt.make_floor(id)
		"prop": return PlaceholderArt.make_prop(id)
		"fx_atlas": return PlaceholderArt.make_fx(id)
	return PlaceholderArt.make_prop(id)


## Раскладки листов определяются по размеру текстуры и размеру кадра:
##  * 1×1 — один статичный кадр на все позы/направления;
##  * 3×1 — полоса S, E, N (враги, броня): позы одинаковы, W зеркалится из E;
##  * ≥6×≥4 — атлас героя: строки S, E, N, death; колонки idle, walk0..3, hit.
func sheet_kind(tex: Texture2D, frame_px: Vector2) -> String:
	var cols := int(round(tex.get_size().x / frame_px.x))
	var rows := int(round(tex.get_size().y / frame_px.y))
	if cols <= 1 and rows <= 1:
		return "single"
	if cols == 3 and rows == 1:
		return "strip3"
	return "atlas"


func _frame_px(id: String) -> Vector2:
	var e := entry(id)
	if e.has("frame_px"):
		return Vector2(e.frame_px[0], e.frame_px[1])
	var cp: Array = e.get("canvas_px", [256, 256])
	return Vector2(cp[0], cp[1])


## Кадр актёра: {texture, region: Rect2, flip_h, pivot (px кадра), placeholder}.
func get_actor_frame(id: String, anim: String, dir: String, idx: int = 0) -> Dictionary:
	var e := entry(id)
	var frame_px := _frame_px(id)
	var flip := false
	var d := dir
	if d == "W":
		d = str(e.get("mirror_W_from", "E"))
		flip = true
	var tex: Texture2D = _load_or_null(id)
	if tex == null:
		_note_placeholder(id)
		return {"texture": get_texture(id, d), "region": Rect2(Vector2.ZERO, frame_px), "flip_h": flip, "pivot": get_pivot(id), "placeholder": true}
	var row := maxi(ACTOR_DIRS.find(d), 0)
	var col := 0
	match sheet_kind(tex, frame_px):
		"single":
			row = 0
		"strip3":
			col = row
			row = 0
		_:
			var cols: Array = ATLAS_COLUMNS.get(anim, [0])
			col = cols[idx % cols.size()]
			if anim == "death":
				row = 3
				col = clampi(idx, 0, 3)
	return {"texture": tex, "region": Rect2(Vector2(col, row) * frame_px, frame_px), "flip_h": flip, "pivot": get_pivot(id), "placeholder": false}


## Накладка брони: клетка направления из полосы 3×1 (или placeholder).
func get_armor_frame(id: String, dir: String) -> Dictionary:
	return get_actor_frame(id, "idle", dir, 0)


## Метаданные поставок арта (assets/art_meta/*.json): сокеты героя, хват/дуло оружия.
var meta := {}
const META_FILES := ["res://assets/art_meta/batch_02.json", "res://assets/art_meta/batch_04.json", "res://assets/art_meta/weapons.json"]


func _load_meta() -> void:
	for f in META_FILES:
		if FileAccess.file_exists(f):
			var m = JSON.parse_string(FileAccess.get_file_as_string(f))
			if typeof(m) == TYPE_DICTIONARY:
				for k in m:
					meta[k] = m[k]


func get_pivot(id: String) -> Vector2:
	var e := entry(id)
	if e.has("pivot_px"):
		return Vector2(e.pivot_px[0], e.pivot_px[1])
	var cp: Array = e.get("canvas_px", [256, 256])
	return Vector2(cp[0], cp[1]) * 0.5


func get_scale(id: String) -> float:
	return float(entry(id).get("world_scale", 1.0))


## Сокет оружия героя (в px клетки) по направлению. Из метаданных, если есть настоящий файл героя.
## anim/idx — покадровые координаты (hero.weapon_socket_frames_px[dir][anim] — точка или список точек по кадрам).
func get_weapon_socket(dir: String, anim: String = "idle", idx: int = 0) -> Vector2:
	var d := "E" if dir == "W" else dir
	if file_exists("hero.body") and meta.has("hero") and meta.hero.has("weapon_socket_frames_px") and meta.hero.weapon_socket_frames_px.has(d):
		var fr: Dictionary = meta.hero.weapon_socket_frames_px[d]
		if fr.has(anim):
			var v = fr[anim]
			if v.size() > 0 and typeof(v[0]) == TYPE_ARRAY:
				v = v[idx % v.size()]
			return Vector2(v[0], v[1])
	if file_exists("hero.body") and meta.has("hero") and meta.hero.has("weapon_socket_px") and meta.hero.weapon_socket_px.has(d):
		var v: Array = meta.hero.weapon_socket_px[d]
		return Vector2(v[0], v[1])
	match d:
		"E": return Vector2(155, 145)
		"N": return Vector2(150, 138)
		_: return Vector2(148, 150)


## Хват оружия и дуло в px исходного спрайта (измерены по реальным PNG; иначе контракт (64,64)/(224,64)).
func get_weapon_points(weapon_sprite_id: String) -> Dictionary:
	var grip := get_pivot(weapon_sprite_id)
	var muzzle := Vector2(224, 64)
	var e := entry(weapon_sprite_id)
	if e.has("muzzle_px"):
		muzzle = Vector2(e.muzzle_px[0], e.muzzle_px[1])
	if file_exists(weapon_sprite_id) and meta.has("weapons") and meta.weapons.has(weapon_sprite_id):
		var w: Dictionary = meta.weapons[weapon_sprite_id]
		grip = Vector2(w.grip_px[0], w.grip_px[1])
		muzzle = Vector2(w.muzzle_px[0], w.muzzle_px[1])
	return {"grip": grip, "muzzle": muzzle}


func get_muzzle_flash_anchor() -> Vector2:
	if file_exists("fx.muzzle") and meta.has("assets") and meta.assets.has("fx.muzzle"):
		var o: Array = meta.assets["fx.muzzle"].origin_px
		return Vector2(o[0], o[1])
	return Vector2(29, 69) if file_exists("fx.muzzle") else Vector2(64, 64)


func get_muzzle_offset(weapon_sprite_id: String) -> float:
	var p := get_weapon_points(weapon_sprite_id)
	return (p.muzzle - p.grip).length() * get_scale(weapon_sprite_id)


func report() -> Dictionary:
	var out := {}
	for id in entries:
		out[id] = status(id)
	return out
