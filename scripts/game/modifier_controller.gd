class_name ModifierController
extends RefCounted
## Периодические опасности арены (пар, электрические зоны, заражённые лужи) из слотов раскладки.
## Каждой зоне предшествует предупреждение; зоны не накрывают героя в момент создания,
## число одновременных зон ограничено, слоты проверены на сохранение безопасного маршрута.

var game
var kinds: Array = []             # напр. ["steam"] / ["electric"]
var timers := {}


func setup(g, p_kinds: Array) -> void:
	game = g
	kinds = p_kinds
	timers.clear()
	for k in kinds:
		timers[k] = float(GameData.modifiers[k].interval) * 0.6        # первое срабатывание не сразу


func tick(dt: float) -> void:
	for k in kinds:
		timers[k] -= dt
		if timers[k] <= 0.0:
			timers[k] = float(GameData.modifiers[k].interval)
			_activate(k)


func _activate(kind: String) -> void:
	var cfg: Dictionary = GameData.modifiers[kind]
	var slots: Array = game.arena.hazard_slots
	if slots.is_empty() or game.hazards.count_tag("mod_" + kind) >= int(cfg.max_zones):
		return
	var cands: Array = []
	for s in slots:
		var c := Vector2(s.x, s.y)
		if game.player != null and c.distance_to(game.player.position) < float(cfg.radius) + 60.0:
			continue                              # не накрываем героя в момент появления
		cands.append(c)
	if cands.is_empty():
		return
	var pos: Vector2 = cands[game.rng_combat.randi() % cands.size()]
	var dm := WaveMath.damage_mult(game.gw)
	game.hazards.add({
		"shape": "circle", "pos": pos, "radius": float(cfg.radius), "delay": float(cfg.warning),
		"life": float(cfg.duration), "damage": float(cfg.player_damage) * dm, "tick": float(cfg.tick),
		"hits_player": true, "hits_enemies": float(cfg.enemy_damage) > 0.0,
		"enemy_damage": float(cfg.enemy_damage), "palette": str(cfg.palette), "source": "mod_" + kind, "tag": "mod_" + kind,
	})
