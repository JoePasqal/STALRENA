extends Node
## Раунд 2 минуты (босс — 2 минуты или смерть босса), растянутый спавн, аптечки: покупка, накопление, перенос.
## godot --headless --path . --quit-after 400000 res://tests/test_round.tscn

var passed := 0
var failed := 0
var game: Node


func check(c: bool, name: String, extra: String = "") -> void:
	if c:
		passed += 1
	else:
		failed += 1
		print("  FAIL: ", name, " ", extra)


func new_game(wave_done: int = 0, loadout: int = 0) -> void:
	if game != null:
		game.queue_free()
		await get_tree().process_frame
	Session.new_run(21)
	if loadout > 0:
		DebugTools.apply_loadout(Session.run, loadout)
	else:
		Session.run.waves_completed = wave_done
	game = load("res://scenes/game.tscn").instantiate()
	game.auto_open_ui = false
	add_child(game)
	await get_tree().process_frame
	ShopService.begin_wave(Session.run)
	game._launch_wave()
	game.state = game.St.COMBAT


func _ready() -> void:
	Settings.data.tutorial_done = true
	Settings.data.tutorial_shop_done = true
	Settings.data.autoaim = true
	GameData.load_all()
	SaveService.base_dir = "user://test_saves"
	DirAccess.make_dir_recursive_absolute("user://test_saves")
	check(float(GameData.B.waves.round_seconds) == 120.0 and float(GameData.B.waves.boss_round_seconds) == 120.0, "данные: раунд 120 с")
	# обычный раунд: спавн растянут, раунд завершается по таймеру
	await new_game(4)
	check(game.round_limit == 120.0, "round_limit = 120")
	var total: int = game.queue.size()
	var pl: Player = game.player
	var spawned_10 := 0
	var t_end := -1.0
	var left_at_10 := -1
	var steps := 0
	while game.state == game.St.COMBAT and steps < 60 * 140:
		game.sim_step(1.0 / 60.0)
		pl.hp = pl.max_hp
		steps += 1
		if steps == 600:
			left_at_10 = game.queue.size()
	check(game.state == game.St.WAVE_COMPLETE, "раунд завершился победой", str(game.state))
	check(game.wave_time <= 120.05, "раунд не длиннее 120 с", str(game.wave_time))
	check(left_at_10 >= int(total * 0.6), "спавн растянут: к 10-й секунде осталось в очереди ≥60%%", "%d из %d" % [left_at_10, total])
	check(game.wave_time >= 60.0, "раунд длится заметно дольше старой «зачистки за 15–40 с»", str(game.wave_time))
	# таймер, даже если враги живы: принудительно держим живого врага
	await new_game(4)
	game.queue.clear()
	var e: Enemy = game._spawn_enemy("brute", "", game.arena.start + Vector2(900, 0), false)
	e.hp = 1e9
	e.max_hp = 1e9
	e.state = Enemy.S.MOVE
	e.speed = 0.0
	game.player.hp = 1e9
	game.player.max_hp = 1e9
	var coins0: int = Session.run.coins
	steps = 0
	while game.state == game.St.COMBAT and steps < 60 * 130:
		game.sim_step(1.0 / 60.0)
		steps += 1
	check(game.state == game.St.WAVE_COMPLETE and absf(game.wave_time - 120.0) < 0.1, "живой враг: раунд всё равно закончился ровно на 120 с", str(game.wave_time))
	check(game.enemies.is_empty() and game.hazards.count() == 0, "по таймеру убраны враги и поля")
	check(Session.run.waves_completed == 5, "волна засчитана по таймеру")
	check(bool(game.wave_result.get("timeout", false)), "результат помечен как «время вышло»")
	# босс: смерть раньше таймера → бонус 30; таймер при живом боссе → без бонуса
	await new_game(0, 12)
	var run: RunState = Session.run
	game.player.hp = 1e9
	game.player.max_hp = 1e9
	var c1: int = run.coins
	var snap: int = run.coins_at_wave_start
	for i in 60 * 20:
		game.sim_step(1.0 / 60.0)
	game.boss.take_damage(1e9, false, "player")
	await get_tree().process_frame
	await get_tree().process_frame
	check(game.state == game.St.WAVE_COMPLETE and game.wave_time < 60.0, "босс убит раньше таймера — раунд закончился сразу", str(game.wave_time))
	check(run.coins - c1 == Economy.reward_for(12, snap, true).total, "босс убит: бонус +30 выдан")
	await new_game(0, 12)
	run = Session.run
	game.player.hp = 1e9
	game.player.max_hp = 1e9
	game.boss.hp = 1e9
	game.boss.max_hp = 1e9
	c1 = run.coins
	snap = run.coins_at_wave_start
	steps = 0
	while game.state == game.St.COMBAT and steps < 60 * 130:
		game.sim_step(1.0 / 60.0)
		game.player.hp = game.player.max_hp
		steps += 1
	check(game.state == game.St.WAVE_COMPLETE and absf(game.wave_time - 120.0) < 0.1, "босс жив: раунд закончился на 120 с", str(game.wave_time))
	check(run.coins - c1 == Economy.reward_for(12, snap, false).total and not bool(game.wave_result.boss_killed), "босс жив: награда без бонуса +30")
	# аптечки: покупка, накопление, перенос
	var r := RunState.new_run(3)
	check(r.medkits == 1, "старт: 1 аптечка")
	r.coins = 100
	check(ShopService.buy_medkit(r).ok and r.medkits == 2 and r.coins == 82, "покупка аптечки: цена 18, запас 2")
	check(ShopService.buy_medkit(r).ok and ShopService.buy_medkit(r).ok and r.medkits == 4 and r.coins == 46, "можно покупать подряд (неограниченно, до лимита)")
	r.coins = 5
	check(not ShopService.buy_medkit(r).ok and r.medkits == 4 and r.coins == 5, "не хватает монет — отказ без списания")
	r.coins = 100000
	r.medkits = int(GameData.B.medkit.max_stock)
	check(not ShopService.buy_medkit(r).ok, "лимит запаса аптечек")
	r.medkits = 4
	r.phase = "combat"
	check(not ShopService.buy_medkit(r).ok, "покупка вне магазина невозможна")
	var m := Medkit.new()
	m.reset_for_wave(4)
	check(m.stock == 4, "раунд стартует с накопленным запасом")
	m.reset_for_wave(0)
	check(m.stock == 1, "минимум одна аптечка в начале раунда при пустом запасе")
	# перенос через раунд в игре
	await new_game(2)
	run = Session.run
	run.medkits = 3
	game.player.setup(game, run)
	check(game.player.medkit.stock == 3, "в бою: в запасе 3")
	game.player.hp = 10.0
	game.player.use_medkit()
	check(game.player.medkit.stock == 2, "использована одна")
	for i in 60 * 5:
		game.player.tick(1.0 / 60.0)
	game.player.hp = 20.0
	game.player.use_medkit()
	check(game.player.medkit.stock == 1, "после окончания эффекта можно использовать следующую")
	game.suppress_win = false
	game._on_wave_won()
	check(run.medkits == 1, "после победы неиспользованные сохранены (осталась 1)")
	var back := RunState.from_dict(JSON.parse_string(JSON.stringify(run.to_dict())))
	check(back.medkits == 1, "запас аптечек сохраняется в сохранении")
	# баланс эффекта аптечки не изменился
	var mk := Medkit.new()
	mk.reset_for_wave(5)
	mk.try_use(10.0, 200.0)
	check(absf(mk.total - 40.0) < 0.001 and mk.duration == 4.0, "эффект аптечки прежний: 20% за 4 с")
	print("ИТОГО (раунд/аптечки): passed=%d failed=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
