extends SceneTree
## Отчёт о графике: что из manifest реально есть в проекте, что заменено заглушкой.
## godot --headless --path . --script res://tools/art_report.gd > docs/ART_STATUS.md

func _init() -> void:
	var m = JSON.parse_string(FileAccess.get_file_as_string("res://assets/asset_manifest_v1.json"))
	var overrides := {}
	if FileAccess.file_exists("res://assets/art_status.json"):
		overrides = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art_status.json"))
	var present := 0
	var rows: Array = []
	for a in m.assets:
		var path: String = a.target_path
		var exists := FileAccess.file_exists(path) or FileAccess.file_exists(path + ".import")
		var st := "placeholder (файла нет, процедурная заглушка)"
		if exists:
			present += 1
			st = String(overrides.get(a.id, "source_received"))
		rows.append("| `%s` | %s | `%s` | %s | %s |" % [a.id, a.kind, path.replace("res://", ""), "%dx%d" % [int(a.canvas_px[0]), int(a.canvas_px[1])], st])
	print("# Статус графики (генерируется tools/art_report.gd)\n")
	print("Записей в manifest: %d. Файлы найдены: %d. Остальные заменяются процедурными заглушками того же логического размера (AssetRegistry).\n" % [m.assets.size(), present])
	print("Статусы интеграции: planned → source_received → prepared → integrated → verified. Здесь реально используются только `placeholder` и `source_received`; повышение статуса — ручная проверка размера, прозрачности, pivot и ракурсов (assets/art_status.json).\n")
	print("| ID | Вид | Ожидаемый путь | Холст, px | Статус |")
	print("|---|---|---|---|---|")
	for r in rows:
		print(r)
	quit()
