class_name DebugTools
extends RefCounted
## Ускоренный переход на тестовые волны с подходящей экипировкой (24, 60, 120).
## В release-сборке скрыто (Session.debug_enabled). Нужен для проверки баланса и ограничений.

static func apply_loadout(run: RunState, wave: int) -> void:
	GameData.ensure()
	run.waves_completed = wave - 1
	run.phase = "shop"
	run.over = false
	var rank := 3 if wave < 40 else 5
	var mastery := 0 if wave < 40 else (3 if wave < 100 else 12)
	run.shop_level = 3 if wave < 40 else 5
	run.coins = 400
	for id in GameData.weapon_ids:
		run.weapons[id] = {"rank": rank, "mastery": mastery if rank == 5 else 0}
	for id in GameData.armor_ids:
		run.armors[id] = {"rank": rank, "mastery": mastery if rank == 5 else 0}
	run.equipped_weapon = "carbine"
	run.equipped_armor = "field"
	run.modules.clear()
	var ids: Array = ["amplifier", "feeder", "bolt_drive", "reserve_cells", "shock_lining", "cell_matrix"] if run.shop_level < 5 else GameData.module_ids.slice(0, 6)
	for mid in ids:
		run.modules[mid] = {"level": 2 if wave < 100 else 3, "paid": 36}
	run.parts.clear()
	run.hp = StatCalc.max_hp(run)
	ShopService.generate_offers(run, false)
