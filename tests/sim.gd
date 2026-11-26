extends Node
## Автоматический прогон боя автопилотом (НЕ человек) без отрисовки.
## godot --headless --path . res://tests/sim.tscn -- --waves=12 --seed=7 [--loadout=24] [--god]
## Печатает результат каждой волны. Используется для проверки волн, боссов, лимитов и замеров.

var args := {}
var game: Node
var log_lines: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var waves := int(args.get("waves", 3))
	var seed_v := int(args.get("seed", 7))
	Settings.data.autoaim = true
	Session.new_run(seed_v)
	if args.has("loadout"):
		DebugTools.apply_loadout(Session.run, int(args.loadout))
	game = load("res://scenes/game.tscn").instantiate()
	game.auto_open_ui = false
	add_child(game)
	await get_tree().process_frame
	var start_wave: int = Session.run.next_wave()
	var ok := true
	for i in waves:
		shop_phase()
		var r := run_wave()
		print(r)
		if not r.begins_with("WIN"):
			ok = false
			break
	print("SIM DONE ok=%s waves_completed=%d coins=%d" % [ok, Session.run.waves_completed, Session.run.coins])
	get_tree().quit(0 if ok else 2)


func shop_phase() -> void:
	var run: RunState = Session.run
	run.hp = StatCalc.max_hp(run)
	# жадная закупка: части активного оружия/брони, затем модули, затем база
	for _round in 3:
		for kind in ["part", "module", "base"]:
			for o in run.offers.duplicate():
				if o.bought or o.kind != kind:
					continue
				if kind == "part" and not (o.fam == "weapon:" + run.equipped_weapon or o.fam == "armor:" + run.equipped_armor):
					continue
				if kind == "base" and o.type == "weapon" and run.weapons.size() > 2:
					continue
				var st := ShopService.offer_status(run, o)
				if st.ok and run.coins >= int(o.price):
					ShopService.buy(run, int(o.uid))
	# переключиться на лучшее по DPS оружие
	var best := run.equipped_weapon
	var best_dps := 0.0
	for id in run.weapons:
		var d := StatCalc.weapon_dps(StatCalc.weapon_stats(run, id))
		if d > best_dps:
			best_dps = d
			best = id
	Inventory.equip_weapon(run, best)
	var up := ShopService.upgrade_status(run)
	if up.ok and run.coins >= int(up.cost) + 20:
		ShopService.upgrade_shop(run)
	game.run = run
	game.shop_ui.close()


func run_wave() -> String:
	var run: RunState = Session.run
	var res := ShopService.begin_wave(run)
	if not res.ok:
		return "FAIL begin_wave " + str(res)
	game.state = game.St.SHOP
	game._launch_wave()
	game.bot = BotInput.new()
	game.state = game.St.COMBAT
	var steps := 0
	var max_steps := int(float(args.get("fps", 60)) * 400)
	var t0 := Time.get_ticks_usec()
	var peak_alive := 0
	var peak_proj := 0
	var god := args.has("god")
	var dt_step := 1.0 / float(args.get("fps", 60))
	while game.state == game.St.COMBAT and steps < max_steps:
		game.sim_step(dt_step)
		if god:
			game.player.hp = game.player.max_hp
		steps += 1
		peak_alive = maxi(peak_alive, game.enemies.size())
		peak_proj = maxi(peak_proj, game.projectiles.enemy_count)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var gw: int = game.gw
	var info := "w%d %s %s t=%.1fs hp=%d/%d alive_peak=%d eproj_peak=%d sim=%.2fms/step coins=%d" % [gw, game.plan.archetype, GameData.weapons[run.equipped_weapon].id + str(run.weapons[run.equipped_weapon].rank), steps * dt_step, int(game.player.hp), int(game.player.max_hp), peak_alive, peak_proj, ms / maxf(steps, 1), run.coins]
	if game.state == game.St.WAVE_COMPLETE:
		game.state = game.St.SHOP
		return "WIN  " + info
	if game.state == game.St.GAMEOVER:
		return "LOSE " + info + " by=" + str(run.stats.get("deaths_by", ""))
	return "TIMEOUT " + info + " enemies=" + str(game.enemies.size()) + " queue=" + str(game.queue.size())
