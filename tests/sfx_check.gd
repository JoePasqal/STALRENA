extends Node
## Проверка синтеза звуков и музыки: все звуки собираются, не пустые, время генерации.

func _ready() -> void:
	var s := Sfx
	var t0 := Time.get_ticks_msec()
	var ids := ["shot_pistol", "shot_smg", "shot_carbine", "shot_shotgun", "shot_lmg", "shot_marksman", "flame", "hit", "hit_crit", "hurt", "enemy_die", "tele", "boss_tele", "boss_roar", "explosion", "reload", "reload_done", "empty", "medkit", "buy", "deny", "refresh", "lock", "levelup", "wave", "win", "lose", "click", "tutorial", "step_ok", "flip", "reveal", "case_open", "pick_buff", "reveal_major", "buff_done", "pick_debuff", "reveal_minor", "curse_done", "curse_open"]
	var bad := 0
	for id in ids:
		var w: AudioStreamWAV = s._make(id)
		if w == null or w.data.size() < 100:
			bad += 1
			print("BAD ", id)
	var t1 := Time.get_ticks_msec()
	var m1: AudioStreamWAV = s._music("shop")
	var m2: AudioStreamWAV = s._music("combat")
	print("SFX sounds=%d bad=%d synth_ms=%d music_ms=%d music_bytes=%d/%d" % [ids.size(), bad, t1 - t0, Time.get_ticks_msec() - t1, m1.data.size(), m2.data.size()])
	get_tree().quit(1 if bad > 0 else 0)
