class_name BonusCard
extends Control
## Карточка кейса. С графикой партии 5: рубашка → покадровый переворот (8 кадров) → лицо; содержимое (иконка, название,
## описание) рисует код поверх лица. Без файлов — программная карточка со сжатием по ширине (запасной вариант).

signal tapped(card)

var bonus_id := ""
var kind := "buff"
var index := 0
var flip := 0.0                 # 0 — рубашкой вверх, 1 — лицом
var dim := 0.0                  # затемнение невыбранных после показа
var glow := 0.0                 # подсветка выбранной
var hover := false
var enabled := false


func setup(p_index: int, p_bonus_id: String, p_kind: String = "buff") -> void:
	index = p_index
	bonus_id = p_bonus_id
	kind = p_kind
	mouse_filter = Control.MOUSE_FILTER_STOP
	pivot_offset = size * 0.5


func _gui_input(event: InputEvent) -> void:
	if not enabled:
		return
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
		tapped.emit(self)
		accept_event()
	elif event is InputEventMouseMotion:
		hover = true
		queue_redraw()


func _process(_d: float) -> void:
	queue_redraw()                  # flip/dim/glow меняются твином


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hover = false
		queue_redraw()


func _ids() -> Dictionary:
	var curse := kind == "debuff"
	return {
		"back": "ui.curse_card_back" if curse else "ui.bonus_card_back",
		"face": "ui.card_face_curse" if curse else "ui.card_face_buff",
		"flip": "ui.card_flip_curse" if curse else "ui.card_flip_buff",
	}


func _color() -> Color:
	var def: Dictionary = BonusService.def_of(kind, bonus_id)
	return Color(def.color[0], def.color[1], def.color[2]) if def.has("color") else Color(0.8, 0.8, 0.8)


func _draw() -> void:
	var ids := _ids()
	if AssetRegistry.file_exists(ids.flip) and AssetRegistry.file_exists(ids.face) and AssetRegistry.file_exists(ids.back):
		_draw_art(ids)
	else:
		_draw_fallback()


## Версия с графикой: покадровый переворот; полоса содержит рубашку → ребро → пустое лицо.
func _draw_art(ids: Dictionary) -> void:
	var w := size.x
	var h := size.y
	var shade := 1.0 - dim * 0.55
	var mod := Color(shade, shade, shade, 1.0)
	if glow > 0.0 and AssetRegistry.file_exists("ui.card_glow"):
		var gt := AssetRegistry.get_texture("ui.card_glow")
		var k := 1.25
		draw_texture_rect(gt, Rect2(-w * (k - 1.0) * 0.5, -h * (k - 1.0) * 0.5, w * k, h * k), false, Color(1, 1, 1, glow))
	var tex: Texture2D
	var region := Rect2()
	if flip <= 0.001:
		tex = AssetRegistry.get_texture(ids.back)
		region = Rect2(Vector2.ZERO, tex.get_size())
	elif flip >= 0.999:
		tex = AssetRegistry.get_texture(ids.face)
		region = Rect2(Vector2.ZERO, tex.get_size())
	else:
		var fr := AssetRegistry.strip_frame(ids.flip, int(flip * float(AssetRegistry.strip_frame(ids.flip, 0).frames - 0.001)))
		tex = fr.texture
		region = fr.region
	draw_texture_rect_region(tex, Rect2(0, 0, w, h), region, mod)
	var a := clampf((flip - 0.7) / 0.3, 0.0, 1.0)             # содержимое проявляется в конце переворота
	if a > 0.0:
		_draw_content(Vector2.ZERO, Vector2(w, h), a, shade, true)
	if enabled and flip <= 0.001:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 250.0)
		var c := Color(0.95, 0.25, 0.2) if kind == "debuff" else Color(1.0, 0.7, 0.25)
		draw_rect(Rect2(0, 0, w, h), Color(c.r, c.g, c.b, (0.35 if hover else 0.0) + 0.2 * pulse), false, 4.0)


func _draw_content(origin: Vector2, sz: Vector2, alpha: float, shade: float, inset: bool = false) -> void:
	var f := ThemeDB.fallback_font
	var def: Dictionary = BonusService.def_of(kind, bonus_id)
	var col := _color().darkened(dim * 0.55)
	col.a = alpha
	if inset:
		_draw_content_inset(f, def, origin, sz, alpha, shade, col)
		return
	var isz := minf(sz.x * 0.55, 140.0)
	var tex := AssetRegistry.get_texture(str(def.get("icon_id", "")))
	draw_texture_rect(tex, Rect2(origin.x + (sz.x - isz) * 0.5, origin.y + sz.y * 0.1, isz, isz), false, Color(shade, shade, shade, alpha))
	var ty := origin.y + sz.y * 0.1 + isz + 34.0
	draw_string(f, Vector2(origin.x + 8, ty), str(def.get("name", "")), HORIZONTAL_ALIGNMENT_CENTER, sz.x - 16, 26, col)
	var txt := Color(0.9, 0.92, 0.88, alpha).darkened(dim * 0.55)
	txt.a = alpha
	draw_multiline_string(f, Vector2(origin.x + 14, ty + 34), str(def.get("desc", "")), HORIZONTAL_ALIGNMENT_CENTER, sz.x - 28, 19, 5, txt)
	var foot := Color(0.75, 0.8, 0.75, alpha).darkened(dim * 0.55)
	foot.a = alpha
	draw_string(f, Vector2(origin.x + 8, origin.y + sz.y - 22), ("на %d волны" % BonusService.duration()) if kind == "buff" else "только следующий раунд", HORIZONTAL_ALIGNMENT_CENTER, sz.x - 16, 18, foot)


## Содержимое внутри рамки арт-карточки (внутренняя область ≈ 18%..82% по ширине, 10%..86% по высоте).
func _draw_content_inset(f: Font, def: Dictionary, origin: Vector2, sz: Vector2, alpha: float, shade: float, col: Color) -> void:
	var ix := origin.x + sz.x * 0.17
	var iw := sz.x * 0.66
	var isz := minf(iw * 0.78, 110.0)
	var tex := AssetRegistry.get_texture(str(def.get("icon_id", "")))
	draw_texture_rect(tex, Rect2(origin.x + (sz.x - isz) * 0.5, origin.y + sz.y * 0.10, isz, isz), false, Color(shade, shade, shade, alpha))
	var ty := origin.y + sz.y * 0.10 + isz + 22.0
	var nm := str(def.get("name", ""))
	var nsz := _fit_font(f, nm, iw, 21, 12)
	draw_string(f, Vector2(ix, ty), nm, HORIZONTAL_ALIGNMENT_CENTER, iw, nsz, col)
	var txt := Color(0.9, 0.92, 0.88, alpha).darkened(dim * 0.55)
	txt.a = alpha
	draw_multiline_string(f, Vector2(ix, ty + 22.0), str(def.get("desc", "")), HORIZONTAL_ALIGNMENT_CENTER, iw, 15, 5, txt)
	var foot := Color(0.75, 0.8, 0.75, alpha).darkened(dim * 0.55)
	foot.a = alpha
	var ft := ("на %d волны" % BonusService.duration()) if kind == "buff" else "только след. раунд"
	draw_string(f, Vector2(ix, origin.y + sz.y * 0.85), ft, HORIZONTAL_ALIGNMENT_CENTER, iw, _fit_font(f, ft, iw, 14, 10), foot)


func _fit_font(f: Font, text: String, width: float, max_size: int, min_size: int) -> int:
	var sz := max_size
	while sz > min_size and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > width:
		sz -= 1
	return sz


## Запасной вариант без файлов: процедурная карточка (рубашка/лицо) и сжатие по ширине.
func _draw_fallback() -> void:
	var f := ThemeDB.fallback_font
	var w := size.x
	var h := size.y
	var sx := absf(cos(flip * PI))
	var face := flip > 0.5
	draw_set_transform(Vector2(w * 0.5, h * 0.5), 0.0, Vector2(maxf(sx, 0.02), 1.0))
	var r := Rect2(-w * 0.5, -h * 0.5, w, h)
	var col := _color()
	if face:
		draw_rect(r, Color(0.09, 0.11, 0.09).darkened(dim * 0.55))
		draw_rect(r, col.darkened(dim * 0.55), false, 5.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_draw_content(Vector2.ZERO, Vector2(w, h), 1.0, 1.0 - dim * 0.55)
	else:
		draw_rect(r, Color(0.12, 0.14, 0.12))
		draw_rect(r, Color(0.9, 0.2, 0.15) if kind == "debuff" else Color(1.0, 0.6, 0.2), false, 5.0)
		draw_string(f, Vector2(-w * 0.5, 22), "?", HORIZONTAL_ALIGNMENT_CENTER, w, 120, Color(0.95, 0.25, 0.2) if kind == "debuff" else Color(1.0, 0.6, 0.2))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
