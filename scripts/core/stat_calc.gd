class_name StatCalc
extends RefCounted
## Чистые функции расчёта характеристик из исходных данных и текущих источников
## (не накопительное умножение). Все лимиты — из balance_v1.json:stat_caps.


static func active_set_ids(run: RunState) -> Array:
	var out: Array = []
	for sid in GameData.sets:
		var ok := true
		for req in GameData.sets[sid].requires:
			if not run.modules.has(req) or int(run.modules[req].level) < 1:
				ok = false
				break
		if ok:
			out.append(sid)
	return out


## stat -> суммарный бонус модулей и активных наборов.
static func module_bonuses(run: RunState) -> Dictionary:
	var out := {}
	for id in run.modules:
		var m: Dictionary = GameData.modules[id]
		var lvl := clampi(int(run.modules[id].level), 0, int(m.max_level))
		out[m.stat] = float(out.get(m.stat, 0.0)) + float(m.per_level) * lvl
	for sid in active_set_ids(run):
		var b: Dictionary = GameData.sets[sid].bonus
		for k in b:
			out[k] = float(out.get(k, 0.0)) + float(b[k])   # не зависит от уровня модулей
	return out


static func armor_base_hp(run: RunState) -> float:
	if run.equipped_armor == "" or not run.armors.has(run.equipped_armor):
		return 0.0
	var a: Dictionary = GameData.armors[run.equipped_armor]
	return float(a.hp_by_rank[int(run.armors[run.equipped_armor].rank) - 1])


static func armor_mastery_hp(run: RunState) -> float:
	if run.equipped_armor == "" or not run.armors.has(run.equipped_armor):
		return 0.0
	var e: Dictionary = run.armors[run.equipped_armor]
	if int(e.rank) < 5:
		return 0.0
	var a: Dictionary = GameData.armors[run.equipped_armor]
	var inc: float = float(GameData.B.shop.mastery.increment_fraction_of_rank_v_base)
	return float(a.hp_by_rank[4]) * inc * int(e.mastery)


static func max_hp(run: RunState) -> float:
	var bonus: Dictionary = module_bonuses(run)
	var raw: float = float(GameData.B.player.base_hp) + armor_base_hp(run) + armor_mastery_hp(run)
	return raw * (1.0 + float(bonus.get("max_hp_percent", 0.0)))


static func move_speed_multiplier(run: RunState) -> float:
	var caps: Dictionary = GameData.B.stat_caps
	var armor_bonus := 0.0
	if run.equipped_armor != "":
		armor_bonus = float(GameData.armors[run.equipped_armor].move_speed_bonus)
	var bonus: Dictionary = module_bonuses(run)
	var m: float = 1.0 + armor_bonus + float(bonus.get("move_speed_percent", 0.0))
	return clampf(m, float(caps.move_speed_multiplier_min), float(caps.move_speed_multiplier_max))


static func player_stats(run: RunState) -> Dictionary:
	var p: Dictionary = GameData.B.player
	var caps: Dictionary = GameData.B.stat_caps
	var bonus: Dictionary = module_bonuses(run)
	return {
		"max_hp": max_hp(run),
		"move_speed": float(p.base_move_speed) * move_speed_multiplier(run),
		"hit_radius": float(p.hit_radius),
		"contact_guard": minf(float(p.contact_invulnerability_seconds) + float(bonus.get("contact_invulnerability_seconds_add", 0.0)), float(caps.contact_invulnerability_seconds_max)),
		"regen_fraction": float(bonus.get("out_of_damage_regen_max_hp_fraction_per_second", 0.0)),
		"regen_delay": float(p.regen_delay_after_damage_seconds),
	}


static func weapon_damage(run: RunState, weapon_id: String) -> float:
	var w: Dictionary = GameData.weapons[weapon_id]
	var e: Dictionary = run.weapons[weapon_id]
	var bonus: Dictionary = module_bonuses(run)
	var inc: float = float(GameData.B.shop.mastery.increment_fraction_of_rank_v_base)
	var mastery_k: float = 1.0 + inc * int(e.mastery)
	return float(w.base_damage) * GameData.rank_mult(int(e.rank)) * mastery_k * (1.0 + float(bonus.get("damage_percent", 0.0)))


static func weapon_stats(run: RunState, weapon_id: String) -> Dictionary:
	var w: Dictionary = GameData.weapons[weapon_id]
	var e: Dictionary = run.weapons[weapon_id]
	var caps: Dictionary = GameData.B.stat_caps
	var bonus: Dictionary = module_bonuses(run)
	var dmg := weapon_damage(run, weapon_id)
	var fr_bonus := minf(float(bonus.get("fire_rate_percent", 0.0)), float(caps.fire_rate_bonus_max))
	var rl_bonus: float = float(bonus.get("reload_speed_percent", 0.0))
	var range_bonus := minf(float(bonus.get("range_percent", 0.0)), float(caps.range_bonus_max))
	var ps_bonus := minf(float(bonus.get("projectile_speed_percent", 0.0)), float(caps.projectile_speed_bonus_max))
	var mag_bonus := minf(float(bonus.get("magazine_percent", 0.0)), float(caps.magazine_bonus_max))
	var crit := minf(float(GameData.B.player.base_crit_chance) + float(bonus.get("crit_chance_add", 0.0)), float(caps.crit_chance_max))
	var cmult := minf(float(GameData.B.player.base_crit_multiplier) + float(bonus.get("crit_multiplier_add", 0.0)), float(caps.crit_multiplier_max))
	var s := {
		"id": weapon_id,
		"rank": int(e.rank),
		"mastery": int(e.mastery),
		"damage": dmg,
		"fire_rate": float(w.shots_per_second) * (1.0 + fr_bonus),
		"magazine": maxi(1, int(round(float(w.magazine) * (1.0 + mag_bonus)))),
		"reload_time": float(w.reload_seconds) / (1.0 + rl_bonus),
		"range": float(w.range_units) * (1.0 + range_bonus),
		"projectile_speed": float(w.projectile_speed) * (1.0 + ps_bonus),
		"spread": float(w.spread_degrees),
		"spread_semantics": str(w.spread_semantics),
		"pellets": int(w.projectiles_per_shot),
		"pierce": int(w.additional_pierce_targets),
		"fire_mode": str(w.fire_mode),
		"ammo_per_shot": int(w.ammo_per_shot),
		"crit_chance": crit,
		"crit_multiplier": cmult,
	}
	if str(w.fire_mode) == "cone_ticks":
		s["tick_seconds"] = float(w.tick_seconds) / (1.0 + fr_bonus)
		s["fuel_per_second"] = float(w.fuel_per_second)
		s["burn_dps"] = float(w.burn_base_damage_per_second) * GameData.rank_mult(int(e.rank)) * (1.0 + float(GameData.B.shop.mastery.increment_fraction_of_rank_v_base) * int(e.mastery)) * (1.0 + float(bonus.get("damage_percent", 0.0)))
		s["burn_duration"] = float(w.burn_duration_seconds)
	return s


## Средний урон в секунду (без попаданий мимо), для отладки/тюнинга баланса.
static func weapon_dps(stats: Dictionary) -> float:
	var per_shot: float = float(stats.damage) * int(stats.pellets)
	var crit_avg: float = 1.0 + float(stats.crit_chance) * (float(stats.crit_multiplier) - 1.0)
	var mag: int = int(stats.magazine)
	var shots_per_sec: float = float(stats.fire_rate)
	var cycle: float = float(mag) / shots_per_sec + float(stats.reload_time)
	return per_shot * crit_avg * float(mag) / cycle
