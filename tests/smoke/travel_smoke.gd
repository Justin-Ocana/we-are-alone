extends Node
## Prueba de integración del Hito 3 (headless): viajes por el Sistema Solar con la nave y el piloto automático.
## Luna → Tierra destruida → Júpiter, comprobando los cambios de cuerpo dominante (ADR-027), la llegada a la
## distancia de aproximación y que no aparecen valores no finitos. Uso: --travel-smoke.

var main: Node
var world: SurfaceWorld
var failures := 0
var checks := 0
var _step := 0
var _t := 0.0
var _anchors: Array = []
var _max_speed := 0.0
var _impacts := 0
var _touch_v := 0.0


func _ready() -> void:
	world = main.start_world("moon", main.SPAWN_LAT, main.SPAWN_LON, false, true)
	print("TRAVEL-SMOKE: inicio")


func check(cond: bool, what: String) -> void:
	checks += 1
	print("  %s  %s" % ["PASA " if cond else "FALLA", what])
	if not cond:
		failures += 1


func _finish() -> void:
	print("TRAVEL-SMOKE RESULTADO: %d comprobaciones, %d fallidas" % [checks, failures])
	get_tree().quit(failures)


## Coloca la nave a `alt` m sobre la referencia del cuerpo dominante, quieta.
func _place(alt: float) -> void:
	var ship := world.ship
	var r := world.terrain.radius + alt
	ship.state.pos_bf = ship.state.pos_bf.normalized().mul(r)
	ship.state.velocity = Vector3.ZERO
	ship.state.target_speed = 0.0
	ship.autopilot.disengage(ship.state, "prueba")


func _physics_process(delta: float) -> void:
	if world == null or not world.surface_ready or world.ship == null:
		return
	var ship := world.ship
	var pl := world.player
	_t += delta
	if _anchors.is_empty() or _anchors[-1] != world.body.id:
		_anchors.append(world.body.id)
	_max_speed = maxf(_max_speed, ship.state.speed())
	var p := ship.state.pos_bf
	if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
		check(false, "posición finita")
		_finish()
		return
	match _step:
		0:
			check(world.body.id == "moon" and world.system != null, "se empieza en la Luna con el Sistema Solar cargado")
			# Sube a bordo: directamente al puesto de pilotaje.
			pl.global_transform = ship.global_transform * Transform3D(Basis(), ShipLayout.SEAT_EXIT)
			_step = 1
			_t = 0.0
		1:
			if _t > 1.0:
				pl._interact()
				check(pl.is_piloting(), "el piloto se sienta")
				if OS.has_environment("TRAVEL_VENUS"):
					ship.cmd_travel("venus")
					_anchors = [world.body.id]
					_step = 7
					_t = 0.0
					return
				ship.cmd_travel("earth")
				check(ship.state.autopilot == ShipState.Autopilot.TRAVEL, "piloto automático de viaje a la Tierra")
				_step = 2
				_t = 0.0
		2:
			if fmod(_t, 20.0) < delta:
				var st := ship.state
				print("  VIAJE t=%.0f ancla=%s r=%.0f km v=%.0f m/s obj=%.0f reg=%d luz=%s salto=%.1f falta=%.0f km ap=%d climb=%s" % [_t, world.body.id,
					st.pos_bf.length() / 1000.0, st.speed(), st.target_speed, st.regime, st.light_active, st.warp, st.travel_remaining / 1000.0, st.autopilot, st.travel_climb])
				print("    pitch=%.2f yaw=%.2f w=%s fwd·up=%.2f dir·up=%.2f landed=%s radar=%.0f" % [ship._ap_controls.pitch, ship._ap_controls.yaw, str(st.ang_vel), st.forward().dot(st.pos_bf.normalized().to_vector3()), st.travel_dir.dot(st.pos_bf.normalized().to_vector3()), st.landed, ship.radar_altitude])
			if ship.state.autopilot != ShipState.Autopilot.TRAVEL:
				var d := world.system.position_in_frame("earth", world.body.id).sub(ship.state.pos_bf).length()
				check(world.body.id == "earth", "al llegar domina la Tierra (marcos: %s; último aviso: %s)" % [str(_anchors), ship.state.event_text])
				var r := world.system.body("earth").radius_m()
				check(d < r * 4.0 and d > r * 1.3, "llegada a la Tierra destruida a %.0f km del centro (%.0f s)" % [d / 1000.0, _t])
				check(pl.seated and pl.aboard == ship, "el piloto sigue sentado en la nave tras los cambios de marco")
				ship.cmd_travel("jupiter")
				_anchors = [world.body.id]
				_max_speed = 0.0
				_step = 3
				_t = 0.0
			elif _t > 240.0:
				check(false, "no llegó a la Tierra (marcos %s, faltan %.0f km)" % [str(_anchors), ship.state.travel_remaining / 1000.0])
				_finish()
		3:
			if ship.state.autopilot != ShipState.Autopilot.TRAVEL:
				var d := world.system.position_in_frame("jupiter", world.body.id).sub(ship.state.pos_bf).length()
				var r := world.system.body("jupiter").radius_m()
				check("sun" in _anchors and world.body.id == "jupiter", "Tierra → Sol → Júpiter (marcos: %s)" % str(_anchors))
				check(d < r * 4.0 and d > r * 1.3, "llegada a Júpiter a %.0f km del centro (%.0f s)" % [d / 1000.0, _t])
				check(_max_speed > ShipParams.C, "salto interplanetario por encima de c (ficticio): %.0f c" % (_max_speed / ShipParams.C))
				check(not world.terrain.solid, "Júpiter no tiene suelo (terreno no sólido)")
				_place(60000.0)
				_step = 4
				_t = 0.0
			elif _t > 300.0:
				check(false, "no llegó a Júpiter (marcos %s, faltan %s)" % [str(_anchors), Units.format_distance(ship.state.travel_remaining)])
				_finish()
		4:
			if _t > 1.0:
				var st := ship.state
				var m := world.atmo
				check(absf(st.ext_pressure - m.pressure(60000.0)) / m.pressure(60000.0) < 0.05,
					"Júpiter a +60 km: %.3f bar, %.0f K, viento %.0f m/s" % [st.ext_pressure / 1e5, st.ext_temperature, st.wind_speed])
				_place(-25000.0)
				_step = 5
				_t = 0.0
		5:
			if _t > 1.0:
				var st := ship.state
				var cl := world.atmo.cloud_at(-25000.0)
				check(st.ext_pressure > 1.5e5 and not cl.is_empty(),
					"Júpiter a −25 km: %.2f bar, %.0f K, dentro de '%s'" % [st.ext_pressure / 1e5, st.ext_temperature, cl.get("name", "—")])
				check(float(world.env.sky_mat.get_shader_parameter("deep_amount")) > 0.2, "niebla de nubes al descender (%.2f)" % float(world.env.sky_mat.get_shader_parameter("deep_amount")))
				check(st.hull_integrity > 99.0, "el casco aguanta a %.1f bar" % (st.ext_pressure / 1e5))
				_place(-450000.0)
				_step = 6
				_t = 0.0
		6:
			# Entrada libre (FICTICIO, ADR-031): la presión ya no destruye el casco; sólo el calor del Sol.
			if _t > 3.0:
				var st6 := ship.state
				check(st6.hull_integrity >= 100.0 and st6.ext_pressure > 300.0e5,
					"a −450 km (%.0f bar, %.0f K) el casco reforzado aguanta: %.0f %%" % [st6.ext_pressure / 1e5, st6.ext_temperature, st6.hull_integrity])
				ship.cmd_travel("venus")
				_anchors = [world.body.id]
				_step = 7
				_t = 0.0
		7:
			if fmod(_t, 20.0) < delta:
				var st := ship.state
				print("  VIAJE7 t=%.0f ancla=%s v=%.0f falta=%s ap=%d salto=%.0f evento=%s casco=%.0f" % [_t, world.body.id, st.speed(),
					Units.format_distance(st.travel_remaining), st.autopilot, st.warp, st.event_text, st.hull_integrity])
			if ship.state.autopilot != ShipState.Autopilot.TRAVEL and world.body.id == "venus":
				check(true, "viaje a Venus (marcos %s, %.0f s)" % [str(_anchors), _t])
				_step = 75
				_t = 0.0
			elif _t > 300.0:
				check(false, "no llegó a Venus")
				_finish()
		75:
			if _t > 6.0:
				var up_r := ship.state.pos_bf.normalized().to_vector3()
				check(absf(ship.state.forward().dot(up_r)) < 0.1 and ship.state.basis.y.dot(up_r) > 0.95,
					"al llegar la nave queda nivelada con el horizonte (%.2f)" % ship.state.basis.y.dot(up_r))
				_place(world.terrain.height_at_dir(ship.state.pos_bf.normalized()) + 1500.0)
				_step = 8
				_t = 0.0
				Input.action_press(&"ship_down")
		8:
			if fmod(_t, 5.0) < delta:
				print("  VENUS t=%.0f radar=%.0f v=%s vvert=%.2f ctrl=%s ap=%d seated=%s piloting=%s" % [_t, ship.radar_altitude, str(ship.state.velocity), ship.vertical_speed, str(ship.controls.strafe), ship.state.autopilot, pl.seated, pl.is_piloting()])
			if ship.state.landed:
				Input.action_release(&"ship_down")
				var st := ship.state
				check(true, "aterrizaje en Venus en %.0f s" % _t)
				check(absf(st.ext_pressure / 1e5 - world.atmo.pressure(world.ship.radar_altitude * 0.0 + (st.pos_bf.length() - world.terrain.radius)) / 1e5) < 3.0 and st.ext_pressure > 80.0e5,
					"superficie de Venus: %.1f bar, %.0f K (%.0f °C)" % [st.ext_pressure / 1e5, st.ext_temperature, st.ext_temperature - 273.15])
				check(st.hull_integrity > 99.0, "el casco resiste la superficie de Venus: %.0f %%" % st.hull_integrity)
				# Aterrizaje automático (ronda 10): desde 3 km, sin golpes y tocando suelo despacio.
				_place(world.terrain.height_at_dir(ship.state.pos_bf.normalized()) + 3000.0)
				ship.state.landed = false
				ship.impact.connect(func(st: float): _impacts += 1 if st >= 0.2 else 0)  # el contacto suave da < 0,2
				ship.cmd_toggle_autopilot(ShipState.Autopilot.APPROACH)
				_step = 9
				_t = 0.0
			elif _t > 200.0:
				Input.action_release(&"ship_down")
				check(false, "no aterrizó en Venus (alt radar %.0f m)" % ship.radar_altitude)
				_finish()
		9:
			if ship.radar_altitude < 3.0 and not ship.state.landed:
				_touch_v = maxf(_touch_v, absf(ship.vertical_speed))
			if fmod(_t, 10.0) < delta:
				print("  AUTOLAND t=%.0f radar=%.0f vvert=%.2f ap=%d" % [_t, ship.radar_altitude, ship.vertical_speed, ship.state.autopilot])
			if ship.state.landed:
				check(_impacts == 0 and _touch_v < 2.5, "aterrizaje automático desde 3 km en %.0f s: %d golpes, contacto a %.2f m/s" % [_t, _impacts, _touch_v])
				_finish()
			elif _t > 240.0:
				check(false, "el aterrizaje automático no se posó (alt radar %.0f m, piloto %d)" % [ship.radar_altitude, ship.state.autopilot])
				_finish()

