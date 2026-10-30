class_name LunarBase
extends Node3D
## Base lunar LF-01 de MacSpaces (ADR-043). Se coloca sobre la explanada del terreno en (SITE_LAT, SITE_LON) y
## se recoloca desde su posición BF exacta en cada recentrado del origen flotante (nunca acumula desplazamientos).
##
## Gestiona: puertas (BaseDoor), luces por sala (emergencia ámbar parpadeante / blancas con energía auxiliar),
## qué salas se dibujan (la del jugador y las visibles por puertas abiertas), la cápsula, la palanca, la esclusa y
## las compuertas del techo del hangar, e interacciones (Astronaut las consulta con `nearest_interaction`).
## La historia (qué pasa al usar cada cosa) la decide PrologueDirector escuchando `interacted` y `room_entered`.

signal interacted(astro: Node, id: String, kind: String)
signal room_entered(astro: Node, room: String)
signal door_denied(astro: Node, door_id: String, state: String)

const INTERACT_RANGE := 1.7
const DOOR_PANEL_RANGE := 2.2
const EMERGENCY_ENERGY := 0.85

var world: SurfaceWorld
var pos_bf: DVec3                  ## origen de la base (suelo) en el marco del cuerpo
var basis_bf := Basis()            ## columnas: este, arriba, sur
var builder: BaseBuilder
var body: StaticBody3D
var doors := {}                    ## id → BaseDoor
var power_aux := false
var artificial_gravity := false     ## 1 g en el interior (con la energía restablecida; FICTICIO)
var roof_open := 0.0               ## 0 cerrado · 1 abierto
var roof_target := 0.0
var _roof_beep := 0.0
var capsule_open := 0.0
var capsule_target := 0.0
var pods_assigned: Array = [false, false, false, false, false, false]   ## cápsulas con un jugador dentro
var _pod_open: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var lever_on := false
var airlock_phase := ""            ## "" | "despresurizando" | "abierta" | "presurizando"
var airlock_t := 0.0
var label_override := {}           ## id de terminal → texto de la acción ("" = no se puede usar ahora)
var _light_base := {}              ## OmniLight3D → [color, energía, parpadea]
var _rooms_of := {}                ## astronauta → sala actual
var _visible_rooms := {}
var _t := 0.0
var _hum: AudioStreamPlayer3D


func setup(p_world: SurfaceWorld) -> void:
	world = p_world
	var dir := CubeSphere.latlon_to_dir(BaseLayout.SITE_LAT, BaseLayout.SITE_LON)
	var h := world.terrain.height_at_dir(dir)
	pos_bf = dir.mul(world.terrain.radius + h)
	var up := dir.to_vector3()
	var north := (Vector3.UP - up * up.dot(Vector3.UP)).normalized()
	var east := north.cross(up).normalized()
	basis_bf = Basis(east, up, -north)


func _ready() -> void:
	name = "BaseLF01"
	body = StaticBody3D.new()
	body.name = "Colision"
	body.collision_layer = Layers.bit(Layers.PHYS_SHIP)
	body.collision_mask = 0
	add_child(body)
	builder = BaseBuilder.new()
	builder.build(self, body)
	var panel_mat: Material = builder.mats["furn"]
	var frame_mat: Material = builder.mats["metal"]
	for id in BaseLayout.DOORS:
		var d := BaseDoor.new()
		d.name = "Puerta_" + id
		add_child(d)
		d.setup(id, BaseLayout.DOORS[id], panel_mat, frame_mat, body)
		d.moved.connect(_on_door_moved.bind(d))
		doors[id] = d
	for room in builder.lights:
		var emergency: bool = BaseLayout.ROOMS[room][6] == "emergencia"
		var i := 0
		for l: OmniLight3D in builder.lights[room]:
			_light_base[l] = [builder.EMERGENCY if emergency else Color.BLACK, EMERGENCY_ENERGY if emergency else 0.0, (i + room.length()) % 3 == 0]
			i += 1
	_hum = AudioStreamPlayer3D.new()
	_hum.stream = GameAudio.stream("ship_hum", true)
	_hum.bus = "Ambiente"
	_hum.volume_db = -14.0
	_hum.max_distance = 60.0
	_hum.position = Vector3(0, 2.0, -60.0)
	add_child(_hum)
	_hum.play()
	_limit_detail_range()
	FloatingOrigin.origin_shifted.connect(func(_d: Vector3): _place())
	world.anchor_changed.connect(_on_anchor_changed)
	_place()
	_apply_lights()


## Puertas, rótulos, logotipos, cápsulas y demás piezas sueltas del interior no se dibujan a más de 80 m (ronda 11:
## desde el punto de aparición clásico, a 1,5 km, añadían ~340 llamadas de dibujo). La carcasa exterior y el techo
## del hangar sí se ven de lejos.
func _limit_detail_range() -> void:
	var keep := {}
	for mi in builder.batcher.meshes_by_batch.get("base:ext", []):
		keep[mi] = true
	var roof: Node = builder.nodes.get("techo")
	for n in find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if keep.has(g) or g.visibility_range_end > 0.0 or (roof != null and roof.is_ancestor_of(g)):
			continue
		if g.layers & Layers.bit(Layers.WORLD) and not g is Label3D:
			continue   # balizas y logotipos exteriores
		g.visibility_range_end = 80.0


func _place() -> void:
	if world != null and world.body.id != "moon":
		return
	global_transform = Transform3D(basis_bf, FloatingOrigin.to_local(pos_bf))


## La base sólo existe mientras el cuerpo dominante es la Luna (ronda 11: al viajar a otro mundo seguía colocada con
## coordenadas lunares en el marco del nuevo cuerpo, con sus colisiones).
func _on_anchor_changed(id: String) -> void:
	var here := id == "moon"
	visible = here
	set_process(here)
	body.collision_layer = Layers.bit(Layers.PHYS_SHIP) if here else 0
	for n in find_children("*", "StaticBody3D", true, false):
		(n as StaticBody3D).collision_layer = Layers.bit(Layers.PHYS_SHIP) if here else 0
	for d in doors.values():
		d.process_mode = Node.PROCESS_MODE_INHERIT if here else Node.PROCESS_MODE_DISABLED
	if here:
		_place()


## Punto local de la base → posición del motor (marco local del origen flotante).
func to_engine(p: Vector3) -> Vector3:
	return global_transform * p


func to_base(p: Vector3) -> Vector3:
	return global_transform.affine_inverse() * p


func point_bf(p: Vector3) -> DVec3:
	return pos_bf.add_vector3(basis_bf * p)


## Sala del astronauta (o "" si está fuera de la base).
func room_of(a: Node3D) -> String:
	return BaseLayout.room_at(to_base(a.global_position + a.global_transform.basis.y * 0.5))


func _process(delta: float) -> void:
	_t += delta
	var people := []
	var outside := false
	var current := {}
	var astros: Array = world.all_people() if world != null else []
	for a in astros:
		if not is_instance_valid(a):
			continue
		var lp := to_base(a.global_position)
		people.append(lp)
		var room := BaseLayout.room_at(lp + Vector3(0, 0.5, 0))
		if room == "":
			outside = true
		current[room] = true
		if _rooms_of.get(a, "-") != room:
			_rooms_of[a] = room
			if a.has_method("set_habitat"):
				a.set_habitat(room != "" and not (room == "esclusa" and airlock_phase in ["abierta", "despresurizando", "presurizando"]))
			if room != "":
				room_entered.emit(a, room)
	for id in doors:
		doors[id].update(delta, people)
	_update_visibility(current, outside)
	_update_lights(delta)
	_update_anims(delta)


# --- Visibilidad por salas ----------------------------------------------------------------------

func _update_visibility(current: Dictionary, outside: bool) -> void:
	var vis := {}
	var frontier: Array = []
	for room in current:
		if room != "":
			vis[room] = true
			frontier.append(room)
	if outside:
		for room in ["esclusa", "observatorio", "hangar"]:
			vis[room] = true
	# Dos saltos a través de puertas abiertas (se ve el pasillo y lo que hay al fondo de una puerta abierta).
	for depth in 2:
		var next: Array = []
		for room in frontier:
			for nb in BaseLayout.neighbors(room):
				var d: BaseDoor = doors[nb[1]]
				if d.open > 0.02 and not vis.has(nb[0]):
					vis[nb[0]] = true
					next.append(nb[0])
		frontier = next
	# El exterior también se ve desde el observatorio (ventanales y cúpula), el hangar con el techo abierto y la
	# esclusa con la escotilla abierta (ronda 11).
	var ext_visible := outside or current.has("observatorio") or (current.has("hangar") and roof_open > 0.02) 		or (current.has("esclusa") and airlock_phase == "abierta")
	vis["__ext"] = ext_visible
	if vis.hash() == _visible_rooms.hash() and _visible_rooms.size() == vis.size():
		return
	_visible_rooms = vis
	for b in builder.batcher.meshes_by_batch:
		var room := str(b).trim_prefix("base:")
		var show := ext_visible if room == "ext" else vis.has(room)
		for mi: MeshInstance3D in builder.batcher.meshes_by_batch[b]:
			mi.visible = show
	for room in builder.lights:
		for l: OmniLight3D in builder.lights[room]:
			l.visible = vis.has(room) and float(_light_base[l][1]) > 0.0


func _on_door_moved(open: bool, d: BaseDoor) -> void:
	GameAudio.play_at("door_open" if open else "door_close", d, Vector3(0, 1.2, 0), -4.0, 25.0)
	_visible_rooms = {}   # recalcular el próximo fotograma


# --- Luces ---------------------------------------------------------------------------------------

func set_power_aux(on: bool) -> void:
	power_aux = on
	artificial_gravity = on
	for id in BaseLayout.AUX_UNLOCKS:
		if on and doors[id].state == "locked_power":
			doors[id].set_state("open")
	_apply_lights()


## Parpadeo de arranque de la red: sólo las luces (antes desbloqueaba puertas y la gravedad a ratos).
func flicker_lights(on: bool) -> void:
	var keep := power_aux
	power_aux = on
	_apply_lights()
	power_aux = keep


func _apply_lights() -> void:
	for room in builder.lights:
		var emergency: bool = BaseLayout.ROOMS[room][6] == "emergencia"
		var lit_white: bool = power_aux and room in BaseLayout.AUX_LIT
		var col: Color = BaseBuilder.WHITE if lit_white else (BaseBuilder.EMERGENCY if emergency else Color.BLACK)
		var energy := (2.4 if room == "hangar" else 1.15) if lit_white else (EMERGENCY_ENERGY if emergency else 0.0)
		if room == "hangar" and not lit_white:
			energy = 1.5
		var i := 0
		for l: OmniLight3D in builder.lights[room]:
			l.light_color = col
			_light_base[l] = [col, energy, not lit_white and (i + room.length()) % 3 == 0]
			i += 1
		var lm: StandardMaterial3D = builder.lamp_mats[room]
		lm.albedo_color = col * (1.4 if lit_white else 0.9) if energy > 0.0 else Color(0.05, 0.05, 0.05)
	_visible_rooms = {}


## Parpadeo de las luces de emergencia: ruido suave más apagones breves e irregulares en una de cada tres.
func _update_lights(_delta: float) -> void:
	for l: OmniLight3D in _light_base:
		if not l.visible:
			continue
		var e: Array = _light_base[l]
		var energy: float = e[1]
		if e[2] and energy > 0.0:
			var ph := float(l.get_instance_id() % 97)
			var n := sin(_t * 7.3 + ph) * sin(_t * 2.1 + ph * 0.37)
			var drop := 1.0 if fmod(_t * 0.37 + ph * 0.13, 1.0) > 0.07 else 0.08
			energy *= (0.82 + 0.18 * n) * drop
		l.light_energy = energy


# --- Animaciones: cápsula, palanca, esclusa, techo -------------------------------------------------

func open_capsule() -> void:
	capsule_target = 1.0
	GameAudio.play_at("airlock_cycle", self, Vector3(0, 1.5, -98.0), -6.0, 20.0)


func pull_lever() -> void:
	lever_on = true
	GameAudio.play_at("stand", self, Vector3(-14.4, 1.3, -39.0), 0.0, 15.0)


func open_roof() -> void:
	if roof_target < 1.0:
		roof_target = 1.0
		GameAudio.play_at("airlock_cycle", self, Vector3(0, 20.0, 34.0), 0.0, 120.0)


func close_roof() -> void:
	if roof_target > 0.0:
		roof_target = 0.0
		GameAudio.play_at("airlock_cycle", self, Vector3(0, 20.0, 34.0), 0.0, 120.0)


## ¿Está la nave dentro del recinto del hangar (en planta, hasta 400 m de altura)?
func ship_over_hangar(s: Ship) -> bool:
	if s == null:
		return false
	var lp := to_base(s.global_position)
	return BaseLayout.room_rect("hangar").grow(-2.0).has_point(Vector2(lp.x, lp.z)) and lp.y > -2.0 and lp.y < 400.0


## Despegue desde el hangar: sólo con las compuertas abiertas del todo (Ship.takeoff_guard).
func takeoff_block_reason(s: Ship) -> String:
	if ship_over_hangar(s) and roof_open < 0.98:
		open_roof()
		return "Abriendo las compuertas del hangar: espera a que terminen"
	return ""


## Coloca las compuertas del techo sin animación (partidas sin prólogo o cargadas).
func set_roof(open: bool) -> void:
	roof_target = 1.0 if open else 0.0
	roof_open = roof_target - 0.0001 if open else 0.0001


## Ciclo de la esclusa: cierra la puerta interior, despresuriza (10 s) y abre la escotilla exterior.
func start_airlock_cycle() -> void:
	if airlock_phase != "":
		return
	airlock_phase = "despresurizando"
	airlock_t = 0.0
	doors["d_esclusa"].force_closed = true
	GameAudio.play_at("airlock_cycle", self, Vector3(40.0, 2.0, 63.0), 0.0, 30.0)


## Vuelta (ronda 11): con la escotilla abierta, la cierra, presuriza (8 s) y abre la puerta interior al hangar.
func start_repressurize() -> void:
	if airlock_phase != "abierta":
		return
	airlock_phase = "presurizando"
	airlock_t = 0.0
	doors["d_exterior"].force_open = false
	GameAudio.play_at("airlock_cycle", self, Vector3(40.0, 2.0, 63.0), 0.0, 30.0)


## Panel interior fuera del prólogo: despresurizar para salir o presurizar para entrar.
func cycle_airlock() -> void:
	if airlock_phase == "":
		start_airlock_cycle()
	elif airlock_phase == "abierta":
		start_repressurize()


## Reserva la cápsula `i` para un jugador (su puerta se abrirá con las demás al terminar la reanimación).
func assign_pod(i: int) -> void:
	if i >= 0 and i < pods_assigned.size():
		pods_assigned[i] = true


func next_free_pod() -> int:
	for i in pods_assigned.size():
		if not pods_assigned[i]:
			return i
	return pods_assigned.size() - 1


## Texto de la acción de salir en todas las cápsulas ("" = todavía no se puede).
func set_capsule_label(text) -> void:
	for id in BaseLayout.TERMINALS:
		if BaseLayout.TERMINALS[id][3] == "capsule":
			if text == null:
				label_override.erase(id)
			else:
				label_override[id] = text


func _update_anims(delta: float) -> void:
	capsule_open = move_toward(capsule_open, capsule_target, delta * 0.35)
	var pdoors: Array = builder.nodes.get("pod_doors", [])
	for i in pdoors.size():
		var tgt := capsule_target if pods_assigned[i] else 0.0
		if is_equal_approx(_pod_open[i], tgt):
			continue
		_pod_open[i] = move_toward(_pod_open[i], tgt, delta * 0.35)
		var e: Array = pdoors[i]
		(e[0] as Node3D).position = (e[2] as Vector3) + Vector3(0, _pod_open[i] * 2.1, 0)
		(e[1] as Node3D).position = (e[3] as Vector3) + Vector3(0, _pod_open[i] * 2.4, 0)
	var lever: MeshInstance3D = builder.nodes.get("palanca")
	if lever != null:
		lever.rotation.z = lerpf(lever.rotation.z, 0.6 if lever_on else -0.6, 1.0 - exp(-6.0 * delta))
	# Compuertas del techo: 12 s con arranque y frenado suaves; balizas y avisos mientras se mueven. Con alguien a los
	# mandos de la nave dentro del recinto, se abren solas (para despegar o para entrar).
	var ship := world.ship if world != null else null
	if ship != null and not ship.immobilized and ship.pilot != null and ship_over_hangar(ship) and roof_target < 1.0:
		open_roof()
	var moving := not is_equal_approx(roof_open, roof_target)
	if moving:
		roof_open = move_toward(roof_open, roof_target, delta / 12.0)
		var e := roof_open * roof_open * (3.0 - 2.0 * roof_open)
		var roof: Node3D = builder.nodes["techo"]
		var w: float = builder.nodes["techo_w"]
		var r := BaseLayout.room_rect("hangar")
		var i := 0
		for leaf: Node3D in roof.get_children():
			var side := -1.0 if i == 0 else 1.0
			leaf.position.x = r.get_center().x + side * w * (0.25 + 0.5 * e)
			i += 1
		_roof_beep -= delta
		if _roof_beep <= 0.0:
			_roof_beep = 1.0
			GameAudio.play_at("beep", self, Vector3(0, 21.0, 34.0), -2.0, 90.0)
	for bc: Array in builder.nodes.get("roof_beacons", []):
		var on := 1.0 if moving else 0.0
		var pulse := maxf(0.0, sin(_t * 9.0 + bc[0].position.x * 0.1)) * on
		(bc[0] as OmniLight3D).light_energy = 2.5 * pulse
		((bc[1] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = Color(0.25, 0.12, 0.03).lerp(Color(1.6, 0.7, 0.1), pulse)
	if airlock_phase == "despresurizando":
		airlock_t += delta
		var kpa := maxf(0.0, 101.0 * (1.0 - airlock_t / 10.0))
		_set_label("panel_esclusa", "DESPRESURIZANDO\n%d kPa" % int(kpa))
		if airlock_t >= 10.0:
			airlock_phase = "abierta"
			doors["d_exterior"].force_open = true
			_set_label("panel_esclusa", "0 kPa · EXTERIOR SEGURO\nESCOTILLA ABIERTA")
			for a in world.all_people():
				if room_of(a) == "esclusa" and a.has_method("set_habitat"):
					a.set_habitat(false)
	elif airlock_phase == "presurizando":
		airlock_t += delta
		_set_label("panel_esclusa", "PRESURIZANDO\n%d kPa" % int(minf(101.0, 101.0 * airlock_t / 8.0)))
		if airlock_t >= 8.0:
			airlock_phase = ""
			doors["d_esclusa"].force_closed = false
			_set_label("panel_esclusa", "PRESIÓN 101 kPa\nEXTERIOR: VACÍO")
			for a in world.all_people():
				if room_of(a) == "esclusa" and a.has_method("set_habitat"):
					a.set_habitat(true)


func _set_label(id: String, text: String) -> void:
	var l: Label3D = builder.labels.get(id)
	if l != null:
		l.text = text


func set_screen(id: String, text: String) -> void:
	_set_label(id, text)


# --- Interacción ---------------------------------------------------------------------------------

## Lo más cercano que se puede usar: terminal (al alcance y de frente) o el panel de una puerta cerrada con llave.
func nearest_interaction(a: Node3D) -> Dictionary:
	if not visible:
		return {}
	var lp := to_base(a.global_position)
	var fwd := (global_transform.basis.inverse() * -a.global_transform.basis.z)
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-6 else Vector3.FORWARD
	var best := {}
	var best_d := INF
	for id in BaseLayout.TERMINALS:
		var t: Array = BaseLayout.TERMINALS[id]
		var lbl: String = label_override.get(id, t[0])
		if lbl == "":
			continue
		var tp: Vector3 = t[2]
		var to := Vector3(tp.x - lp.x, 0.0, tp.z - lp.z)
		var d := to.length()
		var reach := INTERACT_RANGE + (1.4 if t[3] == "screen" or id == "consola_ops" else 0.0)
		if d > reach or absf(tp.y - (lp.y + 1.0)) > 1.6:
			continue
		if d > 0.5 and fwd.dot(to / d) < 0.2:
			continue
		if d < best_d:
			best_d = d
			best = {"id": id, "label": lbl, "kind": t[3]}
	if not best.is_empty():
		return best
	for id in doors:
		var dr: BaseDoor = doors[id]
		if (dr.is_locked() or dr.state == "cycle") and dr.distance_to_local(lp) < DOOR_PANEL_RANGE:
			return {"id": "door:" + id, "label": _door_label(dr), "kind": "door"}
	return {}


func _door_label(d: BaseDoor) -> String:
	match d.state:
		"locked_power":
			return "Puerta sin energía"
		"locked_auth":
			return "Acceso restringido"
		"blocked":
			return "Puerta obstruida"
		"locked_script":
			return "Puerta bloqueada"
		"cycle":
			return "Escotilla exterior"
	return "Puerta"


func interact(a: Node, id: String, kind: String) -> void:
	if Net.is_client() and a is Astronaut:
		# En línea la historia la lleva el anfitrión: se le pide y él responde (ADR-044).
		GameAudio.play("beep" if kind != "door" else "error", -6.0)
		Net.rpc_id(1, "request", "interact", [id, kind])
		return
	if kind == "hangar_roof":
		GameAudio.play("beep", -6.0)
		if world.prologue != null and world.prologue.active and world.prologue.step != "completado":
			if world.has_method("show_note"):
				world.show_note(a, "Compuertas bloqueadas: la nave espera reparación (completa el prólogo).")
			return
		if roof_target > 0.5:
			close_roof()
		else:
			open_roof()
		return
	if kind == "airlock_ext":
		# Desde fuera: si la esclusa está presurizada, se vacía y se abre la escotilla para entrar.
		GameAudio.play("beep", -6.0)
		if airlock_phase == "":
			start_airlock_cycle()
		return
	if kind == "door":
		var did := id.trim_prefix("door:")
		GameAudio.play("error", -6.0)
		door_denied.emit(a, did, doors[did].state)
		return
	GameAudio.play("beep", -6.0)
	interacted.emit(a, id, kind)


# --- Guardado ------------------------------------------------------------------------------------

func capture() -> Dictionary:
	var ds := {}
	for id in doors:
		ds[id] = doors[id].state
	return {"doors": ds, "power_aux": power_aux, "roof": roof_target, "capsule": capsule_target, "lever": lever_on,
		"airlock": airlock_phase, "labels": label_override.duplicate(), "pods": pods_assigned.duplicate()}


func apply(d: Dictionary) -> void:
	var ds: Dictionary = d.get("doors", {})
	for id in ds:
		if doors.has(id):
			doors[id].set_state(str(ds[id]))
	lever_on = bool(d.get("lever", false))
	label_override = (d.get("labels", {}) as Dictionary).duplicate()
	_apply_pods(d)
	capsule_target = float(d.get("capsule", 0.0))
	capsule_open = capsule_target
	for i in _pod_open.size():
		_pod_open[i] = capsule_target - 0.0001 if pods_assigned[i] else 0.0001
	roof_target = float(d.get("roof", 0.0))
	roof_open = roof_target - 0.0001   # fuerza a colocar las compuertas en el siguiente fotograma
	airlock_phase = str(d.get("airlock", ""))
	if airlock_phase == "despresurizando" or airlock_phase == "presurizando":
		airlock_phase = ""
	if airlock_phase == "abierta":
		doors["d_exterior"].force_open = true
		doors["d_esclusa"].force_closed = true
	capsule_open = capsule_target - 0.0001
	set_power_aux(bool(d.get("power_aux", false)))


func _apply_pods(d: Dictionary) -> void:
	var p: Array = d.get("pods", [])
	for i in mini(p.size(), pods_assigned.size()):
		pods_assigned[i] = pods_assigned[i] or bool(p[i])


## Estado del anfitrión en un cliente: sólo cambia lo distinto y deja que las animaciones sigan solas.
func apply_net(d: Dictionary) -> void:
	var ds: Dictionary = d.get("doors", {})
	for id in ds:
		if doors.has(id) and doors[id].state != str(ds[id]):
			doors[id].set_state(str(ds[id]))
	label_override = (d.get("labels", {}) as Dictionary).duplicate()
	_apply_pods(d)
	capsule_target = float(d.get("capsule", capsule_target))
	roof_target = float(d.get("roof", roof_target))
	lever_on = bool(d.get("lever", lever_on))
	var phase := str(d.get("airlock", ""))
	if phase != airlock_phase:
		if phase == "despresurizando":
			start_airlock_cycle()
		elif phase == "presurizando":
			airlock_phase = "abierta"
			start_repressurize()
		elif phase == "abierta":
			airlock_phase = "abierta"
			doors["d_exterior"].force_open = true
			doors["d_esclusa"].force_closed = true
		else:
			airlock_phase = phase
	if bool(d.get("power_aux", false)) != power_aux:
		set_power_aux(bool(d.get("power_aux", false)))
