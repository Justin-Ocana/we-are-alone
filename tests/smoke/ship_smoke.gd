extends Node
## Prueba de integración del Hito 2 (headless, --fixed-fps 60). Recorre los criterios de aceptación con
## física real: entrar por la esclusa caminando, visitar las 8 áreas, sentarse, despegar, acelerar con
## velocidad objetivo, piloto automático, caminar mientras la nave se mueve y gira, aterrizar, salir,
## cámara exterior y modo lumínico. Además (ADR-018/019): gravedad aparente al inclinarse la nave, piloto
## automático al levantarse, asiento de copiloto, estacionamiento de la nave vacía, caída libre con giro,
## estabilización, daño y desmayo al caer, y llamada de la nave (B).
## Sale con código = nº de comprobaciones fallidas.

const WAYPOINT_TIMEOUT := 25.0
const AREAS := ["cabina", "comedor", "dormitorios", "bano", "maquinas", "almacen", "enfermeria", "esclusa"]

var main: Node
var world: SurfaceWorld
var ship: Ship
var pl: Astronaut
var failures := 0
var checks := 0

var _step := 0
var _t := 0.0
var _route: Array = []          ## [Vector3 local de la nave, etiqueta]
var _route_i := 0
var _wp_t := 0.0
var _visited := {}
var _both_doors_open := false
var _min_local_y := INF
var _left_ship := false
var _heading0 := Vector3.ZERO
var _p0: DVec3
var _dist_integral := 0.0
var _speed_1s := 0.0
var _route_done := false
var _route_ok := true
var _fell_floating := false
var _max_spin := 0.0
var _health_before := 0.0


func _ready() -> void:
	world = main.start_world("moon", -20.0, 140.0, false, true)
	print("SHIP-SMOKE: inicio")


func check(cond: bool, what: String) -> void:
	checks += 1
	if cond:
		print("  PASA  ", what)
	else:
		failures += 1
		print("  FALLA ", what)


func _release_all() -> void:
	for a in [&"move_forward", &"sprint", &"ship_up", &"ship_down", &"ship_throttle_up", &"ship_roll_left", &"jump", &"stabilize"]:
		Input.action_release(a)


func _next(step: int) -> void:
	_release_all()
	_step = step
	_t = 0.0


func _physics_process(delta: float) -> void:
	if world == null or not world.surface_ready or world.ship == null:
		return
	ship = world.ship
	pl = world.player
	_t += delta
	# Invariantes continuas.
	if ship.airlock.inner.open > 0.02 and ship.airlock.outer.open > 0.02:
		_both_doors_open = true
	if pl.aboard != null and not pl.seated:
		_min_local_y = minf(_min_local_y, ship.to_local(pl.global_position).y)
	match _step:
		0:
			check(ship.state.landed, "la nave aparece posada (alt. radar %.2f m)" % ship.radar_altitude)
			check(ship.dyn["mesh_count"] < 160, "geometría agrupada: %d mallas, %d formas de colisión" % [ship.dyn["mesh_count"], ship.dyn["shape_count"]])
			# Se coloca al astronauta a 3 m del pie de la rampa, fuera de la nave.
			_teleport_local(Vector3(19.0, -2.0, -3.0), PI / 2)
			check(pl.aboard == null, "el astronauta empieza fuera de la nave")
			_route = [[Vector3(16.6, 0, -3.0), "pie de la rampa"], [Vector3(11.5, 0, -3.0), "rampa"],
				[Vector3(5.0, 0, -3.0), "esclusa"], [Vector3(0.0, 0, -3.0), "pasillo"]]
			_route.append_array(_area_tour())
			_start_route()
			_next(1)
		1:
			if _follow_route(delta):
				check(_route_ok, "recorrido completo a pie por el interior")
				for a in AREAS:
					check(_visited.has(a), "área visitada: %s (%s)" % [ShipLayout.ROOMS[a][0], ShipLayout.ROOMS[a][1]])
				check(not _both_doors_open, "la esclusa nunca abrió ambas puertas a la vez")
				check(_min_local_y > -0.15, "nunca por debajo del suelo de la nave (mín. %.3f m)" % _min_local_y)
				var g_moon := world.body.gravity_at_distance(pl.position_bf().length())
				check(pl.aboard == ship and absf(pl.gravity_mps2 - g_moon) < 0.01, "a bordo, nave posada: gravedad aparente = la de la Luna (%.3f m/s²)" % pl.gravity_mps2)
				_next(2)
		2:
			# Sentarse a pilotar.
			pl._interact()
			check(pl.seated and ship.pilot == pl, "el astronauta se sienta en el puesto de pilotaje (asiento '%s', sentado %s, local %s)" % [
				pl.seat_id, pl.seated, str(ship.to_local(pl.global_position).snapped(Vector3.ONE * 0.01))])
			check(ship.state.arcade == (GameSettings.flight_mode == "arcade"), "modo de vuelo tomado de los ajustes")
			# Este recorrido valida la física del modo simulación; el arcade tiene sus propias pruebas.
			ship.set_arcade(false)
			pl.pilot_input.arcade = false
			check(pl.interaction_hint.contains("Levantarse"), "indicación de interacción para levantarse")
			_next(3)
			Input.action_press(&"ship_up")
		3:
			if _t > 5.0:
				Input.action_release(&"ship_up")
				check(not ship.state.landed and ship.radar_altitude > 15.0, "despegue vertical (alt. radar %.1f m)" % ship.radar_altitude)
				ship.cmd_set_regime(0)
				ship.model.set_target(ship.state, 40.0)
				_p0 = ship.state.pos_bf.copy()
				_next(4)
		4:
			if absf(_t - 1.0) < delta * 0.5:
				_speed_1s = ship.state.forward_speed()
			if _t > 14.0:
				check(_speed_1s < 25.0, "aceleración gradual: %.1f m/s tras 1 s (objetivo 40)" % _speed_1s)
				check(absf(ship.state.forward_speed() - 40.0) < 2.0, "alcanza la velocidad objetivo (%.1f m/s)" % ship.state.forward_speed())
				# Cámara exterior.
				world.view.ship_exterior = true
				_next(5)
		5:
			if _t > 1.0:
				var cam := world.view.active_camera()
				var d := cam.global_position.distance_to(ship.global_position)
				check(cam == world.view.ship_camera, "cámara exterior activa")
				check(d > 20.0 and d < 80.0, "la cámara exterior sigue a la nave real (a %.1f m)" % d)
				world.view.ship_exterior = false
				ship.cmd_toggle_autopilot(ShipState.Autopilot.HOLD)
				_heading0 = ship.state.forward()
				_next(6)
		6:
			if _t > 10.0:
				var err := rad_to_deg(ship.state.forward().angle_to(_heading0))
				check(ship.state.autopilot == ShipState.Autopilot.HOLD, "piloto automático activo")
				check(err < 2.0, "mantiene el rumbo (error %.2f°)" % err)
				check(absf(ship.state.forward_speed() - 40.0) < 2.0, "mantiene la velocidad (%.1f m/s)" % ship.state.forward_speed())
				_next(7)
				Input.action_press(&"ship_roll_left")
		7:
			if _t > 0.3:
				check(ship.state.autopilot == ShipState.Autopilot.OFF, "la entrada manual recupera el control")
				Input.action_release(&"ship_roll_left")
				# Piloto automático de nuevo y el piloto se levanta: la nave sigue volando sola.
				ship.cmd_toggle_autopilot(ShipState.Autopilot.HOLD)
				# Para caminar mientras la nave gira se activa la gravedad artificial (G): con la gravedad real,
				# los giros empujarían al astronauta contra las paredes (se prueba aparte).
				ship.cmd_toggle_artificial_gravity()
				pl._interact()
				check(not pl.seated and pl.aboard == ship and ship.pilot == null, "el piloto se levanta con la nave en vuelo")
				check(ship.controls.manual_magnitude() == 0.0, "los mandos quedan liberados al levantarse")
				check(world.view.active_camera() == pl.cam.fp_camera or not world.view.ship_exterior, "cámara correcta tras levantarse")
				_route = [[Vector3(0, 0, -17.0), "arco"], [Vector3(0, 0, 8.0), "pasillo"],
					[ShipLayout.door_approach("maquinas", 1.0), "puerta máquinas"], [Vector3(-3.0, 0, 13.0), "sala de máquinas"]]
				_start_route()
				_next(8)
		8:
			# Mientras camina, la nave gira (rumbo nuevo a 60° y luego otro).
			if absf(_t - 1.0) < delta * 0.5:
				ship.state.autopilot_heading = ship.state.forward().rotated(ship.local_up(), deg_to_rad(60.0))
			if absf(_t - 6.0) < delta * 0.5:
				ship.state.autopilot_heading = ship.state.forward().rotated(ship.state.basis.x, deg_to_rad(20.0))
			if pl.aboard != ship:
				_left_ship = true
			if _follow_route(delta):
				check(_route_ok and not _left_ship, "camina hasta la sala de máquinas con la nave moviéndose y girando")
				check(ship.music.speaker_mix > 0.95, "música: fuera del puente suena por los altavoces (%.2f)" % ship.music.speaker_mix)
				check(ship.state.speed() > 30.0, "la nave seguía en movimiento (%.1f m/s)" % ship.state.speed())
				check(_min_local_y > -0.15, "sin atravesar el suelo durante el vuelo (mín. %.3f m)" % _min_local_y)
				ship.cmd_toggle_artificial_gravity()
				_route = [[Vector3(0, 0, 8.0), "pasillo"], [Vector3(0, 0, -17.5), "cabina"], [Vector3(0, 0, -22.0), "asiento"]]
				_start_route()
				_next(9)
		9:
			if _follow_route(delta):
				pl._interact()
				check(pl.seated, "vuelve a sentarse")
				ship.cmd_toggle_autopilot(ShipState.Autopilot.HOLD)  # desactiva
				# Levantarse en marcha sin piloto automático: se activa solo y mantiene rumbo y velocidad.
				pl._interact()
				check(ship.state.autopilot == ShipState.Autopilot.HOLD and ship.state.speed() > 30.0,
					"al dejar los mandos en marcha se activa el piloto automático (%.1f m/s)" % ship.state.speed())
				pl._interact()
				check(pl.seated, "se sienta de nuevo")
				var v0 := ship.state.speed()
				ship.cmd_stop()
				_speed_1s = v0
				_next(10)
		10:
			if absf(_t - 2.0) < delta * 0.5:
				check(ship.state.speed() < 0.6, "frenado de emergencia: de %.0f m/s a %.2f m/s en 2 s" % [_speed_1s, ship.state.speed()])
			if _t > 6.0:
				# Nivelar la nave, levantarse e inclinarla 25°: sin gravedad artificial, el astronauta lo nota.
				_level_ship()
				pl._interact()
				check(not pl.seated, "se levanta con la nave en vuelo estacionario")
				ship.set_arcade(false)  # sin autonivelado: la inclinación se mantiene durante la prueba
				ship.autopilot.disengage(ship.state, "prueba")
				_set_ship_basis(Basis(ship.state.forward(), deg_to_rad(25.0)) * ship.state.basis)
				_next(30)
		30:
			if _t > 4.0:
				var radial := pl.position_bf().normalized().to_vector3()
				var to_g := rad_to_deg(pl.global_transform.basis.y.angle_to(radial))
				var to_ship := rad_to_deg(pl.global_transform.basis.y.angle_to(ship.local_up()))
				check(to_g < 6.0 and absf(to_ship - 25.0) < 6.0,
					"gravedad real a bordo: el cuerpo sigue la vertical del planeta (%.1f°), no la de la nave (%.1f°)" % [to_g, to_ship])
				check(pl.aboard == ship and ship.to_local(pl.global_position).y > -0.3, "sigue dentro de la nave, sin atravesar el suelo")
				# Arcade (autonivelado) + piloto automático de rumbo: debe conservar la inclinación actual.
				ship.set_arcade(true)
				ship.cmd_toggle_autopilot(ShipState.Autopilot.HOLD)
				_next(33)
		33:
			if _t > 3.0:
				var tilt := rad_to_deg(ship.local_up().angle_to(ship.state.pos_bf.normalized().to_vector3()))
				check(ship.state.autopilot == ShipState.Autopilot.HOLD and absf(tilt - 25.0) < 4.0,
					"el piloto automático conserva la inclinación actual (%.1f°)" % tilt)
				ship.autopilot.disengage(ship.state, "prueba")
				ship.set_arcade(false)
				# Gravedad artificial (G): aunque la nave quede de costado (90°), el astronauta sigue de pie en su suelo.
				ship.cmd_toggle_artificial_gravity()
				_set_ship_basis(Basis(ship.state.forward(), deg_to_rad(65.0)) * ship.state.basis)
				_next(34)
		34:
			if _t > 3.0:
				var to_ship := rad_to_deg(pl.global_transform.basis.y.angle_to(ship.local_up()))
				var tilt := rad_to_deg(ship.local_up().angle_to(ship.state.pos_bf.normalized().to_vector3()))
				check(ship.state.artificial_gravity and to_ship < 6.0 and not pl.floating and ship.to_local(pl.global_position).y > -0.3,
					"gravedad artificial: con la nave a %.0f° sigue de pie sobre el suelo de la nave (%.1f°)" % [tilt, to_ship])
				ship.cmd_toggle_artificial_gravity()
				_level_ship()
				_teleport_local(Vector3(0, 0, -21.7), 0.0)
				_next(31)
		31:
			if _t > 1.0:
				pl._interact()
				check(pl.seated and pl.is_piloting(), "vuelve al puesto de pilotaje")
				check(ship.music.speaker_mix < 0.05 and ship.music.presence > 0.95, "música: en el puente se oye limpia (altavoces %.2f)" % ship.music.speaker_mix)
				_next(11)
				Input.action_press(&"ship_down")
		11:
			if fmod(_t, 5.0) < delta:
				var radial := ship.state.pos_bf.normalized().to_vector3()
				print("  DESC t=%.0f alt=%.2f vvert=%.2f v=%.2f incl=%.1f° tren=%s ap=%d asist=%s strafe=%s" % [_t, ship.radar_altitude, ship.vertical_speed, ship.state.speed(), rad_to_deg(ship.state.basis.y.angle_to(radial)), ship.state.gear_deployed, ship.state.autopilot, ship.state.flight_assist, str(ship.controls.strafe)])
			if ship.state.landed:
				check(true, "aterrizaje suave con asistencia (%.1f s)" % _t)
				pl._interact()
				check(not pl.seated, "se levanta tras aterrizar")
				# Asiento de copiloto: se sienta sin tomar los mandos.
				_teleport_local(Vector3(2.4, 0, -21.6), 0.0)
				_next(32)
		32:
			if _t > 0.5:
				pl._interact()
				check(pl.seated and pl.seat_id == "copiloto" and ship.pilot == null and not pl.is_piloting(),
					"se sienta en el asiento del copiloto sin tomar los mandos")
				pl._interact()
				check(not pl.seated and ship.seat_free("copiloto"), "se levanta del asiento del copiloto")
				_route = [[Vector3(0, 0, -17.0), "arco"], [Vector3(0.0, 0, -3.0), "pasillo"], [Vector3(5.0, 0, -3.0), "esclusa"],
					[Vector3(11.5, 0, -3.0), "rampa"], [Vector3(18.5, 0, -3.0), "fuera"]]
				_start_route()
				_next(12)
			elif _t > 120.0:
				check(false, "no aterrizó a tiempo")
				_finish()
		12:
			if _follow_route(delta):
				check(_route_ok, "sale por la esclusa y la rampa")
				check(pl.aboard == null, "fuera de la nave")
				var g := world.body.gravity_at_distance(pl.position_bf().length())
				check(absf(pl.gravity_mps2 - g) < 1e-6, "vuelve la gravedad planetaria (%.4f m/s²)" % pl.gravity_mps2)
				check(not _both_doors_open, "la esclusa nunca abrió ambas puertas a la vez")
				_next(13)
		13:
			if _t > 2.0:
				check(pl.is_on_floor() and absf(pl.altitude_m) < 0.8, "de pie sobre el terreno (alt. %.2f m)" % pl.altitude_m)
				# Nave en vuelo con un pasajero que "se baja": al quedarse vacía se estaciona sola.
				var radial := ship.state.pos_bf.normalized()
				var east := ship.state.basis.x
				ship.state.landed = false
				ship.state.pos_bf = ship.state.pos_bf.add_vector3(radial.to_vector3() * 150.0 - east * 400.0)
				ship.state.velocity = ship.state.forward() * 20.0
				ship.model.set_target(ship.state, 20.0)
				ship.cmd_toggle_autopilot(ShipState.Autopilot.HOLD)
				# "Alguien acaba de bajarse": se simula el paso de ocupada a vacía (añadir al astronauta, que está en
				# el suelo, lo arrastraría con la nave teletransportada: el traslado conserva la pose relativa).
				ship._was_occupied = true
				_next(40)
		40:
			if _t > 0.5:
				check(ship.state.autopilot == ShipState.Autopilot.OFF and (ship.state.braking or ship.state.speed() < 2.0)
					and ship.state.event_text.begins_with("Nave vacía"),
					"nave vacía en vuelo: estacionamiento automático (%s; ap %d, frenando %s, %.1f m/s)" % [ship.state.event_text,
					ship.state.autopilot, ship.state.braking, ship.state.speed()])
				# Caída libre: salir de una nave en marcha a 60 m de altura (se hereda un giro).
				_health_before = pl.health
				pl._exit_spin = Vector3(0.8, 0.3, 0.0)
				pl._exit_spin_t = 8.0
				# A un lado de la nave (ya detenida por el estacionamiento automático): si no, el astronauta caería
				# sobre su techo en lugar de al suelo.
				var up := pl.position_bf().normalized().to_vector3()
				var side := ship.global_transform.basis.x
				pl.global_position += up * 35.0 + (side - up * side.dot(up)).normalized() * 90.0
				pl.velocity = Vector3.ZERO
				_next(41)
		41:
			if pl.floating:
				_fell_floating = true
				_max_spin = maxf(_max_spin, pl.ang_vel.length())
			if absf(_t - 1.5) < delta * 0.5:
				check(_fell_floating and _max_spin > 0.6, "caída libre: cuerpo flotando y girando (%.2f rad/s)" % _max_spin)
				Input.action_press(&"stabilize")
			if absf(_t - 3.5) < delta * 0.5:
				Input.action_release(&"stabilize")
				check(pl.ang_vel.length() < 0.05 and pl.jet_fuel < 1.0,
					"X estabiliza el giro (%.3f rad/s, combustible %.0f %%)" % [pl.ang_vel.length(), pl.jet_fuel * 100.0])
			if _t > 2.0 and not pl.floating:
				check(pl.health < _health_before and pl.aboard == null, "el golpe al caer de 35 m hace daño sin matar (salud %.0f)" % pl.health)
				_health_before = pl.health
				_next(42)
			elif _t > 30.0:
				check(false, "no llegó al suelo")
				_next(42)
		42:
			if _t > FAINT_WAIT:
				var radial := pl.position_bf().normalized().to_vector3()
				check(pl.health > _health_before and not pl.input_blocked, "sin desmayo: la salud se regenera (%.0f → %.0f)" % [_health_before, pl.health])
				check(pl.is_on_floor() and rad_to_deg(pl.global_transform.basis.y.angle_to(radial)) < 8.0,
					"de pie y erguido tras la caída (%.1f°)" % rad_to_deg(pl.global_transform.basis.y.angle_to(radial)))
				# Llamar a la nave (B): vuela hasta el astronauta y se posa cerca.
				pl._recall_ship()
				check(ship.state.autopilot == ShipState.Autopilot.RECALL, "llamada a la nave aceptada (piloto=%s, aviso='%s', a bordo=%s, asiento=%s)" % [
					str(ship.pilot), ship.state.event_text, str(pl.aboard), str(pl.seated)])
				_next(43)
		43:
			var d := pl.global_position.distance_to(ship.global_position)
			if ship.state.landed:
				check(d < 70.0, "la nave llamada se posa cerca del astronauta (a %.0f m, %.0f s)" % [d, _t])
				_next(44)
			elif _t > 150.0:
				check(false, "la nave llamada no llegó (a %.0f m, alt %.0f m)" % [d, ship.radar_altitude])
				_next(44)
		44:
			if _t > 0.5:
				# Modo lumínico: rechazado junto al planeta.
				var before := ship.state.regime
				ship.cmd_set_regime(ship.params.light_index())
				check(ship.state.regime == before, "modo lumínico rechazado junto al planeta")
				# Nave vacía: se lleva a 4 radios y se activa.
				var r := world.terrain.radius * 4.0
				ship.state.landed = false
				ship.state.pos_bf = ship.state.pos_bf.normalized().mul(r)
				ship.state.basis = Basis(ship.state.basis.x, ship.state.basis.z, -ship.state.pos_bf.normalized().to_vector3()).orthonormalized()
				ship.state.basis = Basis.looking_at(ship.state.pos_bf.normalized().to_vector3(), ship.state.basis.y)
				ship.cmd_set_regime(ship.params.light_index())
				check(ship.params.is_light(ship.state.regime), "modo lumínico aceptado a 4 radios")
				ship.model.set_target(ship.state, ShipParams.C)
				_p0 = ship.state.pos_bf.copy()
				_dist_integral = 0.0
				_next(14)
		14:
			_dist_integral += ship.state.speed() * delta
			if _t > 14.0:
				var frac := ship.state.speed() / ShipParams.C
				var moved := ship.state.pos_bf.distance_to(_p0)
				check(ship.state.light_active and frac > 0.9 and frac <= 1.0, "velocidad lumínica alcanzada (%.3f c), nunca superior a c" % frac)
				check(absf(moved - _dist_integral) / maxf(moved, 1.0) < 0.02, "desplazamiento coherente: %s (integral %s)" % [Units.format_distance(moved), Units.format_distance(_dist_integral)])
				_finish()


const FAINT_WAIT := 9.0


func _level_ship() -> void:
	var radial := ship.state.pos_bf.normalized().to_vector3()
	var fwd := ship.state.forward()
	fwd = (fwd - radial * fwd.dot(radial)).normalized()
	_set_ship_basis(Basis(radial.cross(-fwd).normalized(), radial, -fwd))


## Cambia la orientación de la nave llevando consigo a los pasajeros (como haría un giro real).
func _set_ship_basis(b: Basis) -> void:
	var old_xf := ship.global_transform
	ship.state.basis = b
	var new_xf := ship.local_transform()
	ship.global_transform = new_xf
	ship._push_physics_transform()
	for p in ship.passengers:
		p.carry(new_xf * old_xf.affine_inverse())


func _teleport_local(local: Vector3, yaw: float) -> void:
	var xf := ship.global_transform * Transform3D(Basis(Vector3.UP, yaw), local)
	pl.global_transform = xf
	pl.velocity = Vector3.ZERO


func _area_tour() -> Array:
	var r := []
	var order := [["comedor", -1.0], ["dormitorios", -1.0], ["almacen", -1.0], ["salon", 1.0], ["vestuario", 1.0], ["bano", 1.0],
		["enfermeria", 1.0]]
	for o in order:
		var id: String = o[0]
		var side: float = o[1]
		r.append([ShipLayout.door_approach(id, -side), "pasillo→%s" % id])
		r.append([ShipLayout.door_approach(id, side), "puerta %s" % id])
		r.append([_visit_point(id), id])
		r.append([ShipLayout.door_approach(id, side), "puerta %s" % id])
		r.append([ShipLayout.door_approach(id, -side), "pasillo"])
	r.append([Vector3(0, 0, 8.0), "pasillo"])
	r.append([ShipLayout.door_approach("maquinas", 1.0), "puerta máquinas"])
	r.append([Vector3(-3.0, 0, 13.0), "maquinas"])
	r.append([ShipLayout.door_approach("maquinas", 1.0), "puerta máquinas"])
	r.append([Vector3(0, 0, -17.0), "arco"])
	r.append([Vector3(0, 0, -22.0), "cabina"])
	return r


## Punto libre de mobiliario dentro de cada habitación.
func _visit_point(id: String) -> Vector3:
	var pts := {"comedor": Vector3(-4.0, 0, -9.5), "dormitorios": Vector3(-4.5, 0, -3.0), "almacen": Vector3(-4.0, 0, 6.0),
		"vestuario": Vector3(4.0, 0, 2.0), "bano": Vector3(3.0, 0, -7.5), "enfermeria": Vector3(4.5, 0, -12.5),
		"salon": Vector3(2.6, 0, 9.2)}
	return pts.get(id, ShipLayout.room_center(id))


func _start_route() -> void:
	_route_i = 0
	_wp_t = 0.0
	_route_ok = true
	_left_ship = false


## Sigue la ruta orientando al astronauta hacia cada punto. Devuelve true al terminar.
func _follow_route(delta: float) -> bool:
	if _route_i >= _route.size():
		Input.action_release(&"move_forward")
		return true
	var target: Vector3 = _route[_route_i][0]
	var local := ship.to_local(pl.global_position)
	var room := ShipLayout.room_at(local + Vector3(0, 0.9, 0))
	if room != "":
		_visited[room] = true
	var to := Vector2(target.x - local.x, target.z - local.z)
	if to.length() < 0.45:
		_route_i += 1
		_wp_t = 0.0
		return false
	_wp_t += delta
	if _wp_t > WAYPOINT_TIMEOUT:
		print("  ATASCO en '%s' (local %s, objetivo %s)" % [_route[_route_i][1], str(local.snapped(Vector3.ONE * 0.01)), str(target)])
		_report_blockers()
		_route_ok = false
		_route_i += 1
		_wp_t = 0.0
		return false
	# Orientar: dirección deseada en el espacio local de la nave → mundo.
	var dir_world := ship.global_transform.basis * Vector3(to.x, 0, to.y).normalized()
	var up := pl.global_transform.basis.y.normalized()
	dir_world = (dir_world - up * dir_world.dot(up)).normalized()
	var fwd := -pl.global_transform.basis.z
	var ang := fwd.signed_angle_to(dir_world, up)
	pl.rotate(up, ang)
	Input.action_press(&"move_forward")
	return false


## Diagnóstico: formas de colisión que solapan la cápsula del astronauta 20 cm por delante.
func _report_blockers() -> void:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = pl._collision.shape
	q.transform = pl._collision.global_transform.translated(-pl.global_transform.basis.z * 0.2)
	q.collision_mask = pl.collision_mask
	q.exclude = [pl.get_rid()]
	for hit in pl.get_world_3d().direct_space_state.intersect_shape(q, 8):
		var o: Object = hit["collider"]
		var owner_id: int = o.shape_find_owner(hit["shape"]) if o.has_method("shape_find_owner") else -1
		var ow: Object = o.shape_owner_get_owner(owner_id) if owner_id >= 0 else null
		if ow is CollisionShape3D and ow.get_parent() == ship.collision_body:
			var tam: Variant = ow.shape.size if ow.shape is BoxShape3D else ow.shape.get_class()
			print("    bloquea: forma de la nave en %s tamaño %s" % [str(ow.position), str(tam)])
		else:
			print("    bloquea: ", o)


func _finish() -> void:
	print("SHIP-SMOKE RESULTADO: %d comprobaciones, %d fallidas" % [checks, failures])
	set_physics_process(false)
	get_tree().quit(failures)
