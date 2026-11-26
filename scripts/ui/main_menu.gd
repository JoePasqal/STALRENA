extends Control
## Главное меню: продолжить / новый забег (с подтверждением) / настройки / рекорды.

var _confirm: ConfirmationDialog
var _settings_panel: Control
var _notice: Label
var _continue_btn: Button


func _ready() -> void:
	theme = UiKit.theme()
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	vb.custom_minimum_size = Vector2(420, 0)
	center.add_child(vb)
	vb.add_child(UiKit.label("STALRENA", 72, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(UiKit.label("Выживание в аренах · магазин между волнами", 22, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(Control.new())
	_continue_btn = UiKit.button("Продолжить", Vector2(0, 60), 26)
	_continue_btn.pressed.connect(_on_continue)
	vb.add_child(_continue_btn)
	var nb := UiKit.button("Новый забег", Vector2(0, 60), 26)
	nb.pressed.connect(_on_new)
	vb.add_child(nb)
	var sb := UiKit.button("Настройки", Vector2(0, 52))
	sb.pressed.connect(_on_settings)
	vb.add_child(sb)
	var qb := UiKit.button("Выход", Vector2(0, 52))
	qb.pressed.connect(func(): get_tree().quit())
	vb.add_child(qb)
	_notice = UiKit.label("", 20, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_notice)
	var rec := SaveService.load_records()
	var rl := UiKit.label("Рекорд: волна %d" % int(rec.best_wave) if int(rec.best_wave) > 0 else "Рекордов пока нет", 20, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(rl)
	var ver := UiKit.label("Godot %s · v1" % Engine.get_version_info().string, 16, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(ver)

	_confirm = ConfirmationDialog.new()
	_confirm.title = "Новый забег"
	_confirm.dialog_text = "Есть активный забег. Начать новый и потерять его?"
	_confirm.ok_button_text = "Начать новый"
	_confirm.cancel_button_text = "Отмена"
	_confirm.confirmed.connect(_start_new)
	add_child(_confirm)
	_refresh()


func _refresh() -> void:
	var s := SaveService.load_run()
	var active: bool = s.run != null and not s.run.over
	_continue_btn.disabled = not active
	match s.status:
		"corrupt": _notice.text = "Сохранение повреждено. Начните новый забег."
		"incompatible": _notice.text = "Сохранение несовместимо с этой версией. Начните новый забег."
		"backup": _notice.text = "Основной файл повреждён — будет восстановлена резервная копия."
		_: _notice.text = ""
	if s.run != null and s.run.over:
		_notice.text = "Последний забег завершён."


func _on_continue() -> void:
	var res := Session.continue_run()
	if res.run == null or res.run.over:
		_refresh()
		return
	Session.go_game()


func _on_new() -> void:
	var s := SaveService.load_run()
	if s.run != null and not s.run.over:
		_confirm.popup_centered()
	else:
		_start_new()


func _start_new() -> void:
	Session.new_run()
	Session.go_game()


func _on_settings() -> void:
	var sp: Control = load("res://scripts/ui/settings_panel.gd").new()
	add_child(sp)
