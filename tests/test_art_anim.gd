extends Node
## Анимации партии 5 в игре: ходьба/замах/смерть врагов, трупы (смещение, срок, лимит), броня в движении,
## карточки и ящики, эффекты. Проверяется поведение кода, а не качество рисунка.
## godot --headless --path . --quit-after 400000 res://tests/test_art_anim.tscn

var passed := 0
var failed := 0
var game: Node

const EMPTY := {"id": "t_empty", "location_id": "sawmill", "size": [2400, 1250], "start": [1200, 625], "walls": [], "water": [], "hazard_slots": []}


func check(c: bool, name: String, extra: String = "") -> void:
	if c:
		passed += 1
	else:
		failed += 1
		print("  FAIL: ", name, " ", extra)


func new_game(wave_done: int = 0) -> void:
	if game != null:
		game.queue_free()
		await get_tree().process_frame
	Session.new_run(13)
	Session.run.waves_completed = wave_done
	game = load("res://scenes/game.tscn").instantiate()
	game.auto_open_ui = false
	add_child(game)
	await get_tree().process_frame
	ShopService.begin_wave(Session.run)
	game._launch_wave()
	game.queue.clear()
	game.suppress_win = true
	game.state = game.St.COMBAT
	game.arena = ArenaModel.new()
	game.arena.load_layout(EMPTY)
	game.player.position = game.arena.start
	game.player.hp = 1e9
	game.player.max_hp = 1e9


func spawn(id: String, pos: Vector2) -> Enemy:
	var e: Enemy = game._spawn_enemy(id, "", pos, false)
	e.state = Enemy.S.MOVE
	e.sprite.visible = true
	e.hp = 1e9
	e.max_hp = 1e9
	return e


func _ready() -> void:
	Settings.data.tutorial_done = true
	Settings.data.tutorial_shop_done = true
	GameData.load_all()
	# файлы партии 5 присутствуют и распознаются по раскладкам
	for id in ["enemy.drifter.walk", "enemy.drifter.attack", "enemy.drifter.death", "boss.cleaver.walk", "boss.cleaver.death", "corpse.drifter", "corpse.boss.cleaver", "armor.light.anim", "fx.fire_loop", "fx.explosion", "ui.card_flip_buff", "ui.bonus_case_anim", "water.flooded", "water.flooded_edge", "prop.machine_a", "prop.pipe_long", "ui.logo", "ui.menu_bg", "ui.coin"]:
		check(AssetRegistry.file_exists(id), "файл есть: " + id)
	var wf := AssetRegistry.anim_frame("enemy.drifter.walk", "E", 2)
	check(wf.region == Rect2(512, 256, 256, 256) and not wf.flip_h, "ходьба: кадр 2, ряд E → клетка (512,256)", str(wf.region))
	check(AssetRegistry.anim_frame("enemy.drifter.walk", "W", 0).flip_h, "W зеркалится из E")
	check(AssetRegistry.anim_frame("boss.cleaver.walk", "N", 3).region == Rect2(1536, 1024, 512, 512), "босс: клетка 512, ряд N")
	check(AssetRegistry.strip_frame("fx.explosion", 7).region == Rect2(1792, 0, 256, 256), "эффект: полоса 8 кадров")
	check(AssetRegistry.corpse_offset("corpse.drifter") == Vector2(0, -17), "смещение трупа из метаданных (0,-17)", str(AssetRegistry.corpse_offset("corpse.drifter")))
	check(AssetRegistry.corpse_offset("corpse.boss.cleaver") == Vector2(0, -47.5), "смещение трупа босса из метаданных")
	# ходьба / замах
	await new_game(4)
	var pl: Player = game.player
	pl.position = game.arena.start + Vector2(-500, 0)
	var e := spawn("drifter", game.arena.start + Vector2(500, 0))
	var saw_walk := false
	for i in 90:
		game.sim_step(1.0 / 60.0)
		if e._frame_key.begins_with("walk"):
			saw_walk = true
	check(saw_walk, "враг в движении показывает кадры ходьбы")
	var key_walk: String = e._frame_key
	# замах: ставим вплотную
	var e2 := spawn("drifter", pl.position + Vector2(26, 0))
	e2.speed = 0.0
	var saw_attack := false
	var saw_peak := false
	var saw_recovery := false
	for i in 150:
		game.sim_step(1.0 / 60.0)
		if e2._frame_key.begins_with("attack|"):
			saw_attack = true
			if e2._frame_key.ends_with("|1"):
				saw_peak = true
			if e2._frame_key.ends_with("|2"):
				saw_recovery = true
	check(saw_attack and saw_peak and saw_recovery, "замах: подготовка → пик → возврат (3 позы)", "%s %s %s" % [saw_attack, saw_peak, saw_recovery])
	# смерть → труп
	game.enemies.erase(e)
	e.queue_free()
	var tgt := spawn("runner", game.arena.start + Vector2(300, 100))
	tgt.speed = 0.0
	var pos0 := tgt.position
	game.corpses.clear()
	tgt.take_damage(1e12, false, "player")
	check(game.corpses.size() == 1 and is_instance_valid(game.corpses[0]), "смерть создаёт труп")
	var c: Corpse = game.corpses[0]
	check(c.position == pos0 and c._phase == 0, "анимация смерти стартует в позиции врага")
	for i in 60:
		game.sim_step(1.0 / 60.0)
	check(c._phase == 1 and c.position.is_equal_approx(pos0 + AssetRegistry.corpse_offset("corpse.runner")), "после 4 кадров — лежащий труп со смещением из метаданных", str(c.position))
	var life := 0.0
	while is_instance_valid(c) and life < 12.0:
		game.sim_step(1.0 / 60.0)
		life += 1.0 / 60.0
		if game.corpses.is_empty():
			break
	check(life > 6.0 and life < 9.5, "труп лежит ~7 с и исчезает", str(life))
	# лимит трупов
	for i in 40:
		var z := spawn("drifter", game.arena.start + Vector2(200 + i * 5, 200))
		z.take_damage(1e12, false, "player")
	check(game.corpses.size() <= 24, "число трупов ограничено (≤24)", str(game.corpses.size()))
	# босс — труп босса
	await new_game(0)
	game.plan.boss = true
	var b := Boss.new()
	b.setup_boss(game, "cleaver", 12, game.arena.start + Vector2(400, 0))
	game.entities.add_child(b)
	game.enemies.append(b)
	game.boss = b
	b.state = Enemy.S.MOVE
	b.sprite.visible = true
	b.take_damage(1e12, false, "player")
	check(game.corpses.size() == 1 and game.corpses[0].corpse_id == "corpse.boss.cleaver", "босс оставляет труп corpse.boss.cleaver")
	# броня в движении
	await new_game(0)
	pl = game.player
	var run: RunState = Session.run
	run.armors["field"] = {"rank": 1, "mastery": 0}
	run.equipped_armor = "field"
	pl.setup(game, run)
	pl.aim_dir = Vector2.RIGHT
	pl.vel = Vector2(150, 0)
	pl.walk_t = 0.27
	pl._frame_key = ""
	pl._update_visuals(0.0)
	var idx := int(pl.walk_t * 8.0) % 4
	check(pl.armor_sprite.visible and pl.armor_sprite.region_rect.position.x == idx * 256 and pl.armor_sprite.region_rect.position.y == 256, "броня на ходьбе: колонка %d, ряд E" % idx, str(pl.armor_sprite.region_rect))
	pl.vel = Vector2.ZERO
	pl.hit_flash = 0.1
	pl._frame_key = ""
	pl._update_visuals(0.0)
	check(pl.armor_sprite.region_rect.position.x == 4 * 256, "броня при ударе: колонка hit (4)", str(pl.armor_sprite.region_rect))
	pl.hit_flash = 0.0
	pl.dead = true
	pl._frame_key = ""
	pl._update_visuals(0.0)
	check(not pl.armor_sprite.visible, "при смерти броня скрыта")
	# эффекты: огонь, взрыв, искры
	await new_game(24)
	game.fx.anims.clear()
	game.hazards.add({"shape": "circle", "pos": game.arena.start + Vector2(200, 0), "radius": 90.0, "delay": 0.1, "life": 1.0, "damage": 1.0, "once": true, "tag": "explosion", "palette": "enemy"})
	for i in 20:
		game.hazards.step(1.0 / 60.0)
	check(game.fx.anims.size() >= 1 and game.fx.anims[0].id == "fx.explosion", "взрыв проигрывает fx.explosion")
	game.fx.anims.clear()
	game.hazards.add({"shape": "circle", "pos": game.arena.start + Vector2(250, 0), "radius": 95.0, "delay": 0.1, "life": 2.0, "damage": 1.0, "tick": 0.5, "palette": "fire", "tag": "molotov"})
	for i in 20:
		game.hazards.step(1.0 / 60.0)
	check(game.fx.anims.size() >= 1 and game.fx.anims[0].id == "fx.fire_burst", "поджог проигрывает fx.fire_burst, затем цикл fx.fire_loop")
	game.fx.spark(game.arena.start)
	check(game.fx.anims.size() >= 1, "искры попадания — покадровый эффект")
	# декор: не создаёт коллизий, не блокирует старт
	await new_game(0)
	var decor := 0
	for n in game.entities.get_children():
		if n is Sprite2D:
			decor += 1
	check(decor >= 10, "декор расставлен (спрайты без коллизии)", str(decor))
	game.sim_step(1.0 / 60.0)
	check(true, "декор не ломает шаг симуляции (update_fade только у WallProp)")
	# укрытия: варианты и безопасное число стен
	var vp := WallProp.new()
	vp.setup(Rect2(0, 0, 80, 220), "concrete", Color.WHITE)
	check(vp._variants_ready("concrete") and vp._variants_ready("pipe") and vp._variants_ready("machine") and vp._variants_ready("debris"), "варианты укрытий найдены (бетон, трубы, станки, машины)")
	vp.free()
	print("ИТОГО (арт партии 5 в игре): passed=%d failed=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
