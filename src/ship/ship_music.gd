class_name ShipMusic
extends Node
## Música de la nave (ADR-022). Reproduce archivos de audio del jugador por la megafonía de la nave:
## - Biblioteca: MP3/OGG de la carpeta Música del sistema y de `user://music` (también subcarpetas).
## - Enlaces DIRECTOS a archivos .mp3/.ogg (se descargan con HTTPRequest a `user://music/descargas`).
## - Spotify y YouTube NO son posibles: Spotify cifra su audio (DRM, sólo suena en sus apps) y descargar
##   el audio de YouTube va contra sus condiciones de uso. Se informa al jugador en lugar de intentarlo.
## Escucha según dónde esté el oyente (el astronauta local):
## - En el puente: sonido limpio, a volumen normal.
## - En el resto de la nave: "por los altavoces" — paso banda (graves y agudos recortados), algo de
##   saturación y reverberación metálica, un poco más bajo. La transición es suave al cruzar la puerta.
## - Fuera de la nave: silencio (no hay aire), salvo que se elija oírla bajito por la radio del traje.
## Ajustes (ronda 14, GameSettings.ship_*): volumen, nivel de los altavoces respecto al puente, intensidad del efecto
## de altavoz, graves y agudos (ecualizador), orden (lista, aleatorio, repetir) y bajar la música mientras alguien
## habla (diálogos, voz de proximidad o radio).
## El estado (pista, reproduciendo) se publica en ShipState. En línea, MusicShare comparte la canción con los demás:
## `local_action` avisa de lo que hace el jugador local y `forward` desvía los controles al DJ cuando la canción que
## suena es de otro jugador (`remote`).

signal changed
signal status(text: String)
signal local_action(action: String, arg: float)   ## el jugador local ha usado los controles (o acabó una canción)

const BUS := "MusicaNave"
const EXTENSIONS := ["mp3", "ogg"]
const MAX_DOWNLOAD_BYTES := 60 * 1024 * 1024
const BLOCKED_HOSTS := ["spotify.com", "spotify.link", "youtube.com", "youtu.be", "music.youtube", "soundcloud.com"]

var ship: Node                         ## Ship
var listener: Node3D = null            ## astronauta local (lo fija el mundo)
var tracks: Array = []                 ## [{title, path}]
var current := -1
var volume_db := -6.0                  ## volumen del reproductor (GameSettings.ship_music_db)
var player: AudioStreamPlayer
var speaker_mix := 1.0                 ## 0 = limpio (puente), 1 = altavoces
var presence := 0.0                    ## 0 = fuera de la nave, 1 = dentro
var _http: HTTPRequest
var _download_title := ""
var _bus := -1
var _duck := 0.0                       ## 0..1 atenuación por voces
var remote := false                    ## suena una canción de otro jugador (MusicShare)
var remote_dj := ""                    ## nombre de ese jugador
var forward := Callable()              ## MusicShare: (acción, valor) para pedir al DJ pausar, avanzar…
var _remote_path := ""
var _remote_title := ""


func _ready() -> void:
	_bus = _ensure_bus()
	volume_db = GameSettings.ship_music_db
	player = AudioStreamPlayer.new()
	player.bus = BUS
	player.volume_db = -80.0
	add_child(player)
	player.finished.connect(_on_finished)
	_http = HTTPRequest.new()
	_http.body_size_limit = MAX_DOWNLOAD_BYTES
	_http.timeout = 90.0
	_http.request_completed.connect(_on_download)
	add_child(_http)
	DirAccess.make_dir_recursive_absolute("user://music/descargas")
	rescan()


## Bus con efectos de "altavoz": paso alto, paso bajo, saturación y reverberación (índices 0..3) y el ecualizador de
## graves y agudos del jugador (índice 4).
static func _ensure_bus() -> int:
	var idx := AudioServer.get_bus_index(BUS)
	if idx >= 0:
		return idx
	AudioServer.add_bus()
	idx = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, BUS)
	AudioServer.set_bus_send(idx, "Master")
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = 20.0
	AudioServer.add_bus_effect(idx, hp)
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(idx, lp)
	var dist := AudioEffectDistortion.new()
	dist.mode = AudioEffectDistortion.MODE_OVERDRIVE
	dist.drive = 0.0
	dist.post_gain = 0.0
	AudioServer.add_bus_effect(idx, dist)
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.45
	rev.damping = 0.35
	rev.wet = 0.0
	rev.dry = 1.0
	AudioServer.add_bus_effect(idx, rev)
	AudioServer.add_bus_effect(idx, AudioEffectEQ6.new())
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(GameSettings.ship_music_volume, 0.0001)))
	return idx


# --- Biblioteca -------------------------------------------------------------------------------

func music_dirs() -> Array:
	var dirs := [ProjectSettings.globalize_path("user://music")]
	var sys := OS.get_system_dir(OS.SYSTEM_DIR_MUSIC)
	if sys != "":
		dirs.append(sys)
	return dirs


func rescan() -> void:
	var keep := {}
	for t in tracks:
		keep[t["path"]] = true
	var found := []
	for d in music_dirs():
		_scan(d, found, 0)
	found.sort_custom(func(a, b): return a["title"].naturalnocasecmp_to(b["title"]) < 0)
	var playing_path: String = tracks[current]["path"] if current >= 0 and current < tracks.size() else ""
	tracks = found
	current = -1
	for i in tracks.size():
		if tracks[i]["path"] == playing_path:
			current = i
	changed.emit()


func _scan(dir: String, out: Array, depth: int) -> void:
	var da := DirAccess.open(dir)
	if da == null or depth > 3:
		return
	for f in da.get_files():
		if f.get_extension().to_lower() in EXTENSIONS:
			out.append({"title": f.get_basename(), "path": dir.path_join(f)})
	for sub in da.get_directories():
		if not sub.begins_with("."):
			_scan(dir.path_join(sub), out, depth + 1)


static func load_stream(path: String) -> AudioStream:
	var ext := path.get_extension().to_lower()
	if ext == "mp3":
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.is_empty():
			return null
		var mp3 := AudioStreamMP3.new()
		mp3.data = bytes
		return mp3
	if ext == "ogg":
		return AudioStreamOggVorbis.load_from_file(path)
	return null


# --- Controles --------------------------------------------------------------------------------

## Controles sobre una canción de otro jugador: se piden a su DJ (true = desviado).
func _fwd(action: String, arg: float = 0.0) -> bool:
	if remote and forward.is_valid():
		forward.call(action, arg)
		return true
	return false


func play_index(i: int) -> void:
	if i < 0 or i >= tracks.size():
		return
	var stream := load_stream(tracks[i]["path"])
	if stream == null:
		status.emit("No se pudo leer «%s»" % tracks[i]["title"])
		return
	current = i
	remote = false
	remote_dj = ""
	player.stream = stream
	player.play()
	_publish()
	status.emit("Reproduciendo «%s»" % tracks[i]["title"])
	local_action.emit("play", 0.0)


## Canción compartida por otro jugador (ya en disco), desde `from_s` segundos.
func play_file(path: String, p_title: String, from_s: float) -> void:
	var stream := load_stream(path)
	if stream == null:
		return
	_remote_path = path
	_remote_title = p_title
	current = -1
	player.stream = stream
	player.stream_paused = false
	player.play(clampf(from_s, 0.0, maxf(stream.get_length() - 0.5, 0.0)))
	_publish()


## Ruta del archivo que suena (propio o compartido) o "".
func current_path() -> String:
	if remote:
		return _remote_path if player.stream != null else ""
	return tracks[current]["path"] if current >= 0 and current < tracks.size() and player.stream != null else ""


## Para sin avisar a nadie (lo usa MusicShare al seguir al DJ).
func stop_local() -> void:
	player.stop()
	player.stream_paused = false
	remote = false
	remote_dj = ""
	_publish()


func toggle_pause() -> void:
	if _fwd("toggle"):
		return
	_toggle_pause()
	local_action.emit("toggle", 0.0)


func _toggle_pause() -> void:
	if player.stream == null:
		play_index(maxi(current, 0))
		return
	if player.playing:
		player.stream_paused = true
	elif player.stream_paused:
		player.stream_paused = false
	else:
		player.play()
	_publish()


func stop() -> void:
	if _fwd("stop"):
		return
	player.stop()
	player.stream_paused = false
	_publish()
	local_action.emit("stop", 0.0)


func next() -> void:
	if _fwd("next"):
		return
	if tracks.is_empty():
		return
	if GameSettings.ship_music_order == "aleatorio" and tracks.size() > 1:
		var i := randi() % (tracks.size() - 1)
		play_index(i if i < current else i + 1)
		return
	play_index((current + 1) % tracks.size())


## Fin de una canción: la misma otra vez («repetir») o la siguiente según el orden elegido.
func _on_finished() -> void:
	if remote:
		return      # la siguiente la decide el DJ
	if GameSettings.ship_music_order == "repetir" and current >= 0:
		play_index(current)
	else:
		next()


## Guarda el volumen del reproductor (panel M).
func set_volume(db: float) -> void:
	volume_db = db
	GameSettings.ship_music_db = db


func previous() -> void:
	if _fwd("previous"):
		return
	if tracks.is_empty():
		return
	if player.get_playback_position() > 3.0:
		player.seek(0.0)
		return
	play_index((current - 1 + tracks.size()) % tracks.size())


func seek_fraction(f: float) -> void:
	if _fwd("seek", f):
		return
	if player.stream != null and player.playing:
		player.seek(clampf(f, 0.0, 1.0) * player.stream.get_length())
		local_action.emit("seek", f)


func is_playing() -> bool:
	return player.playing and not player.stream_paused


func title() -> String:
	if remote:
		return _remote_title
	return tracks[current]["title"] if current >= 0 and current < tracks.size() else ""


func position() -> float:
	return player.get_playback_position() if player.stream != null else 0.0


func length() -> float:
	return player.stream.get_length() if player.stream != null else 0.0


func _publish() -> void:
	if ship != null:
		ship.state.music_title = title()
		ship.state.music_playing = is_playing()
	changed.emit()


# --- Enlaces ----------------------------------------------------------------------------------

## Comprueba un enlace. Devuelve "" si se puede intentar, o el motivo por el que no.
static func url_problem(url: String) -> String:
	var u := url.strip_edges().to_lower()
	if not (u.begins_with("http://") or u.begins_with("https://")):
		return "El enlace debe empezar por http:// o https://"
	for h in BLOCKED_HOSTS:
		if u.contains(h):
			return "Spotify, YouTube y SoundCloud no permiten reproducir su audio fuera de sus aplicaciones " \
				+ "(cifrado DRM / condiciones de uso). Usa archivos MP3/OGG propios o un enlace directo a un .mp3/.ogg."
	return ""


func play_url(url: String) -> void:
	var problem := url_problem(url)
	if problem != "":
		status.emit(problem)
		return
	var clean := url.strip_edges()
	var fname := clean.get_file().split("?")[0].uri_decode()
	var ext := fname.get_extension().to_lower()
	if not ext in EXTENSIONS:
		ext = "mp3"
		fname = "enlace_%d.mp3" % (abs(clean.hash()) % 100000)
	_download_title = fname.get_basename()
	var target := ProjectSettings.globalize_path("user://music/descargas").path_join(fname.get_basename() + "." + ext)
	_http.cancel_request()
	_http.download_file = target
	var err := _http.request(clean)
	if err != OK:
		status.emit("No se pudo iniciar la descarga (error %d)" % err)
		return
	status.emit("Descargando «%s»…" % _download_title)


func _on_download(result: int, code: int, headers: PackedStringArray, _body: PackedByteArray) -> void:
	var path := _http.download_file
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		DirAccess.remove_absolute(path)
		status.emit("La descarga falló (resultado %d, HTTP %d)" % [result, code])
		return
	var ctype := ""
	for h in headers:
		if h.to_lower().begins_with("content-type:"):
			ctype = h.substr(13).strip_edges().to_lower()
	if ctype != "" and not (ctype.begins_with("audio/") or ctype.contains("octet-stream") or ctype.contains("ogg")):
		DirAccess.remove_absolute(path)
		status.emit("El enlace no es un archivo de audio (%s). Hace falta un enlace directo a un .mp3/.ogg." % ctype)
		return
	rescan()
	for i in tracks.size():
		if tracks[i]["path"] == path:
			play_index(i)
			return
	status.emit("Descargado, pero no se pudo añadir a la lista")


# --- Escucha según la posición ------------------------------------------------------------------

func _process(delta: float) -> void:
	var inside := 0.0
	var clean := 0.0
	var radio := false
	if listener != null and is_instance_valid(listener) and ship != null:
		if listener.get("aboard") == ship:
			inside = 1.0
			var local: Vector3 = ship.to_local(listener.global_position + listener.global_transform.basis.y * 0.9)
			if ShipLayout.room_at(local) == "cabina":
				clean = 1.0
		elif GameSettings.ship_music_outside:
			inside = 1.0     # fuera: por la radio del traje, bajito y con sonido de radio
			radio = true
	presence = move_toward(presence, inside, delta * 1.5)
	speaker_mix = move_toward(speaker_mix, 1.0 - clean, delta * 2.0)
	# Bajar la música mientras alguien habla (diálogos de la historia o voz de los compañeros).
	var talking := GameSettings.ship_music_duck and (GameAudio.is_ducked() or Voice.anyone_speaking())
	_duck = move_toward(_duck, 1.0 if talking else 0.0, delta * (4.0 if talking else 1.2))
	var s := speaker_mix
	var fx := 1.0 if radio else s * GameSettings.ship_speaker_fx
	var level := volume_db + (-14.0 if radio else GameSettings.ship_speaker_db * s) - 12.0 * _duck
	player.volume_db = lerpf(-80.0, level, presence) if presence > 0.001 else -80.0
	if _bus >= 0:
		(AudioServer.get_bus_effect(_bus, 0) as AudioEffectHighPassFilter).cutoff_hz = lerpf(20.0, 500.0 if radio else 380.0, fx)
		(AudioServer.get_bus_effect(_bus, 1) as AudioEffectLowPassFilter).cutoff_hz = lerpf(20000.0, 2800.0 if radio else 3600.0, fx)
		var dist := AudioServer.get_bus_effect(_bus, 2) as AudioEffectDistortion
		dist.drive = (0.35 if radio else 0.22) * fx
		(AudioServer.get_bus_effect(_bus, 3) as AudioEffectReverb).wet = 0.0 if radio else 0.22 * fx
		if AudioServer.get_bus_effect_count(_bus) > 4:
			var eq := AudioServer.get_bus_effect(_bus, 4) as AudioEffectEQ6
			eq.set_band_gain_db(0, GameSettings.ship_bass_db)
			eq.set_band_gain_db(1, GameSettings.ship_bass_db * 0.7)
			eq.set_band_gain_db(4, GameSettings.ship_treble_db * 0.7)
			eq.set_band_gain_db(5, GameSettings.ship_treble_db)
