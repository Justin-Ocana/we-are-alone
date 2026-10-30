class_name Units
extends RefCounted
## Constantes físicas y conversiones. Todo el proyecto usa SI: m, s, kg, m/s, m/s².

const G := 6.67430e-11              ## m³ kg⁻¹ s⁻² (CODATA 2018)
const AU := 1.495978707e11          ## m (definición IAU 2012)
const LIGHT_YEAR := 9.4607304725808e15  ## m (año juliano)
const PARSEC := 3.0856775814913673e16   ## m (IAU 2015)

const ASTRONAUT_HEIGHT_M := 1.85
const ASTRONAUT_EYE_HEIGHT_M := 1.70
const ASTRONAUT_RADIUS_M := 0.30


static func surface_gravity(gm: float, radius_m: float) -> float:
	return gm / (radius_m * radius_m)


## Distancia al horizonte geométrico desde una altura h sobre una esfera de radio r.
static func horizon_distance(radius_m: float, height_m: float) -> float:
	var h := maxf(height_m, 0.0)
	return sqrt(2.0 * radius_m * h + h * h)


static func format_distance(m: float) -> String:
	var a := absf(m)
	if a < 1000.0:
		return "%.1f m" % m
	if a < 1.0e7:
		return "%.2f km" % (m / 1000.0)
	if a < 0.1 * AU:
		return "%.0f km" % (m / 1000.0)
	if a < 0.1 * LIGHT_YEAR:
		return "%.3f UA" % (m / AU)
	return "%.3f al" % (m / LIGHT_YEAR)


static func format_speed(mps: float) -> String:
	if absf(mps) < 1000.0:
		return "%.1f m/s" % mps
	return "%.2f km/s" % (mps / 1000.0)
