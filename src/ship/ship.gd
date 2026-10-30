class_name Ship
extends Node3D
## Nave transitable y pilotable (ADR-011..013).
##
## - El estado replicable vive en `state` (ShipState, posición en doble precisión en el marco BF).
##   El nodo sólo refleja ese estado: su transform local se recalcula cada paso desde los dobles.
## - Física: ShipFlightModel (velocidad/orientación) + integración de la posición con prueba del segmento
##   recorrido contra el terreno analítico (sin atravesar el planeta a ninguna velocidad) y aterrizaje.
## - Pasajeros: cada paso aplica la variación de transform de la nave a los astronautas a bordo
##   (traslado explícito: funciona con varios astronautas y a cualquier velocidad, sin depender de la
##   lógica de plataformas móviles). Dentro rige la gravedad aparente (`apparent_gravity`, ADR-018).
## - Se ejecuta antes que los astronautas (process_physics_priority negativo).

signal event(text: String)
signal impact(strength: float)       ## golpe de la nave (aterrizaje duro o choque): sacude a los pasajeros

const PRIORITY := -20
const GEAR_DEPLOY_ALT := 60.0
var _last_impact_ms := -100000
var net_puppet := false    ## en línea: otro equipo manda en la nave y aquí sólo se sigue su estado (ADR-044)
var _net_pos: DVec3 = null
var _net_basis := Basis()
var _net_vel := Vector3.ZERO
var _net_ms := 0
var takeoff_guard := Callable()   ## (Ship) -> String: motivo para no despegar (compuertas del hangar cerradas)
var immobilized := false   ## prólogo: la nave espera reparación en el hangar de LF-01 (no despega; ADR-043)
var _immob_ms := -100000
const LIGHT_LABEL_HZ := 10.0
const INERTIAL_MAX := 1.2            ## m/s²: la compensación inercial deja sentir como máximo esto
                                     ## (menor que la gravedad lunar: las maniobras inclinan, no vuelcan)

var params: ShipParams
var state := ShipState.new()
var model: ShipFlightModel
var autopilot: ShipAutopilot
var terrain: PlanetTerrain
var body_def: BodyDef
var collision_body: StaticBody3D
var dyn := {}
var doors := {}                      ## id -> ShipDoor
var airlock := ShipAirlock.new()
var passengers: Array = []           ## astronautas a bordo (no sentados)
var crew_sources: Array = []         ## todos los astronautas del mundo (para puertas/esclusa); lo fija el mundo
var pilot: Node = null               ## astronauta en el puesto de pilotaje (o null)
var seat_occupants := {}             ## id de asiento -> astronauta
var accel := Vector3.ZERO            ## aceleración lineal de la nave (marco BF, m/s²)
var ang_accel := Vector3.ZERO        ## aceleración angular (marco BF, rad/s²)
var _prev_velocity := Vector3.ZERO
var _prev_ang_world := Vector3.ZERO
var _was_occupied := false
var music: ShipMusic                 ## megafonía (ADR-022)
var system: SolarSystem = null       ## Sistema Solar (viajes, ADR-028); lo fija el mundo
var atmo: AtmosphereModel = null     ## atmósfera del cuerpo dominante (ADR-029); lo fija el mundo
const HULL_PRESSURE_LIMIT := 1.0e7   ## Pa (100 bar): presión de diseño del casco (FICTICIA)
const HULL_TEMP_LIMIT := 2000.0      ## K: límite del escudo térmico (FICTICIO)
const DRAG_CDA := 350.0              ## m²: coeficiente de arrastre × área frontal (estimado para 57 m)
const HULL_EMISSIVITY := 0.85
const SIGMA := 5.670374419e-8
var controls := ShipControls.new()   ## entrada del piloto humano
var radar_altitude := 0.0            ## m desde las patas al suelo
var vertical_speed := 0.0
var _ap_controls := ShipControls.new()
var _label_accum := 0.0
var _blink := 0.0
var _gear_extension := 1.0


func setup(p_params: ShipParams, p_terrain: PlanetTerrain, p_body: BodyDef) -> void:
	params = p_params
	terrain = p_terrain
	body_def = p_body
	model = ShipFlightModel.new(params)
	autopilot = ShipAutopilot.new(params)


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON  # se mueve en pasos de física (ADR-042)
	process_physics_priority = PRIORITY
	add_to_group(FloatingOriginService.GROUP)
	impact.connect(_on_impact)
	music = ShipMusic.new()
	music.name = "Music"
	music.ship = self
	add_child(music)
	# Cuerpo estático recolocado cada paso; su transform se envía al servidor de física de inmediato
	# en `_sync_node` (ver ADR-011): sin eso, las colisiones del interior irían un paso por detrás.
	collision_body = StaticBody3D.new()
	collision_body.name = "Hull"
	collision_body.collision_layer = Layers.bit(Layers.PHYS_SHIP)
	collision_body.collision_mask = 0
	add_child(collision_body)
	dyn = ShipBuilder.new().build(self, collision_body)
	doors = dyn["doors"]
	airlock.inner = doors["esclusa_int"]
	airlock.outer = doors["esclusa_ext"]
	FloatingOrigin.origin_shifted.connect(func(_d): _sync_node())
	_sync_node()


## Posa la nave en la superficie en la dirección BF dada, con el morro hacia `heading` (tangente).
func place_landed(dir: DVec3, heading: Vector3) -> void:
	var d := dir.normalized()
	var up := d.to_vector3()
	var fwd := (heading - up * heading.dot(up)).normalized()
	state.basis = Basis(up.cross(-fwd).normalized(), up, -fwd).orthonormalized()
	var ground := _gear_ground_radius(d, state.basis)
	state.pos_bf = d.mul(ground + params.gear_drop)
	state.velocity = Vector3.ZERO
	state.ang_vel = Vector3.ZERO
	state.landed = true
	state.gear_deployed = true
	state.target_speed = 0.0
	_sync_node()


## Transform local (motor) correspondiente al estado, con el origen flotante actual.
func local_transform() -> Transform3D:
	return Transform3D(state.basis, FloatingOrigin.to_local(state.pos_bf))


func _sync_node() -> void:
	global_transform = local_transform()
	_push_physics_transform()


## Godot encola las notificaciones de cambio de transform y las aplica al servidor de física más
## tarde; los astronautas se mueven en el MISMO paso, así que el cuerpo de colisión se actualiza ya.
func _push_physics_transform() -> void:
	if collision_body != null and collision_body.is_inside_tree():
		PhysicsServer3D.body_set_state(collision_body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM,
			collision_body.global_transform)


func local_up() -> Vector3:
	return state.basis.y


func gravity_vector() -> Vector3:
	var r := state.pos_bf.length()
	return -state.pos_bf.normalized().to_vector3() * body_def.gravity_at_distance(r)


## Velocidad (marco BF) de un punto de la nave dado en coordenadas locales del motor.
func point_velocity(global_point: Vector3) -> Vector3:
	var r := global_point - global_position
	return state.velocity + (state.basis * state.ang_vel).cross(r)


# --- Ciclo de física -------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	if params == null:
		return
	var old_xf := local_transform()
	# Pose de cada pasajero RELATIVA a la nave antes de moverla (números pequeños: sin pérdida de precisión).
	var old_inv := old_xf.affine_inverse()
	var rels: Array[Transform3D] = []
	for p in passengers:
		rels.append(old_inv * p.global_transform)
	var dist := state.pos_bf.length()
	var radius := terrain.radius
	# Órdenes: piloto automático (cede ante entrada manual) o piloto humano.
	var cmd := controls
	if state.autopilot != ShipState.Autopilot.OFF:
		if controls.manual_magnitude() > ShipAutopilot.MANUAL_OVERRIDE:
			autopilot.disengage(state, "control manual")
			emit_signal("event", state.event_text)
		else:
			if state.autopilot == ShipState.Autopilot.TRAVEL:
				_update_travel()
			if absf(controls.throttle) > 0.0 and state.autopilot != ShipState.Autopilot.TRAVEL:  # el acelerador ajusta la velocidad de crucero
				model._throttle(state, controls.throttle, dt)
				state.autopilot_speed = state.target_speed
			autopilot.compute(state, _ap_controls, -state.pos_bf.to_vector3(), radius, model, radar_altitude, terrain.solid)
			cmd = _ap_controls
	cmd = _landing_assist(cmd)
	# Autonivelado en Arcade, salvo con el piloto automático de rumbo (mantiene la inclinación actual).
	if (state.arcade and state.autopilot != ShipState.Autopilot.HOLD and state.autopilot != ShipState.Autopilot.TRAVEL) 			or state.autopilot == ShipState.Autopilot.RECALL:
		cmd = _auto_level(cmd)
	# Despegue: impulso vertical con la nave posada.
	var guard := ""
	if state.landed and cmd.strafe.y > 0.3 and takeoff_guard.is_valid():
		guard = str(takeoff_guard.call(self))
	if state.landed and cmd.strafe.y > 0.3 and guard != "":
		if Time.get_ticks_msec() - _immob_ms > 3000:
			_immob_ms = Time.get_ticks_msec()
			state.post_event(guard)
			emit_signal("event", state.event_text)
	elif state.landed and cmd.strafe.y > 0.3 and immobilized:
		if Time.get_ticks_msec() - _immob_ms > 4000:
			_immob_ms = Time.get_ticks_msec()
			state.post_event("Propulsión bloqueada: reparación pendiente en el hangar")
			emit_signal("event", state.event_text)
	elif state.landed and cmd.strafe.y > 0.3:
		state.takeoff_t = 0.0
		state.landed = false
		state.velocity = local_up() * 2.0
		state.post_event("Despegue")
	if net_puppet:
		_net_follow(dt)
	else:
		model.step(state, cmd, gravity_vector(), dist, radius, dt)
		if not state.landed:
			_apply_environment(dt)
			_advance(dt)
	# Aceleraciones (para la gravedad aparente de los pasajeros).
	var w_world := state.basis * state.ang_vel
	var k := 1.0 - exp(-dt / 0.12)  # filtrado: lo que se siente no tiene picos de un paso
	accel = accel.lerp((state.velocity - _prev_velocity) / dt, k)
	ang_accel = ang_accel.lerp((w_world - _prev_ang_world) / dt, k)
	_prev_velocity = state.velocity
	_prev_ang_world = w_world
	_check_empty()
	_update_radar()
	var new_xf := local_transform()
	# A gran velocidad la nave avanza miles de km por paso: se recentra el origen flotante en ella ANTES de
	# recolocar a los pasajeros, así sus posiciones nunca pasan por números grandes en 32 bits (ADR-031).
	var shifted := false
	if new_xf.origin.length() > FloatingOrigin.threshold_m and _carries_origin_driver():
		FloatingOrigin.update_focus(new_xf.origin)
		new_xf = local_transform()
		shifted = true
	global_transform = new_xf
	_push_physics_transform()
	var rot := (new_xf.basis * old_xf.basis.inverse()).orthonormalized()
	for pi in passengers.size():
		passengers[pi].carry_relative(new_xf, rels[pi], rot)
	# Ocupantes de los asientos en el MISMO paso que la nave (antes sólo en _process): con la interpolación de física,
	# su posición «anterior» se quedaba atrás y la cámara del piloto podía acabar lejos de la cabina (ronda 11).
	for sid in seat_occupants:
		var occ = seat_occupants[sid]
		if is_instance_valid(occ) and occ is Node3D:
			(occ as Node3D).global_transform = seat_transform(sid)
	if shifted:
		# Recentrado en este paso: la nave y su gente se dibujan ya en su sitio nuevo, sin interpolar desde el viejo.
		# A partir de unos 60 km/s esto ocurre en cada paso (motor lumínico): antes desaparecía la cabina en 1ª persona.
		reset_physics_interpolation()
		for p in passengers:
			if is_instance_valid(p):
				p.reset_physics_interpolation()
		for sid in seat_occupants:
			var occ2 = seat_occupants[sid]
			if is_instance_valid(occ2) and occ2 is Node:
				(occ2 as Node).reset_physics_interpolation()
	_update_doors(dt)
	_update_gear(dt)
	state.doors = {}
	for id in doors:
		state.doors[id] = doors[id].open
	state.airlock_phase = airlock.phase_name()


## Estado recibido de quien manda en la nave (ya en el marco del cuerpo dominante local).
func net_receive(pos: DVec3, basis: Basis, vel: Vector3, ang_vel: Vector3, landed: bool) -> void:
	_net_pos = pos
	_net_basis = basis.orthonormalized()
	_net_vel = vel
	state.ang_vel = ang_vel
	state.landed = landed
	_net_ms = Time.get_ticks_msec()


## Sigue el estado recibido: extrapolación corta con su velocidad y corrección suave (salto si se aleja mucho).
func _net_follow(dt: float) -> void:
	if _net_pos == null:
		return
	var lead := minf((Time.get_ticks_msec() - _net_ms) / 1000.0, 0.3)
	var target := _net_pos.add_vector3(_net_vel * lead)
	var err := target.sub(state.pos_bf).to_vector3()
	if err.length() > 200.0 + _net_vel.length() * 0.5:
		state.pos_bf = target
	else:
		state.pos_bf = state.pos_bf.add_vector3(_net_vel * dt + err * (1.0 - exp(-8.0 * dt)))
	state.basis = Basis(state.basis.get_rotation_quaternion().slerp(_net_basis.get_rotation_quaternion(), 1.0 - exp(-10.0 * dt)))
	state.velocity = _net_vel


## Arcade: cerca de un cuerpo, sin entrada de alabeo, la nave se nivela sola con el horizonte.
func _auto_level(cmd: ShipControls) -> ShipControls:
	if absf(cmd.roll) > 0.05 or state.landed:
		return cmd
	var altitude := state.pos_bf.length() - terrain.radius
	if altitude > 80000.0:
		return cmd
	var radial := state.pos_bf.normalized().to_vector3()
	if absf(state.forward().dot(radial)) > 0.9:
		return cmd  # morro casi vertical: el horizonte no está definido
	var out := _copy_controls(cmd)
	out.roll = auto_level_roll(state.basis, radial)
	return out


## Orden de alabeo que lleva las alas a la horizontal. Alabeo +1 = a la izquierda (sube el ala derecha),
## así que con el ala derecha alta (ángulo > 0) hay que alabear a la derecha (orden negativa).
## Usa el ángulo completo (atan2): también endereza la nave si está invertida.
static func auto_level_roll(b: Basis, radial: Vector3) -> float:
	var bank := atan2(b.x.dot(radial), b.y.dot(radial))
	return clampf(-bank * 1.6, -1.0, 1.0)


func _copy_controls(cmd: ShipControls) -> ShipControls:
	var c := ShipControls.new()
	c.pitch = cmd.pitch
	c.yaw = cmd.yaw
	c.roll = cmd.roll
	c.strafe = cmd.strafe
	c.throttle = cmd.throttle
	c.boost = cmd.boost
	return c


## Asistencia de aterrizaje: con el tren fuera y cerca del suelo, la velocidad de descenso pedida se
## limita progresivamente (1 m/s + 0,45 m/s por metro de altitud; ronda 10, antes 1,5 + 0,9 y sólo bajo 25 m, que con
## el retardo de la asistencia aún tocaba suelo a más de 3 m/s) para posarse con suavidad.
func _landing_assist(cmd: ShipControls) -> ShipControls:
	if not state.flight_assist or not state.gear_deployed or state.landed or radar_altitude > 55.0:
		return cmd
	if cmd.strafe.y >= 0.0:
		return cmd
	var allowed := 1.0 + maxf(radar_altitude, 0.0) * 0.45
	var limited := _copy_controls(cmd)
	limited.strafe = Vector2(cmd.strafe.x, maxf(cmd.strafe.y, -allowed / model.maneuver_speed(state)))
	return limited


## Integra la posición comprobando el segmento recorrido contra el terreno (cualquier velocidad).
func _advance(dt: float) -> void:
	var motion := state.velocity * dt
	var p0 := state.pos_bf
	var p1 := p0.add_vector3(motion)
	var clearance := _clearance()
	var hit := _segment_terrain_hit(p0, p1, clearance)
	if hit < 0.0:
		state.pos_bf = p1
		return
	# Contacto: se detiene en el punto seguro y se decide entre aterrizaje e impacto.
	var safe := p0.add_vector3(motion * maxf(0.0, hit - 0.001))
	var up := safe.normalized()
	var ground := _gear_ground_radius(up, state.basis)
	state.pos_bf = up.mul(maxf(safe.length(), ground + clearance))
	var radial := up.to_vector3()
	var v_in := state.velocity.dot(radial)
	var tilt := rad_to_deg(state.basis.y.angle_to(radial))
	var horizontal := (state.velocity - radial * v_in).length()
	var gentle := absf(v_in) <= params.landing_max_speed and horizontal <= params.landing_max_speed * 1.5
	# Apoyada casi quieta (sin tren o algo inclinada): se posa igualmente. Antes quedaba rozando el suelo y cada paso
	# contaba como un choque: la sacudida de cámara se saturaba para todos a bordo (ronda 10, «la cámara se vuelve loca»).
	var settle := absf(v_in) < 1.0 and horizontal < 1.0
	if gentle and ((tilt <= params.landing_max_tilt_deg and state.gear_deployed) or settle):
		_touch_down(up)
	else:
		if absf(v_in) > params.hard_impact or horizontal > params.hard_impact * 3.0:
			state.post_event("¡Impacto contra el terreno a %.0f m/s!" % state.velocity.length())
		# Un roce lento no sacude: sólo golpes de verdad, y como mucho uno cada 0,4 s.
		var now := Time.get_ticks_msec()
		if (absf(v_in) > 1.5 or horizontal > 4.0) and now - _last_impact_ms > 400:
			_last_impact_ms = now
			impact.emit(clampf(maxf(absf(v_in), horizontal * 0.3) / 10.0, 0.2, 3.0))
		state.velocity = (state.velocity - radial * v_in) * 0.3
		if v_in > 0.0:
			state.velocity += radial * v_in


func _touch_down(up: DVec3) -> void:
	var radial := up.to_vector3()
	var fwd := state.forward() - radial * state.forward().dot(radial)
	if fwd.length_squared() < 1e-6:
		fwd = state.basis.y - radial * state.basis.y.dot(radial)
	fwd = fwd.normalized()
	state.basis = Basis(radial.cross(-fwd).normalized(), radial, -fwd).orthonormalized()
	var ground := _gear_ground_radius(up, state.basis)
	state.pos_bf = up.mul(ground + params.gear_drop)
	var touch := absf(state.velocity.dot(radial))  # antes de anular la velocidad (antes siempre valía 0)
	state.velocity = Vector3.ZERO
	state.ang_vel = Vector3.ZERO
	state.landed = true
	state.target_speed = 0.0
	autopilot.disengage(state, "nave posada")
	state.post_event("Nave posada")
	impact.emit(clampf(touch / 6.0, 0.1, 1.0))


## Distancia mínima del origen de la nave (suelo de la cubierta) al terreno.
func _clearance() -> float:
	var drop := params.gear_drop if state.gear_deployed else 0.45
	# Inclinación: el casco (≈28 m de semieslora) baja por delante o por detrás.
	var r := state.pos_bf.normalized().to_vector3()
	var tilt_sin := sqrt(maxf(0.0, 1.0 - pow(absf(state.basis.y.dot(r)), 2.0)))
	return drop + tilt_sin * ShipLayout.HALF_LENGTH * 0.55


## Radio del suelo bajo la nave: máximo entre las tres patas (para no hundir ninguna).
func _gear_ground_radius(up: DVec3, b: Basis) -> float:
	var best := terrain.ground_radius_at(up)
	var origin_r := up.length()
	if origin_r < 1.0:
		return best
	for off: Vector3 in ShipLayout.GEAR_POINTS:
		var p := up.normalized().mul(terrain.radius).add_vector3(b * off)
		best = maxf(best, terrain.ground_radius_at(p))
	return best


## Primer parámetro t∈[0,1] en el que el segmento queda a menos de `clearance` del terreno, o −1.
func _segment_terrain_hit(p0: DVec3, p1: DVec3, clearance: float) -> float:
	var top := terrain.radius + terrain.max_elevation() + clearance + 50.0
	var d := p1.sub(p0)
	var len := d.length()
	# Intersección del segmento con la esfera de seguridad.
	var t_enter := 0.0
	if p0.length() > top:
		var a := d.dot(d)
		if a < 1e-12:
			return -1.0
		var b := 2.0 * p0.dot(d)
		var c := p0.dot(p0) - top * top
		var disc := b * b - 4.0 * a * c
		if disc < 0.0:
			return -1.0
		var sq := sqrt(disc)
		t_enter = (-b - sq) / (2.0 * a)
		if t_enter > 1.0 or (-b + sq) / (2.0 * a) < 0.0:
			return -1.0
		t_enter = maxf(t_enter, 0.0)
	var steps := clampi(int(len / 20.0), 1, 64)
	for i in steps + 1:
		var t := lerpf(t_enter, 1.0, float(i) / float(steps))
		var p := p0.add(d.mul(t))
		if p.length() < terrain.ground_radius_at(p) + clearance:
			return t
	return -1.0


func _update_radar() -> void:
	var r := state.pos_bf.length()
	var up := state.pos_bf.normalized().to_vector3()
	radar_altitude = r - params.gear_drop - _gear_ground_radius(state.pos_bf, state.basis)
	vertical_speed = state.velocity.dot(up)


# --- Puertas, esclusa, tren, rampa ------------------------------------------------------------

func _crew_points() -> Array:
	var pts := []
	for a in crew_sources:
		if is_instance_valid(a):
			pts.append({"id": a.get_instance_id(), "p": to_local(a.global_position + a.global_transform.basis.y * 0.9)})
	return pts


func _update_doors(dt: float) -> void:
	var people := _crew_points()
	var locals := []
	for person in people:
		locals.append(person["p"])
	airlock.update(dt, people)
	for id in doors:
		doors[id].update(dt, locals)


func _update_gear(dt: float) -> void:
	var want := state.landed or radar_altitude < GEAR_DEPLOY_ALT or state.gear_hold
	state.gear_deployed = want or _gear_extension > 0.99
	_gear_extension = move_toward(_gear_extension, 1.0 if want else 0.0, dt * 0.5)
	if not want and _gear_extension < 0.99:
		state.gear_deployed = false
	var lift := (1.0 - _gear_extension) * 1.0
	var i := 0
	for g in dyn.get("gear", []):
		g.position.y = lift
		var s: CollisionShape3D = dyn["gear_shapes"][i]
		s.position.y = -params.gear_drop + 0.15 + lift
		i += 1
	var ramp: Node3D = dyn.get("ramp")
	var ramp_shape: CollisionShape3D = dyn.get("ramp_shape")
	if ramp != null:
		ramp.visible = state.landed
		ramp_shape.disabled = not state.landed


# --- Indicadores visuales (estado real de los sistemas) --------------------------------------

func _process(delta: float) -> void:
	if state.party:
		_update_party()
	_update_nav_lights()
	_update_room_culling()
	if params == null:
		return
	var out := state.engine_output
	var eg: StandardMaterial3D = dyn.get("engine_glow")
	if eg != null:
		eg.albedo_color = (dyn["engine_glow_color"] as Color) * (0.15 + 1.6 * out)
	var rg: StandardMaterial3D = dyn.get("reactor_glow")
	if rg != null:
		var pulse := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.004)
		rg.albedo_color = (dyn["reactor_glow_color"] as Color) * (0.35 + 1.2 * out) * pulse
	for disc in dyn.get("engine_discs", []):
		disc.scale = Vector3.ONE * (0.6 + 0.4 * out)
	for key in dyn.get("airlock_lights", {}):
		var side := "inner" if key.begins_with("inner") else "outer"
		dyn["airlock_lights"][key].albedo_color = airlock.indicator_color(side)
	_label_accum += delta
	if _label_accum >= 1.0 / LIGHT_LABEL_HZ:
		_label_accum = 0.0
		_update_labels()


func regime_name() -> String:
	return str(params.regime(state.regime).get("name", ""))


func _update_labels() -> void:
	var labels: Dictionary = dyn.get("labels", {})
	if labels.is_empty():
		return
	var ap: String = ["MANUAL", "AUTO: RUMBO", "AUTO: APROX.", "AUTO: LLAMADA", "AUTO: VIAJE"][state.autopilot]
	labels["nav"].text = "VEL %s\nOBJ %s\n%s" % [ShipParams.format_speed(state.speed()),
		ShipParams.format_speed(state.target_speed), ap]
	labels["regimen"].text = "%s\nASIST. %s\n%s" % [regime_name(), "SÍ" if state.flight_assist else "NO",
		"POSADA" if state.landed else ("TREN FUERA" if state.gear_deployed else "TREN DENTRO")]
	labels["sistemas"].text = "MOTOR %3d%%\nALT %s\nV.VERT %+.1f m/s" % [int(state.engine_output * 100.0),
		Units.format_distance(radar_altitude), vertical_speed]
	labels["maquinas"].text = "REACTOR %3d%%\nEMPUJE %3d%%\n%s" % [int(30 + state.engine_output * 70.0),
		int(state.engine_output * 100.0), "LUMÍNICO ACTIVO" if state.light_active else "NOMINAL"]
	labels["esclusa"].text = "ESCLUSA\n%s" % airlock.phase_name().to_upper()
	if labels.has("musica"):
		labels["musica"].text = "MEGAFONÍA\n%s\n%s" % ["♪ " + state.music_title if state.music_title != "" else "— en silencio —",
			"REPRODUCIENDO" if state.music_playing else "M: abrir el reproductor"]
	if labels.has("salon"):
		labels["salon"].text = "%s\n%s · ALT %s\nGRAVEDAD %s" % [regime_name().to_upper(), ShipParams.format_speed(state.speed()),
			Units.format_distance(radar_altitude), "ARTIFICIAL" if state.artificial_gravity else "REAL"]


# --- Pasajeros y piloto -----------------------------------------------------------------------

## ¿Va a bordo el jugador que mueve el origen flotante? (En el cooperativo sólo el anfitrión lo mueve.)
func _carries_origin_driver() -> bool:
	for a in passengers + seat_occupants.values():
		if is_instance_valid(a) and bool(a.get("drives_origin")):
			return true
	return pilot != null and bool(pilot.get("drives_origin"))

## Gravedad aparente en un punto de la nave (lo que siente un pasajero que no está sentado).
## Realista: gravedad del cuerpo celeste menos la aceleración del punto (lineal + rotación), con la
## compensación inercial limitando lo que se siente a INERTIAL_MAX. Si la nave se inclina, el suelo se
## inclina respecto a la gravedad; lejos de los planetas, ingravidez. Con gravedad artificial: 1 g "abajo".
func apparent_gravity(global_point: Vector3) -> Vector3:
	if state.artificial_gravity:
		return -local_up() * params.artificial_gravity
	var g := gravity_vector()
	if state.landed:
		return g
	var r := global_point - global_position
	var w := state.basis * state.ang_vel
	var a_point := accel + ang_accel.cross(r) + w.cross(w.cross(r))
	return g - a_point.limit_length(INERTIAL_MAX)


func _on_impact(strength: float) -> void:
	var told := {}
	for a in passengers + seat_occupants.values():
		if is_instance_valid(a) and not told.has(a) and a.has_method("on_ship_impact"):
			told[a] = true
			a.on_ship_impact(strength)


## La nave se estaciona sola (frena y suelta el piloto automático) cuando se queda vacía en vuelo.
func _check_empty() -> void:
	var occupied := pilot != null or not passengers.is_empty() or not seat_occupants.is_empty()
	if _was_occupied and not occupied and not state.landed \
			and state.autopilot != ShipState.Autopilot.RECALL and state.speed() > 0.5:
		autopilot.disengage(state, "nave vacía")
		model.emergency_stop(state)
		state.post_event("Nave vacía: estacionamiento automático")
	_was_occupied = occupied


func add_passenger(a: Node) -> void:
	if not passengers.has(a):
		passengers.append(a)


func remove_passenger(a: Node) -> void:
	passengers.erase(a)


func seat_transform(seat_id: String = "piloto") -> Transform3D:
	var seat: Array = ShipLayout.SEATS.get(seat_id, ShipLayout.SEATS["piloto"])
	return global_transform * Transform3D(Basis(Vector3.UP, seat[1]), seat[0])


func seat_free(seat_id: String = "piloto") -> bool:
	return not seat_occupants.has(seat_id)


## Asiento libre más cercano a un punto local (a menos de `radius` m), o "".
func nearest_free_seat(local_pos: Vector3, radius: float = 2.0) -> String:
	var best := ""
	# Con la nave inclinada cuesta acercarse (el suelo "cuesta arriba"): el alcance crece hasta +2 m.
	var g := gravity_vector()
	var tilt := 0.0
	if g.length_squared() > 1e-6:
		tilt = rad_to_deg(local_up().angle_to(-g))
	var best_d := radius + 2.0 * clampf((tilt - 8.0) / 37.0, 0.0, 1.0)
	for id in ShipLayout.SEATS:
		if seat_occupants.has(id):
			continue
		var p: Vector3 = ShipLayout.SEATS[id][0]
		var d := Vector2(local_pos.x - p.x, local_pos.z - p.z).length()
		if d < best_d:
			best_d = d
			best = id
	return best


## Puesto interactivo más cercano al alcance (ShipLayout.STATIONS) o "".
func nearest_station(local_pos: Vector3) -> String:
	var best := ""
	var best_d := ShipLayout.STATION_REACH
	for id in ShipLayout.STATIONS:
		var p: Vector3 = ShipLayout.STATIONS[id][0]
		var d := Vector2(local_pos.x - p.x, local_pos.z - p.z).length()
		if d < best_d and absf(local_pos.y + 1.0 - p.y) < 1.6:
			best_d = d
			best = id
	return best


static func is_pilot_seat(seat_id: String) -> bool:
	return bool(ShipLayout.SEATS.get(seat_id, [null, 0.0, false])[2])


func sit(a: Node, seat_id: String = "piloto") -> bool:
	if seat_occupants.has(seat_id):
		return false
	seat_occupants[seat_id] = a
	state.seats[seat_id] = a.get_instance_id()
	if is_pilot_seat(seat_id):
		pilot = a
		state.pilot_id = a.get_instance_id()
	remove_passenger(a)
	return true


func stand(a: Node) -> void:
	for id in seat_occupants.keys():
		if seat_occupants[id] == a:
			seat_occupants.erase(id)
			state.seats.erase(id)
	if pilot == a:
		pilot = null
		state.pilot_id = -1
		controls.clear()
		# Al dejar los mandos en vuelo, el piloto automático mantiene rumbo y velocidad.
		if not state.landed and state.autopilot == ShipState.Autopilot.OFF:
			if state.speed() > 1.0:
				autopilot.engage(state, ShipState.Autopilot.HOLD)
				state.autopilot_speed = state.target_speed
				state.post_event("Piloto automático activado: mantiene rumbo y velocidad")
			else:
				model.emergency_stop(state)


## Llamada a la nave (tecla B fuera de ella): vuela hasta cerca de `target_bf` y se posa.
func cmd_recall(target_bf: DVec3) -> void:
	if immobilized:
		state.post_event("La nave está inmovilizada en el hangar")
		return
	if pilot != null:
		state.post_event("La nave tiene piloto")
		return
	var radial := target_bf.normalized()
	var away := state.pos_bf.sub(target_bf).to_vector3()
	away -= radial.to_vector3() * away.dot(radial.to_vector3())
	if away.length_squared() < 1.0:
		away = state.basis.x
	var land := target_bf.add_vector3(away.normalized() * ShipAutopilot.RECALL_LAND_RADIUS)
	state.autopilot_target = land
	if state.landed:
		state.landed = false
		state.velocity = local_up() * 3.0
	state.autopilot = ShipState.Autopilot.RECALL
	state.post_event("Nave en camino")


# --- Entorno: atmósfera, Sol y casco (ADR-029) -----------------------------------------------

## Arrastre con el viento real, calentamiento (Sutton-Graves) y radiación solar, presión externa, limitador
## atmosférico de Arcade y daños del casco. Integridad 0 → rescate de emergencia (ficticio).
func _apply_environment(dt: float) -> void:
	var alt := state.pos_bf.length() - terrain.radius
	var radial := state.pos_bf.normalized().to_vector3()
	state.ext_pressure = 0.0
	state.ext_temperature = 3.0
	state.dyn_pressure = 0.0
	state.wind_speed = 0.0
	state.atmo_speed_limit = INF
	var q_conv := 0.0
	if atmo != null and atmo.present() and alt < atmo.top_altitude():
		var lat := asin(clampf(radial.y, -1.0, 1.0))
		var east := Vector3.UP.cross(radial)
		east = east.normalized() if east.length_squared() > 1e-8 else Vector3.RIGHT
		var u := atmo.zonal_wind(lat, alt)
		state.wind_speed = u
		var v_rel := state.velocity - east * u
		var rho := atmo.density(alt)
		var vr := v_rel.length()
		state.ext_pressure = atmo.pressure(alt)
		state.ext_temperature = atmo.temperature(alt)
		state.dyn_pressure = 0.5 * rho * vr * vr
		# En viaje automático no hay arrastre ni limitador (FICTICIO, ADR-031): si no, salir desde cientos de bar
		# en Júpiter llevaría media hora a la velocidad segura.
		var traveling := state.autopilot == ShipState.Autopilot.TRAVEL
		if vr > 0.01 and not traveling:
			var a := 0.5 * rho * DRAG_CDA / params.mass_kg * vr * vr
			state.velocity -= v_rel / vr * minf(a * dt, vr * 0.5)
		q_conv = atmo.heat_flux(alt, vr)
		if state.arcade and not params.is_light(state.regime) and not traveling:
			state.atmo_speed_limit = maxf(atmo.safe_speed(alt), 50.0)
	# Radiación del Sol absorbida (absortancia 0,3, una cara).
	var q_sun := 0.0
	var t_sun := 0.0
	if system != null:
		var sun_rel := system.position_in_frame("sun", body_def.id).sub(state.pos_bf)
		var d_sun := sun_rel.length()
		var sun: BodyDef = system.body("sun")
		q_sun = 0.3 * sun.physical("luminosity", 3.828e26) / (4.0 * PI * d_sun * d_sun)
		t_sun = pow(q_sun / (HULL_EMISSIVITY * SIGMA), 0.25)
		if d_sun < sun.radius_m() * 1.02:
			state.hull_integrity = 0.0
	state.heat_flux = q_conv + q_sun
	var t_eq := maxf(state.ext_temperature, pow(state.heat_flux / (HULL_EMISSIVITY * SIGMA), 0.25))
	state.hull_temperature = lerpf(state.hull_temperature, t_eq, 1.0 - exp(-dt / 6.0))
	state.plasma = clampf((q_conv - 1.0e5) / 1.0e6, 0.0, 1.0)
	# Daños (FICTICIO, por jugabilidad): la nave puede entrar en cualquier planeta para ver su atmósfera (sin
	# aplastamiento ni quemaduras de entrada); sólo el calor del Sol daña el casco.
	var dmg := 0.0
	if t_sun > HULL_TEMP_LIMIT:
		dmg += (t_sun / HULL_TEMP_LIMIT - 1.0) * 60.0
	if dmg > 0.0:
		state.hull_integrity = maxf(0.0, state.hull_integrity - dmg * dt)
	# Turbulencia: sacudidas para los pasajeros proporcionales a la presión dinámica.
	if state.dyn_pressure > 2000.0:
		var tr := clampf(state.dyn_pressure / 4.0e5, 0.0, 0.15) * dt * 4.0
		for a2 in passengers + seat_occupants.values():
			if is_instance_valid(a2) and a2.get("cam") != null:
				a2.cam.add_trauma(tr)
	if state.hull_integrity <= 0.0:
		_emergency_rescue()


## Rescate de emergencia (FICTICIO, por jugabilidad): la nave reaparece intacta a 3 radios del cuerpo dominante.
func _emergency_rescue() -> void:
	var radial := state.pos_bf.normalized()
	var r := maxf(terrain.radius * 3.0, terrain.radius + 200000.0)
	state.pos_bf = radial.mul(r)
	state.velocity = Vector3.ZERO
	state.target_speed = 0.0
	state.hull_integrity = 100.0
	state.hull_temperature = 290.0
	state.warp = 1.0
	if params.is_light(state.regime):
		state.regime = 0
		state.light_active = false
	autopilot.disengage(state, "casco destruido")
	state.post_event("¡CASCO DESTRUIDO! Rescate de emergencia: la nave reaparece en órbita alta")


## Piloto automático de viaje a otro cuerpo del Sistema Solar (ADR-028).
func cmd_travel(target_id: String) -> void:
	if system == null or not system.has_body(target_id):
		return
	if state.landed:
		state.landed = false
		state.velocity = local_up() * 5.0
	state.travel_target = target_id
	state.autopilot = ShipState.Autopilot.TRAVEL
	state.post_event("Rumbo a %s" % system.body(target_id).display_name)


## Cada paso del viaje: dirección al destino, despegue vertical si se está junto al suelo, y ley de velocidad
## (llegar en ~12 s de "cola" exponencial). Lejos de los cuerpos (≥ 3 radios) usa el motor lumínico con un
## salto automático de hasta 1000 c para que el viaje dure minutos (FICTICIO, documentado en ADR-028).
func _update_travel() -> void:
	var anchor := body_def.id
	var tgt := state.travel_target
	var tb: BodyDef = system.body(tgt)
	if tb == null:
		autopilot.disengage(state, "destino desconocido")
		return
	var to := system.position_in_frame(tgt, anchor).sub(state.pos_bf)
	var dist := to.length()
	var r_t := tb.radius_m() * (float(tb.surface().get("expansion", 1.0)) if tb.surface_type() == "shattered" else 1.0)
	var arrive := maxf(r_t * 2.5, r_t + 30000.0)
	var remaining := dist - arrive
	state.travel_remaining = remaining
	if remaining <= maxf(500.0, arrive * 0.002):
		# Llegada: frenar y quedar NIVELADO con el horizonte del cuerpo dominante (piloto automático de rumbo).
		model.emergency_stop(state)
		state.warp = 1.0
		var up_r := state.pos_bf.normalized().to_vector3()
		var fwd_h := state.forward() - up_r * state.forward().dot(up_r)
		if fwd_h.length_squared() < 1e-6:
			fwd_h = state.basis.y - up_r * state.basis.y.dot(up_r)
		state.autopilot = ShipState.Autopilot.HOLD
		state.autopilot_heading = fwd_h.normalized()
		state.autopilot_up = up_r
		state.autopilot_speed = 0.0
		state.travel_target = ""
		# Ronda 11: indicar cómo seguir (antes la nave quedaba quieta a miles de km y parecía atascada).
		if tb.has_solid_surface():
			state.post_event("Llegada a %s · pulsa T para el aterrizaje automático (o baja con Ctrl)" % tb.display_name)
		else:
			state.post_event("Llegada a %s · sin superficie sólida: T para descender hasta las nubes" % tb.display_name)
		return
	var dir := to.mul(1.0 / maxf(dist, 1.0)).to_vector3()
	var radial := state.pos_bf.normalized().to_vector3()   # vertical del cuerpo (no el "arriba" de la nave)
	var r_anchor := terrain.radius
	var alt := state.pos_bf.length() - r_anchor
	state.travel_free = not terrain.solid
	state.travel_climb = anchor != tgt and terrain.solid and radar_altitude < 400.0
	if state.travel_climb:
		# Ascenso vertical nivelado: junto al suelo no se cabecea (el casco tocaría el terreno).
		var fwd := state.forward() - radial * state.forward().dot(radial)
		dir = fwd.normalized() if fwd.length_squared() > 1e-6 else dir
	elif anchor != tgt and terrain.solid and alt < 3000.0:
		dir = (radial * 0.85 + dir * 0.15).normalized()  # después, alejarse del suelo
	elif anchor != tgt:
		# Evasión: si la recta al destino atraviesa el cuerpo dominante (o pasa muy cerca del Sol), se sube y se
		# rodea: dirección = vertical + componente tangencial hacia el destino, hasta tener la línea libre.
		var keep := r_anchor * (3.0 if anchor == "sun" else 1.15)
		var p0 := state.pos_bf.to_vector3()
		var tc := clampf(-p0.dot(dir), 0.0, dist)
		var closest := (p0 + dir * tc).length()
		if closest < keep and tc > 0.0:
			var tang := dir - radial * dir.dot(radial)
			tang = tang.normalized() if tang.length_squared() > 1e-8 else state.basis.x
			dir = (radial * 0.7 + tang * 0.7).normalized()
	state.travel_dir = dir
	# Frenado exponencial con constante de 5 s y un mínimo de 500 m/s: cualquier viaje dura 1-2 minutos.
	var v_des := remaining / 5.0 + 500.0
	var near := state.pos_bf.length() < 3.0 * r_anchor
	var li := params.light_index()
	if near or li < 0:
		if params.is_light(state.regime):
			state.regime = 0 if state.arcade else 2
			state.light_active = false
		state.warp = 1.0
	else:
		if not params.is_light(state.regime):
			model.set_regime(state, li, state.pos_bf.length(), r_anchor)
		state.warp = clampf(v_des / ShipParams.C, 1.0, 1000.0)
	# Sólo se acelera con el morro apuntando al destino.
	var facing := state.forward().dot(dir)
	model.set_target(state, v_des * clampf((facing - 0.6) / 0.35, 0.0, 1.0))


## Ocultación de salas (ronda 9): con algún jugador local dentro, una sala sólo se dibuja si alguien está en ella o
## su puerta está abierta (desde dentro no hay otra forma de verla). Desde fuera se ven todas por las ventanas.
const ROOM_DOOR := {"comedor": "comedor", "dormitorios": "dormitorios", "almacen": "almacen", "enfermeria": "enfermeria",
	"bano": "bano", "esclusa": "esclusa_int", "vestuario": "vestuario", "salon": "salon", "maquinas": "maquinas", "cabina": "cabina"}


func _update_room_culling() -> void:
	var rooms: Dictionary = dyn.get("room_meshes", {})
	if rooms.is_empty():
		return
	var inside_rooms := {}
	var anyone_outside := false
	for a in crew_sources:
		if not is_instance_valid(a) or a.get("pin") == null:
			continue
		if a.aboard == self or a.seated:
			inside_rooms[ShipLayout.room_at(to_local(a.global_position) + Vector3(0, 0.9, 0))] = true
		else:
			anyone_outside = true
	for batch in rooms:
		var room := str(batch).trim_prefix("int:")
		if not str(batch).begins_with("int:") or room.begins_with("pasillo"):
			continue
		var vis := true
		if not anyone_outside and not inside_rooms.is_empty() and ROOM_DOOR.has(room) and not inside_rooms.has(room):
			var door: ShipDoor = doors.get(ROOM_DOOR[room])
			vis = door == null or door.open > 0.01
		for mi in rooms[batch]:
			mi.visible = vis


## Luces de navegación: las de posición fijas, estroboscópicas blancas cada 1,2 s y baliza roja pulsante.
## Posada y sin nadie a los mandos, sólo queda la baliza.
func _update_nav_lights() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for e in dyn.get("nav_blink", []):
		var m: StandardMaterial3D = e[0]
		var c: Color = e[1]
		var k := 1.0
		match str(e[2]):
			"strobe":
				k = 1.6 if fmod(t, 1.2) < 0.08 or (fmod(t, 1.2) > 0.2 and fmod(t, 1.2) < 0.26) else 0.05
				if state.landed and pilot == null:
					k = 0.05
			"beacon":
				k = 0.25 + 1.3 * pow(maxf(sin(t * TAU * 0.7), 0.0), 6.0)
			"steady":
				k = 1.0 if not state.landed or pilot != null else 0.35
		m.albedo_color = c * k


## Modo fiesta (tecla P a bordo): todas las luces interiores se vuelven de discoteca.
func cmd_toggle_party() -> void:
	state.party = not state.party
	if not state.party:
		for e in dyn.get("lights", []):
			e[0].light_color = e[1]
			e[0].light_energy = e[2]
		for m in dyn.get("party_mats", []):
			m[0].albedo_color = m[1]
	state.post_event("MODO FIESTA %s" % ("ACTIVADO" if state.party else "desactivado"))


func _update_party() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var beat := 0.55 + 0.45 * pow(absf(sin(t * PI * 2.0)), 4.0)   # ~120 pulsaciones por minuto
	var lights: Array = dyn.get("lights", [])
	for i in lights.size():
		var l: OmniLight3D = lights[i][0]
		l.light_color = Color.from_hsv(fmod(t * 0.35 + float(i) * 0.137, 1.0), 0.9, 1.0)
		l.light_energy = float(lights[i][2]) * (0.6 + 1.2 * beat * (0.6 + 0.4 * sin(t * 7.0 + float(i))))
	var k := 0
	for m in dyn.get("party_mats", []):
		m[0].albedo_color = Color.from_hsv(fmod(t * 0.5 + float(k) * 0.25, 1.0), 0.85, 1.0) * (0.6 + beat)
		k += 1


## Gravedad artificial (tecla G en un asiento): comodidad frente a realismo.
func cmd_toggle_artificial_gravity() -> void:
	state.artificial_gravity = not state.artificial_gravity
	state.post_event("Gravedad artificial %s" % ("ACTIVADA (1 g hacia el suelo)" if state.artificial_gravity else "DESACTIVADA (gravedad e inercia reales)"))


## Acciones de pilotaje discretas (las llama ShipPilotInput).
func cmd_set_regime(i: int) -> void:
	if model.set_regime(state, i, state.pos_bf.length(), terrain.radius):
		state.post_event("Régimen: %s" % regime_name())


func cmd_stop() -> void:
	model.emergency_stop(state)
	if state.autopilot != ShipState.Autopilot.OFF:
		state.autopilot_speed = 0.0
	state.post_event("Velocidad objetivo: 0")


func cmd_adjust_target(factor: float) -> void:
	var v := state.target_speed
	if absf(v) < 1.0:
		v = signf(factor - 1.0) * maxf(1.0, params.regime_max_speed(state.regime) * 0.01)
	else:
		v *= factor
	model.set_target(state, v)
	if state.autopilot != ShipState.Autopilot.OFF:
		state.autopilot_speed = state.target_speed


func cmd_toggle_autopilot(mode: int) -> void:
	if state.autopilot == mode:
		autopilot.disengage(state, "a petición del piloto")
	else:
		autopilot.engage(state, mode)


## Motor lumínico (arcade: L). Requiere estar lejos de cuerpos masivos.
func cmd_toggle_light() -> void:
	var li := params.light_index()
	if params.is_light(state.regime):
		var back := maxi(0, li - 1)
		state.regime = back
		state.light_active = false
		if state.velocity.length() > params.regime_max_speed(back):
			state.velocity = state.velocity.normalized() * params.regime_max_speed(back)
		model.set_target(state, minf(state.target_speed, params.regime_max_speed(back)))
		state.post_event("Motor lumínico desactivado")
	elif model.set_regime(state, li, state.pos_bf.length(), terrain.radius):
		model.set_target(state, ShipParams.C)
		state.post_event("Cargando motor lumínico…")


## Focos exteriores (K): iluminan el terreno delante y debajo de la nave (útil en la cara nocturna).
func cmd_toggle_floodlights() -> void:
	state.floodlights = not state.floodlights
	for l in dyn.get("floodlights", []):
		l.visible = state.floodlights
	state.post_event("Focos exteriores %s" % ("encendidos" if state.floodlights else "apagados"))


## Tren de aterrizaje (U): automático (se despliega cerca del suelo) o desplegado siempre.
func cmd_toggle_gear() -> void:
	state.gear_hold = not state.gear_hold
	state.post_event("Tren de aterrizaje: %s" % ("DESPLEGADO" if state.gear_hold else "automático"))


## El modo de vuelo se toma de los ajustes al sentarse (cada piloto el suyo).
func set_arcade(on: bool) -> void:
	state.arcade = on
	if on and not params.is_light(state.regime):
		state.regime = 0
	model.set_target(state, state.target_speed)


func cmd_toggle_assist() -> void:
	state.flight_assist = not state.flight_assist
	state.post_event("Asistencia de vuelo: %s" % ("activada" if state.flight_assist else "DESACTIVADA (newtoniano)"))
