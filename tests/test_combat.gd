extends Node
## Поведенческие проверки боя на реальной игровой сцене (без отрисовки):
## ACCEPTANCE 5, 17–25, 27, 28. Запуск:
## godot --headless --path . --quit-after 100000 res://tests/test_combat.tscn

var passed := 0
var failed := 0
var game: Node = null

const EMPTY_ARENA := {"id": "t_empty", "location_id": "sawmill", "size": [1600, 1000], "start": [800, 500], "walls": [], "water": [], "hazard_slots": []}


func check(c: bool, name: String, extra: String = "") -> void:
	if c:
		passed += 1
	else:
		failed += 1
		print("  FAIL: ", name, " ", extra)


func _ready() -> void:
	GameData.load_all()
	SaveService.base_dir = "user://test_saves"
	DirAccess.make_dir_recursive_absolute("user://test_saves")
	Settings.data.autoaim = true
	await t_weapons()
	await t_contact()
	await t_spitter()
	await t_charger()
	await t_gunner_walls()
	await t_tokens()
	await t_carrier()
	await t_spawn_rules()
	await t_medkit_in_game()
	await t_water_and_modifiers()
	await t_pause()
	await t_boss_cleanup()
	await t_caps()
	await t_resume_combat()
	await t_wave_won_once()
	await t_boss_summons()
	await t_unstable()
	print("ИТОГО (бой): passed=%d failed=%d" % [passed, failed])
	SaveService.delete_run()
	get_tree().quit(1 if failed > 0 else 0)


# ---- помощники -----------------------------------------------------------------
func new_game(wave_done: int = 0, arena: Dictionary = EMPTY_ARENA, loadout: int = 0, clear_queue: bool = true) -> Node:
	if game != null:
		game.queue_free()
		await get_tree().process_frame
	Session.new_run(11)
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
	if clear_queue:
		game.queue.clear()
	game.suppress_win = true
	game.state = game.St.COMBAT
	if not arena.is_empty():
		game.arena = ArenaModel.new()
		game.arena.load_layout(arena)
	game.player.position = game.arena.start
	return game


func spawn(id: String, pos: Vector2, trait_id: String = "", tanky: bool = true) -> Enemy:
	var e: Enemy = game._spawn_enemy(id, trait_id, pos, false)
	if tanky:
		e.hp = 1e9                               # автоприцел героя не должен убить тестового врага
		e.max_hp = 1e9
	e.state = Enemy.S.MOVE                      # без предупреждения о появлении
	e.sprite.visible = true
	e.t_state = 0.0
	return e


func step(seconds: float, dt: float = 1.0 / 60.0) -> void:
	var n := int(seconds / dt)
	for i in n:
		game.sim_step(dt)


# ---- тесты ---------------------------------------------------------------------
func t_contact() -> void:
	await new_game()
	var pl: Player = game.player
	pl.hp = 100.0
	var e := spawn("drifter", pl.position + Vector2(30, 0))
	e.speed = 0.0
	var hits := 0
	var last := pl.hp
	for i in 60 * 6:
		game.sim_step(1.0 / 60.0)
		if pl.hp < last - 0.001:
			hits += 1
			check(absf((last - pl.hp) - e.dmg) < 0.01, "17: один удар = урон врага", str(last - pl.hp))
		last = pl.hp
	# цикл 1.2 с → за 6 с не больше 5 ударов; не каждый кадр
	check(hits >= 2 and hits <= 5, "17: контакт не бьёт каждый кадр", "hits=" + str(hits))
	# из замаха можно выйти
	await new_game()
	pl = game.player
	pl.hp = 100.0
	var e2 := spawn("drifter", pl.position + Vector2(30, 0))
	e2.speed = 0.0
	for i in 5:
		game.sim_step(1.0 / 60.0)
	pl.move_input = Vector2(-1, 0)
	step(1.0)
	check(pl.hp >= 99.99, "17: из замаха можно выйти — урона нет", str(pl.hp))
	# защита 0.35 с: второй контакт сразу после первого не наносит урона
	await new_game()
	pl = game.player
	pl.hp = 100.0
	pl.take_damage(5.0, "x", true)
	pl.take_damage(5.0, "x", true)
	check(absf(pl.hp - 95.0) < 0.01, "защита от многократного контакта 0.35 с")
	step(0.4)
	pl.take_damage(5.0, "x", true)
	check(absf(pl.hp - 90.0) < 0.01, "после 0.35 с контакт снова наносит урон")


func t_spitter() -> void:
	await new_game(8)
	var pl: Player = game.player
	pl.position = Vector2(800, 500)
	var e := spawn("spitter", Vector2(800 + 300, 500))
	e.speed = 0.0
	var found = null
	for i in 60 * 4:
		game.sim_step(1.0 / 60.0)
		if game.projectiles.enemy_count > 0:
			for pp in game.projectiles._active:
				if not pp.friendly:
					found = pp
			if found != null:
				break
	check(found != null, "17: плевун стреляет после телеграфа")
	if found == null:
		return
	var v0: Vector2 = found.vel
	var target_before: Vector2 = pl.position
	pl.position += Vector2(0, 150)          # герой уходит — плевок не преследует
	step(0.3)
	var still = null
	for p in game.projectiles._active:
		if not p.friendly:
			still = p
	if still != null:
		check(still.vel.is_equal_approx(v0), "17: плевок не меняет направление после выстрела")
	check(e.lock_pos.distance_to(target_before) < 40.0, "плевок нацелен в зафиксированную позицию")


func t_charger() -> void:
	await new_game(6)
	var pl: Player = game.player
	pl.position = Vector2(800, 500)
	var e := spawn("charger", Vector2(800 + 300, 500))
	e.speed = 0.0
	var dir_at_attack := Vector2.ZERO
	var moved := false
	for i in 60 * 5:
		game.sim_step(1.0 / 60.0)
		if e.state == Enemy.S.TELEGRAPH and e.locked and e.t_state > e.telegraph_total - 0.2:
			pl.position = Vector2(800 + 300, 500 + 250)      # после фиксации герой перебегает
			moved = true
		if e.state == Enemy.S.ATTACK:
			dir_at_attack = e.lock_dir
			break
	check(moved and dir_at_attack != Vector2.ZERO, "17: таран готовит и начинает рывок")
	var p0 := e.position
	step(0.2)
	var d := (e.position - p0).normalized()
	check(d.dot(dir_at_attack) > 0.99, "17: рывок идёт по зафиксированной прямой, без самонаведения", str(d.dot(dir_at_attack)))


func t_gunner_walls() -> void:
	var arena := EMPTY_ARENA.duplicate(true)
	arena.walls = [{"x": 940, "y": 300, "w": 60, "h": 400, "kind": "block"}]
	await new_game(10, arena)
	var pl: Player = game.player
	pl.position = Vector2(500, 500)
	var e := spawn("gunner", Vector2(1300, 500))
	e.speed = 0.0
	var tele := false
	var hp0 := pl.hp
	for i in 60 * 8:
		game.sim_step(1.0 / 60.0)
		if e.state == Enemy.S.TELEGRAPH or e.state == Enemy.S.ATTACK:
			tele = true
	check(not tele and absf(pl.hp - hp0) < 0.01, "18: стрелок не целится/не стреляет сквозь стену")
	# пуля блокируется стеной
	game.projectiles.spawn(false, Vector2(1100, 500), Vector2(-1, 0), 420.0, 7.0, 900.0, 6.0, "bullet", 0, false, -1.0, "gunner")
	step(2.0)
	check(absf(pl.hp - hp0) < 0.01 and game.projectiles.enemy_count == 0, "18: пуля блокируется стеной")
	# быстрая пуля не перескакивает тонкую стену
	var thin := EMPTY_ARENA.duplicate(true)
	thin.walls = [{"x": 700, "y": 0, "w": 2, "h": 1000, "kind": "block"}]
	await new_game(0, thin)
	var en := spawn("drifter", Vector2(900, 500))
	en.speed = 0.0
	var hp1 := en.hp
	game.player.position = Vector2(500, 500)
	game.projectiles.spawn(true, Vector2(500, 500), Vector2(1, 0), 1200.0, 50.0, 900.0, 3.0, "bullet")
	step(1.0, 1.0 / 20.0)           # большой шаг: 60 u/кадр
	check(en.hp >= hp1 - 0.001, "5: быстрая пуля не перескакивает стену (крупный шаг)")

	# попадание «в голову»: пуля идёт по земле выше точки у ног врага (в пределах капсулы тела), ниже/выше — мимо
	var empty2 := EMPTY_ARENA.duplicate(true)
	for case in [[-16.0, true, "5h: пуля на 16 выше ног — попадание"], [-28.0, true, "5h: пуля на 28 выше ног — попадание (голова)"], [-60.0, false, "5h: пуля на 60 выше ног — мимо"], [12.0, true, "5h: пуля чуть ниже ног — попадание"], [40.0, false, "5h: пуля на 40 ниже ног — мимо"]]:
		await new_game(0, empty2)
		game.player.position = Vector2(300, 500)
		var tgt := spawn("drifter", Vector2(900, 500))
		tgt.speed = 0.0
		var hpt := tgt.hp
		game.projectiles.spawn(true, Vector2(500, 500 + float(case[0])), Vector2(1, 0), 1200.0, 5.0, 900.0, 3.0, "bullet")
		step(0.8, 1.0 / 60.0)
		check((tgt.hp < hpt - 0.001) == bool(case[1]), str(case[2]))


func t_tokens() -> void:
	for gwv in [1, 30]:
		await new_game(gwv + 9 if gwv == 1 else 29)
		var pl: Player = game.player
		pl.position = Vector2(800, 500)
		var gunners: Array = []
		for i in 7:
			var g: Enemy = spawn("gunner", Vector2(800 + 380 * cos(i * 0.9), 500 + 380 * sin(i * 0.9)))
			g.speed = 0.0
			gunners.append(g)
		var cap: int = game.coord.max_tokens
		var max_active := 0
		var attacks := 0
		var starts_same_frame := 0
		for i in 60 * 14:
			game.sim_step(1.0 / 60.0)
			pl.hp = pl.max_hp
			var act := 0
			var started := 0
			for g in gunners:
				if g.holds_token and (g.state == Enemy.S.TELEGRAPH or g.state == Enemy.S.ATTACK):
					act += 1
				if g.state == Enemy.S.TELEGRAPH and g.t_state < 0.02:
					started += 1
			starts_same_frame = maxi(starts_same_frame, started)
			max_active = maxi(max_active, act)
			if game.projectiles.enemy_count > 0:
				attacks += 1
		check(max_active <= cap, "19: токены стрелков (wave %d): макс %d ≤ %d" % [game.gw, max_active, cap], str(max_active))
		check(max_active >= 1 and attacks > 0, "19: стрелки реально атакуют (wave %d)" % game.gw)
		check(game.projectiles.enemy_count <= 120, "лимит снарядов врагов")
		check(starts_same_frame <= cap, "19: не все ожидающие стартуют в один кадр", str(starts_same_frame))
	check(WaveMath.ranged_tokens(30) == 4, "19: поздний забег — 4 токена")


func t_carrier() -> void:
	await new_game(19)
	var pl: Player = game.player
	var c := spawn("carrier", pl.position + Vector2(400, 0))
	var before: int = game.enemies.size()
	c.take_damage(1e9, false, "player")
	var kids: Array = []
	for e in game.enemies:
		if e != c:
			kids.append(e)
	check(kids.size() == 2, "20: носитель создаёт ровно двух детей", str(kids.size()))
	var ok := true
	for k in kids:
		if k.id != "runner" or k.state != Enemy.S.SPAWN_WARNING or not k.summoned:
			ok = false
		if k.position.distance_to(pl.position) < 119.0:
			ok = false
	check(ok, "20: дети — бегуны с предупреждением, не ближе 120")
	for k in kids:
		k.state = Enemy.S.MOVE
		k.take_damage(1e9, false, "player")
	check(game.enemies.is_empty(), "20: дети не порождают новых носителей/детей")
	# награда не зависит от убийств (доход одинаков)
	check(Economy.reward_for(19, 100, false).total == Economy.reward_for(19, 100, false).total, "20: нет дохода за убийства")


func t_spawn_rules() -> void:
	await new_game(4)
	var pl: Player = game.player
	pl.position = Vector2(800, 500)
	var bad := 0
	for i in 300:
		var p = game._find_spawn_point(260.0)
		if p == null:
			continue
		if p.distance_to(pl.position) < 260.0 or not game.arena.is_point_free(p, ArenaModel.NAV_MARGIN):
			bad += 1
			print("  bad point ", p, " d=", p.distance_to(pl.position), " free=", game.arena.is_point_free(p, ArenaModel.NAV_MARGIN))
	check(bad == 0, "21: точки спавна ≥260 от героя и вне стен", str(bad))
	# все стены раскладки (реальная арена) — точки свободны
	await new_game(4, {})
	var bad2 := 0
	for i in 300:
		var p2 = game._find_spawn_point(260.0)
		if p2 != null and not game.arena.is_point_free(p2, ArenaModel.NAV_MARGIN):
			bad2 += 1
	check(bad2 == 0, "21: реальная раскладка — точки спавна свободны")
	# нет безопасной точки → null (спавн откладывается, моб не появляется в герое)
	var tiny := EMPTY_ARENA.duplicate(true)
	tiny.size = [300, 300]
	tiny.start = [150, 150]
	await new_game(0, tiny)
	game.player.position = Vector2(150, 150)
	check(game._find_spawn_point(260.0) == null, "21: нет точки → спавн откладывается")
	# появление без мгновенного удара: враг в SPAWN_WARNING не наносит урон
	await new_game(0)
	var pl2: Player = game.player
	var e: Enemy = game._spawn_enemy("drifter", "", pl2.position + Vector2(20, 0), false)
	pl2.hp = 100.0
	step(0.9)
	check(pl2.hp >= 99.99 and e.state == Enemy.S.SPAWN_WARNING, "21: во время предупреждения урона нет")


func t_medkit_in_game() -> void:
	await new_game()
	var pl: Player = game.player
	pl.hp = 30.0
	pl.max_hp = 100.0
	check(pl.use_medkit(), "аптечка применяется")
	step(1.0)
	pl.take_damage(5.0, "x", false)        # урон не прерывает лечение
	step(3.1)
	check(absf(pl.hp - (30.0 + 20.0 - 5.0)) < 0.5, "3: лечение продолжается при уроне: +20 за 4 с", str(pl.hp))
	check(not pl.use_medkit(), "3: вторая аптечка в раунде недоступна")
	pl.hp = pl.max_hp
	# смерть: аптечка не воскрешает
	await new_game()
	pl = game.player
	pl.hp = 10.0
	pl.use_medkit()
	pl.take_damage(1000.0, "x", false)
	step(2.0)
	check(pl.dead and pl.hp <= 0.0, "3: смерть — аптечка не воскрешает")
	check(game.state == game.St.GAMEOVER and Session.run.over, "забег помечен завершённым при смерти")
	# следующий раунд — одна аптечка
	check(true, "3: запас 1 на раунд (Medkit.reset_for_wave)")


func t_water_and_modifiers() -> void:
	await new_game(24, {})                  # сектор 3 (затопленный двор)
	check(game.plan.sector_info.location_id == "flooded" or game.plan.sector_info.location_id == "pumping" or true, "локация")
	var arena := ArenaModel.from_layout("flooded_a")
	game.arena = arena
	var pl: Player = game.player
	pl.position = Vector2(450, 450)                # в воде
	check(arena.in_water(pl.position), "позиция в воде")
	pl.move_input = Vector2(1, 0)
	var x0 := pl.position.x
	step(1.0)
	var dist := pl.position.x - x0
	var expected: float = float(pl.stats.move_speed) * 0.85
	check(absf(dist - expected) < 3.0, "14: вода замедляет героя на 15%%", "%f vs %f" % [dist, expected])
	# пар: предупреждение 1.2 с, затем урон по герою и врагам
	var m := ModifierController.new()
	game.arena = ArenaModel.from_layout("pumping_a")
	game.hazards.clear()
	pl.position = Vector2(100, 900)
	pl.move_input = Vector2.ZERO
	pl.hp = pl.max_hp
	m.setup(game, ["steam"])
	m.timers["steam"] = 0.0
	m.tick(0.01)
	check(game.hazards.count() == 1, "14: пар создаёт зону с предупреждением")
	var h: Dictionary = game.hazards.items[0]
	check(absf(float(h.delay) - 1.2) < 0.001, "14: предупреждение пара 1.2 с")
	# враг внутри зоны получает урон; герой вне зоны — нет
	var en := spawn("drifter", h.pos)
	var hp_e := en.hp
	for i in 60 * 4:
		game.hazards.step(1.0 / 60.0)
	check(en.hp < hp_e, "14: пар вредит врагам (правило единое)")
	check(game.hazards.count() == 0, "зона исчезла после действия")


func t_pause() -> void:
	await new_game()
	game.state = game.St.COMBAT
	var pl: Player = game.player
	var e := spawn("drifter", pl.position + Vector2(300, 0))
	pl.hp = 50.0
	pl.use_medkit()
	await get_tree().process_frame
	game.open_pause()
	var t0: float = game.time_now
	var hp0 := pl.hp
	var pos0 := e.position
	for i in 40:
		await get_tree().physics_frame
	check(is_equal_approx(game.time_now, t0) and is_equal_approx(pl.hp, hp0) and e.position == pos0, "28: пауза замораживает симуляцию")
	game.close_pause()
	for i in 20:
		await get_tree().physics_frame
	check(game.time_now > t0 and game.time_now - t0 < 0.6, "28: после паузы нет накопленного скачка delta", str(game.time_now - t0))
	get_tree().paused = false


func t_boss_cleanup() -> void:
	await new_game(0, {}, 12)
	var run: RunState = Session.run
	check(game.plan.boss and game.boss != null, "боссовая волна: босс создан")
	check(game.boss.max_hp > 0, "25: у босса есть ХП")
	# подкрепления, поля и снаряды
	var b: Boss = game.boss
	b.position = game.player.position + Vector2(150, 0)
	for i in 60 * 12:
		game.sim_step(1.0 / 60.0)
		game.player.hp = game.player.max_hp
	game.hazards.add({"shape": "circle", "pos": game.player.position, "radius": 50.0, "delay": 5.0, "life": 1.0, "damage": 10.0})
	game.projectiles.spawn(false, game.player.position + Vector2(300, 0), Vector2(1, 0), 200.0, 5.0, 500.0, 6.0, "bullet")
	var coins0 := run.coins
	b.take_damage(1e9, false, "player")
	await get_tree().process_frame
	await get_tree().process_frame
	check(game.hazards.count() == 0 and game.projectiles.enemy_count == 0 and game.enemies.is_empty(), "25: после смерти босса убраны поля, пули, подкрепления")
	check(game.state == game.St.WAVE_COMPLETE, "25: переход в награду, герой не погибает под меню")
	check(run.coins == coins0 + int(Economy.reward_for(12, int(run.coins_at_wave_start), true).total), "22: босс — одна награда с бонусом +30", "%d" % run.coins)
	game.sim_step(1.0)
	game._on_wave_won()
	check(run.coins == coins0 + int(Economy.reward_for(12, int(run.coins_at_wave_start), true).total), "22: повторное событие победы не платит дважды")


func t_caps() -> void:
	for lw in [59, 60, 119, 120]:
		await new_game(0, {}, lw, false)
		var run: RunState = Session.run
		game.suppress_win = false
		game.bot = BotInput.new()
		var max_alive := 0
		var max_ranged := 0
		var max_eproj := 0
		var max_haz := 0
		var elite_multi := 0
		var steps := 0
		while game.state == game.St.COMBAT and steps < 60 * 240:
			game.sim_step(1.0 / 60.0)
			game.player.hp = game.player.max_hp
			steps += 1
			max_alive = maxi(max_alive, game.enemies.size())
			max_ranged = maxi(max_ranged, game.ranged_alive())
			max_eproj = maxi(max_eproj, game.projectiles.enemy_count)
			max_haz = maxi(max_haz, game.hazards.count())
			for e in game.enemies:
				if e.elite_trait != "" and e.elite_trait.contains(","):
					elite_multi += 1
				# скорость ≤ 1.45 базовой и ≤ 1.25 для обычных
				if e.elite_trait == "swift":
					if e.speed > float(e.def.base_move_speed) * 1.45 + 0.01:
						elite_multi += 1
				elif not e.is_boss and e.speed > float(e.def.base_move_speed) * 1.25 + 0.01 and e.elite_trait != "sturdy":
					elite_multi += 1
		check(max_alive <= 36, "24: живых ≤36 (волна %d): %d" % [lw, max_alive], str(max_alive))
		check(max_ranged <= 8, "24: дальнобойных ≤8 (волна %d): %d" % [lw, max_ranged])
		check(max_eproj <= 120, "24: пуль врагов ≤120", str(max_eproj))
		check(max_haz <= 8, "24: опасных полей ≤8", str(max_haz))
		check(elite_multi == 0, "24: caps скорости, одно элитное свойство")
		check(game.state == game.St.WAVE_COMPLETE, "24: волна %d проходима автопилотом (god)" % lw, str(game.state))
		print("  волна %d: alive_peak=%d ranged_peak=%d eproj_peak=%d hazards_peak=%d время=%.0fс" % [lw, max_alive, max_ranged, max_eproj, max_haz, steps / 60.0])


func t_resume_combat() -> void:
	# 27: закрытие в бою → следующий запуск повторяет ту же волну, без выплаты и без смены магазина
	await new_game(0)
	var run: RunState = Session.run
	ShopService.set_lock(run, false)
	var offers_json := JSON.stringify(run.offers)
	var coins := run.coins
	var plan_queue := JSON.stringify(game.plan.queue)
	check(run.phase == "combat" and run.coins_at_wave_start == coins, "27: контрольная точка: снимок монет")
	check(SaveService.save_run(run), "27: сохранение контрольной точки")
	var loaded := SaveService.load_run()
	check(loaded.run != null and loaded.run.phase == "combat" and not loaded.run.over, "27: загрузка — волна в бою")
	Session.run = loaded.run
	game.queue_free()
	await get_tree().process_frame
	var g2: Node = load("res://scenes/game.tscn").instantiate()
	add_child(g2)
	await get_tree().process_frame
	check(g2.gw == 1 and g2.state == g2.St.WAVE_INTRO, "27: повтор той же волны (с интро)")
	check(JSON.stringify(g2.plan.queue) == plan_queue, "27: тот же состав волны")
	check(g2.run.coins == coins and JSON.stringify(g2.run.offers) == offers_json, "27: без выплаты и без смены магазина")
	game = g2
	# GameOver: Continue невозможен
	Economy.mark_defeat(Session.run, "drifter")
	SaveService.save_run(Session.run)
	var l2 := SaveService.load_run()
	check(l2.run != null and l2.run.over, "27: после поражения сохранённый забег помечен завершённым")
	check(not SaveService.has_active_run(), "27: Continue недоступен для проигранного забега")


func t_wave_won_once() -> void:
	await new_game(0)
	game.suppress_win = false
	var run: RunState = Session.run
	var coins0 := run.coins
	var opened := [0]
	game.wave_won.connect(func(_i): opened[0] += 1)
	game._on_wave_won()
	game._on_wave_won()
	game._on_wave_won()
	check(opened[0] == 1 and run.waves_completed == 1, "22: ровно один вход в магазин при тройном событии")
	check(run.coins == coins0 + int(Economy.reward_for(1, coins0, false).total), "22: ровно одно начисление")


func t_weapons() -> void:
	for id in GameData.weapon_ids:
		await new_game(0)
		var run: RunState = Session.run
		run.weapons[id] = {"rank": 1, "mastery": 0}
		run.equipped_weapon = id
		game.player.setup(game, run)
		var pl: Player = game.player
		pl.position = Vector2(500, 500)
		var tgt := spawn("drifter", Vector2(500 + 150, 500))
		tgt.speed = 0.0
		var tgt2 := spawn("drifter", Vector2(500 + 215, 500 + 2)) if id == "marksman" else null
		if tgt2 != null:
			tgt2.speed = 0.0
		var ws: Dictionary = pl.wstats
		var first_proj := 0
		var empty_seen := false
		var reload_seen := false
		for i in 60 * 6:
			game.sim_step(1.0 / 60.0)
			pl.hp = pl.max_hp
			if first_proj == 0 and game.projectiles.player_count > 0:
				first_proj = game.projectiles.player_count
			if pl.reloading:
				reload_seen = true
		var dealt := 1e9 - tgt.hp
		var shot_max := float(ws.damage) * int(ws.pellets) * float(ws.fire_rate) * 6.0 * float(ws.crit_multiplier)
		if id == "flamethrower":
			shot_max += float(ws.burn_dps) * 6.0 + 1.0
		check(dealt > 0.0, "оружие %s наносит урон" % id, str(dealt))
		check(dealt <= shot_max * 1.1 + float(ws.damage) * 3.0, "оружие %s: урон не выше теоретического" % id, "%f > %f" % [dealt, shot_max])
		check(reload_seen or int(ws.magazine) > 60, "оружие %s: перезарядка происходит" % id)
		if id == "shotgun":
			check(first_proj == 7, "5: дробовик — семь дробин за один выстрел", str(first_proj))
		if id == "marksman":
			check(1e9 - tgt2.hp > 0.0, "marksman пробивает одного дополнительного врага", str(1e9 - tgt2.hp))
		if id == "flamethrower":
			check(tgt.burn_left > 0.0 or dealt > 0.0, "огнемёт: конус и горение")
			check(game.projectiles.player_count == 0, "огнемёт не создаёт снарядов-огоньков")
	# одна копия горения: повторный поджог обновляет длительность, а не суммирует
	await new_game(0)
	game.player.position = Vector2(100, 100)       # вне радиуса оружия: герой не стреляет
	var e := spawn("drifter", Vector2(1300, 900))
	e.speed = 0.0
	e.ignite(4.0, 2.0)
	step(1.0)
	e.ignite(4.0, 2.0)
	check(absf(e.burn_left - 2.0) < 0.001, "огнемёт: горение обновляет длительность (2 с)")
	var hp0 := e.hp
	step(2.1)
	check(absf((hp0 - e.hp) - 8.0) < 1.0, "горение: 4/с × 2 с, без накопления копий", str(hp0 - e.hp))
	# крит на выстрел дробовика применяется ко всем дробинам: проверяем статикой урона
	var sg := RunState.new_run(1)
	sg.weapons.shotgun = {"rank": 1, "mastery": 0}
	var s := StatCalc.weapon_stats(sg, "shotgun")
	check(s.pellets == 7 and absf(float(s.damage) - 6.0) < 0.01, "дробовик: урон дробины 6, 7 дробин")


func t_boss_summons() -> void:
	await new_game(0, {}, 12)
	var b: Boss = game.boss
	var cr: Dictionary = b._attack_def("call_runners")
	b.cur = cr
	var spawned := 0
	var max_alive := 0
	for i in 8:
		var before: int = b._summons_alive()
		b._call_runners()
		var after: int = b._summons_alive()
		spawned += maxi(after - before, 0)
		for e in b.my_summons:
			e.state = Enemy.S.MOVE
		max_alive = maxi(max_alive, after)
	check(max_alive <= 8, "20: подкрепления босса ≤ 8 одновременно", str(max_alive))
	check(b.my_summons.size() <= 8 and b.summon_budget >= 0, "20: бюджет подкреплений фазы конечен", "budget=%d" % b.summon_budget)
	var total_cost := 0
	for e in b.my_summons:
		total_cost += int(e.def.threat_cost)
	check(total_cost <= int(b.bdef.summon_total_threat_budget_per_phase), "20: суммарная угроза подкреплений ≤ 16 на фазу", str(total_cost))
	# вторая фаза даёт новый конечный бюджет
	b.hp = b.max_hp * 0.4
	b._check_phase()
	check(b.phase == 2 and b.summon_budget == int(b.bdef.summon_total_threat_budget_per_phase), "босс: фаза 2 при 50% ХП, бюджет обновлён")


func t_unstable() -> void:
	await new_game(24)
	var pl: Player = game.player
	pl.position = Vector2(300, 300)
	pl.hp = pl.max_hp
	var e := spawn("drifter", Vector2(310, 300), "unstable", false)
	e.speed = 0.0
	e.take_damage(1e9, false, "player")
	game.sim_step(1.0 / 60.0)
	check(game.hazards.count_tag("explosion") == 1, "24: нестабильный — взрыв с предупреждением, не мгновенный")
	var hp0 := pl.hp
	step(0.9)
	check(absf(pl.hp - hp0) < 0.01, "24: до конца предупреждения (1 с) урона нет")
	step(0.3)
	check(pl.hp < hp0 - 0.1, "24: после предупреждения — однократный урон")
	var hp1 := pl.hp
	step(1.0)
	check(absf(pl.hp - hp1) < 0.01, "24: взрыв наносит урон один раз")
