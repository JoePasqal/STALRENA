extends Node
## Звук: процедурный синтез (шум через фильтр + огибающая + «удар»), без внешних файлов и сервисов.
## Если есть файл res://assets/audio/<id>.ogg|.wav|.mp3 — он используется вместо синтеза.
## Громкость эффектов и музыки — из настроек. Отсутствие звука не ломает сцены.

const RATE := 22050
const MUSIC_RATE := 11025
const POOL := 14

var _cache := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_play := {}
var _music_player: AudioStreamPlayer
var _music_id := ""
var _music_cache := {}
var _rng := RandomNumberGenerator.new()

## Минимальный интервал между одинаковыми звуками (защита от «каши» при автоогне).
const THROTTLE := {"hit": 0.045, "hit_crit": 0.05, "flame": 0.11, "tele": 0.12, "enemy_die": 0.05, "shot_smg": 0.0, "shot_lmg": 0.0}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 4242
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_music_player = AudioStreamPlayer.new()
	add_child(_music_player)
	apply_volumes()


func apply_volumes() -> void:
	if _music_player == null:
		return
	var v: float = float(Settings.data.music_volume)
	_music_player.volume_db = linear_to_db(maxf(v * 0.55, 0.0001))
	if v <= 0.001 and _music_player.playing:
		_music_player.stream_paused = true
	elif _music_player.stream != null:
		_music_player.stream_paused = false
		if not _music_player.playing:
			_music_player.play()


# ---- синтез ---------------------------------------------------------------------
## layers: Array of {k: "noise"|"sine"|"square"|"tri", f0, f1, dur, vol, cutoff0, cutoff1, delay, decay}
func _render(layers: Array, rate: int = RATE) -> AudioStreamWAV:
	var total := 0.0
	for l in layers:
		total = maxf(total, float(l.get("delay", 0.0)) + float(l.dur))
	var n := int(rate * total) + 1
	var buf := PackedFloat32Array()
	buf.resize(n)
	for l in layers:
		var dur: float = l.dur
		var delay: float = l.get("delay", 0.0)
		var vol: float = l.get("vol", 0.5)
		var decay: float = l.get("decay", 4.0)
		var f0: float = l.get("f0", 440.0)
		var f1: float = l.get("f1", f0)
		var c0: float = l.get("cutoff0", 8000.0)
		var c1: float = l.get("cutoff1", c0)
		var kind: String = l.k
		var start := int(delay * rate)
		var cnt := int(dur * rate)
		var phase := 0.0
		var lp := 0.0
		for i in cnt:
			var t := float(i) / cnt
			var env := exp(-decay * t) * (1.0 - t) * minf(1.0, float(i) / 40.0)       # короткая атака без щелчка
			var f := lerpf(f0, f1, t)
			phase += f / rate
			var v := 0.0
			match kind:
				"noise":
					var x := _rng.randf_range(-1.0, 1.0)
					var a := clampf(TAU * lerpf(c0, c1, t) / rate, 0.01, 0.95)    # однополюсный фильтр
					lp += a * (x - lp)
					v = lp * 2.2
				"square": v = 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
				"tri": v = absf(fmod(phase, 1.0) * 4.0 - 2.0) - 1.0
				_: v = sin(TAU * phase)
			var idx := start + i
			if idx < n:
				buf[idx] += v * env * vol
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var s := int(clampf(buf[i], -1.0, 1.0) * 32000.0)
		bytes[i * 2] = s & 0xFF
		bytes[i * 2 + 1] = (s >> 8) & 0xFF
	w.data = bytes
	return w


func _noise(dur: float, c0: float, c1: float, vol: float, decay: float = 5.0, delay: float = 0.0) -> Dictionary:
	return {"k": "noise", "dur": dur, "cutoff0": c0, "cutoff1": c1, "vol": vol, "decay": decay, "delay": delay}


func _tone(kind: String, f0: float, f1: float, dur: float, vol: float, decay: float = 4.0, delay: float = 0.0) -> Dictionary:
	return {"k": kind, "f0": f0, "f1": f1, "dur": dur, "vol": vol, "decay": decay, "delay": delay}


func _make(id: String) -> AudioStreamWAV:
	match id:
		"shot_pistol": return _render([_noise(0.11, 6000, 900, 0.8, 6.0), _tone("sine", 220, 70, 0.08, 0.7, 7.0)])
		"shot_smg": return _render([_noise(0.06, 7000, 1800, 0.6, 7.0), _tone("sine", 260, 110, 0.05, 0.4, 8.0)])
		"shot_carbine": return _render([_noise(0.10, 5200, 800, 0.8, 6.0), _tone("sine", 180, 60, 0.09, 0.7, 6.0)])
		"shot_shotgun": return _render([_noise(0.26, 3600, 400, 1.0, 4.5), _tone("sine", 120, 38, 0.2, 0.9, 5.0), _noise(0.12, 7000, 2500, 0.5, 8.0)])
		"shot_lmg": return _render([_noise(0.08, 3000, 700, 0.8, 6.0), _tone("sine", 140, 55, 0.08, 0.8, 6.0)])
		"shot_marksman": return _render([_noise(0.12, 9000, 1500, 0.9, 7.0), _tone("sine", 200, 50, 0.14, 0.7, 5.0), _noise(0.45, 1800, 300, 0.25, 3.5, 0.05)])
		"flame": return _render([_noise(0.14, 2500, 1200, 0.45, 3.0), _tone("sine", 70, 60, 0.12, 0.3, 3.0)])
		"hit": return _render([_noise(0.04, 5000, 1500, 0.55, 8.0)])
		"hit_crit": return _render([_noise(0.07, 8000, 2500, 0.7, 6.0), _tone("sine", 900, 500, 0.06, 0.4, 6.0)])
		"hurt": return _render([_noise(0.16, 1800, 300, 0.7, 4.0), _tone("sine", 160, 60, 0.18, 0.8, 4.0)])
		"enemy_die": return _render([_noise(0.22, 2200, 250, 0.6, 3.5), _tone("sine", 220, 60, 0.22, 0.5, 3.5)])
		"tele": return _render([_tone("square", 520, 700, 0.09, 0.22, 3.0), _tone("square", 700, 900, 0.09, 0.22, 3.0, 0.1)])
		"boss_tele": return _render([_tone("sine", 90, 55, 0.5, 0.9, 2.0), _noise(0.5, 900, 200, 0.5, 2.5)])
		"boss_roar": return _render([_tone("sine", 70, 38, 0.9, 0.9, 1.6), _noise(0.9, 1400, 180, 0.55, 2.0), _tone("tri", 110, 50, 0.9, 0.35, 2.0)])
		"explosion": return _render([_noise(0.6, 2600, 150, 1.0, 3.0), _tone("sine", 70, 30, 0.55, 0.95, 3.0)])
		"reload": return _render([_noise(0.03, 6000, 4000, 0.7, 6.0), _noise(0.04, 5000, 3000, 0.7, 6.0, 0.14), _tone("sine", 1400, 900, 0.03, 0.25, 6.0, 0.14)])
		"reload_done": return _render([_noise(0.05, 4500, 2500, 0.8, 5.0), _noise(0.04, 6000, 3500, 0.7, 6.0, 0.09), _tone("sine", 800, 500, 0.05, 0.25, 6.0, 0.09)])
		"empty": return _render([_noise(0.025, 7000, 5000, 0.55, 6.0)])
		"medkit": return _render([_tone("sine", 523, 523, 0.18, 0.45, 3.0), _tone("sine", 659, 659, 0.18, 0.45, 3.0, 0.11), _tone("sine", 784, 784, 0.3, 0.45, 3.0, 0.22)])
		"buy": return _render([_tone("sine", 1318, 1318, 0.22, 0.45, 4.0), _tone("sine", 1976, 1976, 0.3, 0.35, 4.5, 0.07)])
		"deny": return _render([_tone("square", 150, 110, 0.14, 0.35, 3.0), _tone("square", 120, 90, 0.14, 0.35, 3.0, 0.1)])
		"refresh": return _render([_noise(0.26, 1200, 7000, 0.4, 2.5), _tone("sine", 400, 900, 0.22, 0.2, 3.0)])
		"lock": return _render([_noise(0.03, 4000, 2000, 0.6, 7.0), _tone("sine", 600, 400, 0.05, 0.35, 6.0)])
		"levelup": return _render([_tone("tri", 392, 392, 0.14, 0.4, 3.0), _tone("tri", 494, 494, 0.14, 0.4, 3.0, 0.12), _tone("tri", 587, 587, 0.14, 0.4, 3.0, 0.24), _tone("tri", 784, 784, 0.4, 0.45, 2.5, 0.36)])
		"wave": return _render([_tone("tri", 110, 110, 0.5, 0.5, 2.0), _tone("tri", 165, 165, 0.5, 0.35, 2.0, 0.0)])
		"win": return _render([_tone("tri", 523, 523, 0.16, 0.4, 3.0), _tone("tri", 659, 659, 0.16, 0.4, 3.0, 0.14), _tone("tri", 784, 784, 0.16, 0.4, 3.0, 0.28), _tone("tri", 1047, 1047, 0.5, 0.45, 2.5, 0.42)])
		"lose": return _render([_tone("tri", 392, 392, 0.3, 0.45, 2.5), _tone("tri", 330, 330, 0.3, 0.45, 2.5, 0.28), _tone("tri", 262, 262, 0.3, 0.45, 2.5, 0.56), _tone("tri", 196, 196, 0.8, 0.5, 2.0, 0.84)])
		"click": return _render([_tone("sine", 900, 700, 0.04, 0.3, 6.0)])
		"tutorial": return _render([_tone("sine", 880, 880, 0.12, 0.3, 4.0), _tone("sine", 1175, 1175, 0.2, 0.3, 4.0, 0.09)])
		"step_ok": return _render([_tone("sine", 660, 660, 0.1, 0.35, 4.0), _tone("sine", 990, 990, 0.2, 0.35, 4.0, 0.08)])
	return _render([_tone("sine", 400, 400, 0.05, 0.3, 5.0)])


# ---- музыка (короткие зацикленные дорожки, синтез) --------------------------------
func _music(id: String) -> AudioStreamWAV:
	if _music_cache.has(id):
		return _music_cache[id]
	var bpm := 84.0 if id == "shop" else 118.0
	var beat := 60.0 / bpm
	var bars := 4
	var dur := beat * 4.0 * bars
	var n := int(MUSIC_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	# аккордовая прогрессия Am F C G (корни в Гц)
	var roots := [110.0, 87.31, 130.81, 98.0]
	var thirds := [1.189, 1.26, 1.26, 1.26]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for bar in bars:
		var r: float = roots[bar]
		var th: float = thirds[bar]
		var t0 := bar * beat * 4.0
		if id == "shop":
			for note in [1.0, th, 1.5, 2.0]:
				_add_tone(buf, t0, beat * 4.0, r * note * 2.0, 0.07, "sine", true)
			_add_tone(buf, t0, beat * 4.0, r, 0.16, "sine", true)
		else:
			for b in 8:
				var tb := t0 + b * beat * 0.5
				_add_tone(buf, tb, beat * 0.45, r * (1.0 if b % 4 != 3 else 1.5), 0.17, "tri", false)       # пульсирующий бас
				_add_noise_tick(buf, tb + beat * 0.25, 0.035, 0.05, rng)                                  # хэт
			_add_noise_tick(buf, t0, 0.12, 0.25, rng)                                                       # «бочка»-шум
			_add_tone(buf, t0, beat * 4.0, r * 4.0, 0.035, "sine", true)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MUSIC_RATE
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var s := int(clampf(buf[i], -1.0, 1.0) * 26000.0)
		bytes[i * 2] = s & 0xFF
		bytes[i * 2 + 1] = (s >> 8) & 0xFF
	w.data = bytes
	_music_cache[id] = w
	return w


func _add_tone(buf: PackedFloat32Array, t0: float, dur: float, f: float, vol: float, kind: String, pad: bool) -> void:
	var s0 := int(t0 * MUSIC_RATE)
	var cnt := int(dur * MUSIC_RATE)
	for i in cnt:
		var idx := s0 + i
		if idx >= buf.size():
			break
		var t := float(i) / cnt
		var env := 1.0
		if pad:
			env = minf(t / 0.25, 1.0) * minf((1.0 - t) / 0.25, 1.0)      # мягкие вход/выход, без щелчков
		else:
			env = exp(-3.5 * t) * minf(1.0, float(i) / 30.0)
		var ph := f * float(i) / MUSIC_RATE
		var v := sin(TAU * ph) if kind == "sine" else (absf(fmod(ph, 1.0) * 4.0 - 2.0) - 1.0)
		buf[idx] += v * env * vol


func _add_noise_tick(buf: PackedFloat32Array, t0: float, dur: float, vol: float, rng: RandomNumberGenerator) -> void:
	var s0 := int(t0 * MUSIC_RATE)
	var cnt := int(dur * MUSIC_RATE)
	var lp := 0.0
	for i in cnt:
		var idx := s0 + i
		if idx >= buf.size():
			break
		lp += 0.5 * (rng.randf_range(-1.0, 1.0) - lp)
		buf[idx] += lp * exp(-6.0 * float(i) / cnt) * vol


func music(id: String) -> void:
	if id == _music_id:
		return
	_music_id = id
	if id == "":
		_music_player.stop()
		return
	_music_player.stream = _load_override("music_" + id) if _load_override("music_" + id) != null else _music(id)
	_music_player.play()
	apply_volumes()


func _load_override(id: String) -> AudioStream:
	for ext in ["ogg", "wav", "mp3"]:
		var p := "res://assets/audio/%s.%s" % [id, ext]
		if ResourceLoader.exists(p):
			var s = load(p)
			if s is AudioStream:
				return s
	return null


func play(id: String, pitch: float = 1.0) -> void:
	var vol: float = float(Settings.data.sfx_volume)
	if vol <= 0.001 or _players.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	var gap: float = THROTTLE.get(id, 0.0)
	if gap > 0.0 and now - float(_last_play.get(id, -10.0)) < gap:
		return
	_last_play[id] = now
	if not _cache.has(id):
		var ov := _load_override(id)
		_cache[id] = ov if ov != null else _make(id)
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _cache[id]
	p.pitch_scale = pitch * _rng.randf_range(0.96, 1.04)
	p.volume_db = linear_to_db(vol)
	p.play()


## Заранее собрать звуки боя (чтобы не было задержки при первом выстреле).
func warmup() -> void:
	for id in ["shot_pistol", "shot_carbine", "hit", "hurt", "enemy_die", "tele", "reload", "reload_done", "medkit", "buy", "deny", "wave", "win", "lose", "click"]:
		if not _cache.has(id):
			_cache[id] = _make(id)
