class_name TouchControls
extends Control
## Мобильное управление: плавающий левый стик (движение), правый стик (ручной прицел и
## стрельба пока удерживается), кнопки аптечки/перезарядки/паузы. Мультитач: каждый палец
## привязан к своему индексу, поэтому стики и кнопки не блокируют друг друга.
## События приходят через _gui_input (координаты уже в логических пикселях сцены).

var game
var move_vec := Vector2.ZERO
var aim_vec := Vector2.ZERO
var aim_active := false

const STICK_R := 90.0
const DEAD := 12.0

var _left := -1
var _left_o := Vector2.ZERO
var _left_p := Vector2.ZERO
var _right := -1
var _right_o := Vector2.ZERO
var _right_p := Vector2.ZERO
var _btn := {}           # индекс пальца -> имя кнопки
var _last_aim := Vector2.RIGHT


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _btn_defs() -> Dictionary:
	var sm := UiKit.safe_margins(get_viewport())
	var rx := size.x - 78.0 - sm.size.x
	var by := size.y - 78.0 - sm.size.y
	return {
		"medkit": {"c": Vector2(rx, by - 250.0), "r": 52.0},
		"reload": {"c": Vector2(rx, by - 360.0), "r": 40.0},
		"pause": {"c": Vector2(size.x - 56.0 - sm.size.x, 50.0 + sm.position.y), "r": 32.0},
	}


func _hit_button(p: Vector2) -> String:
	var defs := _btn_defs()
	for k in defs:
		if p.distance_to(defs[k].c) <= defs[k].r + 10.0:
			return k
	return ""


func reset_inputs() -> void:
	_left = -1
	_right = -1
	_btn.clear()
	move_vec = Vector2.ZERO
	aim_vec = Vector2.ZERO
	aim_active = false


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		_touch(event.index, event.position, event.pressed)
		accept_event()
	elif event is InputEventScreenDrag:
		_drag(event.index, event.position)
		accept_event()
	elif not DisplayServer.is_touchscreen_available() and Settings.data.touch_ui == "on":
		# режим проверки на ПК: мышь как палец №99
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_touch(99, event.position, event.pressed)
			accept_event()
		elif event is InputEventMouseMotion and (_left == 99 or _right == 99):
			_drag(99, event.position)
			accept_event()


func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		var b := _hit_button(pos)
		if b != "":
			_btn[idx] = b
			match b:
				"medkit": game.player.use_medkit()
				"reload": game.player.start_reload()
				"pause": game.open_pause()
			return
		if pos.x < size.x * 0.5 and _left == -1:
			_left = idx
			_left_o = pos
			_left_p = pos
		elif pos.x >= size.x * 0.5 and _right == -1:
			_right = idx
			_right_o = pos
			_right_p = pos
			aim_active = true
			aim_vec = _last_aim
	else:
		_btn.erase(idx)
		if idx == _left:
			_left = -1
			move_vec = Vector2.ZERO
		if idx == _right:
			_right = -1
			aim_active = false        # после отпускания — возврат к автонаведению


func _drag(idx: int, pos: Vector2) -> void:
	if idx == _left:
		_left_p = pos
		var d := pos - _left_o
		if d.length() > STICK_R:
			_left_o = pos - d.normalized() * STICK_R      # плавающая база
			d = pos - _left_o
		move_vec = d / STICK_R if d.length() > DEAD else Vector2.ZERO
	elif idx == _right:
		_right_p = pos
		var d2 := pos - _right_o
		if d2.length() > STICK_R:
			_right_o = pos - d2.normalized() * STICK_R
			d2 = pos - _right_o
		if d2.length() > DEAD:
			aim_vec = d2.normalized()
			_last_aim = aim_vec


func _process(_d: float) -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	if visible:
		queue_redraw()


func _draw() -> void:
	if game == null or game.player == null:
		return
	var sm := UiKit.safe_margins(get_viewport())
	var ring := Color(1, 1, 1, 0.22)
	var knob := Color(0.62, 0.84, 0.93, 0.55)
	if _left == -1:
		draw_arc(Vector2(150.0 + sm.position.x, size.y - 150.0 - sm.size.y), STICK_R, 0.0, TAU, 32, ring, 3.0)
	else:
		draw_arc(_left_o, STICK_R, 0.0, TAU, 32, ring, 4.0)
		draw_circle(_left_p if _left_p.distance_to(_left_o) < STICK_R else _left_o + (_left_p - _left_o).normalized() * STICK_R, 38.0, knob)
	if _right == -1:
		draw_arc(Vector2(size.x - 200.0 - sm.size.x, size.y - 150.0 - sm.size.y), STICK_R, 0.0, TAU, 32, ring, 3.0)
	else:
		draw_arc(_right_o, STICK_R, 0.0, TAU, 32, Color(1.0, 0.55, 0.2, 0.35), 4.0)
		draw_circle(_right_p if _right_p.distance_to(_right_o) < STICK_R else _right_o + (_right_p - _right_o).normalized() * STICK_R, 38.0, Color(1.0, 0.6, 0.25, 0.5))
	var defs := _btn_defs()
	var pl: Player = game.player
	var f := ThemeDB.fallback_font
	for k in defs:
		var c: Vector2 = defs[k].c
		var r: float = defs[k].r
		var pressed := _btn.values().has(k)
		var enabled := true
		if k == "medkit":
			enabled = pl.medkit.stock > 0 or pl.medkit.active
		draw_circle(c, r, Color(0.08, 0.1, 0.08, 0.65 if enabled else 0.4))
		draw_arc(c, r, 0.0, TAU, 28, Color(0.62, 0.84, 0.93, 0.9 if enabled else 0.3) if not pressed else Color(1.0, 0.7, 0.3), 3.0)
		match k:
			"medkit":
				var tex := AssetRegistry.get_texture("icon.medkit")
				draw_texture_rect(tex, Rect2(c - Vector2(r, r) * 0.62, Vector2(r, r) * 1.24), false, Color(1, 1, 1, 1.0 if enabled else 0.4))
				draw_string(f, c + Vector2(-r, r + 22.0), "Аптечка %d/1" % pl.medkit.stock, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 16, Color(1, 1, 1, 0.85))
				if pl.medkit.active:
					draw_arc(c, r + 6.0, -PI * 0.5, -PI * 0.5 + TAU * pl.medkit.progress(), 28, Color(0.55, 0.9, 1.0), 5.0)
			"reload":
				draw_string(f, c + Vector2(-r, 8.0), "R", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 26, Color(1, 1, 1, 0.9))
				if pl.reloading:
					draw_arc(c, r + 5.0, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - pl.reload_left / maxf(float(pl.wstats.reload_time), 0.01)), 24, Color(1.0, 0.8, 0.4), 4.0)
			"pause":
				draw_rect(Rect2(c + Vector2(-10, -12), Vector2(7, 24)), Color(1, 1, 1, 0.9))
				draw_rect(Rect2(c + Vector2(3, -12), Vector2(7, 24)), Color(1, 1, 1, 0.9))
