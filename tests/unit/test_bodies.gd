extends TestCase
## Catálogo de cuerpos, unidades físicas y escala humana.


func test_catalog_loads_without_errors() -> void:
	var cat := BodyCatalog.load_dir()
	assert_eq(cat.errors.size(), 0, "errores: %s" % str(cat.errors))
	assert_true(cat.get_body("moon") != null, "existe la Luna")
	assert_true(cat.get_body("proto_a") != null, "existe Prototipo-A")


func test_moon_real_values() -> void:
	var moon := BodyCatalog.load_dir().get_body("moon")
	assert_near(moon.radius_m(), 1737400.0, 0.5, "radio medio NSSDC")
	assert_eq(moon.physical_quality("mean_radius"), "measured", "calidad del dato")
	assert_near(moon.surface_gravity(), 1.62, 0.01, "gravedad superficial NSSDC 1,62 m/s²")
	assert_true(not moon.has_atmosphere(), "sin atmósfera")
	assert_true(moon.terrain_note().contains("PROCEDURAL"), "el terreno se declara procedural")


func test_fictional_world_is_labelled() -> void:
	var p := BodyCatalog.load_dir().get_body("proto_a")
	assert_true(p.is_fictional(), "Prototipo-A debe declararse ficticio")
	assert_near(p.surface_gravity(), 9.0, 0.02, "g ≈ 9,0 m/s²")


func test_gravity_inverse_square() -> void:
	var moon := BodyCatalog.load_dir().get_body("moon")
	var g0 := moon.gravity_at_distance(moon.radius_m())
	var g2 := moon.gravity_at_distance(moon.radius_m() * 2.0)
	assert_near(g2, g0 / 4.0, 1e-12, "ley de la inversa del cuadrado")


func test_invalid_body_is_rejected() -> void:
	var b := BodyDef.from_dict({"schema_version": 1, "id": "x", "name": "X", "kind": "planet",
		"physical": {"mean_radius": {"value": -5, "quality": "made_up"}}, "surface": {}})
	assert_true(not b.is_valid(), "radio negativo / calidad inválida / sin masa deben rechazarse")


func test_astronaut_scale() -> void:
	assert_near(Units.ASTRONAUT_HEIGHT_M, 1.85, 1e-9, "altura del astronauta")
	assert_true(Units.ASTRONAUT_EYE_HEIGHT_M < Units.ASTRONAUT_HEIGHT_M, "ojos por debajo de la coronilla")


func test_jump_height_emerges_from_gravity() -> void:
	var v := Astronaut.JUMP_TAKEOFF_SPEED
	var h_earth := v * v / (2.0 * 9.81)
	var h_moon := v * v / (2.0 * 1.62)
	assert_true(h_earth > 0.3 and h_earth < 0.6, "salto humano en la Tierra ≈ 0,46 m")
	assert_true(h_moon > 2.0 and h_moon < 3.5, "salto en la Luna ≈ 2,8 m")


func test_horizon_distance() -> void:
	# Observador de 1,70 m sobre una esfera de 6.371 km: horizonte ≈ 4,65 km.
	assert_near(Units.horizon_distance(6.371e6, 1.70), 4654.0, 5.0, "distancia al horizonte")
