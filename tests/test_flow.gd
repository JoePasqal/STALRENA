extends Node
## Полный цикл через реальные UI-обработчики: меню → Shop (покупки, вкладки, продажа, замок,
## обновление, уровень, мастерство) → WaveIntro → Combat → WaveComplete → Shop → пауза → меню → Continue.
## godot --headless --path . --quit-after 100000 res://tests/test_flow.tscn

var passed := 0
var failed := 0


func check(c: bool, name: String, extra: String = "") -> void:
	if c:
		passed += 1
	else:
		failed += 1
		print("  FAIL: ", name, " ", extra)


func _ready() -> void:
	SaveService.base_dir = "user://test_saves"
	DirAccess.make_dir_recursive_absolute("user://test_saves")
	SaveService.delete_run()
	Settings.data.autoaim = true
	Session.new_run(77)
	var run: RunState = Session.run
	run.coins = 900
	run.waves_completed = 5
	run.weapons["carbine"] = {"rank": 5, "mastery": 0}
	run.armors["field"] = {"rank": 5, "mastery": 0}
	run.equipped_armor = "field"
	var game: Node = load("res://scenes/game.tscn").instantiate()
	add_child(game)                      # обычный путь _ready → _enter_shop
	await get_tree().process_frame
	check(game.state == game.St.SHOP and game.shop_ui.visible, "Shop открыт при входе в игру")
	var shop: ShopScreen = game.shop_ui
	# вкладки правой панели без ошибок
	for t in 3:
		shop._tab = t
		shop.refresh()
	# покупки по карточкам
	run.coins = 900
	for o in run.offers.duplicate():
		if not o.bought and ShopService.offer_status(run, o).ok and run.coins >= int(o.price):
			shop._buy(int(o.uid))
	check(run.stats.purchases > 0, "UI-покупки проходят", str(run.stats.purchases))
	# вкладки после покупок (модули/части/продажа)
	for t in 3:
		shop._tab = t
		shop.refresh()
	if not run.modules.is_empty():
		var mid: String = run.modules.keys()[0]
		var coins_before := run.coins
		shop._sell_module(mid)
		check(run.coins > coins_before and not run.modules.has(mid), "UI: продажа модуля")
	# мастерство, экипировка, уровень магазина, обновление, замок
	run.coins = 900
	shop._equip_weapon("carbine")
	shop._mastery("weapon")
	check(run.weapons.carbine.mastery == 1 and run.mastery_bought_this_shop, "UI: мастерство оружия куплено один раз")
	shop._mastery("armor")
	check(run.armors.field.mastery == 0, "UI: второе мастерство в этом магазине отклонено")
	shop._equip_armor("field")
	shop._refresh_pressed()
	check(run.coins <= 900 - 80 - 10 + 1, "UI: обновление списало 10")
	ShopService.set_lock(run, true)
	shop.refresh()
	run.waves_completed = 8
	run.coins = 500
	var lvl_before := run.shop_level
	var up := ShopService.upgrade_shop(run)
	check(up.ok and run.shop_level == lvl_before + 1, "уровень магазина повышен")
	shop.refresh()
	# сохранение и перезагрузка из магазина
	check(SaveService.save_run(run), "сохранение из магазина")
	var offers_json := JSON.stringify(run.offers)
	var loaded := SaveService.load_run()
	check(loaded.status == "ok" and JSON.stringify(loaded.run.offers) == offers_json and loaded.run.pity == run.pity, "26: Shop восстановлен точно")
	# старт волны через сигнал UI
	shop.start_requested.emit()
	check(game.state == game.St.WAVE_INTRO and run.phase == "combat", "старт волны: интро и фаза combat")
	check(is_equal_approx(game.player.hp, game.player.max_hp) and game.player.medkit.stock == 1, "перед волной полное ХП и одна аптечка")
	game.state = game.St.COMBAT
	game.bot = BotInput.new()
	var steps := 0
	while game.state == game.St.COMBAT and steps < 60 * 300:
		game.sim_step(1.0 / 60.0)
		game.player.hp = game.player.max_hp
		steps += 1
	check(game.state == game.St.WAVE_COMPLETE, "победа в волне автопилотом", str(game.state))
	check(run.waves_completed == 9 and run.phase == "shop", "после победы: волна засчитана ровно один раз")
	# пауза не ломается, выход в меню сохраняет забег
	game.state = game.St.COMBAT
	game.open_pause()
	check(game.pause_ui.visible and get_tree().paused, "пауза открывается")
	game.close_pause()
	check(not get_tree().paused, "пауза закрывается")
	game.state = game.St.WAVE_COMPLETE
	game.complete_t = 0.0
	game._physics_process(0.1)
	await get_tree().process_frame
	check(game.state == game.St.SHOP and game.shop_ui.visible, "после награды снова открыт Shop")
	Session.save()
	var cont := Session.continue_run()
	check(cont.run != null and cont.run.waves_completed == 9, "Continue загружает забег")
	print("ИТОГО (поток): passed=%d failed=%d" % [passed, failed])
	SaveService.delete_run()
	get_tree().quit(1 if failed > 0 else 0)
