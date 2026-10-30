class_name SuitAudio
extends Node
## Sonido del traje generado proceduralmente (sin archivos externos), ADR-009.
## - Pisadas: golpe grave transmitido por el traje. En el vacío no hay sonido exterior; con
##   atmósfera se añade un crujido agudo del suelo.
## - Zumbido continuo del ventilador del soporte vital.

const RATE := 22050

var has_atmosphere := false
var surface := "vacuum"           ## "deck" (a bordo), "air" (suelo con atmósfera) o "vacuum" (lo fija el astronauta)
var _step_players: Array[AudioStreamPlayer] = []
var _hum_player: AudioStreamPlayer
var _steps_vacuum: Array[AudioStreamWAV] = []
var _steps_air: Array[AudioStreamWAV] = []
var _step_index := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	for i in 3:
		_steps_vacuum.append(_make_step(0.22, 0.04, 0.0, 10 + i))
		_steps_air.append(_make_step(0.22, 0.06, 0.55, 20 + i))
	for i in 3:
		_step_players.append(_player(-8.0))
	_hum_player = _player(-30.0)
	_hum_player.stream = _make_hum(2.0)
	if is_inside_tree() and AudioServer.get_bus_count() > 0:
		_hum_player.play()


func _player(db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.volume_db = db
	add_child(p)
	return p


func footstep(intensity: float) -> void:
	var p := _step_players[_step_index % _step_players.size()]
	_step_index += 1
	# Pisadas grabadas (Kenney, CC0): cubierta metálica a bordo, crujido del suelo con atmósfera y, en el vacío,
	# sólo el golpe transmitido por el traje (más grave y apagado).
	var kind := "step_deck" if surface == "deck" else ("step_ground" if surface == "air" else "step_suit")
	var v: Array = GameAudio.variant(kind)
	if not v.is_empty():
		p.stream = v[0]
		p.bus = GameAudio.BUS_SFX
		p.pitch_scale = _rng.randf_range(0.92, 1.05) * (0.62 if surface == "vacuum" else 1.0)
		p.volume_db = linear_to_db(clampf(intensity, 0.05, 1.5)) - (14.0 if surface == "vacuum" else 9.0) + float(v[1])
		p.play()
		return
	var pool := _steps_air if has_atmosphere else _steps_vacuum
	p.stream = pool[_rng.randi() % pool.size()]
	p.pitch_scale = _rng.randf_range(0.9, 1.1)
	p.volume_db = linear_to_db(clampf(intensity, 0.05, 1.5)) - 8.0
	p.play()


var jet := 0.0                     ## 0..1 empuje de los propulsores del traje (lo fija el astronauta)
var _jet_player: AudioStreamPlayer


## La respiración se eliminó a petición del usuario (resultaba molesta). Aquí sólo suenan los propulsores del
## traje (siseo grabado en bucle, Kenney CC0), que se oyen por el propio traje también en el vacío.
func update(delta: float, _exertion: float) -> void:
	if _jet_player == null:
		_jet_player = AudioStreamPlayer.new()
		_jet_player.bus = GameAudio.BUS_SFX
		_jet_player.stream = GameAudio.stream("res://assets/audio/kenney/scifi_thrusterFire_000.ogg", true)
		_jet_player.volume_db = -80.0
		add_child(_jet_player)
		if _jet_player.stream != null:
			_jet_player.play()
	var target := linear_to_db(maxf(jet * 0.5, 0.0001)) - 6.0
	_jet_player.volume_db = lerpf(_jet_player.volume_db, target, 1.0 - exp(-10.0 * delta))


# --- Síntesis ---------------------------------------------------------------------

static func _to_wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = samples.size()
	return w


## Golpe grave (ruido muy filtrado con caída rápida) + crujido opcional (atmósfera).
func _make_step(seconds: float, decay: float, crunch: float, seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var hp_prev := 0.0
	var hp := 0.0
	for i in n:
		var t := float(i) / RATE
		var white := rng.randf_range(-1.0, 1.0)
		lp += 0.03 * (white - lp)
		lp2 += 0.05 * (lp - lp2)
		var thump := lp2 * exp(-t / decay) * 9.0 + sin(TAU * 55.0 * t) * exp(-t / (decay * 0.7)) * 0.35
		hp = 0.7 * (hp + white - hp_prev)
		hp_prev = white
		var grit := hp * exp(-t / 0.05) * crunch * (0.5 + 0.5 * rng.randf())
		out[i] = thump + grit * 0.35
	return _to_wav(out)


## Ruido marrón suave para el ventilador del soporte vital (bucle).
func _make_hum(seconds: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var brown := 0.0
	for i in n:
		brown = clampf(brown + rng.randf_range(-1.0, 1.0) * 0.02, -1.0, 1.0) * 0.998
		var t := float(i) / RATE
		out[i] = brown * 0.8 + sin(TAU * 120.0 * t) * 0.03
	# Fundido en los extremos para un bucle sin chasquidos.
	var fade := int(0.05 * RATE)
	for i in fade:
		var f := float(i) / fade
		out[i] *= f
		out[n - 1 - i] *= f
	return _to_wav(out, true)
