class_name Economy
extends RefCounted
## Выплаты, завершение волны, поражение. Идемпотентно: двойное событие смерти
## последнего моба не начисляет награду дважды.


static func reward_for(global_wave: int, coins_at_start: int, is_boss: bool, coin_bonus: float = 0.0) -> Dictionary:
	var e: Dictionary = GameData.B.economy
	var base := int(e.wave_base_reward)
	var growth := mini(int(e.reward_growth_per_wave_after_first) * (global_wave - 1), int(e.max_growth_reward))
	var interest := mini(int(floor(coins_at_start / float(e.interest_per_saved_coins))) * int(e.interest_per_step), int(e.interest_cap))
	var boss := int(e.boss_bonus) if is_boss else 0
	var subtotal := base + growth + interest + boss
	var extra := int(floor(subtotal * coin_bonus))             # бонус-кейс «Золотая жила»
	return {"base": base, "growth": growth, "interest": interest, "boss": boss, "bonus": extra, "total": subtotal + extra}


## Победа в волне: ровно одно начисление и один вход в магазин. Возвращает {} при повторе.
static func complete_wave(run: RunState) -> Dictionary:
	if run.phase != "combat" or run.over:
		return {}
	var gw := run.next_wave()
	var boss := run.is_boss_wave(gw)
	var rw := reward_for(gw, run.coins_at_wave_start, boss, BonusService.coin_bonus(run))
	run.coins += int(rw.total)
	run.waves_completed = gw
	run.phase = "shop"
	run.hp = StatCalc.max_hp(run)
	run.last_reward = rw.duplicate()
	run.last_reward["wave"] = gw
	BonusService.on_wave_completed(run, gw)
	run.hp = StatCalc.max_hp(run)          # после снятия бонуса максимум мог измениться
	ShopService.on_enter_shop(run)
	return {"wave": gw, "reward": rw, "boss": boss}


## Поражение: забег помечается завершённым до показа результатов, выплаты нет.
static func mark_defeat(run: RunState, source: String) -> void:
	if run.over:
		return
	run.over = true
	run.phase = "over"
	run.stats["deaths_by"] = source
