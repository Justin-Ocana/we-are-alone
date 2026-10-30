class_name DialogueDirector
extends Node
## Diálogos del juego (ADR-043): una sola voz a la vez (cola), cada diálogo importante suena UNA vez (se recuerda en
## la partida guardada), los mensajes de error se pueden repetir (con pausa mínima y nunca encima de otra voz),
## subtítulos sincronizados (si la línea los tiene) y omisión con Espacio de las líneas que lo permiten.
## Las líneas están en data/dialogue/prologue.json; los audios que faltan se saltan sin error.

signal line_started(id: String, speaker: String, skippable: bool)
signal line_finished(id: String, skipped: bool)
signal subtitle_changed(text: String)

const DATA := "res://data/dialogue/prologue.json"
const ERROR_COOLDOWN_S := 6.0
const GAP_S := 0.35                 ## silencio entre dos líneas encadenadas

var heard := {}                     ## id → true (se guarda)
var lines := {}
var current := ""
var _queue: Array = []              ## ids pendientes
var _player: AudioStreamPlayer
var _subs: Array = []               ## [{start, end, text}] de la línea actual
var _sub_text := ""
var _last_error := {}               ## id → tiempo
var _gap := 0.0
var _t := 0.0
var _skipped := false
var simulate := false              ## pruebas: no suena nada y cada línea dura 0,3 s
var _sim_t := 0.0


func _ready() -> void:
	var f := FileAccess.open(DATA, FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			lines = d.get("lines", {})
	_player = AudioStreamPlayer.new()
	_player.bus = GameAudio.BUS_VOICE
	add_child(_player)
	_player.finished.connect(_on_finished)


## ¿Existe el audio de la línea? (16 y 24-32 aún no se han grabado.)
func has_audio(id: String) -> bool:
	return lines.has(id) and ResourceLoader.exists(str(lines[id].get("audio", "")))


func is_busy() -> bool:
	return current != "" or not _queue.is_empty() or _gap > 0.0


func is_playing(id: String) -> bool:
	return current == id


## Pide una línea. Las de historia y opcionales suenan una sola vez; las de error se repiten (con pausa) pero sólo si
## no está hablando nadie. Devuelve true si se ha encolado o va a sonar.
func say(id: String) -> bool:
	if not lines.has(id):
		return false
	var kind := str(lines[id].get("kind", "story"))
	if kind == "error":
		if is_busy() or _t - float(_last_error.get(id, -100.0)) < ERROR_COOLDOWN_S:
			return false
		_last_error[id] = _t
	elif heard.has(id) or id in _queue or current == id:
		return false
	if not has_audio(id):
		heard[id] = true     # falta el audio: se da por oída para no esperarla
		line_finished.emit(id, false)
		return false
	_queue.append(id)
	if current == "" and _gap <= 0.0:
		_next()
	return true


## Omite la línea actual (sólo si es omitible, salvo `force`).
func skip(force: bool = false) -> void:
	if current == "":
		return
	if not force and not bool(lines[current].get("skippable", false)):
		return
	_skipped = true
	_player.stop()
	_on_finished()


## Cliente en línea: el anfitrión dice qué suena (sin cola ni «una sola vez»; ADR-044).
func play_remote(id: String) -> void:
	if not has_audio(id):
		return
	_queue.clear()
	if current != "":
		_skipped = true
		_player.stop()
		_on_finished()
	_gap = 0.0
	_queue.append(id)
	_next()


func stop_all() -> void:
	_queue.clear()
	if current != "":
		_skipped = true
		_player.stop()
		_on_finished()


func _next() -> void:
	if _queue.is_empty():
		GameAudio.duck(false)
		return
	current = _queue.pop_front()
	var e: Dictionary = lines[current]
	_player.stream = load(str(e["audio"]))
	_subs = []
	var sp := str(e.get("subtitles", ""))
	if sp != "":
		var f := FileAccess.open(sp, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_subs = d.get("lines", [])
	elif str(e.get("text", "")) != "":
		_subs = [{"start": 0.0, "end": 1.0e9, "text": str(e["text"])}]
	_skipped = false
	GameAudio.duck(true, float(e.get("duck_music", 0.35)), float(e.get("duck_ambient", 0.35)))
	_player.volume_db = float(e.get("volume_db", 0.0))
	if simulate:
		_sim_t = 0.3
	else:
		_player.play()
	line_started.emit(current, str(e.get("speaker", "")), bool(e.get("skippable", false)))
	_set_sub("")


func _on_finished() -> void:
	if current == "":
		return
	var id := current
	var kind := str(lines[id].get("kind", "story"))
	if kind != "error":
		heard[id] = true
	current = ""
	_set_sub("")
	_gap = GAP_S   # antes de avisar: quien encadene otra línea respeta la pausa
	if _queue.is_empty():
		GameAudio.duck(false)
	line_finished.emit(id, _skipped)


func _process(delta: float) -> void:
	_t += delta
	if simulate and current != "":
		_sim_t -= delta
		if _sim_t <= 0.0:
			_on_finished()
	if _gap > 0.0:
		_gap -= delta
		if _gap <= 0.0 and current == "":
			_next()
	if current != "" and not _subs.is_empty() and GameSettings.subtitles:
		var pos := _player.get_playback_position()
		var text := ""
		for s in _subs:
			if pos >= float(s["start"]) and pos <= float(s["end"]) + 0.25:
				text = str(s["text"])
				break
		_set_sub(text)


func _set_sub(text: String) -> void:
	if text != _sub_text:
		_sub_text = text
		subtitle_changed.emit(text)


func _unhandled_input(event: InputEvent) -> void:
	if current == "" or not bool(lines[current].get("skippable", false)):
		return
	var space: bool = event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_SPACE
	var pad: bool = event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A
	if space or pad:
		get_viewport().set_input_as_handled()
		if Net.is_client():
			Net.rpc_id(1, "request", "skip", [])
		else:
			skip()


func capture() -> Dictionary:
	return {"heard": heard.keys()}


func apply(d: Dictionary) -> void:
	heard = {}
	for id in d.get("heard", []):
		heard[str(id)] = true
