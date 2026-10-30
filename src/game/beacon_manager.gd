class_name BeaconManager
extends Node
## Balizas de exploración (ronda 11): el jugador planta hasta 8 por mundo (tecla O o menú rápido) para marcar
## lugares (una muestra, un cráter, el camino de vuelta). Mástil de 2 m con luz intermitente que se ve de lejos,
## marcador en el HUD con nombre y distancia, se recogen de nuevo con la tecla de interactuar y se guardan con la
## partida (ExplorationLog.beacons, posiciones BF de 64 bits por cuerpo). En línea son de cada jugador.

const MAX_PER_BODY := 8
const PICK_RANGE := 2.2
const MARKER_RANGE := 80000.0      ## m: más lejos no se dibuja el marcador
const COLORS := [Color(0.3, 1.0, 0.5), Color(0.35, 0.85, 1.0), Color(1.0, 0.8, 0.25), Color(1.0, 0.4, 0.8)]

var world: SurfaceWorld
var log: ExplorationLog
var _nodes := {}                   ## índice en log.beacons → Node3D
var _layer: CanvasLayer
var _canvas: Control
var _t := 0.0


func setup(p_world: SurfaceWorld, p_log: ExplorationLog) -> void:
	world = p_world
	log = p_log
	world.interact_providers.append(self)
	world.anchor_changed.connect(func(_id: String): _rebuild())
	FloatingOrigin.origin_shifted.connect(func(_d: Vector3): _place_all())
	log.changed.connect(_rebuild)
	_layer = CanvasLayer.new()
	_layer.layer = 4
	add_child(_layer)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_draw)
	_layer.add_child(_canvas)
	_rebuild()


func _here() -> Array:
	var out := []
	for i in log.beacons.size():
		if str(log.beacons[i].get("body", "")) == world.body.id:
			out.append(i)
	return out


## Planta una baliza a los pies del astronauta (sólo a pie, fuera de naves y de la base).
func place(a: Astronaut) -> void:
	var h := a.exploration_hud
	if a.aboard != null or a.seated or a.in_habitat or a.flying or not world.terrain.solid:
		if h != null:
			h.notify("Las balizas se plantan a pie, en el exterior y sobre suelo firme.", UiTheme.DANGER)
		return
	if _here().size() >= MAX_PER_BODY:
		if h != null:
			h.notify("Ya hay %d balizas en este mundo: recoge alguna antes." % MAX_PER_BODY, UiTheme.DANGER)
		return
	var p := a.position_bf()
	var dir := p.normalized()
	var ground := dir.mul(world.terrain.radius + world.terrain.height_at_dir(dir))
	var fwd := -a.global_transform.basis.z * 1.2
	ground = ground.add_vector3(fwd - dir.to_vector3() * fwd.dot(dir.to_vector3()))
	var n := _next_number()
	log.beacons.append({"body": world.body.id, "pos": [ground.x, ground.y, ground.z], "n": n, "when": int(Time.get_unix_time_from_system())})
	GameAudio.play("sample", -4.0)
	if h != null:
		h.notify("Baliza B%d plantada" % n, COLORS[(n - 1) % COLORS.size()])
	log.changed.emit()


func _next_number() -> int:
	var used := {}
	for i in _here():
		used[int(log.beacons[i].get("n", 0))] = true
	var n := 1
	while used.has(n):
		n += 1
	return n


func _rebuild() -> void:
	for k in _nodes:
		if is_instance_valid(_nodes[k]):
			_nodes[k].queue_free()
	_nodes = {}
	for i in _here():
		_nodes[i] = _make(int(log.beacons[i].get("n", 1)))
	_place_all()


func _make(n: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Baliza_%d" % n
	var col: Color = COLORS[(n - 1) % COLORS.size()]
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.05
	cm.height = 2.0
	pole.mesh = cm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.85, 0.85, 0.82)
	pole.material_override = pmat
	pole.position = Vector3(0, 1.0, 0)
	root.add_child(pole)
	var tip := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	tip.mesh = sm
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.albedo_color = col * 1.6
	tip.material_override = tmat
	tip.position = Vector3(0, 2.05, 0)
	root.add_child(tip)
	var l := OmniLight3D.new()
	l.position = Vector3(0, 2.1, 0)
	l.light_color = col
	l.omni_range = 18.0
	l.light_cull_mask = Layers.bits([Layers.WORLD, Layers.BODY, Layers.HEAD, Layers.SHIP_EXT])
	root.add_child(l)
	root.set_meta("light", l)
	root.set_meta("tip", tmat)
	root.set_meta("color", col)
	world.add_child(root)
	return root


func _place_all() -> void:
	for i in _nodes:
		var e: Dictionary = log.beacons[i]
		var p: Array = e["pos"]
		var bf := DVec3.new(p[0], p[1], p[2])
		var up := bf.normalized().to_vector3()
		var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
		(_nodes[i] as Node3D).global_transform = Transform3D(Basis(side, up, side.cross(up)), FloatingOrigin.to_local(bf))


func _process(delta: float) -> void:
	_t += delta
	var blink := 0.5 + 0.5 * sin(_t * 4.0)
	for i in _nodes:
		var n: Node3D = _nodes[i]
		(n.get_meta("light") as OmniLight3D).light_energy = 0.4 + 1.6 * blink
		(n.get_meta("tip") as StandardMaterial3D).albedo_color = (n.get_meta("color") as Color) * (0.6 + 1.2 * blink)
	_canvas.queue_redraw()


func _on_draw() -> void:
	if GameSettings.ui_hidden or world.view == null:
		return
	var cam := world.view.active_camera()
	if cam == null:
		return
	var vp := _canvas.get_viewport_rect().size
	var s := clampf(vp.y / 720.0, 0.8, 1.6) * GameSettings.ui_scale
	for i in _nodes:
		var n: Node3D = _nodes[i]
		var head := n.global_position + n.global_transform.basis.y * 2.3
		var d := cam.global_position.distance_to(head)
		if d > MARKER_RANGE or d < 3.0:
			continue
		var e: Dictionary = log.beacons[i]
		UiTheme.draw_world_marker(_canvas, cam, head, "B%d" % int(e.get("n", 1)), Units.format_distance(d), n.get_meta("color"), s * 0.85)


# --- Recoger (proveedor de interacción) ---------------------------------------------------------

func nearest_interaction(a: Node3D) -> Dictionary:
	if a is Astronaut and (a.aboard != null or a.seated):
		return {}
	for i in _nodes:
		var n: Node3D = _nodes[i]
		if n.global_position.distance_to(a.global_position) < PICK_RANGE:
			return {"id": "beacon:%d" % i, "label": "Recoger la baliza B%d" % int(log.beacons[i].get("n", 1)), "kind": "beacon"}
	return {}


func interact(a: Node, id: String, _kind: String) -> void:
	var i := int(id.trim_prefix("beacon:"))
	if i < 0 or i >= log.beacons.size():
		return
	var n := int(log.beacons[i].get("n", 1))
	log.beacons.remove_at(i)
	GameAudio.play("stand", -4.0)
	if a is Astronaut and a.exploration_hud != null:
		a.exploration_hud.notify("Baliza B%d recogida" % n)
	log.changed.emit()
