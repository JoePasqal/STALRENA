extends Node
## Бонус-кейс: появление после каждой 10-й волны, 3 разных карточки, выбор, 2 волны действия, монеты, caps, сохранение, UI-порядок переворота.

var passed := 0
var failed := 0


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
	SaveService.base_dir = "user://test_saves"
	DirAccess.make_dir_recursive_absolute("user://test_saves")
	Settings.data.tutorial_done = true
	Settings.data.tutorial_shop_done = true
	GameData.reload()
	check(GameData.validate().is_empty(), "balance + bonuses валидны", str(GameData.validate()))
	# кейс только после кратных 10
	var run := RunState.new_run(31)
	for w in range(1, 31):
		finish_wave(run, w)
		var expect := (w % 10 == 0)
		check(BonusService.has_case(run) == expect, "кейс после волны %d: %s" % [w, expect], str(run.bonus_case))
		if expect:
			var o: Array = run.bonus_case.options
			check(o.size() == 3 and o[0] != o[1] and o[1] != o[2] and o[0] != o[2], "три РАЗНЫХ карточки (волна %d)" % w, str(o))
			check(JSON.stringify(run.bonus_case) == JSON.stringify(BonusService.make_case(31, w)), "детерминировано от seed и волны")
			# перезагрузка не перебрасывает кейс
			var back := RunState.from_dict(JSON.parse_string(JSON.stringify(run.to_dict())))
			check(JSON.stringify(back.bonus_case) == JSON.stringify(run.bonus_case), "сохранение/загрузка: тот же кейс, без перебрасывания")
			var r := BonusService.pick(run, 2)
			check(r.ok and run.active_bonus.waves_left == 2 and not BonusService.has_case(run), "выбор применён, кейс закрыт")
			check(not BonusService.pick(run, 0).ok, "второй выбор невозможен")
			# применение: две следующие волны, потом снимается
			run.phase = "shop"
		elif run.active_bonus.is_empty() == false:
			pass
	# эффекты каждого бонуса
	for id in GameData.bonus_ids:
		var r2 := RunState.new_run(5)
		r2.weapons.carbine = {"rank": 1, "mastery": 0}
		r2.equipped_weapon = "carbine"
		var base_w := StatCalc.weapon_stats(r2, "carbine")
		var base_hp := StatCalc.max_hp(r2)
		var base_ms := StatCalc.move_speed_multiplier(r2)
		r2.bonus_case = {"wave": 10, "options": [id, GameData.bonus_ids[0] if id != GameData.bonus_ids[0] else GameData.bonus_ids[1], GameData.bonus_ids[2] if id != GameData.bonus_ids[2] else GameData.bonus_ids[3]]}
		BonusService.pick(r2, 0)
		var w := StatCalc.weapon_stats(r2, "carbine")
		match id:
			"double_damage": check(absf(w.damage - base_w.damage * 2.0) < 0.001, "Двойной урон ×2")
			"sturdy_body": check(absf(StatCalc.max_hp(r2) - base_hp * 1.5) < 0.001 and absf(r2.hp - StatCalc.max_hp(r2)) < 0.001, "Крепкое тело +50% ХП, здоровье полное")
			"gold_vein": check(Economy.reward_for(5, 0, false, BonusService.coin_bonus(r2)).total == int(floor(34 * 1.25)) + 0 or Economy.reward_for(5, 0, false, BonusService.coin_bonus(r2)).total > Economy.reward_for(5, 0, false).total, "Золотая жила: монеты больше")
			"rapid_fire": check(w.fire_rate > base_w.fire_rate and w.fire_rate <= 5.0 * 1.8 + 0.001, "Скорострельность в пределах cap +80%")
			"quick_legs": check(StatCalc.move_speed_multiplier(r2) > base_ms and StatCalc.move_speed_multiplier(r2) <= 1.35 + 1e-9, "Лёгкий шаг в пределах cap 1,35")
			"sharp_eye": check(w.crit_chance <= 0.6 and w.crit_chance > base_w.crit_chance and w.crit_multiplier <= 2.5, "Верный глаз с caps")
			"fast_hands": check(absf(w.reload_time - base_w.reload_time / 2.0) < 0.001, "Быстрые руки: перезарядка base/(1+1)")
		# аптечка не меняется: 20% максимума за 4 с
		var m := Medkit.new()
		m.reset_for_wave()
		m.try_use(10.0, StatCalc.max_hp(r2))
		check(absf(m.total - 0.2 * StatCalc.max_hp(r2)) < 0.001 and m.duration == 4.0, "аптечка не изменена бонусом %s" % id)
		check(StatCalc.armor_base_hp(r2) == 0.0 and GameData.armors.light.damage_reduction == 0, "броня не снижает урон (бонус %s)" % id)
	# срок: волны 11 и 12, на 13-й бонуса нет; монеты +25% на 11 и 12
	var r3 := RunState.new_run(9)
	finish_wave(r3, 10)
	r3.bonus_case = {"wave": 10, "options": ["gold_vein", "double_damage", "fast_hands"]}
	BonusService.pick(r3, 0)
	var coins0 := r3.coins
	r3.phase = "shop"
	finish_wave(r3, 11)
	var gain11 := r3.coins - coins0
	check(gain11 == Economy.reward_for(11, r3.coins_at_wave_start, false, 0.25).total and r3.active_bonus.waves_left == 1, "волна 11: бонус монет применён, осталась 1 волна", "%d" % gain11)
	var c2 := r3.coins
	finish_wave(r3, 12)
	check(r3.coins - c2 == Economy.reward_for(12, r3.coins_at_wave_start, true, 0.25).total and r3.active_bonus.is_empty(), "волна 12: бонус монет применён и снят после неё")
	var c3 := r3.coins
	finish_wave(r3, 13)
	check(r3.coins - c3 == Economy.reward_for(13, r3.coins_at_wave_start, false).total, "волна 13: бонуса нет")
	# UI: кейс открывается при входе в магазин, переворот: сначала две невыбранные, выбранная последней
	Session.new_run(77)
	var run2: RunState = Session.run
	run2.waves_completed = 9
	run2.phase = "combat"
	run2.coins_at_wave_start = run2.coins
	Economy.complete_wave(run2)
	check(BonusService.has_case(run2), "UI: после 10-й волны кейс создан")
	var opts_before: Array = run2.bonus_case.options.duplicate()
	var game: Node = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var ui: BonusCaseScreen = game.bonus_ui
	check(ui.visible and ui.state == "closed", "UI: кейс показан закрытым при входе в магазин")
	ui._anim_speed = 40.0
	ui._on_btn()
	var t := 0.0
	while ui.state != "choosing" and t < 3.0:
		await get_tree().process_frame
		t += 0.016
	check(ui.cards.size() == 3 and ui.state == "choosing", "UI: три закрытые карточки")
	var ids: Array = []
	for c in ui.cards:
		ids.append(c.bonus_id)
		check(c.flip == 0.0, "карточка закрыта до выбора")
	check(ids == opts_before, "UI: карточки соответствуют сохранённому кейсу")
	var first_seen := {}
	ui._on_card(ui.cards[1])
	check(not BonusService.has_case(game.run) and game.run.active_bonus.id == opts_before[1], "выбор применён и сохранён сразу")
	t = 0.0
	var tick := 0
	while ui.state != "done" and t < 6.0:
		await get_tree().process_frame
		tick += 1
		for c in ui.cards:
			if c.flip > 0.02 and not first_seen.has(c.index):
				first_seen[c.index] = tick
		t += 0.016
	check(ui.state == "done", "UI: анимация завершилась", ui.state)
	check(first_seen.has(0) and first_seen.has(2) and first_seen.has(1) and first_seen[1] > first_seen[0] and first_seen[1] > first_seen[2], "UI: сначала переворачиваются две другие, выбранная — последней", str(first_seen))
	check(first_seen[0] < first_seen[2], "UI: невыбранные открываются по очереди")
	for c in ui.cards:
		check(c.flip > 0.99, "все три карточки показаны лицом в конце")
	ui._on_btn()
	check(not ui.visible and BonusService.active_def(game.run).id == opts_before[1], "«Забрать» закрывает кейс, бонус активен")
	print("ИТОГО (кейс бонуса): passed=%d failed=%d" % [passed, failed])
	SaveService.delete_run()
	get_tree().quit(1 if failed > 0 else 0)
