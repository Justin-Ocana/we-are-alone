extends TestCase
## Modelo de vuelo, regímenes, modo lumínico y piloto automático (ADR-012).

const DT := 1.0 / 60.0
const R := 1737400.0


func _setup() -> Array:
	var p := ShipParams.load_file("res://data/ships/explorer.json")
	var s := ShipState.new()
	s.landed = false
	s.arcade = false  # las pruebas generales validan el modelo de simulación; arcade tiene las suyas
	var m := ShipFlightModel.new(p)
	return [p, s, m]


func _run(m: ShipFlightModel, s: ShipState, c: ShipControls, seconds: float, g := Vector3.ZERO, dist := R * 10.0) -> void:
	for i in int(seconds / DT):
		m.step(s, c, g, dist, R, DT)
		s.pos_bf = s.pos_bf.add_vector3(s.velocity * DT)


func test_params_load() -> void:
	var p := ShipParams.load_file("res://data/ships/explorer.json")
	assert_eq(p.errors.size(), 0, "sin errores")
	assert_eq(p.regimes.size(), 5, "cinco regímenes")
	assert_near(p.regime_max_speed(p.light_index()), ShipParams.C, 1.0, "el régimen lumínico se limita a c")


func test_gradual_acceleration_and_cruise() -> void:
	var a := _setup()
	var p: ShipParams = a[0]
	var s: ShipState = a[1]
	var m: ShipFlightModel = a[2]
	s.regime = 1  # vuelo normal, 35 m/s²
	m.set_target(s, 500.0)
	var c := ShipControls.new()
	_run(m, s, c, 1.0)
	assert_true(s.forward_speed() < p.regime_accel(1) + p.hover_reserve + 1.0, "tras 1 s no supera la aceleración máxima (%.1f m/s)" % s.forward_speed())
	assert_true(s.forward_speed() > 5.0, "pero sí acelera")
	_run(m, s, c, 40.0)
	assert_near(s.forward_speed(), 500.0, 5.0, "alcanza y mantiene la velocidad de crucero")
	m.set_target(s, 0.0)
	_run(m, s, c, 40.0)
	assert_near(s.speed(), 0.0, 1.0, "frena gradualmente hasta detenerse")


func test_target_clamped_to_regime() -> void:
	var a := _setup()
	var p: ShipParams = a[0]
	var s: ShipState = a[1]
	var m: ShipFlightModel = a[2]
	s.regime = 0
	m.set_target(s, 1.0e6)
	assert_near(s.target_speed, p.regime_max_speed(0), 1e-6, "objetivo limitado al régimen")
	m.set_target(s, -1.0e6)
	assert_near(s.target_speed, -p.regime_max_speed(0) * p.reverse_fraction, 1e-6, "marcha atrás limitada")


func test_hover_compensates_gravity() -> void:
	var a := _setup()
	var s: ShipState = a[1]
	var m: ShipFlightModel = a[2]
	var g := Vector3(0, -9.0, 0)
	_run(m, s, ShipControls.new(), 5.0, g)
	assert_true(s.speed() < 0.5, "con asistencia la nave se mantiene en el sitio (%.2f m/s)" % s.speed())
	s.flight_assist = false
	_run(m, s, ShipControls.new(), 2.0, g)
	assert_true(s.velocity.y < -15.0, "sin asistencia cae (%.1f m/s)" % s.velocity.y)


func test_rotation_is_gradual_and_damped() -> void:
	var a := _setup()
	var p: ShipParams = a[0]
	var s: ShipState = a[1]
	var m: ShipFlightModel = a[2]
	var c := ShipControls.new()
	c.yaw = 1.0
	_run(m, s, c, 0.1)
	assert_true(s.ang_vel.y < p.max_rate.y * 0.5, "la velocidad angular crece gradualmente")
	_run(m, s, c, 3.0)
	assert_near(s.ang_vel.y, p.max_rate.y, 1e-3, "alcanza la velocidad angular máxima")
	assert_true(s.forward().x < -0.5, "yaw +1 gira el morro a la izquierda")
	c.yaw = 0.0
	_run(m, s, c, 2.0)
	assert_near(s.ang_vel.y, 0.0, 1e-4, "la asistencia detiene la rotación")


func test_light_mode_refused_near_body() -> void:
	var a := _setup()
	var p: ShipParams = a[0]
	var s: ShipState = a[1]
	var m: ShipFlightModel = a[2]
	assert_true(not m.set_regime(s, p.light_index(), R * 1.5, R), "rechazado a 1,5 radios")
	assert_true(s.event_text.contains("no disponible"), "con mensaje explicativo")
	assert_true(m.set_regime(s, p.light_index(), R * 5.0, R), "aceptado a 5 radios")


func test_light_mode_reaches_c_without_exceeding() -> void:
	var a := _setup()
	var p: ShipParams = a[0]
	var s: ShipState = a[1]
	var m: ShipFlightModel = a[2]
	m.set_regime(s, p.light_index(), R * 100.0, R)
	m.set_target(s, ShipParams.C)
	var c := ShipControls.new()
	_run(m, s, c, 2.0, Vector3.ZERO, R * 1.0e4)
	assert_true(not s.light_active and s.speed() <= p.regime_max_speed(p.light_index() - 1) + 1.0,
		"durante la carga sólo se usa el régimen anterior (%s m/s)" % str(s.speed()))
	_run(m, s, c, 20.0, Vector3.ZERO, R * 1.0e4)
	assert_true(s.light_active, "motor lumínico activo tras la carga")
	assert_true(s.speed() <= ShipParams.C + 1e-3, "nunca supera c")
	assert_true(s.speed() > 0.9 * ShipParams.C, "se acerca a c (%.3f c)" % (s.speed() / ShipParams.C))
	# Proximidad: salida automática.
	m.step(s, c, Vector3.ZERO, R * 2.0, R, DT)
	assert_true(not s.light_active and s.speed() <= p.regime_max_speed(s.regime) + 1.0, "salida automática cerca de un cuerpo")


func test_autopilot_holds_heading_and_speed() -> void:
	var a := _setup()
	var p: ShipParams = a[0]
	var s: ShipState = a[1]
	var m: ShipFlightModel = a[2]
	var ap := ShipAutopilot.new(p)
	s.regime = 1
	m.set_target(s, 300.0)
	assert_true(ap.engage(s, ShipState.Autopilot.HOLD), "se activa")
	var heading := s.autopilot_heading
	# Perturbación: la nave empieza girando.
	s.ang_vel = Vector3(0.3, -0.4, 0.2)
	var c := ShipControls.new()
	for i in int(60.0 / DT):
		ap.compute(s, c, Vector3(0, -R * 3.0, 0), R, m)
		m.step(s, c, Vector3.ZERO, R * 3.0, R, DT)
	var err := rad_to_deg(s.forward().angle_to(heading))
	assert_true(err < 1.0, "mantiene el rumbo (error %.3f°)" % err)
	assert_near(s.forward_speed(), 300.0, 3.0, "mantiene la velocidad de crucero")
	ap.disengage(s, "control manual")
	assert_eq(s.autopilot, ShipState.Autopilot.OFF, "cede el control")


func test_speed_formatting() -> void:
	assert_true(ShipParams.format_speed(12.0).contains("m/s"), "m/s")
	assert_true(ShipParams.format_speed(5000.0).contains("km/s"), "km/s")
	assert_true(ShipParams.format_speed(ShipParams.C * 0.5).contains("0.5000 c"), "fracción de c")


func test_arcade_speed_grows_with_altitude() -> void:
	assert_near(ShipFlightModel.arcade_cap(0.0), 150.0, 1e-6, "150 m/s junto al suelo")
	assert_near(ShipFlightModel.arcade_cap(1000.0), 4150.0, 1e-6, "≈4,2 km/s a 1 km")
	assert_near(ShipFlightModel.arcade_cap(1.0e7), 1.0e6, 1e-6, "1000 km/s en el espacio")


func test_arcade_quick_response_boost_and_stop() -> void:
	var a := _setup()
	var s: ShipState = a[1]
	var m: ShipFlightModel = a[2]
	s.arcade = true
	var c := ShipControls.new()
	c.throttle = 1.0
	var dist := R + 1000.0   # 1 km de altitud
	for i in int(3.0 / DT):
		m.step(s, c, Vector3.ZERO, dist, R, DT)
	assert_true(s.target_speed > 0.9 * s.speed_cap, "W mantenido 3 s lleva el objetivo casi al máximo (%.0f / %.0f)" % [s.target_speed, s.speed_cap])
	c.throttle = 0.0
	for i in int(4.0 / DT):
		m.step(s, c, Vector3.ZERO, dist, R, DT)
	assert_true(s.forward_speed() > 0.85 * s.speed_cap, "acelera en pocos segundos (%.0f m/s)" % s.forward_speed())
	var before := s.forward_speed()
	c.boost = true
	for i in int(2.0 / DT):
		m.step(s, c, Vector3.ZERO, dist, R, DT)
	assert_true(s.forward_speed() > before * 1.5, "el turbo acelera por encima del máximo normal")
	c.boost = false
	m.emergency_stop(s)
	for i in int(6.0 / DT):
		m.step(s, c, Vector3.ZERO, dist, R, DT)
	assert_true(s.speed() < 1.0, "X detiene la nave (%.2f m/s)" % s.speed())
	c.throttle = -1.0
	for i in int(4.0 / DT):
		m.step(s, c, Vector3.ZERO, dist, R, DT)
	assert_true(s.forward_speed() < -5.0, "S con la nave parada da marcha atrás (%.1f m/s)" % s.forward_speed())


func test_arcade_slows_when_descending() -> void:
	var a := _setup()
	var s: ShipState = a[1]
	var m: ShipFlightModel = a[2]
	s.arcade = true
	m.step(s, ShipControls.new(), Vector3.ZERO, R + 5000.0, R, DT)
	m.set_target(s, s.speed_cap)
	m.step(s, ShipControls.new(), Vector3.ZERO, R + 50.0, R, DT)
	assert_true(s.target_speed <= ShipFlightModel.arcade_cap(50.0) + 1e-6, "al acercarse al suelo el objetivo se recorta (%.0f m/s)" % s.target_speed)


func test_auto_level_rights_the_ship() -> void:
	# Con el ala derecha alta debe ordenar alabeo a la derecha, y con el bucle cerrado nivelar la nave,
	# incluso partiendo casi invertida.
	var a := _setup()
	var p: ShipParams = a[0]
	var m: ShipFlightModel = a[2]
	for start_deg: float in [30.0, -50.0, 170.0]:
		var s := ShipState.new()
		s.landed = false
		s.basis = Basis(Vector3.BACK, deg_to_rad(start_deg))  # alabeo inicial (ala derecha alta si > 0)
		var c := ShipControls.new()
		for i in int(8.0 / DT):
			c.roll = Ship.auto_level_roll(s.basis, Vector3.UP)
			m.step(s, c, Vector3.ZERO, R * 10.0, R, DT)
		var bank := rad_to_deg(atan2(s.basis.x.dot(Vector3.UP), s.basis.y.dot(Vector3.UP)))
		assert_true(absf(bank) < 2.0, "desde %.0f° queda nivelada (%.2f°)" % [start_deg, bank])
	assert_true(Ship.auto_level_roll(Basis(Vector3.BACK, 0.4), Vector3.UP) < 0.0, "ala derecha alta → alabeo a la derecha")
	assert_true(p != null, "parámetros")


func test_emergency_stop_is_fast_at_any_speed() -> void:
	var a := _setup()
	var s: ShipState = a[1]
	var m: ShipFlightModel = a[2]
	s.arcade = true
	var c := ShipControls.new()
	var dist := R * 3.0
	for v: float in [50.0, 5000.0, 250000.0]:
		s.velocity = s.forward() * v
		m.set_target(s, v)
		m.emergency_stop(s)
		var t := 0.0
		while s.speed() > 1.0 and t < 10.0:
			m.step(s, c, Vector3.ZERO, dist, R, DT)
			t += DT
		assert_true(t < 3.0, "X detiene la nave desde %.0f m/s en %.2f s" % [v, t])


func test_emergency_stop_leaves_light_mode() -> void:
	var a := _setup()
	var p: ShipParams = a[0]
	var s: ShipState = a[1]
	var m: ShipFlightModel = a[2]
	s.regime = p.light_index()
	s.light_active = true
	s.velocity = s.forward() * ShipParams.C * 0.9
	m.emergency_stop(s)
	assert_true(not s.light_active and not p.is_light(s.regime), "el frenado de emergencia sale del modo lumínico")
	var t := 0.0
	while s.speed() > 1.0 and t < 10.0:
		m.step(s, ShipControls.new(), Vector3.ZERO, R * 10.0, R, DT)
		t += DT
	assert_true(t < 3.0, "y se detiene desde 0,9 c en %.2f s" % t)
