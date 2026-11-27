class_name Medkit
extends RefCounted
## Аптечка: ровно 20% максимального ХП за 4 с (5%/с). Одна на раунд, без накопления.
## Максимум фиксируется при применении. Результат не зависит от FPS: выдача
## считается от накопленного времени, а не суммой дельт.

var stock: int = 1
var active: bool = false
var elapsed: float = 0.0
var duration: float = 4.0
var total: float = 0.0
var given: float = 0.0


## carry — запас из забега (покупки и неиспользованные). Раунд всегда начинается минимум с одной аптечки;
## сверх минимума накапливаются только те, что игрок купил и не потратил.
func reset_for_wave(carry: int = 0) -> void:
	stock = clampi(maxi(carry, int(GameData.B.medkit.minimum_stock_at_wave_start)), 0, int(GameData.B.medkit.max_stock))
	clear_effect()


func clear_effect() -> void:
	active = false
	elapsed = 0.0
	total = 0.0
	given = 0.0


func can_use(hp: float, max_hp: float) -> bool:
	return stock > 0 and not active and hp > 0.0 and hp < max_hp - 0.0001


func try_use(hp: float, max_hp: float, heal_mult: float = 1.0) -> bool:
	if not can_use(hp, max_hp):
		return false
	stock -= 1
	active = true
	elapsed = 0.0
	given = 0.0
	duration = float(GameData.B.medkit.duration_seconds)
	total = max_hp * float(GameData.B.medkit.heal_max_hp_fraction) * heal_mult      # дебафф «Слабая аптечка» умножает лечение
	return true


## Возвращает количество ХП к добавлению за этот шаг (ограничение максимумом — на вызывающем).
func tick(delta: float) -> float:
	if not active:
		return 0.0
	elapsed = minf(elapsed + delta, duration)
	var target := total * (elapsed / duration)
	var amount := target - given
	given = target
	if elapsed >= duration:
		active = false
	return maxf(amount, 0.0)


func progress() -> float:
	return clampf(elapsed / duration, 0.0, 1.0) if active else 0.0
