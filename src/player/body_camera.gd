class_name BodyCamera
extends Node3D
## Cámaras del astronauta (ADR-009).
##
## 1ª persona "verdadera": la cámara está en los ojos del cuerpo animado (AstronautRig.eye_marker),
## de modo que al mirar abajo el torso se inclina y se ven el pecho, los brazos y los pies.
## Estabilización de cabeza (como Star Citizen / las aves): se contrarresta parte del bote de la
## pelvis y la rotación de la vista no hereda el bamboleo del cuerpo. La inercia de la cabeza es un
## muelle amortiguado; aterrizar comprime el muelle y da un golpe de cabeceo.
## `motion_intensity` (0..1, ajustable en pausa) escala todos los efectos por comodidad.
## Efectos añadidos (ADR-019): sacudida por "trauma" (golpes, impactos de la nave, daño), vibración de
## los motores a bordo (sólo con empuje real, nunca en reposo), inercia de la cabeza al frenar/arrancar,
## postura en pendientes, estabilización al enfocar (clic derecho) y enfoque de instrumentos cercanos,
## y desorientación al flotar/marearse (bamboleo, pulso de FOV).
##
## 3ª persona: cámara sobre el hombro con brazo elástico, seguimiento con retardo y zoom.

var astro: Astronaut
var rig: AstronautRig
var fp_camera: Camera3D
var tp_camera: Camera3D
var tp_pivot: Node3D
var tp_arm: SpringArm3D
var first_person := true
var motion_intensity := 0.7
var base_fov := 75.0
var tp_distance := 3.4
const FOCUS_FOV := 32.0          ## FOV al enfocar (clic derecho): agudeza del ojo que un monitor no da
const LEAN_ROLL := 0.20          ## rad de alabeo al asomarse del todo
const CLOSE_FOCUS_FOV := 50.0    ## enfoque de algo a menos de 1,2 m: zoom suave, sin perder el contexto

var focus_zoom := 0.0            ## 0..1 enfoque actual (suavizado)

var _pos := Vector3(0, Units.ASTRONAUT_EYE_HEIGHT_M, 0)
var _vel := Vector3.ZERO
var _initialized := false
var _roll := 0.0
var _kick := 0.0
var _kick_vel := 0.0
var _fov_extra := 0.0
var _t := 0.0
var _tp_pos := Vector3(0, 1.55, 0)
var _idle := 0.0
var trauma := 0.0                ## 0..1: intensidad de sacudida (decae sola)
var _inertia := Vector2.ZERO     ## inclinación de cabeza por aceleración (cabeceo, alabeo)
var _prev_v_local := Vector3.ZERO
var _a_local := Vector3.ZERO
var _last_pf := -1
var _slope := 0.0


func setup(p_astro: Astronaut, p_rig: AstronautRig) -> void:
	astro = p_astro
	rig = p_rig
	# Interpolación (ADR-042): las cámaras no heredan la transformación del astronauta paso a paso; `follow()` las
	# coloca cada fotograma en su posición INTERPOLADA con la rotación actual (el ratón responde sin retraso).
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	top_level = true
	process_priority = -1000  # antes que nadie lea la cámara este fotograma (mundo, nubes, superposición)
	follow()
	fp_camera = Camera3D.new()
	fp_camera.name = "FirstPersonCamera"
	fp_camera.near = 0.05
	fp_camera.cull_mask = 0xFFFFF & ~(1 << (AstronautRig.HEAD_LAYER - 1))
	add_child(fp_camera)

	tp_pivot = Node3D.new()
	tp_pivot.name = "ThirdPersonPivot"
	add_child(tp_pivot)
	tp_arm = SpringArm3D.new()
	tp_arm.spring_length = tp_distance
	tp_arm.margin = 0.2
	tp_arm.collision_mask = Layers.solid_mask()
	var probe := SphereShape3D.new()
	probe.radius = 0.2
	tp_arm.shape = probe
	tp_arm.position = Vector3(0.45, 0.15, 0.0)
	tp_arm.add_excluded_object(astro.get_rid())
	tp_pivot.add_child(tp_arm)
	tp_camera = Camera3D.new()
	tp_camera.name = "ThirdPersonCamera"
	tp_camera.near = 0.05
	tp_arm.add_child(tp_camera)


func _process(_delta: float) -> void:
	follow()


## Sigue al cuerpo: posición interpolada entre pasos de física (suave aunque los FPS no coincidan con los 60 Hz de la
## física) y orientación actual del cuerpo.
func follow() -> void:
	if astro == null or not astro.is_inside_tree():
		return
	var xf := astro.global_transform
	if astro.is_physics_interpolated_and_enabled():
		xf.origin = astro.get_global_transform_interpolated().origin
	global_transform = xf


func current_camera() -> Camera3D:
	return fp_camera if first_person else tp_camera


func apply(p_first_person: bool, fov: float) -> void:
	first_person = p_first_person
	base_fov = fov
	fp_camera.current = first_person
	tp_camera.current = not first_person


func zoom(factor: float) -> void:
	tp_distance = clampf(tp_distance * factor, 1.6, 12.0)


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func on_landed(impact_speed: float) -> void:
	var s := minf(impact_speed, 8.0) * motion_intensity
	_vel.y -= s * 0.45
	_kick_vel -= s * 0.09


func update(delta: float, look_pitch: float, head_yaw: float, turn_rate: float, running: bool,
		exertion: float) -> void:
	if delta <= 0.0:
		return
	_t += delta
	var mi := motion_intensity
	# Estabilidad al apuntar o examinar: el enfoque amortigua casi todo el movimiento involuntario.
	var stab := 1.0 - 0.8 * focus_zoom
	# --- Posición: ojos del cuerpo menos parte del movimiento de la pelvis (estabilización).
	var eye := astro.to_local(rig.eye_marker.global_position)
	var target := eye - rig.pelvis_motion * (1.0 - 0.45 * mi * stab)
	if not _initialized:
		_pos = target
		_initialized = true
	# Muelle integrado en subpasos de 1/240 s (ronda 11): con un solo paso por fotograma, un tirón de FPS
	# (Δt ≥ 0,08 s) lo volvía inestable y la cabeza oscilaba sola: el «temblor sin motivo».
	var k := 260.0
	var c := 2.0 * sqrt(k) * 0.85
	var left := minf(delta, 0.1)
	while left > 1e-6:
		var h := minf(left, 1.0 / 240.0)
		_vel += ((target - _pos) * k - _vel * c) * h
		_pos += _vel * h
		left -= h
	# Límite de seguridad: la cabeza no se separa más de 25 cm de los ojos.
	if _pos.distance_to(target) > 0.25:
		_pos = target + (_pos - target).limit_length(0.25)
	# --- Sacudida por trauma (decae ~1,4/s; amplitud ∝ trauma²) y vibración de motores a bordo.
	trauma = maxf(0.0, trauma - 1.4 * delta)
	var shake := trauma * trauma * maxf(mi, 0.35)
	var shake_rot := Vector3(_n(_t * 23.0, 0.0), _n(_t * 21.0, 1.7), _n(_t * 19.0, 3.1)) * 0.045 * shake
	var shake_pos := Vector3(_n(_t * 17.0, 4.2), _n(_t * 19.0, 5.3), 0.0) * 0.03 * shake
	var ship := astro.aboard
	if ship != null and not ship.state.landed:
		# Sólo con empuje claro (despegue, aceleración, frenado): en vuelo estacionario o posada, cero.
		var vib := smoothstep(0.15, 1.0, ship.state.engine_output) * 0.0016 * mi
		shake_rot += Vector3(sin(_t * 157.0), sin(_t * 131.0 + 1.0), 0.0) * vib
	fp_camera.position = _pos + shake_pos

	# --- Rotación: vista pura + alabeo por desplazamiento lateral/giro + cabeceo por aterrizaje.
	var v_local := astro.global_transform.basis.orthonormalized().transposed() * astro.velocity
	# Inercia corporal: al frenar, la cabeza se va un poco hacia delante; al arrancar, hacia atrás.
	# Aceleración por PASO DE FÍSICA (la velocidad sólo cambia en ellos): por fotograma salían picos alternos
	# (0 en unos fotogramas, el doble en otros) que hacían temblar la inclinación de la cabeza.
	var a_local := _a_local
	var pf := Engine.get_physics_frames()
	if pf != _last_pf:
		var steps := maxi(1, pf - _last_pf) if _last_pf >= 0 else 1
		_a_local = (v_local - _prev_v_local) * Engine.physics_ticks_per_second / float(steps)
		_a_local = _a_local.limit_length(40.0)
		a_local = _a_local
		_prev_v_local = v_local
		_last_pf = pf
	var inertia_t := Vector2.ZERO
	if astro.is_on_floor() and not astro.floating:
		inertia_t = Vector2(clampf(-a_local.z * 0.006, -0.035, 0.035), clampf(a_local.x * 0.004, -0.02, 0.02)) * mi * stab
		# Postura en pendiente: al subir se mira algo más arriba; al bajar, hacia los pies.
		var v_h := Vector2(v_local.x, v_local.z).length()
		_slope = lerpf(_slope, clampf(v_local.y / maxf(v_h, 0.6), -0.6, 0.6) * 0.05 * mi, 1.0 - exp(-3.0 * delta))
	else:
		_slope = lerpf(_slope, 0.0, 1.0 - exp(-3.0 * delta))
	_inertia = _inertia.lerp(inertia_t, 1.0 - exp(-5.0 * delta))
	var roll_t := clampf(-v_local.x * 0.010 - turn_rate * 0.012, -0.07, 0.07) * mi * stab
	_roll = lerpf(_roll, roll_t, 1.0 - exp(-6.0 * delta))
	_kick_vel += (-90.0 * _kick - 12.0 * _kick_vel) * delta
	_kick = clampf(_kick + _kick_vel * delta, -0.12, 0.05)
	# Cámara completamente estable con el jugador quieto y descansado: el balanceo de respiración sólo
	# aparece tras un esfuerzo (recuperando el aliento) o en movimiento, y se desvanece al reposar.
	var moving := clampf(astro.velocity.length() / 1.5, 0.0, 1.0)
	var idle_motion := maxf(moving, clampf((exertion - 0.15) / 0.5, 0.0, 1.0))
	_idle = lerpf(_idle, idle_motion, 1.0 - exp(-1.5 * delta))
	var breath := sin(_t * TAU * lerpf(0.22, 0.6, exertion)) * 0.0025 * (0.4 + exertion) * mi * _idle
	var sway_yaw := sin(_t * 0.7) * 0.0012 * mi * _idle
	var lean: float = astro.lean_amount
	# Desorientación al flotar o marearse: bamboleo lento e irregular.
	var dz: float = astro.dizziness
	var disorient := (0.25 if astro.floating else 0.0) + dz
	var wob := Vector3(sin(_t * 1.3) + 0.5 * sin(_t * 2.9), sin(_t * 0.9 + 1.0), sin(_t * 0.7) + 0.4 * sin(_t * 2.1)) \
		* 0.025 * disorient * maxf(mi, 0.5)
	fp_camera.basis = Basis(Vector3.UP, head_yaw + (sway_yaw * stab + shake_rot.y + wob.y)) \
		* Basis(Vector3.RIGHT, look_pitch + _kick + breath * stab + _inertia.x + _slope + shake_rot.x + wob.x) \
		* Basis(Vector3.BACK, _roll - lean * LEAN_ROLL + _inertia.y + shake_rot.z + wob.z)
	# FOV: +6° al correr; en vuelo se abre con la velocidad (sensación de velocidad, hasta +18°).
	var fov_t := 0.0
	if running:
		fov_t = 6.0 * mi
	elif astro.flying:
		var v := astro.velocity.length()
		fov_t = clampf((log(maxf(v, 1.0)) / log(10.0) - 1.3) * 6.0, 0.0, 18.0) * mi
	fov_t += sin(_t * 0.8) * 5.0 * dz * maxf(mi, 0.5)  # pulso de FOV al marearse
	_fov_extra = lerpf(_fov_extra, fov_t, 1.0 - exp(-3.0 * delta))
	# Enfoque (clic derecho, como Arma): más débil si te mueves o estás cansado ("Human Focus").
	var focus_strength := clampf(1.0 - astro.velocity.length() / 7.0 - exertion * 0.35, 0.45, 1.0)
	var zoom_t := focus_strength if astro.focusing and not astro.flying else 0.0
	focus_zoom = lerpf(focus_zoom, zoom_t, 1.0 - exp(-(9.0 if zoom_t > focus_zoom else 12.0) * delta))
	var focus_fov := CLOSE_FOCUS_FOV if astro.close_focus else FOCUS_FOV
	fp_camera.fov = lerpf(base_fov + _fov_extra, focus_fov, focus_zoom)
	tp_camera.fov = lerpf(base_fov, FOCUS_FOV * 1.3, focus_zoom)

	# --- 3ª persona: pivote sobre el hombro siguiendo la cabeza con retardo.
	var tp_target := Vector3(0, 1.55, 0) + rig.pelvis_motion * 0.5 + Vector3(lean * 0.35, 0.0, 0.0)
	if astro.seated:
		# Sentado (pilotando): por encima del respaldo y un poco al lado; antes el respaldo tapaba al personaje.
		tp_target = Vector3(0.35, 2.05, 0.15)
	_tp_pos = _tp_pos.lerp(tp_target, 1.0 - exp(-10.0 * delta))
	tp_pivot.position = _tp_pos + shake_pos * 2.0
	tp_pivot.basis = Basis(Vector3.UP, head_yaw + wob.y) * Basis(Vector3.RIGHT, clampf(look_pitch, -1.2, 1.0) + shake_rot.x + wob.x) \
		* Basis(Vector3.BACK, shake_rot.z + wob.z)
	var want_len := minf(tp_distance, 2.4) if astro.seated else tp_distance
	tp_arm.spring_length = lerpf(tp_arm.spring_length, want_len, 1.0 - exp(-8.0 * delta))


## Ruido suave en [-1, 1] (suma de senos inconmensurables; barato y sin repetición visible).
static func _n(x: float, seed: float) -> float:
	return (sin(x + seed) + 0.6 * sin(x * 1.73 + seed * 2.1) + 0.3 * sin(x * 2.91 + seed * 0.7)) / 1.9
