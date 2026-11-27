extends Node
## Ящик с проклятием: расписание (12, 14, 16, 18, 22…; кратные 10 — бафф), обязательный выбор, 1 раунд,
## эффекты (скорость, лечение, огонь, урон, ХП, темп, монеты), коктейли Молотова каждые 20 с, UI-порядок.

var passed := 0
var failed := 0
var game: Node


func check(c: bool, name: String, extra: String = "") -> void:
	if c:
		passed += 1
	else:
		failed += 1
		print("  FAIL: ", name, " ", extra)


func finish_wave(run: RunState, wave: int) -> void:
	run.waves_completed = wave - 1
	run.phase = "combat"
	run.coins_at_wave_start = run.coins
	Economy.complete_wave(run)


func _ready() -> void:
	Settings.data.tutorial_done = true
	Settings.data.tutorial_shop_done = true
	Settings.data.autoaim = true
	GameData.load_all()
	SaveService.base_dir = "user://test_saves"
	DirAccess.make_dir_recursive_absolute("user://test_saves")
	check(GameData.validate().is_empty() and GameData.debuff_ids.size() >= 3, "данные дебаффов валидны")
	# расписание
	var run := RunState.new_run(41)
	var buff_waves: Array = []
	var debuff_waves: Array = []
	for w in range(1, 61):
		finish_wave(run, w)
		var k := BonusService.case_kind(run) if BonusService.has_case(run) else ""
		check(k == BonusService.case_kind_for(w), "волна %d: вид ящика %s" % [w, k])
		if k == "buff":
			buff_waves.append(w)
		elif k == "debuff":
			debuff_waves.append(w)
			var o: Array = run.bonus_case.options
			check(o.size() == 3 and o[0] != o[1] and o[1] != o[2] and o[0] != o[2], "три разных дебаффа (волна %d)" % w)
			check(JSON.stringify(run.bonus_case) == JSON.stringify(BonusService.make_case(41, w, "debuff")), "дебафф-ящик детерминирован")
			var back := RunState.from_dict(JSON.parse_string(JSON.stringify(run.to_dict())))
			check(JSON.stringify(back.bonus_case) == JSON.stringify(run.bonus_case), "ящик не перебрасывается после загрузки")
		if BonusService.has_case(run):
			BonusService.pick(run, 0)             # чтобы не копился неоткрытый ящик
		run.phase = "shop"
	check(buff_waves == [10, 20, 30, 40, 50, 60], "бафф-ящики: каждые 10 волн", str(buff_waves))
	check(debuff_waves == [12, 14, 16, 18, 22, 24, 26, 28, 32, 34, 36, 38, 42, 44, 46, 48, 52, 54, 56, 58], "дебафф-ящики: каждые 2 волны после 10, кроме кратных 10", str(debuff_waves))
	check(not (10 in debuff_waves) and not (20 in debuff_waves) and not (11 in debuff_waves) and not (8 in debuff_waves), "до 10-й волны и на кратных 10 дебаффа нет")
	# срок 1 раунд
	var r := RunState.new_run(5)
	finish_wave(r, 12)
	check(BonusService.has_case(r) and BonusService.case_kind(r) == "debuff", "после 12-й — ящик с проклятием")
	BonusService.pick(r, 1)
	check(r.active_debuff.waves_left == 1 and not BonusService.has_case(r), "дебафф выбран, действует 1 раунд")
	r.phase = "shop"
	finish_wave(r, 13)
	check(r.active_debuff.is_empty(), "после 13-й дебафф снят")
	# эффекты каждого дебаффа
	for id in GameData.debuff_ids:
		var rr := RunState.new_run(7)
		rr.weapons.carbine = {"rank": 1, "mastery": 0}
		rr.equipped_weapon = "carbine"
		var bw := StatCalc.weapon_stats(rr, "carbine")
		var bhp := StatCalc.max_hp(rr)
		var bms := StatCalc.move_speed_multiplier(rr)
		rr.active_debuff = {"id": id, "waves_left": 1}
		var w := StatCalc.weapon_stats(rr, "carbine")
		match id:
			"slow_legs": check(StatCalc.move_speed_multiplier(rr) < bms and StatCalc.move_speed_multiplier(rr) >= 0.75, "Тяжёлые ноги −20% (не ниже cap 0,75)")
			"weak_medkit":
				var m := Medkit.new()
				m.reset_for_wave(1)
				m.try_use(10.0, 100.0, BonusService.medkit_heal_mult(rr))
				check(absf(m.total - 10.0) < 0.001 and m.duration == 4.0, "Слабая аптечка: 10% вместо 20% за те же 4 с")
			"molotov": check(not BonusService.molotov(rr).is_empty() and float(BonusService.molotov(rr).interval) == 20.0, "Молотов: интервал 20 с")
			"dull_ammo": check(absf(w.damage - bw.damage * 0.75) < 0.001, "Тупые патроны: урон ×0,75")
			"frail": check(absf(StatCalc.max_hp(rr) - bhp * 0.7) < 0.001, "Хрупкость: ХП ×0,7")
			"stiff_bolt": check(absf(w.fire_rate - bw.fire_rate * 0.7) < 0.001, "Тугой затвор: темп ×0,7")
			"poor_loot": check(Economy.reward_for(5, 0, false, BonusService.coin_bonus(rr)).total < Economy.reward_for(5, 0, false).total, "Скудная добыча: монет меньше")
		# аптечка без дебаффа не изменена
		var m2 := Medkit.new()
		m2.reset_for_wave(1)
		m2.try_use(10.0, 100.0)
		check(absf(m2.total - 20.0) < 0.001, "обычная аптечка 20% не изменена")
	# баф и дебафф вместе (дебафф на 13-й после бафа 11–12)
	var both := RunState.new_run(9)
	both.active_bonus = {"id": "double_damage", "waves_left": 2}
	both.active_debuff = {"id": "dull_ammo", "waves_left": 1}
	both.weapons.carbine = {"rank": 1, "mastery": 0}
	var wb := StatCalc.weapon_stats(both, "carbine")
	check(absf(wb.damage - 16.0 * (1.0 + 1.0 - 0.25)) < 0.001, "баф и дебафф суммируются аддитивно")
	# Молотов в игре: огонь рядом с героем каждые 20 с, с предупреждением
	Session.new_run(51)
	var gr: RunState = Session.run
	gr.waves_completed = 11
	gr.active_debuff = {"id": "molotov", "waves_left": 1}
	game = load("res://scenes/game.tscn").instantiate()
	game.auto_open_ui = false
	add_child(game)
	await get_tree().process_frame
	ShopService.begin_wave(gr)
	game._launch_wave()
	game.queue.clear()
	game.suppress_win = true
	game.state = game.St.COMBAT
	var pl: Player = game.player
	pl.hp = 1e9
	pl.max_hp = 1e9
	var created: Array = []
	var seen_ids := {}
	for i in 60 * 65:
		game.sim_step(1.0 / 60.0)
		for h in game.hazards.items:
			if h.get("tag", "") == "molotov" and not seen_ids.has(h.pos):
				seen_ids[h.pos] = true
				created.append([i / 60.0, h.pos.distance_to(pl.position), h.delay, h.radius])
	check(created.size() == 3, "за 65 с загорелось 3 раза (20, 40, 60 с)", str(created))
	if created.size() >= 1:
		check(absf(created[0][0] - 20.0) < 1.0, "первый поджог на 20-й секунде", str(created[0][0]))
		check(created[0][2] == 1.2, "предупреждение 1,2 с перед огнём")
	check(game.hazards.count() <= 8, "лимит опасных полей соблюдён")
	# UI: ящик с проклятием показывается с красным оформлением, порядок переворота как у кейса
	Session.new_run(77)
	var run2: RunState = Session.run
	run2.waves_completed = 11
	run2.phase = "combat"
	run2.coins_at_wave_start = run2.coins
	Economy.complete_wave(run2)
	check(BonusService.has_case(run2) and BonusService.case_kind(run2) == "debuff", "UI: после 12-й ящик с проклятием")
	var before: Array = run2.bonus_case.options.duplicate()
	game.queue_free()
	await get_tree().process_frame
	game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var ui: BonusCaseScreen = game.bonus_ui
	check(ui.visible and ui.state == "closed" and ui._kind == "debuff" and ui._title.text == "Ящик с проклятием!", "UI: ящик показан закрытым, заголовок «Ящик с проклятием!»")
	ui._anim_speed = 40.0
	ui._on_btn()
	var t := 0.0
	while ui.state != "choosing" and t < 3.0:
		await get_tree().process_frame
		t += 0.016
	check(ui.cards.size() == 3 and ui.cards[0].kind == "debuff", "UI: три карточки дебаффов")
	var ids: Array = []
	for c in ui.cards:
		ids.append(c.bonus_id)
	check(ids == before, "UI: карточки = сохранённый ящик")
	var first_seen := {}
	ui._on_card(ui.cards[2])
	check(game.run.active_debuff.id == before[2] and not BonusService.has_case(game.run), "выбор обязателен и применён сразу")
	t = 0.0
	var tick := 0
	while ui.state != "done" and t < 6.0:
		await get_tree().process_frame
		tick += 1
		for c in ui.cards:
			if c.flip > 0.02 and not first_seen.has(c.index):
				first_seen[c.index] = tick
		t += 0.016
	check(ui.state == "done" and first_seen[2] > first_seen[0] and first_seen[2] > first_seen[1], "UI: выбранная переворачивается последней", str(first_seen))
	print("ИТОГО (ящик с проклятием): passed=%d failed=%d" % [passed, failed])
	SaveService.delete_run()
	get_tree().quit(1 if failed > 0 else 0)
