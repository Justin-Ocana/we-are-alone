class_name BodyDef
extends RefCounted
## Definición de un cuerpo celeste cargada desde JSON (ver ADR-005).
## Cada magnitud física conserva su calidad (measured/estimated/approximate/fictional) y su fuente.

const SCHEMA_VERSION := 1
const QUALITIES := ["measured", "estimated", "approximate", "fictional"]

var id: String = ""
var display_name: String = ""
var kind: String = ""
var parent_id: String = ""
var description: String = ""
var raw: Dictionary = {}
var errors: PackedStringArray = []


static func from_dict(d: Dictionary) -> BodyDef:
	var b := BodyDef.new()
	b.raw = d
	b._validate()
	b.id = str(d.get("id", ""))
	b.display_name = str(d.get("name", b.id))
	b.kind = str(d.get("kind", ""))
	b.parent_id = str(d.get("parent", ""))
	b.description = str(d.get("description", ""))
	return b


static func load_file(path: String) -> BodyDef:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		var b := BodyDef.new()
		b.errors.append("No se pudo leer %s" % path)
		return b
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		var b2 := BodyDef.new()
		b2.errors.append("JSON inválido en %s" % path)
		return b2
	return from_dict(parsed)


func is_valid() -> bool:
	return errors.is_empty()


func _validate() -> void:
	if int(raw.get("schema_version", -1)) != SCHEMA_VERSION:
		errors.append("schema_version distinto de %d" % SCHEMA_VERSION)
	for key in ["id", "name", "kind", "physical", "surface"]:
		if not raw.has(key):
			errors.append("Falta el campo '%s'" % key)
	var phys: Dictionary = raw.get("physical", {})
	for key in ["mean_radius", "mass"]:
		if not phys.has(key):
			errors.append("Falta physical.%s" % key)
			continue
		var q: Dictionary = phys[key]
		if not q.has("value") or float(q["value"]) <= 0.0:
			errors.append("physical.%s.value debe ser > 0" % key)
		if not QUALITIES.has(str(q.get("quality", ""))):
			errors.append("physical.%s.quality inválida" % key)


## Valor numérico de una magnitud física (`physical.<key>.value`) o `fallback`.
func physical(key: String, fallback: float = 0.0) -> float:
	var q: Variant = raw.get("physical", {}).get(key)
	if q is Dictionary and q.has("value"):
		return float(q["value"])
	return fallback


func physical_quality(key: String) -> String:
	var q: Variant = raw.get("physical", {}).get(key)
	if q is Dictionary:
		return str(q.get("quality", "unknown"))
	return "unknown"


func radius_m() -> float:
	return physical("mean_radius")


func mass_kg() -> float:
	return physical("mass")


func gm() -> float:
	return physical("gm", Units.G * mass_kg())


func surface_gravity() -> float:
	return Units.surface_gravity(gm(), radius_m())


func gravity_at_distance(r_m: float) -> float:
	return gm() / (r_m * r_m)


func solar_day_s() -> float:
	return physical("solar_day", physical("sidereal_rotation_period", 86400.0))


func axial_tilt_deg() -> float:
	return physical("axial_tilt", 0.0)


func surface() -> Dictionary:
	return raw.get("surface", {})


func terrain_profile() -> String:
	return str(surface().get("terrain_profile", "arid_rocky"))


func terrain_seed() -> int:
	return int(surface().get("seed", 1))


func terrain_note() -> String:
	return str(surface().get("terrain_note", ""))


func atmosphere() -> Dictionary:
	return raw.get("atmosphere", {"present": false})


func has_atmosphere() -> bool:
	return bool(atmosphere().get("present", false))


func is_fictional() -> bool:
	return physical_quality("mean_radius") == "fictional"


# --- Sistema Solar (ADR-024) --------------------------------------------------------------

func orbit() -> Dictionary:
	return raw.get("orbit", {})


func rotation() -> Dictionary:
	return raw.get("rotation", {})


func render() -> Dictionary:
	return raw.get("render", {})


## "solid", "none" (gigante gaseoso), "plasma" (Sol), "shattered" (Tierra destruida).
func surface_type() -> String:
	return str(surface().get("type", "solid"))


func has_solid_surface() -> bool:
	return surface_type() == "solid"


func in_system() -> bool:
	return orbit().has("model")


func render_color(key: String = "color", fallback := Color(0.6, 0.6, 0.6)) -> Color:
	var c: Variant = render().get(key)
	if c is Array and c.size() >= 3:
		return Color(c[0], c[1], c[2])
	return fallback


func flattening() -> float:
	return float(render().get("flattening", 0.0))
