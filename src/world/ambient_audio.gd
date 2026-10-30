class_name AmbientAudio
extends Node
## Ambiente sonoro del mundo (ADR-038), escuchado desde el jugador anfitrión:
## - Zumbido y ventilación de la nave a bordo.
## - Viento: sólo con atmósfera; crece con la presión y con la velocidad relativa al aire (amortiguado dentro).
##   En el vacío no hay viento (sólo suenan el traje y lo que toca tu cuerpo).
## - Motores: a bordo, según la potencia; fuera, sólo si hay aire.
## - Rumor de las profundidades en los gigantes gaseosos y truenos cuando caen rayos.
## - Elige la banda sonora (exploración, atmósferas densas, fiesta) y la silencia si suena tu música en la nave.

var world: SurfaceWorld
var _hum: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _engine: AudioStreamPlayer
var _deep: AudioStreamPlayer
var _flash_prev := 0.0
var _thunder_t := -1.0
var _warp_prev := false
var _landed_prev := true


func _ready() -> void:
	_hum = _loop("res://assets/audio/amb/ship_hum.wav")
	_wind = _loop("res://assets/audio/amb/wind.wav")
	_engine = _loop("res://assets/audio/kenney/scifi_spaceEngineLow_000.ogg")
	_deep = _loop("res://assets/audio/amb/deep.wav")
	GameAudio.set_music("explore")


func _loop(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = GameAudio.BUS_AMB
	p.stream = GameAudio.stream(path, true)
	p.volume_db = -80.0
	add_child(p)
	p.play()
	return p


static func _fade(p: AudioStreamPlayer, lin: float, delta: float, rate: float = 3.0) -> void:
	var target := linear_to_db(maxf(lin, 0.0001))
	p.volume_db = lerpf(p.volume_db, target, 1.0 - exp(-rate * delta))


func _process(delta: float) -> void:
	if world == null or world.player == null or get_tree().paused:
		return
	var pl := world.player
	var ship := world.ship
	var aboard := pl.aboard != null or pl.seated
	var st: ShipState = ship.state if ship != null else null
	# Atmósfera alrededor del oyente.
	var p_bf := pl.position_bf()
	var alt := p_bf.length() - world.terrain.radius
	var pressure := 0.0
	if world.atmo != null and world.atmo.present():
		pressure = world.atmo.pressure(alt)
	var p_bar := pressure / 1.0e5
	var air_speed := 0.0
	if aboard and st != null:
		air_speed = st.speed()
	elif not aboard:
		air_speed = pl.velocity.length()
	var wind_level := 0.0
	if p_bar > 0.002:
		var density_term := clampf(sqrt(p_bar) * 0.6, 0.0, 1.0)
		var flow := clampf(0.25 + air_speed / 250.0 + absf(st.wind_speed if st != null else 0.0) / 120.0, 0.0, 1.4)
		wind_level = density_term * flow * (0.35 if aboard else 1.0)
	_fade(_wind, wind_level * 0.8, delta)
	_wind.pitch_scale = clampf(0.85 + air_speed / 900.0, 0.85, 1.6)
	_fade(_hum, 0.55 if aboard else 0.0, delta, 2.0)
	var eng := 0.0
	if st != null:
		if aboard:
			eng = 0.15 + st.engine_output * 0.85 if not st.landed else 0.0
		elif p_bar > 0.01 and ship != null:
			var d := pl.global_position.distance_to(ship.global_position)
			eng = st.engine_output * clampf(1.0 - d / 600.0, 0.0, 1.0)
		_engine.pitch_scale = 0.8 + st.engine_output * 0.5 + (0.3 if ship.controls.boost else 0.0)
	_fade(_engine, eng * 0.7, delta)
	var deep_level := 0.0
	if world.atmo != null and world.atmo.kind == "gas_giant" and p_bar > 1.0:
		deep_level = clampf(log(p_bar) / log(200.0), 0.0, 1.0)
	_fade(_deep, deep_level * 0.8, delta, 1.0)
	# Truenos: tras cada rayo, con el retraso de la distancia (1–3 s).
	var fl := world.env.flash_amount()
	if fl > 0.4 and _flash_prev <= 0.4:
		_thunder_t = randf_range(0.8, 3.0)
	_flash_prev = fl
	if _thunder_t > 0.0:
		_thunder_t -= delta
		if _thunder_t <= 0.0:
			GameAudio.play("thunder", randf_range(-10.0, -3.0), randf_range(0.8, 1.1))
	# Salto lumínico y aterrizajes.
	if st != null:
		if st.light_active and not _warp_prev and aboard:
			GameAudio.play("warp", -4.0)
		_warp_prev = st.light_active
		if st.landed and not _landed_prev and ship != null:
			GameAudio.play_at("landing", ship, Vector3.ZERO, 0.0, 250.0)
		_landed_prev = st.landed
	# Banda sonora según el contexto.
	var ctx := "explore"
	if st != null and st.party:
		ctx = "party"
	elif p_bar > 3.0 or (world.atmo != null and world.atmo.kind == "gas_giant" and p_bar > 0.5):
		ctx = "deep"
	for a in world.players:
		if a.emote != "" and a.emote.begins_with("dance"):
			ctx = "party"
	GameAudio.set_music(ctx)
	GameAudio.set_suppressed(st != null and st.music_playing)
