extends TestCase
## Modelos de atmósfera (ADR-029) contra mediciones reales.

var _cat: BodyCatalog


func _model(id: String) -> AtmosphereModel:
	if _cat == null:
		_cat = BodyCatalog.load_dir()
	return AtmosphereModel.for_body(_cat.get_body(id))


func test_jupiter_matches_galileo_probe() -> void:
	var m := _model("jupiter")
	assert_near(m.pressure(0.0), 1.0e5, 1.0, "1 bar en la referencia")
	assert_near(m.temperature(0.0), 165.0, 0.1, "165 K a 1 bar (NSSDC)")
	assert_near(m.density(0.0), 0.16, 0.03, "densidad a 1 bar ≈ 0,16 kg/m³ (NSSDC): %.3f" % m.density(0.0))
	# Galileo: perdió la señal a ≈ 23 bar y ≈ 425 K, unos 150 km bajo el nivel de 1 bar (la profundidad depende
	# de la referencia; el dato fiable es la temperatura en ese nivel de presión).
	var lo := -400000.0
	var hi := 0.0
	for k in 60:
		var mid := (lo + hi) * 0.5
		if m.pressure(mid) > 23.0e5:
			lo = mid
		else:
			hi = mid
	var t := m.temperature(hi)
	assert_true(t > 400.0 and t < 450.0, "a 23 bar: %.0f K (Galileo ≈ 425 K)" % t)
	assert_true(-hi > 100000.0 and -hi < 175000.0, "23 bar a %.0f km bajo 1 bar (Galileo ≈ 150 km)" % (-hi / 1000.0))
	assert_near(m.temperature(m._h * log(10.0)), 112.0, 0.5, "112 K a 0,1 bar")


func test_venus_surface() -> void:
	var m := _model("venus")
	assert_near(m.pressure(0.0) / 1.0e5, 92.0, 0.01, "92 bar en superficie")
	assert_near(m.temperature(0.0), 737.0, 0.1, "737 K en superficie")
	assert_true(m.density(0.0) > 55.0 and m.density(0.0) < 75.0, "densidad ≈ 65 kg/m³: %.1f" % m.density(0.0))
	assert_true(not m.cloud_at(55000.0).is_empty(), "nubes de ácido sulfúrico a 55 km")
	assert_true(m.cloud_at(20000.0).is_empty(), "sin nubes a 20 km")
	assert_true(m.light_fraction(0.0) < 0.1, "poca luz en el suelo")


func test_mars_and_titan() -> void:
	var mars := _model("mars")
	assert_near(mars.pressure(0.0), 636.0, 1.0, "Marte: 6,36 mbar")
	assert_true(mars.density(0.0) > 0.010 and mars.density(0.0) < 0.022, "Marte: ρ ≈ 0,016 kg/m³ (%.4f)" % mars.density(0.0))
	var titan := _model("titan")
	assert_near(titan.pressure(0.0) / 1.0e5, 1.467, 0.001, "Titán: 1,467 bar (Huygens)")
	assert_true(titan.density(0.0) > 4.5 and titan.density(0.0) < 6.0, "Titán: ρ ≈ 5,3 kg/m³ (%.2f)" % titan.density(0.0))


func test_airless_and_safe_speed() -> void:
	assert_true(not _model("moon").present(), "la Luna no tiene atmósfera")
	var m := _model("jupiter")
	var v_high := m.safe_speed(200000.0)
	var v_low := m.safe_speed(0.0)
	assert_true(v_high > v_low, "velocidad segura mayor arriba (%.0f > %.0f m/s)" % [v_high, v_low])
	assert_near(m.heat_flux(0.0, v_low), 2.4e5, 2.4e3, "la velocidad segura da el flujo límite")
	assert_true(absf(m.zonal_wind(deg_to_rad(23.0), 0.0)) <= 260.0, "vientos de Júpiter acotados")
