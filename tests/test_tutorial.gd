extends Node
## Обучение: магазин (4 шага) → схема управления (модальная, интро ждёт) → живые подсказки по действиям → завершение/пропуск.
## godot --headless --path . --quit-after 100000 res://tests/test_tutorial.tscn

var passed := 0
var failed := 0


func check(c: bool, name: String, extra: String = "") -> void:
	if c:
		passed += 1
	else:
		failed += 1
		print("  FAIL: ", name, " ", extra)


func _ready() -> void:
	Tutorial.force_headless = true
	SaveService.base_dir = "user://test_saves"
	DirAccess.make_dir_recursive_absolute("user://test_saves")
	var backup := {"hints": Settings.data.hints, "a": Settings.data.tutorial_shop_done, "b": Settings.data.tutorial_done, "touch": Settings.data.touch_ui}
	Settings.data.hints = true
	Settings.data.tutorial_shop_done = false
	Settings.data.tutorial_done = false
	Settings.data.touch_ui = "on"
	Settings.data.autoaim = true
	Session.new_run(5)
	var game: Node = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var tut: Tutorial = game.tutorial
	check(tut.mode == "shop" and tut.blocking and tut.visible, "магазин: обучение открылось с первым шагом")
	check(tut.game.shop_ui.tutorial_rects().cards.size.x > 100, "подсветка: прямоугольники магазина измерены")
	for i in 4:
		check(tut.mode == "shop" and tut.step == i, "магазин: шаг %d" % i)
		tut._on_next()
		await get_tree().process_frame
	check(tut.mode == "" and not tut.blocking and Settings.data.tutorial_shop_done, "магазин: после 4 шагов обучение закрыто и запомнено")
	# старт волны → схема управления блокирует интро
	game.shop_ui.start_requested.emit()
	await get_tree().process_frame
	check(tut.mode == "controls" and tut.blocking and game.state == game.St.WAVE_INTRO, "бой: схема управления открыта поверх интро")
	var t0: float = game.intro_t
	for i in 10:
		game._physics_process(0.2)
	check(is_equal_approx(game.intro_t, t0) and game.state == game.St.WAVE_INTRO, "бой: пока схема открыта, интро и симуляция стоят")
	tut._on_next()
	check(tut.mode == "live" and not tut.blocking and tut._live_step == "move", "бой: «Понятно» → подсказка «Движение»")
	game.state = game.St.COMBAT
	game.intro_t = 0.0
	# движение
	var pl: Player = game.player
	for i in 40:
		pl.position += Vector2(6, 0)
		tut.combat_tick(1.0 / 60.0)
	check(tut._live_step == "shoot", "подсказка «Движение» засчитана после ~200 единиц пути", tut._live_step)
	# стрельба: два убийства
	game.run.stats["kills"] = int(game.run.stats.get("kills", 0)) + 2
	tut.combat_tick(0.1)
	check(tut._live_step == "medkit", "подсказка «Стрельба» засчитана по убийствам", tut._live_step)
	# аптечка
	pl.hp = pl.max_hp * 0.5
	tut.combat_tick(0.1)
	check(tut._medkit_asked and tut._tip_title == "Аптечка", "аптечка: подсказка при потере здоровья")
	pl.use_medkit()
	tut.combat_tick(0.1)
	check(tut._live_step == "" and tut._tip_title == "Аптечка применена", "аптечка: засчитана после нажатия")
	# красный телеграф как событие
	tut._tele_shown = false
	var e := Enemy.new()
	e.state = Enemy.S.TELEGRAPH
	game.enemies.append(e)
	tut.combat_tick(0.1)
	check(tut._tele_shown, "красный круг: подсказка показана при первом телеграфе")
	game.enemies.erase(e)
	e.free()
	# победа в волне завершает обучение
	game.state = game.St.COMBAT
	game._on_wave_won()
	check(Settings.data.tutorial_done and tut.mode == "", "обучение завершено после победы в первой волне")
	# повторно не появляется
	check(not (not Settings.data.tutorial_done), "флаг обучения сохранён")
	# пропуск
	Settings.data.tutorial_shop_done = false
	Settings.data.tutorial_done = false
	game.run.waves_completed = 0
	game.run.phase = "shop"
	tut.begin_shop()
	check(tut.mode == "shop", "пропуск: обучение магазина снова открыто")
	tut.skip_all()
	check(Settings.data.tutorial_shop_done and Settings.data.tutorial_done and tut.mode == "" and not tut.blocking, "«Пропустить обучение» закрывает всё и запоминает")
	# отключение подсказок
	Settings.data.tutorial_shop_done = false
	Settings.data.hints = false
	tut.begin_shop()
	check(tut.mode == "", "настройка «Подсказки» выкл. — обучения нет")
	# восстановление настроек пользователя
	Settings.data.hints = backup.hints
	Settings.data.tutorial_shop_done = backup.a
	Settings.data.tutorial_done = backup.b
	Settings.data.touch_ui = backup.touch
	Settings.save_settings()
	print("ИТОГО (обучение): passed=%d failed=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
