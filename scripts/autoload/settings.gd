extends Node
## Локальные настройки (отдельный файл, не затрагивается забегом).

const PATH := "user://settings.json"
const QUALITY := ["low", "medium", "high"]

var data := {
	"music_volume": 0.6,
	"sfx_volume": 0.8,
	"hints": true,
	"quality": "high",           # low = меньше эффектов, 30 FPS-режим допустим
	"autoaim": false,            # по умолчанию ручной прицел: правый стик/мышь целится и стреляет
	"settings_ver": 2,
	"touch_ui": "auto",          # auto | on | off
	"screen_shake": false,
	"show_fps": false,
	"fps_cap": 60,
	"tutorial_shop_done": false,   # обучение: экраны магазина показаны
	"tutorial_done": false,        # обучение: подсказки первой волны пройдены
}


func _ready() -> void:
	load_settings()
	_ensure_input_actions()
	apply()


func get_value(key: String):
	return data.get(key)


func set_value(key: String, value) -> void:
	data[key] = value
	apply()
	save_settings()


func load_settings() -> void:
	if FileAccess.file_exists(PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			for k in parsed:
				if data.has(k):
					data[k] = parsed[k]
		if int(parsed.get("settings_ver", 1)) < 2:
			data.autoaim = false                 # раньше по умолчанию была автострельба — переводим на ручную
			data.settings_ver = 2


func save_settings() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


func apply() -> void:
	Engine.max_fps = int(data.fps_cap)
	if has_node("/root/Sfx"):
		get_node("/root/Sfx").apply_volumes()


## Сенсорный интерфейс: авто (есть сенсорный экран) / вкл / выкл.
func touch_ui_enabled() -> bool:
	match str(data.touch_ui):
		"on": return true
		"off": return false
	return DisplayServer.is_touchscreen_available()


func low_quality() -> bool:
	return str(data.quality) == "low"


func _ensure_input_actions() -> void:
	var map := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"reload": [KEY_R],
		"medkit": [KEY_F],
		"pause": [KEY_ESCAPE],
	}
	for action in map:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			for k in map[action]:
				var ev := InputEventKey.new()
				ev.physical_keycode = k
				InputMap.action_add_event(action, ev)
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fire", mb)
