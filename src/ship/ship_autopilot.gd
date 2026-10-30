class_name ShipAutopilot
extends RefCounted
## Piloto automático (ADR-012). Genera ShipControls que pasan por el MISMO modelo de vuelo que el
## pilotaje manual (mismos límites); nunca teletransporta la nave.
##
## Modos:
## - HOLD: mantiene la actitud capturada al activarlo (rumbo, cabeceo e inclinación lateral) y la
##   velocidad de crucero.
## - APPROACH: apunta al centro del cuerpo y limita la velocidad según la altitud; a `approach_altitude` se
##   nivela y, si el cuerpo es sólido, DESCIENDE EN VERTICAL hasta posarse (perfil de velocidad de `descent_speed`,
##   ronda 10: antes se quedaba a 3 km y el descenso final dependía del piloto).
## - RECALL: vuela hasta un punto (la posición del astronauta que la llama) a altura de seguridad,
##   frena encima y desciende para posarse cerca (la asistencia de aterrizaje suaviza el final).
## Preparado para añadir destinos por coordenadas/rutas: sólo hay que proporcionar otra dirección
## objetivo y otra ley de velocidad.

const RECALL_CRUISE_ALT := 140.0
const RECALL_LAND_RADIUS := 30.0
const BOOST_SPEED := 2.5          ## mismo factor que el turbo del modelo de vuelo

const APPROACH_ALTITUDE := 3000.0
const MANUAL_OVERRIDE := 0.15
## Descenso automático: deceleración prudente (m/s², muy por debajo del empuje vertical disponible incluso en la
## Tierra) y velocidad final de contacto (m/s, el tren admite 3).
const LAND_DECEL := 3.0
const LAND_FINAL := 0.8

var params: ShipParams


func _init(p: ShipParams) -> void:
	params = p


func engage(s: ShipState, mode: int) -> bool:
	if s.landed:
		s.post_event("Piloto automático no disponible con la nave posada")
		return false
	s.autopilot = mode
	s.autopilot_heading = s.forward()
	s.autopilot_up = s.basis.y
	s.autopilot_speed = s.target_speed
	s.post_event("Piloto automático: %s" % ("mantener rumbo y velocidad" if mode == ShipState.Autopilot.HOLD else "aproximación y aterrizaje automático"))
	return true


func disengage(s: ShipState, reason: String) -> void:
	if s.autopilot == ShipState.Autopilot.OFF:
		return
	s.autopilot = ShipState.Autopilot.OFF
	s.post_event("Piloto automático desactivado (%s)" % reason)


## Rellena `out` con las órdenes del piloto automático. `to_center` = vector BF de la nave al centro del cuerpo.
func compute(s: ShipState, out: ShipControls, to_center: Vector3, body_radius: float, model: ShipFlightModel,
		radar_altitude: float = 1.0e9, can_land: bool = false) -> void:
	out.clear()
	if s.autopilot == ShipState.Autopilot.RECALL:
		_recall(s, out, to_center, model, radar_altitude)
		return
	if s.autopilot == ShipState.Autopilot.TRAVEL:
		# La velocidad y el régimen los fija Ship._update_travel; aquí sólo se apunta.
		_aim(s, out, s.travel_dir)
		if s.travel_climb:
			out.strafe.y = 1.0
		return
	var target_dir := s.autopilot_heading
	var speed := s.autopilot_speed
	if s.autopilot == ShipState.Autopilot.APPROACH:
		target_dir = to_center.normalized()
		var altitude := to_center.length() - body_radius
		if can_land and minf(altitude, radar_altitude) < APPROACH_ALTITUDE + 300.0:
			_land(s, out, -to_center.normalized(), model, radar_altitude, Vector3.ZERO)
			return
		var max_safe := maxf(0.0, (altitude - APPROACH_ALTITUDE) * 0.05)
		speed = minf(maxf(s.autopilot_speed, 50.0), max_safe)
	_aim(s, out, target_dir)
	if s.autopilot == ShipState.Autopilot.HOLD:
		# Alabeo hacia el "arriba" capturado (misma ley que el autonivelado, con otra referencia).
		var bank := atan2(s.basis.x.dot(s.autopilot_up), s.basis.y.dot(s.autopilot_up))
		out.roll = clampf(-bank * 1.6, -1.0, 1.0)
	model.set_target(s, speed)


func _recall(s: ShipState, out: ShipControls, to_center: Vector3, model: ShipFlightModel, alt: float) -> void:
	var radial := -to_center.normalized()
	var to := s.autopilot_target.sub(s.pos_bf).to_vector3()
	var horiz := to - radial * to.dot(radial)
	var dist := horiz.length()
	var fwd_h := s.forward() - radial * s.forward().dot(radial)
	if dist > RECALL_LAND_RADIUS * 2.0:
		_aim(s, out, horiz.normalized())
		# Lejos, a la máxima velocidad permitida (ronda 11): sube a una altura de crucero proporcional a la distancia
		# (allí el límite de velocidad es mayor), usa el turbo y frena con margen al acercarse.
		var cruise := clampf(dist * 0.06, RECALL_CRUISE_ALT, 20000.0)
		var facing := fwd_h.normalized().dot(horiz.normalized()) if fwd_h.length_squared() > 1e-6 else 0.0
		var brake := sqrt(2.0 * 8.0 * maxf(dist - RECALL_LAND_RADIUS * 2.0, 0.0)) + 15.0
		var speed := minf(brake, s.speed_cap) * clampf((facing - 0.5) * 2.0, 0.0, 1.0)
		out.boost = facing > 0.9 and brake > s.speed_cap * BOOST_SPEED   # el turbo multiplica el objetivo del modelo
		model.set_target(s, speed)
		out.strafe.y = clampf((cruise - alt) * 0.04, -1.0, 1.0)
	else:
		# Sobre el destino: se acerca despacio en horizontal y baja con el perfil seguro (nunca a fondo).
		var h_vel := horiz.normalized() * clampf((dist - RECALL_LAND_RADIUS) * 0.3, 0.0, 8.0) if dist > 0.5 else Vector3.ZERO
		_land(s, out, radial, model, alt, h_vel)


## Velocidad de descenso segura a `alt` metros del suelo: √(2·a·h) (siempre puede frenar a tiempo) y, cerca del suelo,
## proporcional a la altura, hasta `LAND_FINAL` en el contacto.
static func descent_speed(alt: float) -> float:
	var h := maxf(alt, 0.0)
	return minf(LAND_FINAL + h * 0.3, LAND_FINAL + sqrt(2.0 * LAND_DECEL * h))


## Descenso final: alas niveladas y una velocidad DESEADA en el marco del cuerpo (vertical del perfil + `h_vel`),
## que se traduce a ejes de la nave (maniobra lateral/vertical y velocidad hacia delante) para el modelo de vuelo.
## Así baja recto aunque la nave aún no esté nivelada del todo. Mientras deriva en horizontal, no termina de bajar.
func _land(s: ShipState, out: ShipControls, radial: Vector3, model: ShipFlightModel, alt: float, h_vel: Vector3) -> void:
	var fwd_h := s.forward() - radial * s.forward().dot(radial)
	if fwd_h.length_squared() < 0.04:
		fwd_h = s.basis.y - radial * s.basis.y.dot(radial)  # morro hacia abajo: al nivelar quedará hacia su "arriba"
	if fwd_h.length_squared() > 1e-6:
		_aim(s, out, fwd_h.normalized())
	var v_down := descent_speed(alt)
	var drift := (s.velocity - radial * s.velocity.dot(radial) - h_vel).length()
	if alt < 40.0 and drift > 2.5:
		v_down = minf(v_down, 0.3)  # primero detener la deriva: el tren sólo admite 4,5 m/s de lado
	var v_body := s.basis.transposed() * (h_vel - radial * v_down)
	out.strafe = Vector2(v_body.x, v_body.y) / model.maneuver_speed(s)
	model.set_target(s, -v_body.z)


func _aim(s: ShipState, out: ShipControls, target_dir: Vector3) -> void:
	var e := s.basis.transposed() * target_dir.normalized()  # en ejes de la nave; delante = -Z
	# Eje de giro = delante × objetivo (sin la singularidad de cabeceo/guiñada a 90°): se reparte el ángulo
	# total entre cabeceo (eje X) y guiñada (eje Y).
	var ang := acos(clampf(-e.z, -1.0, 1.0))
	var axis := Vector2(e.y, -e.x)
	if axis.length_squared() < 1e-10:
		axis = Vector2(1.0 if -e.z < 0.0 else 0.0, 0.0)  # justo detrás: cabecear
	axis = axis.normalized()
	var err_pitch := axis.x * ang
	var err_yaw := axis.y * ang
	out.pitch = _axis_cmd(err_pitch, s.ang_vel.x, params.max_rate.x, params.max_ang_accel.x)
	out.yaw = _axis_cmd(err_yaw, s.ang_vel.y, params.max_rate.y, params.max_ang_accel.y)
	out.roll = 0.0  # la asistencia amortigua el alabeo


## Velocidad angular deseada con frenado óptimo (√(2·a·θ)), expresada como fracción de la máxima.
static func _axis_cmd(err: float, _rate: float, max_rate: float, max_acc: float) -> float:
	var desired := signf(err) * minf(minf(max_rate, sqrt(2.0 * max_acc * 0.6 * absf(err))), 3.0 * absf(err))
	return clampf(desired / max_rate, -1.0, 1.0)
