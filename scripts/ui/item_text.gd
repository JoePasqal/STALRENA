class_name ItemText
extends RefCounted
## Тексты характеристик предметов из данных (живой текст, не запекается в картинки).

static func stat_text(stat: String, value: float) -> String:
	match stat:
		"damage_percent": return "+%d%% урона" % int(round(value * 100.0))
		"fire_rate_percent": return "+%d%% темпа стрельбы" % int(round(value * 100.0))
		"reload_speed_percent": return "+%d%% скорости перезарядки" % int(round(value * 100.0))
		"crit_chance_add": return "+%d%% шанса крита" % int(round(value * 100.0))
		"crit_multiplier_add": return "+%.2f к множителю крита" % value
		"projectile_speed_percent": return "+%d%% скорости пуль" % int(round(value * 100.0))
		"max_hp_percent": return "+%d%% максимума ХП" % int(round(value * 100.0))
		"contact_invulnerability_seconds_add": return "+%.2f с защиты от контакта" % value
		"out_of_damage_regen_max_hp_fraction_per_second": return "регенерация +%.2f%% ХП/с (после 8 с без урона)" % (value * 100.0)
		"move_speed_percent": return "+%d%% скорости" % int(round(value * 100.0))
		"range_percent": return "+%d%% дальности" % int(round(value * 100.0))
		"magazine_percent": return "+%d%% ёмкости магазина" % int(round(value * 100.0))
	return stat


static func module_effect(id: String, level: int) -> String:
	var m: Dictionary = GameData.modules[id]
	return stat_text(str(m.stat), float(m.per_level) * level)


static func module_line(run: RunState, id: String) -> String:
	var m: Dictionary = GameData.modules[id]
	var cur := int(run.modules[id].level) if run.modules.has(id) else 0
	var s := "%s за уровень" % stat_text(str(m.stat), float(m.per_level))
	if cur > 0:
		s += "\nСейчас ур.%d → станет ур.%d (%s)" % [cur, cur + 1, module_effect(id, cur + 1)]
	else:
		s += "\nНовый модуль: займёт ячейку"
	return s


static func set_bonus(s: Dictionary) -> String:
	var parts: Array = []
	for k in s.bonus:
		parts.append(stat_text(str(k), float(s.bonus[k])))
	return ", ".join(parts)


static func weapon_line(id: String, rank: int) -> String:
	var w: Dictionary = GameData.weapons[id]
	var dmg := float(w.base_damage) * GameData.rank_mult(rank)
	var pel := " ×%d" % int(w.projectiles_per_shot) if int(w.projectiles_per_shot) > 1 else ""
	var extra := ""
	if str(w.fire_mode) == "cone_ticks":
		extra = "\nКонус пламени, горение 2 с"
	elif int(w.additional_pierce_targets) > 0:
		extra = "\nПробивает +%d цель" % int(w.additional_pierce_targets)
	return "Урон %.0f%s · %.1f выстр/с\nМагазин %d · дальность %d%s" % [dmg, pel, float(w.shots_per_second), int(w.magazine), int(w.range_units), extra]


static func armor_line(id: String, rank: int) -> String:
	var a: Dictionary = GameData.armors[id]
	var sp := int(round(float(a.move_speed_bonus) * 100.0))
	var s := "+%d максимума ХП" % int(a.hp_by_rank[rank - 1])
	if sp != 0:
		s += "\nСкорость %s%d%%" % ["+" if sp > 0 else "", sp]
	else:
		s += "\nСкорость без изменений"
	return s + "\nУрон не снижает"
