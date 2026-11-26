extends Node2D
## Заглушка: игровая сцена появляется на следующем шаге этапа A.
func _ready() -> void:
	var l := Label.new()
	l.text = "Игровая сцена в разработке (этап A)"
	add_child(l)
