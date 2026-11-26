extends Control
## Пауза: продолжить, настройки, текущая сборка, выход в меню (сохранение остаётся).

var game
var _build_label: Label
var _dbg_box: VBoxContainer
var settings_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UiKit.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	var p := PanelContainer.new()
	c.add_child(p)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(520, 0)
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(UiKit.label("Пауза", 38, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	_build_label = UiKit.label("", 18, UiKit.MUTED)
	_build_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_build_label)
	var rb := UiKit.button("Продолжить", Vector2(0, 58), 24)
	rb.pressed.connect(func(): game.close_pause())
	v.add_child(rb)
	var sb := UiKit.button("Настройки", Vector2(0, 52))
	settings_btn = sb
	sb.pressed.connect(func():
		var sp: Control = load("res://scripts/ui/settings_panel.gd").new()
		add_child(sp))
	v.add_child(sb)
	var mb := UiKit.button("Выйти в меню", Vector2(0, 52))
	mb.pressed.connect(func():
		get_tree().paused = false
		game._exit_to_menu())
	v.add_child(mb)
	_dbg_box = VBoxContainer.new()
	v.add_child(_dbg_box)
	if Session.debug_enabled:
		_dbg_box.add_child(UiKit.label("Отладка (скрыто в release):", 16, UiKit.MUTED))
		for w in GameData.B.get("debug_waves", [24, 60, 120]) if GameData.B.has("debug_waves") else [24, 60, 120]:
			var db := UiKit.button("Перейти на волну %d" % int(w), Vector2(0, 40), 16)
			var wv := int(w)
			db.pressed.connect(func():
				DebugTools.apply_loadout(Session.run, wv)
				Session.save()
				get_tree().paused = false
				Session.go_game())
			_dbg_box.add_child(db)


func open() -> void:
	var run: RunState = game.run
	var ps := StatCalc.player_stats(run)
	var ws := StatCalc.weapon_stats(run, run.equipped_weapon)
	var armor := "без брони" if run.equipped_armor == "" else "%s %s" % [GameData.armors[run.equipped_armor].name, GameData.rank_roman(int(run.armors[run.equipped_armor].rank))]
	var mods: Array = []
	for id in run.modules:
		mods.append("%s %d" % [GameData.modules[id].name, int(run.modules[id].level)])
	_build_label.text = "Сборка: %s %s · %s\nМакс. ХП %d · урон %.1f · темп %.1f/с\nМодули: %s" % [GameData.weapons[run.equipped_weapon].name, GameData.rank_roman(int(ws.rank)), armor, int(round(ps.max_hp)), ws.damage, ws.fire_rate, ", ".join(mods) if not mods.is_empty() else "нет"]
	visible = true
	if game.touch != null:
		game.touch.reset_inputs()


func _process(_d: float) -> void:
	if visible:
		position = Vector2.ZERO
		size = get_viewport_rect().size
