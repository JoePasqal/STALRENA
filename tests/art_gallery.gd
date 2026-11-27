extends Node
## Проверка графики в реальной игре. Нужен дисплей (xvfb) и opengl3.
## godot --path . res://tests/art_gallery.tscn -- --out=/dir [--mode=hero|armor|enemies|props|walk|death|all]
## Сохраняет PNG-листы и последовательности кадров (для GIF).

var args := {}
var game: Node
var out := "/tmp/gallery"

const EMPTY := {"id": "g_empty", "location_id": "sawmill", "size": [1600, 1000], "start": [800, 500], "walls": [], "water": [], "hazard_slots": []}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	out = str(args.get("out", "/tmp/gallery"))
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1280, 720)
	Settings.data.autoaim = false
	Session.new_run(3)
	game = load("res://scenes/game.tscn").instantiate()
	game.auto_open_ui = false
	add_child(game)
	await _f(2)
	var mode := str(args.get("mode", "all"))
	await _begin(EMPTY)
	if mode in ["hero", "all"]: await hero_sheet()
	if mode in ["armor", "all"]: await armor_sheet()
	if mode in ["enemies", "all"]: await enemies_shot()
	if mode in ["walk", "all"]: await walk_frames()
	if mode in ["death", "all"]: await death_frames()
	if mode in ["walkn", "all"]: await walk_n_weapons()
	if mode in ["floors", "all"]: await floors_shot()
	if mode in ["props", "all"]:
		await props_shot()
	get_tree().quit()


func _f(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _begin(arena: Dictionary, wave_done: int = 0) -> void:
	Session.run.phase = "shop"
	Session.run.waves_completed = wave_done
	ShopService.begin_wave(Session.run)
	game._launch_wave()
	game.queue.clear()
	game.suppress_win = true
	game.state = game.St.COMBAT
	if not arena.is_empty():
		game.arena = ArenaModel.new()
		game.arena.load_layout(arena)
	if arena.has("walls") and arena.walls.is_empty():
		game._clear_arena_nodes()            # убрать визуальные стены реальной раскладки
	game.set_physics_process(false)          # шаги симуляции — только вручную (иначе _poll_input обнуляет ввод)
	game.results_ui.visible = false
	game.player.position = game.arena.start
	game.hud.visible = false
	game.touch.visible = false
	game.cam.zoom = Vector2(2, 2)
	game.cam.position = game.player.position
	game.cam.limit_left = -2000
	game.cam.limit_top = -2000
	game.cam.limit_right = 4000
	game.cam.limit_bottom = 4000


func _setup_player(weapon: String, armor: String, dir: Vector2) -> void:
	var run: RunState = Session.run
	run.weapons[weapon] = {"rank": 1, "mastery": 0}
	run.equipped_weapon = weapon
	if armor != "":
		run.armors[armor] = {"rank": 1, "mastery": 0}
	run.equipped_armor = armor
	var pl: Player = game.player
	pl.setup(game, run)
	pl.position = game.arena.start
	pl.aim_dir = dir
	pl.vel = Vector2.ZERO
	pl.move_input = Vector2.ZERO
	pl.debug_muzzle = true
	pl._frame_key = ""
	pl._update_visuals(0.0)


func _crop() -> Image:
	var img := get_viewport().get_texture().get_image()
	var c := img.get_size() / 2
	return img.get_region(Rect2i(c.x - 150, c.y - 190, 300, 300))


func _sheet(rows: Array, cols: int, name: String) -> void:
	var rowsn := int(ceil(rows.size() / float(cols)))
	var sheet := Image.create(300 * cols, 300 * rowsn, false, Image.FORMAT_RGBA8)
	for i in rows.size():
		sheet.blit_rect(rows[i], Rect2i(0, 0, 300, 300), Vector2i((i % cols) * 300, (i / cols) * 300))
	sheet.save_png("%s/%s.png" % [out, name])


func hero_sheet() -> void:
	var crops: Array = []
	for weapon in GameData.weapon_ids:
		for dir in [Vector2.DOWN, Vector2.RIGHT, Vector2.UP, Vector2.LEFT]:
			_setup_player(weapon, "", dir)
			await _f(3)
			crops.append(_crop())
	_sheet(crops, 4, "hero_weapons_SENW_all7")


func armor_sheet() -> void:
	var crops: Array = []
	for armor in ["light", "field", "heavy"]:
		for dir in [Vector2.DOWN, Vector2.RIGHT, Vector2.UP, Vector2.LEFT]:
			_setup_player("carbine", armor, dir)
			await _f(3)
			crops.append(_crop())
	_sheet(crops, 4, "armor_light_field_heavy_SENW")
	# рука/перчатки при ходьбе и ударе в E
	crops = []
	for armor in ["light", "field", "heavy"]:
		_setup_player("pistol", armor, Vector2.RIGHT)
		game.player.hit_flash = 0.1
		game.player._frame_key = ""
		game.player._update_visuals(0.0)
		await _f(3)
		crops.append(_crop())
		game.player.hit_flash = 0.0
		for k in 3:
			game.player.move_input = Vector2(1, 0)
			game.player.walk_t = 0.13 * (k + 1) * 2
			game.player.vel = Vector2(150, 0)
			game.player._frame_key = ""
			game.player._update_visuals(0.0)
			await _f(3)
			crops.append(_crop())
	_sheet(crops, 4, "armor_E_hit_and_walk")


func enemies_shot() -> void:
	game.player.visible = false
	var ids: Array = GameData.enemies.keys()
	var dirs := [Vector2.DOWN, Vector2.RIGHT, Vector2.UP, Vector2.LEFT]
	var crops: Array = []
	for id in ids:
		for d in dirs:
			var e: Enemy = game._spawn_enemy(id, "", game.arena.start, false)
			e.state = Enemy.S.MOVE
			e.sprite.visible = true
			e.face = d
			e.hp = e.max_hp
			e._update_visual(0.0)
			await _f(3)
			crops.append(_crop())
			game.enemies.erase(e)
			e.queue_free()
	_sheet(crops, 4, "enemies_all8_SENW")
	game.player.visible = true


func props_shot() -> void:
	await _begin({}, 0)
	game.cam.zoom = Vector2(1, 1)
	game.cam.position = Vector2(800, 500)
	game.player.visible = false
	await _f(4)
	get_viewport().get_texture().get_image().save_png("%s/props_sawmill.png" % out)
	game._build_arena({"layout_id": "sawmill_b", "location_id": "sawmill", "tint_index": 0, "sector": 1})
	game.cam.position = Vector2(800, 500)
	await _f(4)
	get_viewport().get_texture().get_image().save_png("%s/props_sawmill_b.png" % out)


func _seq(name: String, n: int, steps_between: int, setup_each: Callable) -> void:
	for i in n:
		setup_each.call(i)
		for s in steps_between:
			game.sim_step(1.0 / 60.0)
		await _f(2)
		_crop().save_png("%s/%s_%02d.png" % [out, name, i])


func walk_frames() -> void:
	for pair in [["E", Vector2.RIGHT], ["S", Vector2.DOWN], ["N", Vector2.UP]]:
		_setup_player("carbine", "field", pair[1])
		game.player.position = Vector2(500, 500)
		var dir: Vector2 = pair[1]
		await _seq("walk_" + pair[0], 20, 6, func(_i):
			game.player.move_input = dir
			game.player.aim_dir = dir)
		game.player.position = game.arena.start
	game.player.move_input = Vector2.ZERO


func death_frames() -> void:
	_setup_player("carbine", "field", Vector2.RIGHT)
	var pl: Player = game.player
	pl.position = game.arena.start
	game.cam.position = pl.position
	await _f(2)
	pl.dead = true
	pl.death_t = 0.0
	pl.move_input = Vector2.ZERO
	pl.medkit.clear_effect()
	for i in 14:
		pl.tick(0.1)
		await _f(2)
		_crop().save_png("%s/death_%02d.png" % [out, i])


## Ходьба/hit на N с каждым оружием: проверка видимой перчатки и покадровых сокетов.
func walk_n_weapons() -> void:
	for weapon in GameData.weapon_ids:
		var crops: Array = []
		_setup_player(weapon, "field", Vector2.UP)
		for k in 4:
			game.player.vel = Vector2(0, -150)
			game.player.walk_t = (k + 0.1) / 8.0
			game.player._frame_key = ""
			game.player._update_visuals(0.0)
			await _f(3)
			crops.append(_crop())
		game.player.vel = Vector2.ZERO
		game.player.hit_flash = 0.1
		game.player._frame_key = ""
		game.player._update_visuals(0.0)
		await _f(3)
		crops.append(_crop())
		game.player.hit_flash = 0.0
		game.player._frame_key = ""
		game.player._update_visuals(0.0)
		await _f(3)
		crops.append(_crop())
		_sheet(crops, 6, "N_walk_hit_idle_" + weapon)


func floors_shot() -> void:
	for loc in ["sawmill", "pumping", "flooded"]:
		var tex := AssetRegistry.get_texture("floor." + loc)
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		var big := Image.create(1536, 1536, false, Image.FORMAT_RGBA8)
		for x in 3:
			for y in 3:
				big.blit_rect(img, Rect2i(0, 0, 512, 512), Vector2i(x * 512, y * 512))
		big.resize(900, 900)
		big.save_png("%s/floor_3x3_%s.png" % [out, loc])
	# реальные арены трёх локаций
	for pair in [["sawmill_a", "sawmill"], ["pumping_a", "pumping"], ["flooded_a", "flooded"]]:
		await _begin({}, 0)
		game._build_arena({"layout_id": pair[0], "location_id": pair[1], "tint_index": 0, "sector": 1})
		game.cam.zoom = Vector2(0.8, 0.8)
		game.cam.position = Vector2(800, 500)
		game.player.position = Vector2(800, 500)
		game.player.visible = true
		await _f(4)
		get_viewport().get_texture().get_image().save_png("%s/arena_%s.png" % [out, pair[1]])
