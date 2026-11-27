class_name RunState
extends RefCounted
## Всё состояние забега. Сериализуется в JSON (SaveService). Все числа 64 бит
## RNG хранятся строками (JSON float теряет точность выше 2^53).

const FORMAT_VERSION := 1

var seed_value: int = 1
var rng_shop := RandomNumberGenerator.new()      # отдельные генераторы: магазин
var created_unix: int = 0
var phase: String = "shop"                       # shop | combat | over
var over: bool = false
var waves_completed: int = 0                     # следующая волна = +1
var coins: int = 100
var hp: float = 100.0
var shop_level: int = 1
var weapons: Dictionary = {}                     # id -> {rank, mastery}
var armors: Dictionary = {}                      # id -> {rank, mastery}
var equipped_weapon: String = "pistol"
var equipped_armor: String = ""
var parts: Dictionary = {}                       # "weapon:carbine" -> {"2": [цены]}
var modules: Dictionary = {}                     # id -> {level, paid}
var offers: Array = []
var offer_seq: int = 0
var shop_locked: bool = false
var pity: int = 0
var mastery_bought_this_shop: bool = false
var last_purchase: Dictionary = {}
var coins_at_wave_start: int = 0
var archetype_history: Array = []
var play_time: float = 0.0                       # секунды боя
var stats: Dictionary = {}                       # kills, damage, shots, hits, purchases...
var last_reward: Dictionary = {}                 # последняя выплата (для UI)
var medkits: int = 1                             # запас аптечек: покупаются, неиспользованные переносятся
var bonus_case: Dictionary = {}                  # {wave, options:[id,id,id]} — неоткрытый кейс; не перебрасывается при перезагрузке
var active_debuff: Dictionary = {}               # {id, waves_left} — обязательный дебафф из ящика с проклятием
var active_bonus: Dictionary = {}                # {id, waves_left}


static func new_run(p_seed: int = -1) -> RunState:
	GameData.ensure()
	var r := RunState.new()
	if p_seed < 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		p_seed = rng.randi() % 2147483647
	r.seed_value = maxi(p_seed, 1)
	r.rng_shop.seed = hash([r.seed_value, "shop"])
	r.created_unix = int(Time.get_unix_time_from_system())
	var p: Dictionary = GameData.B.player
	r.coins = int(p.starting_coins)
	r.weapons[p.starting_weapon] = {"rank": int(p.starting_rank), "mastery": 0}
	r.equipped_weapon = p.starting_weapon
	r.shop_level = 1
	r.medkits = int(GameData.B.medkit.stock_at_wave_start)
	r.stats = {"kills": 0, "damage": 0.0, "shots": 0, "hits": 0, "purchases": 0, "deaths_by": "", "wave_log": []}
	r.hp = StatCalc.max_hp(r)
	ShopService.generate_offers(r, false)
	return r


func next_wave() -> int:
	return waves_completed + 1


func sector_of(global_wave: int) -> int:
	return int(floor((global_wave - 1) / float(GameData.B.waves.sector_length))) + 1


func local_wave_of(global_wave: int) -> int:
	return ((global_wave - 1) % int(GameData.B.waves.sector_length)) + 1


func is_boss_wave(global_wave: int) -> bool:
	return local_wave_of(global_wave) == int(GameData.B.waves.sector_length)


func family_rank(key: String) -> int:
	var sp := GameData.split_family(key)
	var d: Dictionary = weapons if sp[0] == "weapon" else armors
	if d.has(sp[1]):
		return int(d[sp[1]].rank)
	return 0


func part_count(key: String, target_rank: int) -> int:
	if parts.has(key) and parts[key].has(str(target_rank)):
		return parts[key][str(target_rank)].size()
	return 0


func part_prices(key: String, target_rank: int) -> Array:
	if parts.has(key) and parts[key].has(str(target_rank)):
		return parts[key][str(target_rank)]
	return []


func used_module_slots() -> int:
	return modules.size()


func free_module_slots() -> int:
	return GameData.module_slots(shop_level) - modules.size()


# ---- сериализация ----------------------------------------------------------
func to_dict() -> Dictionary:
	return {
		"format": FORMAT_VERSION,
		"seed": seed_value,
		"rng_shop_seed": str(rng_shop.seed),
		"rng_shop_state": str(rng_shop.state),
		"created_unix": created_unix,
		"phase": phase,
		"over": over,
		"waves_completed": waves_completed,
		"coins": coins,
		"hp": hp,
		"shop_level": shop_level,
		"weapons": weapons.duplicate(true),
		"armors": armors.duplicate(true),
		"equipped_weapon": equipped_weapon,
		"equipped_armor": equipped_armor,
		"parts": parts.duplicate(true),
		"modules": modules.duplicate(true),
		"offers": offers.duplicate(true),
		"offer_seq": offer_seq,
		"shop_locked": shop_locked,
		"pity": pity,
		"mastery_bought_this_shop": mastery_bought_this_shop,
		"last_purchase": last_purchase.duplicate(true),
		"coins_at_wave_start": coins_at_wave_start,
		"archetype_history": archetype_history.duplicate(),
		"play_time": play_time,
		"stats": stats.duplicate(true),
		"last_reward": last_reward.duplicate(true),
		"medkits": medkits,
		"bonus_case": bonus_case.duplicate(true),
		"active_bonus": active_bonus.duplicate(true),
		"active_debuff": active_debuff.duplicate(true),
	}


## Восстановление. Возвращает null при несовместимости/повреждении.
static func from_dict(d: Dictionary) -> RunState:
	GameData.ensure()
	if int(d.get("format", 0)) != FORMAT_VERSION:
		return null
	for k in ["seed", "phase", "coins", "weapons", "armors", "offers", "shop_level", "waves_completed", "equipped_weapon"]:
		if not d.has(k):
			return null
	var r := RunState.new()
	r.seed_value = int(d.seed)
	r.rng_shop.seed = int(str(d.get("rng_shop_seed", "1")))
	r.rng_shop.state = int(str(d.get("rng_shop_state", "1")))
	r.created_unix = int(d.get("created_unix", 0))
	r.phase = str(d.phase)
	r.over = bool(d.get("over", false))
	r.waves_completed = int(d.waves_completed)
	r.coins = int(d.coins)
	r.hp = float(d.get("hp", 100.0))
	r.shop_level = clampi(int(d.shop_level), 1, GameData.max_shop_level())
	r.weapons = _norm_equip(d.weapons)
	r.armors = _norm_equip(d.armors)
	r.equipped_weapon = str(d.equipped_weapon)
	r.equipped_armor = str(d.get("equipped_armor", ""))
	r.parts = {}
	var dp: Dictionary = d.get("parts", {})
	for fam in dp:
		r.parts[fam] = {}
		for tr in dp[fam]:
			var arr: Array = []
			for v in dp[fam][tr]:
				arr.append(int(v))
			r.parts[fam][tr] = arr
	r.modules = {}
	var dm: Dictionary = d.get("modules", {})
	for id in dm:
		r.modules[id] = {"level": int(dm[id].level), "paid": int(dm[id].paid)}
	r.offers = []
	for o in d.offers:
		var oo: Dictionary = o.duplicate(true)
		for k in ["uid", "price", "target_rank"]:
			if oo.has(k):
				oo[k] = int(oo[k])
		r.offers.append(oo)
	r.offer_seq = int(d.get("offer_seq", 0))
	r.shop_locked = bool(d.get("shop_locked", false))
	r.pity = int(d.get("pity", 0))
	r.mastery_bought_this_shop = bool(d.get("mastery_bought_this_shop", false))
	r.last_purchase = d.get("last_purchase", {})
	r.coins_at_wave_start = int(d.get("coins_at_wave_start", 0))
	r.archetype_history = d.get("archetype_history", [])
	r.play_time = float(d.get("play_time", 0.0))
	r.stats = d.get("stats", {})
	r.last_reward = d.get("last_reward", {})
	r.medkits = clampi(int(d.get("medkits", 1)), 0, int(GameData.B.medkit.max_stock))
	r.bonus_case = d.get("bonus_case", {})
	if r.bonus_case.has("wave"):
		r.bonus_case["wave"] = int(r.bonus_case.wave)
	r.active_debuff = d.get("active_debuff", {})
	if r.active_debuff.has("waves_left"):
		r.active_debuff["waves_left"] = int(r.active_debuff.waves_left)
	r.active_bonus = d.get("active_bonus", {})
	if r.active_bonus.has("waves_left"):
		r.active_bonus["waves_left"] = int(r.active_bonus.waves_left)
	if not r.validate().is_empty():
		return null
	return r


static func _norm_equip(src: Dictionary) -> Dictionary:
	var out := {}
	for id in src:
		out[id] = {"rank": int(src[id].rank), "mastery": int(src[id].get("mastery", 0))}
	return out


## Логическая проверка загруженного состояния.
func validate() -> Array:
	var err: Array = []
	for id in weapons:
		if not GameData.weapons.has(id):
			err.append("неизвестное оружие " + id)
		elif weapons[id].rank < 1 or weapons[id].rank > 5:
			err.append("ранг оружия")
	for id in armors:
		if not GameData.armors.has(id):
			err.append("неизвестная броня " + id)
		elif armors[id].rank < 1 or armors[id].rank > 5:
			err.append("ранг брони")
	if not weapons.has(equipped_weapon):
		err.append("активное оружие не куплено")
	if equipped_armor != "" and not armors.has(equipped_armor):
		err.append("экипированная броня не куплена")
	for id in modules:
		if not GameData.modules.has(id):
			err.append("неизвестный модуль " + id)
	if coins < 0:
		err.append("отрицательные монеты")
	if offers.size() != int(GameData.B.shop.offer_count):
		err.append("число карточек")
	if not ["shop", "combat", "over"].has(phase):
		err.append("фаза")
	return err
