class_name Ephemeris
extends RefCounted
## Efemérides keplerianas del Sistema Solar (ADR-024). Todo en doble precisión (float de GDScript + DVec3).
##
## Marco del sistema: eclíptica media y equinoccio J2000, heliocéntrico, en metros.
## - Planetas: elementos de la Tabla 1 del JPL (Standish & Williams 1992) con sus tasas por siglo; algoritmo
##   oficial: M = L − ϖ, ω = ϖ − Ω, ecuación de Kepler, rotación (ω, I, Ω) a la eclíptica.
## - Satélites: elementos medios del JPL en su plano de referencia (eclíptica, plano de Laplace o ecuador del
##   planeta) con precesión lineal del periastro y del nodo.
## - Orientación: polo IAU (α0, δ0 ecuatoriales J2000 con deriva) y meridiano W = W0 + Ẇ·d.
## Tiempo: segundos desde J2000.0 (2000-01-01 12:00 TT); TT ≈ UTC + 69 s (despreciable aquí).

const AU := 1.495978707e11
const OBLIQUITY_DEG := 23.43928
const SECONDS_PER_DAY := 86400.0
const SECONDS_PER_CENTURY := 36525.0 * 86400.0
const J2000_JD := 2451545.0
const J2000_UNIX := 946727935.816   ## 2000-01-01 11:58:55,816 UTC = 12:00 TT

static var _eps_sin := sin(deg_to_rad(OBLIQUITY_DEG))
static var _eps_cos := cos(deg_to_rad(OBLIQUITY_DEG))


static func now_seconds() -> float:
	return Time.get_unix_time_from_system() - J2000_UNIX


## Ecuatorial ICRF → eclíptica J2000.
static func equatorial_to_ecliptic(v: DVec3) -> DVec3:
	return DVec3.new(v.x, v.y * _eps_cos + v.z * _eps_sin, -v.y * _eps_sin + v.z * _eps_cos)


static func radec_to_vector(ra_deg: float, dec_deg: float) -> DVec3:
	var ra := deg_to_rad(ra_deg)
	var dec := deg_to_rad(dec_deg)
	return DVec3.new(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec))


## Ecuación de Kepler M = E − e·sin E (radianes), Newton-Raphson.
static func solve_kepler(m: float, e: float) -> float:
	m = wrapf(m, -PI, PI)
	var ecc := m + e * sin(m)
	for i in 30:
		var de := (m - (ecc - e * sin(ecc))) / (1.0 - e * cos(ecc))
		ecc += de
		if absf(de) < 1e-12:
			break
	return ecc


## Posición en el plano de referencia a partir de (a, e, i, Ω, ω, M) en metros y grados.
static func elements_to_position(a: float, e: float, i_deg: float, node_deg: float, w_deg: float, m_deg: float) -> DVec3:
	var ecc := solve_kepler(deg_to_rad(m_deg), e)
	var xp := a * (cos(ecc) - e)
	var yp := a * sqrt(maxf(0.0, 1.0 - e * e)) * sin(ecc)
	var w := deg_to_rad(w_deg)
	var o := deg_to_rad(node_deg)
	var inc := deg_to_rad(i_deg)
	var cw := cos(w)
	var sw := sin(w)
	var co := cos(o)
	var so := sin(o)
	var ci := cos(inc)
	var si := sin(inc)
	return DVec3.new(
		(cw * co - sw * so * ci) * xp + (-sw * co - cw * so * ci) * yp,
		(cw * so + sw * co * ci) * xp + (-sw * so + cw * co * ci) * yp,
		(sw * si) * xp + (cw * si) * yp)


## Posición heliocéntrica (eclíptica J2000, m) de un planeta con elementos JPL (`orbit` del JSON).
static func planet_position(orbit: Dictionary, t_s: float) -> DVec3:
	var el: Array = orbit["elements"]
	var rt: Array = orbit["rates_per_century"]
	var tc := t_s / SECONDS_PER_CENTURY
	var a := (float(el[0]) + float(rt[0]) * tc) * AU
	var e := float(el[1]) + float(rt[1]) * tc
	var inc := float(el[2]) + float(rt[2]) * tc
	var l := float(el[3]) + float(rt[3]) * tc
	var varpi := float(el[4]) + float(rt[4]) * tc
	var node := float(el[5]) + float(rt[5]) * tc
	return elements_to_position(a, e, inc, node, varpi - node, l - varpi)


## Base (x = nodo ascendente sobre el ecuador ICRF, z = polo) de un plano dado por su polo ecuatorial, en eclíptica.
static func plane_basis(pole_eq: DVec3) -> Array:
	var zi := DVec3.new(0, 0, 1)
	var node := zi.cross(pole_eq)
	if node.length_squared() < 1e-18:
		node = DVec3.new(1, 0, 0)
	node = node.normalized()
	var y := pole_eq.cross(node).normalized()
	return [equatorial_to_ecliptic(node), equatorial_to_ecliptic(y), equatorial_to_ecliptic(pole_eq)]


## Posición de un satélite respecto a su planeta (eclíptica J2000, m). `planet_pole_eq`: polo del planeta (ICRF),
## necesario para los marcos "equatorial".
static func satellite_position(orbit: Dictionary, t_s: float, planet_pole_eq: DVec3) -> DVec3:
	var dt := t_s - (float(orbit["epoch_jd"]) - J2000_JD) * SECONDS_PER_DAY
	var period := float(orbit["period_s"])
	var m := float(orbit["M_deg"]) + (360.0 * dt / period if period > 0.0 else 0.0)
	var w := float(orbit["w_deg"])
	var node := float(orbit["node_deg"])
	var pa := float(orbit.get("apsis_period_s", 0.0))
	var pn := float(orbit.get("node_period_s", 0.0))
	# P es el periodo SIDÉREO (JPL): la longitud media λ = Ω + ω + M avanza 360°/P; la precesión del
	# periastro y del nodo sólo reparte ese avance entre los tres ángulos.
	if pa > 1.0:
		var dw := 360.0 * dt / pa
		w += dw
		m -= dw
	if pn > 1.0:
		var dn := 360.0 * dt / pn
		node -= dn
		m += dn
	var p := elements_to_position(float(orbit["a_m"]), float(orbit["e"]), float(orbit["i_deg"]), node, w, m)
	var frame := str(orbit.get("frame", "ecliptic"))
	if frame == "ecliptic":
		return p
	var pole_eq := planet_pole_eq
	if frame == "laplace" and orbit.has("laplace_pole_ra"):
		pole_eq = radec_to_vector(float(orbit["laplace_pole_ra"]), float(orbit["laplace_pole_dec"]))
	var b := plane_basis(pole_eq)
	return b[0].mul(p.x).add(b[1].mul(p.y)).add(b[2].mul(p.z))


## Polo de rotación (ICRF) según el modelo IAU del cuerpo.
static func pole_equatorial(rot: Dictionary, t_s: float) -> DVec3:
	var tc := t_s / SECONDS_PER_CENTURY
	return radec_to_vector(float(rot.get("pole_ra", 0.0)) + float(rot.get("pole_ra_rate", 0.0)) * tc,
		float(rot.get("pole_dec", 90.0)) + float(rot.get("pole_dec_rate", 0.0)) * tc)


## Ejes del marco fijo al cuerpo en la eclíptica, con la convención del motor:
## [X = 90° E, Y = polo norte, Z = meridiano 0]. Modelo IAU (W medido desde el nodo del ecuador del cuerpo
## sobre el ecuador ICRF).
static func iau_axes(rot: Dictionary, t_s: float) -> Array:
	var pole := pole_equatorial(rot, t_s)
	var b := plane_basis(pole)  # [nodo, y, polo] ya en eclíptica
	var wd := deg_to_rad(float(rot.get("w0", 0.0)) + float(rot.get("wdot", 0.0)) * t_s / SECONDS_PER_DAY)
	var pm: DVec3 = b[0].mul(cos(wd)).add(b[1].mul(sin(wd)))
	var zp: DVec3 = b[2]
	return [zp.cross(pm).normalized(), zp, pm.normalized()]


## Ejes de una luna en rotación síncrona: polo = normal de la órbita, meridiano 0 hacia el planeta.
static func synchronous_axes(rel_pos: DVec3, rel_vel: DVec3) -> Array:
	var pole := rel_pos.cross(rel_vel)
	if pole.length_squared() < 1e-12:
		pole = DVec3.new(0, 0, 1)
	pole = pole.normalized()
	var pm := rel_pos.mul(-1.0)
	pm = pm.sub(pole.mul(pm.dot(pole))).normalized()
	return [pole.cross(pm).normalized(), pole, pm]


## v (eclíptica) → coordenadas del marco de ejes `axes` (filas = ejes del motor X, Y, Z).
static func to_frame(axes: Array, v: DVec3) -> DVec3:
	return DVec3.new(v.dot(axes[0]), v.dot(axes[1]), v.dot(axes[2]))


## Coordenadas del marco → eclíptica.
static func from_frame(axes: Array, v: DVec3) -> DVec3:
	return axes[0].mul(v.x).add(axes[1].mul(v.y)).add(axes[2].mul(v.z))
