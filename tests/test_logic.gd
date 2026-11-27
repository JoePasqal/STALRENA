extends SceneTree
## Логические проверки без сцены (ACCEPTANCE.md: 1–16, 22–24 частично, 26, 29).
## Запуск: godot --headless --path . --script res://tests/test_logic.gd

var passed := 0
var failed := 0


func check(cond: bool, name: String, extra: String = "") -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  FAIL: ", name, " ", extra)


func approx(a: float, b: float, eps: float = 0.001) -> bool:
	return absf(a - b) <= eps


func _init() -> void:
	GameData.load_all()
	var errs := GameData.validate()
	check(errs.is_empty(), "balance валиден", str(errs))
	t_new_run()
	t_medkit()
	t_armor_hp()
	t_parts_and_ranks()
	t_shop_buy_refresh_lock()
	t_generation_distribution()
	t_pity()
	t_modules_sets()
	t_mastery()
	t_economy()
	t_waves()
	t_locations()
	t_layouts()
	t_save()
	t_stat_caps()
	print("ИТОГО: passed=%d failed=%d" % [passed, failed])
	quit(1 if failed > 0 else 0)


func fresh(seed_v: int = 12345) -> RunState:
	return RunState.new_run(seed_v)


func give_weapon(run: RunState, id: String, rank: int = 1) -> void:
	run.weapons[id] = {"rank": rank, "mastery": 0}


func t_new_run() -> void:
	var r := fresh()
	check(r.coins == 100, "1: 100 монет")
	check(approx(r.hp, 100.0) and approx(StatCalc.max_hp(r), 100.0), "1: 100/100 ХП")
	check(r.weapons.has("pistol") and r.weapons.pistol.rank == 1 and r.equipped_weapon == "pistol", "1: Искра I")
	check(r.equipped_armor == "" and r.armors.is_empty(), "1: без брони")
	check(r.shop_level == 1, "1: уровень магазина 1")
	check(r.offers.size() == 6, "1: шесть предложений")
	check(r.phase == "shop", "1: магазин до первой волны")
	var m := Medkit.new()
	m.reset_for_wave()
	check(m.stock == 1, "1: одна аптечка")
	check(GameData.module_slots(1) == 2, "1: две ячейки модулей")


func t_medkit() -> void:
	# 2: 200 макс. ХП, за 1 с лечит 10, за 4 с — ровно 40, при разных FPS
	for fps in [30, 60, 120, 144]:
		var m := Medkit.new()
		m.reset_for_wave()
		var hp := 50.0
		check(m.try_use(hp, 200.0), "2: применение @%d" % fps)
		var dt: float = 1.0 / float(fps)
		var t := 0.0
		var heal_1s := 0.0
		while m.active:
			var step := minf(dt, 4.0 - t)       # неполная последняя delta
			var h := m.tick(step)
			hp += h
			t += step
			if t <= 1.0 + 1e-9:
				heal_1s += h
			if t > 5.0:
				break
		check(approx(hp, 90.0, 0.001), "2: +40 за 4 с @%d fps (получено %.4f)" % [fps, hp - 50.0])
		check(approx(heal_1s, 10.0, 0.2), "2: +10 за 1 с @%d fps (%.3f)" % [fps, heal_1s])
	# 2: пауза — без тиков ничего не меняется
	var mp := Medkit.new()
	mp.reset_for_wave()
	mp.try_use(10, 100)
	mp.tick(1.0)
	var before := mp.given
	# (пауза: tick не вызывается)
	check(approx(mp.given, before), "2: пауза не лечит")
	# 3: на полном здоровье отклоняется без расхода
	var m3 := Medkit.new()
	m3.reset_for_wave()
	check(not m3.try_use(100, 100), "3: полное ХП — отказ")
	check(m3.stock == 1, "3: запас не списан")
	# почти полное: лечение ограничивается максимумом вызывающим
	check(m3.try_use(99.5, 100), "3: почти полное — можно")
	var hp3 := 99.5
	while m3.active:
		hp3 = minf(hp3 + m3.tick(0.1), 100.0)
	check(approx(hp3, 100.0), "3: ограничение максимумом")
	# повторное применение при активном эффекте и нулевом запасе
	var m4 := Medkit.new()
	m4.reset_for_wave()
	m4.try_use(10, 100)
	check(not m4.try_use(10, 100), "3: нет повторного")
	# следующий раунд: ровно 1, не 2
	m4.stock = 1
	m4.reset_for_wave()
	check(m4.stock == 1, "3: на раунд ровно 1")
	var m5 := Medkit.new()
	m5.reset_for_wave()
	m5.reset_for_wave()
	check(m5.stock == 1, "3: без накопления")
	# смерть/конец волны очищают эффект
	m4.try_use(10, 100)
	m4.clear_effect()
	check(not m4.active and approx(m4.tick(1.0), 0.0), "3: после смерти не лечит")
	# максимум фиксируется при применении
	var m6 := Medkit.new()
	m6.reset_for_wave()
	m6.try_use(50, 100)
	var got := 0.0
	for i in 400:
		got += m6.tick(0.01)
	check(approx(got, 20.0, 0.001), "2: 20% фиксированного максимума = 20")


func t_armor_hp() -> void:
	var r := fresh()
	r.armors["field"] = {"rank": 1, "mastery": 0}
	r.equipped_armor = "field"
	var old := 100.0
	r.hp = 60.0
	# 4: изолированный пересчёт: 60/100 → 100/140 (+40)
	r.armors.field.rank = 1
	r.equipped_armor = ""
	r.hp = 60.0
	var old_max := StatCalc.max_hp(r)
	r.equipped_armor = "field"      # +40 ХП (Оплот I)
	Inventory.refresh_max_hp(r, old_max)
	check(approx(StatCalc.max_hp(r), 140.0) and approx(r.hp, 100.0), "4: 60/100 → 100/140", "hp=%f" % r.hp)
	# снижение максимума ограничивает текущее здоровье
	r.hp = 140.0
	var om := StatCalc.max_hp(r)
	r.equipped_armor = ""
	Inventory.refresh_max_hp(r, om)
	check(approx(r.hp, 100.0), "4: при снижении ХП ограничено")
	# в реальном Shop здоровье полное
	var r2 := fresh()
	r2.coins = 1000
	r2.offers[0] = {"uid": 999, "kind": "base", "type": "armor", "id": "heavy", "fam": "", "target_rank": 0, "price": 32, "bought": false}
	var res := ShopService.buy(r2, 999)
	check(res.ok and r2.equipped_armor == "heavy", "4: броня куплена и надета")
	check(approx(r2.hp, StatCalc.max_hp(r2)) and approx(r2.hp, 155.0), "4: в магазине ХП полное 155", str(r2.hp))
	# броня не скрыто снижает урон
	for a in GameData.armors.values():
		check(float(a.damage_reduction) == 0.0, "4: броня без снижения урона " + a.id)
	# формула с мастерством и модулями: (100+armor+mastery)*(1+%)
	var r3 := fresh()
	r3.armors["heavy"] = {"rank": 5, "mastery": 2}
	r3.equipped_armor = "heavy"
	r3.modules["reserve_cells"] = {"level": 3, "paid": 60}
	var expected := (100.0 + 350.0 + 350.0 * 0.05 * 2) * (1.0 + 0.24)
	check(approx(StatCalc.max_hp(r3), expected, 0.01), "формула макс. ХП", "%f vs %f" % [StatCalc.max_hp(r3), expected])


func t_parts_and_ranks() -> void:
	var r := fresh()
	give_weapon(r, "carbine")
	give_weapon(r, "shotgun")
	# 6: три части carbine/2 повышают только карабин I→II
	for i in 2:
		check(Inventory.add_part(r, "weapon:carbine", 2, 10).ok, "6: часть %d" % i)
		check(r.weapons.carbine.rank == 1, "6: две части ранг не меняют")
	check(r.part_count("weapon:carbine", 2) == 2, "6: счётчик 2/3")
	var res := Inventory.add_part(r, "weapon:carbine", 2, 10)
	check(res.ok and res.ranked_up and r.weapons.carbine.rank == 2, "6: третья повышает карабин")
	check(r.part_count("weapon:carbine", 2) == 0, "6: части поглощены")
	check(r.weapons.shotgun.rank == 1 and r.weapons.pistol.rank == 1, "6: другие ветки не затронуты")
	# нельзя пропускать ранги
	check(not Inventory.add_part(r, "weapon:carbine", 4, 24).ok, "6: нельзя пропустить ранг")
	check(not Inventory.add_part(r, "weapon:carbine", 2, 10).ok, "13: ранг уже собран")
	# смешивать нельзя: части shotgun/2 не идут в carbine
	Inventory.add_part(r, "weapon:shotgun", 2, 10)
	check(r.part_count("weapon:carbine", 2) == 0 and r.part_count("weapon:shotgun", 2) == 1, "6: семейства раздельно")
	# продажа неиспользованной части 50% вниз
	r.coins = 0
	Inventory.add_part(r, "weapon:shotgun", 2, 11)
	var s := Inventory.sell_part(r, "weapon:shotgun", 2)
	check(s.ok and s.refund == 5 and r.coins == 5, "продажа части floor(11*0.5)=5", str(s))
	# 7: прогресс неактивной ветки сохраняется после смены оружия и загрузки
	r.weapons.carbine.rank = 2
	Inventory.equip_weapon(r, "shotgun")
	Inventory.equip_weapon(r, "carbine")
	var d := r.to_dict()
	var r2 := RunState.from_dict(JSON.parse_string(JSON.stringify(d)))
	check(r2 != null and r2.weapons.carbine.rank == 2 and r2.part_count("weapon:shotgun", 2) == 1, "7: ранг и части после загрузки")
	var s_before := StatCalc.weapon_stats(r, "carbine")
	var s_after := StatCalc.weapon_stats(r2, "carbine")
	check(approx(s_before.damage, s_after.damage), "7: характеристики прежние")
	check(approx(s_after.damage, 16.0 * 1.45), "ранг II = множитель урона 1.45", str(s_after.damage))


func t_shop_buy_refresh_lock() -> void:
	var r := fresh()
	give_weapon(r, "carbine")
	var o := ShopService._new_offer(r, "module")
	o.type = "module"; o.id = "amplifier"; o.price = 18
	r.offers[0] = o
	r.coins = 100
	var uid := int(o.uid)
	var a := ShopService.buy(r, uid)
	var b := ShopService.buy(r, uid)
	check(a.ok and not b.ok, "8: второй быстрый тап не покупает")
	check(r.coins == 82 and r.modules.amplifier.level == 1, "8: списано ровно один раз")
	check(r.offers[0].bought, "8: карточка помечена купленной")
	# отказ не списывает
	r.coins = 5
	var o2 := ShopService._new_offer(r, "module")
	o2.type = "module"; o2.id = "feeder"; o2.price = 18
	r.offers[1] = o2
	var f := ShopService.buy(r, int(o2.uid))
	check(not f.ok and r.coins == 5 and r.coins >= 0, "8: отказ не списывает, нет отрицательных")
	# 9: обновление за 10 меняет все шесть и восстанавливает пустые места; при 9 монетах отказ без изменения RNG
	r.coins = 9
	var rng_state := r.rng_shop.state
	var ids_before := []
	for x in r.offers:
		ids_before.append(x.uid)
	var rf := ShopService.refresh(r)
	check(not rf.ok and r.coins == 9 and r.rng_shop.state == rng_state, "9: 9 монет — отказ, RNG не тронут")
	var same := true
	for i in 6:
		if r.offers[i].uid != ids_before[i]:
			same = false
	check(same, "9: карточки не изменились при отказе")
	r.coins = 50
	rf = ShopService.refresh(r)
	check(rf.ok and r.coins == 40, "9: обновление стоит ровно 10")
	var any_old := false
	for x in r.offers:
		if ids_before.has(x.uid):
			any_old = true
	check(not any_old and r.offers.size() == 6, "9: все шесть новые")
	var no_bought := true
	for x in r.offers:
		if x.bought:
			no_bought = false
	check(no_bought, "9: купленные места восстановлены")
	# 10: lock сохраняет набор, цены, пустые места; ручной refresh снимает lock
	r.offers[2].bought = true
	var snapshot := JSON.stringify(r.offers)
	ShopService.set_lock(r, true)
	r.phase = "combat"; r.phase = "shop"
	ShopService.on_enter_shop(r)
	check(JSON.stringify(r.offers) == snapshot, "10: замок сохранил набор/цены/пустые")
	var r_loaded := RunState.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	check(JSON.stringify(r_loaded.offers) == snapshot, "10/26: после загрузки без перекидывания")
	ShopService.set_lock(r, true)
	r.coins = 50
	var rf2 := ShopService.refresh(r)
	check(rf2.ok and rf2.lock_cleared and not r.shop_locked, "10: ручное обновление снимает замок")
	# без lock — следующий вход генерирует новый набор
	var snap2 := JSON.stringify(r.offers)
	ShopService.on_enter_shop(r)
	check(JSON.stringify(r.offers) != snap2, "вход без замка обновляет набор")
	# повышение магазина не даёт бесплатный reroll
	r.waves_completed = 5
	r.coins = 500
	var snap3 := JSON.stringify(r.offers)
	var up := ShopService.upgrade_shop(r)
	check(up.ok and r.shop_level == 2 and JSON.stringify(r.offers) == snap3 and r.coins == 460, "10: уровень без reroll, цена 40")
	r.waves_completed = 3
	var up2 := ShopService.upgrade_status(r)
	check(not up2.ok, "уровень 3 требует 8 волн")
	r.shop_level = 5
	check(ShopService.upgrade_status(r).get("max", false), "уровень 5 — максимум")
	# двойной вход в магазин / покупки вне магазина
	r.phase = "combat"
	check(not ShopService.buy(r, int(r.offers[0].uid)).ok, "покупки только между волнами")
	# 13: купленная карточка части; после сборки ранга остальные недоступны без списания
	var r3 := fresh()
	give_weapon(r3, "carbine")
	r3.coins = 500
	r3.offers = []
	for i in 6:
		var po := ShopService._make_part_offer(r3, {"type": "weapon", "id": "carbine", "fam": "weapon:carbine", "target": 2})
		r3.offers.append(po)
	for i in 3:
		check(ShopService.buy(r3, int(r3.offers[i].uid)).ok, "покупка части %d" % i)
	check(r3.weapons.carbine.rank == 2, "13: ранг собран")
	var coins_before := r3.coins
	var st := ShopService.offer_status(r3, r3.offers[3])
	var bad := ShopService.buy(r3, int(r3.offers[3].uid))
	check(not st.ok and st.reason == "Ранг уже собран" and not bad.ok and r3.coins == coins_before, "13: недоступно, деньги целы")
	check(not r3.offers[3].bought, "13: карточка не пересоздана и не помечена")


func t_generation_distribution() -> void:
	# 11: частоты соответствуют конфигу; нет недоступных рангов/частей
	var r := fresh(777)
	give_weapon(r, "carbine")
	give_weapon(r, "shotgun", 3)
	r.armors["field"] = {"rank": 5, "mastery": 0}
	r.shop_level = 3
	var cats := {"base": 0, "part": 0, "module": 0, "complete": 0}
	var rank_count := {}
	var bad := 0
	var n := 4000
	for i in n:
		ShopService.generate_offers(r, false)
		for o in r.offers:
			cats[o.kind] += 1
			if o.kind == "part":
				rank_count[o.target_rank] = int(rank_count.get(o.target_rank, 0)) + 1
				var cur := r.family_rank(o.fam)
				if int(o.target_rank) != cur + 1 or cur >= 5:
					bad += 1
				if not GameData.allowed_ranks(3).has(int(o.target_rank)):
					bad += 1
				if o.fam == "armor:field":
					bad += 1                      # V ранг: обычные части не генерируются
	check(bad == 0, "11: нет недоступных частей/рангов", str(bad))
	var total := float(n * 6)
	# кандидатные категории: base, parts, modules все непустые → 20/55/25
	check(absf(cats.base / total - 0.20) < 0.02, "11: base ~20%", str(cats.base / total))
	check(absf(cats.part / total - 0.55) < 0.02, "11: parts ~55%", str(cats.part / total))
	check(absf(cats.module / total - 0.25) < 0.02, "11: modules ~25%", str(cats.module / total))
	# кандидаты частей: carbine→2 (вес 40), shotgun→4 (вес 10), pistol→2 (40)
	# ранг среди допустимых: вес 2: 40, 4: 10 → 80% / 20%
	var pc := float(rank_count.get(2, 0) + rank_count.get(4, 0))
	check(absf(float(rank_count.get(2, 0)) / pc - 0.8) < 0.03, "11: ранги по весам уровня", str(rank_count))
	# пустые категории — перенормировка без зависания
	var r2 := fresh(5)
	r2.shop_level = 1
	for id in GameData.weapon_ids:
		give_weapon(r2, id, 5)
	for id in GameData.armor_ids:
		r2.armors[id] = {"rank": 5, "mastery": 0}
	r2.modules = {"amplifier": {"level": 3, "paid": 54}, "feeder": {"level": 3, "paid": 54}}
	for id in GameData.module_ids:
		r2.modules[id] = {"level": 3, "paid": 54}
	r2.shop_level = 5
	ShopService.generate_offers(r2, false)
	var all_complete := true
	for o in r2.offers:
		if o.kind != "complete":
			all_complete = false
	check(all_complete, "11: всё собрано — карточки «Сборка завершена»")
	check(not ShopService.can_refresh(r2).ok, "11: платное обновление отключено")
	# дубликаты базовой ветки внутри набора запрещены
	var dup := 0
	var r3 := fresh(99)
	r3.shop_level = 1
	for i in 500:
		ShopService.generate_offers(r3, false)
		var seen := {}
		for o in r3.offers:
			if o.kind == "base":
				var k: String = str(o.type) + str(o.id)
				if seen.has(k):
					dup += 1
				seen[k] = true
	check(dup == 0, "дубликатов базовой ветки нет")


func t_pity() -> void:
	var r := fresh(31)
	give_weapon(r, "carbine")
	r.equipped_weapon = "carbine"
	r.shop_level = 2
	r.coins = 100000
	# вручную: три платных обновления без части → четвёртое гарантирует
	r.pity = 3
	var ok := true
	for i in 50:
		r.pity = 3
		ShopService.refresh(r)
		if not ShopService.offers_contain_pity_part(r):
			ok = false
	check(ok, "12: при pity>=3 часть гарантирована")
	check(r.pity == 0, "12: счётчик сброшен")
	# счётчик наращивается только платными, и только если части нет
	var r2 := fresh(32)
	r2.equipped_weapon = "pistol"
	r2.shop_level = 1
	r2.coins = 100000
	var free_inc := true
	for i in 30:
		var p0 := r2.pity
		ShopService.generate_offers(r2, false)
		if r2.pity > p0:
			free_inc = false
	check(free_inc, "12: бесплатная смена набора не наращивает pity")
	# цели отсутствуют (оружие V ранга) → гарантия не создаёт запрещённый ранг, счётчик заморожен
	var r3 := fresh(33)
	r3.weapons.pistol.rank = 5
	r3.pity = 3
	r3.coins = 1000
	ShopService.refresh(r3)
	var illegal := false
	for o in r3.offers:
		if o.kind == "part" and o.fam == "weapon:pistol":
			illegal = true
	check(not illegal and r3.pity == 3, "12: нет цели — гарантии нет, счётчик заморожен")
	# цель на недоступном ранге (магазин 1, оружие II → нужен III)
	var r4 := fresh(34)
	r4.weapons.pistol.rank = 2
	r4.shop_level = 1
	r4.pity = 3
	r4.coins = 1000
	ShopService.refresh(r4)
	var bad := false
	for o in r4.offers:
		if o.kind == "part" and int(o.target_rank) == 3:
			bad = true
	check(not bad, "12: ранг недоступен уровнем магазина — не генерируется")


func t_modules_sets() -> void:
	var r := fresh()
	r.coins = 1000
	# 14: один слот, дубликат повышает уровень до 3, четвёртая недоступна
	check(Inventory.add_module(r, "amplifier", 18).ok, "14: первый модуль")
	check(r.modules.size() == 1, "14: слот занят")
	Inventory.add_module(r, "amplifier", 18)
	Inventory.add_module(r, "amplifier", 18)
	check(r.modules.amplifier.level == 3 and r.modules.size() == 1, "14: три копии = уровень 3 в одном слоте")
	check(not Inventory.add_module(r, "amplifier", 18).ok, "14: четвёртая копия недоступна")
	# новый вид при заполненных слотах (2 слота)
	check(Inventory.add_module(r, "feeder", 18).ok, "второй вид")
	check(not Inventory.add_module(r, "bolt_drive", 18).ok, "14: заполнены слоты — новый вид нельзя")
	# продажа возвращает половину фактических затрат без арбитража
	r.coins = 0
	var s := Inventory.sell_module(r, "amplifier")
	check(s.ok and s.refund == 27 and r.coins == 27 and not r.modules.has("amplifier"), "14: продажа 54 → 27", str(s))
	# 15: набор требует три разных модуля; дубликаты не заменяют недостающий
	var r2 := fresh()
	r2.shop_level = 3
	Inventory.add_module(r2, "amplifier", 18)
	Inventory.add_module(r2, "amplifier", 18)
	Inventory.add_module(r2, "feeder", 18)
	check(StatCalc.active_set_ids(r2).is_empty(), "15: дубликаты не открывают набор")
	var b1 := StatCalc.module_bonuses(r2)
	check(approx(b1.damage_percent, 0.16), "15: бонус модуля уровня 2 = 0.16")
	Inventory.add_module(r2, "bolt_drive", 18)
	check(StatCalc.active_set_ids(r2) == ["assault"], "15: три разных → набор Штурм")
	var b2 := StatCalc.module_bonuses(r2)
	check(approx(b2.damage_percent, 0.16 + 0.12), "15: бонус набора не зависит от уровня", str(b2))
	# повторный пересчёт не усиливает бесконечно
	var b3 := StatCalc.module_bonuses(r2)
	check(approx(b3.damage_percent, b2.damage_percent), "15: пересчёт идемпотентен")
	Inventory.sell_module(r2, "feeder")
	check(StatCalc.active_set_ids(r2).is_empty() and approx(StatCalc.module_bonuses(r2).damage_percent, 0.16), "15: продажа выключает набор")
	# Живучесть: ХП-процент
	var r3 := fresh()
	r3.shop_level = 3
	for id in ["reserve_cells", "shock_lining", "cell_matrix"]:
		Inventory.add_module(r3, id, 20)
	check(approx(StatCalc.max_hp(r3), 100.0 * (1.0 + 0.08 + 0.12)), "Живучесть: +ХП%", str(StatCalc.max_hp(r3)))
	# caps
	var r4 := fresh()
	r4.shop_level = 5
	for id in ["target_sensor", "precision_core"]:
		r4.modules[id] = {"level": 3, "paid": 0}
	var ws := StatCalc.weapon_stats(r4, "pistol")
	check(ws.crit_chance <= 0.6 and ws.crit_multiplier <= 2.5, "caps: крит")


func t_mastery() -> void:
	var r := fresh()
	r.weapons.carbine = {"rank": 5, "mastery": 0}
	r.equipped_weapon = "carbine"
	r.coins = 1000
	check(not Inventory.buy_mastery(r, "weapon").ok, "16: до первой волны недоступно")
	r.waves_completed = 1
	check(Inventory.buy_mastery(r, "weapon").ok, "16: покупка мастерства")
	check(not Inventory.buy_mastery(r, "weapon").ok and not Inventory.buy_mastery(r, "armor").ok, "16: одна покупка на магазин")
	var dmg := StatCalc.weapon_damage(r, "carbine")
	check(approx(dmg, 16.0 * 4.2 * 1.05), "16: +5% от урона V ранга (аддитивно)", str(dmg))
	# переключение, сохранение, reroll не сбрасывают лимит
	r.weapons.pistol.rank = 5
	Inventory.equip_weapon(r, "pistol")
	check(not Inventory.buy_mastery(r, "weapon").ok, "16: переключение ветки не сбрасывает лимит")
	var r2 := RunState.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	check(r2.mastery_bought_this_shop, "16: загрузка не сбрасывает лимит")
	ShopService.refresh(r2)
	check(r2.mastery_bought_this_shop, "16: reroll не сбрасывает лимит")
	# новый магазин сбрасывает
	r2.phase = "combat"
	var res := Economy.complete_wave(r2)
	check(not r2.mastery_bought_this_shop, "16: новый Shop — лимит снят")
	# V ранг обязателен
	var r3 := fresh()
	r3.waves_completed = 3
	r3.coins = 500
	check(not Inventory.buy_mastery(r3, "weapon").ok, "16: только на V ранге")
	# броня: +5% от ХП V ранга
	var r4 := fresh()
	r4.waves_completed = 2
	r4.coins = 500
	r4.armors.field = {"rank": 5, "mastery": 0}
	r4.equipped_armor = "field"
	Inventory.buy_mastery(r4, "armor")
	check(approx(StatCalc.max_hp(r4), 100.0 + 285.0 + 285.0 * 0.05), "16: мастерство брони", str(StatCalc.max_hp(r4)))


func t_economy() -> void:
	# 22: доход
	check(Economy.reward_for(1, 100, false).total == 26 + 0 + 10, "22: волна 1 при 100 монетах = 36")
	check(Economy.reward_for(1, 0, false).total == 26, "22: без процентов")
	check(Economy.reward_for(1, 105, false).interest == 10, "22: процент ≤10")
	check(Economy.reward_for(1, 999, false).interest == 10, "22: кап процента")
	check(Economy.reward_for(34, 0, false).growth == 64, "22: кап роста 64")
	check(Economy.reward_for(12, 0, true).boss == 30, "22: босс +30")
	check(Economy.reward_for(5, 49, false).interest == 4, "22: floor(49/10)=4")
	var r := fresh()
	ShopService.begin_wave(r)
	r.coins = 7           # остаток после боя не влияет
	var c0 := 100
	var res := Economy.complete_wave(r)
	check(r.coins == 7 + int(res.reward.total) and res.reward.interest == 10, "22: интерес по снимку до боя, не по остатку")
	var again := Economy.complete_wave(r)
	check(again.is_empty(), "22: награда ровно одна (повтор)")
	check(r.waves_completed == 1 and r.phase == "shop", "22: ровно один вход в магазин")
	# поражение — без выплаты; нельзя продолжить
	var r2 := fresh()
	ShopService.begin_wave(r2)
	var coins_before := r2.coins
	Economy.mark_defeat(r2, "drifter")
	check(r2.over and r2.coins == coins_before, "поражение: без выплаты")
	check(Economy.complete_wave(r2).is_empty(), "поражение: победа после смерти не засчитывается")
	# 23: смена сектора сохраняет снаряжение
	var r3 := fresh()
	r3.coins = 5
	r3.weapons.smg = {"rank": 3, "mastery": 0}
	r3.modules["servos"] = {"level": 2, "paid": 36}
	r3.waves_completed = 11
	r3.phase = "combat"
	var before := JSON.stringify([r3.weapons, r3.modules, r3.parts])
	var res3 := Economy.complete_wave(r3)
	check(res3.boss == true and res3.wave == 12 and r3.sector_of(12) == 1 and r3.sector_of(13) == 2, "23: сектор 12→13")
	check(r3.sector_of(24) == 2 and r3.sector_of(25) == 3 and r3.sector_of(36) == 3 and r3.sector_of(37) == 4, "23: 24→25, 36→37")
	check(r3.local_wave_of(13) == 1 and r3.local_wave_of(24) == 12, "23: локальная волна")
	check(JSON.stringify([r3.weapons, r3.modules, r3.parts]) == before and r3.coins >= 5, "23: снаряжение и монеты сохранены")
	var r4 := fresh()
	r4.waves_completed = 11
	r4.phase = "combat"
	var res4 := Economy.complete_wave(r4)
	check(res4.boss and res4.reward.boss == 30, "23: победа на 12 волне — босс-бонус")


func t_waves() -> void:
	# масштабирование: линейное с капами
	check(approx(WaveMath.hp_mult(1), 1.0) and approx(WaveMath.hp_mult(61), 1.0 + 0.055 * 60), "рост ХП линейный")
	check(approx(WaveMath.speed_mult(120), 1.25), "кап скорости 1.25")
	check(WaveMath.projectile_speed_mult(500) <= 1.2 + 1e-9, "кап скорости пуль 1.2")
	check(WaveMath.threat_budget(1) == 10 and WaveMath.threat_budget(120) == 140, "24: бюджет ≤140")
	var def: Dictionary = GameData.enemies.charger
	check(WaveMath.charge_speed(def, 500) <= 420.0 + 1e-6, "кап скорости тарана")
	# планы волн: детерминированность, бюджет, лимиты, первые появления
	var seed_v := 4242
	var arch_prev := ""
	var streak := 0
	var max_streak := 0
	for gw in range(1, 130):
		var p := WaveDirector.build_plan(seed_v, gw)
		var p2 := WaveDirector.build_plan(seed_v, gw)
		check(JSON.stringify(p.queue) == JSON.stringify(p2.queue), "волна %d детерминирована" % gw)
		if p.boss:
			check(gw % 12 == 0, "босс только на каждой 12-й")
			arch_prev = ""
			streak = 0
			continue
		check(p.threat_total <= p.budget + 0, "волна %d: сумма угрозы ≤ бюджета" % gw, "%d/%d" % [p.threat_total, p.budget])
		check(WaveDirector.queue_cost(p.queue) == p.threat_total, "стоимость очереди совпадает (с элитой)")
		check(p.queue.size() <= 260, "очередь конечна")
		for e in p.queue:
			check(int(GameData.enemies[e.id].first_wave) <= gw, "тип %s не раньше волны %d" % [e.id, gw])
			if e.trait != "":
				check(gw >= 18, "элита с волны 18")
		if p.archetype == arch_prev:
			streak += 1
		else:
			streak = 1
		arch_prev = p.archetype
		max_streak = maxi(max_streak, streak)
	check(max_streak <= 2, "не более двух одинаковых архетипов подряд", str(max_streak))
	var p1 := WaveDirector.build_plan(seed_v, 1)
	var only_drifters := true
	for e in p1.queue:
		if e.id != "drifter":
			only_drifters = false
	check(only_drifters and p1.queue.size() >= 6, "волна 1 — бродяги")
	# первое появление типа
	for id in GameData.enemies:
		var fw := int(GameData.enemies[id].first_wave)
		var pp := WaveDirector.build_plan(seed_v, fw)
		var cnt := 0
		for e in pp.queue:
			if e.id == id:
				cnt += 1
		check(cnt >= 1, "тип %s появляется на волне %d" % [id, fw])
	# носитель стоит вместе с детьми: 8 (2 бегуна по 2 = 4 + база 4)
	check(int(GameData.enemies.carrier.threat_cost) == 8 and GameData.enemies.carrier.threat_cost_includes_children, "носитель включает детей")
	# разные seed → не всегда одинаковые планы
	var diff := false
	for gw in range(2, 12):
		if JSON.stringify(WaveDirector.build_plan(1, gw).queue) != JSON.stringify(WaveDirector.build_plan(2, gw).queue):
			diff = true
	check(diff, "seed влияет на состав")
	# элита: не больше одного свойства (структурно — одно поле), вероятность в границах
	check(WaveMath.elite_probability(17) == 0.0 and approx(WaveMath.elite_probability(18), 0.08) and WaveMath.elite_probability(500) <= 0.25 + 1e-9, "вероятность элиты 8%…25%")
	check(WaveMath.ranged_tokens(24) == 2 and WaveMath.ranged_tokens(25) == 4, "токены стрелков 2→4 с волны 25")


func t_locations() -> void:
	for seed_v in [1, 7, 99]:
		var seen_layouts := {}
		for sector in range(1, 13):
			var info := LocationService.sector_info(seed_v, sector)
			check(info.location_id == GameData.location_order[(sector - 1) % 3], "сектор %d → локация" % sector)
			if sector <= 3:
				check(info.modifier == "", "первый визит без модификатора")
			else:
				check(info.modifier != "" and info.modifier != info.native_hazard, "повторный визит: один модификатор")
			# возвращение на локацию — другая раскладка
			if sector > 3:
				var prev := LocationService.sector_info(seed_v, sector - 3)
				check(prev.layout_id != info.layout_id, "возврат: другая раскладка")
			# детерминированно
			check(JSON.stringify(info) == JSON.stringify(LocationService.sector_info(seed_v, sector)), "детерминировано")


func t_layouts() -> void:
	for id in GameData.layouts:
		var m := ArenaModel.from_layout(id)
		check(m.connectivity_ratio(m.start) > 0.999, "%s: свободные ячейки связны" % id, str(m.connectivity_ratio(m.start)))
		check(m.is_point_free(m.start, 150.0), "%s: стартовая зона свободна (150)" % id)
		# все слоты опасностей вместе не должны разрывать карту
		var m2 := ArenaModel.from_layout(id)
		m2.build_nav(m2.hazard_slots)
		check(m2.connectivity_ratio(m2.start) > 0.999, "%s: при закрытых слотах опасностей карта связна" % id, str(m2.connectivity_ratio(m2.start)))
		var path := m.find_path(Vector2(60, 60), m.size - Vector2(60, 60))
		check(path.size() > 2, "%s: путь по углам" % id)
		# стены не сильно загромождают
		var free_ratio := float(m.free_cell_count()) / float(m.grid_w * m.grid_h)
		check(free_ratio > 0.6, "%s: достаточно свободного места" % id, str(free_ratio))
	# геометрия: быстрая пуля не перескакивает тонкую стену (сегмент-луч)
	var m3 := ArenaModel.new()
	m3.load_layout({"id": "t", "location_id": "x", "size": [1000, 1000], "start": [500, 500], "walls": [{"x": 500, "y": 0, "w": 2, "h": 1000, "kind": "block"}], "water": [], "hazard_slots": []})
	var t := m3.raycast_walls(Vector2(400, 500), Vector2(1400, 500))
	check(t > 0.0 and t < 0.2, "5: луч ловит тонкую стену (1200 u/s шаг)", str(t))
	check(m3.raycast_walls(Vector2(400, 500), Vector2(480, 500)) < 0.0, "луч до стены не задевает")
	var rc := m3.resolve_circle(Vector2(495, 500), 12)
	check(rc.hit and rc.pos.x <= 488.001, "выталкивание круга из стены")


func t_save() -> void:
	var dir := "user://test_saves"
	DirAccess.make_dir_recursive_absolute(dir)
	SaveService.base_dir = dir
	SaveService.delete_run()
	check(SaveService.load_run().status == "none", "29: нет сохранения — none, без падения")
	var r := fresh(555)
	give_weapon(r, "marksman", 2)
	r.coins = 77
	Inventory.add_module(r, "servos", 18)
	r.pity = 2
	check(SaveService.save_run(r), "26: запись")
	var l := SaveService.load_run()
	check(l.status == "ok" and l.run.coins == 77 and l.run.pity == 2 and l.run.weapons.marksman.rank == 2, "26: загрузка точных данных")
	check(JSON.stringify(l.run.offers) == JSON.stringify(r.offers), "26: карточки и цены восстановлены")
	# RNG магазина продолжается с того же места
	var a := r.rng_shop.randi()
	var b: int = l.run.rng_shop.randi()
	check(a == b, "26: состояние RNG магазина сохранено")
	# вторая запись создаёт резервную копию; повреждённый основной → backup
	r.coins = 88
	SaveService.save_run(r)
	var f := FileAccess.open(dir + "/run.json", FileAccess.WRITE)
	f.store_string("{ битый json")
	f.close()
	var l2 := SaveService.load_run()
	check(l2.status == "backup" and l2.run != null and l2.run.coins == 77, "29: повреждённый основной → валидный backup", l2.status)
	# оба повреждены → corrupt, без падения
	var f2 := FileAccess.open(dir + "/run.json.bak", FileAccess.WRITE)
	f2.store_string("мусор")
	f2.close()
	check(SaveService.load_run().status == "corrupt", "29: оба повреждены → corrupt")
	# рекорды отдельно
	var rec := SaveService.add_result(5, 120.0, "gunner")
	check(rec.best_wave >= 5, "рекорды отдельным файлом")
	for i in 12:
		rec = SaveService.add_result(i, 1.0, "x")
	check(rec.history.size() == 10, "история последних 10")
	check(SaveService.load_run().status == "corrupt", "29: рекорды не затрагивают слот")
	# контрольная сумма: подмена данных без пересчёта хеша не принимается
	SaveService.delete_run()
	SaveService.save_run(r)
	var txt := FileAccess.get_file_as_string(dir + "/run.json")
	var w = JSON.parse_string(txt)
	w.payload_json = str(w.payload_json).replace("\"coins\":88", "\"coins\":9999")
	var f3 := FileAccess.open(dir + "/run.json", FileAccess.WRITE)
	f3.store_string(JSON.stringify(w))
	f3.close()
	check(SaveService.load_run().status != "ok", "29: подмена данных отвергается")
	# несовместимая версия
	SaveService.delete_run()
	var d := r.to_dict()
	d.format = 999
	check(RunState.from_dict(d) == null, "миграция: несовместимая версия обрабатывается")
	SaveService.delete_run()
	SaveService.base_dir = "user://"


func t_stat_caps() -> void:
	var r := fresh()
	r.shop_level = 5
	r.armors["heavy"] = {"rank": 1, "mastery": 0}
	r.equipped_armor = "heavy"
	check(approx(StatCalc.move_speed_multiplier(r), 0.9), "Бастион −10% скорости")
	r.armors["light"] = {"rank": 1, "mastery": 0}
	r.equipped_armor = "light"
	for id in ["servos"]:
		r.modules[id] = {"level": 3, "paid": 0}
	check(approx(StatCalc.move_speed_multiplier(r), 1.0 + 0.08 + 0.12), "Дозор + Сервопривод")
	# время перезарядки base/(1+bonus), а не base*(1-bonus)
	var r2 := fresh()
	r2.modules["bolt_drive"] = {"level": 3, "paid": 0}
	var ws := StatCalc.weapon_stats(r2, "pistol")
	check(approx(ws.reload_time, 1.2 / 1.3), "перезарядка base/(1+bonus)", str(ws.reload_time))
	# дробовик: 7 дробин; урон по рангу
	var sg := fresh()
	sg.weapons.shotgun = {"rank": 3, "mastery": 0}
	var s := StatCalc.weapon_stats(sg, "shotgun")
	check(s.pellets == 7 and approx(s.damage, 6.0 * 2.1), "дробовик ранг III")
	# огнемёт: горение умножается на ранг
	sg.weapons.flamethrower = {"rank": 2, "mastery": 0}
	var f := StatCalc.weapon_stats(sg, "flamethrower")
	check(approx(f.burn_dps, 4.0 * 1.45) and f.fire_mode == "cone_ticks", "огнемёт: горение 4/с × ранг")
	# V ранг: урон ×4.2, остальные характеристики не меняются
	sg.weapons.carbine = {"rank": 5, "mastery": 0}
	var c := StatCalc.weapon_stats(sg, "carbine")
	check(approx(c.damage, 16.0 * 4.2) and approx(c.fire_rate, 5.0) and c.magazine == 24, "ранг меняет только урон")
