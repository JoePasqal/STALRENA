class_name BonusCaseScreen
extends Control
## Бонус-кейс: закрытый кейс → «Открыть» → 3 карточки рубашкой вверх → игрок выбирает одну → две другие по очереди
## плавно переворачиваются, последней — выбранная. Выбор применяется и сохраняется сразу в момент нажатия.

signal closed

var game
var cards: Array[BonusCard] = []
var state := "idle"          # idle | closed | choosing | revealing | done
var _title: Label
var _sub: Label
var _btn: Button
var _lid := 0.0
var _chosen := -1
var _result := {}
var _anim_speed := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UiKit.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_title = UiKit.label("", 40, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_title)
	_sub = UiKit.label("", 22, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_sub)
	_btn = UiKit.button("Открыть кейс", Vector2(300, 64), 26)
	_btn.pressed.connect(_on_btn)
	add_child(_btn)


func open() -> void:
	if not BonusService.has_case(game.run):
		return
	state = "closed"
	_lid = 0.0
	_chosen = -1
	visible = true
	_clear_cards()
	_title.text = "Кейс бонуса!"
	_sub.text = "Пройдена %d-я волна. Откройте кейс и выберите одну карточку: бонус действует следующие %d волны." % [int(game.run.bonus_case.wave), BonusService.duration()]
	_btn.text = "Открыть кейс"
	_btn.visible = true
	Sfx.play("reveal")
	_layout()


func _clear_cards() -> void:
	for c in cards:
		c.queue_free()
	cards.clear()


func _process(_d: float) -> void:
	if visible:
		position = Vector2.ZERO
		size = get_viewport_rect().size
		_layout()
		queue_redraw()


func _layout() -> void:
	var vs := size
	_title.position = Vector2(0, 26)
	_title.size = Vector2(vs.x, 50)
	_sub.position = Vector2(60, 84)
	_sub.size = Vector2(vs.x - 120, 30)
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_btn.position = Vector2((vs.x - _btn.size.x) * 0.5, vs.y - 100)
	var cw := minf(250.0, (vs.x - 200.0) / 3.0)
	var ch := minf(cw * 1.5, vs.y - 230.0)
	cw = ch / 1.5
	for i in cards.size():
		var x := vs.x * 0.5 + (i - 1) * (cw + 40.0) - cw * 0.5
		cards[i].size = Vector2(cw, ch)
		cards[i].position = Vector2(x, 140.0)
		cards[i].pivot_offset = cards[i].size * 0.5


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.03, 0.97))
	if state == "closed":
		_draw_case()


func _draw_case() -> void:
	var c := Vector2(size.x * 0.5, size.y * 0.5 + 10)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 300.0)
	draw_circle(c, 150.0 + 14.0 * pulse, Color(1.0, 0.8, 0.3, 0.10 + 0.08 * pulse))
	var key := "ui.bonus_case_open" if _lid > 0.5 else "ui.bonus_case_closed"
	if AssetRegistry.file_exists(key):
		var tex := AssetRegistry.get_texture(key)
		draw_texture_rect(tex, Rect2(c - Vector2(256, 192), Vector2(512, 384)), false)
		return
	# процедурный кейс (заглушка): корпус, крышка с подъёмом, металлические полосы, замок
	var body := Rect2(c.x - 130, c.y - 10, 260, 110)
	draw_rect(body, Color(0.42, 0.28, 0.16))
	draw_rect(body, Color(0.08, 0.06, 0.04), false, 4.0)
	for bx in [-90.0, 90.0]:
		draw_rect(Rect2(c.x + bx - 10, body.position.y, 20, body.size.y), Color(0.55, 0.55, 0.52))
	var lid_y := body.position.y - 55.0 - 70.0 * _lid
	var lid := Rect2(c.x - 134, lid_y, 268, 56)
	draw_rect(lid, Color(0.5, 0.34, 0.2))
	draw_rect(lid, Color(0.08, 0.06, 0.04), false, 4.0)
	for bx in [-90.0, 90.0]:
		draw_rect(Rect2(c.x + bx - 10, lid.position.y, 20, lid.size.y), Color(0.55, 0.55, 0.52))
	if _lid < 0.2:
		draw_circle(Vector2(c.x, body.position.y), 16.0, Color(1.0, 0.85, 0.3))
		draw_rect(Rect2(c.x - 5, body.position.y - 2, 10, 20), Color(0.2, 0.15, 0.05))
	else:
		draw_circle(Vector2(c.x, body.position.y - 10), 60.0 * _lid, Color(1.0, 0.9, 0.5, 0.45 * _lid))


func _on_btn() -> void:
	if state == "closed":
		state = "opening"
		_btn.visible = false
		Sfx.play("case_open")
		var tw := create_tween()
		tw.tween_property(self, "_lid", 1.0, 0.55 / _anim_speed)
		tw.tween_callback(_spawn_cards)
	elif state == "done":
		state = "idle"
		visible = false
		_clear_cards()
		closed.emit()


func _spawn_cards() -> void:
	state = "choosing"
	_title.text = "Выберите одну карточку"
	_sub.text = "Что внутри — неизвестно. Остальные две будут показаны после выбора."
	var opts: Array = game.run.bonus_case.options
	for i in opts.size():
		var c := BonusCard.new()
		c.setup(i, str(opts[i]))
		c.size = Vector2(200, 300)
		c.tapped.connect(_on_card)
		add_child(c)
		cards.append(c)
		c.modulate.a = 0.0
	_layout()
	for i in cards.size():
		var tw := create_tween()
		tw.tween_interval(0.12 * i / _anim_speed)
		tw.tween_property(cards[i], "modulate:a", 1.0, 0.3 / _anim_speed)
		tw.tween_callback(func(): cards[i].enabled = true)
	_lid = 0.0
	queue_redraw()


func _on_card(card: BonusCard) -> void:
	if state != "choosing":
		return
	state = "revealing"
	_chosen = card.index
	for c in cards:
		c.enabled = false
	_result = BonusService.pick(game.run, _chosen)          # применяется и сохраняется немедленно
	Session.save()
	Sfx.play("click")
	_title.text = "Вы выбрали карточку %d" % (_chosen + 1)
	_sub.text = "Смотрим, что было в остальных…"
	var order: Array = []
	for i in cards.size():
		if i != _chosen:
			order.append(i)
	var tw := create_tween()
	tw.tween_interval(0.4 / _anim_speed)
	for i in order:
		tw.tween_callback(func(): Sfx.play("flip"))
		tw.tween_property(cards[i], "flip", 1.0, 0.6 / _anim_speed).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_property(cards[i], "dim", 1.0, 0.8 / _anim_speed)
		tw.tween_interval(0.35 / _anim_speed)
	tw.tween_callback(func():
		Sfx.play("flip")
		_sub.text = "…и ваша карточка!")
	tw.tween_property(cards[_chosen], "flip", 1.0, 0.8 / _anim_speed).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(_finish)
	tw.tween_property(cards[_chosen], "glow", 1.0, 0.4 / _anim_speed)


func _finish() -> void:
	state = "done"
	Sfx.play("levelup")
	var def: Dictionary = GameData.bonuses[str(_result.id)]
	_title.text = "Бонус: %s" % def.name
	_sub.text = "%s. Действует на следующие %d волны." % [def.desc, BonusService.duration()]
	_btn.text = "Забрать"
	_btn.visible = true


func debug_pick_and_fast(index: int) -> void:
	_anim_speed = 50.0
	if state == "closed":
		_on_btn()
	await get_tree().create_timer(0.1).timeout
	if state == "choosing":
		_on_card(cards[index])
