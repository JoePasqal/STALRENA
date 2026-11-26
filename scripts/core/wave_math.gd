class_name WaveMath
extends RefCounted
## Масштабирование по глобальной волне — линейное, без накопления множителей.

static func hp_mult(gw: int) -> float:
	return 1.0 + float(GameData.B.scaling.enemy_hp_linear_per_wave) * (gw - 1)


static func damage_mult(gw: int) -> float:
	return 1.0 + float(GameData.B.scaling.enemy_damage_linear_per_wave) * (gw - 1)


static func speed_mult(gw: int) -> float:
	var s: Dictionary = GameData.B.scaling
	return minf(float(s.enemy_speed_multiplier_cap), 1.0 + float(s.enemy_speed_linear_per_wave) * (gw - 1))


static func projectile_speed_mult(gw: int) -> float:
	var s: Dictionary = GameData.B.scaling
	return minf(float(s.projectile_speed_multiplier_cap), 1.0 + float(s.projectile_speed_linear_per_wave) * (gw - 1))


static func threat_budget(gw: int) -> int:
	var w: Dictionary = GameData.B.waves
	return mini(int(w.threat_cap), int(w.threat_start) + int(w.threat_growth_per_wave) * (gw - 1))


static func elite_probability(gw: int) -> float:
	var e: Dictionary = GameData.B.elites
	if gw < int(e.first_wave):
		return 0.0
	return minf(float(e.probability_cap), float(e.initial_probability) + float(e.probability_growth_per_wave) * (gw - int(e.first_wave)))


static func ranged_tokens(gw: int) -> int:
	var c: Dictionary = GameData.B.combat_coordinator
	return int(c.late_ranged_attack_tokens) if gw >= int(c.late_tokens_first_wave) else int(c.early_ranged_attack_tokens)


## Боевой скорость тарана ограничена отдельным капом.
static func charge_speed(def: Dictionary, gw: int) -> float:
	return minf(float(def.charge_speed) * speed_mult(gw), float(def.charge_speed_cap))
