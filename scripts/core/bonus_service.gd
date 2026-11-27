class_name BonusService
extends RefCounted
## Бонус-кейс: каждые N (10) пройденных волн — 3 закрытые карточки, выбор одной, бонус на 2 следующие волны.
## Варианты детерминированы от (seed забега, волна) и хранятся в сохранении: перезагрузка не даёт перебросить кейс.


static func interval() -> int:
	return int(GameData.bonus_cfg.interval_waves)


static func duration() -> int:
	return int(GameData.bonus_cfg.duration_waves)


## Вызывается при входе в магазин после победы (Economy.complete_wave). Сначала снимается срок действия
## предыдущего бонуса, затем, если волна кратна 10, создаётся кейс.
static func on_wave_completed(run: RunState, wave: int) -> void:
	if not run.active_bonus.is_empty():
		run.active_bonus["waves_left"] = int(run.active_bonus.waves_left) - 1
		if int(run.active_bonus.waves_left) <= 0:
			run.active_bonus = {}
	if wave > 0 and wave % interval() == 0:
		run.bonus_case = make_case(run.seed_value, wave)


static func make_case(seed_value: int, wave: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, wave, "bonus_case"])
	var pool: Array = GameData.bonus_ids.duplicate()
	var opts: Array = []
	for i in int(GameData.bonus_cfg.options_count):
		var k := rng.randi() % pool.size()
		opts.append(pool[k])
		pool.remove_at(k)                 # три РАЗНЫХ бонуса
	return {"wave": wave, "options": opts}


static func has_case(run: RunState) -> bool:
	return not run.bonus_case.is_empty() and run.bonus_case.has("options")


## Выбор карточки: бонус применяется сразу и атомарно, кейс закрывается. Повтор не срабатывает.
static func pick(run: RunState, index: int) -> Dictionary:
	if not has_case(run) or run.phase != "shop":
		return {"ok": false, "reason": "Кейса нет"}
	var opts: Array = run.bonus_case.options
	if index < 0 or index >= opts.size():
		return {"ok": false, "reason": "Нет такой карточки"}
	var id: String = opts[index]
	var old := StatCalc.max_hp(run)
	run.active_bonus = {"id": id, "waves_left": duration()}
	run.bonus_case = {}
	Inventory.refresh_max_hp(run, old)
	run.hp = StatCalc.max_hp(run)
	return {"ok": true, "id": id, "options": opts, "index": index}


static func active_def(run: RunState) -> Dictionary:
	if run.active_bonus.is_empty() or not GameData.bonuses.has(str(run.active_bonus.get("id", ""))):
		return {}
	return GameData.bonuses[str(run.active_bonus.id)]


static func effects(run: RunState) -> Dictionary:
	var d := active_def(run)
	return d.get("effects", {})


static func coin_bonus(run: RunState) -> float:
	return float(active_def(run).get("coin_bonus", 0.0))
