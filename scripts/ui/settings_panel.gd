extends Control
## Окно настроек (используется в меню и на паузе). Меняет Settings и сохраняет сразу.

signal closed


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UiKit.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.custom_minimum_size = Vector2(560, 0)
	panel.add_child(vb)
	vb.add_child(UiKit.label("Настройки", 34, UiKit.ACCENT))
	_slider(vb, "Громкость эффектов", "sfx_volume")
	_slider(vb, "Громкость музыки", "music_volume")
	_check(vb, "Автонаведение и автострельба", "autoaim")
	_check(vb, "Подсказки", "hints")
	_check(vb, "Показывать FPS", "show_fps")
	_option(vb, "Качество эффектов", "quality", [["low", "Низкое (меньше эффектов)"], ["medium", "Среднее"], ["high", "Высокое"]])
	_option(vb, "Сенсорное управление", "touch_ui", [["auto", "Авто"], ["on", "Всегда"], ["off", "Выключено"]])
	_option(vb, "Лимит кадров", "fps_cap", [[30, "30 (экономия)"], [60, "60"], [0, "Без лимита"]])
	var close := UiKit.button("Закрыть", Vector2(0, 56))
	close.pressed.connect(func():
		closed.emit()
		queue_free())
	vb.add_child(close)


func _row(parent: Control, text: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	var l := UiKit.label(text, 22)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(l)
	parent.add_child(hb)
	return hb


func _slider(parent: Control, text: String, key: String) -> void:
	var hb := _row(parent, text)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(Settings.data[key])
	s.custom_minimum_size = Vector2(220, 30)
	s.value_changed.connect(func(v): Settings.set_value(key, v))
	hb.add_child(s)


func _check(parent: Control, text: String, key: String) -> void:
	var hb := _row(parent, text)
	var c := CheckButton.new()
	c.button_pressed = bool(Settings.data[key])
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(v): Settings.set_value(key, v))
	hb.add_child(c)


func _option(parent: Control, text: String, key: String, opts: Array) -> void:
	var hb := _row(parent, text)
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.custom_minimum_size = Vector2(260, 40)
	var sel := 0
	for i in opts.size():
		ob.add_item(str(opts[i][1]), i)
		if str(opts[i][0]) == str(Settings.data[key]):
			sel = i
	ob.select(sel)
	ob.item_selected.connect(func(i): Settings.set_value(key, opts[i][0]))
	hb.add_child(ob)
