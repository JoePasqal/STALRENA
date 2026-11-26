class_name CombatCoordinator
extends RefCounted
## Токены на одновременную подготовку дальних атак + отдельный канал босса.
## Ожидающие не атакуют одновременно при освобождении: у каждого случайная задержка повтора.

var max_tokens := 2
var holders := {}                 # instance_id -> true
var boss_token_holder := 0
var boss_tokens_max := 1


func configure(global_wave: int) -> void:
	max_tokens = WaveMath.ranged_tokens(global_wave)
	boss_tokens_max = int(GameData.B.combat_coordinator.boss_pattern_tokens)
	reset()


func reset() -> void:
	holders.clear()
	boss_token_holder = 0


func request(enemy: Object) -> bool:
	var id := enemy.get_instance_id()
	if holders.has(id):
		return true
	if holders.size() >= max_tokens:
		return false
	holders[id] = true
	return true


func release(enemy: Object) -> void:
	holders.erase(enemy.get_instance_id())


func holds(enemy: Object) -> bool:
	return holders.has(enemy.get_instance_id())


func active_count() -> int:
	return holders.size()


func request_boss(boss: Object) -> bool:
	if boss_token_holder == 0 or boss_token_holder == boss.get_instance_id():
		boss_token_holder = boss.get_instance_id()
		return true
	return false


func release_boss(boss: Object) -> void:
	if boss_token_holder == boss.get_instance_id():
		boss_token_holder = 0


static func retry_delay(rng: RandomNumberGenerator) -> float:
	var c: Dictionary = GameData.B.combat_coordinator
	return rng.randf_range(float(c.waiting_attack_jitter_seconds_min), float(c.waiting_attack_jitter_seconds_max))
