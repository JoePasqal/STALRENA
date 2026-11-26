extends Node
## Простые локальные сигналы (процедурные), отдельная громкость. Отсутствие
## звука не ломает сцены.

const RATE := 22050
var _cache := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func apply_volumes() -> void:
	pass


func _tone(freq: float, dur: float, kind: String) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(freq * 10)
	for i in n:
		var t := float(i) / RATE
		var env := pow(1.0 - float(i) / n, 2.0)
		var v := 0.0
		match kind:
			"noise": v = rng.randf_range(-1.0, 1.0)
			"square": v = 1.0 if fmod(t * freq, 1.0) < 0.5 else -1.0
			_: v = sin(TAU * freq * t)
		var s := int(clampf(v * env * 0.35, -1.0, 1.0) * 32767.0)
		bytes[i * 2] = s & 0xFF
		bytes[i * 2 + 1] = (s >> 8) & 0xFF
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = bytes
	return w


func play(id: String) -> void:
	if not _cache.has(id):
		match id:
			"shot": _cache[id] = _tone(520.0, 0.06, "square")
			"shot_heavy": _cache[id] = _tone(220.0, 0.12, "noise")
			"hit": _cache[id] = _tone(300.0, 0.05, "noise")
			"hurt": _cache[id] = _tone(120.0, 0.16, "square")
			"click": _cache[id] = _tone(700.0, 0.04, "sine")
			"buy": _cache[id] = _tone(880.0, 0.1, "sine")
			"deny": _cache[id] = _tone(160.0, 0.1, "square")
			"heal": _cache[id] = _tone(660.0, 0.2, "sine")
			"wave": _cache[id] = _tone(440.0, 0.25, "sine")
			_: _cache[id] = _tone(400.0, 0.05, "sine")
	var vol: float = float(Settings.data.sfx_volume)
	if vol <= 0.001 or _players.is_empty():
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _cache[id]
	p.volume_db = linear_to_db(vol)
	p.play()
