extends TestCase
## Precisión de coordenadas (ADR-003).


func test_dvec3_keeps_millimetres_at_1_au() -> void:
	var p := DVec3.new(Units.AU, 0.0, 0.0)
	var q := p.add(DVec3.new(0.001, 0.0, 0.0))
	assert_near(q.sub(p).x, 0.001, 1e-4, "1 mm a 1 UA se conserva (ulp del double a 1 UA ≈ 30 µm)")


func test_vector3_loses_precision_at_planet_scale() -> void:
	# Documenta por qué no usamos Vector3 para posiciones absolutas.
	var v := Vector3(6.0e6, 0, 0) + Vector3(0.1, 0, 0)
	assert_true(absf((v.x - 6.0e6) - 0.1) > 0.01, "Vector3 de 32 bits no debería resolver 10 cm a 6.000 km")


func test_floating_origin_round_trip() -> void:
	var fo := FloatingOriginService.new()
	fo.reset(DVec3.new(6.0e6, 1234.5678, -98765.4321))
	var p := DVec3.new(6.0e6 + 12.345, 1234.5678 - 3.25, -98765.4321 + 0.5)
	var local := fo.to_local(p)
	assert_near(local.x, 12.345, 1e-4, "local x")
	assert_near(local.y, -3.25, 1e-4, "local y")
	var back := fo.to_global(local)
	assert_true(back.is_equal_approx_tol(p, 1e-4), "ida y vuelta BF→local→BF con error < 0,1 mm")
	fo.free()


func test_floating_origin_shift_threshold() -> void:
	var fo := FloatingOriginService.new()
	fo.reset(DVec3.new(1.0e7, 0, 0))
	assert_true(not fo.update_focus(Vector3(500, 0, 0)), "no recentra por debajo del umbral")
	assert_true(fo.update_focus(Vector3(2000, 0, 0)), "recentra por encima del umbral")
	assert_near(fo.offset.x, 1.0e7 + 2000.0, 1e-9, "el offset absorbe el desplazamiento exacto")
	assert_eq(fo.shift_count, 1, "contador de recentrados")
	fo.free()


func test_many_shifts_do_not_accumulate_error() -> void:
	# Simula un viaje de 1.000 km con recentrados cada ~1 km; el offset debe ser exacto.
	var fo := FloatingOriginService.new()
	fo.reset(DVec3.new(6.0e6, 0, 0))
	var expected := 6.0e6
	for i in 1000:
		var step := Vector3(1000.0 + float(i % 7) * 0.125, 0, 0)
		fo.shift(step)
		expected += float(step.x)
	assert_near(fo.offset.x, expected, 1e-6, "offset tras 1000 recentrados")
	fo.free()


func test_latlon_round_trip() -> void:
	for ll in [Vector2(0, 0), Vector2(45, 90), Vector2(-33.3, -120.5), Vector2(89.9, 10)]:
		var d := CubeSphere.latlon_to_dir(ll.x, ll.y)
		assert_near(d.length(), 1.0, 1e-12, "dirección unitaria")
		var back := CubeSphere.dir_to_latlon(d)
		assert_near(back.x, ll.x, 1e-9, "latitud")
		assert_near(back.y, ll.y, 1e-9, "longitud")
