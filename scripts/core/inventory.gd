class_name Inventory
extends RefCounted
## Операции над снаряжением: ранги, части, модули, мастерство, экипировка.
## Все команды возвращают {ok, reason, ...}. Ничего не знает про UI.

static func fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


## Пересчёт максимального ХП после изменения источников. Положительный прирост
## прибавляется к текущему ХП (60/100 +40 → 100/140); при снижении — ограничение.
static func refresh_max_hp(run: RunState, old_max: float) -> void:
	var new_max := StatCalc.max_hp(run)
	if new_max > old_max:
		run.hp += new_max - old_max
	run.hp = minf(run.hp, new_max)


static func in_shop(run: RunState) -> bool:
	return run.phase == "shop" and not run.over


static func equip_weapon(run: RunState, id: String) -> Dictionary:
	if not in_shop(run):
		return fail("Менять снаряжение можно только в магазине")
	if not run.weapons.has(id):
		return fail("Оружие не куплено")
	var old := StatCalc.max_hp(run)
	run.equipped_weapon = id
	refresh_max_hp(run, old)
	return {"ok": true}


static func equip_armor(run: RunState, id: String) -> Dictionary:
	if not in_shop(run):
		return fail("Менять снаряжение можно только в магазине")
	if id != "" and not run.armors.has(id):
		return fail("Броня не куплена")
	var old := StatCalc.max_hp(run)
	run.equipped_armor = id
	refresh_max_hp(run, old)
	# В магазине здоровье всегда полное: переключение брони не лечит в бою.
	if in_shop(run):
		run.hp = StatCalc.max_hp(run)
	return {"ok": true}


static func add_base(run: RunState, type: String, id: String) -> Dictionary:
	var old := StatCalc.max_hp(run)
	if type == "weapon":
		if run.weapons.has(id):
			return fail("Уже куплено")
		run.weapons[id] = {"rank": 1, "mastery": 0}
	else:
		if run.armors.has(id):
			return fail("Уже куплено")
		run.armors[id] = {"rank": 1, "mastery": 0}
		if run.equipped_armor == "":
			run.equipped_armor = id          # первая броня надевается сразу
	refresh_max_hp(run, old)
	return {"ok": true}


## Покупка одной части. Третья часть поглощает три и повышает ранг.
static func add_part(run: RunState, fam: String, target_rank: int, paid_price: int) -> Dictionary:
	var cur := run.family_rank(fam)
	if cur <= 0:
		return fail("Ветка не куплена")
	if cur >= target_rank:
		return fail("Ранг уже собран")
	if target_rank != cur + 1:
		return fail("Нельзя пропускать ранги")
	var key := str(target_rank)
	if not run.parts.has(fam):
		run.parts[fam] = {}
	if not run.parts[fam].has(key):
		run.parts[fam][key] = []
	run.parts[fam][key].append(paid_price)
	var need := GameData.parts_required(target_rank)
	var ranked := false
	if run.parts[fam][key].size() >= need:
		run.parts[fam].erase(key)
		if run.parts[fam].is_empty():
			run.parts.erase(fam)
		var old := StatCalc.max_hp(run)
		var sp := GameData.split_family(fam)
		if sp[0] == "weapon":
			run.weapons[sp[1]].rank = target_rank
		else:
			run.armors[sp[1]].rank = target_rank
		refresh_max_hp(run, old)
		ranked = true
	return {"ok": true, "ranked_up": ranked, "fam": fam, "rank": target_rank}


## Продажа несобранной части за 50% фактически уплаченного (вниз).
static func sell_part(run: RunState, fam: String, target_rank: int) -> Dictionary:
	if not in_shop(run):
		return fail("Продажа только в магазине")
	var arr: Array = run.part_prices(fam, target_rank)
	if arr.is_empty():
		return fail("Нет такой части")
	var paid: int = arr.pop_back()
	var refund := int(floor(paid * float(GameData.B.shop.sell_refund_fraction)))
	run.coins += refund
	if arr.is_empty():
		run.parts[fam].erase(str(target_rank))
		if run.parts[fam].is_empty():
			run.parts.erase(fam)
	return {"ok": true, "refund": refund}


# ---- модули ---------------------------------------------------------------
static func module_status(run: RunState, id: String) -> Dictionary:
	var m: Dictionary = GameData.modules[id]
	if run.modules.has(id):
		if int(run.modules[id].level) >= int(m.max_level):
			return fail("Максимальный уровень")
		return {"ok": true}
	if run.free_module_slots() <= 0:
		return fail("Нет свободной ячейки модулей")
	return {"ok": true}


static func add_module(run: RunState, id: String, paid_price: int) -> Dictionary:
	var st := module_status(run, id)
	if not st.ok:
		return st
	var old := StatCalc.max_hp(run)
	if run.modules.has(id):
		run.modules[id].level += 1
		run.modules[id].paid += paid_price
	else:
		run.modules[id] = {"level": 1, "paid": paid_price}
	refresh_max_hp(run, old)
	return {"ok": true}


static func sell_module(run: RunState, id: String) -> Dictionary:
	if not in_shop(run):
		return fail("Продажа только в магазине")
	if not run.modules.has(id):
		return fail("Модуль не установлен")
	var refund := int(floor(int(run.modules[id].paid) * float(GameData.B.shop.sell_refund_fraction)))
	var old := StatCalc.max_hp(run)
	run.modules.erase(id)
	run.coins += refund
	refresh_max_hp(run, old)
	run.hp = minf(run.hp, StatCalc.max_hp(run))
	if in_shop(run):
		run.hp = StatCalc.max_hp(run)
	return {"ok": true, "refund": refund}


# ---- мастерство -----------------------------------------------------------
static func mastery_status(run: RunState, kind: String) -> Dictionary:
	var cfg: Dictionary = GameData.B.shop.mastery
	if not in_shop(run):
		return fail("Только в магазине")
	if run.waves_completed < 1:
		return fail("Мастерство открывается после первой волны")
	if run.mastery_bought_this_shop:
		return fail("Мастерство уже куплено в этом магазине")
	var e: Dictionary
	if kind == "weapon":
		e = run.weapons.get(run.equipped_weapon, {})
	else:
		e = run.armors.get(run.equipped_armor, {})
	if e.is_empty():
		return fail("Нет экипированного предмета")
	if int(e.rank) < int(cfg.unlock_equipment_rank):
		return fail("Нужен V ранг")
	if run.coins < int(cfg.cost):
		return fail("Не хватает монет")
	return {"ok": true}


static func buy_mastery(run: RunState, kind: String) -> Dictionary:
	var st := mastery_status(run, kind)
	if not st.ok:
		return st
	var old := StatCalc.max_hp(run)
	run.coins -= int(GameData.B.shop.mastery.cost)
	if kind == "weapon":
		run.weapons[run.equipped_weapon].mastery += 1
	else:
		run.armors[run.equipped_armor].mastery += 1
	run.mastery_bought_this_shop = true
	refresh_max_hp(run, old)
	if in_shop(run):
		run.hp = StatCalc.max_hp(run)
	return {"ok": true}
