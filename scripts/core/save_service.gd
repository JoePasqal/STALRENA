class_name SaveService
extends RefCounted
## Один слот активного забега: атомарная запись (временный файл → замена) и
## одна резервная копия предыдущей валидной версии. Рекорды/настройки хранятся
## отдельно и не затрагиваются повреждением слота забега.

static var base_dir: String = "user://"
static var last_error: String = ""

const RUN_FILE := "run.json"
const BAK_SUFFIX := ".bak"
const TMP_SUFFIX := ".tmp"
const RECORDS_FILE := "records.json"


static func _p(name: String) -> String:
	return base_dir.path_join(name)


static func _wrap(payload: Dictionary) -> String:
	var inner := JSON.stringify(payload)
	return JSON.stringify({"format": RunState.FORMAT_VERSION, "hash": inner.md5_text(), "payload_json": inner})


## Возвращает {ok, data|null, error}
static func _read_wrapped(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "нет файла"}
	var txt := FileAccess.get_file_as_string(path)
	var w = JSON.parse_string(txt)
	if typeof(w) != TYPE_DICTIONARY or not w.has("payload_json") or not w.has("hash"):
		return {"ok": false, "error": "повреждён"}
	if str(w.payload_json).md5_text() != str(w.hash):
		return {"ok": false, "error": "контрольная сумма"}
	var d = JSON.parse_string(str(w.payload_json))
	if typeof(d) != TYPE_DICTIONARY:
		return {"ok": false, "error": "payload"}
	return {"ok": true, "data": d}


static func write_json_atomic(name: String, text: String, keep_backup: bool) -> bool:
	var path := _p(name)
	var tmp := path + TMP_SUFFIX
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "не удалось открыть временный файл (%d)" % FileAccess.get_open_error()
		return false
	f.store_string(text)
	f.flush()
	f.close()
	if FileAccess.get_file_as_string(tmp) != text:
		last_error = "проверка записи не прошла"
		DirAccess.remove_absolute(tmp)
		return false
	if keep_backup and FileAccess.file_exists(path):
		# предыдущая валидная копия становится резервной
		if _read_wrapped(path).ok:
			DirAccess.copy_absolute(path, path + BAK_SUFFIX)
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		last_error = "не удалось заменить файл (%d)" % err
		return false
	return true


static func save_run(run: RunState) -> bool:
	last_error = ""
	var ok := write_json_atomic(RUN_FILE, _wrap(run.to_dict()), true)
	if not ok:
		push_warning("SaveService: ошибка записи: " + last_error)
	return ok


## {status: "none"|"ok"|"backup"|"corrupt"|"incompatible", run: RunState|null}
static func load_run() -> Dictionary:
	var main := _read_wrapped(_p(RUN_FILE))
	if not main.ok and main.error == "нет файла" and not FileAccess.file_exists(_p(RUN_FILE) + BAK_SUFFIX):
		return {"status": "none", "run": null}
	if main.ok:
		var r := RunState.from_dict(main.data)
		if r != null:
			return {"status": "ok", "run": r}
	var bak := _read_wrapped(_p(RUN_FILE) + BAK_SUFFIX)
	if bak.ok:
		var r2 := RunState.from_dict(bak.data)
		if r2 != null:
			return {"status": "backup", "run": r2}
	if main.ok or bak.ok:
		return {"status": "incompatible", "run": null}
	return {"status": "corrupt", "run": null}


static func has_active_run() -> bool:
	var s := load_run()
	return s.run != null and not s.run.over


static func delete_run() -> void:
	for suffix in ["", BAK_SUFFIX, TMP_SUFFIX]:
		var p: String = _p(RUN_FILE) + str(suffix)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


# ---- рекорды (отдельный файл) ------------------------------------------------
static func load_records() -> Dictionary:
	var d := {"best_wave": 0, "best_time": 0.0, "history": []}
	var path := _p(RECORDS_FILE)
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			d.best_wave = int(parsed.get("best_wave", 0))
			d.best_time = float(parsed.get("best_time", 0.0))
			d.history = parsed.get("history", [])
	return d


static func add_result(wave_reached: int, time_s: float, source: String) -> Dictionary:
	var rec := load_records()
	if wave_reached > int(rec.best_wave):
		rec.best_wave = wave_reached
		rec.best_time = time_s
	rec.history.push_front({"wave": wave_reached, "time": time_s, "by": source, "unix": int(Time.get_unix_time_from_system())})
	var n := int(GameData.B.save.recent_results_count)
	while rec.history.size() > n:
		rec.history.pop_back()
	write_json_atomic(RECORDS_FILE, JSON.stringify(rec), false)
	return rec
