class_name Tutorial
extends Control
## Обучение первого забега, рассчитанное в первую очередь на телефон:
##  1) в первом магазине — 4 экрана с подсветкой (карточки, снаряжение, кнопки, старт);
##  2) в первой волне — схема управления на самом экране (левый/правый палец, кнопки) и живые подсказки:
##     движение → стрельба → красные круги → аптечка. Подсказки продвигаются по действиям игрока.
## Можно пропустить в любой момент; повтор — в настройках. Выключается настройкой «Подсказки».

signal finished

var game
var blocking := false                    # модальный экран: симуляция/интро стоят
var mode := ""                           # "" | shop | controls | live
var step := 0
var _touch := false
var _t := 0.0

var _card: PanelContainer
var _title: Label
var _text: Label
var _count: Label
var _next: Button
var _skip: Button

# живые подсказки
var _live_step := ""                     # move | shoot | medkit | ""
var _live_t := 0.0
var _moved := 0.0
var _last_pos := Vector2.ZERO
var _kills_start := 0
var _tele_shown := false
var _tele_t := 0.0
var _medkit_asked := false
var _medkit_done := false
var _tip_title := ""
var _tip_text := ""
var _highlight := Rect2()
var _highlight_circle := Vector3(-1, -1, 0)    # x, y, r — подсветка кнопки/зоны
var _hint_pos := Vector2(-1, -1)

static var force_headless := false           # тесты: включить обучение без дисплея

const SHOP_STEPS := [
	{"rect": "cards", "title": "Магазин: шесть предложений", "text": "Нажмите «Купить» под карточкой. Карточка «Часть → ранг II» — одна из трёх нужных частей: три одинаковые части повышают ранг оружия или брони. Покупки возможны только здесь, между волнами."},
	{"rect": "right", "title": "Ваше снаряжение", "text": "Справа — активное оружие (нажмите на другое, чтобы взять его) и броня: она добавляет ХП и не снижает урон. Вкладки «Модули» и «Части» показывают ячейки, прогресс сборки (например 1/3) и продажу."},
	{"rect": "bottom", "title": "Кнопки магазина", "text": "«Обновить всё» (10 монет) меняет все шесть карточек. «Сохранить предложения» оставит набор на следующую волну. «Повысить магазин» открывает более высокие ранги. «Мастерство» пригодится позже — на V ранге."},
	{"rect": "start", "title": "В бой", "text": "Когда готовы — нажмите «Начать волну». Раунд длится 2 минуты (босс — 2 минуты или его смерть). Герой получит полное здоровье, полный магазин патронов и минимум одну аптечку; ещё аптечки покупаются кнопкой «Аптечка», неиспользованные сохраняются."},
]


func is_enabled() -> bool:
	if not bool(Settings.data.hints):
		return false
	if DisplayServer.get_name() == "headless" and not force_headless:
		return false
	return true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UiKit.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UiKit.box(Color(0.08, 0.1, 0.08, 0.96), 12, UiKit.ACCENT, 3))
	add_child(_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_card.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	_title = UiKit.label("", 26, UiKit.ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(200, 0)
	head.add_child(_title)
	_count = UiKit.label("", 18, UiKit.MUTED)
	head.add_child(_count)
	_text = UiKit.label("", 21)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(300, 0)
	v.add_child(_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_skip = UiKit.button("Пропустить обучение", Vector2(0, 52), 18)
	_skip.pressed.connect(skip_all)
	row.add_child(_skip)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	_next = UiKit.button("Дальше", Vector2(190, 56), 22)
	_next.pressed.connect(_on_next)
	row.add_child(_next)


# ---- запуск ------------------------------------------------------------------------
func begin_shop() -> void:
	if not is_enabled() or bool(Settings.data.tutorial_shop_done) or game.run.waves_completed > 0:
		return
	_touch = Settings.touch_ui_enabled()
	mode = "shop"
	step = 0
	blocking = true
	_show_shop_step()


func begin_controls(force: bool = false) -> void:
	if not force and (not is_enabled() or bool(Settings.data.tutorial_done) or game.run.waves_completed > 0):
		return
	_touch = game.touch != null and game.touch.visible
	mode = "controls"
	blocking = true
	_live_step = ""
	_tele_shown = false
	_medkit_asked = false
	_medkit_done = false
	_set_card("Управление" if not _touch else "Управление на телефоне", _controls_text(), "", "Понятно")
	_card_place("bottom")
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	Sfx.play("tutorial")


func _controls_text() -> String:
	if _touch:
		return "ЛЕВЫЙ палец — движение: ведите по левой половине экрана.\nПРАВЫЙ палец — прицел и огонь: держите на правой половине и ведите к врагу. Пока правый палец не нажат, герой не стреляет (автострельбу можно включить в настройках).\nКнопки справа: аптечка, перезарядка (R) и пауза."
	return "WASD / стрелки — движение. Мышь + ЛКМ — ручной прицел и огонь; без ЛКМ герой не стреляет (автострельбу можно включить в настройках).\nR — перезарядка, F — аптечка (одна на раунд), Esc — пауза."


func on_wave_started() -> void:
	pass


## Вызывается после «Понятно» на схеме управления: начинаются живые подсказки.
func _start_live() -> void:
	mode = "live"
	blocking = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	_live_step = "move"
	_live_t = 0.0
	_moved = 0.0
	_last_pos = game.player.position
	_kills_start = int(game.run.stats.get("kills", 0))
	_tip("Движение", "Положите палец на левую половину экрана и ведите — герой пойдёт." if _touch else "Идите клавишами WASD или стрелками.")
	_hint_pos = Vector2(0.18, 0.78)
	visible = true


func skip_all() -> void:
	Settings.set_value("tutorial_shop_done", true)
	Settings.set_value("tutorial_done", true)
	_end()


func _end() -> void:
	mode = ""
	blocking = false
	_live_step = ""
	visible = false
	_tip_title = ""
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	finished.emit()


# ---- магазин ---------------------------------------------------------------------------
func _show_shop_step() -> void:
	var s: Dictionary = SHOP_STEPS[step]
	_set_card(str(s.title), str(s.text), "%d/%d" % [step + 1, SHOP_STEPS.size()], "Понятно" if step == SHOP_STEPS.size() - 1 else "Дальше")
	var rects: Dictionary = game.shop_ui.tutorial_rects()
	_highlight = rects.get(s.rect, Rect2())
	if s.rect == "cards":
		_highlight.size.y *= 0.5               # подсвечиваем верхний ряд, чтобы карточка-подсказка не закрывала нижний
	_card_place("top" if _highlight.get_center().y > size.y * 0.55 else "bottom")
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	Sfx.play("tutorial")


func _on_next() -> void:
	Sfx.play("click")
	if mode == "shop":
		step += 1
		if step >= SHOP_STEPS.size():
			Settings.set_value("tutorial_shop_done", true)
			_highlight = Rect2()
			_end()
		else:
			_show_shop_step()
	elif mode == "controls":
		_start_live()


func _set_card(title: String, text: String, count: String, next_text: String) -> void:
	_card.visible = true
	_title.text = title
	_text.text = text
	_count.text = count
	_next.text = next_text
	_skip.visible = true
	_highlight = Rect2()


func _card_place(where: String) -> void:
	size = get_viewport_rect().size
	_card.custom_minimum_size = Vector2(minf(size.x - 60.0, 880.0), 0)
	_card.reset_size()
	await get_tree().process_frame
	_card.reset_size()                         # после первой раскладки высота текста пересчитывается по ширине
	await get_tree().process_frame
	var w := _card.size.x
	var y := 24.0 if where == "top" else maxf(size.y - _card.size.y - 24.0, 24.0)
	_card.position = Vector2((size.x - w) * 0.5, y)


# ---- живые подсказки ------------------------------------------------------------------------
func _tip(title: String, text: String) -> void:
	_tip_title = title
	_tip_text = text
	Sfx.play("tutorial")


func combat_tick(dt: float) -> void:
	if mode != "live" or game.state != game.St.COMBAT:
		return
	_t += dt
	_live_t += dt
	var pl: Player = game.player
	_moved += pl.position.distance_to(_last_pos)
	_last_pos = pl.position
	# событие: первый красный телеграф
	if not _tele_shown and _live_step != "medkit":
		for e in game.enemies:
			if e.state == Enemy.S.TELEGRAPH:
				_tele_shown = true
				_tele_t = 6.0
				_prev_tip = [_tip_title, _tip_text]
				_tip("Красный круг — враг сейчас ударит", "Отойдите из круга, пока он не заполнился — тогда удар не попадёт. Круги и линии показывают, куда придёт атака.")
				break
	if _tele_t > 0.0:
		_tele_t -= dt
		if _tele_t <= 0.0:
			_tip_title = _prev_tip[0]
			_tip_text = _prev_tip[1]
	match _live_step:
		"move":
			if _moved > 160.0:
				Sfx.play("step_ok")
				_live_step = "shoot"
				_live_t = 0.0
				_kills_start = int(game.run.stats.get("kills", 0))
				_tip("Стрельба", "Левый палец — идти, правый — целиться и стрелять: держите палец на ПРАВОЙ половине экрана и ведите к врагу." if _touch else "Наведите мышь на врага и держите ЛКМ — герой стреляет только пока вы целитесь.")
				_hint_pos = Vector2(0.82, 0.78)
			elif _live_t > 25.0:
				_live_step = "shoot"
				_live_t = 0.0
		"shoot":
			if int(game.run.stats.get("kills", 0)) - _kills_start >= 2 or _live_t > 30.0:
				Sfx.play("step_ok")
				_live_step = "medkit"
				_live_t = 0.0
				_tip_title = ""
				_hint_pos = Vector2(-1, -1)
		"medkit":
			if not _medkit_asked and (pl.hp < pl.max_hp * 0.85 or _live_t > 40.0):
				_medkit_asked = true
				_live_t = 0.0
				_tip("Аптечка", "Здоровье упало — нажмите кнопку с красным крестом (она подсвечена)." if _touch else "Здоровье упало — нажмите F.")
			if _medkit_asked and (pl.medkit.active or pl.medkit.stock == 0):
				Sfx.play("step_ok")
				_medkit_done = true
				_medkit_asked = false
				_live_step = ""
				_tip("Аптечка применена", "Лечит 20% максимума ХП за 4 секунды; одновременно действует одна. Ещё аптечки можно купить в магазине — неиспользованные не пропадают.")
				_live_t = 0.0
			elif _medkit_asked and _live_t > 14.0:
				_live_step = ""
				_tip_title = ""
		"":
			if _live_t > 7.0:
				_tip_title = ""
	if _tele_t <= 0.0 and _live_step == "" and _tip_title == "" and _tele_shown:
		pass


var _prev_tip := ["", ""]


func on_wave_won() -> void:
	if mode == "live":
		Settings.set_value("tutorial_done", true)
		_tip_title = ""
		_end()


# ---- рисование ----------------------------------------------------------------------------------
func _process(delta: float) -> void:
	if visible:
		position = Vector2.ZERO
		size = get_viewport_rect().size
		queue_redraw()


func _draw() -> void:
	var f := ThemeDB.fallback_font
	var vs := size
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 5.0)
	if mode == "shop" and _highlight.size.x > 0.0:
		var h := _highlight.grow(6.0)
		var dim := Color(0, 0, 0, 0.72)
		draw_rect(Rect2(0, 0, vs.x, h.position.y), dim)
		draw_rect(Rect2(0, h.end.y, vs.x, vs.y - h.end.y), dim)
		draw_rect(Rect2(0, h.position.y, h.position.x, h.size.y), dim)
		draw_rect(Rect2(h.end.x, h.position.y, vs.x - h.end.x, h.size.y), dim)
		draw_rect(h, Color(1.0, 0.6, 0.15, 0.6 + 0.4 * pulse), false, 4.0)
		return
	if mode == "controls":
		_draw_controls_map(f, vs, pulse)
		return
	if mode == "live":
		_draw_live(f, vs, pulse)


func _draw_controls_map(f: Font, vs: Vector2, pulse: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.62))
	if _touch:
		var sm := UiKit.safe_margins(get_viewport())
		# левая и правая зоны
		var lz := Rect2(14, 90, vs.x * 0.5 - 24, vs.y - 110)
		var rz := Rect2(vs.x * 0.5 + 10, 90, vs.x * 0.5 - 24, vs.y - 110)
		draw_rect(lz, Color(0.62, 0.84, 0.93, 0.12))
		draw_rect(lz, Color(0.62, 0.84, 0.93, 0.8), false, 3.0)
		draw_rect(rz, Color(1.0, 0.55, 0.2, 0.12))
		draw_rect(rz, Color(1.0, 0.55, 0.2, 0.8), false, 3.0)
		draw_string(f, Vector2(lz.position.x, lz.position.y + 40), "ЛЕВЫЙ ПАЛЕЦ", HORIZONTAL_ALIGNMENT_CENTER, lz.size.x, 30, Color(0.7, 0.9, 1.0))
		draw_string(f, Vector2(lz.position.x, lz.position.y + 72), "движение", HORIZONTAL_ALIGNMENT_CENTER, lz.size.x, 24, Color.WHITE)
		draw_string(f, Vector2(rz.position.x, rz.position.y + 40), "ПРАВЫЙ ПАЛЕЦ", HORIZONTAL_ALIGNMENT_CENTER, rz.size.x, 30, Color(1.0, 0.75, 0.4))
		draw_string(f, Vector2(rz.position.x, rz.position.y + 72), "прицел и огонь (держать)", HORIZONTAL_ALIGNMENT_CENTER, rz.size.x, 24, Color.WHITE)
		# схематичные стики
		var lc := Vector2(lz.get_center().x, lz.get_center().y + 20)
		draw_arc(lc, 80.0, 0.0, TAU, 40, Color(1, 1, 1, 0.7), 4.0)
		draw_circle(lc + Vector2(40, -30) * pulse, 36.0, Color(0.62, 0.84, 0.93, 0.7))
		var rc := Vector2(rz.get_center().x - 60, rz.get_center().y + 20)
		draw_arc(rc, 80.0, 0.0, TAU, 40, Color(1, 1, 1, 0.7), 4.0)
		draw_circle(rc + Vector2(-30, -40) * pulse, 36.0, Color(1.0, 0.6, 0.25, 0.75))
		# кнопки
		if game.touch != null:
			var defs: Dictionary = game.touch._btn_defs()
			var names := {"medkit": "Аптечка", "reload": "Перезарядка", "pause": "Пауза"}
			for k in defs:
				var c: Vector2 = defs[k].c
				var r: float = defs[k].r
				draw_arc(c, r + 8.0 + 4.0 * pulse, 0.0, TAU, 32, Color(1.0, 0.85, 0.3), 4.0)
				draw_string(f, Vector2(c.x - r - 270.0, c.y + 8.0), names[k], HORIZONTAL_ALIGNMENT_RIGHT, 250.0, 24, Color(1.0, 0.9, 0.5))
	else:
		draw_string(f, Vector2(0, vs.y * 0.3), "WASD / стрелки — движение", HORIZONTAL_ALIGNMENT_CENTER, vs.x, 36, Color.WHITE)
		draw_string(f, Vector2(0, vs.y * 0.3 + 52), "Мышь + ЛКМ — прицел и огонь", HORIZONTAL_ALIGNMENT_CENTER, vs.x, 30, Color(1.0, 0.8, 0.5))
		draw_string(f, Vector2(0, vs.y * 0.3 + 100), "R — перезарядка · F — аптечка · Esc — пауза", HORIZONTAL_ALIGNMENT_CENTER, vs.x, 28, Color(0.7, 0.9, 1.0))


func _draw_live(f: Font, vs: Vector2, pulse: float) -> void:
	# карточка-подсказка сверху (не мешает управлению: нажатия проходят сквозь)
	if _tip_title != "":
		var w := minf(vs.x - 80.0, 860.0)
		var x := (vs.x - w) * 0.5
		var y := 108.0
		draw_rect(Rect2(x, y, w, 118), Color(0.06, 0.08, 0.06, 0.88))
		draw_rect(Rect2(x, y, w, 118), Color(1.0, 0.6, 0.15), false, 3.0)
		draw_string(f, Vector2(x + 16, y + 34), _tip_title, HORIZONTAL_ALIGNMENT_LEFT, w - 32, 26, Color(1.0, 0.75, 0.4))
		draw_multiline_string(f, Vector2(x + 16, y + 66), _tip_text, HORIZONTAL_ALIGNMENT_LEFT, w - 32, 21, 3, Color.WHITE)
	if not _touch:
		return
	# подсветка зоны/кнопки
	var sm := UiKit.safe_margins(get_viewport())
	if _live_step == "move":
		_draw_finger(Vector2(150.0 + sm.position.x, vs.y - 150.0 - sm.size.y), pulse, Color(0.62, 0.84, 0.93), Vector2(1, -0.6))
	elif _live_step == "shoot":
		_draw_finger(Vector2(vs.x - 200.0 - sm.size.x, vs.y - 150.0 - sm.size.y), pulse, Color(1.0, 0.6, 0.25), Vector2(-1, -0.6))
	elif _live_step == "medkit" and _medkit_asked and game.touch != null:
		var d: Dictionary = game.touch._btn_defs()
		var c: Vector2 = d["medkit"].c
		draw_arc(c, d["medkit"].r + 10.0 + 8.0 * pulse, 0.0, TAU, 36, Color(1.0, 0.85, 0.3), 6.0)
		draw_string(f, Vector2(c.x - 260.0, c.y + 8.0), "нажмите!", HORIZONTAL_ALIGNMENT_RIGHT, 220.0, 28, Color(1.0, 0.9, 0.5))


## Анимированный «палец»: кольцо стика и точка, которая ведётся в указанную сторону.
func _draw_finger(center: Vector2, pulse: float, col: Color, dir: Vector2) -> void:
	draw_arc(center, 90.0, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.9), 5.0)
	var p := center + dir.normalized() * 55.0 * pulse
	draw_circle(p, 34.0, Color(col.r, col.g, col.b, 0.55))
	draw_circle(p, 12.0, Color(1, 1, 1, 0.9))
	draw_line(center, center + dir.normalized() * 75.0, Color(1, 1, 1, 0.7), 4.0)


# ---- для тестов/снимков ---------------------------------------------------------------------------
func debug_show(name: String) -> void:
	_touch = Settings.touch_ui_enabled() if game.touch == null else (game.touch.visible or Settings.data.touch_ui == "on")
	match name:
		"controls": begin_controls(true)
		"move", "shoot", "medkit", "tele":
			mode = "live"
			blocking = false
			visible = true
			_card.visible = false
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			match name:
				"move":
					_live_step = "move"
					_tip("Движение", "Положите палец на левую половину экрана и ведите — герой пойдёт." if _touch else "Идите клавишами WASD или стрелками.")
				"shoot":
					_live_step = "shoot"
					_tip("Стрельба", "Левый палец — идти, правый — целиться и стрелять: держите палец на ПРАВОЙ половине экрана и ведите к врагу." if _touch else "Наведите мышь на врага и держите ЛКМ — герой стреляет только пока вы целитесь.")
				"medkit":
					_live_step = "medkit"
					_medkit_asked = true
					_tip("Аптечка", "Здоровье упало — нажмите кнопку с красным крестом (она подсвечена).")
				"tele":
					_live_step = ""
					_tip("Красный круг — враг сейчас ударит", "Отойдите из круга, пока он не заполнился — тогда удар не попадёт. Круги и линии показывают, куда придёт атака.")
		_:
			if name.begins_with("shop"):
				mode = "shop"
				step = int(name.trim_prefix("shop"))
				blocking = true
				_show_shop_step()
