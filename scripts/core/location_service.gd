class_name LocationService
extends RefCounted
## Сектор → локация, раскладка, модификатор, освещение. Детерминированно от seed забега.

const MODIFIERS := ["steam", "electric", "toxic"]
const NATIVE_HAZARD := {"sawmill": "", "pumping": "steam", "flooded": ""}
const TINTS := [Color(1, 1, 1), Color(0.88, 0.95, 1.0), Color(1.0, 0.93, 0.82)]


static func sector_info(run_seed: int, sector: int) -> Dictionary:
	var order: Array = GameData.location_order
	var loc: String = order[(sector - 1) % order.size()]
	var visit := int((sector - 1) / order.size())
	var variants: Array = GameData.layouts_by_location[loc]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, loc, "layout"])
	var offset := rng.randi() % variants.size()
	var layout_id: String = variants[(offset + visit) % variants.size()]
	var mrng := RandomNumberGenerator.new()
	mrng.seed = hash([run_seed, sector, "modifier"])
	var modifier := ""
	if visit >= 1:                       # первый визит локации — без модификаторов
		var pool: Array = []
		for m in MODIFIERS:
			if m != NATIVE_HAZARD.get(loc, ""):
				pool.append(m)
		modifier = pool[mrng.randi() % pool.size()]
	return {
		"sector": sector,
		"location_id": loc,
		"layout_id": layout_id,
		"modifier": modifier,
		"native_hazard": NATIVE_HAZARD.get(loc, ""),
		"tint_index": mrng.randi() % TINTS.size() if visit >= 1 else 0,
		"visit": visit,
	}
