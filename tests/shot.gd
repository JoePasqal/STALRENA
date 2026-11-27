extends Node
## Снимки реального проекта (не концепт): godot --path . res://tests/shot.tscn -- --shot=shop|combat|boss|menu --out=/path.png [--loadout=N] [--steps=N] [--seed=N]
## Нужен дисплей (xvfb-run -a ...) и renderer opengl3.

var args := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var shot := str(args.get("shot", "combat"))
	var out := str(args.get("out", "/tmp/shot.png"))
	get_window().size = Vector2i(int(args.get("w", 1280)), int(args.get("h", 720)))
	Settings.data.autoaim = true
	if args.has("touch"):
		Settings.data.touch_ui = "on"
	Settings.data.tutorial_done = true
	Settings.data.tutorial_shop_done = true
	Session.new_run(int(args.get("seed", 5)))
	if args.has("loadout"):
		DebugTools.apply_loadout(Session.run, int(args.loadout))
	if shot == "menu":
		var m: Node = load("res://scenes/main_menu.tscn").instantiate()
		add_child(m)
		await _frames(4)
		_save(out)
		get_tree().quit()
		return
	var game: Node = load("res://scenes/game.tscn").instantiate()
	game.auto_open_ui = false
	add_child(game)
	await _frames(2)
	if shot == "shop":
		var run: RunState = Session.run
		run.coins = int(args.get("coins", 250))
		run.waves_completed = int(args.get("done", 3))
		ShopService.generate_offers(run, false)
		game._enter_shop()
		await _frames(4)
		if args.has("tut"):
			game.tutorial.debug_show(str(args.tut))
			await _frames(8)
		_save(out)
		get_tree().quit()
		return
	var run2: RunState = Session.run
	ShopService.begin_wave(run2)
	game.state = game.St.SHOP
	game._launch_wave()
	game.bot = BotInput.new()
	game.state = game.St.COMBAT
	game.intro_t = 0.0
	if shot == "case":
		var rn: RunState = Session.run
		rn.waves_completed = 11 if str(args.get("kind", "buff")) == "debuff" else 9
		rn.phase = "combat"
		rn.coins_at_wave_start = rn.coins
		Economy.complete_wave(rn)
		game._enter_shop()
		await _frames(4)
		var ui: BonusCaseScreen = game.bonus_ui
		var stage := str(args.get("stage", "closed"))
		if stage != "closed":
			ui._anim_speed = 1.0
			ui._on_btn()
			await get_tree().create_timer(1.6).timeout
		if stage in ["mid", "done"]:
			ui._on_card(ui.cards[1])
			await get_tree().create_timer(1.55 if stage == "mid" else 6.0).timeout
		await _frames(3)
		_save(out)
		get_tree().quit()
		return
	if shot == "pause" or shot == "results" or shot == "settings":
		game.state = game.St.COMBAT
		for i in 120:
			game.sim_step(1.0 / 60.0)
		if shot == "results":
			game.player.take_damage(1e9, "drifter", false)
			game.sim_step(1.0 / 60.0)
		else:
			game.open_pause()
			if shot == "settings":
				game.pause_ui.settings_btn.pressed.emit()
		await _frames(4)
		get_tree().paused = false
		_save(out)
		get_tree().quit()
		return
	var steps := int(args.get("steps", 600))
	for i in steps:
		game.sim_step(1.0 / 60.0)
		if game.state != game.St.COMBAT:
			break
	if args.has("intro"):
		game.state = game.St.WAVE_INTRO
		game.intro_t = 5.0
		game.hud.show_wave_intro(run2, game.gw, game.plan)
	if args.has("tut"):
		game.tutorial.debug_show(str(args.tut))
		if str(args.tut) == "medkit":
			game.player.hp = game.player.max_hp * 0.5
	await _frames(8 if args.has("tut") else 3)
	_save(out)
	print("shot saved ", out, " state=", game.state, " enemies=", game.enemies.size())
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _save(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
