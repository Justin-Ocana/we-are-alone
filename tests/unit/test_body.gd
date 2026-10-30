extends TestCase
## Cuerpo del astronauta: marcha (Froude), proporciones e IK de piernas (ADR-009).

const G_MOON := 1.62
const G_EARTH := 9.80665


func test_earth_gaits() -> void:
	assert_eq(Gait.select(1.4, G_EARTH), Gait.Kind.WALK, "1,4 m/s en la Tierra = caminar")
	assert_eq(Gait.select(5.0, G_EARTH), Gait.Kind.RUN, "5 m/s en la Tierra = correr")
	assert_eq(Gait.select(0.0, G_EARTH), Gait.Kind.IDLE, "quieto")


func test_moon_lope() -> void:
	# Apolo: con traje y 1/6 g se pasa a "loping" desde Fr ≈ 0,36 (≈0,73 m/s).
	assert_eq(Gait.select(1.6, G_MOON), Gait.Kind.LOPE, "1,6 m/s en la Luna = saltitos")
	assert_eq(Gait.select(0.5, G_MOON), Gait.Kind.WALK, "0,5 m/s en la Luna = caminar")


func test_walk_run_transition_speed_on_earth() -> void:
	# Fr = 0,5 con L = 0,92 m → v ≈ 2,1 m/s.
	var v := sqrt(Gait.FR_WALK_RUN * G_EARTH * Gait.LEG_LENGTH_M)
	assert_near(v, 2.12, 0.05, "velocidad de transición caminar→correr")
	assert_eq(Gait.select(v * 0.95, G_EARTH), Gait.Kind.WALK, "justo por debajo")
	assert_eq(Gait.select(v * 1.05, G_EARTH), Gait.Kind.RUN, "justo por encima")


func test_stride_length_is_human() -> void:
	# Paso humano a 1,4 m/s: ciclo ≈ 1,3–1,5 m (cadencia ≈ 2 pasos/s).
	var stride := Gait.stride_length(1.4, G_EARTH)
	assert_true(stride > 1.2 and stride < 1.6, "zancada a 1,4 m/s = %.2f m" % stride)
	var cadence := 2.0 * 1.4 / stride
	assert_true(cadence > 1.7 and cadence < 2.3, "cadencia %.2f pasos/s" % cadence)
	assert_true(Gait.stride_length(1.6, G_MOON) > stride, "en la Luna la zancada es más larga")


func test_lunar_speed_factor() -> void:
	assert_near(Gait.max_speed_factor(G_MOON), 0.6, 0.01, "≈60 % en gravedad lunar (Hewes 1966)")
	assert_near(Gait.max_speed_factor(G_EARTH), 1.0, 1e-6, "100 % en la Tierra")


func test_lope_has_ballistic_flight() -> void:
	var h := Gait.flight_height(Gait.Kind.LOPE, 1.6, G_MOON)
	assert_true(h > 0.03 and h < 0.25, "bote lunar %.3f m" % h)
	assert_near(Gait.flight_height(Gait.Kind.WALK, 1.4, G_EARTH), 0.0, 1e-9, "caminar no tiene fase aérea")


func test_rig_proportions_match_1_85_m() -> void:
	var standing_eye := AstronautRig.HIP_HEIGHT - AstronautRig.STAND_BEND + AstronautRig.SPINE_OFFSET \
		+ AstronautRig.ABDOMEN + AstronautRig.CHEST + AstronautRig.NECK + AstronautRig.EYE_UP
	assert_near(standing_eye, Units.ASTRONAUT_EYE_HEIGHT_M, 0.02, "altura de los ojos del modelo")
	assert_near(AstronautRig.THIGH + AstronautRig.SHIN + AstronautRig.ANKLE_HEIGHT, AstronautRig.HIP_HEIGHT, 0.001,
		"pierna estirada = altura de cadera")


func test_leg_ik_reaches_target() -> void:
	# Sin árbol de escena: se componen las transformaciones locales (pelvis → cadera → rodilla → tobillo).
	var rig := AstronautRig.new()
	var targets := [Vector3(-0.11, 0.07, -0.3), Vector3(0.11, 0.25, 0.2), Vector3(-0.1, 0.4, 0.0)]
	for t: Vector3 in targets:
		rig._solve_leg(0, Vector3(-AstronautRig.HIP_HALF_WIDTH, -0.05, 0.0), t, Vector3.UP, -1.0)
		var hip_t := rig.pelvis.transform * rig.hips[0].transform
		var knee_t := hip_t * rig.knees[0].transform
		var ankle_t := knee_t * rig.ankles[0].transform
		var ankle_rig := ankle_t.origin
		assert_true(ankle_rig.distance_to(t) < 0.005, "tobillo a %.4f m del objetivo %s" % [ankle_rig.distance_to(t), str(t)])
		var mid := (hip_t.origin + ankle_rig) * 0.5
		assert_true(knee_t.origin.z <= mid.z + 1e-3, "la rodilla se dobla hacia delante")
		assert_true(ankle_t.basis.y.normalized().dot(Vector3.UP) > 0.99, "planta del pie paralela al suelo")
	rig.free()
