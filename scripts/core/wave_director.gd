class_name WaveDirector
extends RefCounted
## Составление волн: архетип, бюджет угрозы, конечная очередь спавна.
## Детерминированно от (seed забега, глобальная волна): повтор волны после
## перезапуска даёт тот же состав. Режиссёр не подстраивается под ХП игрока.

static var _arch_cache: Dictionary = {}


## Архетип волны с запретом более двух одинаковых подряд.
static func archetype_for(run_seed: int, gw: int) -> String:
	var key := run_seed
	var hist: Array
	if _arch_cache.has(key):
		hist = _arch_cache[key]
	else:
		hist = []
	var cfg: Dictionary = GameData.B.waves
	var weights: Dictionary = cfg.archetype_weights
	var streak_max := int(cfg.max_same_archetype_streak)
	while hist.size() < gw:
		var w := hist.size() + 1
		if is_boss_wave(w):
			hist.append("boss")           # боссовая волна обрывает серию архетипов
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([run_seed, w, "archetype"])
		var names: Array = []
		var ws: Array = []
		for n in weights:
			if hist.size() >= streak_max:
				var same := true
				for i in range(hist.size() - streak_max, hist.size()):
					if hist[i] != n:
						same = false
						break
				if same:
					continue
			names.append(n)
			ws.append(weights[n])
		var idx := ShopService._pick_weighted(rng, ws)
		hist.append(names[idx])
	_arch_cache[key] = hist
	return hist[gw - 1]


static func is_boss_wave(gw: int) -> bool:
	return ((gw - 1) % int(GameData.B.waves.sector_length)) + 1 == int(GameData.B.waves.sector_length)


static func build_plan(run_seed: int, gw: int) -> Dictionary:
	var sector := int(floor((gw - 1) / float(GameData.B.waves.sector_length))) + 1
	var info := LocationService.sector_info(run_seed, sector)
	if is_boss_wave(gw):
		var loc: Dictionary = GameData.locations[info.location_id]
		return {"wave": gw, "boss": true, "boss_id": loc.boss_id, "archetype": "boss", "budget": 0, "queue": [], "sector_info": info, "threat_total": 0}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, gw, "compose"])
	var cfg: Dictionary = GameData.B.waves
	var local := ((gw - 1) % int(cfg.sector_length)) + 1
	var arch := archetype_for(run_seed, gw)
	var budget_f := float(WaveMath.threat_budget(gw))
	if arch == "breather":
		budget_f *= float(cfg.breather_budget_multiplier)
	if local <= 2:
		budget_f *= 0.8                   # первые две волны сектора легче среднего
	if local == int(cfg.sector_length) - 1:
		budget_f *= 0.85                  # перед боссом — без максимальной комбинации
	# первое появление типа — немного легче и ограниченное число
	var new_types: Array = []
	for id in GameData.enemies:
		if int(GameData.enemies[id].first_wave) == gw:
			new_types.append(id)
	if not new_types.is_empty() and gw > 1:
		budget_f *= 0.85
	budget_f *= float(cfg.get("round_budget_scale", 1.0))      # раунд на 2 минуты — больше угрозы, растянутой по времени
	var budget := maxi(int(floor(budget_f)), 1)

	var weights: Dictionary = {}
	for id in GameData.B.waves.archetypes[arch]:
		if int(GameData.enemies[id].first_wave) <= gw:
			weights[id] = float(GameData.B.waves.archetypes[arch][id])
	if weights.is_empty():
		weights["drifter"] = 1.0
	var queue: Array = []
	var remaining := budget
	var counts := {}
	var elite_p := WaveMath.elite_probability(gw)
	var traits: Array = GameData.B.elites.traits

	# гарантированное представление нового типа (один экземпляр)
	for id in new_types:
		var c := int(GameData.enemies[id].threat_cost)
		if c <= int(budget * 0.5) or gw == 1:
			queue.append(_entry(id, ""))
			remaining -= c
			counts[id] = 1
			weights[id] = weights.get(id, 1.0)
	var guard := 0
	while remaining > 0 and guard < 600:
		guard += 1
		var ids: Array = []
		var ws: Array = []
		for id in weights:
			var c := int(GameData.enemies[id].threat_cost)
			if c > remaining:
				continue
			if new_types.has(id) and gw > 1:
				var cap := maxi(1, int(budget * 0.3 / maxf(c, 1)))
				if int(counts.get(id, 0)) >= cap:
					continue
			ids.append(id)
			ws.append(weights[id])
		if ids.is_empty():
			ids = ["drifter"]                 # остаток закрываем простейшими врагами (стоимость 1)
			ws = [1.0]
		var pick: String = ids[ShopService._pick_weighted(rng, ws)]
		var cost := int(GameData.enemies[pick].threat_cost)
		var trait_id := ""
		if elite_p > 0.0 and rng.randf() < elite_p and cost * 2 <= remaining:
			trait_id = traits[rng.randi() % traits.size()].id    # максимум одно свойство
			cost *= int(GameData.B.elites.threat_cost_multiplier)
		queue.append(_entry(pick, trait_id))
		remaining -= cost
		counts[pick] = int(counts.get(pick, 0)) + 1
	_shuffle(queue, rng)
	return {"wave": gw, "boss": false, "archetype": arch, "budget": budget, "queue": queue, "sector_info": info, "threat_total": budget - remaining, "counts": counts}


static func _entry(id: String, trait_id: String) -> Dictionary:
	return {"id": id, "trait": trait_id}


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


static func queue_cost(queue: Array) -> int:
	var total := 0
	for e in queue:
		var c := int(GameData.enemies[e.id].threat_cost)
		if e.trait != "":
			c *= int(GameData.B.elites.threat_cost_multiplier)
		total += c
	return total


static func archetype_title(arch: String) -> String:
	match arch:
		"swarm": return "Рой"
		"breakthrough": return "Прорыв"
		"hunt": return "Охота"
		"crossfire": return "Перекрёстный огонь"
		"breather": return "Передышка"
		"boss": return "Босс"
	return arch
