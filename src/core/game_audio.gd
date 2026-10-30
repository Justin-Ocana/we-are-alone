extends Node
## Autoload `GameAudio` (ADR-038): efectos, interfaz y banda sonora.
## - Buses: Efectos, Ambiente, Música (más MusicaNave, la de la megafonía, que crea ShipMusic).
## - Interfaz: cualquier botón, desplegable, casilla, pestaña o deslizador del juego suena solo (se engancha a los
##   nodos nuevos del árbol), sin código en cada menú.
## - Banda sonora: listas de pistas por contexto (menú, exploración, atmósferas densas, fiesta) en data/music.json
##   (propias y CC0 de OpenGameArt), rotando con silencios entre pistas. Calla mientras suena la música del jugador
##   por la megafonía de la nave.

const BUS_SFX := "Efectos"
const BUS_AMB := "Ambiente"
const BUS_MUSIC := "Musica"
const BUS_VOICE := "Voces"   ## diálogos del prólogo (ADR-043): volumen propio y atenúa música y ambiente
const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DATA := "res://data/music.json"   ## pistas de la banda sonora y sus contextos (ronda 14)
const KENNEY_DIR := "res://assets/audio/kenney/"
## Sonidos grabados (Kenney, CC0) que sustituyen a los sintetizados; se elige una variante al azar.
## La interfaz y los avisos usan los sintetizados suaves (ronda 8: los clics y la consola resultaban molestos).
## [nombre del sonido] -> [[archivo sin extensión, ajuste en dB]]
const VARIANTS := {
	"door_open": [["scifi_doorOpen_000", 0.0], ["scifi_doorOpen_001", 0.0], ["scifi_doorOpen_002", 0.0]],
	"door_close": [["scifi_doorClose_000", 0.0], ["scifi_doorClose_001", 0.0], ["scifi_doorClose_002", 0.0]],
	"sit": [["impact_impactSoft_medium_000", 0.0], ["impact_impactSoft_medium_001", 0.0]],
	"stand": [["impact_impactPlate_light_000", -3.0], ["impact_impactPlate_light_001", -3.0]],
	"sample": [["impact_impactMining_000", 0.0], ["impact_impactMining_001", 0.0], ["impact_impactMining_002", 0.0],
		["impact_impactMining_003", 0.0]],
	"landing": [["impact_impactMetal_heavy_000", 2.0], ["impact_impactMetal_heavy_001", 2.0]],
	"thruster": [["scifi_thrusterFire_000", -6.0], ["scifi_thrusterFire_001", -6.0], ["scifi_thrusterFire_002", -6.0]],
	"step_deck": [["impact_impactMetal_light_000", -6.0], ["impact_impactMetal_light_001", -6.0],
		["impact_impactMetal_light_002", -6.0], ["impact_impactMetal_light_003", -6.0]],
	"step_ground": [["impact_footstep_snow_000", 0.0], ["impact_footstep_snow_001", 0.0], ["impact_footstep_snow_002", 0.0],
		["impact_footstep_snow_003", 0.0], ["impact_footstep_snow_004", 0.0]],
	"step_suit": [["impact_footstep_concrete_000", 0.0], ["impact_footstep_concrete_001", 0.0], ["impact_footstep_concrete_002", 0.0],
		["impact_footstep_concrete_003", 0.0], ["impact_footstep_concrete_004", 0.0]],
}
const MUSIC_DB := -9.0
const FADE_S := 2.5

signal track_started(title: String, author: String)

var tracks: Array = []              ## pistas de data/music.json que existen
var _bags := {}                     ## contexto → pistas pendientes (barajadas)
var _current := {}
var _gap_t := 0.0
var _cache := {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_i := 0
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _context := ""
var _suppressed := false
var _hover_ms := 0
var _slider_ms := 0
var _ducked := false
var _duck_music := 0.35
var _duck_amb := 0.35


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b in [BUS_SFX, BUS_AMB, BUS_MUSIC, BUS_VOICE]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	apply_volumes()
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		_pool.append(p)
	_music_a = _music_player()
	_music_b = _music_player()
	_load_tracks()
	get_tree().node_added.connect(_on_node_added)


func _music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = BUS_MUSIC
	p.volume_db = -80.0
	add_child(p)
	return p


func apply_volumes() -> void:
	var dm := _duck_music if _ducked else 1.0
	var da := _duck_amb if _ducked else 1.0
	var vols := {BUS_SFX: GameSettings.sfx_volume, BUS_AMB: GameSettings.ambient_volume * da,
		BUS_MUSIC: GameSettings.music_volume * dm, BUS_VOICE: GameSettings.voice_volume}
	for b in vols:
		var i := AudioServer.get_bus_index(b)
		if i >= 0:
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(float(vols[b]), 0.0001)))


## Atenúa música y ambiente mientras suena un diálogo (y los restaura después).
## `music_k` y `amb_k`: cuánto queda de la música y del ambiente (el mensaje de Blackwell silencia la música: su
## grabación ya trae banda sonora).
func duck(on: bool, music_k: float = 0.35, amb_k: float = 0.35) -> void:
	if _ducked == on and _duck_music == music_k and _duck_amb == amb_k:
		return
	_ducked = on
	_duck_music = music_k
	_duck_amb = amb_k
	apply_volumes()


func is_ducked() -> bool:
	return _ducked


## Carga (con caché) un sonido de assets/audio/sfx o una ruta completa. Los .wav que deben repetirse se
## preparan como bucle.
func stream(name: String, loop: bool = false) -> AudioStream:
	var path := name if name.begins_with("res://") else SFX_DIR + name + ".wav"
	var key := path + ("#loop" if loop else "")
	if _cache.has(key):
		return _cache[key]
	if not ResourceLoader.exists(path):
		return null
	var s: AudioStream = load(path)
	if loop and s is AudioStreamOggVorbis:
		s = s.duplicate()
		(s as AudioStreamOggVorbis).loop = true
	elif loop and s is AudioStreamWAV:
		s = s.duplicate()
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	_cache[key] = s
	return s


## Variante grabada al azar (o null si el sonido sólo existe sintetizado). Devuelve [stream, ajuste dB].
func variant(name: String) -> Array:
	var list: Array = VARIANTS.get(name, [])
	if list.is_empty():
		return []
	var v: Array = list[randi() % list.size()]
	var s := stream(KENNEY_DIR + str(v[0]) + ".ogg")
	return [s, float(v[1])] if s != null else []


## Efecto no posicional (interfaz, avisos, acciones del propio jugador).
func play(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var v := variant(name)
	if not v.is_empty():
		var p0 := _pool[_pool_i]
		_pool_i = (_pool_i + 1) % _pool.size()
		p0.stream = v[0]
		p0.volume_db = volume_db + float(v[1])
		p0.pitch_scale = pitch * randf_range(0.96, 1.04)
		p0.play()
		return
	var s := stream(name)
	if s == null:
		return
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


## Efecto posicional de un solo uso colgado de `parent` (puertas, esclusa, aterrizaje…).
func play_at(name: String, parent: Node3D, offset: Vector3 = Vector3.ZERO, volume_db: float = 0.0, max_distance: float = 60.0) -> void:
	var v := variant(name)
	var s: AudioStream = v[0] if not v.is_empty() else stream(name)
	if not v.is_empty():
		volume_db += float(v[1])
	if s == null or parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = BUS_SFX
	p.volume_db = volume_db
	p.max_distance = max_distance
	p.unit_size = 6.0
	p.position = offset
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# --- Banda sonora ---------------------------------------------------------------------------
# Listas por contexto (data/music.json): al cambiar de contexto, fundido cruzado a una pista de su lista; al acabar
# una pista, silencio (según GameSettings.music_gaps) y otra de la lista, sin repetir la anterior (bolsa barajada).

## Contexto musical: "menu", "explore", "deep", "party" o "" (silencio). Cambia con un fundido cruzado.
func set_music(context: String) -> void:
	if context == _context:
		return
	_context = context
	_gap_t = 0.0
	_start_track(_pick(context))


func _load_tracks() -> void:
	var f := FileAccess.open(MUSIC_DATA, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		return
	for t in d.get("tracks", []):
		if t is Dictionary and ResourceLoader.exists(str(t.get("file", ""))):
			tracks.append(t)


## Siguiente pista del contexto: bolsa barajada por contexto, sin repetir la que acaba de sonar.
func _pick(context: String) -> Dictionary:
	if context == "":
		return {}
	var bag: Array = _bags.get(context, [])
	if bag.is_empty():
		for t in tracks:
			if context in t.get("contexts", []):
				bag.append(t)
		bag.shuffle()
		if bag.size() > 1 and not _current.is_empty() and str(bag[-1].get("id")) == str(_current.get("id")):
			bag.push_front(bag.pop_back())
		_bags[context] = bag
	return bag.pop_back() if not bag.is_empty() else {}


func _start_track(t: Dictionary) -> void:
	var old := _music_a
	_music_a = _music_b
	_music_b = old
	_current = t
	_music_a.stream = null
	if t.is_empty():
		return
	var s: AudioStream = load(str(t["file"]))
	if s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = false
	elif s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = false
	_music_a.stream = s
	_music_a.volume_db = -60.0
	_music_a.play()
	track_started.emit(str(t.get("title", "")), str(t.get("author", "")))


## Mientras suena la música propia por la megafonía de la nave, la banda sonora calla.
func set_suppressed(on: bool) -> void:
	_suppressed = on


func music_context() -> String:
	return _context


## Pista actual {id, title, author, ...} o {} (silencio).
func current_track() -> Dictionary:
	return _current if _music_a.playing else {}


## Salta a otra pista del contexto actual.
func next_track() -> void:
	_gap_t = 0.0
	_start_track(_pick(_context))


## Pausa entre pistas según Opciones > Audio > Banda sonora.
static func gap_for(mode: String) -> float:
	match mode:
		"continua":
			return randf_range(1.0, 3.0)
		"a_ratos":
			return randf_range(90.0, 240.0)
	return randf_range(20.0, 60.0)


func _process(delta: float) -> void:
	var off := GameSettings.music_gaps == "nunca"
	var gain := float(_current.get("gain_db", 0.0))
	var target := MUSIC_DB + gain if not _suppressed and not off and _music_a.stream != null else -80.0
	_music_a.volume_db = move_toward(_music_a.volume_db, target, delta * 60.0 / FADE_S)
	_music_b.volume_db = move_toward(_music_b.volume_db, -80.0, delta * 60.0 / FADE_S)
	if _music_b.playing and _music_b.volume_db <= -79.0:
		_music_b.stop()
	# Fin de pista: silencio y después otra de la lista (en el menú, sin pausa larga).
	if _music_a.stream != null and not _music_a.playing and not _suppressed and not off:
		if _gap_t <= 0.0:
			_gap_t = gap_for("continua" if _context == "menu" else GameSettings.music_gaps)
			_music_a.stream = null
	if _music_a.stream == null and _context != "" and _gap_t > 0.0:
		_gap_t -= delta
		if _gap_t <= 0.0:
			_start_track(_pick(_context))


# --- Interfaz -------------------------------------------------------------------------------

func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		var b := n as BaseButton
		b.mouse_entered.connect(_hover)
		b.focus_entered.connect(_hover)
		if b is OptionButton:
			(b as OptionButton).item_selected.connect(func(_i: int): play("ui_toggle", -6.0))
		elif b is CheckButton or b is CheckBox:
			b.toggled.connect(func(_on: bool): play("ui_toggle", -4.0))
		else:
			b.pressed.connect(func(): play("ui_click", -5.0))
	elif n is Slider:
		(n as Slider).value_changed.connect(func(_v: float):
			var now := Time.get_ticks_msec()
			if now - _slider_ms > 70:
				_slider_ms = now
				play("ui_hover", -10.0, 1.3))
	elif n is TabContainer:
		(n as TabContainer).tab_changed.connect(func(_t: int): play("ui_toggle", -6.0))
	elif n is ItemList:
		(n as ItemList).item_selected.connect(func(_i: int): play("ui_hover", -8.0))


func _hover() -> void:
	var now := Time.get_ticks_msec()
	if now - _hover_ms < 45:
		return
	_hover_ms = now
	play("ui_hover", -12.0)
