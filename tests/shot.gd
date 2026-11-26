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
	var steps := int(args.get("steps", 600))
	for i in steps:
		game.sim_step(1.0 / 60.0)
		if game.state != game.St.COMBAT:
			break
	if args.has("intro"):
		game.state = game.St.WAVE_INTRO
		game.intro_t = 5.0
		game.hud.show_wave_intro(run2, game.gw, game.plan)
	await _frames(3)
	_save(out)
	print("shot saved ", out, " state=", game.state, " enemies=", game.enemies.size())
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _save(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
