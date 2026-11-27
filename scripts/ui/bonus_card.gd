class_name BonusCard
extends Control
## Одна карточка кейса: рубашка/лицо, плавный переворот (сжатие по X, смена стороны на середине).

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


func _draw() -> void:
	var f := ThemeDB.fallback_font
	var w := size.x
	var h := size.y
	var sx := absf(cos(flip * PI))
	var face := flip > 0.5
	var lift := -10.0 * (1.0 - sx) * 0.0
	draw_set_transform(Vector2(w * 0.5, h * 0.5 + lift), 0.0, Vector2(maxf(sx, 0.02), 1.0))
	var r := Rect2(-w * 0.5, -h * 0.5, w, h)
	var def: Dictionary = BonusService.def_of(kind, bonus_id)
	var col := Color(def.color[0], def.color[1], def.color[2]) if def.has("color") else Color(0.8, 0.8, 0.8)
	var shade := 1.0 - dim * 0.55
	if face:
		draw_rect(r, Color(0.09, 0.11, 0.09).darkened(dim * 0.55))
		draw_rect(r.grow(-6), Color(col.r, col.g, col.b, 0.18))
		draw_rect(r, col.darkened(dim * 0.55), false, 5.0)
		if glow > 0.0:
			draw_rect(r.grow(8.0 + 6.0 * glow), Color(1.0, 0.9, 0.4, 0.55 * glow), false, 8.0)
		var tex := AssetRegistry.get_texture(str(def.get("icon_id", "")))
		var isz := minf(w * 0.62, 150.0)
		draw_texture_rect(tex, Rect2(-isz * 0.5, -h * 0.5 + 24, isz, isz), false, Color(shade, shade, shade, 1.0))
		draw_string(f, Vector2(-w * 0.5 + 8, -h * 0.5 + 24 + isz + 36), str(def.get("name", "")), HORIZONTAL_ALIGNMENT_CENTER, w - 16, 26, col.darkened(dim * 0.55))
		draw_multiline_string(f, Vector2(-w * 0.5 + 12, -h * 0.5 + 24 + isz + 70), str(def.get("desc", "")), HORIZONTAL_ALIGNMENT_CENTER, w - 24, 19, 5, Color(0.88, 0.9, 0.85).darkened(dim * 0.55))
		draw_string(f, Vector2(-w * 0.5 + 8, h * 0.5 - 16), ("на %d волны" % BonusService.duration()) if kind == "buff" else "только следующий раунд", HORIZONTAL_ALIGNMENT_CENTER, w - 16, 18, Color(0.7, 0.75, 0.7).darkened(dim * 0.55))
	else:
		var back_id := "ui.curse_card_back" if kind == "debuff" else "ui.bonus_card_back"
		if AssetRegistry.file_exists(back_id):
			draw_texture_rect(AssetRegistry.get_texture(back_id), r, false)
		else:
			draw_rect(r, Color(0.12, 0.14, 0.12))
			draw_rect(r.grow(-10), Color(0.16, 0.19, 0.16))
			var y := r.position.y + 28
			while y < r.end.y - 20:
				draw_line(Vector2(r.position.x + 18, y), Vector2(r.end.x - 18, y), Color(1, 1, 1, 0.05), 2.0)
				y += 22
			draw_string(f, Vector2(-w * 0.5, 22), "?", HORIZONTAL_ALIGNMENT_CENTER, w, 120, Color(0.95, 0.25, 0.2, 0.95) if kind == "debuff" else Color(1.0, 0.6, 0.2, 0.9))
		var base_edge := Color(0.9, 0.2, 0.15) if kind == "debuff" else Color(1.0, 0.6, 0.2)
		var edge := Color(base_edge.r, base_edge.g, base_edge.b, 0.7 + (0.3 if hover else 0.0) + (0.25 * sin(Time.get_ticks_msec() / 250.0) if enabled else 0.0))
		draw_rect(r, edge, false, 5.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
