extends Node
## Подмена графики через AssetRegistry: если файл по пути из manifest есть — он используется,
## если нет — placeholder; баланс и коллизии от PNG не зависят. Запуск после --import.

func _ready() -> void:
	var present := AssetRegistry.file_exists("weapon.pistol")
	var tex := AssetRegistry.get_texture("weapon.pistol")
	var missing_tex := AssetRegistry.get_texture("fx.muzzle")
	print("ART weapon.pistol file=%s status=%s size=%s | fx.muzzle status=%s size=%s" % [present, AssetRegistry.status("weapon.pistol"), tex.get_size(), AssetRegistry.status("fx.muzzle"), missing_tex.get_size()])
	var run := RunState.new_run(1)
	var s1 := StatCalc.weapon_stats(run, "pistol")
	print("ART balance unchanged: damage=%s range=%s pivot=%s scale=%s" % [s1.damage, s1.range, AssetRegistry.get_pivot("weapon.pistol"), AssetRegistry.get_scale("weapon.pistol")])
	var ok := (present and AssetRegistry.status("weapon.pistol") != "placeholder" and AssetRegistry.status("fx.muzzle") == "placeholder" and absf(s1.damage - 13.0) < 0.001)
	print("ART RESULT ", "OK" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
