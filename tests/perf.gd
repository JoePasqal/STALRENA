extends Node
## Замер кадра при ~36 мобах и интенсивной стрельбе (с отрисовкой).
## xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/perf.tscn -- --loadout=119 --frames=900
## Результат зависит от машины: на ПК/программном GL это НЕ показатель телефона.

var args := {}
var game: Node
var frame_ms: Array = []
var alive_sum := 0
var proj_sum := 0
var n_frames := 0
var want_frames := 900
var _t_last := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	want_frames = int(args.get("frames", 900))
	if args.has("low"):
		Settings.data.quality = "low"
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Session.new_run(9)
	DebugTools.apply_loadout(Session.run, int(args.get("loadout", 119)))
	Session.run.equipped_weapon = str(args.get("weapon", "lmg"))
	game = load("res://scenes/game.tscn").instantiate()
	game.auto_open_ui = false
	add_child(game)
	await get_tree().process_frame
	ShopService.begin_wave(Session.run)
	game._launch_wave()
	game.bot = BotInput.new()
	game.state = game.St.COMBAT
	game.player.hp = 1e9
	game.player.max_hp = 1e9
	_t_last = Time.get_ticks_usec()


func _process(_d: float) -> void:
	if game == null or n_frames >= want_frames:
		return
	var now := Time.get_ticks_usec()
	if n_frames > 0 or true:
		frame_ms.append((now - _t_last) / 1000.0)
	_t_last = now
	game.player.hp = game.player.max_hp
	# держим плотный бой: если волна закончилась — запускаем следующую
	if game.queue.is_empty() and game.state == game.St.COMBAT:
		game.suppress_win = true
	if game.state == game.St.WAVE_COMPLETE or game.state == game.St.SHOP:
		Session.run.phase = "shop"
		ShopService.begin_wave(Session.run)
		game._launch_wave()
		game.bot = BotInput.new()
		game.state = game.St.COMBAT
	_top_up(36)
	alive_sum += game.enemies.size()
	proj_sum += game.projectiles.player_count + game.projectiles.enemy_count
	n_frames += 1
	if n_frames >= want_frames:
		_report()


func _report() -> void:
	frame_ms = frame_ms.slice(30)          # без прогрева
	var sorted := frame_ms.duplicate()
	sorted.sort()
	var avg := 0.0
	for v in frame_ms:
		avg += v
	avg /= maxf(frame_ms.size(), 1)
	var p95: float = sorted[int(sorted.size() * 0.95)]
	var p99: float = sorted[int(sorted.size() * 0.99)]
	print("PERF frames=%d avg=%.2fms (%.0f FPS) p95=%.2fms p99=%.2fms max=%.2fms avg_enemies=%.1f avg_projectiles=%.1f quality=%s renderer=%s" % [frame_ms.size(), avg, 1000.0 / avg, p95, p99, sorted[sorted.size() - 1], alive_sum / float(n_frames), proj_sum / float(n_frames), Settings.data.quality, RenderingServer.get_video_adapter_name()])
	get_tree().quit()


const MIX := ["drifter", "drifter", "runner", "runner", "charger", "spitter", "gunner", "brute", "flanker", "carrier"]


func _top_up(target: int) -> void:
	var cells: Array = game.arena.free_cells()
	var guard := 0
	while game.enemies.size() < target and guard < 40:
		guard += 1
		var c: Vector2 = game.arena.cell_center(cells[game.rng_combat.randi() % cells.size()])
		if c.distance_to(game.player.position) < 260.0:
			continue
		var id: String = MIX[game.rng_combat.randi() % MIX.size()]
		var e: Enemy = game._spawn_enemy(id, "", c, false)
		e.state = Enemy.S.MOVE
		e.sprite.visible = true
		game.queue.clear()
