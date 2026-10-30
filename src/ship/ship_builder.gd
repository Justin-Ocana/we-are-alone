class_name ShipBuilder
extends RefCounted
## Construye la nave clase Kestrel a partir de ShipLayout (ADR-013, rediseño ADR-021): geometría agrupada
## por zonas (MeshBatcher), colisiones simplificadas (cajas/cilindros en el StaticBody3D de la nave) más el
## casco exterior liso (ShipHull, colisión de malla), mobiliario por habitación, puertas, esclusa, rampa,
## tren de aterrizaje, luces y pantallas. Todo en metros, a escala del astronauta de 1,85 m.

const H := ShipLayout.DECK_HEIGHT
const WT := ShipLayout.WALL_T
const HT := ShipLayout.HULL_T

var ship: Node3D
var body: StaticBody3D
var batcher := MeshBatcher.new()
var mats := {}
var dyn := {}          ## nodos/materiales dinámicos para Ship
var shape_count := 0


func build(p_ship: Node3D, p_body: StaticBody3D) -> Dictionary:
	ship = p_ship
	body = p_body
	_make_materials()
	dyn = {"doors": {}, "labels": {}, "gear": [], "gear_shapes": [], "nav": [], "airlock_lights": {}, "lights": []}
	_structure()
	_cockpit()
	_galley()
	_quarters()
	_storage()
	_medbay()
	_bathroom()
	_airlock()
	_eva_room()
	_lounge()
	_engineering()
	_exterior()
	_doors()
	_lights()
	dyn["party_mats"] = []
	for key in ["glow_white", "glow_cyan", "glow_amber", "glow_green"]:
		dyn["party_mats"].append([mats[key], (mats[key] as StandardMaterial3D).albedo_color])
	var mesh_count := batcher.build(ship, mats, func(b: String) -> int:
		return Layers.SHIP_INT if b.begins_with("int:") else Layers.SHIP_EXT)
	dyn["mesh_count"] = mesh_count
	dyn["mats"] = mats
	dyn["room_meshes"] = batcher.meshes_by_batch
	dyn["shape_count"] = shape_count
	return dyn


# --- Materiales -----------------------------------------------------------------------

func _panel(c: Color, panel: float, rough: float, metal: float = 0.0, grate: float = 0.0, line: float = 0.35,
		opts: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://src/ship/ship_panel.gdshader")
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("panel", panel)
	m.set_shader_parameter("roughness_value", rough)
	m.set_shader_parameter("metallic_value", metal)
	m.set_shader_parameter("grate", grate)
	m.set_shader_parameter("line_dark", line)
	m.set_shader_parameter("high_detail", GameSettings.quality == "high")
	# Acabado (ADR-039): suciedad, desgaste, remaches, relieve y si es casco exterior.
	for k in opts:
		m.set_shader_parameter(k, opts[k])
	return m


static var _ds_shader: Shader


static func _double_sided_panel_shader() -> Shader:
	if _ds_shader == null:
		var base: Shader = load("res://src/ship/ship_panel.gdshader")
		_ds_shader = Shader.new()
		_ds_shader.code = base.code.replace("render_mode diffuse_burley;", "render_mode diffuse_burley, cull_disabled;")
	return _ds_shader


static func _std(c: Color, rough: float = 0.6, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func _glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.55, 0.8, 1.0, 0.1)
	m.roughness = 0.05
	m.metallic_specular = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func glow(c: Color, energy: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c * energy
	return m


func _make_materials() -> void:
	mats = {
		"hull": _panel(Color(0.82, 0.82, 0.80), 2.2, 0.45, 0.3, 0.0, 0.3, {"exterior": 1.0, "grime": 0.4, "wear": 0.35, "bevel": 1.3}),
		"hull_dark": _panel(Color(0.17, 0.17, 0.18), 0.9, 0.55, 0.45, 0.0, 0.35, {"exterior": 1.0, "grime": 0.3, "wear": 0.5}),
		"hull_accent": _panel(Color(0.22, 0.30, 0.40), 2.2, 0.5, 0.25, 0.0, 0.25, {"exterior": 1.0, "grime": 0.35, "wear": 0.3}),
		"plant": _std(Color(0.22, 0.48, 0.24), 0.9),
		"glass": _glass(),
		"trim": _panel(Color(0.95, 0.45, 0.1), 3.0, 0.45, 0.1, 0.0, 0.2, {"rivets": 0.0, "grime": 0.3, "wear": 0.45, "exterior": 1.0}),
		"wall": _panel(Color(0.80, 0.80, 0.78), 1.0, 0.7, 0.0, 0.0, 0.32, {"grime": 0.12, "wear": 0.08}),
		"wall_accent": _panel(Color(0.30, 0.36, 0.44), 0.6, 0.6, 0.1, 0.0, 0.35, {"grime": 0.1, "wear": 0.15}),
		"floor": _panel(Color(0.30, 0.31, 0.33), 1.0, 0.65, 0.5, 1.0, 0.35, {"grime": 0.35, "wear": 0.4, "rivets": 0.0}),
		"ceiling": _panel(Color(0.62, 0.63, 0.65), 1.2, 0.8, 0.0, 0.0, 0.35, {"grime": 0.08, "wear": 0.0}),
		"furn": _panel(Color(0.86, 0.87, 0.87), 1.6, 0.42, 0.0, 0.0, 0.18, {"rivets": 0.0, "grime": 0.08, "wear": 0.06, "bevel": 0.6}),
		"furn_dark": _panel(Color(0.18, 0.19, 0.21), 1.4, 0.55, 0.25, 0.0, 0.25, {"rivets": 0.0, "grime": 0.12, "wear": 0.2, "bevel": 0.6}),
		"fabric": _std(Color(0.15, 0.15, 0.17), 0.92),
		"fabric_light": _std(Color(0.75, 0.82, 0.85), 0.95),
		"counter": _std(Color(0.92, 0.92, 0.90), 0.3),
		"metal": _panel(Color(0.62, 0.64, 0.67), 0.6, 0.32, 0.75, 0.0, 0.2, {"rivets": 1.0, "grime": 0.25, "wear": 0.0, "bevel": 0.8}),
		"glow_cyan": glow(Color(0.35, 0.85, 1.0)),
		"glow_amber": glow(Color(1.0, 0.62, 0.18)),
		"glow_red": glow(Color(1.0, 0.15, 0.1)),
		"glow_green": glow(Color(0.25, 1.0, 0.45)),
		"glow_white": glow(Color(1.0, 0.97, 0.9)),
		"screen": glow(Color(0.06, 0.16, 0.26)),
	}
	# Casco exterior de doble cara (ronda 11): si en algún rincón queda una rendija entre los tabiques interiores, se
	# ve el casco por dentro y no el espacio (antes, desde dentro, esas esquinas parecían transparentes).
	var ds := _double_sided_panel_shader()
	for key in ["hull", "hull_dark", "hull_accent"]:
		(mats[key] as ShaderMaterial).shader = ds
	dyn_material("engine_glow", Color(0.45, 0.75, 1.0))
	dyn_material("reactor_glow", Color(0.3, 0.9, 1.0))


func dyn_material(key: String, c: Color) -> void:
	var m := glow(c, 0.4)
	mats[key] = m
	dyn[key] = m
	dyn[key + "_color"] = c


# --- Primitivas con colisión ------------------------------------------------------------

func box(batch: String, mat: String, center: Vector3, size: Vector3, collide := true, rot := Vector3.ZERO) -> void:
	var xf := Transform3D(Basis.from_euler(rot), center)
	batcher.box(batch, mat, xf, size)
	if collide:
		var s := BoxShape3D.new()
		s.size = size
		_shape(s, xf)


func cyl(batch: String, mat: String, center: Vector3, radius: float, height: float, collide := false,
		rot := Vector3.ZERO, top := -1.0) -> void:
	var c := CylinderMesh.new()
	c.top_radius = radius if top < 0.0 else top
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 16
	c.rings = 1
	var xf := Transform3D(Basis.from_euler(rot), center)
	batcher.primitive(batch, mat, c, xf)
	if collide:
		var s := CylinderShape3D.new()
		s.radius = radius
		s.height = height
		_shape(s, xf)


func sphere(batch: String, mat: String, center: Vector3, radius: float, scl := Vector3.ONE) -> void:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 16
	s.rings = 8
	batcher.primitive(batch, mat, s, Transform3D(Basis().scaled(scl), center))


func ring(batch: String, mat: String, center: Vector3, inner: float, outer: float, rot := Vector3.ZERO) -> void:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 20
	t.ring_segments = 8
	batcher.primitive(batch, mat, t, Transform3D(Basis.from_euler(rot), center))


func _shape(s: Shape3D, xf: Transform3D) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = s
	cs.transform = xf
	body.add_child(cs)
	shape_count += 1
	return cs


## Pared en el plano x = `x`, de z0 a z1, con huecos [centro_z, ancho, y0, y1].
func wall_x(x: float, z0: float, z1: float, holes: Array, batch_fn: Callable, mat: String, t := WT, collide := true) -> void:
	_wall(true, x, z0, z1, holes, batch_fn, mat, t, collide)


## Pared en el plano z = `z`, de x0 a x1, con huecos [centro_x, ancho, y0, y1].
func wall_z(z: float, x0: float, x1: float, holes: Array, batch_fn: Callable, mat: String, t := WT, collide := true) -> void:
	_wall(false, z, x0, x1, holes, batch_fn, mat, t, collide)


func _wall(along_z: bool, plane: float, a0: float, a1: float, holes: Array, batch_fn: Callable,
		mat: String, t: float, collide: bool) -> void:
	var sorted := holes.duplicate()
	sorted.sort_custom(func(p, q): return p[0] < q[0])
	var cursor := a0
	for hole in sorted:
		var h0: float = hole[0] - hole[1] * 0.5
		var h1: float = hole[0] + hole[1] * 0.5
		var y0: float = hole[2]
		var y1: float = hole[3]
		_wall_piece(along_z, plane, cursor, h0, 0.0, H, batch_fn, mat, t, collide)
		if y0 > 0.01:
			_wall_piece(along_z, plane, h0, h1, 0.0, y0, batch_fn, mat, t, collide)
		if y1 < H - 0.01:
			_wall_piece(along_z, plane, h0, h1, y1, H, batch_fn, mat, t, collide)
		cursor = h1
	_wall_piece(along_z, plane, cursor, a1, 0.0, H, batch_fn, mat, t, collide)


func _wall_piece(along_z: bool, plane: float, a0: float, a1: float, y0: float, y1: float,
		batch_fn: Callable, mat: String, t: float, collide: bool) -> void:
	if a1 - a0 < 0.01 or y1 - y0 < 0.01:
		return
	var mid := (a0 + a1) * 0.5
	var center := Vector3(plane, (y0 + y1) * 0.5, mid) if along_z else Vector3(mid, (y0 + y1) * 0.5, plane)
	var size := Vector3(t, y1 - y0, a1 - a0) if along_z else Vector3(a1 - a0, y1 - y0, t)
	box(batch_fn.call(center), mat, center, size, collide)


const CORRIDOR_SEGMENTS := [[-18.0, -8.0], [-8.0, 2.0], [2.0, 10.0]]


## Lote interior según la zona del punto (el pasillo se divide en tres tramos por el límite de luces).
static func cell(p: Vector3) -> String:
	var room := ShipLayout.room_at(p)
	if room == "pasillo":
		room = "pasillo_a" if p.z < -8.0 else ("pasillo_b" if p.z < 2.0 else "pasillo_c")
	return "int:" + (room if room != "" else "casco")


## Lote de las paredes COMPARTIDAS (pasillo↔sala y mamparos entre salas): nunca se ocultan. Antes eran del lote de
## la sala vecina y, al ocultarla con la puerta cerrada (ronda 9), desaparecía la pared y se veía el exterior
## (ronda 10). Se reparten en tres tramos a lo largo de la nave.
static func _structural(p: Vector3) -> String:
	return "int:estructura_" + ("a" if p.z < -8.0 else ("b" if p.z < 2.0 else "c"))


func _cell_left(p: Vector3) -> String:
	return cell(p + Vector3(-0.3, 0, 0))


func _cell_right(p: Vector3) -> String:
	return cell(p + Vector3(0.3, 0, 0))


func _cell_fwd(p: Vector3) -> String:
	return cell(p + Vector3(0, 0, -0.3))


func _cell_aft(p: Vector3) -> String:
	return cell(p + Vector3(0, 0, 0.3))


# --- Estructura: suelos, techos, mamparos y paredes interiores del casco ----------------------

func _structure() -> void:
	var dh := ShipLayout.DOOR_HEIGHT
	var dw := ShipLayout.DOOR_WIDTH
	var hw := ShipLayout.HALF_WIDTH
	var fz := ShipLayout.FRONT_Z
	var az := ShipLayout.AFT_Z
	var ch := ShipLayout.COCKPIT_HALF
	var cfz := ShipLayout.COCKPIT_FRONT_Z
	var chf := ShipLayout.CORRIDOR_HALF
	# Colisión de suelo y techo: losas continuas (sin juntas en las que tropezar).
	var body_len := az - fz + 0.5
	_shape_box(Vector3(0, -0.2, (fz + az) * 0.5), Vector3(hw * 2.0 + 0.5, 0.4, body_len))
	_shape_box(Vector3(0, -0.2, (cfz + fz) * 0.5 - 0.1), Vector3(ch * 2.0 + 0.5, 0.4, fz - cfz + 0.3))
	_shape_box(Vector3(0, H + 0.15, (fz + az) * 0.5), Vector3(hw * 2.0 + 0.5, 0.3, body_len))
	_shape_box(Vector3(0, H + 0.15, (cfz + fz) * 0.5 - 0.1), Vector3(ch * 2.0 + 0.5, 0.3, fz - cfz + 0.3))
	for id in ShipLayout.ROOMS:
		var r: Array = ShipLayout.ROOMS[id]
		var a: Vector2 = r[2]
		var c: Vector2 = r[3]
		if id == "pasillo":
			for seg in CORRIDOR_SEGMENTS:
				_floor_ceiling(Vector2(a.x, seg[0]), Vector2(c.x, seg[1]))
		else:
			_floor_ceiling(a, c)
	# Paredes del pasillo con las puertas laterales.
	var left := []
	var right := []
	for id in ShipLayout.DOORS:
		var d: Array = ShipLayout.DOORS[id]
		var dc: Vector2 = d[2]
		if d[3] == "x" and absf(absf(dc.x) - chf) < 0.01:
			(left if dc.x < 0.0 else right).append([dc.y, dw, 0.0, dh])
	wall_x(-chf, fz, 10.0, left, _structural, "wall")
	wall_x(chf, fz, 10.0, right, _structural, "wall")
	# Franja de señalización, zócalo y costillas estructurales del pasillo.
	# (Se interrumpen en cada puerta: nada cruza el vano.)
	for x: float in [-chf + 0.07, chf - 0.07]:
		for span in _wall_spans(x, fz + 0.2, 10.0 - 0.2):
			var zc: float = (span[0] + span[1]) * 0.5
			var length: float = span[1] - span[0]
			box(cell(Vector3(x, 1, zc)), "trim", Vector3(x, 1.05, zc), Vector3(0.02, 0.05, length), false)
			box(cell(Vector3(x, 1, zc)), "furn_dark", Vector3(x, 0.06, zc), Vector3(0.03, 0.12, length), false)
	var z := fz + 2.0
	while z < 10.0:
		var bt := cell(Vector3(0, 1, z))
		box(bt, "wall_accent", Vector3(0, H - 0.08, z), Vector3(chf * 2.0, 0.16, 0.18), false)
		for x: float in [-chf + 0.04, chf - 0.04]:
			if not _near_door(x, z):
				box(bt, "wall_accent", Vector3(x, H * 0.5, z), Vector3(0.08, H, 0.18), false)
		z += 4.0
	# Mamparos transversales.
	wall_z(-8.0, -hw, -chf, [], _structural, "wall")
	wall_z(2.0, -hw, -chf, [], _structural, "wall")
	for zz: float in [-10.0, -6.0, 0.0, 4.0]:
		wall_z(zz, chf, hw, [], _structural, "wall")
	wall_z(10.0, -hw, hw, [[0.0, dw, 0.0, dh]], _structural, "wall")
	# Mamparo delantero con el arco del puente.
	wall_z(fz, -hw, hw, [[0.0, ShipLayout.ARCH_WIDTH, 0.0, 2.6]], _structural, "wall")
	box("int:cabina", "wall_accent", Vector3(0, 2.75, fz - 0.1), Vector3(ShipLayout.ARCH_WIDTH + 0.3, 0.3, 0.1), false)
	for sx: float in [-1.0, 1.0]:
		box("int:cabina", "wall_accent", Vector3(sx * (ShipLayout.ARCH_WIDTH * 0.5 + 0.1), 1.3, fz - 0.1), Vector3(0.2, 2.6, 0.1), false)
	# Paredes interiores del casco (el casco exterior liso lo genera ShipHull).
	_hull_x(-1.0, fz, az, ShipLayout.HULL_OPENINGS_LEFT)
	_hull_x(1.0, fz, az, ShipLayout.HULL_OPENINGS_RIGHT)
	wall_z(az + 0.05, -hw, hw, [], func(p: Vector3) -> String: return cell(p - Vector3(0, 0, 0.3)), "wall", 0.1, false)
	_shape_box(Vector3(0, H * 0.5, az + HT * 0.5), Vector3(hw * 2.0 + 0.5, H, HT))
	_liner()


## Forro interior continuo (ronda 12) detrás de las paredes del casco, del techo y del mamparo de popa, en
## un lote que nunca se oculta: si entre los tabiques de dos salas queda una rendija, se ve pared iluminada y no el
## vacío ni el exterior (las «esquinas transparentes» de las capturas del usuario). Respeta los huecos de las ventanas.
func _liner() -> void:
	var hw := ShipLayout.HALF_WIDTH
	var fz := ShipLayout.FRONT_Z
	var az := ShipLayout.AFT_Z
	var b := func(_p: Vector3) -> String: return "int:estructura_b"   # lote ya existente (sin mallas nuevas)
	for side in [-1.0, 1.0]:
		var holes: Array = ShipLayout.HULL_OPENINGS_LEFT if side < 0.0 else ShipLayout.HULL_OPENINGS_RIGHT
		wall_x(side * (hw + 0.13), fz - 0.1, az + 0.1, holes, b, "wall", 0.04, false)
	wall_z(az + 0.13, -hw - 0.15, hw + 0.15, [], b, "wall", 0.04, false)
	box("int:estructura_b", "wall", Vector3(0, H + 0.12, (fz + az) * 0.5), Vector3(hw * 2.0 + 0.3, 0.04, az - fz + 0.3), false)


## Tramos de la pared del pasillo (lado de `x`) entre z0 y z1 que no están en el vano de una puerta.
func _wall_spans(x: float, z0: float, z1: float) -> Array:
	var holes := []
	for id in ShipLayout.DOORS:
		var d: Array = ShipLayout.DOORS[id]
		var c: Vector2 = d[2]
		if d[3] == "x" and signf(c.x) == signf(x) and absf(absf(c.x) - ShipLayout.CORRIDOR_HALF) < 0.01:
			holes.append([c.y - ShipLayout.DOOR_WIDTH * 0.5 - 0.1, c.y + ShipLayout.DOOR_WIDTH * 0.5 + 0.1])
	holes.sort_custom(func(a, b): return a[0] < b[0])
	var spans := []
	var cursor := z0
	for h in holes:
		if h[0] > cursor + 0.05:
			spans.append([cursor, minf(h[0], z1)])
		cursor = maxf(cursor, h[1])
	if z1 > cursor + 0.05:
		spans.append([cursor, z1])
	return spans


func _near_door(x: float, z: float) -> bool:
	for id in ShipLayout.DOORS:
		var d: Array = ShipLayout.DOORS[id]
		var c: Vector2 = d[2]
		if d[3] == "x" and signf(c.x) == signf(x) and absf(c.y - z) < ShipLayout.DOOR_WIDTH * 1.6:
			return true
	return false


func _shape_box(center: Vector3, size: Vector3) -> void:
	var s := BoxShape3D.new()
	s.size = size
	_shape(s, Transform3D(Basis(), center))


func _floor_ceiling(a: Vector2, c: Vector2) -> void:
	var center := Vector3((a.x + c.x) * 0.5, 0, (a.y + c.y) * 0.5)
	var size := Vector3(c.x - a.x, 0.05, c.y - a.y)
	var batch := cell(center + Vector3(0, 1, 0))
	var fw := ShipLayout.FLOOR_WINDOW
	var wz0 := maxf(a.y, fw.position.y)
	var wz1 := minf(c.y, fw.end.y)
	if batch.begins_with("int:pasillo") and wz1 > wz0:
		# Suelo con ventana: tiras laterales junto al cristal y suelo completo fuera de su tramo.
		for zr in [[a.y, wz0], [wz1, c.y]]:
			if zr[1] - zr[0] > 0.01:
				box(batch, "floor", Vector3(center.x, -0.025, (zr[0] + zr[1]) * 0.5), Vector3(size.x, 0.05, zr[1] - zr[0]), false)
		for xr in [[a.x, fw.position.x], [fw.end.x, c.x]]:
			box(batch, "floor", Vector3((xr[0] + xr[1]) * 0.5, -0.025, (wz0 + wz1) * 0.5), Vector3(xr[1] - xr[0], 0.05, wz1 - wz0), false)
		box(batch, "glass", Vector3(center.x, -0.03, (wz0 + wz1) * 0.5), Vector3(fw.size.x, 0.02, wz1 - wz0), false)
		for x: float in [fw.position.x - 0.02, fw.end.x + 0.02]:
			box(batch, "glow_cyan", Vector3(x, 0.004, (wz0 + wz1) * 0.5), Vector3(0.03, 0.008, wz1 - wz0), false)
	else:
		box(batch, "floor", center + Vector3(0, -0.025, 0), size, false)
	box(batch, "ceiling", center + Vector3(0, H + 0.025, 0), size, false)
	# Tiras de luz en el techo (dos en las salas anchas) y moldura perimetral.
	var long_z := size.z >= size.x
	var strip := Vector3(0.18, 0.04, size.z * 0.6) if long_z else Vector3(size.x * 0.6, 0.04, 0.18)
	if minf(size.x, size.z) > 5.0:
		var off := Vector3(size.x * 0.22, 0, 0) if long_z else Vector3(0, 0, size.z * 0.22)
		box(batch, "glow_white", center + Vector3(0, H - 0.02, 0) + off, strip, false)
		box(batch, "glow_white", center + Vector3(0, H - 0.02, 0) - off, strip, false)
	else:
		box(batch, "glow_white", center + Vector3(0, H - 0.02, 0), strip, false)
	box(batch, "wall_accent", center + Vector3(0, H - 0.1, size.z * 0.5 - 0.06), Vector3(size.x - 0.1, 0.12, 0.06), false)
	box(batch, "wall_accent", center + Vector3(0, H - 0.1, -size.z * 0.5 + 0.06), Vector3(size.x - 0.1, 0.12, 0.06), false)


## Pared interior del casco en x = ±9 (panel visual + colisión de 0,25 m; las ventanas se cierran en la colisión).
func _hull_x(side: float, z0: float, z1: float, holes: Array) -> void:
	var x_in := side * ShipLayout.HALF_WIDTH
	wall_x(x_in + side * 0.05, z0, z1, holes, func(p: Vector3) -> String: return cell(p - Vector3(side * 0.3, 0, 0)), "wall", 0.1, false)
	_wall_collision_x(x_in + side * HT * 0.5, z0, z1, holes, HT)
	for hole in holes:
		if hole[2] > 0.01:
			var bt := cell(Vector3(x_in - side * 0.3, 1.0, hole[0]))
			box(bt, "wall_accent", Vector3(x_in - side * 0.01, hole[3] + 0.05, hole[0]), Vector3(0.08, 0.1, hole[1] + 0.2), false)
			box(bt, "wall_accent", Vector3(x_in - side * 0.04, hole[2] - 0.04, hole[0]), Vector3(0.14, 0.08, hole[1] + 0.2), false)


func _wall_collision_x(x: float, z0: float, z1: float, holes: Array, t: float) -> void:
	# Sólo los huecos de puerta dejan pasar; las ventanas se cierran en la colisión.
	var door_holes := holes.filter(func(h): return h[2] <= 0.01)
	var sorted := door_holes.duplicate()
	sorted.sort_custom(func(p, q): return p[0] < q[0])
	var cursor := z0 - 0.25
	for hole in sorted:
		var h0: float = hole[0] - hole[1] * 0.5
		var h1: float = hole[0] + hole[1] * 0.5
		_shape_box(Vector3(x, H * 0.5, (cursor + h0) * 0.5), Vector3(t, H, h0 - cursor))
		_shape_box(Vector3(x, (hole[3] + H) * 0.5, hole[0]), Vector3(t, H - hole[3], hole[1]))
		cursor = h1
	_shape_box(Vector3(x, H * 0.5, (cursor + z1 + 0.25) * 0.5), Vector3(t, H, z1 + 0.25 - cursor))


## Asiento ergonómico (ronda 8): base de cinco patas, asiento acolchado con borde redondeado, refuerzos laterales,
## respaldo con reposacabezas, arnés naranja y reposabrazos; el de pilotaje lleva palanca y acelerador con botones.
## Mira a su −Z tras girar `yaw`.
func _seat(b: String, p: Vector3, yaw: float, pilot := false) -> void:
	var r := Basis(Vector3.UP, yaw)
	var swap := absf(sin(yaw)) > 0.5   # las esferas escaladas no giran: se intercambian sus ejes X/Z
	var sc := func(v: Vector3) -> Vector3: return Vector3(v.z, v.y, v.x) if swap else v
	# Base: columna, cinco patas y ruedas.
	cyl(b, "metal", p + Vector3(0, 0.25, 0), 0.06, 0.42, false)
	cyl(b, "furn_dark", p + Vector3(0, 0.05, 0), 0.08, 0.1, false)
	for k in 5:
		var a := TAU * k / 5.0 + yaw
		var dv := Vector3(sin(a), 0, cos(a))
		box(b, "furn_dark", p + dv * 0.17 + Vector3(0, 0.05, 0), Vector3(0.05, 0.04, 0.34), false, Vector3(0, a, 0))
		sphere(b, "furn_dark", p + dv * 0.33 + Vector3(0, 0.035, 0), 0.035)
	# Asiento: cojín con borde delantero redondeado y refuerzos laterales.
	box(b, "fabric", p + r * Vector3(0, 0.5, 0.03), Vector3(0.5, 0.1, 0.5), false, Vector3(0, yaw, 0))
	cyl(b, "fabric", p + r * Vector3(0, 0.5, -0.22), 0.055, 0.5, false, Vector3(0, yaw, PI / 2))
	for side: float in [-1.0, 1.0]:
		sphere(b, "fabric", p + r * Vector3(side * 0.26, 0.55, 0.03), 0.07, sc.call(Vector3(0.9, 0.8, 3.4)))
	# Respaldo: panel, refuerzos laterales, reposacabezas y arnés de cuatro puntos.
	box(b, "fabric", p + r * Vector3(0, 1.0, 0.3), Vector3(0.48, 0.86, 0.1), false, Vector3(-0.15, yaw, 0))
	box(b, "furn_dark", p + r * Vector3(0, 1.0, 0.37), Vector3(0.5, 0.88, 0.04), false, Vector3(-0.15, yaw, 0))
	for side: float in [-1.0, 1.0]:
		sphere(b, "fabric", p + r * Vector3(side * 0.25, 0.95, 0.27), 0.08, sc.call(Vector3(0.8, 4.8, 1.0)))
		box(b, "trim", p + r * Vector3(side * 0.12, 1.02, 0.235), Vector3(0.05, 0.75, 0.012), false, Vector3(-0.15, yaw, side * 0.18))
	box(b, "trim", p + r * Vector3(0, 0.62, 0.0), Vector3(0.3, 0.05, 0.012), false, Vector3(-PI / 2 + 0.05, yaw, 0))
	sphere(b, "metal", p + r * Vector3(0, 0.66, -0.05), 0.04, sc.call(Vector3(1.4, 1.0, 0.6)))
	sphere(b, "fabric", p + r * Vector3(0, 1.55, 0.36), 0.15, sc.call(Vector3(1.25, 0.8, 0.55)))
	# Reposabrazos.
	for side: float in [-1.0, 1.0]:
		box(b, "furn_dark", p + r * Vector3(side * 0.33, 0.62, 0.05), Vector3(0.08, 0.06, 0.46), false, Vector3(0, yaw, 0))
		cyl(b, "metal", p + r * Vector3(side * 0.33, 0.56, 0.2), 0.02, 0.1, false)
	if pilot:
		# Palanca (derecha) con gatillo y acelerador (izquierda) con botones iluminados.
		cyl(b, "furn_dark", p + r * Vector3(0.33, 0.72, -0.1), 0.022, 0.16, false)
		sphere(b, "furn_dark", p + r * Vector3(0.33, 0.81, -0.1), 0.04, Vector3(1, 1.3, 1))
		sphere(b, "glow_red", p + r * Vector3(0.33, 0.85, -0.12), 0.012)
		box(b, "furn_dark", p + r * Vector3(-0.33, 0.7, -0.08), Vector3(0.06, 0.1, 0.14), false, Vector3(-0.4, yaw, 0))
		sphere(b, "glow_amber", p + r * Vector3(-0.33, 0.76, -0.12), 0.012)
		sphere(b, "glow_cyan", p + r * Vector3(-0.31, 0.75, -0.06), 0.01)
	var s := BoxShape3D.new()
	s.size = Vector3(0.62, 0.9, 0.7)
	_shape(s, Transform3D(r, p + r * Vector3(0, 0.45, 0.1)))


# --- A. Puente de mando ------------------------------------------------------------------

func _cockpit() -> void:
	var b := "int:cabina"
	var ch := ShipLayout.COCKPIT_HALF
	var cfz := ShipLayout.COCKPIT_FRONT_Z
	var fz := ShipLayout.FRONT_Z
	var w: Array = ShipLayout.COCKPIT_SIDE_WINDOW
	# Paredes laterales con ventanas; colisión cerrada.
	for side: float in [-1.0, 1.0]:
		var x := side * ch
		wall_x(x + side * 0.05, cfz, fz, [w], func(_p: Vector3) -> String: return b, "wall", 0.1, false)
		_shape_box(Vector3(x + side * 0.125, H * 0.5, (cfz + fz) * 0.5), Vector3(0.25, H, fz - cfz + 0.3))
		box(b, "wall_accent", Vector3(x - side * 0.01, w[3] + 0.05, w[0]), Vector3(0.1, 0.1, w[1] + 0.2), false)
		box(b, "wall_accent", Vector3(x - side * 0.05, w[2] - 0.04, w[0]), Vector3(0.16, 0.08, w[1] + 0.2), false)
	# Frente: antepecho, parabrisas (hueco) y dintel; colisión completa.
	var ws := ShipLayout.WINDSHIELD
	var zf := cfz + 0.05
	box(b, "wall", Vector3(0, ws.position.y * 0.5, zf), Vector3(ch * 2.0, ws.position.y, 0.1), false)
	box(b, "wall", Vector3(0, (ws.end.y + H) * 0.5, zf), Vector3(ch * 2.0, H - ws.end.y, 0.1), false)
	var side_w := ch - ws.size.x * 0.5
	for sx: float in [-1.0, 1.0]:
		box(b, "wall", Vector3(sx * (ws.size.x * 0.5 + side_w * 0.5), ws.position.y + ws.size.y * 0.5, zf), Vector3(side_w, ws.size.y, 0.1), false)
	_shape_box(Vector3(0, H * 0.5, cfz - 0.05), Vector3(ch * 2.0 + 0.5, H, 0.3))
	box(b, "wall_accent", Vector3(0, ws.position.y - 0.03, cfz + 0.12), Vector3(ws.size.x + 0.2, 0.06, 0.16), false)
	# Asientos: piloto, copiloto y navegante al frente; ingeniero y comunicaciones a los lados.
	for id in ShipLayout.SEATS:
		var seat: Array = ShipLayout.SEATS[id]
		var p: Vector3 = seat[0]
		if ShipLayout.room_at(p + Vector3(0, 1, 0)) == "cabina":
			_seat(b, p, seat[1], seat[2])
	# Consola principal inclinada con cinco pantallas (bajas: por debajo de la línea de visión).
	var cz := ShipLayout.PILOT_SEAT.z - 1.65
	box(b, "furn_dark", Vector3(0, 0.39, cz), Vector3(8.6, 0.78, 0.7), true)
	box(b, "furn", Vector3(0, 0.81, cz + 0.2), Vector3(8.6, 0.08, 0.75), false, Vector3(0.35, 0, 0))
	for i in 5:
		var x := -3.1 + i * 1.55
		box(b, "screen", Vector3(x, 0.96, cz), Vector3(1.2, 0.36, 0.04), false, Vector3(-0.8, 0, 0))
	for i in 24:
		var mat := "glow_green" if i % 3 == 0 else ("glow_amber" if i % 3 == 1 else "glow_cyan")
		box(b, mat, Vector3(-3.9 + i * 0.34, 0.86, cz + 0.45), Vector3(0.06, 0.02, 0.06), false, Vector3(0.35, 0, 0))
	_label("nav", Vector3(0.0, 0.96, cz + 0.01), Vector3(-0.8, 0, 0), 0.0013)
	_label("regimen", Vector3(-1.55, 0.96, cz + 0.01), Vector3(-0.8, 0, 0), 0.0012)
	_label("sistemas", Vector3(1.55, 0.96, cz + 0.01), Vector3(-0.8, 0, 0), 0.0012)
	# Panel superior sobre los pilotos.
	box(b, "furn_dark", Vector3(0, H - 0.12, cz + 1.0), Vector3(3.2, 0.15, 1.2), false)
	for i in 10:
		box(b, "glow_amber" if i % 2 == 0 else "glow_cyan", Vector3(-1.35 + i * 0.3, H - 0.2, cz + 1.2), Vector3(0.1, 0.02, 0.06), false)
	# Consolas laterales de los puestos de ingeniería y comunicaciones.
	for side: float in [-1.0, 1.0]:
		box(b, "furn_dark", Vector3(side * (ch - 0.4), 0.45, -19.9), Vector3(0.6, 0.9, 2.0), true)
		box(b, "screen", Vector3(side * (ch - 0.55), 1.0, -19.9), Vector3(0.04, 0.5, 1.5), false, Vector3(0, 0, side * 0.35))
		box(b, "glow_cyan" if side < 0.0 else "glow_green", Vector3(side * (ch - 0.58), 1.0, -19.9), Vector3(0.01, 0.38, 1.3), false, Vector3(0, 0, side * 0.35))
	_label("musica", Vector3(ch - 0.6, 1.02, -19.9), Vector3(0, -PI / 2, 0), 0.0014, Color(1.0, 0.85, 0.5))
	# Anillo de luz en el techo y franja en el suelo hacia los asientos.
	ring(b, "glow_white", Vector3(0, H - 0.03, -21.0), 1.5, 1.6)
	box(b, "trim", Vector3(0, 0.005, -20.0), Vector3(0.08, 0.01, 3.0), false)


func _label(key: String, pos: Vector3, rot: Vector3, pixel: float, color := Color(0.6, 0.95, 1.0)) -> Label3D:
	var l := Label3D.new()
	l.position = pos + Basis.from_euler(rot) * Vector3(0, 0, 0.03)
	l.rotation = rot
	l.pixel_size = pixel
	l.font_size = 48
	l.outline_size = 0
	l.modulate = color
	l.shaded = false
	l.double_sided = false
	l.layers = Layers.bit(Layers.SHIP_INT)
	l.text = "—"
	ship.add_child(l)
	dyn["labels"][key] = l
	return l


# --- B. Comedor y cocina -----------------------------------------------------------------

func _galley() -> void:
	var b := "int:comedor"
	# Encimera a lo largo del mamparo delantero, armarios altos, nevera, placa, fregadero y cafetera.
	box(b, "furn", Vector3(-5.2, 0.44, -17.6), Vector3(5.2, 0.88, 0.62))
	box(b, "counter", Vector3(-5.2, 0.9, -17.6), Vector3(5.3, 0.05, 0.66), false)
	box(b, "furn", Vector3(-5.2, 2.15, -17.78), Vector3(5.2, 0.7, 0.36))
	for i in 7:
		box(b, "furn_dark", Vector3(-7.4 + i * 0.73, 2.15, -17.59), Vector3(0.02, 0.6, 0.01), false)
	box(b, "metal", Vector3(-8.5, 1.05, -17.55), Vector3(0.8, 2.1, 0.7))            # nevera
	box(b, "glow_cyan", Vector3(-8.3, 1.5, -17.19), Vector3(0.12, 0.2, 0.01), false)
	box(b, "furn_dark", Vector3(-3.4, 0.93, -17.6), Vector3(0.6, 0.02, 0.45), false)  # placa
	for i in 4:
		ring(b, "glow_red", Vector3(-3.55 + (i % 2) * 0.3, 0.945, -17.7 + (i / 2) * 0.22), 0.05, 0.07)
	box(b, "metal", Vector3(-5.2, 0.9, -17.6), Vector3(0.5, 0.06, 0.4), false)       # fregadero
	box(b, "metal", Vector3(-6.6, 1.15, -17.75), Vector3(0.5, 0.3, 0.35), false)     # microondas
	box(b, "glow_cyan", Vector3(-6.5, 1.15, -17.57), Vector3(0.18, 0.12, 0.01), false)
	box(b, "furn_dark", Vector3(-4.3, 1.1, -17.72), Vector3(0.3, 0.38, 0.3), false)  # cafetera
	box(b, "glow_amber", Vector3(-4.3, 1.2, -17.56), Vector3(0.06, 0.06, 0.01), false)
	# Mesa para seis junto a la ventana (perpendicular al casco) con dos bancos.
	box(b, "counter", Vector3(-6.0, 0.74, -13.0), Vector3(3.4, 0.05, 1.1), false)
	for x: float in [-7.2, -4.8]:
		cyl(b, "metal", Vector3(x, 0.37, -13.0), 0.07, 0.72, false)
	_shape_box(Vector3(-6.0, 0.38, -13.0), Vector3(3.4, 0.76, 1.1))
	for zs: float in [-1.0, 1.0]:
		box(b, "fabric", Vector3(-6.0, 0.24, -13.0 + zs * 1.05), Vector3(3.2, 0.48, 0.48))
		box(b, "fabric", Vector3(-6.0, 0.75, -13.0 + zs * 1.37), Vector3(3.2, 0.6, 0.12), false)
	sphere(b, "glow_amber", Vector3(-6.0, 2.6, -13.0), 0.18, Vector3(2.5, 0.5, 1.0))  # lámpara colgante
	# Plantas (tierra y hojas) en las esquinas.
	_plant(b, Vector3(-8.5, 0, -8.6))
	_plant(b, Vector3(-1.9, 0, -17.4))


func _plant(b: String, p: Vector3) -> void:
	cyl(b, "furn_dark", p + Vector3(0, 0.22, 0), 0.24, 0.44, true, Vector3.ZERO, 0.28)
	sphere(b, "plant", p + Vector3(0, 0.75, 0), 0.38, Vector3(1, 1.2, 1))
	sphere(b, "plant", p + Vector3(0.15, 1.05, 0.05), 0.24)


# --- C. Dormitorios ----------------------------------------------------------------------

func _quarters() -> void:
	var b := "int:dormitorios"
	for zc: float in [-6.8, 0.8]:
		# Litera: cama baja (colisión), cama alta (losa), postes, colchones, escalera y luces de lectura.
		box(b, "furn", Vector3(-8.47, 0.22, zc), Vector3(0.95, 0.44, 2.0))
		box(b, "fabric", Vector3(-8.47, 0.5, zc), Vector3(0.9, 0.12, 1.92), false)
		box(b, "furn", Vector3(-8.47, 1.65, zc), Vector3(0.95, 0.08, 2.0))
		box(b, "fabric", Vector3(-8.47, 1.75, zc), Vector3(0.9, 0.12, 1.92), false)
		for dz: float in [-0.97, 0.97]:
			box(b, "metal", Vector3(-8.0, 1.1, zc + dz), Vector3(0.05, 2.2, 0.05), false)
		box(b, "fabric_light", Vector3(-8.55, 0.62, zc - 0.75), Vector3(0.5, 0.12, 0.35), false)
		box(b, "fabric_light", Vector3(-8.55, 1.87, zc - 0.75), Vector3(0.5, 0.12, 0.35), false)
		for i in 5:
			box(b, "metal", Vector3(-7.98, 0.5 + i * 0.3, zc + 0.75), Vector3(0.04, 0.03, 0.4), false)
		box(b, "glow_amber", Vector3(-8.9, 1.3, zc - 0.6), Vector3(0.02, 0.06, 0.2), false)
		box(b, "glow_amber", Vector3(-8.9, 2.45, zc - 0.6), Vector3(0.02, 0.06, 0.2), false)
	# Escritorio bajo la ventana con silla, taquillas y alfombra.
	box(b, "furn", Vector3(-8.65, 0.73, -3.0), Vector3(0.6, 0.05, 1.6), false)
	_shape_box(Vector3(-8.65, 0.37, -3.0), Vector3(0.6, 0.74, 1.6))
	box(b, "furn_dark", Vector3(-8.65, 0.35, -3.0), Vector3(0.55, 0.7, 1.5), false)
	box(b, "screen", Vector3(-8.85, 1.05, -3.0), Vector3(0.04, 0.38, 0.6), false, Vector3(0, 0, -0.15))
	box(b, "fabric", Vector3(-7.95, 0.45, -3.0), Vector3(0.45, 0.08, 0.45), false)
	cyl(b, "metal", Vector3(-7.95, 0.22, -3.0), 0.04, 0.44, false)
	box(b, "furn", Vector3(-3.2, 1.05, -7.68), Vector3(2.8, 2.1, 0.55))
	for i in 5:
		box(b, "furn_dark", Vector3(-4.32 + i * 0.56, 1.05, -7.4), Vector3(0.02, 2.0, 0.01), false)
		box(b, "glow_green", Vector3(-4.5 + i * 0.56, 1.25, -7.4), Vector3(0.04, 0.04, 0.01), false)
	box(b, "fabric_light", Vector3(-5.0, 0.006, -3.0), Vector3(3.0, 0.012, 2.2), false)


# --- F. Almacén ---------------------------------------------------------------------------

func _storage() -> void:
	var b := "int:almacen"
	# Estanterías a lo largo del casco con cajas.
	for z: float in [2.5, 4.25, 6.0, 7.75, 9.5]:
		box(b, "metal", Vector3(-8.65, 1.4, z), Vector3(0.6, 2.8, 0.05), false)
	for y: float in [0.15, 0.8, 1.45, 2.1, 2.75]:
		box(b, "furn_dark", Vector3(-8.65, y, 6.0), Vector3(0.6, 0.04, 7.05), false)
	_shape_box(Vector3(-8.65, 1.4, 6.0), Vector3(0.62, 2.8, 7.1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 51
	for y: float in [0.17, 0.82, 1.47, 2.12]:
		var z := 2.6
		while z < 9.2:
			var w := rng.randf_range(0.3, 0.6)
			var hgt := rng.randf_range(0.2, 0.5)
			box(b, "trim" if rng.randf() < 0.25 else "furn", Vector3(-8.65, y + 0.02 + hgt * 0.5, z + w * 0.5), Vector3(0.45, hgt, w * 0.9), false)
			z += w + 0.08
	# Contenedores de carga (con colisión), dejando paso desde la puerta.
	box(b, "hull_dark", Vector3(-6.4, 0.5, 9.3), Vector3(1.0, 1.0, 1.0))
	box(b, "trim", Vector3(-6.4, 1.4, 9.3), Vector3(0.8, 0.8, 0.8))
	box(b, "hull_dark", Vector3(-5.1, 0.4, 9.4), Vector3(0.8, 0.8, 0.8))
	box(b, "furn", Vector3(-4.0, 0.6, 2.6), Vector3(2.4, 1.2, 0.8))
	box(b, "glow_cyan", Vector3(-4.0, 1.0, 3.01), Vector3(0.3, 0.1, 0.01), false)
	box(b, "hull_dark", Vector3(-7.0, 0.35, 3.2), Vector3(1.2, 0.7, 1.0))
	for i in 3:
		box(b, "trim", Vector3(-4.4, 0.006, 4.5 + i * 1.8), Vector3(4.0, 0.012, 0.06), false)


# --- G. Enfermería ------------------------------------------------------------------------

func _medbay() -> void:
	var b := "int:enfermeria"
	for x: float in [3.9, 6.4]:
		# Camilla con monitor.
		box(b, "metal", Vector3(x, 0.38, -16.8), Vector3(0.85, 0.76, 2.0))
		box(b, "fabric_light", Vector3(x, 0.82, -16.8), Vector3(0.8, 0.12, 1.95), false)
		box(b, "fabric_light", Vector3(x, 0.92, -17.6), Vector3(0.6, 0.1, 0.35), false)
		cyl(b, "metal", Vector3(x + 0.7, 0.9, -17.6), 0.03, 1.8, false)
		box(b, "furn_dark", Vector3(x + 0.6, 1.75, -17.6), Vector3(0.5, 0.35, 0.05), false, Vector3(0, -0.4, 0))
		box(b, "glow_green", Vector3(x + 0.6, 1.75, -17.57), Vector3(0.4, 0.25, 0.01), false, Vector3(0, -0.4, 0))
	# Arco de exploración sobre la primera camilla.
	for side: float in [-1.0, 1.0]:
		box(b, "furn", Vector3(3.9 + side * 0.65, 1.15, -16.3), Vector3(0.1, 2.3, 0.25), false)
	box(b, "furn", Vector3(3.9, 2.3, -16.3), Vector3(1.4, 0.12, 0.25), false)
	box(b, "glow_cyan", Vector3(3.9, 2.23, -16.3), Vector3(1.1, 0.02, 0.08), false)
	# Armarios médicos con cruz a lo largo del mamparo de popa.
	box(b, "furn", Vector3(5.0, 0.47, -10.35), Vector3(6.6, 0.94, 0.58))
	box(b, "counter", Vector3(5.0, 0.96, -10.35), Vector3(6.7, 0.04, 0.62), false)
	box(b, "furn", Vector3(5.0, 2.1, -10.2), Vector3(6.6, 0.6, 0.3))
	box(b, "glow_red", Vector3(3.0, 2.1, -10.36), Vector3(0.36, 0.1, 0.01), false)
	box(b, "glow_red", Vector3(3.0, 2.1, -10.36), Vector3(0.1, 0.36, 0.01), false)
	box(b, "furn", Vector3(2.0, 0.45, -12.0), Vector3(0.45, 0.9, 0.5))   # carro médico
	box(b, "glow_cyan", Vector3(2.0, 0.8, -11.74), Vector3(0.2, 0.08, 0.01), false)
	_plant(b, Vector3(8.5, 0, -10.9))


# --- D. Baño -------------------------------------------------------------------------------

func _bathroom() -> void:
	var b := "int:bano"
	box(b, "counter", Vector3(8.5, 0.21, -9.4), Vector3(0.55, 0.42, 0.4))          # inodoro
	box(b, "counter", Vector3(8.8, 0.6, -9.4), Vector3(0.18, 0.45, 0.45), false)
	box(b, "furn_dark", Vector3(8.45, 0.43, -9.4), Vector3(0.45, 0.02, 0.32), false)
	box(b, "furn", Vector3(8.55, 0.42, -6.6), Vector3(0.7, 0.84, 0.75))            # lavabo
	box(b, "metal", Vector3(8.5, 0.86, -6.6), Vector3(0.45, 0.04, 0.4), false)
	box(b, "metal", Vector3(8.93, 1.55, -6.6), Vector3(0.02, 0.7, 0.6), false)    # espejo
	box(b, "glow_white", Vector3(8.92, 1.95, -6.6), Vector3(0.02, 0.04, 0.5), false)
	# Ducha: plato, montantes, mampara y alcachofa.
	box(b, "counter", Vector3(5.2, 0.04, -9.3), Vector3(1.3, 0.08, 1.3))
	for p: Vector2 in [Vector2(4.55, -8.65), Vector2(5.85, -8.65)]:
		box(b, "metal", Vector3(p.x, 1.15, p.y), Vector3(0.05, 2.3, 0.05), true)
	box(b, "metal", Vector3(5.2, 2.3, -8.65), Vector3(1.35, 0.05, 0.05), false)
	cyl(b, "metal", Vector3(5.2, 2.25, -9.6), 0.12, 0.04, false)
	box(b, "wall_accent", Vector3(6.6, 1.1, -9.3), Vector3(0.06, 2.2, 1.3))         # separador


# --- H. Esclusa ---------------------------------------------------------------------------

func _airlock() -> void:
	var b := "int:esclusa"
	for z: float in [-5.6, -0.4]:
		box(b, "furn_dark", Vector3(5.1, 0.22, z), Vector3(4.0, 0.44, 0.42))
	# Trajes de repuesto colgados (visual).
	for i in 3:
		var p := Vector3(3.4 + i * 1.6, 0, -0.3)
		box(b, "furn", p + Vector3(0, 1.45, 0), Vector3(0.5, 0.7, 0.25), false)
		sphere(b, "fabric_light", p + Vector3(0, 2.0, 0), 0.16)
	# Franjas de advertencia junto a la puerta exterior.
	for i in 6:
		box(b, "trim" if i % 2 == 0 else "furn_dark", Vector3(8.5, 0.005, -3.75 + i * 0.3), Vector3(0.8, 0.01, 0.28), false)
	_label("esclusa", Vector3(1.32, 2.6, -3.0), Vector3(0, PI / 2, 0), 0.0016, Color(1, 0.8, 0.3))


func _airlock_light(key: String, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(0.05, 0.12, 0.3)
	mi.mesh = m
	var mat := glow(Color(1, 0.15, 0.1))
	mi.material_override = mat
	mi.position = pos
	mi.layers = Layers.bit(Layers.SHIP_INT) | Layers.bit(Layers.SHIP_EXT)
	ship.add_child(mi)
	dyn["airlock_lights"][key] = mat


# --- Vestuario EVA --------------------------------------------------------------------------

func _eva_room() -> void:
	var b := "int:vestuario"
	box(b, "furn", Vector3(8.65, 1.05, 2.0), Vector3(0.6, 2.1, 3.2))
	for i in 6:
		box(b, "furn_dark", Vector3(8.34, 1.05, 0.6 + i * 0.56), Vector3(0.01, 2.0, 0.02), false)
	for i in 3:
		var p := Vector3(3.6 + i * 1.4, 0, 3.55)
		cyl(b, "metal", p + Vector3(0, 0.05, 0), 0.3, 0.1, true)
		box(b, "furn", p + Vector3(0, 1.15, 0), Vector3(0.5, 0.8, 0.3), false)
		sphere(b, "furn", p + Vector3(0, 1.77, 0), 0.17)
		sphere(b, "glow_amber", p + Vector3(0, 1.79, -0.06), 0.13, Vector3(1, 0.8, 0.9))
	box(b, "furn_dark", Vector3(6.2, 0.23, 1.6), Vector3(1.8, 0.46, 0.45))


# --- Sala común -----------------------------------------------------------------------------

func _lounge() -> void:
	var b := "int:salon"
	# Sofá de tres plazas mirando al ventanal de estribor (los asientos se pueden usar).
	box(b, "fabric", Vector3(4.2, 0.22, 6.6), Vector3(0.75, 0.44, 3.6))
	for i in 3:
		box(b, "fabric_light", Vector3(4.25, 0.5, 5.4 + i * 1.2), Vector3(0.7, 0.12, 1.1), false)
	box(b, "fabric", Vector3(3.78, 0.75, 6.6), Vector3(0.16, 0.75, 3.6), false)
	for z: float in [4.75, 8.45]:
		box(b, "fabric", Vector3(4.15, 0.45, z), Vector3(0.85, 0.5, 0.15), false)
	# Mesa baja, lámpara de pie y plantas.
	box(b, "counter", Vector3(6.0, 0.42, 6.6), Vector3(0.9, 0.05, 1.6), false)
	box(b, "furn_dark", Vector3(6.0, 0.2, 6.6), Vector3(0.7, 0.4, 1.3))
	cyl(b, "metal", Vector3(3.9, 0.85, 9.4), 0.03, 1.7, false)
	sphere(b, "glow_amber", Vector3(3.9, 1.75, 9.4), 0.2, Vector3(1, 0.7, 1))
	_plant(b, Vector3(8.5, 0, 4.5))
	_plant(b, Vector3(8.5, 0, 9.5))
	# Pantalla en el mamparo con los datos de navegación.
	box(b, "furn_dark", Vector3(5.0, 1.7, 4.08), Vector3(2.4, 1.2, 0.05), false)
	box(b, "screen", Vector3(5.0, 1.7, 4.11), Vector3(2.2, 1.05, 0.01), false)
	_label("salon", Vector3(5.0, 1.7, 4.09), Vector3.ZERO, 0.002)


# --- E. Sala de máquinas ---------------------------------------------------------------------

func _engineering() -> void:
	var b := "int:maquinas"
	var rc := Vector3(0, 0, 16.5)
	# Núcleo del reactor con anillos que brillan según la potencia (material dinámico) y barandilla.
	cyl(b, "metal", rc + Vector3(0, H * 0.5, 0), 1.2, H, true)
	cyl(b, "hull_dark", rc + Vector3(0, 0.15, 0), 1.6, 0.3, true)
	cyl(b, "hull_dark", rc + Vector3(0, H - 0.15, 0), 1.6, 0.3, false)
	for y: float in [0.8, 1.5, 2.2]:
		ring(b, "reactor_glow", rc + Vector3(0, y, 0), 1.2, 1.33)
	ring(b, "trim", rc + Vector3(0, 1.05, 0), 2.35, 2.42)
	for i in 8:
		var a := TAU * i / 8.0
		cyl(b, "metal", rc + Vector3(cos(a) * 2.38, 0.52, sin(a) * 2.38), 0.03, 1.05, false)
	# Alojamientos de los motores principales contra el mamparo de popa.
	for side: float in [-1.0, 1.0]:
		box(b, "hull_dark", Vector3(side * 5.5, 1.3, 21.1), Vector3(3.6, 2.6, 1.6))
		for i in 5:
			box(b, "engine_glow", Vector3(side * 5.5 - 1.3 + i * 0.65, 1.4, 20.29), Vector3(0.4, 1.4, 0.02), false)
		# Bombas y paneles laterales.
		box(b, "metal", Vector3(side * 8.45, 0.9, 15.0), Vector3(0.9, 1.8, 3.6))
		for i in 3:
			box(b, "glow_green" if i != 1 else "glow_amber", Vector3(side * 7.99, 1.4, 13.8 + i * 1.2), Vector3(0.01, 0.06, 0.06), false)
		# Conducciones por el techo y bajantes.
		cyl(b, "metal", Vector3(side * 2.6, H - 0.3, 16.0), 0.1, 11.0, false, Vector3(PI / 2, 0, 0))
		cyl(b, "trim", Vector3(side * 3.1, H - 0.3, 16.0), 0.07, 11.0, false, Vector3(PI / 2, 0, 0))
		cyl(b, "metal", Vector3(side * 2.6, 2.0, 20.2), 0.1, 1.4, false)
		cyl(b, "metal", Vector3(side * 1.4, H - 0.3, 16.5), 0.08, 1.2, false, Vector3(0, 0, PI / 2))
	# Consolas de ingeniería junto a la puerta (la izquierda muestra datos reales).
	for side: float in [-1.0, 1.0]:
		box(b, "furn_dark", Vector3(side * 4.5, 0.45, 10.9), Vector3(2.2, 0.9, 0.7))
		box(b, "screen", Vector3(side * 4.5, 1.25, 11.27), Vector3(1.8, 0.6, 0.04), false)
	_label("maquinas", Vector3(-4.5, 1.25, 11.27), Vector3.ZERO, 0.0015, Color(0.6, 1.0, 0.8))
	for i in 6:
		box(b, "glow_amber" if i % 2 == 0 else "glow_cyan", Vector3(3.8 + i * 0.28, 1.25, 11.3), Vector3(0.12, 0.3, 0.01), false)
	box(b, "trim", Vector3(0, 0.006, 13.0), Vector3(1.2, 0.012, 4.6), false)


# --- Exterior -------------------------------------------------------------------------------

func _exterior() -> void:
	var faces := ShipHull.new().build(self)
	var shell := ConcavePolygonShape3D.new()
	shell.set_faces(faces)
	shell.backface_collision = true
	_shape(shell, Transform3D())
	_engine_glow_discs()
	_landing_gear()
	_ramp()
	_nav_lights()
	_floodlights()


## Luces de navegación que parpadean (roja a babor, verde a estribor, estroboscópica blanca en las derivas y
## baliza roja en el lomo) con materiales propios para animarlos sin tocar los del interior.
func _nav_lights() -> void:
	var list := []
	var specs := [["nav_red", Color(1.0, 0.12, 0.08), Vector3(-19.75, 0.05, 16.0), 0.2, "steady"],
		["nav_green", Color(0.2, 1.0, 0.35), Vector3(19.75, 0.05, 16.0), 0.2, "steady"],
		["strobe", Color(1, 1, 1), Vector3(-5.85, 7.25, 22.7), 0.13, "strobe"],
		["strobe", Color(1, 1, 1), Vector3(5.85, 7.25, 22.7), 0.13, "strobe"],
		["beacon", Color(1.0, 0.2, 0.1), Vector3(0, ShipHull.C_Y + ShipHull.B_FUS + 0.55, -2.0), 0.16, "beacon"]]
	for sp in specs:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = sp[3]
		sm.height = sp[3] * 2.0
		mi.mesh = sm
		var m := glow(sp[1], 2.0)
		mi.material_override = m
		mi.position = sp[2]
		mi.layers = Layers.bit(Layers.SHIP_EXT)
		ship.add_child(mi)
		list.append([m, sp[1], sp[4]])
	dyn["nav_blink"] = list


## Focos exteriores (K): dos proyectores bajo el morro hacia delante y abajo. Sólo iluminan el mundo.
func _floodlights() -> void:
	var lights := []
	for side: float in [-1.0, 1.0]:
		var l := SpotLight3D.new()
		l.position = Vector3(side * 1.6, -1.0, -26.0)
		l.rotation = Vector3(-0.42, side * 0.12, 0)
		l.spot_range = 160.0
		l.spot_angle = 32.0
		l.spot_attenuation = 0.8
		l.light_energy = 6.0
		l.light_color = Color(1.0, 0.95, 0.85)
		l.light_cull_mask = Layers.bit(Layers.WORLD)
		l.layers = Layers.bit(Layers.WORLD)
		l.shadow_enabled = false
		l.visible = false
		ship.add_child(l)
		lights.append(l)
	dyn["floodlights"] = lights


func _engine_glow_discs() -> void:
	var discs := []
	var mat: Material = mats["engine_glow"]
	for p: Vector3 in [Vector3(-3.4, ShipHull.C_Y, 24.66), Vector3(3.4, ShipHull.C_Y, 24.66), Vector3(-15.5, 0.3, 23.42), Vector3(15.5, 0.3, 23.42)]:
		var mi := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 1.05 if absf(p.x) < 5.0 else 0.88
		c.bottom_radius = c.top_radius
		c.height = 0.05
		mi.mesh = c
		mi.material_override = mat
		mi.rotation = Vector3(PI / 2, 0, 0)
		mi.position = p
		mi.layers = Layers.bit(Layers.SHIP_EXT)
		ship.add_child(mi)
		discs.append(mi)
	dyn["engine_discs"] = discs


func _landing_gear() -> void:
	var leg_mat: Material = mats["metal"]
	var pad_mat: Material = mats["hull_dark"]
	var drop := ShipLayout.GEAR_DROP
	for p: Vector3 in ShipLayout.GEAR_POINTS:
		var root := Node3D.new()
		root.position = p
		ship.add_child(root)
		var top := -0.9
		var leg := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.17
		c.bottom_radius = 0.13
		c.height = drop + top - 0.1
		leg.mesh = c
		leg.material_override = leg_mat
		leg.position = Vector3(0, top - c.height * 0.5, 0)
		leg.layers = Layers.bit(Layers.SHIP_EXT)
		root.add_child(leg)
		var strut := MeshInstance3D.new()
		var sc := CylinderMesh.new()
		sc.top_radius = 0.24
		sc.bottom_radius = 0.24
		sc.height = 0.5
		strut.mesh = sc
		strut.material_override = pad_mat
		strut.position = Vector3(0, top - 0.25, 0)
		strut.layers = leg.layers
		root.add_child(strut)
		var pad := MeshInstance3D.new()
		var pc := CylinderMesh.new()
		pc.top_radius = 0.5
		pc.bottom_radius = 0.6
		pc.height = 0.14
		pad.mesh = pc
		pad.material_override = pad_mat
		pad.position = Vector3(0, -drop + 0.07, 0)
		pad.layers = leg.layers
		root.add_child(pad)
		dyn["gear"].append(root)
		var s := BoxShape3D.new()
		s.size = Vector3(1.1, 0.3, 1.1)
		dyn["gear_shapes"].append(_shape(s, Transform3D(Basis(), p + Vector3(0, -drop + 0.15, 0))))


## Rampa de la esclusa: del umbral exterior hasta 3,1 m por debajo de la cubierta (≈27°). Baja más que
## las patas (2,0 m) para enlazar con el suelo aunque el terreno sea irregular (el extremo puede quedar
## enterrado; nunca queda un escalón).
func _ramp() -> void:
	var length := 6.8
	var drop := 3.1
	var angle := asin(drop / length)
	var door: Vector2 = ShipLayout.DOORS["esclusa_ext"][2]
	var pivot := Vector3(ShipHull.shell_x(door.y, 0.0) + 0.05, 0.0, door.y)
	var root := Node3D.new()
	root.position = pivot
	root.rotation = Vector3(0, 0, -angle)
	ship.add_child(root)
	var slab := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(length, 0.1, 1.5)
	slab.mesh = bm
	slab.material_override = mats["floor"]
	slab.position = Vector3(length * 0.5, -0.05, 0)
	slab.layers = Layers.bit(Layers.SHIP_EXT)
	root.add_child(slab)
	for side: float in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(length, 0.05, 0.05)
		rail.mesh = rm
		rail.material_override = mats["trim"]
		rail.position = Vector3(length * 0.5, 0.9, side * 0.72)
		rail.layers = Layers.bit(Layers.SHIP_EXT)
		root.add_child(rail)
	var s := BoxShape3D.new()
	s.size = Vector3(length, 0.1, 1.5)
	var xf := Transform3D(Basis.from_euler(Vector3(0, 0, -angle)), pivot) * Transform3D(Basis(), Vector3(length * 0.5, -0.05, 0))
	dyn["ramp"] = root
	dyn["ramp_shape"] = _shape(s, xf)


# --- Puertas ---------------------------------------------------------------------------------

func _doors() -> void:
	var mat := _panel(Color(0.55, 0.6, 0.66), 0.5, 0.5, 0.3)
	var stripe: Material = mats["trim"]
	for id in ShipLayout.DOORS:
		var d: Array = ShipLayout.DOORS[id]
		if d[4] == "arco":
			continue
		var door := ShipDoor.new()
		door.id = id
		var c: Vector2 = d[2]
		door.center = Vector3(c.x, 0, c.y)
		door.normal_axis = d[3]
		door.automatic = d[4] == "auto"
		if ShipLayout.DOOR_SIZES.has(id):
			var ds: Vector2 = ShipLayout.DOOR_SIZES[id]
			door.width = ds.x
			door.height = ds.y
			door.sense_radius = 2.2
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = door.panel_size()
		mi.mesh = bm
		mi.material_override = mat
		mi.layers = Layers.bit(Layers.SHIP_INT) | Layers.bit(Layers.SHIP_EXT)
		ship.add_child(mi)
		var band := MeshInstance3D.new()
		var band_mesh := BoxMesh.new()
		band_mesh.size = door.panel_size() * Vector3(1.05, 0.04, 1.05)
		band.mesh = band_mesh
		band.material_override = stripe
		band.position = Vector3(0, 0.1, 0)
		band.layers = mi.layers
		mi.add_child(band)
		door.mesh = mi
		var s := BoxShape3D.new()
		s.size = door.panel_size()
		door.shape = _shape(s, Transform3D(Basis(), door.closed_position()))
		door.update(0.0, [])
		dyn["doors"][id] = door
		# Marco del vano.
		var b := cell(door.center + (Vector3(0.3, 1, 0) if door.normal_axis == "x" else Vector3(0, 1, 0.3)))
		var frame_len := door.width + 0.2
		if door.normal_axis == "x":
			box(b, "wall_accent", door.center + Vector3(0, door.height + 0.06, 0), Vector3(0.16, 0.12, frame_len), false)
		else:
			box(b, "wall_accent", door.center + Vector3(0, door.height + 0.06, 0), Vector3(frame_len, 0.12, 0.16), false)
	var inner: Vector2 = ShipLayout.DOORS["esclusa_int"][2]
	var outer: Vector2 = ShipLayout.DOORS["esclusa_ext"][2]
	var lz := inner.y - ShipLayout.DOOR_WIDTH * 0.5 - 0.25
	_airlock_light("inner", Vector3(inner.x + 0.08, 2.5, lz))
	_airlock_light("inner_corr", Vector3(inner.x - 0.08, 2.5, lz))
	_airlock_light("outer", Vector3(outer.x - 0.08, 2.5, lz))
	_airlock_light("outer_ext", Vector3(ShipHull.shell_x(lz, 2.5) + 0.05, 2.5, lz))


# --- Luces ------------------------------------------------------------------------------------

func _lights() -> void:
	var warm := Color(1.0, 0.92, 0.8)
	var cool := Color(0.85, 0.95, 1.0)
	# 12 luces (ronda 9; antes 23): en el renderizador Compatibility cada luz que toca una malla añade una pasada de
	# dibujo, así que se usa una o dos por sala con alcances que apenas se solapan con las vecinas.
	var specs := [
		[Vector3(0, 2.7, -21.8), 6.5, 1.55, Color(0.82, 0.9, 1.0)],      # puente
		[Vector3(0, 2.75, -12.0), 5.5, 1.1, warm],                       # pasillo delantero
		[Vector3(0, 2.75, -2.0), 5.5, 1.1, warm],                        # pasillo central
		[Vector3(0, 2.75, 7.0), 5.0, 1.1, warm],                         # pasillo trasero
		[Vector3(-5.1, 2.7, -13.0), 6.0, 1.3, Color(1.0, 0.93, 0.82)],   # comedor
		[Vector3(-5.1, 2.7, -3.0), 6.0, 1.15, Color(1.0, 0.88, 0.75)],   # dormitorios
		[Vector3(-5.1, 2.7, 6.0), 5.5, 1.1, cool],                       # almacén
		[Vector3(5.1, 2.7, -14.0), 5.5, 1.35, Color(0.9, 1.0, 1.0)],     # enfermería
		[Vector3(5.1, 2.7, -5.5), 5.0, 1.15, Color(1.0, 0.95, 0.85)],    # baño y esclusa
		[Vector3(5.1, 2.7, 4.0), 5.5, 1.15, Color(1.0, 0.88, 0.7)],      # vestuario y sala común
		[Vector3(-3.5, 2.7, 16.0), 7.0, 1.15, Color(0.7, 0.95, 1.0)],    # máquinas
		[Vector3(3.5, 2.7, 16.0), 7.0, 1.15, Color(0.7, 0.95, 1.0)],
	]
	for sp in specs:
		var l := OmniLight3D.new()
		l.position = sp[0]
		l.omni_range = sp[1] + 1.5
		l.light_energy = sp[2] * 1.15
		l.light_color = sp[3]
		l.omni_attenuation = 1.0
		l.light_specular = 0.35
		dyn["lights"].append([l, l.light_color, l.light_energy])
		l.shadow_enabled = false
		l.light_cull_mask = Layers.interior_light_mask()
		# Las cámaras también filtran las luces por sus `layers`: sin esto la cámara del interior (que no dibuja
		# WORLD) descartaba todas las luces y el interior sólo tenía luz ambiente (plano, ADR-023).
		l.layers = Layers.interior_light_mask()
		ship.add_child(l)
	# Foco exterior sobre la rampa (sólo ilumina el exterior).
	var door: Vector2 = ShipLayout.DOORS["esclusa_ext"][2]
	var spot := SpotLight3D.new()
	spot.position = Vector3(ShipHull.shell_x(door.y, 2.8) + 0.4, 2.8, door.y)
	spot.rotation = Vector3(-PI / 2 + 0.35, 0, 0)
	spot.rotate_object_local(Vector3.UP, -PI / 2)
	spot.spot_range = 14.0
	spot.spot_angle = 50.0
	spot.light_energy = 2.0
	spot.light_cull_mask = Layers.sun_mask()
	spot.layers = Layers.sun_mask()
	ship.add_child(spot)
	dyn["floodlight"] = spot
