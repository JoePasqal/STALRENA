extends Control
## Итоги забега после поражения. Забег уже помечен завершённым и продолжить его нельзя.

var game


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UiKit.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)


func open(rec: Dictionary) -> void:
	for c in get_children():
		c.queue_free()
	var run: RunState = game.run
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	var p := PanelContainer.new()
	c.add_child(p)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(560, 0)
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(UiKit.label("Забег окончен", 40, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	var reached := run.waves_completed
	var src := str(run.stats.get("deaths_by", ""))
	var src_name: String = GameData.enemies[src].name if GameData.enemies.has(src) else (GameData.bosses[src].name if GameData.bosses.has(src) else (str(GameData.modifiers[src.trim_prefix("mod_")].name) if src.begins_with("mod_") and GameData.modifiers.has(src.trim_prefix("mod_")) else ("взрыв" if src == "unstable" else src)))
	var mins := int(run.play_time) / 60
	var secs := int(run.play_time) % 60
	v.add_child(UiKit.label("Пройдено волн: %d (сектор %d)" % [reached, run.sector_of(maxi(reached, 1))], 24, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.label("Погибли от: %s" % src_name, 22, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.label("Время в бою: %d:%02d · убийств %d" % [mins, secs, int(run.stats.get("kills", 0))], 20, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.label("Рекорд: волна %d" % int(rec.best_wave), 22, Color(1.0, 0.9, 0.5), HORIZONTAL_ALIGNMENT_CENTER))
	var hist := ""
	for h in rec.history.slice(0, 5):
		hist += "волна %d · %d:%02d\n" % [int(h.wave) - 1 if int(h.wave) > 0 else 0, int(float(h.time)) / 60, int(float(h.time)) % 60]
	v.add_child(UiKit.label("Последние забеги:\n" + hist, 16, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var nb := UiKit.button("Новый забег", Vector2(0, 58), 24)
	nb.pressed.connect(func():
		Session.new_run()
		Session.go_game())
	v.add_child(nb)
	var mb := UiKit.button("В меню", Vector2(0, 52))
	mb.pressed.connect(func(): Session.go_menu())
	v.add_child(mb)
	visible = true
