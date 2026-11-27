class_name BonusService
extends RefCounted
## Ящики после волн:
##  * бонус-кейс (золотой) — после каждой 10-й волны: 3 карточки с баффами, бафф действует 2 следующие волны;
##  * ящик с проклятием (деревянный с красной окантовкой) — после 10-й волны каждые 2 волны, кроме кратных 10:
##    3 карточки с дебаффами, выбор обязателен, дебафф действует 1 следующий раунд.
## Варианты детерминированы от (seed забега, волна, вид) и хранятся в сохранении: перезагрузка не даёт перебросить ящик.


static func interval() -> int:
	return int(GameData.bonus_cfg.interval_waves)


static func duration() -> int:
	return int(GameData.bonus_cfg.duration_waves)


static func debuff_duration() -> int:
	return int(GameData.bonus_cfg.get("debuff_duration_waves", 1))


## Какой ящик положен после этой пройденной волны: "buff" | "debuff" | "".
static func case_kind_for(wave: int) -> String:
	if wave <= 0:
		return ""
	if wave % interval() == 0:
		return "buff"
	var after := int(GameData.bonus_cfg.get("debuff_after_wave", 10))
	var step := int(GameData.bonus_cfg.get("debuff_interval_waves", 2))
	if wave > after and (wave - after) % step == 0:
		return "debuff"
	return ""


## Вызывается при входе в магазин после победы (Economy.complete_wave): сначала снимается срок действия
## активных эффектов, затем создаётся ящик, если он положен.
static func on_wave_completed(run: RunState, wave: int) -> void:
	for key in ["active_bonus", "active_debuff"]:
		var cur: Dictionary = run.get(key)
		if not cur.is_empty():
			cur["waves_left"] = int(cur.waves_left) - 1
			if int(cur.waves_left) <= 0:
				run.set(key, {})
	var kind := case_kind_for(wave)
	if kind != "":
		run.bonus_case = make_case(run.seed_value, wave, kind)


static func pool(kind: String) -> Array:
	return GameData.debuff_ids.duplicate() if kind == "debuff" else GameData.bonus_ids.duplicate()


static func def_of(kind: String, id: String) -> Dictionary:
	return GameData.debuffs.get(id, {}) if kind == "debuff" else GameData.bonuses.get(id, {})


static func make_case(seed_value: int, wave: int, kind: String = "buff") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, wave, "bonus_case" if kind == "buff" else "curse_case"])
	var p: Array = pool(kind)
	var opts: Array = []
	for i in int(GameData.bonus_cfg.options_count):
		var k := rng.randi() % p.size()
		opts.append(p[k])
		p.remove_at(k)                    # три РАЗНЫХ карточки
	return {"wave": wave, "kind": kind, "options": opts}


static func has_case(run: RunState) -> bool:
	return not run.bonus_case.is_empty() and run.bonus_case.has("options")


static func case_kind(run: RunState) -> String:
	return str(run.bonus_case.get("kind", "buff"))


## Выбор карточки: эффект применяется сразу и атомарно, ящик закрывается. Повтор не срабатывает.
static func pick(run: RunState, index: int) -> Dictionary:
	if not has_case(run) or run.phase != "shop":
		return {"ok": false, "reason": "Ящика нет"}
	var opts: Array = run.bonus_case.options
	if index < 0 or index >= opts.size():
		return {"ok": false, "reason": "Нет такой карточки"}
	var kind := case_kind(run)
	var id: String = opts[index]
	var old := StatCalc.max_hp(run)
	if kind == "debuff":
		run.active_debuff = {"id": id, "waves_left": debuff_duration()}
	else:
		run.active_bonus = {"id": id, "waves_left": duration()}
	run.bonus_case = {}
	Inventory.refresh_max_hp(run, old)
	run.hp = StatCalc.max_hp(run)
	return {"ok": true, "id": id, "kind": kind, "options": opts, "index": index}


static func active_def(run: RunState) -> Dictionary:
	if run.active_bonus.is_empty() or not GameData.bonuses.has(str(run.active_bonus.get("id", ""))):
		return {}
	return GameData.bonuses[str(run.active_bonus.id)]


static func active_debuff_def(run: RunState) -> Dictionary:
	if run.active_debuff.is_empty() or not GameData.debuffs.has(str(run.active_debuff.get("id", ""))):
		return {}
	return GameData.debuffs[str(run.active_debuff.id)]


## Суммарные характеристики активного бафа и дебафа (ключи те же, что у модулей; общие caps остаются).
static func effects(run: RunState) -> Dictionary:
	var out := {}
	for d in [active_def(run), active_debuff_def(run)]:
		var e: Dictionary = d.get("effects", {})
		for k in e:
			out[k] = float(out.get(k, 0.0)) + float(e[k])
	return out


static func coin_bonus(run: RunState) -> float:
	return float(active_def(run).get("coin_bonus", 0.0)) + float(active_debuff_def(run).get("coin_bonus", 0.0))


static func medkit_heal_mult(run: RunState) -> float:
	return float(active_debuff_def(run).get("medkit_heal_mult", 1.0))


static func molotov(run: RunState) -> Dictionary:
	return active_debuff_def(run).get("molotov", {})
