class_name UiKit
extends RefCounted
## Общая тема и помощники интерфейса. Весь текст живой (кириллица, встроенный шрифт Godot).

const BG := Color(0.09, 0.1, 0.09)
const PANEL := Color(0.14, 0.16, 0.14, 0.96)
const PANEL_LIGHT := Color(0.2, 0.23, 0.2, 0.98)
const ACCENT := Color(0.88, 0.46, 0.17)         # красно-оранжевый: опасность/акцент
const FRIENDLY := Color(0.62, 0.84, 0.93)       # голубой: дружественное
const TEXT := Color(0.9, 0.92, 0.88)
const MUTED := Color(0.62, 0.66, 0.6)
const GOOD := Color(0.5, 0.82, 0.5)
const BAD := Color(0.9, 0.36, 0.3)
const RANK_COLORS := [Color(0.75, 0.75, 0.72), Color(0.55, 0.82, 0.55), Color(0.5, 0.7, 0.95), Color(0.78, 0.55, 0.95), Color(0.98, 0.72, 0.3)]

static var _theme: Theme = null


static func box(col: Color, radius: int = 8, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 22
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.52, 0.48))
	t.set_stylebox("normal", "Button", box(Color(0.22, 0.26, 0.22), 8, Color(0.36, 0.42, 0.34), 2))
	t.set_stylebox("hover", "Button", box(Color(0.28, 0.33, 0.27), 8, ACCENT, 2))
	t.set_stylebox("pressed", "Button", box(Color(0.36, 0.28, 0.2), 8, ACCENT, 2))
	t.set_stylebox("disabled", "Button", box(Color(0.15, 0.16, 0.15), 8, Color(0.22, 0.24, 0.22), 2))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), 8, FRIENDLY, 2))
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 10, Color(0.3, 0.34, 0.28), 2))
	t.set_stylebox("panel", "Panel", box(PANEL, 10, Color(0.3, 0.34, 0.28), 2))
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_color", "OptionButton", TEXT)
	t.set_stylebox("normal", "OptionButton", box(Color(0.22, 0.26, 0.22), 8, Color(0.36, 0.42, 0.34), 2))
	t.set_stylebox("hover", "OptionButton", box(Color(0.28, 0.33, 0.27), 8, ACCENT, 2))
	t.set_stylebox("pressed", "OptionButton", box(Color(0.28, 0.33, 0.27), 8, ACCENT, 2))
	_theme = t
	return t


static func label(text: String, size: int = 22, col: Color = TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = align as HorizontalAlignment
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


static func button(text: String, min_size: Vector2 = Vector2(0, 52), size: int = 22) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	return b


static func safe_margins(viewport: Viewport) -> Rect2:
	## Безопасная область (вырезы/скругления) в координатах окна → в логические пиксели.
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if win.x <= 0 or win.y <= 0 or safe.size.x <= 0:
		return Rect2()
	var vp_size := viewport.get_visible_rect().size
	var kx := vp_size.x / float(win.x)
	var ky := vp_size.y / float(win.y)
	var left := maxf(safe.position.x * kx, 0.0)
	var top := maxf(safe.position.y * ky, 0.0)
	var right := maxf((win.x - safe.end.x) * kx, 0.0)
	var bottom := maxf((win.y - safe.end.y) * ky, 0.0)
	return Rect2(left, top, right, bottom)    # (left, top, right, bottom)
