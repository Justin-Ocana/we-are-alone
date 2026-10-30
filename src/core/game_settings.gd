extends Node
## Autoload `GameSettings`: configuración persistente en user://settings.cfg (versionada).
## Si el archivo está corrupto o es de una versión desconocida se renombra a .bak y se usan
## valores por defecto.

const PATH := "user://settings.cfg"
const VERSION := 1

## Presets de calidad. terrain_segments: cuadros por lado de cada parche.
## split_factor: un parche se divide si la distancia a su centro < split_factor × arista.
const QUALITY_PRESETS := {
	# Ronda 9 (rendimiento): con ANGLE/D3D11 lo caro son las llamadas de dibujo, no los triángulos: parches más
	# grandes (más segmentos, menos división). render_scale < 1 resultó MUCHO más lento en Compatibility (medido:
	# 58 → 29 FPS a media resolución), así que siempre 1.0.
	"low": {"terrain_segments": 16, "split_factor": 0.9, "max_jobs": 2, "shadows": false, "render_scale": 1.0, "post": "off"},
	"medium": {"terrain_segments": 24, "split_factor": 1.05, "max_jobs": 3, "shadows": false, "render_scale": 1.0, "post": "off"},
	"high": {"terrain_segments": 28, "split_factor": 1.35, "max_jobs": 3, "shadows": true, "render_scale": 1.0, "post": "full"},
}

var quality: String = "medium"
var mouse_sensitivity: float = 0.0025
var fov: float = 75.0
var show_hud: bool = false          ## HUD de depuración (F3); el casco tiene su propia interfaz
var camera_motion: float = 0.7      ## intensidad de los efectos de cámara (0 = estática)
var visor_effects: bool = true      ## distorsión/dispersión del cristal del visor
var motion_smoothing: bool = true   ## interpolación de física (ADR-042): movimiento suave a cualquier FPS
var flight_mode: String = "arcade"  ## "arcade" (sencillo) o "simulacion"
var max_fps: int = 0
var ui_modal: bool = false          ## un panel con ratón libre está abierto (no recapturar ni pausar)
var ui_hidden: bool = false         ## F2: oculta toda la interfaz (no se guarda; para capturas/inmersión)
var pad_look_speed: float = 2.6     ## rad/s de giro de la vista con el stick a fondo
var pad_invert_y: bool = false
var mouse_invert_y: bool = false
var fullscreen: bool = false
var vsync: bool = true
var master_volume: float = 0.9      ## 0..1
var music_volume: float = 0.8       ## 0..1 (banda sonora y música de la nave)
var sfx_volume: float = 0.85        ## 0..1 (efectos e interfaz)
var ambient_volume: float = 0.8     ## 0..1 (viento, zumbido de la nave, motores)
var voice_volume: float = 1.0       ## 0..1 (diálogos y mensajes del prólogo)
var subtitles: bool = true          ## subtítulos de los diálogos
var music_gaps: String = "normal"   ## banda sonora: "continua", "normal" (pausas de 20-60 s), "a_ratos" o "nunca"
var music_titles: bool = true       ## avisar del título de cada pista
# --- Música de la nave (megafonía, ADR-022 / ronda 14)
var ship_music_volume: float = 0.8  ## 0..1 bus de la megafonía
var ship_music_db: float = -6.0     ## volumen del reproductor (panel M)
var ship_speaker_db: float = -4.0   ## altavoces del resto de la nave respecto al puente (dB)
var ship_speaker_fx: float = 1.0    ## 0 = limpio, 1 = altavoz (recorte de graves y agudos, saturación, eco)
var ship_bass_db: float = 0.0       ## graves (-12..+12 dB)
var ship_treble_db: float = 0.0     ## agudos (-12..+12 dB)
var ship_music_duck: bool = true    ## bajar la música mientras hablan (diálogos y voz)
var ship_music_outside: bool = false  ## fuera de la nave, oírla bajito por la radio del traje
var ship_music_order: String = "lista"  ## "lista", "aleatorio" o "repetir"
const AUDIO_KEYS := ["music_gaps", "music_titles", "ship_music_volume", "ship_music_db", "ship_speaker_db",
	"ship_speaker_fx", "ship_bass_db", "ship_treble_db", "ship_music_duck", "ship_music_outside", "ship_music_order"]
# --- Voz en línea (ADR-046). Ajustes PERSONALES; el alcance máximo de proximidad lo fija la sala (Net.rules).
var voice_enabled: bool = true
var voice_mode: String = "vad"            ## proximidad: "vad" (activación por voz) o "ptt" (pulsar para hablar)
var voice_vad_threshold: float = 0.35     ## 0..1 sensibilidad (umbral de la puerta de ruido)
var voice_input_device: String = ""
var voice_output_device: String = ""
var voice_vol_prox: float = 1.0
var voice_vol_radio: float = 0.9
var voice_vol_ship: float = 0.9           ## altavoces de la nave (independiente de las voces cercanas)
var voice_range: float = 35.0             ## m: hasta dónde quieres oír por proximidad (≤ máximo de la sala)
var voice_effects: bool = true            ## oclusión, sala, casco y megafonía
var voice_radio_fx: bool = true           ## procesado de radio (compresión, ruido, cortes)
var voice_listen_radio: bool = true
var voice_listen_ship: bool = true
var voice_ship_linked: bool = true        ## vinculado al canal de la nave (puede transmitir por él)
var voice_ship_speakers: bool = true      ## a bordo, el canal de la nave suena por los altavoces
var voice_channel: int = 1
var voice_mutes: Dictionary = {}          ## nombre → true
var voice_player_volume: Dictionary = {}  ## nombre → 0..2
var voice_bindings: Dictionary = {}       ## acción → [tipo ("key"|"mouse"), código]
const VOICE_KEYS := ["voice_enabled", "voice_mode", "voice_vad_threshold", "voice_input_device", "voice_output_device",
	"voice_vol_prox", "voice_vol_radio", "voice_vol_ship", "voice_range", "voice_effects", "voice_radio_fx",
	"voice_listen_radio", "voice_listen_ship", "voice_ship_linked", "voice_ship_speakers", "voice_channel",
	"voice_mutes", "voice_player_volume", "voice_bindings"]
var split_mode: String = "vertical" ## cooperativo: "vertical" (lado a lado) u "horizontal" (arriba/abajo)
var ui_scale: float = 1.0           ## escala de los textos del HUD (0,8..1,3)
var post_effects: bool = true       ## resplandor, etalonaje, destello del Sol, grano y viñeta (ADR-039)
var post_mode: String = "auto"      ## "auto" (según la calidad), "off", "light" o "full" (ronda 9)
## Controlador gráfico (ronda 9): OpenGL nativo por defecto (medido: el mismo HD 630 da ~20 % más FPS y un tercio
## del coste de CPU por llamada que ANGLE). "angle" vuelve al modo de compatibilidad; se aplica al reiniciar
## mediante user://graficos.cfg (application/config/project_settings_override).
var graphics_driver: String = "opengl"


## Efectos de imagen efectivos: los elegidos o, en automático, los de la calidad (media: desactivados para 60 FPS).
func effective_post() -> String:
	if not post_effects:
		return "off"
	if post_mode == "auto":
		return str(preset().get("post", "full"))
	return post_mode
## Personalización de cada astronauta (ADR-035): nombre, colores del traje, del visor y estilo.
var profiles: Array = [
	{"name": "Jugador 1", "suit": Color(0.92, 0.9, 0.86), "accent": Color(1.0, 0.55, 0.22), "visor": Color(0.85, 0.62, 0.25),
		"pattern": 0, "backpack": 0},
	{"name": "Jugador 2", "suit": Color(0.28, 0.32, 0.38), "accent": Color(0.35, 0.85, 0.8), "visor": Color(0.3, 0.75, 0.9),
		"pattern": 1, "backpack": 1},
]


func profile(slot: int) -> Dictionary:
	return profiles[clampi(slot, 0, profiles.size() - 1)]


func _ready() -> void:
	_migrate_old_user_dir()
	load_settings()
	apply_runtime()


## El juego se llamaba REAL SPACE EXPLORER: copia ajustes, partida y música de su carpeta antigua (una vez).
func _migrate_old_user_dir() -> void:
	var old := OS.get_data_dir().path_join("Godot/app_userdata/REAL SPACE EXPLORER")
	var marker := "user://.migrado"
	if FileAccess.file_exists(marker) or not DirAccess.dir_exists_absolute(old):
		return
	for f in ["settings.cfg", "partida.json"]:
		var src := old.path_join(f)
		var dst := ProjectSettings.globalize_path("user://" + f)
		if FileAccess.file_exists(src) and not FileAccess.file_exists(dst):
			DirAccess.copy_absolute(src, dst)
	var music := old.path_join("music")
	if DirAccess.dir_exists_absolute(music):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://music"))
		for f in DirAccess.get_files_at(music):
			DirAccess.copy_absolute(music.path_join(f), ProjectSettings.globalize_path("user://music").path_join(f))
	var m := FileAccess.open(marker, FileAccess.WRITE)
	if m != null:
		m.store_string("ok")


func preset() -> Dictionary:
	return QUALITY_PRESETS.get(quality, QUALITY_PRESETS["medium"])


## Preset para la pantalla dividida (ronda 7): dos cámaras dibujan la escena, así que el terreno se refina algo
## menos y cada mitad se dibuja al 85 % como máximo.
func coop_preset() -> Dictionary:
	var p: Dictionary = preset().duplicate()
	p["split_factor"] = float(p["split_factor"]) * 0.8
	return p


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if not FileAccess.file_exists(PATH):
		return
	var err := cfg.load(PATH)
	if err != OK or int(cfg.get_value("meta", "version", -1)) != VERSION:
		push_warning("GameSettings: archivo inválido o de otra versión; se usan valores por defecto")
		DirAccess.rename_absolute(PATH, PATH + ".bak")
		return
	quality = str(cfg.get_value("graphics", "quality", quality))
	if not QUALITY_PRESETS.has(quality):
		quality = "medium"
	fov = clampf(float(cfg.get_value("graphics", "fov", fov)), 50.0, 110.0)
	max_fps = int(cfg.get_value("graphics", "max_fps", max_fps))
	mouse_sensitivity = clampf(float(cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity)), 0.0002, 0.02)
	show_hud = bool(cfg.get_value("ui", "show_hud", show_hud))
	camera_motion = clampf(float(cfg.get_value("controls", "camera_motion", camera_motion)), 0.0, 1.0)
	visor_effects = bool(cfg.get_value("graphics", "visor_effects", visor_effects))
	motion_smoothing = bool(cfg.get_value("graphics", "motion_smoothing", motion_smoothing))
	flight_mode = str(cfg.get_value("controls", "flight_mode", flight_mode))
	if flight_mode != "arcade" and flight_mode != "simulacion":
		flight_mode = "arcade"
	pad_look_speed = clampf(float(cfg.get_value("controls", "pad_look_speed", pad_look_speed)), 0.5, 6.0)
	pad_invert_y = bool(cfg.get_value("controls", "pad_invert_y", pad_invert_y))
	mouse_invert_y = bool(cfg.get_value("controls", "mouse_invert_y", mouse_invert_y))
	fullscreen = bool(cfg.get_value("graphics", "fullscreen", fullscreen))
	vsync = bool(cfg.get_value("graphics", "vsync", vsync))
	master_volume = clampf(float(cfg.get_value("audio", "master_volume", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music_volume", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx_volume", sfx_volume)), 0.0, 1.0)
	ambient_volume = clampf(float(cfg.get_value("audio", "ambient_volume", ambient_volume)), 0.0, 1.0)
	voice_volume = clampf(float(cfg.get_value("audio", "voice_volume", voice_volume)), 0.0, 1.0)
	subtitles = bool(cfg.get_value("audio", "subtitles", subtitles))
	split_mode = str(cfg.get_value("coop", "split_mode", split_mode))
	if split_mode != "vertical" and split_mode != "horizontal":
		split_mode = "vertical"
	ui_scale = clampf(float(cfg.get_value("ui", "ui_scale", ui_scale)), 0.8, 1.3)
	post_effects = bool(cfg.get_value("graphics", "post_effects", post_effects))
	post_mode = str(cfg.get_value("graphics", "post_mode", post_mode))
	graphics_driver = str(cfg.get_value("graphics", "driver", graphics_driver))
	for k in AUDIO_KEYS:
		if cfg.has_section_key("audio", k):
			var av = cfg.get_value("audio", k)
			if typeof(av) == typeof(get(k)) or (typeof(av) in [TYPE_INT, TYPE_FLOAT] and typeof(get(k)) == TYPE_FLOAT):
				set(k, float(av) if typeof(get(k)) == TYPE_FLOAT else av)
	for k in VOICE_KEYS:
		if cfg.has_section_key("voz", k):
			var v = cfg.get_value("voz", k)
			if typeof(v) == typeof(get(k)):
				set(k, v)
	voice_vad_threshold = clampf(voice_vad_threshold, 0.0, 1.0)
	voice_range = clampf(voice_range, 5.0, 80.0)
	for i in profiles.size():
		var saved = cfg.get_value("perfil", "p%d" % i) if cfg.has_section_key("perfil", "p%d" % i) else null
		if saved is Dictionary:
			for k in saved:
				if profiles[i].has(k) and typeof(saved[k]) == typeof(profiles[i][k]):
					profiles[i][k] = saved[k]


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", VERSION)
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("graphics", "fov", fov)
	cfg.set_value("graphics", "max_fps", max_fps)
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("ui", "show_hud", show_hud)
	cfg.set_value("controls", "camera_motion", camera_motion)
	cfg.set_value("graphics", "visor_effects", visor_effects)
	cfg.set_value("graphics", "motion_smoothing", motion_smoothing)
	cfg.set_value("controls", "flight_mode", flight_mode)
	cfg.set_value("controls", "pad_look_speed", pad_look_speed)
	cfg.set_value("controls", "pad_invert_y", pad_invert_y)
	cfg.set_value("controls", "mouse_invert_y", mouse_invert_y)
	cfg.set_value("graphics", "fullscreen", fullscreen)
	cfg.set_value("graphics", "vsync", vsync)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "ambient_volume", ambient_volume)
	cfg.set_value("audio", "voice_volume", voice_volume)
	cfg.set_value("audio", "subtitles", subtitles)
	cfg.set_value("coop", "split_mode", split_mode)
	cfg.set_value("ui", "ui_scale", ui_scale)
	cfg.set_value("graphics", "post_effects", post_effects)
	cfg.set_value("graphics", "post_mode", post_mode)
	cfg.set_value("graphics", "driver", graphics_driver)
	_write_driver_override()
	for i in profiles.size():
		cfg.set_value("perfil", "p%d" % i, profiles[i])
	for k in VOICE_KEYS:
		cfg.set_value("voz", k, get(k))
	for k in AUDIO_KEYS:
		cfg.set_value("audio", k, get(k))
	cfg.save(PATH)


func apply_runtime() -> void:
	Engine.max_fps = max_fps
	if is_inside_tree():
		get_tree().physics_interpolation = motion_smoothing
	if is_inside_tree() and get_viewport() != null:
		get_viewport().scaling_3d_scale = float(preset()["render_scale"])
	apply_audio()
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	var cur := DisplayServer.window_get_mode()
	if fullscreen != (cur == DisplayServer.WINDOW_MODE_FULLSCREEN or cur == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN):
		DisplayServer.window_set_mode(want)


## Escribe user://graficos.cfg: Godot lo lee al arrancar y decide ANGLE u OpenGL nativo.
func _write_driver_override() -> void:
	var f := FileAccess.open("user://graficos.cfg", FileAccess.WRITE)
	if f == null:
		return
	f.store_string("[rendering]\n\n")
	if graphics_driver == "angle":
		f.store_string("gl_compatibility/driver.windows=\"opengl3_angle\"\n")
	else:
		f.store_string("gl_compatibility/force_angle_on_devices=[]\n")


## Volumen general (bus Master) y de la música (bus propio, si ya existe).
func apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	var mi := AudioServer.get_bus_index(ShipMusic.BUS)
	if mi >= 0:
		AudioServer.set_bus_volume_db(mi, linear_to_db(maxf(ship_music_volume, 0.0001)))
	var ga := get_node_or_null("/root/GameAudio")
	if ga != null:
		ga.apply_volumes()
