class_name ShipParams
extends RefCounted
## Parámetros de vuelo de una nave cargados desde data/ships/*.json (ADR-012).
## Separados del código para ajustar la sensación de pilotaje sin tocar scripts.

const C := 299792458.0  ## velocidad de la luz en el vacío (m/s, exacta por definición del SI)
const REGIME_LIGHT_ID := "light"

var id := ""
var display_name := ""
var mass_kg := 60000.0
var artificial_gravity := 9.80665
var max_rate := Vector3(deg_to_rad(45), deg_to_rad(38), deg_to_rad(70))      ## rad/s (pitch, yaw, roll)
var max_ang_accel := Vector3(deg_to_rad(70), deg_to_rad(60), deg_to_rad(110))  ## rad/s²
var maneuver_speed := 25.0
var lateral_fraction := 0.5
var vertical_fraction := 0.7
var reverse_fraction := 0.2
var assist_tau := 0.8
var hover_reserve := 20.0
var regimes: Array[Dictionary] = []
var hull_box_center := Vector3(0, 1, -1.5)
var hull_box_size := Vector3(13, 3.6, 37)
var gear_drop := 1.4
var landing_max_speed := 3.0
var landing_max_tilt_deg := 18.0
var hard_impact := 8.0
var errors: PackedStringArray = []


static func load_file(path: String) -> ShipParams:
	var p := ShipParams.new()
	var text := FileAccess.get_file_as_string(path)
	var d: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if typeof(d) != TYPE_DICTIONARY:
		p.errors.append("No se pudo leer %s" % path)
		p._default_regimes()
		return p
	p.id = str(d.get("id", ""))
	p.display_name = str(d.get("name", p.id))
	p.mass_kg = float(d.get("mass_kg", p.mass_kg))
	p.artificial_gravity = float(d.get("artificial_gravity_mps2", p.artificial_gravity))
	var rot: Dictionary = d.get("rotation", {})
	if rot.has("max_rate_deg_s"):
		p.max_rate = _deg3(rot["max_rate_deg_s"])
	if rot.has("max_accel_deg_s2"):
		p.max_ang_accel = _deg3(rot["max_accel_deg_s2"])
	var tr: Dictionary = d.get("translation", {})
	p.maneuver_speed = float(tr.get("maneuver_speed_mps", p.maneuver_speed))
	p.lateral_fraction = float(tr.get("lateral_accel_fraction", p.lateral_fraction))
	p.vertical_fraction = float(tr.get("vertical_accel_fraction", p.vertical_fraction))
	p.reverse_fraction = float(tr.get("reverse_speed_fraction", p.reverse_fraction))
	p.assist_tau = maxf(0.05, float(tr.get("assist_time_constant_s", p.assist_tau)))
	p.hover_reserve = float(tr.get("hover_accel_reserve_mps2", p.hover_reserve))
	for r in d.get("regimes", []):
		p.regimes.append(r)
	if p.regimes.is_empty():
		p._default_regimes()
	var col: Dictionary = d.get("collision", {})
	if col.has("hull_box_center"):
		p.hull_box_center = _v3(col["hull_box_center"])
	if col.has("hull_box_size"):
		p.hull_box_size = _v3(col["hull_box_size"])
	p.gear_drop = float(col.get("gear_drop_m", p.gear_drop))
	p.landing_max_speed = float(col.get("landing_max_speed_mps", p.landing_max_speed))
	p.landing_max_tilt_deg = float(col.get("landing_max_tilt_deg", p.landing_max_tilt_deg))
	p.hard_impact = float(col.get("hard_impact_mps", p.hard_impact))
	return p


func _default_regimes() -> void:
	regimes = [{"id": "maneuver", "name": "Maniobra", "max_speed_mps": 60.0, "accel_mps2": 10.0}]


static func _deg3(a: Array) -> Vector3:
	return Vector3(deg_to_rad(float(a[0])), deg_to_rad(float(a[1])), deg_to_rad(float(a[2])))


static func _v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func regime(i: int) -> Dictionary:
	return regimes[clampi(i, 0, regimes.size() - 1)]


func regime_max_speed(i: int) -> float:
	return minf(float(regime(i).get("max_speed_mps", 60.0)), C)


func regime_accel(i: int) -> float:
	return float(regime(i).get("accel_mps2", 10.0))


func is_light(i: int) -> bool:
	return str(regime(i).get("id", "")) == REGIME_LIGHT_ID


func light_index() -> int:
	for i in regimes.size():
		if is_light(i):
			return i
	return -1


## Formato legible de una velocidad: m/s, km/s y fracción de c.
static func format_speed(v: float) -> String:
	var a := absf(v)
	var s := ""
	if a < 1000.0:
		s = "%.1f m/s" % v
	elif a < 1.0e6:
		s = "%.2f km/s" % (v / 1000.0)
	else:
		s = "%.0f km/s" % (v / 1000.0)
	var frac := a / C
	if frac >= 0.0001:
		s += "  (%.4f c)" % frac
	return s
