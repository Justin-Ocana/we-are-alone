class_name AtmosphereModel
extends RefCounted
## Modelo físico de la atmósfera de un cuerpo (ADR-029), a partir de su JSON.
##
## - Rocosos (Venus, Marte, Titán, Plutón, Tritón): P = P0·e^(−z/H), T = max(T0 − Γ·z, Tmin), ρ = P·μ/(R·T).
## - Gigantes gaseosos (altitud 0 = nivel de 1 bar): por encima, estratosfera que pasa de T(1 bar) a T(0,1 bar)
##   con P = 1 bar·e^(−z/H); por debajo, adiabática seca: T = T1 + (g/cp)·profundidad, P = 1 bar·(T/T1)^(cp/Rs).
##   Con los datos de Júpiter da ≈ 22 bar y ≈ 430 K a 150 km bajo 1 bar: lo medido por la sonda Galileo
##   (≈ 23 bar, ≈ 425 K). No hay suelo: la presión crece sin límite.
## - Capas de nubes por presión (gigantes) o por altitud (rocosos), vientos zonales por latitud y la luz solar
##   que llega a cada profundidad (aproximada por la presión y las nubes atravesadas).

const R_GAS := 8.314462618

var body: BodyDef
var kind := "none"                ## "none", "rocky", "gas_giant"
var g := 9.8
var _a: Dictionary = {}
var _p0 := 0.0
var _t0 := 0.0
var _h := 1.0
var _mu := 0.029                  ## kg/mol
var _lapse := 0.0
var _tmin := 0.0
var _t01 := 0.0
var _cp := 12000.0


static func for_body(b: BodyDef) -> AtmosphereModel:
	var m := AtmosphereModel.new()
	m.body = b
	m.g = b.surface_gravity()
	var a := b.atmosphere()
	m._a = a
	if not bool(a.get("present", false)):
		return m
	m.kind = str(a.get("kind", "rocky"))
	m._mu = float(_val(a, "mean_molecular_weight", 29.0)) / 1000.0
	m._h = float(_val(a, "scale_height", 10000.0))
	if m.kind == "gas_giant":
		m._p0 = 1.0e5
		m._t0 = float(_val(a, "temperature_1bar", 150.0))
		m._t01 = float(_val(a, "temperature_0p1bar", m._t0 * 0.7))
		m._cp = float(_val(a, "specific_heat_cp", 12000.0))
	else:
		m._p0 = float(_val(a, "surface_pressure", 1.0e5))
		m._t0 = float(_val(a, "surface_temperature", 288.0))
		m._lapse = float(_val(a, "lapse_rate", 0.0))
		m._tmin = float(_val(a, "min_temperature", 50.0))
	return m


static func _val(a: Dictionary, key: String, fallback: float) -> float:
	var v: Variant = a.get(key)
	if v is Dictionary:
		return float(v.get("value", fallback))
	if v is float or v is int:
		return float(v)
	return fallback


func present() -> bool:
	return kind != "none"


func temperature(alt: float) -> float:
	match kind:
		"rocky":
			return maxf(_t0 - _lapse * maxf(alt, 0.0), _tmin)
		"gas_giant":
			if alt >= 0.0:
				var z_tropo := _h * log(10.0)
				return lerpf(_t0, _t01, clampf(alt / z_tropo, 0.0, 1.0))
			return _t0 + g / _cp * (-alt)
	return 0.0


func pressure(alt: float) -> float:
	match kind:
		"rocky":
			return _p0 * exp(-maxf(alt, -2000.0) / _h)
		"gas_giant":
			if alt >= 0.0:
				return _p0 * exp(-alt / _h)
			var rs := R_GAS / _mu
			return _p0 * pow(temperature(alt) / _t0, _cp / rs)
	return 0.0


func density(alt: float) -> float:
	var t := temperature(alt)
	if t <= 0.0:
		return 0.0
	return pressure(alt) * _mu / (R_GAS * t)


## Altitud por encima de la cual la presión es menor que 1 Pa (borde efectivo, para efectos y avisos).
func top_altitude() -> float:
	if kind == "none":
		return 0.0
	var p_ref := pressure(0.0)
	if p_ref <= 1.0:
		return 0.0
	return _h * log(p_ref / 1.0)


## Capa de nubes en la que está esa altitud ({} si ninguna). Gigantes: por presión; rocosos: por altitud.
func cloud_at(alt: float) -> Dictionary:
	var clouds: Array = _a.get("clouds", [])
	if kind == "gas_giant":
		var p_bar := pressure(alt) / 1.0e5
		for c in clouds:
			if p_bar >= float(c["p_top_bar"]) and p_bar <= float(c["p_base_bar"]):
				return c
		return {}
	for c in clouds:
		if alt >= float(c.get("bottom_m", 0.0)) and alt <= float(c.get("top_m", 0.0)):
			return c
	return {}


## Fracción de la luz solar que llega a esa altitud (1 en el espacio). Las nubes y la presión la apagan.
func light_fraction(alt: float) -> float:
	match kind:
		"rocky":
			var sl := _val(_a, "surface_light", 1.0)
			var f := clampf(pressure(alt) / maxf(_p0, 1e-6), 0.0, 1.0)
			return lerpf(1.0, sl, f)
		"gas_giant":
			var p_bar := pressure(alt) / 1.0e5
			var tau := 0.35 * maxf(p_bar - 0.2, 0.0)
			for c in _a.get("clouds", []):
				if p_bar > float(c["p_top_bar"]):
					var through := clampf((p_bar - float(c["p_top_bar"])) / maxf(float(c["p_base_bar"]) - float(c["p_top_bar"]), 1e-3), 0.0, 1.0)
					tau += float(c["opacity"]) * 2.0 * through
			return clampf(exp(-tau), 0.0005, 1.0)
	return 1.0


## Viento zonal (m/s, positivo hacia el este) a una latitud (rad) y altitud.
func zonal_wind(lat: float, alt: float) -> float:
	if kind == "gas_giant":
		var wm: Dictionary = _a.get("wind_model", {})
		var u := 0.0
		match str(wm.get("type", "")):
			"jets":
				var n := float(wm.get("jets", 10))
				u = float(wm.get("max_mps", 100.0)) * cos(lat * n) * sqrt(maxf(cos(lat), 0.0))
				u += float(wm.get("equator_mps", 0.0)) * exp(-pow(lat / 0.15, 2.0))
			"broad":
				u = float(wm.get("max_mps", 300.0)) * exp(-pow(rad_to_deg(lat) / float(wm.get("width_deg", 30.0)), 2.0))
			"ice":
				var jl := deg_to_rad(float(wm.get("jet_lat", 60.0)))
				u = float(wm.get("equator_mps", -100.0)) * pow(cos(lat), 2.0)
				u += float(wm.get("max_mps", 200.0)) * exp(-pow((absf(lat) - jl) / deg_to_rad(15.0), 2.0))
		# Los vientos de las cimas de las nubes se mantienen en profundidad (Juno: hasta miles de km).
		return u
	if kind == "rocky":
		var w: Dictionary = _a.get("winds", {})
		var ground := float(w.get("surface_mps", 0.0))
		if w.has("cloud_top_mps"):
			return -lerpf(ground, float(w["cloud_top_mps"]), clampf(alt / 65000.0, 0.0, 1.0))  # superrotación retrógrada
		return ground * cos(lat)
	return 0.0


func color_of(c: Dictionary, key := "color") -> Color:
	var a: Array = c.get(key, [0.5, 0.5, 0.5])
	return Color(a[0], a[1], a[2])


func sky_color(key: String, fallback: Color) -> Color:
	var sky: Dictionary = _a.get("sky", {})
	if sky.has(key):
		var a: Array = sky[key]
		return Color(a[0], a[1], a[2])
	if kind == "gas_giant" and key == "zenith" and _a.has("sky_above_clouds"):
		var b: Array = _a["sky_above_clouds"]
		return Color(b[0], b[1], b[2])
	return fallback


## Velocidad máxima segura de entrada para que el calentamiento convectivo (Sutton-Graves) no supere `q_max`
## (W/m²) con radio de morro `nose_r` (m). Se usa como limitador del modo Arcade dentro de la atmósfera.
func safe_speed(alt: float, q_max: float = 2.4e5, nose_r: float = 6.0) -> float:
	var rho := density(alt)
	if rho <= 1e-12:
		return INF
	return pow(q_max / (1.7415e-4 * sqrt(rho / nose_r)), 1.0 / 3.0)


## Flujo de calor convectivo (W/m², Sutton-Graves) a velocidad `v` respecto al aire.
func heat_flux(alt: float, v: float, nose_r: float = 6.0) -> float:
	return 1.7415e-4 * sqrt(density(alt) / nose_r) * v * v * v
