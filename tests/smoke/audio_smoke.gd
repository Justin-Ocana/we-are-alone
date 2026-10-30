extends Node
## Prueba del audio (ronda 14), headless: pistas de la banda sonora (data/music.json) cargables y largas, cada
## contexto con su lista, rotación sin repetir la anterior, pausas entre pistas, y la megafonía de la nave (ecualizador,
## orden aleatorio sin repetir, volumen de los altavoces). Mide además el volumen (RMS) de cada pista para igualarlas
## con gain_db (informativo). No guarda ajustes. Uso: --audio-smoke.

var main: Node
var failures := 0
var checks := 0
var _cap: AudioEffectCapture
var _meter: AudioStreamPlayer
var _queue: Array = []
var _cur := {}
var _t := 0.0
var _sum := 0.0
var _n := 0
var _peak := 0.0
var _report: Array = []
var _win := 0                       ## tramo medido de la pista actual (20 %, 50 %, 75 %)


func check(cond: bool, what: String) -> void:
	checks += 1
	print("  %s  %s" % ["PASA " if cond else "FALLA", what])
	if not cond:
		failures += 1


func _ready() -> void:
	var ga := GameAudio
	check(ga.tracks.size() >= 12, "banda sonora: %d pistas en data/music.json" % ga.tracks.size())
	var short := []
	for t in ga.tracks:
		var s: AudioStream = load(str(t["file"]))
		if s == null or s.get_length() < 30.0:
			short.append(str(t["id"]))
	check(short.is_empty(), "todas las pistas cargan y duran más de 30 s %s" % str(short))
	for ctx in ["menu", "explore", "deep", "party"]:
		var n := 0
		for t in ga.tracks:
			if ctx in t["contexts"]:
				n += 1
		check(n >= 1, "contexto «%s»: %d pistas" % [ctx, n])
	# Rotación: 20 cambios en exploración sin repetir la anterior y usando varias pistas.
	ga.set_music("explore")
	var seen := {}
	var repeats := 0
	var prev := str(ga._current.get("id", ""))
	for i in 20:
		ga.next_track()
		var id := str(ga._current.get("id", ""))
		seen[id] = true
		if id == prev:
			repeats += 1
		prev = id
	check(repeats == 0 and seen.size() >= 5, "rotación: %d pistas distintas en 20 cambios, %d repeticiones seguidas" % [seen.size(), repeats])
	check(GameAudio.gap_for("continua") < 4.0 and GameAudio.gap_for("a_ratos") > 60.0, "pausas entre pistas según la frecuencia")
	ga.set_music("")
	# Megafonía de la nave.
	var sm := ShipMusic.new()
	add_child(sm)
	var bus := AudioServer.get_bus_index(ShipMusic.BUS)
	check(bus >= 0 and AudioServer.get_bus_effect(bus, 4) is AudioEffectEQ6, "megafonía: bus con ecualizador de graves y agudos")
	sm.tracks = [{"title": "a", "path": "res://assets/audio/music/srg774_airy.mp3"},
		{"title": "b", "path": "res://assets/audio/music/srg774_pulse.mp3"},
		{"title": "c", "path": "res://assets/audio/music/srg774_sector.mp3"}]
	var old_order := GameSettings.ship_music_order
	GameSettings.ship_music_order = "aleatorio"
	sm.play_index(0)
	var same := 0
	var used := {}
	for i in 30:
		var before := sm.current
		sm.next()
		used[sm.current] = true
		if sm.current == before:
			same += 1
	GameSettings.ship_music_order = "repetir"
	var rep_before := sm.current
	sm._on_finished()
	var rep_ok := sm.current == rep_before
	GameSettings.ship_music_order = old_order
	sm.stop()
	check(same == 0 and used.size() == 3, "megafonía: el orden aleatorio no repite la misma canción (%d usadas)" % used.size())
	check(rep_ok, "megafonía: «repetir canción» vuelve a la misma")
	sm.queue_free()
	# Medición de volumen: cada pista 6 s por un bus con captura (sin sonar: volumen del bus a -80 no afecta a la captura
	# porque el efecto va antes del atenuador).
	var mb := AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(mb, "Medidor")
	_cap = AudioEffectCapture.new()
	_cap.buffer_length = 1.0
	AudioServer.add_bus_effect(mb, _cap)
	AudioServer.set_bus_mute(mb, true)
	_meter = AudioStreamPlayer.new()
	_meter.bus = "Medidor"
	add_child(_meter)
	_queue = ga.tracks.duplicate()
	_next_meter()


func _next_meter() -> void:
	if _queue.is_empty():
		for r in _report:
			print("  volumen %-18s RMS %6.1f dBFS · con gain_db %6.1f · pico %5.1f · sugerida %+5.1f dB" % r)
		print("AUDIO-SMOKE RESULTADO: %d comprobaciones, %d fallidas" % [checks, failures])
		get_tree().quit(failures)
		return
	_cur = _queue.pop_front()
	_meter.stream = load(str(_cur["file"]))
	_win = 0
	_sum = 0.0
	_n = 0
	_peak = 0.0
	_start_window()


func _start_window() -> void:
	_meter.play(_meter.stream.get_length() * [0.2, 0.5, 0.75][_win])
	_t = 0.0
	_cap.clear_buffer()


func _process(delta: float) -> void:
	if _cur.is_empty():
		return
	_t += delta
	var f := _cap.get_frames_available()
	if f > 0:
		var buf := _cap.get_buffer(f)
		for v in buf:
			_sum += v.x * v.x + v.y * v.y
			_peak = maxf(_peak, maxf(absf(v.x), absf(v.y)))
		_n += buf.size() * 2
	if _t > 4.0:
		_win += 1
		if _win < 3:
			_start_window()
			return
		var rms := linear_to_db(sqrt(_sum / maxf(_n, 1.0))) if _n > 0 else -999.0
		# Ganancia sugerida: llevarla a -19 dBFS de RMS sin que el pico pase de -1 dBFS tras el -9 dB de la banda sonora.
		var pk := linear_to_db(maxf(_peak, 1e-6))
		var sug := minf(-19.0 - rms, -1.0 - (pk + GameAudio.MUSIC_DB))
		_report.append([str(_cur["id"]), rms, rms + float(_cur.get("gain_db", 0.0)), pk, sug])
		_cur = {}
		_next_meter()
