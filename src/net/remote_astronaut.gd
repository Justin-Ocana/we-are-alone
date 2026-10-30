class_name RemoteAstronaut
extends CharacterBody3D
## Jugador remoto (ADR-044): sólo el cuerpo animado (AstronautRig), sin física ni cámara ni interfaz. Su dueño
## manda 20 estados por segundo (NetWorld); aquí se suaviza el movimiento y se anima con la velocidad recibida.
## A bordo de la nave su pose llega RELATIVA a la nave (estable aunque la nave vaya a miles de km/s).
## Tiene los mismos campos que lee la interfaz de un Astronaut (nombre, sentado, a bordo) para las etiquetas.

var peer_id := 0
var profile := {}
var display_name := ""
var rig: AstronautRig
var world: SurfaceWorld

var look_pitch := 0.0
var head_yaw := 0.0
var exertion := 0.1
var seated := false
var seat_id := ""
var aboard: Ship = null
var flying := false
var grounded := true
var emote := ""
var emote_t := 0.0
var suit_on := true
var habitat := false
var room := ""                       ## sala de la base (para la historia en el anfitrión)

var _target := Transform3D()         ## pose objetivo en el marco del motor
var _target_rel := Transform3D()     ## pose relativa a la nave (si va a bordo)
var _vel := Vector3.ZERO
var _have := false
var _rx_ms := 0
var _turn := 0.0
var _prev_yaw := 0.0


func _init() -> void:
	collision_layer = 0
	collision_mask = 0
	rig = AstronautRig.new()
	rig.name = "Body"
	rig.astro = self
	rig.head_slot = 1                # su cabeza se ve desde la cámara del jugador local
	add_child(rig)


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # se coloca cada fotograma (ADR-042)
	rig.apply_profile(NetSession.profile_from_dict(profile))
	rig.footstep.connect(func(i: float):
		GameAudio.play_at("step_suit" if not habitat else "step_deck", self, Vector3.ZERO, -8.0 + i * 4.0, 25.0))


func set_habitat(on: bool) -> void:
	habitat = on
	rig.set_interior(on or aboard != null)


func position_bf() -> DVec3:
	return FloatingOrigin.to_global(global_position)


## Estado recibido de su dueño (ya convertido al marco del cuerpo dominante local por NetWorld).
func apply_state(d: Dictionary, pos_local: Vector3, basis: Basis, vel: Vector3, ship: Ship) -> void:
	look_pitch = float(d.get("pi", 0.0))
	head_yaw = float(d.get("hy", 0.0))
	exertion = float(d.get("ex", 0.1))
	seat_id = str(d.get("seat", ""))
	seated = seat_id != ""
	flying = bool(d.get("fly", false))
	grounded = bool(d.get("gr", true))
	suit_on = bool(d.get("suit", true))
	var e := str(d.get("em", ""))
	if e != emote:
		emote = e
		emote_t = 0.0
	var was_aboard := aboard
	aboard = ship if bool(d.get("ab", false)) else null
	if aboard != was_aboard:
		rig.set_interior(aboard != null or habitat)
	if aboard != null and d.has("rp"):
		var rp: Array = d["rp"]
		var rq: Array = d["rq"]
		_target_rel = Transform3D(Basis(Quaternion(rq[0], rq[1], rq[2], rq[3])), Vector3(rp[0], rp[1], rp[2]))
	_target = Transform3D(basis, pos_local)
	_vel = vel
	if not _have:
		_have = true
		global_transform = _current_target()
	_rx_ms = Time.get_ticks_msec()


func _current_target() -> Transform3D:
	if aboard != null and is_instance_valid(aboard):
		return aboard.global_transform * _target_rel
	# Extrapolación corta con la velocidad recibida (como mucho 0,25 s).
	var dt := minf((Time.get_ticks_msec() - _rx_ms) / 1000.0, 0.25)
	return Transform3D(_target.basis, _target.origin + _vel * dt)


func _process(delta: float) -> void:
	if not _have:
		return
	var tgt := _current_target()
	var err := tgt.origin - global_position
	var xf := global_transform
	if err.length() > 25.0:
		xf = tgt                          # salto (teletransporte, cambio de cuerpo)
	else:
		var k := 1.0 - exp(-14.0 * delta)
		xf.origin += err * k
		xf.basis = Basis(xf.basis.get_rotation_quaternion().slerp(tgt.basis.get_rotation_quaternion(), k))
	global_transform = xf
	velocity = _vel if aboard == null else Vector3.ZERO
	var yaw := atan2(-xf.basis.z.x, -xf.basis.z.z)
	_turn = lerpf(_turn, wrapf(yaw - _prev_yaw, -PI, PI) / maxf(delta, 1e-4), 1.0 - exp(-8.0 * delta))
	_prev_yaw = yaw
	if seated:
		rig.animate_seated(delta, look_pitch, head_yaw, Vector2.ZERO, exertion)
	else:
		rig.animate(delta, look_pitch, head_yaw, _turn, grounded, flying, 1.62, exertion, 0.0)
		emote_t += delta
		rig.apply_emote(emote, emote_t)
	# Lejos (otro planeta, a miles de km) no se dibuja: la precisión de 32 bits no da para colocarlo.
	visible = global_position.length() < 40000.0
