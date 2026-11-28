class_name Corpse
extends Node2D
## Труп: анимация смерти (4 кадра, 8 кадр/с), затем лежащий спрайт corpse.* со смещением из метаданных.
## Лежит CORPSE_LIFE секунд, плавно исчезает; число трупов на арене ограничено в Game.

const DEATH_FPS := 8.0
const CORPSE_LIFE := 7.0
const FADE := 1.5

var game
var visual_id := ""
var corpse_id := ""
var t := 0.0
var sprite: Sprite2D
var _phase := 0
var _flip := false


func setup(g, enemy) -> void:
	game = g
	position = enemy.position
	visual_id = str(enemy.def.visual_id)
	var short := visual_id.get_slice(".", 1)
	corpse_id = ("corpse.boss." + short) if visual_id.begins_with("boss.") else ("corpse." + short)
	_flip = enemy._frame_dir == "W" or enemy.face.x < -0.2
	z_index = -1                                  # под живыми актёрами, над полом
	sprite = Sprite2D.new()
	sprite.centered = false
	add_child(sprite)
	_show_death_frame(0)


func _show_death_frame(i: int) -> void:
	var fr := AssetRegistry.strip_frame(visual_id + ".death", i)
	if fr.is_empty():
		_phase = 2                                 # нет анимации смерти — сразу труп/исчезновение
		return
	_apply(fr.texture, fr.region, AssetRegistry.get_pivot(visual_id + ".death"), AssetRegistry.get_scale(visual_id + ".death"))


func _apply(tex: Texture2D, region: Rect2, pivot: Vector2, sc: float) -> void:
	sprite.texture = tex
	sprite.region_enabled = region.size != tex.get_size()
	sprite.region_rect = region
	sprite.offset = -pivot
	sprite.scale = Vector2(sc * (-1.0 if _flip else 1.0), sc)


func tick(dt: float) -> bool:
	t += dt
	if _phase == 0:
		var idx := int(t * DEATH_FPS)
		if idx <= 3:
			_show_death_frame(idx)
		else:
			_phase = 1
			if AssetRegistry.file_exists(corpse_id):
				var tex := AssetRegistry.get_texture(corpse_id)
				position += AssetRegistry.corpse_offset(corpse_id)     # corpse_position = actor_position + spawn_offset (метаданные)
				_apply(tex, Rect2(Vector2.ZERO, tex.get_size()), AssetRegistry.get_pivot(corpse_id), AssetRegistry.get_scale(corpse_id))
	var left := CORPSE_LIFE - t
	sprite.modulate.a = clampf(left / FADE, 0.0, 1.0)
	return left > 0.0
