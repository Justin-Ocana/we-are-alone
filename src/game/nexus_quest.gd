class_name NexusQuest
extends Node
## Componentes del NEXUS (ronda 11): el objetivo que deja el mensaje de Magnus Blackwell. Seis componentes repartidos
## entre las instalaciones de MacSpaces de la Luna (talleres de LF-01), Mercurio, Venus, Marte, Europa y Titán.
## En el cuerpo dominante se levanta su instalación (cúpula, mástil con baliza, logotipo y el pedestal con el
## componente); el objetivo muestra dirección y distancia, y fuera de él indica a qué mundo viajar.
## Los componentes recogidos se guardan en el diario (ExplorationLog.nexus). Las ubicaciones son FICTICIAS.

signal collected(body_id: String)

const ORDER := ["moon", "mercury", "venus", "mars", "europa", "titan"]
## id → [nombre de la instalación, latitud, longitud] (la lunar está dentro de la base: punto local del taller)
const SITES := {
	"moon": ["Talleres de mantenimiento de LF-01", 0.0, 0.0],
	"mercury": ["Instalación Caloris-7", 62.0, 15.0],
	"venus": ["Estación Afrodita", -12.0, 97.0],
	"mars": ["Base Tharsis-2", 18.4, -133.8],
	"europa": ["Pozo Conamara", 5.0, 160.0],
	"titan": ["Refugio Kraken", 10.0, -60.0],
}
const MOON_POINT := Vector3(8.0, 0.0, 26.0)    ## pedestal en los talleres de la base (marco de la base)
const PICK_RANGE := 2.4
const MORNING := 0.61               ## 35° por delante del punto subsolar: Sol a ~55° y subiendo
const LIT_MIN := 0.14               ## seno de 8°: por debajo, la instalación se considera a oscuras

var world: SurfaceWorld
var log: ExplorationLog
var _site: Node3D = null           ## instalación del cuerpo actual (no lunar)
var _site_bf: DVec3 = null         ## origen BF de la base procedural (suelo del centro)
var _core_bf: DVec3 = null         ## posición BF del componente (pedestal)
var outpost: NexusOutpost = null   ## base procedural del cuerpo actual (no lunar)
var _core: MeshInstance3D = null
var _beacon: OmniLight3D = null
var _beacon_mat: StandardMaterial3D
var _obj_t := 0.0


func setup(p_world: SurfaceWorld, p_log: ExplorationLog) -> void:
	world = p_world
	log = p_log
	world.interact_providers.append(self)
	world.anchor_changed.connect(func(_id: String): _build_site())
	FloatingOrigin.origin_shifted.connect(func(_d: Vector3): _place())
	_build_site()


func count() -> int:
	return log.nexus.size()


func has_component(body_id: String) -> bool:
	return body_id in log.nexus


## Siguiente mundo con componente pendiente (el actual si aún lo tiene).
func next_body() -> String:
	if SITES.has(world.body.id) and not has_component(world.body.id):
		return world.body.id
	for id in ORDER:
		if not has_component(id):
			return id
	return ""


# --- Instalación en el cuerpo actual ------------------------------------------------------------

func _build_site() -> void:
	_obj_t = 0.0   # objetivo nuevo en cuanto cambia el cuerpo (el marcador anterior apuntaba a una instalación ya borrada)
	if world.story_hud != null:
		world.story_hud.set_objective("", "")
	if _site != null:
		_site.queue_free()
	_site = null
	_site_bf = null
	_core_bf = null
	_core = null
	_beacon = null
	outpost = null
	var id := world.body.id
	if not SITES.has(id) or not world.terrain.solid:
		return
	_site = Node3D.new()
	_site.name = "NEXUS_" + id
	if id == "moon":
		if world.base == null:
			return
		world.base.add_child(_site)
		_site.position = MOON_POINT
		_core_bf = world.base.point_bf(MOON_POINT + Vector3(0, 1.1, 0))
		_pedestal(false, Vector3.ZERO)
		return
	# Base procedural (NexusOutpost) en el lado de día, en el sitio más llano de la zona.
	world.add_child(_site)
	var dir := site_dir(id)
	var center := dir.mul(world.terrain.radius + world.terrain.height_at_dir(dir))
	_site_bf = center
	_frame(dir)
	var g := func(x: float, z: float) -> float:
		var pb := center.add(_east.mul(x)).sub(_north.mul(z))
		return world.terrain.ground_radius_at(pb) - pb.length()
	outpost = NexusOutpost.new()
	outpost.build(_site, hash("nexus:" + id), g, str(SITES[id][0]))
	_core_bf = _local_to_bf(outpost.core_local + Vector3(0, 1.35, 0))
	world.terrain.exclude_rocks(center, outpost.clear_radius())   # sin rocas asomando por los suelos
	_pedestal(false, outpost.core_local)
	_beacon_at(outpost.beacon_local)
	_place()


## Dirección BF (unitaria) de la instalación de `id`. Se elige al llegar: en el lado de DÍA, hacia la mañana (el Sol
## sigue subiendo durante horas), y entre varios candidatos cercanos el más llano. Se guarda en el diario; si al
## volver ha caído la noche y el componente sigue allí, se elige otra vez. En línea manda la del anfitrión.
func site_dir(id: String) -> DVec3:
	var saved = log.nexus_sites.get(id)
	if saved is Array and (saved as Array).size() == 3:
		var d := DVec3.new(float(saved[0]), float(saved[1]), float(saved[2]))
		if has_component(id) or Net.is_client() or sun_elevation(id, d) > LIT_MIN:
			return d
	var d := _choose_site(id)
	log.nexus_sites[id] = [d.x, d.y, d.z]
	return d


## Seno de la elevación del Sol sobre el horizonte en la dirección `dir` del cuerpo `id` (1 = cenit; < 0 = noche).
func sun_elevation(id: String, dir: DVec3) -> float:
	if world.system == null:
		return 1.0
	return world.system.sun_in_frame(id).normalized().to_vector3().dot(dir.normalized().to_vector3())


func _choose_site(id: String) -> DVec3:
	var e: Array = SITES[id]
	var fallback := CubeSphere.latlon_to_dir(float(e[1]), float(e[2]))
	if world.system == null:
		return fallback
	var sys := world.system
	var t0 := sys.time_s
	var s1 := sys.sun_in_frame(id).normalized().to_vector3()
	sys.time_s = t0 + 3600.0
	var s2 := sys.sun_in_frame(id).normalized().to_vector3()
	sys.time_s = t0
	# El punto subsolar avanza hacia `m`: lo que tiene delante está en su mañana.
	var m := s2 - s1
	m -= s1 * s1.dot(m)
	if m.length_squared() < 1e-16:
		m = s1.cross(Vector3.UP if absf(s1.y) < 0.9 else Vector3.RIGHT)
	m = m.normalized()
	var base := (s1 * cos(MORNING) + m * sin(MORNING)).normalized()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("nexus-site:" + id)
	var best := base
	var best_score := INF
	var r := world.terrain.radius
	for k in 28:
		var cand := base
		if k > 0:
			var t := base.cross(Vector3.UP if absf(base.y) < 0.9 else Vector3.RIGHT).normalized()
			var b := base.cross(t)
			var ang := rng.randf() * TAU
			var dist := rng.randf_range(300.0, 5000.0) / r
			cand = (base + (t * cos(ang) + b * sin(ang)) * dist).normalized()
		var score := _roughness(DVec3.from_vector3(cand))
		if score < best_score:
			best_score = score
			best = cand
	return DVec3.from_vector3(best)


## Desnivel (m) del terreno en un cuadrado de ~90 m alrededor de `dir`.
func _roughness(dir: DVec3) -> float:
	var up := dir.normalized().to_vector3()
	var t := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	var b := up.cross(t)
	var r := world.terrain.radius
	var lo := INF
	var hi := -INF
	for i in 6:
		for j in 6:
			var off := (t * (-45.0 + 18.0 * i) + b * (-45.0 + 18.0 * j)) / r
			var h := world.terrain.height_at_dir(DVec3.from_vector3((up + off).normalized()))
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return hi - lo


var _east: DVec3
var _north: DVec3
var _up: DVec3


func _frame(dir: DVec3) -> void:
	var up := dir.normalized().to_vector3()
	var north := (Vector3.UP - up * up.dot(Vector3.UP))
	north = north.normalized() if north.length_squared() > 1e-8 else Vector3.FORWARD
	var east := north.cross(up).normalized()
	_up = DVec3.from_vector3(up)
	_north = DVec3.from_vector3(north)
	_east = DVec3.from_vector3(east)


## Punto del marco local de la base (X este, Y arriba, Z sur) → BF.
func _local_to_bf(p: Vector3) -> DVec3:
	return _site_bf.add(_east.mul(p.x)).add(_up.mul(p.y)).sub(_north.mul(p.z))


func _place() -> void:
	if _site == null or world.body.id == "moon" or _site_bf == null:
		return
	_site.global_transform = Transform3D(Basis(_east.to_vector3(), _up.to_vector3(), -_north.to_vector3()),
		FloatingOrigin.to_local(_site_bf))


## Baliza roja (verde con el componente recogido) en lo alto del mástil.
func _beacon_at(pos: Vector3) -> void:
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beacon_mat.albedo_color = Color(1.0, 0.2, 0.1)
	var b := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	b.mesh = sm
	b.material_override = _beacon_mat
	b.position = pos
	b.layers = Layers.bit(Layers.WORLD)
	_site.add_child(b)
	_beacon = OmniLight3D.new()
	_beacon.position = pos + Vector3(0, 0.3, 0)
	_beacon.omni_range = 60.0
	_beacon.light_color = Color(1.0, 0.3, 0.15)
	_beacon.light_cull_mask = Layers.bits([Layers.WORLD, Layers.BODY, Layers.HEAD, Layers.SHIP_EXT])
	_site.add_child(_beacon)
	if has_component(world.body.id):
		_set_beacon_green()


func _pedestal(exterior: bool, at: Vector3) -> void:
	var dark := _mat(Color(0.1, 0.1, 0.11), 0.4)
	var layer := Layers.WORLD if exterior else Layers.SHIP_INT
	_part(CylinderMesh.new(), dark, at + Vector3(0, 0.5, 0), Vector3(0.6, 1.0, 0.6), true, layer)
	_core = MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.35, 0.5, 0.35)
	_core.mesh = pm
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.albedo_color = Color(0.35, 0.95, 1.0) * 1.4
	_core.material_override = cm
	_core.position = at + Vector3(0, 1.35, 0)
	_core.layers = Layers.bit(layer)
	_site.add_child(_core)
	var l := OmniLight3D.new()
	l.position = at + Vector3(0, 1.6, 0)
	l.omni_range = 6.0
	l.light_color = Color(0.4, 0.9, 1.0)
	l.light_energy = 1.2
	l.light_cull_mask = Layers.bits([Layers.WORLD, Layers.BODY, Layers.SHIP_INT, Layers.BODY_INT])
	_site.add_child(l)
	_core.set_meta("light", l)
	if has_component(world.body.id):
		_core.visible = false
		l.visible = false
		_set_beacon_green()


func _part(mesh: PrimitiveMesh, mat: Material, pos: Vector3, size: Vector3, collide: bool, layer := Layers.WORLD) -> void:
	if mesh is SphereMesh:
		(mesh as SphereMesh).radius = size.x
		(mesh as SphereMesh).height = size.y * 2.0
		(mesh as SphereMesh).is_hemisphere = true
	elif mesh is BoxMesh:
		(mesh as BoxMesh).size = size
	elif mesh is CylinderMesh:
		(mesh as CylinderMesh).top_radius = size.x
		(mesh as CylinderMesh).bottom_radius = size.x
		(mesh as CylinderMesh).height = size.y
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.layers = Layers.bit(layer)
	_site.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = Layers.bit(Layers.PHYS_SHIP)
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = mesh.create_convex_shape()
		body.add_child(cs)
		body.position = pos
		_site.add_child(body)


static func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _set_beacon_green() -> void:
	if _beacon != null:
		_beacon.light_color = Color(0.3, 1.0, 0.45)
	if _beacon_mat != null:
		_beacon_mat.albedo_color = Color(0.3, 1.0, 0.45)


# --- Interacción (proveedor de SurfaceWorld.interact_providers) -----------------------------------

func nearest_interaction(a: Node3D) -> Dictionary:
	if _core_bf == null or _core == null or not _core.visible:
		return {}
	if FloatingOrigin.to_local(_core_bf).distance_to(a.global_position + a.global_transform.basis.y * 1.0) > PICK_RANGE:
		return {}
	return {"id": "nexus", "label": "Recoger el componente del NEXUS", "kind": "nexus"}


func interact(a: Node, _id: String, _kind: String) -> void:
	if Net.is_client():
		Net.rpc_id(1, "request", "nexus", [])
		return
	collect(a)


func collect(a: Node = null) -> void:
	var id := world.body.id
	if has_component(id) or _core == null:
		return
	log.nexus.append(id)
	log.changed.emit()
	_show_collected()
	GameAudio.play("scan", 0.0)
	# Registro de audio de la pieza (data/dialogue/prologue.json, «nexus_<cuerpo>»); en línea suena para todos.
	if world.dialogue != null:
		world.dialogue.say("nexus_" + id)
	var n := count()
	var lines := ["Componente %s: %s." % [n, str(SITES[id][0])], "NEXUS: %d de 6 componentes." % n]
	if n < 6:
		lines.append("Siguiente: %s." % _body_name(next_body()))
	else:
		lines.append("NEXUS COMPLETO. La cartografía universal vuelve a estar en línea.")
	world.show_card_all("COMPONENTE DEL NEXUS RECUPERADO", lines)
	collected.emit(id)
	_obj_t = 0.0


func _show_collected() -> void:
	if _core != null:
		_core.visible = false
		(_core.get_meta("light") as OmniLight3D).visible = false
	_set_beacon_green()


## Cliente en línea: componentes recogidos y ubicaciones de las instalaciones según el anfitrión.
func apply_net(got: Array, sites: Dictionary) -> void:
	var rebuild := false
	for k in sites:
		var v = sites[k]
		var old = log.nexus_sites.get(k)
		if not (old is Array) or (old as Array).size() != 3 or absf(float(old[0]) - float(v[0])) + absf(float(old[1]) - float(v[1])) \
				+ absf(float(old[2]) - float(v[2])) > 1e-7:
			log.nexus_sites[k] = v
			rebuild = rebuild or str(k) == world.body.id
	for id in got:
		if not has_component(str(id)):
			log.nexus.append(str(id))
			if str(id) == world.body.id:
				_show_collected()
	if rebuild:
		_build_site()


func _body_name(id: String) -> String:
	var b: BodyDef = world.system.body(id) if world.system != null else null
	return b.display_name if b != null else id


# --- Objetivo ------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if world == null or world.story_hud == null:
		return
	if _core != null and _core.visible:
		_core.rotate_y(delta * 1.2)
	if _beacon != null:
		_beacon.light_energy = 0.4 + 2.0 * maxf(0.0, sin(Time.get_ticks_msec() * 0.004))
	_obj_t -= delta
	if _obj_t > 0.0:
		return
	_obj_t = 0.5
	var pr := world.prologue
	if pr != null and pr.active and pr.step != "completado":
		return
	if pr != null and pr.active and not pr.flags.has("cleared") and world.player.aboard == null and world.base != null \
			and world.base.room_of(world.player) == "":
		return   # justo al acabar el prólogo, primero el objetivo de volver a la nave
	var nb := next_body()
	if nb == "":
		world.story_hud.set_objective("NEXUS completo (6/6). Busca un mundo habitable.", "")
		return
	var n := count()
	if nb == world.body.id and _core_bf != null:
		world.story_hud.set_objective_world("NEXUS %d/6 · Recupera el componente: %s" % [n, str(SITES[nb][0])],
			func() -> Vector3: return FloatingOrigin.to_local(_core_bf) if _core_bf != null else Vector3.INF)
	else:
		world.story_hud.set_objective("NEXUS %d/6 · Viaja a %s (mapa: Tab) para recuperar el siguiente componente" % [n, _body_name(nb)], "")
