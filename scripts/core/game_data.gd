class_name GameData
extends RefCounted
## Статический доступ к данным баланса (data/balance_v1.json) и раскладкам арен.
## Не зависит от автозагрузок — используется и в тестах без сцены.

const BALANCE_PATH := "res://data/balance_v1.json"
const LAYOUTS_PATH := "res://data/layouts_v1.json"
const MODIFIERS_PATH := "res://data/arena_modifiers_v1.json"
const BONUSES_PATH := "res://data/bonuses_v1.json"

static var B: Dictionary = {}
static var layouts: Dictionary = {}          # id -> layout dict
static var layouts_by_location: Dictionary = {}
static var bonus_cfg: Dictionary = {}              # data/bonuses_v1.json
static var bonuses: Dictionary = {}
static var bonus_ids: Array = []
static var debuffs: Dictionary = {}
static var debuff_ids: Array = []
static var modifiers: Dictionary = {}          # steam/electric/toxic: параметры опасностей арены
static var weapons: Dictionary = {}
static var weapon_ids: Array = []
static var armors: Dictionary = {}
static var armor_ids: Array = []
static var modules: Dictionary = {}
static var module_ids: Array = []
static var sets: Dictionary = {}
static var enemies: Dictionary = {}
static var bosses: Dictionary = {}
static var locations: Dictionary = {}
static var location_order: Array = []
static var _ready_flag := false


static func ensure() -> void:
	if not _ready_flag:
		load_all()


static func load_all(path: String = BALANCE_PATH, layouts_path: String = LAYOUTS_PATH) -> void:
	B = _read_json(path)
	weapons.clear(); weapon_ids.clear()
	for w in B.get("weapons", []):
		weapons[w.id] = w
		weapon_ids.append(w.id)
	armors.clear(); armor_ids.clear()
	for a in B.get("armors", []):
		armors[a.id] = a
		armor_ids.append(a.id)
	modules.clear(); module_ids.clear()
	for m in B.get("modules", []):
		modules[m.id] = m
		module_ids.append(m.id)
	sets.clear()
	for s in B.get("module_sets", []):
		sets[s.id] = s
	enemies.clear()
	for e in B.get("enemies", []):
		enemies[e.id] = e
	bosses.clear()
	for b in B.get("bosses", []):
		bosses[b.id] = b
	locations.clear(); location_order.clear()
	for l in B.get("locations", []):
		locations[l.id] = l
		location_order.append(l.id)
	layouts.clear(); layouts_by_location.clear()
	var ld := _read_json(layouts_path)
	for l in ld.get("layouts", []):
		layouts[l.id] = l
		if not layouts_by_location.has(l.location_id):
			layouts_by_location[l.location_id] = []
		layouts_by_location[l.location_id].append(l.id)
	modifiers = _read_json(MODIFIERS_PATH).get("modifiers", {})
	bonus_cfg = _read_json(BONUSES_PATH)
	bonuses.clear(); bonus_ids.clear()
	for b in bonus_cfg.get("bonuses", []):
		bonuses[b.id] = b
		bonus_ids.append(b.id)
	debuffs.clear(); debuff_ids.clear()
	for b in bonus_cfg.get("debuffs", []):
		debuffs[b.id] = b
		debuff_ids.append(b.id)
	_ready_flag = true


static func _read_json(path: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string(path)
	if txt == "":
		push_error("GameData: не удалось прочитать %s" % path)
		return {}
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("GameData: некорректный JSON %s" % path)
		return {}
	return parsed


# ---- удобные аксессоры ----------------------------------------------------
static func ranks() -> Array:
	return B.ranks


static func rank_def(rank: int) -> Dictionary:
	return B.ranks[clampi(rank, 1, 5) - 1]


static func rank_mult(rank: int) -> float:
	return float(rank_def(rank).damage_multiplier)


static func parts_required(target_rank: int) -> int:
	return int(rank_def(target_rank).parts_required)


static func part_price(target_rank: int) -> int:
	return int(rank_def(target_rank).part_price)


static func rank_name(rank: int) -> String:
	return str(rank_def(rank).name)


const ROMAN := ["I", "II", "III", "IV", "V"]


static func rank_roman(rank: int) -> String:
	return ROMAN[clampi(rank, 1, 5) - 1]


static func shop_cfg() -> Dictionary:
	return B.shop


static func shop_level_def(level: int) -> Dictionary:
	var lv: Array = B.shop.levels
	return lv[clampi(level, 1, lv.size()) - 1]


static func max_shop_level() -> int:
	return B.shop.levels.size()


static func module_slots(level: int) -> int:
	return int(shop_level_def(level).module_slots)


## Ранги, доступные для генерации частей на данном уровне магазина.
static func allowed_ranks(level: int) -> Array:
	var out: Array = []
	var w: Dictionary = shop_level_def(level).rank_weights
	for r in range(1, 6):
		if float(w.get(str(r), 0)) > 0.0:
			out.append(r)
	return out


static func item_name(type: String, id: String) -> String:
	match type:
		"weapon": return str(weapons[id].name)
		"armor": return str(armors[id].name)
		"module": return str(modules[id].name)
	return id


static func family_key(type: String, id: String) -> String:
	return "%s:%s" % [type, id]


static func split_family(key: String) -> Array:
	return key.split(":")


## Проверка согласованности данных. Возвращает список ошибок (пустой — всё хорошо).
static func validate() -> Array:
	ensure()
	var err: Array = []
	if B.is_empty():
		return ["balance_v1.json не загружен"]
	if B.ranks.size() != 5:
		err.append("ranks != 5")
	for w in weapons.values():
		for k in ["base_price", "base_damage", "shots_per_second", "magazine", "reload_seconds", "range_units", "spread_degrees", "projectiles_per_shot", "fire_mode"]:
			if not w.has(k):
				err.append("weapon %s: нет поля %s" % [w.id, k])
	for a in armors.values():
		if a.hp_by_rank.size() != 5:
			err.append("armor %s: hp_by_rank != 5" % a.id)
	for m in modules.values():
		if not sets.has(m.set_id):
			err.append("module %s: неизвестный набор %s" % [m.id, m.set_id])
	for s in sets.values():
		if s.requires.size() != 3:
			err.append("set %s: требуется 3 модуля" % s.id)
		var seen := {}
		for r in s.requires:
			if not modules.has(r):
				err.append("set %s: нет модуля %s" % [s.id, r])
			if seen.has(r):
				err.append("set %s: повтор модуля %s" % [s.id, r])
			seen[r] = true
	for e in enemies.values():
		if e.has("children_id") and not enemies.has(e.children_id):
			err.append("enemy %s: нет ребёнка %s" % [e.id, e.children_id])
		if int(e.threat_cost) < 1:
			err.append("enemy %s: threat_cost < 1" % e.id)
	for arch in B.waves.archetypes:
		for eid in B.waves.archetypes[arch]:
			if not enemies.has(eid):
				err.append("archetype %s: нет врага %s" % [arch, eid])
	if not B.waves.archetypes.has("breather"):
		err.append("нет архетипа breather")
	for b in bosses.values():
		if not locations.has(b.location_id):
			err.append("boss %s: нет локации" % b.id)
	for l in locations.values():
		if not bosses.has(l.boss_id):
			err.append("location %s: нет босса" % l.id)
		if not layouts_by_location.has(l.id) or layouts_by_location[l.id].size() < int(l.minimum_layout_variants):
			err.append("location %s: недостаточно раскладок" % l.id)
	for lv in B.shop.levels:
		var tot := 0.0
		for k in lv.rank_weights:
			tot += float(lv.rank_weights[k])
		if tot <= 0.0:
			err.append("shop level %s: пустые веса рангов" % lv.level)
	if bonus_ids.size() < int(bonus_cfg.get("options_count", 3)):
		err.append("бонусов меньше, чем карточек в кейсе")
	if int(B.shop.offer_count) != 6:
		err.append("offer_count != 6")
	return err
