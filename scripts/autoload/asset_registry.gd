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


## Кадр актёра: {texture, region: Rect2, flip_h, pivot (в px кадра)}. Для placeholder — по текстуре на направление.
func get_actor_frame(id: String, anim: String, dir: String, idx: int = 0) -> Dictionary:
	var e := entry(id)
	var frame_px: Vector2 = Vector2(256, 256)
	if e.has("frame_px"):
		frame_px = Vector2(e.frame_px[0], e.frame_px[1])
	var flip := false
	var d := dir
	if d == "W":
		d = str(e.get("mirror_W_from", "E"))
		flip = true
	var tex: Texture2D = _load_or_null(id)
	if tex == null:
		_note_placeholder(id)
		return {"texture": get_texture(id, d), "region": Rect2(Vector2.ZERO, frame_px), "flip_h": flip, "pivot": get_pivot(id), "placeholder": true}
	if tex.get_size().x <= frame_px.x + 0.5 and tex.get_size().y <= frame_px.y + 0.5:
		# одиночный статичный кадр (первая поставка): используем его для всех поз и направлений
		return {"texture": tex, "region": Rect2(Vector2.ZERO, tex.get_size()), "flip_h": flip, "pivot": get_pivot(id), "placeholder": false}
	var row := ACTOR_DIRS.find(d)
	var cols: Array = ATLAS_COLUMNS.get(anim, [0])
	var col: int = cols[idx % cols.size()]
	if anim == "death":
		row = 3
		col = clampi(idx, 0, 3)
	return {"texture": tex, "region": Rect2(Vector2(col, maxi(row, 0)) * frame_px, frame_px), "flip_h": flip, "pivot": get_pivot(id), "placeholder": false}


func get_pivot(id: String) -> Vector2:
	var e := entry(id)
	if e.has("pivot_px"):
		return Vector2(e.pivot_px[0], e.pivot_px[1])
	var cp: Array = e.get("canvas_px", [256, 256])
	return Vector2(cp[0], cp[1]) * 0.5


func get_scale(id: String) -> float:
	return float(entry(id).get("world_scale", 1.0))


## Сокет оружия героя (в px кадра) по направлению; корректируется в assets/art_meta при финальном арте.
func get_weapon_socket(dir: String) -> Vector2:
	match dir:
		"E", "W": return Vector2(155, 145)
		"N": return Vector2(150, 138)
		_: return Vector2(148, 150)


func get_muzzle_offset(weapon_sprite_id: String) -> float:
	var e := entry(weapon_sprite_id)
	if e.has("muzzle_px") and e.has("pivot_px"):
		return (float(e.muzzle_px[0]) - float(e.pivot_px[0])) * get_scale(weapon_sprite_id)
	return 40.0


func report() -> Dictionary:
	var out := {}
	for id in entries:
		out[id] = status(id)
	return out
