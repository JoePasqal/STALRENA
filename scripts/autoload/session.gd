extends Node
## Текущий забег, переходы между сценами, локальный диагностический лог.

signal run_changed

var run: RunState = null
var debug_enabled := false           # скрытые debug-команды (в релизе выключены)
var load_notice := ""                # сообщение о восстановлении из backup и т.п.
var _diag_once := {}
const LOG_PATH := "user://diag.log"
const LOG_MAX_BYTES := 200000


func _ready() -> void:
	GameData.reload()
	var errs := GameData.validate()
	for e in errs:
		push_error("balance: " + str(e))
	debug_enabled = OS.has_feature("debug") and not OS.has_feature("release")


func new_run(seed_value: int = -1) -> void:
	run = RunState.new_run(seed_value)
	SaveService.save_run(run)
	run_changed.emit()


func continue_run() -> Dictionary:
	var res := SaveService.load_run()
	if res.run != null and not res.run.over:
		run = res.run
		if res.status == "backup":
			load_notice = "Основное сохранение повреждено — восстановлена резервная копия."
		run_changed.emit()
	return res


func save() -> bool:
	if run == null:
		return false
	var ok := SaveService.save_run(run)
	if not ok:
		diag("save-failed", SaveService.last_error)
	return ok


## Диагностика: каждое сообщение пишется один раз за запуск; лог ротируется и локален.
func diag(key: String, text: String) -> void:
	if _diag_once.has(key):
		return
	_diag_once[key] = true
	push_warning("[diag] %s: %s" % [key, text])
	_rotate_log()
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(LOG_PATH) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line("%s %s %s" % [Time.get_datetime_string_from_system(), key, text])


func _rotate_log() -> void:
	if FileAccess.file_exists(LOG_PATH):
		var f := FileAccess.open(LOG_PATH, FileAccess.READ)
		if f and f.get_length() > LOG_MAX_BYTES:
			f.close()
			DirAccess.copy_absolute(LOG_PATH, LOG_PATH + ".1")
			DirAccess.remove_absolute(LOG_PATH)


func go_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func go_game() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/game.tscn")


## Локальный баланс-лог (длительность волны, DPS, попадания, закупки, источник смерти).
## Только на устройстве, без персональных данных, с ротацией по размеру.
const BALANCE_LOG := "user://balance_log.jsonl"
const BALANCE_LOG_MAX := 300000


func balance_log(entry: Dictionary) -> void:
	if FileAccess.file_exists(BALANCE_LOG):
		var f0 := FileAccess.open(BALANCE_LOG, FileAccess.READ)
		if f0 and f0.get_length() > BALANCE_LOG_MAX:
			f0.close()
			DirAccess.copy_absolute(BALANCE_LOG, BALANCE_LOG + ".1")
			DirAccess.remove_absolute(BALANCE_LOG)
	var f := FileAccess.open(BALANCE_LOG, FileAccess.READ_WRITE if FileAccess.file_exists(BALANCE_LOG) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(JSON.stringify(entry))
