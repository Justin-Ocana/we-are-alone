class_name SaveGame
extends RefCounted
## Partida guardada (ADR-034): un único archivo JSON en user://partida.json.
## Guarda el cuerpo dominante, la fecha del juego, la nave (posición en doble precisión, orientación, estado)
## y cada jugador: si va a bordo, su pose RELATIVA a la nave (así reaparece en el mismo sitio aunque la nave
## esté a millones de km); si no, su posición absoluta en el marco del cuerpo. También el diario.
## Se guarda al salir al menú, desde la pausa y cada 3 minutos.

const PATH := "user://partida.json"
const TEST_PATH := "user://partida_pruebas.json"
## Archivo en uso. Las pruebas y bancos automáticos usan TEST_PATH: nunca tocan la partida del jugador (ronda 10).
static var path := PATH
const VERSION := 1


static func exists() -> bool:
	return FileAccess.file_exists(path)


static func summary() -> Dictionary:
	var d := load_data()
	if d.is_empty():
		return {}
	return {"body": str(d.get("anchor_name", d.get("anchor", "?"))), "saved": int(d.get("saved_unix", 0)),
		"coop": bool(d.get("coop", false)), "play": float(d.get("log", {}).get("play_time_s", 0.0))}


static func load_data() -> Dictionary:
	if not exists():
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var d = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY or int(d.get("version", -1)) != VERSION:
		push_warning("SaveGame: partida ilegible o de otra versión")
		return {}
	return d


static func _v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _to_v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() == 3 else Vector3.ZERO


static func _basis(b: Basis) -> Array:
	return _v3(b.x) + _v3(b.y) + _v3(b.z)


static func _to_basis(a) -> Basis:
	if not (a is Array) or a.size() != 9:
		return Basis()
	return Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])).orthonormalized()


static func capture(world: SurfaceWorld) -> Dictionary:
	var d := {"version": VERSION, "saved_unix": int(Time.get_unix_time_from_system()), "anchor": world.body.id,
		"anchor_name": world.body.display_name, "coop": world.coop, "nav_target": world.nav_target,
		"time_scale": world.env.time_scale}
	if world.system != null:
		d["time_s"] = world.system.time_s
	if world.ship != null:
		var st := world.ship.state
		d["ship"] = {"pos": [st.pos_bf.x, st.pos_bf.y, st.pos_bf.z], "basis": _basis(st.basis), "vel": _v3(st.velocity),
			"landed": st.landed, "gravity": st.artificial_gravity, "floodlights": st.floodlights, "hull": st.hull_integrity,
			"gear_hold": st.gear_hold}
	var ps := []
	for a in world.players:
		var e := {"health": a.health, "fuel": a.jet_fuel, "first_person": a.first_person}
		if a.aboard != null and world.ship != null and a.aboard == world.ship:
			var rel: Transform3D = world.ship.global_transform.affine_inverse() * a.global_transform
			e["aboard"] = true
			e["rel_origin"] = _v3(rel.origin)
			e["rel_basis"] = _basis(rel.basis)
			e["seat"] = a.seat_id if a.seated else ""
		else:
			var p: DVec3 = a.position_bf()
			e["aboard"] = false
			e["pos"] = [p.x, p.y, p.z]
			e["basis"] = _basis(a.global_transform.basis)
		ps.append(e)
	d["players"] = ps
	if world.exploration != null:
		d["log"] = world.exploration.to_dict()
	if world.base != null:
		d["base"] = world.base.capture()
	if world.dialogue != null:
		d["dialogue"] = world.dialogue.capture()
	if world.prologue != null:
		d["prologue"] = world.prologue.capture()
	return d


static func save(world: SurfaceWorld) -> bool:
	if world == null or world.ship == null:
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("SaveGame: no se pudo escribir %s" % path)
		return false
	f.store_string(JSON.stringify(capture(world), "\t", false, true))
	f.close()
	return true


## Punto de aparición (lat, lon) para crear el mundo antes de aplicar la partida.
static func spawn_latlon(d: Dictionary) -> Vector2:
	var players: Array = d.get("players", [])
	if not players.is_empty() and not bool(players[0].get("aboard", false)):
		var p = players[0]["pos"]
		return CubeSphere.dir_to_latlon(DVec3.new(p[0], p[1], p[2]))
	var s: Dictionary = d.get("ship", {})
	if s.has("pos"):
		var q = s["pos"]
		return CubeSphere.dir_to_latlon(DVec3.new(q[0], q[1], q[2]))
	return Vector2(12.0, -48.0)


## Aplica la partida a un mundo recién creado (mismo cuerpo dominante).
static func apply(world: SurfaceWorld, d: Dictionary) -> void:
	world.wait_for_surface()   # primero congela y posa en el suelo; después se recolocan los que iban a bordo
	if world.system != null and d.has("time_s"):
		world.system.time_s = float(d["time_s"])
	world.env.time_scale = float(d.get("time_scale", 1.0))
	world.nav_target = str(d.get("nav_target", ""))
	if world.exploration != null and d.has("log"):
		world.exploration.from_dict(d["log"])
	var ship := world.ship
	var sd: Dictionary = d.get("ship", {})
	if ship != null and sd.has("pos"):
		var st := ship.state
		var q = sd["pos"]
		st.pos_bf = DVec3.new(q[0], q[1], q[2])
		st.basis = _to_basis(sd.get("basis"))
		st.velocity = _to_v3(sd.get("vel"))
		st.landed = bool(sd.get("landed", true))
		st.artificial_gravity = bool(sd.get("gravity", false))
		st.hull_integrity = float(sd.get("hull", 100.0))
		st.gear_hold = bool(sd.get("gear_hold", false))
		st.target_speed = 0.0
		if bool(sd.get("floodlights", false)) != st.floodlights:
			ship.cmd_toggle_floodlights()
		FloatingOrigin.reset(st.pos_bf)
		ship._sync_node()
	var players: Array = d.get("players", [])
	for i in mini(players.size(), world.players.size()):
		var e: Dictionary = players[i]
		var a: Astronaut = world.players[i]
		a.health = float(e.get("health", 100.0))
		a.jet_fuel = float(e.get("fuel", 1.0))
		if bool(e.get("first_person", true)) != a.first_person:
			a.first_person = bool(e.get("first_person", true))
			a._apply_camera()
		if bool(e.get("aboard", false)) and ship != null:
			var rel := Transform3D(_to_basis(e.get("rel_basis")), _to_v3(e.get("rel_origin")))
			a.global_transform = ship.global_transform * rel
			a.velocity = Vector3.ZERO
			a.set_meta("resume_seat", str(e.get("seat", "")))
		elif e.has("pos"):
			var p = e["pos"]
			var pb := DVec3.new(p[0], p[1], p[2])
			if a.drives_origin:
				FloatingOrigin.reset(pb)
			a.global_transform = Transform3D(_to_basis(e.get("basis")), FloatingOrigin.to_local(pb))
			a.velocity = Vector3.ZERO
			a.place_on_surface(pb, 0.3)
	# Base LF-01, diálogos oídos y prólogo (ADR-043). Partidas antiguas: no traen estas claves y siguen sin prólogo.
	if world.base != null and d.has("base"):
		world.base.apply(d["base"])
	if world.dialogue != null and d.has("dialogue"):
		world.dialogue.apply(d["dialogue"])
	if world.prologue != null and d.has("prologue"):
		world.prologue.apply(d["prologue"])
