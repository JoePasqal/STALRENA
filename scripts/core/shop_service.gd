class_name ShopService
extends RefCounted
## Магазин: генерация шести предложений, покупка, обновление, замок, уровень,
## защита от неудачи (pity), продажа. Атомарные команды; UI только вызывает их.

const OFFER_KINDS := ["base", "part", "module", "complete"]


static func fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


# ---- кандидаты ------------------------------------------------------------
static func base_candidates(run: RunState, taken: Dictionary) -> Array:
	var out: Array = []
	for id in GameData.weapon_ids:
		if run.weapons.has(id) or taken.has("weapon:" + id):
			continue
		if int(GameData.weapons[id].unlocks_at_shop_level) > run.shop_level:
			continue
		out.append({"type": "weapon", "id": id})
	for id in GameData.armor_ids:
		if run.armors.has(id) or taken.has("armor:" + id):
			continue
		out.append({"type": "armor", "id": id})
	return out


## Части следующего ранга уже купленных веток, доступные на уровне магазина.
static func part_candidates(run: RunState) -> Array:
	var out: Array = []
	var allowed := GameData.allowed_ranks(run.shop_level)
	for id in run.weapons:
		var r := int(run.weapons[id].rank)
		if r < 5 and allowed.has(r + 1):
			out.append({"type": "weapon", "id": id, "fam": "weapon:" + id, "target": r + 1})
	for id in run.armors:
		var r := int(run.armors[id].rank)
		if r < 5 and allowed.has(r + 1):
			out.append({"type": "armor", "id": id, "fam": "armor:" + id, "target": r + 1})
	return out


static func module_candidates(run: RunState) -> Array:
	var out: Array = []
	for id in GameData.module_ids:
		if run.modules.has(id):
			if int(run.modules[id].level) < int(GameData.modules[id].max_level):
				out.append({"id": id})
		else:
			out.append({"id": id})
	return out


## Цели pity: часть для активного оружия / экипированной брони.
static func pity_targets(run: RunState) -> Array:
	var out: Array = []
	var allowed := GameData.allowed_ranks(run.shop_level)
	if run.weapons.has(run.equipped_weapon):
		var r := int(run.weapons[run.equipped_weapon].rank)
		if r < 5 and allowed.has(r + 1):
			out.append({"type": "weapon", "id": run.equipped_weapon, "fam": "weapon:" + run.equipped_weapon, "target": r + 1})
	if run.equipped_armor != "" and run.armors.has(run.equipped_armor):
		var r2 := int(run.armors[run.equipped_armor].rank)
		if r2 < 5 and allowed.has(r2 + 1):
			out.append({"type": "armor", "id": run.equipped_armor, "fam": "armor:" + run.equipped_armor, "target": r2 + 1})
	return out


static func has_any_candidate(run: RunState) -> bool:
	return not base_candidates(run, {}).is_empty() or not part_candidates(run).is_empty() or not module_candidates(run).is_empty()


# ---- генерация ------------------------------------------------------------
static func _pick_weighted(rng: RandomNumberGenerator, weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += float(w)
	if total <= 0.0:
		return -1
	var x := rng.randf() * total
	var acc := 0.0
	for i in weights.size():
		acc += float(weights[i])
		if x < acc and float(weights[i]) > 0.0:
			return i
	# защита от погрешности: последний положительный вес
	for i in range(weights.size() - 1, -1, -1):
		if float(weights[i]) > 0.0:
			return i
	return -1


static func _new_offer(run: RunState, kind: String) -> Dictionary:
	run.offer_seq += 1
	return {"uid": run.offer_seq, "kind": kind, "type": "", "id": "", "fam": "", "target_rank": 0, "price": 0, "bought": false}


static func _make_part_offer(run: RunState, c: Dictionary) -> Dictionary:
	var o := _new_offer(run, "part")
	o.type = c.type
	o.id = c.id
	o.fam = c.fam
	o.target_rank = int(c.target)
	o.price = GameData.part_price(int(c.target))
	return o


static func _gen_slot(run: RunState, taken: Dictionary) -> Dictionary:
	var cfg: Dictionary = GameData.B.shop
	var cats: Array = []
	var weights: Array = []
	var bases := base_candidates(run, taken)
	var parts := part_candidates(run)
	var mods := module_candidates(run)
	if not bases.is_empty():
		cats.append("base"); weights.append(cfg.category_weights.base_equipment)
	if not parts.is_empty():
		cats.append("part"); weights.append(cfg.category_weights.parts)
	if not mods.is_empty():
		cats.append("module"); weights.append(cfg.category_weights.modules)
	var ci := _pick_weighted(run.rng_shop, weights)
	if ci < 0:
		return _new_offer(run, "complete")
	match cats[ci]:
		"base":
			var c: Dictionary = bases[run.rng_shop.randi() % bases.size()]
			var o := _new_offer(run, "base")
			o.type = c.type
			o.id = c.id
			o.price = int(GameData.weapons[c.id].base_price) if c.type == "weapon" else int(GameData.armors[c.id].base_price)
			taken[c.type + ":" + c.id] = true
			return o
		"part":
			# ранг по весам уровня среди допустимых, затем предмет
			var ranks: Array = []
			var rw: Array = []
			var wdef: Dictionary = GameData.shop_level_def(run.shop_level).rank_weights
			for c in parts:
				if not ranks.has(c.target):
					ranks.append(c.target)
			ranks.sort()
			for r in ranks:
				rw.append(float(wdef.get(str(r), 0)))
			var ri := _pick_weighted(run.rng_shop, rw)
			if ri < 0:
				ri = 0
			var pool: Array = []
			for c in parts:
				if c.target == ranks[ri]:
					pool.append(c)
			return _make_part_offer(run, pool[run.rng_shop.randi() % pool.size()])
		"module":
			var mc: Dictionary = mods[run.rng_shop.randi() % mods.size()]
			var mo := _new_offer(run, "module")
			mo.type = "module"
			mo.id = mc.id
			mo.price = int(GameData.modules[mc.id].price_per_copy)
			return mo
	return _new_offer(run, "complete")


## Полная замена шести предложений. paid=true — обновление за монеты (учёт pity).
static func generate_offers(run: RunState, paid: bool) -> void:
	var n := int(GameData.B.shop.offer_count)
	var threshold := int(GameData.B.shop.pity_failed_paid_rerolls_before_guarantee)
	var targets := pity_targets(run)
	var guarantee_slot := -1
	var guarantee_target: Dictionary = {}
	if paid and run.pity >= threshold and not targets.is_empty():
		guarantee_slot = run.rng_shop.randi() % n
		guarantee_target = targets[run.rng_shop.randi() % targets.size()]
	var taken := {}
	var out: Array = []
	for i in n:
		if i == guarantee_slot:
			out.append(_make_part_offer(run, guarantee_target))
		else:
			out.append(_gen_slot(run, taken))
	run.offers = out
	run.shop_locked = false
	_update_pity(run, paid)


static func offers_contain_pity_part(run: RunState) -> bool:
	var targets := pity_targets(run)
	for o in run.offers:
		if o.kind != "part" or o.bought:
			continue
		for t in targets:
			if o.fam == t.fam and int(o.target_rank) == int(t.target):
				return true
	return false


static func _update_pity(run: RunState, paid: bool) -> void:
	if pity_targets(run).is_empty():
		return                                  # цели нет: счётчик заморожен
	if offers_contain_pity_part(run):
		run.pity = 0
	elif paid:
		run.pity += 1


# ---- состояние карточек ---------------------------------------------------
## Можно ли сейчас купить предложение (без учёта денег).
static func offer_status(run: RunState, o: Dictionary) -> Dictionary:
	if o.bought:
		return fail("Куплено")
	match o.kind:
		"base":
			var owned: bool = run.weapons.has(o.id) if o.type == "weapon" else run.armors.has(o.id)
			if owned:
				return fail("Уже куплено")
			if o.type == "weapon" and int(GameData.weapons[o.id].unlocks_at_shop_level) > run.shop_level:
				return fail("Нужен уровень магазина")
			return {"ok": true}
		"part":
			var cur := run.family_rank(o.fam)
			if cur <= 0:
				return fail("Ветка не куплена")
			if cur >= int(o.target_rank):
				return fail("Ранг уже собран")
			if int(o.target_rank) != cur + 1:
				return fail("Недоступно")
			return {"ok": true}
		"module":
			return Inventory.module_status(run, o.id)
		_:
			return fail("Сборка завершена")


static func find_offer(run: RunState, uid: int) -> int:
	for i in run.offers.size():
		if int(run.offers[i].uid) == uid:
			return i
	return -1


## Атомарная покупка: проверки → списание → выдача → пометка карточки.
static func buy(run: RunState, uid: int) -> Dictionary:
	if not Inventory.in_shop(run):
		return fail("Покупки только в магазине")
	var idx := find_offer(run, uid)
	if idx < 0:
		return fail("Нет такого предложения")
	var o: Dictionary = run.offers[idx]
	if o.bought:
		return fail("Уже куплено")
	var st := offer_status(run, o)
	if not st.ok:
		return st
	var price := int(o.price)
	if run.coins < price or price < 0:
		return fail("Не хватает монет")
	var res: Dictionary = {}
	match o.kind:
		"base":
			res = Inventory.add_base(run, o.type, o.id)
		"part":
			res = Inventory.add_part(run, o.fam, int(o.target_rank), price)
		"module":
			res = Inventory.add_module(run, o.id, price)
		_:
			return fail("Сборка завершена")
	if not res.ok:
		return res
	run.coins -= price
	run.offers[idx].bought = true
	run.last_purchase = {"uid": uid, "kind": o.kind, "type": o.type, "id": o.id, "price": price}
	run.stats["purchases"] = int(run.stats.get("purchases", 0)) + 1
	run.hp = StatCalc.max_hp(run)           # в магазине здоровье полное
	res["ok"] = true
	res["price"] = price
	return res


static func can_refresh(run: RunState) -> Dictionary:
	if not Inventory.in_shop(run):
		return fail("Только в магазине")
	if not has_any_candidate(run):
		return fail("Сборка завершена — обновлять нечего")
	if run.coins < int(GameData.B.shop.refresh_cost):
		return fail("Не хватает монет")
	return {"ok": true}


static func refresh(run: RunState) -> Dictionary:
	var st := can_refresh(run)
	if not st.ok:
		return st
	var was_locked := run.shop_locked
	run.coins -= int(GameData.B.shop.refresh_cost)
	generate_offers(run, true)
	return {"ok": true, "lock_cleared": was_locked}


static func set_lock(run: RunState, value: bool) -> Dictionary:
	if not Inventory.in_shop(run):
		return fail("Только в магазине")
	run.shop_locked = value
	return {"ok": true}


## Следующий уровень магазина: цена и требование минимальной пройденной волны.
static func upgrade_status(run: RunState) -> Dictionary:
	if not Inventory.in_shop(run):
		return fail("Только в магазине")
	if run.shop_level >= GameData.max_shop_level():
		return {"ok": false, "reason": "Максимальный уровень", "max": true}
	var nxt := GameData.shop_level_def(run.shop_level + 1)
	if run.waves_completed < int(nxt.minimum_completed_wave):
		return {"ok": false, "reason": "Нужно пройти волн: %d" % int(nxt.minimum_completed_wave), "cost": int(nxt.upgrade_cost_from_previous)}
	if run.coins < int(nxt.upgrade_cost_from_previous):
		return {"ok": false, "reason": "Не хватает монет", "cost": int(nxt.upgrade_cost_from_previous)}
	return {"ok": true, "cost": int(nxt.upgrade_cost_from_previous)}


static func upgrade_shop(run: RunState) -> Dictionary:
	var st := upgrade_status(run)
	if not st.ok:
		return st
	run.coins -= int(st.cost)
	run.shop_level += 1
	# Уже показанные предложения не обновляются бесплатно.
	return {"ok": true, "level": run.shop_level}


# ---- вход в магазин / начало волны -----------------------------------------
## Вызывается один раз после победы (внутри Economy.complete_wave).
static func on_enter_shop(run: RunState) -> void:
	run.mastery_bought_this_shop = false
	if run.shop_locked:
		run.shop_locked = false         # замок действует на один вход; набор и пустые места сохраняются
	else:
		generate_offers(run, false)


## Начало боя: снимок монет, полное ХП, переход в фазу combat.
static func begin_wave(run: RunState) -> Dictionary:
	if run.phase != "shop" or run.over:
		return fail("Волна уже идёт")
	run.coins_at_wave_start = run.coins
	run.hp = StatCalc.max_hp(run)
	run.phase = "combat"
	return {"ok": true, "wave": run.next_wave()}
