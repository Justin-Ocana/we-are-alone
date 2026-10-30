extends TestCase
## Efemérides del Sistema Solar (ADR-024): contra valores conocidos.

var _cat: BodyCatalog
var _sys: SolarSystem


func _setup() -> SolarSystem:
	if _sys == null:
		_cat = BodyCatalog.load_dir()
		_sys = SolarSystem.from_catalog(_cat)
	_sys.set_time(0.0)  # J2000.0
	return _sys


func test_catalog_loads_whole_system() -> void:
	var s := _setup()
	assert_true(_cat.errors.is_empty(), "catálogo sin errores (%s)" % str(_cat.errors.slice(0, 3)))
	for id in ["sun", "mercury", "venus", "earth", "moon", "mars", "jupiter", "saturn", "uranus", "neptune", "pluto",
			"io", "europa", "ganymede", "callisto", "titan", "enceladus", "triton", "charon", "phobos", "deimos"]:
		assert_true(s.has_body(id), "existe '%s'" % id)
	assert_true(s.bodies.size() > 400, "más de 400 cuerpos (%d)" % s.bodies.size())
	assert_true(s.children["saturn"].size() > 250, "lunas de Saturno: %d" % s.children["saturn"].size())


func test_kepler_solver() -> void:
	for e: float in [0.0, 0.2, 0.7, 0.95]:
		for m: float in [0.1, 1.0, 2.5, -2.0]:
			var ecc := Ephemeris.solve_kepler(m, e)
			assert_near(ecc - e * sin(ecc), wrapf(m, -PI, PI), 1e-10, "Kepler e=%.2f M=%.1f" % [e, m])


func test_earth_at_j2000() -> void:
	# Tierra el 1-ene-2000 12h TT: x ≈ −0,177 UA, y ≈ +0,967 UA (efemérides DE: −0,1771, 0,9672).
	var s := _setup()
	var p := s.position("earth").mul(1.0 / Ephemeris.AU)
	assert_near(p.x, -0.1771, 0.004, "Tierra x en J2000 (%.4f UA)" % p.x)
	assert_near(p.y, 0.9672, 0.004, "Tierra y en J2000 (%.4f UA)" % p.y)
	assert_near(p.z, 0.0, 0.001, "Tierra en el plano de la eclíptica")


func test_planet_distances_and_periods() -> void:
	var s := _setup()
	var expected := {"mercury": [0.307, 0.467], "venus": [0.718, 0.729], "mars": [1.38, 1.67], "jupiter": [4.95, 5.46],
		"saturn": [9.0, 10.1], "uranus": [18.2, 20.1], "neptune": [29.8, 30.4], "pluto": [29.6, 49.4]}
	for id in expected:
		var d := s.position(id).length() / Ephemeris.AU
		assert_true(d >= expected[id][0] and d <= expected[id][1], "%s a %.3f UA del Sol" % [id, d])
	# Marte vuelve a su posición tras un periodo sidéreo (686,98 días).
	var p0 := s.position("mars")
	s.set_time(686.98 * 86400.0)
	var p1 := s.position("mars")
	assert_true(p0.distance_to(p1) / p0.length() < 0.01, "Marte cierra su órbita en 687 días")


func test_moon_distance_and_sun_direction() -> void:
	var s := _setup()
	var d := s.position("moon").distance_to(s.position("earth"))
	assert_true(d > 356000e3 and d < 407000e3, "Luna a %.0f km de la Tierra" % (d / 1000.0))
	# A 1-ene-2000 el Sol se ve desde la Tierra en longitud eclíptica ≈ 280,4°.
	var to_sun := s.position("sun").sub(s.position("earth"))
	var lon := fposmod(rad_to_deg(atan2(to_sun.y, to_sun.x)), 360.0)
	assert_near(lon, 280.4, 0.5, "longitud eclíptica del Sol (%.2f°)" % lon)


func test_galilean_moons_periods() -> void:
	var s := _setup()
	var p0 := s.position("io").sub(s.position("jupiter"))
	# Periodo medio de la tabla JPL (1,7627 d respecto al nodo; el sidéreo de NSSDC es 1,7691 d).
	s.set_time(float(s.body("io").orbit()["period_s"]))
	var p1 := s.position("io").sub(s.position("jupiter"))
	assert_true(p0.distance_to(p1) / p0.length() < 0.02, "Ío completa su órbita en un periodo (%.4f d)" % (float(s.body("io").orbit()["period_s"]) / 86400.0))
	var r := p1.length() / 1000.0
	assert_near(r, 421800.0, 3000.0, "Ío a %.0f km de Júpiter" % r)


func test_body_axes_are_orthonormal_and_pole_matches() -> void:
	var s := _setup()
	for id in ["earth", "mars", "jupiter", "moon", "titan"]:
		var ax: Array = s.axes(id)
		assert_near(ax[0].dot(ax[1]), 0.0, 1e-9, "%s: X ⟂ Y" % id)
		assert_near(ax[1].dot(ax[2]), 0.0, 1e-9, "%s: Y ⟂ Z" % id)
		assert_near(ax[0].cross(ax[1]).dot(ax[2]), 1.0, 1e-9, "%s: base dextrógira" % id)
	# El polo de la Tierra está inclinado 23,44° respecto a la normal de la eclíptica.
	var tilt := rad_to_deg(acos(s.axes("earth")[1].z))
	assert_near(tilt, 23.44, 0.05, "oblicuidad de la Tierra (%.2f°)" % tilt)


func test_dominant_body_hierarchy() -> void:
	var s := _setup()
	var moon := s.position("moon")
	var r := s.body("moon").radius_m()
	assert_eq(s.dominant_body(moon.add(DVec3.new(r * 2.0, 0, 0))), "moon", "junto a la Luna domina la Luna")
	var earth := s.position("earth")
	assert_eq(s.dominant_body(earth.add(DVec3.new(2.0e7, 0, 0))), "earth", "a 20 000 km de la Tierra domina la Tierra")
	assert_eq(s.dominant_body(earth.add(DVec3.new(0, 0, 5.0e10))), "sun", "en el espacio interplanetario domina el Sol")
	var titan := s.position("titan")
	assert_eq(s.dominant_body(titan.add(DVec3.new(0, 4.0e6, 0))), "titan", "junto a Titán domina Titán")
