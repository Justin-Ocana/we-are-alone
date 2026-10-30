class_name ShipFlightModel
extends RefCounted
## Modelo de vuelo de 6 grados de libertad (ADR-012). Puro: sólo modifica ShipState.
##
## - Rotación: la velocidad angular sigue a la ordenada (entrada × velocidad máxima) con aceleración
##   angular limitada → giros graduales; sin entrada, la asistencia frena la rotación (estabilización).
## - Traslación con asistencia de vuelo (por defecto): la nave persigue una velocidad deseada en sus ejes
##   (velocidad objetivo hacia delante + maniobra lateral/vertical) con aceleración limitada por eje y
##   compensación de la gravedad. Sin asistencia: empuje directo (newtoniano) y la gravedad actúa.
## - Regímenes de velocidad con aceleraciones propias; los rápidos son explícitamente ficticios.
## - Modo lumínico: sólo lejos de cuerpos masivos (≥ N radios), tras cargar el motor; nunca supera c.
##   Es un modelo NO relativista (sin dilatación temporal ni contracción).
## - Modo ARCADE (por defecto, ADR-016): sin regímenes; la velocidad máxima crece con la altitud
##   (60 m/s junto al suelo → 300 km/s en el espacio), aceleración proporcional (≈3 s hasta el máximo),
##   turbo ×2,5 y frenado de emergencia. Al bajar, el objetivo se recorta solo: la nave frena al acercarse.
## La posición la integra Ship (con colisiones); aquí sólo velocidad y orientación.

const ARCADE_MIN_SPEED := 150.0      ## m/s junto al suelo (más rápido en vuelo normal, ronda 6)
const ARCADE_SPEED_PER_M := 4.0
const ARCADE_MAX_SPEED := 1.0e6     ## 1000 km/s (más potencia, ronda 4)
const BOOST_FACTOR := 2.5
const TAKEOFF_RAMP_S := 9.0          ## s: tras despegar, la aceleración crece del 15 % al 100 % (ronda 11)
const MANEUVER_PER_M := 0.02         ## maniobra vertical/lateral: +2 cm/s por metro de altitud
const MANEUVER_MAX := 3000.0

var params: ShipParams


func _init(p: ShipParams) -> void:
	params = p


## `gravity` en m/s² (marco BF); `dist_center` y `body_radius` en m (para el modo lumínico).
func step(s: ShipState, c: ShipControls, gravity: Vector3, dist_center: float, body_radius: float,
		dt: float) -> void:
	if s.event_time > 0.0:
		s.event_time -= dt
	_update_light_mode(s, dist_center, body_radius, dt)
	s.altitude = dist_center - body_radius
	if not s.landed:
		s.takeoff_t += dt
	if s.arcade and not params.is_light(s.regime):
		s.speed_cap = minf(arcade_cap(dist_center - body_radius), s.atmo_speed_limit)
		if s.autopilot == ShipState.Autopilot.TRAVEL and s.travel_free:
			s.speed_cap = ShipParams.C * 0.1   # sin suelo con el que chocar: salir de las profundidades sin esperar
	else:
		s.speed_cap = max_speed(s)
	set_target(s, s.target_speed)  # recorta el objetivo si el máximo ha bajado (p. ej. al descender)
	_rotate(s, c, dt)
	if s.landed:
		s.velocity = Vector3.ZERO
		s.engine_output = lerpf(s.engine_output, 0.0, 1.0 - exp(-2.0 * dt))
		return
	_translate(s, c, gravity, dt)


static func arcade_cap(altitude: float) -> float:
	return clampf(ARCADE_MIN_SPEED + maxf(altitude, 0.0) * ARCADE_SPEED_PER_M, ARCADE_MIN_SPEED, ARCADE_MAX_SPEED)


## Velocidad de maniobra (subir/bajar/lateral con la asistencia): 25 m/s junto al suelo y más cuanto más alto
## (ronda 11): a 25 m/s, bajar desde la llegada de un viaje (miles de km) parecía quedarse atascado.
func maneuver_speed(s: ShipState) -> float:
	var m := clampf(params.maneuver_speed + maxf(s.altitude - 300.0, 0.0) * MANEUVER_PER_M, params.maneuver_speed, MANEUVER_MAX)
	if s.arcade:
		m = minf(m, maxf(params.maneuver_speed, s.speed_cap * 0.5))
	return m


## Velocidad máxima del régimen; en el lumínico, multiplicada por el salto (ficticio).
func max_speed(s: ShipState) -> float:
	var v := params.regime_max_speed(s.regime)
	if params.is_light(s.regime):
		v *= maxf(1.0, s.warp)
	return v


func set_target(s: ShipState, value: float) -> void:
	var maxs := s.speed_cap if s.arcade and not params.is_light(s.regime) else max_speed(s)
	var reverse := minf(30.0, maxs * 0.25) if s.arcade else maxs * params.reverse_fraction
	s.target_speed = clampf(value, -reverse, maxs)


## Frenado de emergencia: objetivo 0 y deceleración reforzada hasta detenerse.
func emergency_stop(s: ShipState) -> void:
	if params.is_light(s.regime):  # sale del motor lumínico para poder frenar
		s.regime = maxi(0, s.regime - 1)
		s.light_active = false
	set_target(s, 0.0)
	s.braking = true
	s.brake_accel = s.velocity.length() / 1.5  # deceleración constante: parada en ≈1,5 s


func set_regime(s: ShipState, i: int, dist_center: float, body_radius: float) -> bool:
	i = clampi(i, 0, params.regimes.size() - 1)
	if params.is_light(i):
		var min_r := float(params.regime(i).get("min_distance_radii", 3.0))
		if dist_center < min_r * body_radius:
			s.post_event("Lumínico no disponible: a %.1f radios del cuerpo (mínimo %.1f)" % [dist_center / body_radius, min_r])
			return false
		s.light_spool = 0.0
	s.regime = i
	s.light_active = false
	set_target(s, s.target_speed)
	return true


func _update_light_mode(s: ShipState, dist_center: float, body_radius: float, dt: float) -> void:
	if not params.is_light(s.regime):
		s.light_active = false
		return
	var min_r := float(params.regime(s.regime).get("min_distance_radii", 3.0))
	if dist_center < min_r * body_radius:
		# Interrupción automática: caída a crucero con compensación inercial ficticia.
		var cruise := maxi(0, s.regime - 2)
		s.regime = cruise
		s.light_active = false
		s.warp = 1.0
		var vmax := params.regime_max_speed(cruise)
		if s.velocity.length() > vmax:
			s.velocity = s.velocity.normalized() * vmax
		set_target(s, minf(s.target_speed, vmax))
		s.post_event("Salida automática del modo lumínico: proximidad a un cuerpo masivo")
		return
	var spool := float(params.regime(s.regime).get("spool_s", 3.0))
	if not s.light_active:
		s.light_spool += dt
		if s.light_spool >= spool:
			s.light_active = true
			s.post_event("Motor lumínico activo (modelo abstracto, no relativista)")


func _rotate(s: ShipState, c: ShipControls, dt: float) -> void:
	var target := Vector3(c.pitch * params.max_rate.x, c.yaw * params.max_rate.y, c.roll * params.max_rate.z)
	if s.landed:
		target = Vector3.ZERO
	var w := s.ang_vel
	w.x = move_toward(w.x, target.x, params.max_ang_accel.x * dt)
	w.y = move_toward(w.y, target.y, params.max_ang_accel.y * dt)
	w.z = move_toward(w.z, target.z, params.max_ang_accel.z * dt)
	s.ang_vel = w
	var ang := w.length()
	if ang > 1e-9:
		s.basis = (s.basis * Basis(w / ang, ang * dt)).orthonormalized()


func _translate(s: ShipState, c: ShipControls, gravity: Vector3, dt: float) -> void:
	var a_max := params.regime_accel(s.regime)
	if s.arcade and not params.is_light(s.regime):
		a_max = maxf(22.0, s.speed_cap * 0.45)
		if c.boost:
			a_max *= 2.0
	if s.braking:
		# Frenado de emergencia (compensación inercial ficticia): se detiene en ≈1,5 s desde cualquier
		# velocidad, incluso desde el modo lumínico. Pensado para la jugabilidad, no para el realismo.
		a_max = maxf(a_max * 2.5, s.brake_accel)
		if s.velocity.length() < 0.5 and absf(s.target_speed) < 0.01:
			s.braking = false
	if params.is_light(s.regime) and s.light_active:
		a_max *= maxf(1.0, s.warp)
	elif not s.braking:
		# Despegue progresivo (ronda 11): junto al suelo la aceleración arranca suave y crece en ~9 s; en aire denso,
		# además, se reduce (hasta el 45 % a 1 bar o más).
		if s.takeoff_t < TAKEOFF_RAMP_S and s.altitude < 5000.0:
			var k := clampf(s.takeoff_t / TAKEOFF_RAMP_S, 0.0, 1.0)
			a_max *= lerpf(0.15, 1.0, k * k * (3.0 - 2.0 * k))
		a_max *= lerpf(1.0, 0.45, clampf(s.ext_pressure / 1.0e5, 0.0, 1.0))
	var spooling := params.is_light(s.regime) and not s.light_active
	if spooling:
		a_max = params.regime_accel(maxi(0, s.regime - 1))
	# Cada eje puede, además, contrarrestar la componente de la gravedad sobre él (más un margen):
	# así la nave se sostiene en cualquier régimen sin inflar la aceleración disponible.
	var g_body := s.basis.transposed() * gravity
	var margin := Vector3(absf(g_body.x), absf(g_body.y), absf(g_body.z)) * (1.0 + params.hover_reserve / 10.0)
	var limits := Vector3(a_max * params.lateral_fraction, a_max * params.vertical_fraction, a_max) + margin
	var thrust := Vector3.ZERO  # aceleración de empuje, marco BF
	if s.flight_assist:
		if absf(c.throttle) > 0.0:
			_throttle(s, c.throttle, dt)
		var target := s.target_speed
		if c.boost and s.arcade and target > 0.0:
			target = minf(maxf(target, s.speed_cap) * BOOST_FACTOR, ShipParams.C)
		if spooling:
			target = clampf(target, -params.regime_max_speed(s.regime - 1), params.regime_max_speed(s.regime - 1))
		var ms := maneuver_speed(s)
		var v_body := Vector3(c.strafe.x * ms, c.strafe.y * ms, -target)
		var v_des := s.basis * v_body
		# Constante de respuesta: arcade más viva; el frenado de emergencia, casi inmediato.
		var tau := params.assist_tau * (0.6 if s.arcade else 1.0)
		if s.braking:
			tau = 0.05  # casi inmediato: la deceleración la limita `brake_accel` (constante → parada en ≈1,5 s)
		var a_cmd := (v_des - s.velocity) / maxf(tau, dt)
		thrust = a_cmd - gravity
	else:
		thrust = s.basis * Vector3(c.strafe.x * limits.x, c.strafe.y * limits.y, -c.throttle * limits.z)
	# Límites por eje de la nave.
	var tb := s.basis.transposed() * thrust
	tb.x = clampf(tb.x, -limits.x, limits.x)
	tb.y = clampf(tb.y, -limits.y, limits.y)
	# Simulación: los retropropulsores dan la mitad de empuje. Arcade: frenar es tan fuerte como acelerar.
	tb.z = clampf(tb.z, -limits.z, limits.z * (1.0 if s.arcade or s.braking else maxf(params.reverse_fraction, 0.5)))
	thrust = s.basis * tb
	s.velocity += (thrust + gravity) * dt
	var vmax_abs := ShipParams.C * (maxf(1.0, s.warp) if params.is_light(s.regime) and s.light_active else 1.0)
	if s.velocity.length() > vmax_abs:
		s.velocity = s.velocity.normalized() * vmax_abs  # nunca superlumínico salvo en salto (ficticio)
	var demand := clampf(tb.length() / limits.z, 0.0, 1.0)
	s.engine_output = lerpf(s.engine_output, demand, 1.0 - exp(-4.0 * dt))


## Cambio progresivo de la velocidad objetivo (crecimiento exponencial con un mínimo lineal).
func _throttle(s: ShipState, axis: float, dt: float) -> void:
	if axis < 0.0:
		s.braking = false
	if s.arcade and not params.is_light(s.regime):
		# Arcade: respuesta rápida y lineal (≈2,5 s de 0 al máximo disponible).
		set_target(s, s.target_speed + axis * maxf(8.0, s.speed_cap * 0.4) * dt)
		return
	var maxs := max_speed(s)
	var rate := maxf(absf(s.target_speed) * 0.9, maxs * 0.02)
	set_target(s, s.target_speed + axis * rate * dt)
