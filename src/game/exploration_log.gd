class_name ExplorationLog
extends RefCounted
## Diario de exploración (ADR-034): lo que has visitado, escaneado y recogido. Es un registro, no una
## progresión: no desbloquea nada. Se guarda con la partida.
## - Visitas: cuerpos sobre cuya superficie has caminado o aterrizado (y cuándo por primera vez).
## - Escaneos: datos del cuerpo apuntado con el escáner de la nave o del traje.
## - Muestras: rocas recogidas en la superficie; se analizan en el laboratorio del almacén de la nave.
## - Estadísticas: distancia recorrida en la nave, fotos, tiempo de juego.

signal changed

var visited := {}          ## id -> {first: unix, landed: bool, name}
var scans := {}            ## id -> {when: unix, name, lines: [String]}
var samples: Array = []    ## [{body, name, lat, lon, when, analyzed, report}]
var photos := 0
var nexus: Array = []      ## cuerpos cuyo componente del NEXUS se ha recuperado (NexusQuest)
var nexus_sites := {}      ## cuerpo → dirección BF [x, y, z] de su instalación (se elige al llegar, de día)
var beacons: Array = []    ## balizas plantadas: [{body, pos: [x, y, z] BF, n, when}] (BeaconManager)
var ship_distance_m := 0.0
var play_time_s := 0.0


func mark_visit(body: BodyDef, landed: bool) -> bool:
	var e: Dictionary = visited.get(body.id, {})
	var is_new := e.is_empty()
	if is_new:
		e = {"first": Time.get_unix_time_from_system(), "landed": landed, "name": body.display_name}
	elif landed and not bool(e.get("landed", false)):
		e["landed"] = true
	else:
		return false
	visited[body.id] = e
	changed.emit()
	return is_new


func add_scan(body: BodyDef, lines: PackedStringArray) -> bool:
	var is_new := not scans.has(body.id)
	scans[body.id] = {"when": Time.get_unix_time_from_system(), "name": body.display_name, "lines": Array(lines)}
	changed.emit()
	return is_new


func add_sample(body: BodyDef, latlon: Vector2) -> Dictionary:
	var s := {"body": body.id, "name": body.display_name, "lat": latlon.x, "lon": latlon.y,
		"when": Time.get_unix_time_from_system(), "analyzed": false, "report": ""}
	samples.append(s)
	changed.emit()
	return s


func pending_samples() -> int:
	var n := 0
	for s in samples:
		if not bool(s["analyzed"]):
			n += 1
	return n


func to_dict() -> Dictionary:
	return {"visited": visited, "scans": scans, "samples": samples, "photos": photos,
		"ship_distance_m": ship_distance_m, "play_time_s": play_time_s, "nexus": nexus, "nexus_sites": nexus_sites, "beacons": beacons}


func from_dict(d: Dictionary) -> void:
	visited = d.get("visited", {})
	scans = d.get("scans", {})
	samples = d.get("samples", [])
	photos = int(d.get("photos", 0))
	ship_distance_m = float(d.get("ship_distance_m", 0.0))
	play_time_s = float(d.get("play_time_s", 0.0))
	nexus = d.get("nexus", [])
	nexus_sites = d.get("nexus_sites", {})
	beacons = d.get("beacons", [])
	changed.emit()


## Informe de laboratorio de una muestra: datos reales del cuerpo (gravedad, temperatura, atmósfera,
## composición descrita en el catálogo) y una mineralogía plausible marcada como procedural.
static func analyze(body: BodyDef, sample: Dictionary) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%.3f:%.3f" % [sample["body"], sample["lat"], sample["lon"]])
	var minerals: Array = _minerals_for(body)
	var picks := PackedStringArray()
	var left := 100.0
	for i in mini(3, minerals.size()):
		var m: String = minerals[(i + rng.randi_range(0, 1)) % minerals.size()]
		if picks.has(m):
			continue
		var pct := rng.randf_range(15.0, 45.0) if i < 2 else left
		pct = minf(pct, left)
		left -= pct
		picks.append("%s %.0f %%" % [m, pct])
	var lines := PackedStringArray()
	lines.append("Muestra de %s (%.3f°, %.3f°)" % [body.display_name, sample["lat"], sample["lon"]])
	lines.append("Composición (PROCEDURAL, plausible para este cuerpo): " + ", ".join(picks))
	lines.append("Densidad media del cuerpo: %.0f kg/m³ · gravedad %.2f m/s²" % [body.mass_kg() / (4.0 / 3.0 * PI * pow(body.radius_m(), 3.0)),
		body.surface_gravity()])
	var age := rng.randf_range(1.0, 4.4)
	lines.append("Edad estimada de exposición: %.1f mil millones de años (procedural)" % age)
	return "\n".join(lines)


const ICY := ["europa", "enceladus", "ganymede", "callisto", "triton", "pluto", "charon", "miranda", "ariel", "umbriel",
	"titania", "oberon", "tethys", "dione", "rhea", "iapetus", "mimas"]


static func _minerals_for(body: BodyDef) -> Array:
	if body.id in ICY:
		return ["hielo de agua", "hielo de amoníaco", "sales hidratadas", "tolinas", "polvo de silicatos"]
	match body.id:
		"io":
			return ["azufre", "dióxido de azufre helado", "basalto", "silicatos ricos en magnesio"]
		"titan":
			return ["hielo de agua", "tolinas", "hidrocarburos sólidos", "benceno helado"]
		"mars":
			return ["basalto", "óxidos de hierro (hematita)", "sulfatos", "arcillas (filosilicatos)", "olivino"]
		"moon":
			return ["anortosita (plagioclasa)", "basalto de mare", "regolito vítreo", "ilmenita", "piroxeno"]
		"venus":
			return ["basalto", "piroxeno", "magnetita", "anhidrita"]
		"mercury":
			return ["silicatos pobres en hierro", "grafito", "enstatita", "sulfuros"]
		"phobos", "deimos":
			return ["condrita carbonácea", "filosilicatos", "regolito oscuro", "olivino"]
	return ["silicatos", "regolito", "óxidos metálicos", "hielo (en sombra)"]
