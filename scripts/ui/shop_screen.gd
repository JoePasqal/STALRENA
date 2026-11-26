class_name ShopScreen
extends Control
## Магазин между волнами: шесть карточек, обновление за 10, замок, уровень магазина,
## мастерство, сборка (оружие/броня/модули/части) и продажа. Все изменения — только через
## ShopService/Inventory; после каждой транзакции — сохранение.

signal start_requested
signal menu_requested

var game
var _tab := 0
var _cards_box: GridContainer
var _right_box: VBoxContainer
var _bottom_box: HBoxContainer
var _start_box: VBoxContainer
var _top_label: Label
var _coins_label: Label
var _level_label: Label
var _toast: Label
var _toast_t := 0.0
var _busy := false
var _hint: Label
var _confirm_menu: ConfirmationDialog

const TAB_NAMES := ["Сборка", "Модули", "Части"]


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.07, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 16)
	root.add_theme_constant_override("margin_right", 16)
	root.add_theme_constant_override("margin_top", 10)
	root.add_theme_constant_override("margin_bottom", 10)
	add_child(root)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	root.add_child(vb)
	# верхняя панель
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)
	vb.add_child(top)
	_top_label = UiKit.label("", 24, UiKit.ACCENT)
	_top_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_label.clip_text = true
	_top_label.custom_minimum_size = Vector2(100, 0)
	top.add_child(_top_label)
	_coins_label = UiKit.label("", 28, Color(1.0, 0.9, 0.5))
	top.add_child(_coins_label)
	_level_label = UiKit.label("", 20, UiKit.FRIENDLY)
	top.add_child(_level_label)
	var mb0 := UiKit.button("Меню", Vector2(90, 44), 18)
	mb0.pressed.connect(func(): _confirm_menu.popup_centered())
	top.add_child(mb0)
	# середина
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 12)
	vb.add_child(mid)
	_cards_box = GridContainer.new()
	_cards_box.columns = 3
	_cards_box.add_theme_constant_override("h_separation", 10)
	_cards_box.add_theme_constant_override("v_separation", 10)
	_cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(_cards_box)
	var rp := PanelContainer.new()
	rp.custom_minimum_size = Vector2(380, 0)
	mid.add_child(rp)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	rp.add_child(rv)
	var tabs := HBoxContainer.new()
	rv.add_child(tabs)
	for i in TAB_NAMES.size():
		var tb := UiKit.button(TAB_NAMES[i], Vector2(0, 44), 20)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.pressed.connect(func(): _tab = i; refresh())
		tabs.add_child(tb)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(sc)
	_right_box = VBoxContainer.new()
	_right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_box.add_theme_constant_override("separation", 6)
	sc.add_child(_right_box)
	_start_box = VBoxContainer.new()
	rv.add_child(_start_box)
	# нижняя панель
	_bottom_box = HBoxContainer.new()
	_bottom_box.add_theme_constant_override("separation", 8)
	vb.add_child(_bottom_box)
	_hint = UiKit.label("", 16, UiKit.MUTED)
	vb.add_child(_hint)
	_toast = UiKit.label("", 22, UiKit.GOOD, HORIZONTAL_ALIGNMENT_CENTER)
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.position = Vector2(0, 0)
	add_child(_toast)
	_confirm_menu = ConfirmationDialog.new()
	_confirm_menu.dialog_text = "Выйти в меню? Забег сохранён и его можно продолжить."
	_confirm_menu.ok_button_text = "В меню"
	_confirm_menu.cancel_button_text = "Остаться"
	_confirm_menu.confirmed.connect(func(): menu_requested.emit())
	add_child(_confirm_menu)


func open() -> void:
	visible = true
	_busy = false
	refresh()


func close() -> void:
	visible = false


func _process(delta: float) -> void:
	if visible:
		position = Vector2.ZERO
		size = get_viewport_rect().size
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			_toast.text = ""
	if visible:
		_toast.size = Vector2(size.x, 30)
		_toast.position = Vector2(0, size.y - 92.0)


func toast(text: String, good: bool = true) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", UiKit.GOOD if good else UiKit.BAD)
	_toast_t = 2.6


func _run() -> RunState:
	return game.run


# ---- сборка интерфейса ----------------------------------------------------------
func refresh() -> void:
	var run := _run()
	if run == null:
		return
	var gw := run.next_wave()
	var sec := run.sector_of(gw)
	var boss := run.is_boss_wave(gw)
	_top_label.text = "МАГАЗИН · Следующая: волна %d (сектор %d, %d/%d)%s" % [gw, sec, run.local_wave_of(gw), int(GameData.B.waves.sector_length), "  · БОСС" if boss else ""]
	_coins_label.text = "Монеты: %d" % run.coins
	_level_label.text = "Магазин %d/%d · ячеек %d" % [run.shop_level, GameData.max_shop_level(), GameData.module_slots(run.shop_level)]
	_build_cards(run)
	_build_right(run)
	_build_bottom(run)
	_update_hint(run)


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _build_cards(run: RunState) -> void:
	_clear(_cards_box)
	for o in run.offers:
		_cards_box.add_child(_make_card(run, o))


func _rank_col(rank: int) -> Color:
	return UiKit.RANK_COLORS[clampi(rank, 1, 5) - 1]


func _make_card(run: RunState, o: Dictionary) -> Control:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(200, 170)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var st := ShopService.offer_status(run, o)
	var rank_for_color := int(o.target_rank) if o.kind == "part" else 1
	var border := _rank_col(rank_for_color) if o.kind == "part" else Color(0.34, 0.4, 0.32)
	var dim: bool = o.bought or (not st.ok)
	pc.add_theme_stylebox_override("panel", UiKit.box(Color(0.13, 0.15, 0.13, 0.7 if dim else 1.0), 10, border if not dim else Color(0.22, 0.24, 0.22), 3))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	pc.add_child(v)
	if o.kind == "complete":
		v.add_child(UiKit.label("Сборка завершена", 22, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(_small("Всё доступное снаряжение собрано. Развивайтесь через мастерство (V ранг) и модули.", UiKit.MUTED))
		return pc
	if o.bought:
		v.add_child(UiKit.label("Куплено", 26, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(UiKit.label(_offer_title(o), 18, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
		return pc
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	var icon := TextureRect.new()
	icon.texture = AssetRegistry.get_texture(_offer_icon(o))
	icon.custom_minimum_size = Vector2(84, 84)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(icon)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tv)
	var title := UiKit.label(_offer_title(o), 22)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(60, 0)
	tv.add_child(title)
	var sub := UiKit.label(_offer_subtitle(o), 16, border if o.kind == "part" else UiKit.MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(60, 0)
	tv.add_child(sub)
	var desc := _small(_offer_desc(run, o), Color(0.8, 0.84, 0.78))
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc.max_lines_visible = 4
	desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	desc.tooltip_text = _offer_desc(run, o)
	desc.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(desc)
	var btn := UiKit.button("", Vector2(0, 50), 20)
	if not st.ok:
		btn.text = str(st.reason)
		btn.disabled = true
	elif run.coins < int(o.price):
		btn.text = "Не хватает · %d" % int(o.price)
		btn.disabled = true
	else:
		btn.text = "Купить · %d" % int(o.price)
		var uid := int(o.uid)
		btn.pressed.connect(func():
			btn.disabled = true           # защита от второго быстрого тапа
			_buy(uid))
	v.add_child(btn)
	return pc


func _small(text: String, col: Color = UiKit.TEXT) -> Label:
	var l := UiKit.label(text, 16, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(0, 40)
	return l


func _offer_icon(o: Dictionary) -> String:
	match o.kind:
		"base", "part":
			return ("icon.weapon." if o.type == "weapon" else "icon.armor.") + str(o.id)
		"module":
			return "icon.module." + str(o.id)
	return "icon.parts"


func _offer_title(o: Dictionary) -> String:
	match o.kind:
		"base", "part", "module":
			return GameData.item_name(str(o.type), str(o.id))
	return "—"


func _offer_subtitle(o: Dictionary) -> String:
	match o.kind:
		"base":
			return ("Оружие" if o.type == "weapon" else "Броня") + " · база"
		"part":
			return "Часть → ранг %s" % GameData.rank_roman(int(o.target_rank))
		"module":
			return "Модуль · набор «%s»" % GameData.sets[GameData.modules[o.id].set_id].name
	return ""


func _offer_desc(run: RunState, o: Dictionary) -> String:
	match o.kind:
		"base":
			if o.type == "weapon":
				return ItemText.weapon_line(str(o.id), 1)
			return ItemText.armor_line(str(o.id), 1)
		"part":
			var have := run.part_count(o.fam, int(o.target_rank))
			var need := GameData.parts_required(int(o.target_rank))
			var nm := GameData.item_name(str(o.type), str(o.id))
			return "%s: %s → %s\nСобрано %d/%d (после покупки %d/%d)" % [nm, GameData.rank_name(int(o.target_rank) - 1), GameData.rank_name(int(o.target_rank)), have, need, have + 1, need]
		"module":
			return ItemText.module_line(run, str(o.id))
	return ""


func _buy(uid: int) -> void:
	if _busy:
		return
	_busy = true
	var run := _run()
	var res := ShopService.buy(run, uid)
	if res.ok:
		Sfx.play("buy")
		Session.save()
		var o: Dictionary = run.last_purchase
		var msg := "Куплено: %s" % GameData.item_name(str(o.type), str(o.id)) if str(o.kind) != "complete" else "Куплено"
		if res.get("ranked_up", false):
			msg = "Ранг собран: %s → %s!" % [GameData.item_name(str(o.type), str(o.id)), GameData.rank_roman(int(res.rank))]
		toast(msg, true)
	else:
		Sfx.play("deny")
		toast(str(res.reason), false)
	_busy = false
	refresh()


# ---- правая панель -------------------------------------------------------------
func _build_right(run: RunState) -> void:
	_clear(_right_box)
	match _tab:
		0: _tab_build(run)
		1: _tab_modules(run)
		2: _tab_parts(run)


func _tab_build(run: RunState) -> void:
	var ps := StatCalc.player_stats(run)
	_right_box.add_child(UiKit.label("Оружие (выберите активное)", 20, UiKit.ACCENT))
	for id in GameData.weapon_ids:
		if not run.weapons.has(id):
			continue
		var e: Dictionary = run.weapons[id]
		var b := UiKit.button("%s %s%s" % [GameData.weapons[id].name, GameData.rank_roman(int(e.rank)), "  ✔" if id == run.equipped_weapon else ""], Vector2(0, 44), 19)
		b.add_theme_color_override("font_color", _rank_col(int(e.rank)))
		var wid: String = id
		b.pressed.connect(func(): _equip_weapon(wid))
		_right_box.add_child(b)
	var ws := StatCalc.weapon_stats(run, run.equipped_weapon)
	var dps := StatCalc.weapon_dps(ws)
	var line := "Урон %.1f%s · темп %.1f/с · магазин %d\nПерезарядка %.2f с · дальность %d\nКрит %d%% ×%.2f · ~%.0f урона/с" % [ws.damage, " ×%d" % int(ws.pellets) if int(ws.pellets) > 1 else "", ws.fire_rate, int(ws.magazine), ws.reload_time, int(ws.range), int(round(ws.crit_chance * 100.0)), ws.crit_multiplier, dps]
	_right_box.add_child(_small(line, Color(0.8, 0.84, 0.78)))
	_right_box.add_child(UiKit.label("Броня (одна, без снижения урона)", 20, UiKit.ACCENT))
	var nb := UiKit.button("Без брони%s" % ("  ✔" if run.equipped_armor == "" else ""), Vector2(0, 44), 19)
	nb.pressed.connect(func(): _equip_armor(""))
	_right_box.add_child(nb)
	for id in GameData.armor_ids:
		if not run.armors.has(id):
			continue
		var e2: Dictionary = run.armors[id]
		var b2 := UiKit.button("%s %s · +%d ХП%s" % [GameData.armors[id].name, GameData.rank_roman(int(e2.rank)), int(GameData.armors[id].hp_by_rank[int(e2.rank) - 1]), "  ✔" if id == run.equipped_armor else ""], Vector2(0, 44), 19)
		b2.add_theme_color_override("font_color", _rank_col(int(e2.rank)))
		var aid: String = id
		b2.pressed.connect(func(): _equip_armor(aid))
		_right_box.add_child(b2)
	_right_box.add_child(_small("Макс. ХП %d · скорость %d%% · контактная защита %.2f с" % [int(round(ps.max_hp)), int(round(StatCalc.move_speed_multiplier(run) * 100.0)), ps.contact_guard], Color(0.8, 0.84, 0.78)))


func _equip_weapon(id: String) -> void:
	var r := Inventory.equip_weapon(_run(), id)
	if r.ok:
		Session.save()
	else:
		toast(str(r.reason), false)
	refresh()


func _equip_armor(id: String) -> void:
	var r := Inventory.equip_armor(_run(), id)
	if r.ok:
		Session.save()
	else:
		toast(str(r.reason), false)
	refresh()


func _tab_modules(run: RunState) -> void:
	var slots := GameData.module_slots(run.shop_level)
	_right_box.add_child(UiKit.label("Модули: %d/%d ячеек" % [run.modules.size(), slots], 20, UiKit.ACCENT))
	var ids: Array = run.modules.keys()
	ids.sort()
	for i in slots:
		if i < ids.size():
			var id: String = ids[i]
			var m: Dictionary = GameData.modules[id]
			var hb := HBoxContainer.new()
			var l := _small("%s  ур.%d/%d\n%s" % [m.name, int(run.modules[id].level), int(m.max_level), ItemText.module_effect(id, int(run.modules[id].level))], UiKit.TEXT)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hb.add_child(l)
			var refund := int(floor(int(run.modules[id].paid) * float(GameData.B.shop.sell_refund_fraction)))
			var sb := UiKit.button("Продать +%d" % refund, Vector2(130, 46), 17)
			var mid: String = id
			sb.pressed.connect(func(): _sell_module(mid))
			hb.add_child(sb)
			_right_box.add_child(hb)
		else:
			_right_box.add_child(UiKit.label("— свободная ячейка —", 18, UiKit.MUTED))
	_right_box.add_child(UiKit.label("Наборы (нужны 3 РАЗНЫХ модуля)", 20, UiKit.ACCENT))
	var active := StatCalc.active_set_ids(run)
	for sid in GameData.sets:
		var s: Dictionary = GameData.sets[sid]
		var have := 0
		var names: Array = []
		for req in s.requires:
			var ok: bool = run.modules.has(req)
			if ok:
				have += 1
			names.append(("✔ " if ok else "· ") + str(GameData.modules[req].name))
		var col := UiKit.GOOD if active.has(sid) else UiKit.MUTED
		var l2 := _small("%s %d/3 — %s\n%s" % [s.name, have, ItemText.set_bonus(s), "  ".join(names)], col)
		_right_box.add_child(l2)


func _sell_module(id: String) -> void:
	var r := Inventory.sell_module(_run(), id)
	if r.ok:
		Sfx.play("buy")
		Session.save()
		toast("Продано, +%d монет" % int(r.refund), true)
	else:
		toast(str(r.reason), false)
	refresh()


func _tab_parts(run: RunState) -> void:
	_right_box.add_child(UiKit.label("Ветки и ранги", 20, UiKit.ACCENT))
	for type in ["weapon", "armor"]:
		var ids: Array = GameData.weapon_ids if type == "weapon" else GameData.armor_ids
		var src: Dictionary = run.weapons if type == "weapon" else run.armors
		for id in ids:
			if not src.has(id):
				continue
			var e: Dictionary = src[id]
			var rank := int(e.rank)
			var fam := GameData.family_key(type, id)
			var txt := "%s · ранг %s «%s»" % [GameData.item_name(type, id), GameData.rank_roman(rank), GameData.rank_name(rank)]
			if rank < 5:
				txt += "\nДо %s: %d/%d частей" % [GameData.rank_roman(rank + 1), run.part_count(fam, rank + 1), GameData.parts_required(rank + 1)]
			else:
				txt += "\nV ранг. Мастерство ×%d" % int(e.mastery)
			_right_box.add_child(_small(txt, _rank_col(rank)))
			if rank < 5 and run.part_count(fam, rank + 1) > 0:
				var prices := run.part_prices(fam, rank + 1)
				var refund := int(floor(int(prices[prices.size() - 1]) * float(GameData.B.shop.sell_refund_fraction)))
				var sb := UiKit.button("Продать часть +%d" % refund, Vector2(0, 42), 17)
				var tr := rank + 1
				sb.pressed.connect(func(): _sell_part(fam, tr))
				_right_box.add_child(sb)


func _sell_part(fam: String, target: int) -> void:
	var r := Inventory.sell_part(_run(), fam, target)
	if r.ok:
		Sfx.play("buy")
		Session.save()
		toast("Часть продана, +%d" % int(r.refund), true)
	else:
		toast(str(r.reason), false)
	refresh()


# ---- нижняя панель -------------------------------------------------------------
func _build_bottom(run: RunState) -> void:
	_clear(_bottom_box)
	var rc := int(GameData.B.shop.refresh_cost)
	var rf := ShopService.can_refresh(run)
	var rb := UiKit.button("Обновить всё · %d" % rc, Vector2(0, 56), 18)
	rb.disabled = not rf.ok
	if not rf.ok:
		rb.tooltip_text = str(rf.reason)
	rb.pressed.connect(_refresh_pressed)
	_bottom_box.add_child(rb)
	var lk := UiKit.button("Замок: ВКЛ (набор сохранится)" if run.shop_locked else "Сохранить предложения", Vector2(0, 56), 18)
	lk.pressed.connect(func():
		ShopService.set_lock(_run(), not _run().shop_locked)
		Session.save()
		refresh())
	_bottom_box.add_child(lk)
	var up := ShopService.upgrade_status(run)
	var ub := UiKit.button("", Vector2(0, 56), 18)
	if up.get("max", false):
		ub.text = "Магазин: максимум"
		ub.disabled = true
	else:
		ub.text = "Повысить магазин · %d" % int(up.cost)
		ub.disabled = not up.ok
		if not up.ok:
			ub.tooltip_text = str(up.reason)
			ub.text = "Магазин ↑ %d (%s)" % [int(up.cost), str(up.reason)] if str(up.reason).begins_with("Нужно") else ub.text
	ub.pressed.connect(func():
		var r := ShopService.upgrade_shop(_run())
		if r.ok:
			Sfx.play("buy")
			Session.save()
			toast("Уровень магазина %d. Новые предложения — после обновления." % int(r.level), true)
		else:
			toast(str(r.reason), false)
		refresh())
	_bottom_box.add_child(ub)
	# мастерство
	var mc := int(GameData.B.shop.mastery.cost)
	var mw := Inventory.mastery_status(run, "weapon")
	var ma := Inventory.mastery_status(run, "armor")
	var wb := UiKit.button("Мастерство оружия · %d" % mc, Vector2(0, 56), 18)
	wb.disabled = not mw.ok
	wb.tooltip_text = str(mw.get("reason", ""))
	wb.pressed.connect(func(): _mastery("weapon"))
	_bottom_box.add_child(wb)
	var ab := UiKit.button("Мастерство брони · %d" % mc, Vector2(0, 56), 18)
	ab.disabled = not ma.ok
	ab.tooltip_text = str(ma.get("reason", ""))
	ab.pressed.connect(func(): _mastery("armor"))
	_bottom_box.add_child(ab)
	for c in _bottom_box.get_children():
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clear(_start_box)
	var go := UiKit.button("Начать волну %d  ▶" % run.next_wave(), Vector2(0, 64), 26)
	go.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6))
	go.pressed.connect(func():
		go.disabled = true
		start_requested.emit())
	_start_box.add_child(go)


func _refresh_pressed() -> void:
	var run := _run()
	var r := ShopService.refresh(run)
	if r.ok:
		Sfx.play("buy")
		Session.save()
		toast("Набор обновлён" + (" · замок снят" if r.lock_cleared else ""), true)
	else:
		Sfx.play("deny")
		toast(str(r.reason), false)
	refresh()


func _mastery(kind: String) -> void:
	var r := Inventory.buy_mastery(_run(), kind)
	if r.ok:
		Sfx.play("buy")
		Session.save()
		toast("Мастерство куплено", true)
	else:
		toast(str(r.reason), false)
	refresh()


func _update_hint(run: RunState) -> void:
	var targets := ShopService.pity_targets(run)
	var parts: Array = []
	if run.shop_locked:
		parts.append("Замок включён: набор останется на следующую волну.")
	if targets.is_empty():
		parts.append("Нет доступных частей для активного оружия/брони на этом уровне магазина — повысьте магазин или займитесь модулями и мастерством.")
	else:
		parts.append("Гарантия части: %d/%d платных обновлений без подходящей части." % [mini(run.pity, int(GameData.B.shop.pity_failed_paid_rerolls_before_guarantee)), int(GameData.B.shop.pity_failed_paid_rerolls_before_guarantee)])
	_hint.text = "  ".join(parts)
