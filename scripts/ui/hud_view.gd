class_name HudView
extends Control
## HUD: ХП, боезапас, волна/сектор, аптечка и прогресс лечения, пауза, указатели
## атак за пределами экрана, баннеры. Рисуется одним _draw, обновляется из состояния игры.

var game
var _flash := 0.0
var _banner_title := ""
var _banner_sub := ""
var _banner_t := 0.0
var _banner_total := 1.0
var _pause_btn: Button
var _fps_acc := 0.0
var _fps_frames := 0
var _fps_val := 0.0


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_btn = UiKit.button("Пауза", Vector2(110, 46), 20)
	_pause_btn.pressed.connect(func(): game.open_pause())
	add_child(_pause_btn)


func on_hurt() -> void:
	_flash = 0.28


func show_wave_intro(run: RunState, gw: int, plan: Dictionary) -> void:
	var info: Dictionary = plan.sector_info
	var loc: String = GameData.locations[info.location_id].name
	var local := run.local_wave_of(gw)
	_banner_title = "Сектор %d · Волна %d/%d" % [run.sector_of(gw), local, int(GameData.B.waves.sector_length)]
	var sub := loc
	if plan.boss:
		_banner_title = "БОСС · " + GameData.bosses[plan.boss_id].name
	else:
		sub += " · " + WaveDirector.archetype_title(plan.archetype)
	var hint := _new_enemy_hint(gw)
	if hint != "" and bool(Settings.data.hints):
		sub += "\n" + hint
	if info.modifier != "":
		sub += "\nОпасность арены: " + str(GameData.modifiers[info.modifier].name)
	elif info.native_hazard != "":
		sub += "\nОпасность арены: " + str(GameData.modifiers[info.native_hazard].name)
	_banner_sub = sub
	_banner_total = 2.4
	_banner_t = _banner_total


func show_wave_complete(res: Dictionary) -> void:
	var rw: Dictionary = res.reward
	_banner_title = "Волна %d пройдена" % int(res.wave)
	_banner_sub = "+%d монет (база %d, рост %d, процент %d%s)" % [int(rw.total), int(rw.base), int(rw.growth), int(rw.interest), (", босс %d" % int(rw.boss)) if int(rw.boss) > 0 else ""]
	_banner_total = 2.4
	_banner_t = _banner_total


const HINTS := {
	"drifter": "Бродяга: медленный, бьёт после замаха.",
	"runner": "Новый: Бегун — быстрый, кусает после короткой остановки.",
	"charger": "Новый: Таран — готовит рывок по прямой. Отойдите вбок.",
	"spitter": "Новый: Плевун — держит дистанцию, плевок летит в отмеченную точку.",
	"gunner": "Новый: Стрелок — очередь из трёх пуль, не стреляет сквозь стены. Двигайтесь поперёк линии.",
	"brute": "Новый: Громила — тяжёлый удар по кругу. Выйдите из круга до удара.",
	"flanker": "Новый: Загонщик — заходит сбоку.",
	"carrier": "Новый: Носитель — после смерти выпускает двух бегунов.",
}


func _new_enemy_hint(gw: int) -> String:
	for id in GameData.enemies:
		if int(GameData.enemies[id].first_wave) == gw and gw > 1:
			return HINTS.get(id, "")
	return ""


func _process(delta: float) -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	_flash = maxf(_flash - delta, 0.0)
	_banner_t = maxf(_banner_t - delta, 0.0)
	_fps_acc += delta
	_fps_frames += 1
	if _fps_acc >= 0.5:
		_fps_val = _fps_frames / _fps_acc
		_fps_acc = 0.0
		_fps_frames = 0
	var touch_on: bool = game.touch != null and game.touch.visible
	_pause_btn.visible = visible and not touch_on and game.state == game.St.COMBAT
	var sm := UiKit.safe_margins(get_viewport())
	_pause_btn.position = Vector2(size.x - 126.0 - sm.size.x, 14.0 + sm.position.y)
	if visible:
		queue_redraw()


func _w2s(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * p


func _draw() -> void:
	if game == null or game.player == null or not game.player.visible:
		return
	var pl: Player = game.player
	var f := ThemeDB.fallback_font
	var sm := UiKit.safe_margins(get_viewport())
	var m := Vector2(18.0 + sm.position.x, 14.0 + sm.position.y)
	var touch_on: bool = game.touch != null and game.touch.visible
	# ---- ХП
	var bw := 320.0
	draw_rect(Rect2(m, Vector2(bw, 28)), Color(0, 0, 0, 0.6))
	var frac := clampf(pl.hp / maxf(pl.max_hp, 1.0), 0.0, 1.0)
	var col := Color(0.5, 0.82, 0.45).lerp(Color(0.9, 0.3, 0.25), 1.0 - frac)
	draw_rect(Rect2(m + Vector2(2, 2), Vector2((bw - 4) * frac, 24)), col)
	if pl.medkit.active:
		var heal_k := pl.medkit.progress()
		draw_rect(Rect2(m + Vector2(2, 30), Vector2((bw - 4) * heal_k, 5)), Color(0.55, 0.85, 1.0))
	var hp_txt := "ХП %d / %d" % [mini(int(ceil(pl.hp)), int(ceil(pl.max_hp))), int(ceil(pl.max_hp))]
	draw_string(f, m + Vector2(0, 21), hp_txt, HORIZONTAL_ALIGNMENT_CENTER, bw, 20, Color.WHITE)
	# ---- оружие и патроны
	var wname := "%s %s" % [str(pl.weapon_def.name), GameData.rank_roman(int(pl.wstats.rank))]
	var ammo_txt := ""
	if pl.reloading:
		ammo_txt = "Перезарядка…"
		var rk := 1.0 - clampf(pl.reload_left / maxf(float(pl.wstats.reload_time), 0.01), 0.0, 1.0)
		draw_rect(Rect2(m + Vector2(0, 62), Vector2(bw * rk, 4)), Color(1.0, 0.8, 0.4))
	else:
		ammo_txt = "%d / %d" % [int(ceil(pl.ammo)), int(pl.wstats.magazine)]
	draw_string(f, m + Vector2(0, 58), "%s   %s" % [wname, ammo_txt], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.9, 0.92, 0.88))
	# ---- волна/сектор/монеты
	var run: RunState = game.run
	var gwv: int = game.gw
	var top := "Сектор %d · Волна %d/%d  (№%d)" % [run.sector_of(gwv), run.local_wave_of(gwv), int(GameData.B.waves.sector_length), gwv]
	draw_string(f, Vector2(0, m.y + 24), top, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color.WHITE)
	draw_string(f, Vector2(0, m.y + 50), "Монеты: %d" % run.coins, HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color(1.0, 0.9, 0.5))
	# ---- аптечка
	var mk := "Аптечка %d/1" % pl.medkit.stock
	if not touch_on:
		draw_rect(Rect2(m + Vector2(0, 74), Vector2(150, 30)), Color(0, 0, 0, 0.5))
		draw_string(f, m + Vector2(8, 96), mk + "  [F]", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.7, 0.9, 1.0) if pl.medkit.stock > 0 else Color(0.5, 0.5, 0.5))
		if pl.medkit.active:
			draw_rect(Rect2(m + Vector2(0, 104), Vector2(150.0 * pl.medkit.progress(), 4)), Color(0.55, 0.85, 1.0))
		if bool(Settings.data.hints) and game.wave_time < 25.0:
			draw_string(f, Vector2(m.x, size.y - 20.0), "WASD — движение · ЛКМ — стрельба · R — перезарядка · F — аптечка · Esc — пауза", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.6))
	# ---- босс
	if game.boss != null and is_instance_valid(game.boss) and game.boss.state != Enemy.S.DEAD:
		var b: Boss = game.boss
		var bwid := 520.0
		var bx := (size.x - bwid) * 0.5
		draw_rect(Rect2(bx, m.y + 62, bwid, 18), Color(0, 0, 0, 0.65))
		draw_rect(Rect2(bx + 2, m.y + 64, (bwid - 4) * clampf(b.hp / b.max_hp, 0.0, 1.0), 14), Color(0.88, 0.3, 0.18))
		draw_string(f, Vector2(bx, m.y + 96), str(b.bdef.name), HORIZONTAL_ALIGNMENT_CENTER, bwid, 18, Color.WHITE)
	# ---- указатели атак за пределами экрана
	_draw_indicators(f)
	# ---- баннер
	if _banner_t > 0.0:
		var a := clampf(minf(_banner_t, _banner_total - _banner_t + 0.0) * 3.0, 0.0, 1.0)
		var lines := _banner_sub.split("\n")
		var y := size.y * 0.30
		draw_string(f, Vector2(2, y + 2), _banner_title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 44, Color(0, 0, 0, a))
		draw_string(f, Vector2(0, y), _banner_title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 44, Color(1, 0.85, 0.6, a))
		for i in lines.size():
			draw_string(f, Vector2(0, y + 38 + i * 28), lines[i], HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color(1, 1, 1, a))
	if _flash > 0.0:
		var fa := _flash / 0.28 * 0.35
		var t := 26.0
		draw_rect(Rect2(0, 0, size.x, t), Color(0.9, 0.1, 0.05, fa))
		draw_rect(Rect2(0, size.y - t, size.x, t), Color(0.9, 0.1, 0.05, fa))
		draw_rect(Rect2(0, 0, t, size.y), Color(0.9, 0.1, 0.05, fa))
		draw_rect(Rect2(size.x - t, 0, t, size.y), Color(0.9, 0.1, 0.05, fa))
	if bool(Settings.data.show_fps):
		draw_string(f, Vector2(size.x - 120.0, size.y - 14.0), "FPS %d" % int(_fps_val), HORIZONTAL_ALIGNMENT_RIGHT, 110.0, 16, Color(1, 1, 1, 0.7))


func _draw_indicators(f: Font) -> void:
	var rect := Rect2(Vector2.ZERO, size).grow(-40.0)
	var center := size * 0.5
	var last_few: bool = game.queue.is_empty() and game.enemies.size() <= 2
	for e in game.enemies:
		var danger: bool = e.state == Enemy.S.TELEGRAPH and (e.role == "ranged" or e.role == "charge" or e.role == "boss")
		var warn_spawn: bool = e.state == Enemy.S.SPAWN_WARNING and e.summoned
		if not (danger or last_few or warn_spawn):
			continue
		var sp := _w2s(e.position)
		if Rect2(Vector2.ZERO, size).has_point(sp):
			continue
		var dir := (sp - center).normalized()
		var tx := INF if absf(dir.x) < 0.001 else (size.x * 0.5 - 40.0) / absf(dir.x)
		var ty := INF if absf(dir.y) < 0.001 else (size.y * 0.5 - 40.0) / absf(dir.y)
		var p := center + dir * minf(tx, ty)
		var col := Color(1.0, 0.45, 0.12) if (danger or warn_spawn) else Color(0.62, 0.84, 0.93)
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([p + dir * 16.0, p - dir * 10.0 + side * 12.0, p - dir * 10.0 - side * 12.0]), col)
		draw_polyline(PackedVector2Array([p + dir * 16.0, p - dir * 10.0 + side * 12.0, p - dir * 10.0 - side * 12.0, p + dir * 16.0]), Color(0, 0, 0, 0.8), 2.0)
