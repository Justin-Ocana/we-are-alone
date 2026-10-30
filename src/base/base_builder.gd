class_name BaseBuilder
extends RefCounted
## Construye la geometría de la base LF-01 (ADR-043) a partir de BaseLayout: suelos, techos, tabiques con sus
## vanos, carcasa exterior semienterrada (taludes de regolito y cubierta), luces por sala, carteles, logotipos de
## MacSpaces, pantallas y el mobiliario de cada módulo. Todo se agrupa con MeshBatcher en un lote por sala
## ("base:<sala>") para poder dejar de dibujar las salas que no se ven, y uno exterior ("base:ext").
## Estética: paneles blancos, metal gris, superficies negras, detalles naranja y desgaste.

const H_DOOR := BaseLayout.DOOR_H
const T := BaseLayout.WALL_T
const FLOOR_Y := 0.05        ## altura del suelo interior sobre la explanada
const LOGO := "res://assets/ui/macspaces_logo.png"
const EMERGENCY := Color(1.0, 0.42, 0.12)
const WHITE := Color(1.0, 0.95, 0.88)

var base: Node3D
var body: StaticBody3D
var batcher := MeshBatcher.new()
var mats := {}
var lights := {}          ## sala → [OmniLight3D]
var lamp_mats := {}       ## sala → material de los plafones (cambia con la energía)
var labels := {}          ## id → Label3D (pantallas y terminales con texto que cambia)
var nodes := {}           ## id → Node3D (cápsula, compuertas del techo, etc.)
var shape_count := 0
var _logo_mat: StandardMaterial3D
var _logo_mat_ext: StandardMaterial3D


func build(p_base: Node3D, p_body: StaticBody3D) -> void:
	base = p_base
	body = p_body
	_make_materials()
	for id in BaseLayout.ROOMS:
		_room_shell(id)
	_exterior()
	_props()
	_exterior_lights()
	batcher.build(base, mats, func(b: String) -> int:
		return Layers.WORLD if b == "base:ext" else Layers.SHIP_INT)
	for b in batcher.meshes_by_batch:
		for mi: MeshInstance3D in batcher.meshes_by_batch[b]:
			mi.visibility_range_end = 0.0 if b == "base:ext" or b == "base:hangar" else 90.0


# --- Materiales -----------------------------------------------------------------------------

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
	for k in opts:
		m.set_shader_parameter(k, opts[k])
	return m


func _make_materials() -> void:
	mats = {
		# Interior: paneles blancos con más suciedad y desgaste que la nave (años de abandono).
		"wall": _panel(Color(0.84, 0.84, 0.82), 1.2, 0.65, 0.0, 0.0, 0.38, {"grime": 0.42, "wear": 0.3, "fill": 0.035}),
		"wall_dark": _panel(Color(0.09, 0.09, 0.10), 0.9, 0.5, 0.2, 0.0, 0.3, {"grime": 0.3, "wear": 0.35, "fill": 0.035}),
		"metal": _panel(Color(0.52, 0.54, 0.57), 0.7, 0.35, 0.7, 0.0, 0.25, {"grime": 0.45, "wear": 0.2, "bevel": 0.8, "fill": 0.035}),
		"floor": _panel(Color(0.24, 0.25, 0.27), 1.0, 0.7, 0.5, 1.0, 0.35, {"grime": 0.55, "wear": 0.45, "rivets": 0.0, "fill": 0.035}),
		"ceiling": _panel(Color(0.55, 0.56, 0.58), 1.4, 0.8, 0.0, 0.0, 0.4, {"grime": 0.3, "wear": 0.05, "fill": 0.035}),
		"trim": _panel(Color(0.95, 0.42, 0.08), 3.0, 0.45, 0.1, 0.0, 0.2, {"rivets": 0.0, "grime": 0.4, "wear": 0.55, "fill": 0.035}),
		"furn": _panel(Color(0.86, 0.87, 0.87), 1.6, 0.42, 0.0, 0.0, 0.18, {"rivets": 0.0, "grime": 0.25, "wear": 0.2, "bevel": 0.6, "fill": 0.035}),
		"furn_dark": _panel(Color(0.12, 0.12, 0.14), 1.4, 0.55, 0.25, 0.0, 0.25, {"rivets": 0.0, "grime": 0.25, "wear": 0.3, "bevel": 0.6, "fill": 0.035}),
		"hangar_wall": _panel(Color(0.50, 0.51, 0.53), 3.2, 0.5, 0.5, 0.0, 0.3, {"grime": 0.5, "wear": 0.25, "bevel": 1.0, "fill": 0.03}),
		# Exterior: chapa gris clara curtida por el polvo y regolito apilado encima y alrededor.
		"shell": _panel(Color(0.62, 0.62, 0.60), 2.4, 0.6, 0.2, 0.0, 0.3, {"exterior": 1.0, "grime": 0.6, "wear": 0.4, "bevel": 1.2}),
		"shell_dark": _panel(Color(0.16, 0.16, 0.17), 1.2, 0.6, 0.4, 0.0, 0.3, {"exterior": 1.0, "grime": 0.5, "wear": 0.5}),
		"regolith": _regolith(),
		"glass": _glass(),
		"frost": _frost(),
		"plant": _std(Color(0.22, 0.42, 0.20), 0.9),
		"plant_dead": _std(Color(0.30, 0.24, 0.14), 0.95),
		"fabric": _std(Color(0.16, 0.16, 0.18), 0.92),
		"glow_amber": _glow(Color(1.0, 0.5, 0.12)),
		"glow_red": _glow(Color(1.0, 0.12, 0.08)),
		"glow_cyan": _glow(Color(0.35, 0.85, 1.0)),
		"glow_green": _glow(Color(0.25, 1.0, 0.45)),
		"glow_magenta": _glow(Color(0.85, 0.3, 1.0) * 0.7),
		"screen": _glow(Color(0.04, 0.10, 0.16)),
		"screen_dead": _glow(Color(0.015, 0.015, 0.02)),
	}
	for id in BaseLayout.ROOMS:
		var m := _glow(EMERGENCY * 0.8 if BaseLayout.ROOMS[id][6] == "emergencia" else Color(0.05, 0.05, 0.05))
		mats["lamp:" + id] = m
		lamp_mats[id] = m
	var tex: Texture2D = load(LOGO)
	_logo_mat = StandardMaterial3D.new()
	_logo_mat.albedo_texture = tex
	_logo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_logo_mat.emission_enabled = true
	_logo_mat.emission = Color(1, 1, 1)
	_logo_mat.emission_texture = tex
	_logo_mat.emission_energy_multiplier = 0.25
	_logo_mat.roughness = 0.6
	_logo_mat_ext = _logo_mat.duplicate()
	_logo_mat_ext.emission_energy_multiplier = 0.05


static func _std(c: Color, rough: float = 0.6, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


## Regolito de taludes y cubiertas: de doble cara (los taludes son prismas abiertos; desde algunos ángulos se veía
## a través de ellos; ronda 11).
static func _regolith() -> StandardMaterial3D:
	var m := _std(Color(0.34, 0.33, 0.31), 1.0)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _glow(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


static func _glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.55, 0.75, 0.9, 0.12)
	m.roughness = 0.05
	m.metallic_specular = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _frost() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.88, 1.0, 0.35)
	m.roughness = 0.4
	m.emission_enabled = true
	m.emission = Color(0.2, 0.45, 0.6)
	m.emission_energy_multiplier = 0.4
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# --- Primitivas -----------------------------------------------------------------------------

func box(batch: String, mat: String, center: Vector3, size: Vector3, collide := true, rot_y := 0.0) -> void:
	# Marcas pegadas al suelo (franjas, escarcha, mantas): encima del suelo elevado.
	if size.y <= 0.06 and center.y < 0.05 and mat != "floor":
		center.y += FLOOR_Y
	var xf := Transform3D(Basis(Vector3.UP, rot_y), center)
	batcher.box(batch, mat, xf, size)
	if collide:
		var s := BoxShape3D.new()
		s.size = size
		var cs := CollisionShape3D.new()
		cs.shape = s
		cs.transform = xf
		body.add_child(cs)
		shape_count += 1


func cyl(batch: String, mat: String, center: Vector3, radius: float, height: float, collide := false, rot := Vector3.ZERO,
		top := -1.0, segments := 16) -> void:
	var c := CylinderMesh.new()
	c.top_radius = radius if top < 0.0 else top
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	var xf := Transform3D(Basis.from_euler(rot), center)
	batcher.primitive(batch, mat, c, xf)
	if collide:
		var s := CylinderShape3D.new()
		s.radius = radius
		s.height = height
		var cs := CollisionShape3D.new()
		cs.shape = s
		cs.transform = xf
		body.add_child(cs)
		shape_count += 1


func sphere(batch: String, mat: String, center: Vector3, radius: float, scl := Vector3.ONE) -> void:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 14
	s.rings = 7
	batcher.primitive(batch, mat, s, Transform3D(Basis().scaled(scl), center))


## Prisma triangular (talud): base a lo largo de p0→p1 junto a la pared, sube `h` en la pared y llega al suelo a
## `run` metros hacia `out`.
func berm(p0: Vector3, p1: Vector3, out: Vector3, h: float, run: float) -> void:
	var up := Vector3.UP * h
	var o := out.normalized() * run
	var a0 := p0
	var b0 := p0 + up
	var c0 := p0 + o
	var a1 := p1
	var b1 := p1 + up
	var c1 := p1 + o
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var idx := PackedInt32Array()
	var slope_n := (o.normalized() * h + Vector3.UP * run).normalized()
	_quad(v, n, idx, b0, b1, c1, c0, slope_n)   # ladera
	var e0 := (p0 - p1).normalized()
	_tri(v, n, idx, a0, b0, c0, e0)
	_tri(v, n, idx, a1, c1, b1, -e0)
	batcher.triangles("base:ext", "regolith", v, n, idx)


static func _quad(v: PackedVector3Array, n: PackedVector3Array, idx: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3, nn: Vector3) -> void:
	var base_i := v.size()
	for p in [a, b, c, d]:
		v.append(p)
		n.append(nn)
	if (c - a).cross(b - a).dot(nn) > 0.0:
		idx.append_array([base_i, base_i + 1, base_i + 2, base_i, base_i + 2, base_i + 3])
	else:
		idx.append_array([base_i, base_i + 2, base_i + 1, base_i, base_i + 3, base_i + 2])


static func _tri(v: PackedVector3Array, n: PackedVector3Array, idx: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3,
		nn: Vector3) -> void:
	var base_i := v.size()
	for p in [a, b, c]:
		v.append(p)
		n.append(nn)
	if (c - a).cross(b - a).dot(nn) > 0.0:
		idx.append_array([base_i, base_i + 1, base_i + 2])
	else:
		idx.append_array([base_i, base_i + 2, base_i + 1])


func label(id: String, text: String, pos: Vector3, rot_y: float, size := 0.12, col := Color(1.0, 0.55, 0.15),
		layer := Layers.SHIP_INT) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = size * 0.01
	l.font_size = 48
	l.outline_size = 6
	l.modulate = col
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.position = pos
	l.rotation.y = rot_y
	l.layers = Layers.bit(layer)
	l.double_sided = false
	l.shaded = false
	l.font = UiTheme.title_font()
	base.add_child(l)
	if id != "":
		labels[id] = l
	return l


## Logotipo de MacSpaces (quad con la imagen) mirando hacia `rot_y` (0 = hacia +Z, sur).
func logo(pos: Vector3, rot_y: float, width: float, exterior := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(width, width * 194.0 / 314.0)
	mi.mesh = q
	mi.material_override = _logo_mat_ext if exterior else _logo_mat
	mi.position = pos
	mi.rotation.y = rot_y
	mi.layers = Layers.bit(Layers.WORLD if exterior else Layers.SHIP_INT)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	base.add_child(mi)
	return mi


# --- Estructura de cada sala ----------------------------------------------------------------

func _holes_on_edge(room: String, edge: String) -> Array:
	var r := BaseLayout.room_rect(room)
	var out := []
	for did in BaseLayout.DOORS:
		var d: Array = BaseLayout.DOORS[did]
		if d[0] != room and d[1] != room:
			continue
		var c: Vector2 = d[2]
		var w: float = d[4]
		var h: float = d[5]
		match edge:
			"n":
				if d[3] == "z" and absf(c.y - r.position.y) < 0.01:
					out.append([c.x, w + 0.32, 0.0, h + 0.2])
			"s":
				if d[3] == "z" and absf(c.y - r.end.y) < 0.01:
					out.append([c.x, w + 0.32, 0.0, h + 0.2])
			"w":
				if d[3] == "x" and absf(c.x - r.position.x) < 0.01:
					out.append([c.y, w + 0.32, 0.0, h + 0.2])
			"e":
				if d[3] == "x" and absf(c.x - r.end.x) < 0.01:
					out.append([c.y, w + 0.32, 0.0, h + 0.2])
	return out


func _room_shell(id: String) -> void:
	var r := BaseLayout.room_rect(id)
	var h := BaseLayout.room_height(id)
	var b := "base:" + id
	var cx := r.get_center().x
	var cz := r.get_center().y
	# Suelo 5 cm por encima de la explanada (ronda 11): a la misma altura que el terreno parpadeaba (z-fighting).
	box(b, "floor", Vector3(cx, FLOOR_Y - 0.06, cz), Vector3(r.size.x, 0.12, r.size.y))
	if id != "observatorio" and id != "hangar":
		box(b, "ceiling", Vector3(cx, h + 0.05, cz), Vector3(r.size.x, 0.1, r.size.y))
	# Tabiques interiores (cada sala los suyos), con vanos de puerta y, en el observatorio, ventanales.
	var wall_mat := "wall"
	var hn := _holes_on_edge(id, "n")
	var hs := _holes_on_edge(id, "s")
	var hw := _holes_on_edge(id, "w")
	var he := _holes_on_edge(id, "e")
	if id == "observatorio":
		for z in [-60.0, -56.0, -52.0]:
			hw.append([z, 3.0, 1.0, 4.6])
	if id == "hangar":
		wall_mat = "hangar_wall"
	_wall(true, r.position.y + T * 0.5, r.position.x, r.end.x, hn, h, b, wall_mat)
	_wall(true, r.end.y - T * 0.5, r.position.x, r.end.x, hs, h, b, wall_mat)
	_wall(false, r.position.x + T * 0.5, r.position.y, r.end.y, hw, h, b, wall_mat)
	_wall(false, r.end.x - T * 0.5, r.position.y, r.end.y, he, h, b, wall_mat)
	for hole in hw:
		if hole[2] > 0.01:
			box(b, "glass", Vector3(r.position.x + 0.1, (hole[2] + hole[3]) * 0.5, hole[0]), Vector3(0.04, hole[3] - hole[2], hole[1]), true)
	# Zócalo negro y franja naranja de señalización a la altura de la cadera (interrumpidos en los vanos).
	if id != "hangar":
		_band(id, b, 0.07, 0.14, "furn_dark", 0.03)
		_band(id, b, 1.05, 0.06, "trim", 0.02)
	_lights(id)


## Pared en el plano (z = `plane` si along_x, x = `plane` si no) de a0 a a1 con huecos [centro, ancho, y0, y1].
func _wall(along_x: bool, plane: float, a0: float, a1: float, holes: Array, h: float, b: String, mat: String,
		t := T) -> void:
	var sorted := holes.duplicate()
	sorted.sort_custom(func(p, q): return p[0] < q[0])
	var cursor := a0
	for hole in sorted:
		var h0: float = hole[0] - hole[1] * 0.5
		var h1: float = hole[0] + hole[1] * 0.5
		_piece(along_x, plane, cursor, h0, 0.0, h, b, mat, t)
		_piece(along_x, plane, h0, h1, 0.0, hole[2], b, mat, t)
		_piece(along_x, plane, h0, h1, hole[3], h, b, mat, t)
		cursor = h1
	_piece(along_x, plane, cursor, a1, 0.0, h, b, mat, t)


func _piece(along_x: bool, plane: float, a0: float, a1: float, y0: float, y1: float, b: String, mat: String,
		t := T) -> void:
	if a1 - a0 < 0.01 or y1 - y0 < 0.01:
		return
	var mid := (a0 + a1) * 0.5
	var c := Vector3(mid, (y0 + y1) * 0.5, plane) if along_x else Vector3(plane, (y0 + y1) * 0.5, mid)
	var s := Vector3(a1 - a0, y1 - y0, t) if along_x else Vector3(t, y1 - y0, a1 - a0)
	box(b, mat, c, s)


## Franja horizontal pegada a los cuatro tabiques (sin colisión), cortada en los vanos.
func _band(id: String, b: String, y: float, hgt: float, mat: String, depth: float) -> void:
	var r := BaseLayout.room_rect(id)
	var edges := {
		"n": [true, r.position.y + T + depth * 0.5, r.position.x + T, r.end.x - T],
		"s": [true, r.end.y - T - depth * 0.5, r.position.x + T, r.end.x - T],
		"w": [false, r.position.x + T + depth * 0.5, r.position.y + T, r.end.y - T],
		"e": [false, r.end.x - T - depth * 0.5, r.position.y + T, r.end.y - T],
	}
	for e in edges:
		var ed: Array = edges[e]
		var holes := _holes_on_edge(id, e)
		var cursor: float = ed[2]
		holes.sort_custom(func(p, q): return p[0] < q[0])
		var spans := []
		for hole in holes:
			if hole[2] > 0.01 and hole[2] > y + hgt:
				continue
			spans.append([cursor, hole[0] - hole[1] * 0.5])
			cursor = hole[0] + hole[1] * 0.5
		spans.append([cursor, ed[3]])
		for sp in spans:
			var l: float = sp[1] - sp[0]
			if l < 0.05:
				continue
			var mid: float = (sp[0] + sp[1]) * 0.5
			if ed[0]:
				box(b, mat, Vector3(mid, y, ed[1]), Vector3(l, hgt, depth), false)
			else:
				box(b, mat, Vector3(ed[1], y, mid), Vector3(depth, hgt, l), false)


## Luces de techo en rejilla (≈ una cada 7 m) y sus plafones. Sólo iluminan el interior (capas *_INT).
func _lights(id: String) -> void:
	var r := BaseLayout.room_rect(id)
	var h := BaseLayout.room_height(id)
	var b := "base:" + id
	var spacing := 7.0 if id != "hangar" else 20.0
	var nx := maxi(1, int(round(r.size.x / spacing)))
	var nz := maxi(1, int(round(r.size.y / spacing)))
	var arr: Array = []
	var mask := Layers.bits([Layers.SHIP_INT, Layers.BODY_INT, Layers.HEAD_INT, Layers.HEAD_INT_P2])
	if id == "hangar":
		mask |= Layers.bit(Layers.SHIP_EXT)   # la nave (casco exterior) también recibe la luz del hangar
	for ix in nx:
		for iz in nz:
			var p := Vector3(r.position.x + r.size.x * (ix + 0.5) / nx, h - 0.25, r.position.y + r.size.y * (iz + 0.5) / nz)
			if id == "hangar":
				# Plafones colgados bajo las cerchas (antes estaban en el techo y flotaban con las compuertas abiertas).
				var truss_i: int = clampi(int(round((iz + 0.5) / nz * 6.0 - 0.5)), 0, 5)
				p.z = r.position.y + r.size.y * (truss_i + 0.5) / 6.0
				p.y = h - 1.3
			var l := OmniLight3D.new()
			l.position = p
			l.omni_range = maxf(r.size.x / nx, r.size.y / nz) * 1.3 + (2.0 if id != "hangar" else 14.0)
			l.omni_attenuation = 1.2 if id != "hangar" else 0.55
			l.light_cull_mask = mask
			l.shadow_enabled = false
			l.light_energy = 0.0
			base.add_child(l)
			arr.append(l)
			var fx := Vector3(1.2, 0.06, 0.25) if r.size.x >= r.size.y else Vector3(0.25, 0.06, 1.2)
			if id == "hangar":
				fx = Vector3(2.5, 0.2, 2.5)
			box(b, "lamp:" + id, Vector3(p.x, h - 0.03 if id != "hangar" else h - 1.1, p.z), fx, false)
	lights[id] = arr


# --- Exterior semienterrado -----------------------------------------------------------------

func _outside_free(p: Vector2) -> bool:
	return _neighbor_height(p) <= 0.0


## Altura del módulo que ocupa el punto (0 si está libre).
func _neighbor_height(p: Vector2) -> float:
	for id in BaseLayout.ROOMS:
		if BaseLayout.room_rect(id).grow(0.05).has_point(p):
			return BaseLayout.room_height(id)
	return 0.0


func _exterior() -> void:
	for id in BaseLayout.ROOMS:
		var r := BaseLayout.room_rect(id)
		var h := BaseLayout.room_height(id)
		var roof_top := h + 0.45
		# Cubierta: losa gris y, encima, una capa de regolito (protección contra la radiación) salvo en el
		# observatorio (cúpula de cristal) y el hangar (compuertas).
		if id == "observatorio":
			_glass_roof(r, h)
		elif id == "hangar":
			_hangar_roof(r, h)
		else:
			box("base:ext", "shell_dark", Vector3(r.get_center().x, h + 0.25, r.get_center().y), Vector3(r.size.x + 0.6, 0.3, r.size.y + 0.6), false)
			box("base:ext", "regolith", Vector3(r.get_center().x, roof_top + 0.25, r.get_center().y), Vector3(r.size.x - 0.4, 0.5, r.size.y - 0.4), false)
		# Fachadas y taludes sólo donde no hay otra sala al lado.
		var edges := [
			[Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), Vector2(0, -1)],
			[Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), Vector2(0, 1)],
			[Vector2(r.position.x, r.position.y), Vector2(r.position.x, r.end.y), Vector2(-1, 0)],
			[Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), Vector2(1, 0)],
		]
		for e in edges:
			var a: Vector2 = e[0]
			var c: Vector2 = e[1]
			var out: Vector2 = e[2]
			var length := a.distance_to(c)
			var steps := maxi(1, int(ceil(length)))
			var span_start := -1.0
			var span_nh := -1.0
			for i in steps + 1:
				var t := float(i) / steps
				var p := a.lerp(c, minf(t, 1.0))
				# Altura del vecino al otro lado: 0 = libre (fachada y talud); más bajo que esta sala = fachada sólo por
				# encima de su cubierta (por ejemplo, el hangar sobre la esclusa).
				var nh := 1.0e9
				if i < steps:
					nh = _neighbor_height(p.lerp(a.lerp(c, float(i + 1) / steps), 0.5) + out * 0.4)
				var want := nh < h - 0.5
				if span_start >= 0.0 and (not want or nh != span_nh):
					if span_nh <= 0.0:
						_facade(id, a.lerp(c, span_start), a.lerp(c, t), out, h)
					else:
						_upper_facade(a.lerp(c, span_start), a.lerp(c, t), out, span_nh + 0.45, h)
					span_start = -1.0
				if want and span_start < 0.0:
					span_start = t
					span_nh = nh


func _facade(id: String, a: Vector2, c: Vector2, out: Vector2, h: float) -> void:
	var o3 := Vector3(out.x, 0, out.y)
	var along_x := absf(out.y) > 0.5
	var a_s := minf(a.x, c.x) if along_x else minf(a.y, c.y)
	var a_e := maxf(a.x, c.x) if along_x else maxf(a.y, c.y)
	var plane := (a.y if along_x else a.x) + (out.y if along_x else out.x) * 0.15
	# Huecos de la fachada: escotilla exterior de la esclusa y ventanales del observatorio.
	var holes := []
	var edge := "s" if out.y > 0.5 else ("n" if out.y < -0.5 else ("e" if out.x > 0.5 else "w"))
	for hole in _holes_on_edge(id, edge):
		holes.append(hole)
	if id == "observatorio" and edge == "w":
		for z in [-60.0, -56.0, -52.0]:
			holes.append([z, 3.0, 1.0, 4.6])
	holes = holes.filter(func(hh): return hh[0] > a_s and hh[0] < a_e)
	_wall(along_x, plane, a_s - 0.15, a_e + 0.15, holes, h + 0.4, "base:ext", "shell", 0.3)
	if not holes.is_empty():
		if id == "esclusa":
			box("base:ext", "trim", Vector3(plane + 0.17, H_DOOR + 0.45, 63.0), Vector3(0.04, 0.12, 2.6), false)
		if id == "observatorio":
			box("base:ext", "regolith", Vector3(plane - 1.0, 0.4, (a_s + a_e) * 0.5), Vector3(2.0, 0.8, a_e - a_s), false)
		return
	# Talud de regolito: nunca invade otra sala (se recorta con el espacio libre); en los callejones estrechos entre
	# módulos se rellena el hueco hasta casi la cubierta (lo construye sólo el lado este/sur para no duplicarlo).
	var bh := h * (0.72 if id != "hangar" else 0.42)
	var run := bh * 1.6
	var free := run
	for k in 5:
		var p := a.lerp(c, (k + 0.5) / 5.0) + out * 0.35
		free = minf(free, _free_run(p, out, run))
	if free >= run * 0.6:
		var bh2 := bh * free / run
		berm(Vector3(a.x, 0.0, a.y) + o3 * 0.3, Vector3(c.x, 0.0, c.y) + o3 * 0.3, o3, bh2, free)
	elif out.x > 0.5 or out.y > 0.5:
		var w := free + 0.05
		var mid := (a + c) * 0.5 + out * (0.3 + w * 0.5)
		var len := a.distance_to(c)
		var fill_h := minf(h, 3.2) * 0.85
		var sz := Vector3(len, fill_h, w) if along_x else Vector3(w, fill_h, len)
		box("base:ext", "regolith", Vector3(mid.x, fill_h * 0.5, mid.y), sz, false)


## Fachada por encima de un módulo vecino más bajo (sin talud).
func _upper_facade(a: Vector2, c: Vector2, out: Vector2, y0: float, h: float) -> void:
	var along_x := absf(out.y) > 0.5
	var mid := (a + c) * 0.5
	var length := a.distance_to(c)
	var plane := (a.y if along_x else a.x) + (out.y if along_x else out.x) * 0.15
	var cy := (y0 + h + 0.4) * 0.5
	var size := Vector3(length + 0.3, h + 0.4 - y0, 0.3) if along_x else Vector3(0.3, h + 0.4 - y0, length + 0.3)
	var center := Vector3(mid.x, cy, plane) if along_x else Vector3(plane, cy, mid.y)
	box("base:ext", "shell", center, size, false)


## Distancia libre (m) desde `p` hacia `out` hasta la siguiente sala (como mucho `max_d`).
func _free_run(p: Vector2, out: Vector2, max_d: float) -> float:
	var d := 0.0
	while d < max_d:
		if not _outside_free(p + out * d):
			return maxf(0.0, d - 0.4)
		d += 0.4
	return max_d


func _glass_roof(r: Rect2, h: float) -> void:
	var b := "base:observatorio"
	box(b, "metal", Vector3(r.get_center().x, h + 0.05, r.get_center().y), Vector3(r.size.x, 0.1, 0.3), false)
	for i in 5:
		var x := r.position.x + r.size.x * (i + 0.5) / 5.0
		box(b, "metal", Vector3(x, h + 0.05, r.get_center().y), Vector3(0.15, 0.12, r.size.y), false)
	box(b, "glass", Vector3(r.get_center().x, h + 0.1, r.get_center().y), Vector3(r.size.x, 0.04, r.size.y), true)
	box("base:ext", "shell_dark", Vector3(r.get_center().x, h + 0.2, r.position.y - 0.15), Vector3(r.size.x + 0.6, 0.4, 0.3), false)
	box("base:ext", "shell_dark", Vector3(r.get_center().x, h + 0.2, r.end.y + 0.15), Vector3(r.size.x + 0.6, 0.4, 0.3), false)


## Techo del hangar (ronda 11): marco perimetral macizo sobre los muros, dos hojas de compuerta (0,8 m, con costillas y
## franjas de aviso) que ruedan sobre raíles hacia fuera hasta unos pórticos exteriores donde se recogen, motores,
## balizas giratorias y cerchas interiores. Todo con colisión: se puede caminar por la cubierta.
func _hangar_roof(r: Rect2, h: float) -> void:
	var frame_w := 4.0
	var cx := r.get_center().x
	var cz := r.get_center().y
	var top := h + 0.6
	# Marco perimetral (viga de coronación) con pretil.
	box("base:ext", "shell_dark", Vector3(cx, h + 0.3, r.position.y + frame_w * 0.5), Vector3(r.size.x + 0.6, 0.6, frame_w), true)
	box("base:ext", "shell_dark", Vector3(cx, h + 0.3, r.end.y - frame_w * 0.5), Vector3(r.size.x + 0.6, 0.6, frame_w), true)
	box("base:ext", "shell_dark", Vector3(r.position.x + frame_w * 0.5, h + 0.3, cz), Vector3(frame_w, 0.6, r.size.y), true)
	box("base:ext", "shell_dark", Vector3(r.end.x - frame_w * 0.5, h + 0.3, cz), Vector3(frame_w, 0.6, r.size.y), true)
	for z in [r.position.y + 0.25, r.end.y - 0.25]:
		box("base:ext", "trim", Vector3(cx, top + 0.5, z), Vector3(r.size.x + 0.6, 1.0, 0.25), true)
	# Raíles a lo largo de los dos bordes norte y sur, prolongados por fuera de los muros sobre pórticos.
	var rail_len := r.size.x + 2.0 * (r.size.x * 0.5 - frame_w) + 4.0
	for z in [r.position.y + 2.2, r.end.y - 2.2]:
		box("base:ext", "metal", Vector3(cx, top + 0.1, z), Vector3(rail_len, 0.2, 0.6), true)
		for side in [-1.0, 1.0]:
			# Pórticos exteriores: pilares hasta el suelo y viga bajo el raíl.
			for k in 3:
				var x: float = cx + side * (r.size.x * 0.5 + 6.0 + k * 10.0)
				box("base:ext", "metal", Vector3(x, top * 0.5, z), Vector3(0.8, top, 0.8), true)
				box("base:ext", "trim", Vector3(x, 1.2, z), Vector3(0.84, 0.3, 0.84), false)
			box("base:ext", "shell_dark", Vector3(cx + side * (r.size.x * 0.5 + 16.0), top - 0.4, z), Vector3(32.0, 0.6, 0.9), true)
			# Motor de arrastre en el extremo interior del raíl.
			box("base:ext", "furn_dark", Vector3(cx + side * (r.size.x * 0.5 - 2.0), top + 0.6, z), Vector3(2.2, 1.0, 1.4), true)
			box("base:ext", "glow_amber", Vector3(cx + side * (r.size.x * 0.5 - 2.0), top + 1.12, z), Vector3(0.4, 0.04, 0.4), false)
	# Contrafuertes exteriores en los muros largos (dan escala y lógica estructural al volumen del hangar).
	for side in [-1.0, 1.0]:
		var i := 0
		var z := r.position.y + 6.0
		while z < r.end.y - 4.0:
			if side > 0.0 and z > 54.0 and z < 72.0:
				z += 10.0
				continue   # la esclusa está pegada a ese tramo del muro este
			box("base:ext", "shell_dark", Vector3(cx + side * (r.size.x * 0.5 + 0.9), h * 0.5, z), Vector3(1.5, h, 1.2), true)
			z += 10.0
			i += 1
	# Cerchas interiores y tirantes.
	for i in 6:
		var z := r.position.y + r.size.y * (i + 0.5) / 6.0
		box("base:hangar", "metal", Vector3(cx, h - 0.6, z), Vector3(r.size.x - 1.0, 0.8, 0.5), false)
		for side in [-1.0, 1.0]:
			box("base:hangar", "metal", Vector3(cx + side * (r.size.x * 0.5 - 0.6), h - 3.0, z), Vector3(0.5, 6.0, 0.5), false)
	var inner_w := r.size.x - frame_w * 2.0
	var inner_d := r.size.y - frame_w * 2.0
	var roof := Node3D.new()
	roof.name = "TechoHangar"
	base.add_child(roof)
	for side in [-1.0, 1.0]:
		var leaf := StaticBody3D.new()
		leaf.collision_layer = Layers.bit(Layers.PHYS_SHIP)
		leaf.collision_mask = 0
		leaf.position = Vector3(cx + side * inner_w * 0.25, top + 0.6, cz)
		var lw := inner_w * 0.5 + 0.4
		_leaf_part(leaf, "shell", Vector3.ZERO, Vector3(lw, 0.8, inner_d + 0.4))
		# Costillas transversales encima y canto de cierre con franjas de aviso negras y naranjas.
		for k in 7:
			var z: float = -inner_d * 0.5 + inner_d * (k + 0.5) / 7.0
			_leaf_part(leaf, "shell_dark", Vector3(0, 0.55, z), Vector3(lw - 0.6, 0.3, 0.5))
		var edge_x: float = -side * (lw * 0.5 - 0.15)
		for k in 14:
			var z2: float = -inner_d * 0.5 + inner_d * (k + 0.5) / 14.0
			_leaf_part(leaf, "trim" if k % 2 == 0 else "wall_dark", Vector3(edge_x, 0.0, z2), Vector3(0.32, 0.82, inner_d / 14.0))
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(lw, 0.8, inner_d + 0.4)
		cs.shape = bs
		leaf.add_child(cs)
		roof.add_child(leaf)
	nodes["techo"] = roof
	nodes["techo_w"] = inner_w
	# Balizas giratorias en las esquinas del marco (se encienden mientras las compuertas se mueven).
	var beacons := []
	for c in [Vector3(r.position.x + 2.0, top + 0.9, r.position.y + 2.0), Vector3(r.end.x - 2.0, top + 0.9, r.position.y + 2.0),
			Vector3(r.position.x + 2.0, top + 0.9, r.end.y - 2.0), Vector3(r.end.x - 2.0, top + 0.9, r.end.y - 2.0)]:
		var l := OmniLight3D.new()
		l.position = c + Vector3(0, 0.6, 0)
		l.light_color = Color(1.0, 0.55, 0.1)
		l.omni_range = 30.0
		l.light_energy = 0.0
		l.light_cull_mask = Layers.bits([Layers.WORLD, Layers.SHIP_EXT, Layers.BODY, Layers.HEAD, Layers.SHIP_INT])
		l.shadow_enabled = false
		base.add_child(l)
		var g := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.35
		sm.height = 0.5
		g.mesh = sm
		g.material_override = _glow(Color(0.25, 0.12, 0.03))
		g.position = c + Vector3(0, 0.3, 0)
		g.layers = Layers.bit(Layers.WORLD)
		base.add_child(g)
		beacons.append([l, g])
	nodes["roof_beacons"] = beacons
	terminal("hangar", "panel_hangar", Vector3(-5.0, 0, 30.7), 0.0, "COMPUERTAS DEL TECHO\nCONTROL MANUAL")


func _leaf_part(parent: Node3D, mat: String, pos: Vector3, size: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mats[mat]
	mi.position = pos
	mi.layers = Layers.bit(Layers.WORLD) | Layers.bit(Layers.SHIP_INT)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## Focos exteriores ámbar (la noche lunar dura dos semanas): escotilla de la esclusa, hangar y cámara criogénica.
func _exterior_lights() -> void:
	var mask := Layers.bits([Layers.WORLD, Layers.HEAD, Layers.BODY, Layers.SHIP_EXT, Layers.HEAD_P2])
	for e in [[Vector3(46.2, 3.6, 63.0), 28.0], [Vector3(36.0, 10.0, 46.0), 40.0], [Vector3(-36.0, 10.0, 66.0), 40.0],
			[Vector3(0.0, 6.0, -101.0), 24.0], [Vector3(-20.0, 7.0, -56.0), 22.0]]:
		var l := OmniLight3D.new()
		l.position = e[0]
		l.omni_range = e[1]
		l.omni_attenuation = 0.9
		l.light_color = Color(1.0, 0.72, 0.42)
		l.light_energy = 2.0
		l.light_cull_mask = mask
		l.shadow_enabled = false
		base.add_child(l)
		box("base:ext", "glow_amber", e[0] + Vector3(0, 0.15, 0), Vector3(0.6, 0.12, 0.6), false)
	# Balizas rojas en las esquinas del hangar.
	for c in [Vector3(-35.0, 22.6, 30.0), Vector3(35.0, 22.6, 30.0), Vector3(-35.0, 22.6, 100.0), Vector3(35.0, 22.6, 100.0)]:
		box("base:ext", "glow_red", c, Vector3(0.5, 0.5, 0.5), false)


# --- Mobiliario por módulo -----------------------------------------------------------------

func _props() -> void:
	_crio()
	_recuperacion()
	_enfermeria()
	_orientacion()
	_observatorio()
	_corridor("pasillo_norte")
	_corridor("pasillo_sur")
	_operaciones()
	_comunicaciones()
	_archivo()
	_labs()
	_energia()
	_hidroponia()
	_hangar()
	_taller()
	_esclusa()
	_signage()


## Terminal de pie: pupitre negro, pantalla encendida y rótulo pequeño encima.
func terminal(room: String, id: String, pos: Vector3, rot_y: float, title: String, dead := false) -> void:
	var b := "base:" + room
	var fwd := Vector3(sin(rot_y), 0.0, cos(rot_y))
	box(b, "furn_dark", pos + Vector3(0, 0.5, 0) - fwd * 0.1, Vector3(0.9, 1.0, 0.5).rotated(Vector3.UP, 0.0), true, rot_y)
	box(b, "metal", pos + Vector3(0, 1.02, 0) - fwd * 0.05, Vector3(0.95, 0.05, 0.6), false, rot_y)
	box(b, "furn_dark", pos + Vector3(0, 1.45, 0) - fwd * 0.28, Vector3(0.8, 0.55, 0.06), false, rot_y)
	box(b, "screen_dead" if dead else "screen", pos + Vector3(0, 1.45, 0) - fwd * 0.245, Vector3(0.7, 0.45, 0.01), false, rot_y)
	box(b, "trim", pos + Vector3(0, 1.75, 0) - fwd * 0.28, Vector3(0.8, 0.04, 0.07), false, rot_y)
	var l := label(id, title, pos + Vector3(0, 1.48, 0) - fwd * 0.235, rot_y, 0.07, Color(0.55, 0.85, 1.0) if not dead else Color(1.0, 0.3, 0.2))
	l.width = 900.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## Cápsula criogénica vertical. `open`: puerta de cristal abierta; `occupied`: silueta escarchada dentro.
func pod(room: String, pos: Vector3, rot_y: float, state: String) -> void:
	var b := "base:" + room
	var fwd := Vector3(sin(rot_y), 0.0, cos(rot_y))
	cyl(b, "metal", pos + Vector3(0, 0.12, 0), 0.75, 0.24, true)
	cyl(b, "wall", pos + Vector3(0, 2.45, 0), 0.75, 0.3, false)
	cyl(b, "trim", pos + Vector3(0, 2.62, 0), 0.6, 0.06, false)
	# Respaldo (media carcasa) y costillas laterales.
	box(b, "wall", pos + Vector3(0, 1.3, 0) - fwd * 0.55, Vector3(1.2, 2.1, 0.12), true, rot_y)
	for s in [-1.0, 1.0]:
		var side: Vector3 = Vector3(cos(rot_y), 0, -sin(rot_y)) * s * 0.62
		box(b, "metal", pos + Vector3(0, 1.3, 0) + side - fwd * 0.15, Vector3(0.12, 2.1, 0.7), true, rot_y)
	box(b, "glow_cyan" if state != "dead" else "glow_red", pos + Vector3(0, 2.3, 0) + fwd * 0.62, Vector3(0.5, 0.05, 0.02), false, rot_y)
	cyl(b, "metal", pos + Vector3(0.0, 2.9, 0) - fwd * 0.4, 0.08, 0.6, false)
	if state == "occupied" or state == "dead":
		box(b, "frost", pos + Vector3(0, 1.3, 0) + fwd * 0.5, Vector3(1.1, 2.0, 0.05), true, rot_y)
		box(b, "fabric", pos + Vector3(0, 1.1, 0) - fwd * 0.2, Vector3(0.45, 1.5, 0.3), false, rot_y)
	elif state == "empty":
		box(b, "glass", pos + Vector3(0, 1.3, 0) + fwd * 0.5, Vector3(1.1, 2.0, 0.04), true, rot_y)


func _crio() -> void:
	var b := "base:crio"
	# Seis cápsulas con puerta escarchada animada (la del protagonista al norte y cinco laterales) y una sexta lateral
	# ocupada. Las puertas que no se asignan a un jugador siguen cerradas: desde fuera no se sabe si hay alguien.
	var doors_out := []
	for i in BaseLayout.PODS.size():
		var pd: Array = BaseLayout.PODS[i]
		var pp: Vector3 = pd[0]
		var rot: float = pd[1]
		var fwd := Vector3(sin(rot), 0.0, cos(rot))
		pod("crio", pp, rot, "player")
		var door := MeshInstance3D.new()
		var dm := BoxMesh.new()
		dm.size = Vector3(1.1, 2.0, 0.04)
		door.mesh = dm
		door.material_override = mats["frost"]
		door.layers = Layers.bit(Layers.SHIP_INT)
		door.rotation.y = rot
		door.position = pp + Vector3(0, 1.3, 0) + fwd * 0.5
		base.add_child(door)
		var door_body := StaticBody3D.new()
		door_body.collision_layer = Layers.bit(Layers.PHYS_SHIP)
		door_body.collision_mask = 0
		var dcs := CollisionShape3D.new()
		var dbs := BoxShape3D.new()
		dbs.size = Vector3(1.1, 2.0, 0.1)
		dcs.shape = dbs
		door_body.add_child(dcs)
		door_body.rotation.y = rot
		door_body.position = pp + Vector3(0, 1.3, 0) + fwd * 0.55
		base.add_child(door_body)
		doors_out.append([door, door_body, door.position, door_body.position])
	nodes["pod_doors"] = doors_out
	terminal("crio", "terminal_medico", Vector3(2.2, 0, -97.4), -PI * 0.5, "MACSPACES · CAJAFUERTE\nREANIMACIÓN: COMPLETADA")
	pod("crio", Vector3(7.6, 0, -87.5), -PI * 0.5, "occupied")
	# Conductos de refrigerante por el techo y escarcha en el suelo.
	for x in [-5.0, 5.0]:
		cyl(b, "metal", Vector3(x, 4.1, -92.0), 0.14, 15.0, false, Vector3(PI * 0.5, 0, 0))
	box(b, "frost", Vector3(0, 0.005, -95.5), Vector3(4.0, 0.01, 4.0), false)
	box(b, "glow_cyan", Vector3(0, 0.02, -92.0), Vector3(0.3, 0.02, 12.0), false)
	logo(Vector3(0, 3.5, -99.78), 0.0, 3.2)
	label("", "PROGRAMA CAJAFUERTE · CRIOPRESERVACIÓN", Vector3(0, 2.75, -99.78), 0.0, 0.16)


func _recuperacion() -> void:
	var b := "base:recuperacion"
	for z in range(-82, -62, 4):
		box(b, "metal", Vector3(0, 2.95, float(z)), Vector3(3.2, 0.12, 0.25), false)
		for x in [-1.38, 1.38]:
			box(b, "metal", Vector3(x, 1.5, float(z)), Vector3(0.06, 3.0, 0.25), false)
	# Pasamanos y guía luminosa en el suelo hacia la sala de orientación.
	for x in [-1.32, 1.32]:
		box(b, "metal", Vector3(x, 0.95, -73.0), Vector3(0.05, 0.05, 21.0), false)
	for z in range(-82, -63, 2):
		box(b, "glow_amber", Vector3(0, 0.01, float(z)), Vector3(0.4, 0.015, 0.6), false)
	terminal("recuperacion", "terminal_danado", Vector3(1.35, 0, -70.0), -PI * 0.5, "ERR 0x4F · SIN DATOS", true)
	box(b, "glow_red", Vector3(1.38, 1.8, -70.0), Vector3(0.02, 0.08, 0.08), false)


func _enfermeria() -> void:
	var b := "base:enfermeria"
	for z in [-78.0, -74.5]:
		box(b, "furn", Vector3(-9.0, 0.45, z), Vector3(2.0, 0.15, 0.9), true)
		box(b, "metal", Vector3(-9.0, 0.2, z), Vector3(1.8, 0.4, 0.1), false)
		box(b, "fabric", Vector3(-9.8, 0.58, z), Vector3(0.4, 0.12, 0.7), false)
	box(b, "furn", Vector3(-12.6, 1.0, -76.0), Vector3(0.6, 2.0, 2.4), true)
	box(b, "glow_green", Vector3(-12.28, 1.6, -76.0), Vector3(0.02, 0.05, 0.4), false)
	terminal("enfermeria", "enfermeria", Vector3(-11.5, 0, -70.0), PI * 0.5, "ENFERMERÍA · REGISTROS")
	box(b, "fabric", Vector3(-6.0, 0.03, -71.0), Vector3(0.9, 0.04, 0.5), false, 0.6)   # manta caída: evacuación


func _orientacion() -> void:
	var b := "base:orientacion"
	# Pantalla grande en la pared este (mira al oeste) con el logotipo y el texto que cambia.
	box(b, "furn_dark", Vector3(6.75, 2.2, -56.0), Vector3(0.3, 3.0, 6.2), true)
	box(b, "screen", Vector3(6.59, 2.2, -56.0), Vector3(0.02, 2.7, 5.8), false)
	box(b, "trim", Vector3(6.6, 3.76, -56.0), Vector3(0.32, 0.08, 6.2), false)
	var lg := logo(Vector3(6.57, 2.95, -56.0), -PI * 0.5, 2.0)
	nodes["pantalla_logo"] = lg
	var l := label("pantalla", "SIN SEÑAL", Vector3(6.56, 1.55, -56.0), -PI * 0.5, 0.42, Color(0.6, 0.85, 1.0))
	l.width = 1200.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Bancos en filas mirando a la pantalla.
	for x in [-4.0, -1.0, 2.0]:
		box(b, "furn", Vector3(x, 0.45, -56.0), Vector3(0.6, 0.1, 6.0), true)
		box(b, "furn_dark", Vector3(x, 0.22, -56.0), Vector3(0.5, 0.44, 5.6), false)
	label("", "ORIENTACIÓN", Vector3(0, 3.2, -61.78), 0.0, 0.2)


func _observatorio() -> void:
	var b := "base:observatorio"
	cyl(b, "metal", Vector3(-13.0, 0.5, -56.0), 0.5, 1.0, true)
	cyl(b, "furn_dark", Vector3(-13.0, 1.6, -56.0), 0.25, 2.4, false, Vector3(0, 0, -0.9))
	cyl(b, "trim", Vector3(-12.1, 2.15, -56.0), 0.3, 0.12, false, Vector3(0, 0, -0.9))
	for z in [-59.5, -52.5]:
		box(b, "furn", Vector3(-10.0, 0.45, z), Vector3(1.6, 0.1, 0.6), true)
	label("", "OBSERVATORIO", Vector3(-7.25, 3.0, -58.6), -PI * 0.5, 0.14)


func _corridor(id: String) -> void:
	var b := "base:" + id
	var r := BaseLayout.room_rect(id)
	var z := r.position.y + 2.0
	while z < r.end.y - 1.0:
		box(b, "metal", Vector3(0, 3.1, z), Vector3(3.6, 0.14, 0.3), false)
		for x in [-1.58, 1.58]:
			box(b, "metal", Vector3(x, 1.6, z), Vector3(0.06, 3.2, 0.3), false)
		z += 5.0
	cyl(b, "metal", Vector3(-1.3, 2.85, r.get_center().y), 0.09, r.size.y - 0.5, false, Vector3(PI * 0.5, 0, 0))
	cyl(b, "trim", Vector3(1.3, 2.85, r.get_center().y), 0.06, r.size.y - 0.5, false, Vector3(PI * 0.5, 0, 0))


func _operaciones() -> void:
	var b := "base:operaciones"
	# Mesa holográfica central (mapa incompleto) y consolas en U.
	cyl(b, "furn_dark", Vector3(8.4, 0.45, -43.0), 1.6, 0.9, true)
	cyl(b, "glow_cyan", Vector3(8.4, 0.91, -43.0), 1.4, 0.02, false)
	sphere(b, "glow_amber", Vector3(8.4, 1.5, -43.0), 0.35)
	for i in 5:
		var a := -PI * 0.5 + i * PI / 4.0
		var p := Vector3(8.4, 0, -43.0) + Vector3(cos(a), 0, sin(a)) * 4.6
		if i == 2:
			continue
		terminal("operaciones", "", p, atan2(8.4 - p.x, -43.0 - p.z), "OPERACIONES", i == 4)
	box(b, "furn_dark", Vector3(14.8, 2.0, -43.0), Vector3(0.1, 1.8, 6.0), false)
	box(b, "screen", Vector3(14.74, 2.0, -43.0), Vector3(0.02, 1.6, 5.6), false)
	label("", "MAPA ESTELAR — DATOS INCOMPLETOS", Vector3(14.72, 2.0, -43.0), -PI * 0.5, 0.12, Color(0.55, 0.85, 1.0))
	terminal("operaciones", "terminal_nexus", Vector3(13.6, 0, -37.6), -PI * 0.75, "NEXUS · ACCESO PARCIAL")
	logo(Vector3(2.02, 2.6, -40.0), PI * 0.5, 1.8)


func _comunicaciones() -> void:
	var b := "base:comunicaciones"
	for z in [-48.5, -41.5]:
		box(b, "furn_dark", Vector3(20.0, 1.1, z), Vector3(6.0, 2.2, 0.8), true)
		for i in 6:
			box(b, "glow_red" if i % 3 == 0 else "glow_green", Vector3(17.6 + i * 0.9, 1.7, z + (0.41 if z < -45.0 else -0.41)), Vector3(0.06, 0.06, 0.01), false)
	terminal("comunicaciones", "consola_com", Vector3(23.6, 0, -45.0), -PI * 0.5, "COMUNICACIONES\nSIN ENLACE")


func _archivo() -> void:
	var b := "base:archivo"
	for x in [4.0, 7.0, 10.0]:
		box(b, "furn_dark", Vector3(x, 1.1, -30.5), Vector3(1.0, 2.2, 5.0), true)
		for i in 8:
			box(b, "glow_cyan" if i % 2 == 0 else "glow_amber", Vector3(x + 0.51, 0.5 + i * 0.22, -30.5 + (i % 3 - 1) * 1.2), Vector3(0.01, 0.03, 0.12), false)
	terminal("archivo", "archivo", Vector3(7.0, 0, -25.0), PI, "ARCHIVO DIGITAL\nREGISTROS DAÑADOS")


func _labs() -> void:
	var b := "base:lab_experimental"
	# Cilindro de contención roto y mesas con instrumental.
	cyl(b, "metal", Vector3(8.0, 0.15, -17.0), 1.0, 0.3, true)
	cyl(b, "glass", Vector3(8.0, 1.4, -17.0), 0.9, 2.2, true)
	cyl(b, "metal", Vector3(8.0, 2.65, -17.0), 1.0, 0.3, false)
	sphere(b, "glow_magenta", Vector3(8.0, 1.2, -17.0), 0.25)
	for z in [-20.8, -13.2]:
		box(b, "furn", Vector3(5.0, 0.9, z), Vector3(4.0, 0.08, 1.0), true)
		box(b, "furn_dark", Vector3(5.0, 0.45, z), Vector3(3.8, 0.9, 0.9), false)
	box(b, "metal", Vector3(10.0, 0.06, -14.0), Vector3(1.4, 0.12, 0.8), false, 0.5)   # tapa caída
	var b2 := "base:laboratorio"
	for z in [-20.5, -17.0, -13.5]:
		box(b2, "furn", Vector3(19.0, 0.9, z), Vector3(7.0, 0.08, 1.2), true)
		box(b2, "furn_dark", Vector3(19.0, 0.45, z), Vector3(6.8, 0.9, 1.1), false)
		cyl(b2, "metal", Vector3(17.0, 1.1, z), 0.12, 0.35, false)
		cyl(b2, "glass", Vector3(20.5, 1.05, z), 0.15, 0.25, false)


func _energia() -> void:
	var b := "base:energia"
	# Dos generadores principales (uno dañado, sin carcasa) y el cuadro de energía auxiliar.
	for x in [-11.0, -6.5]:
		cyl(b, "metal", Vector3(x, 0.2, -46.0), 1.6, 0.4, true)
		cyl(b, "wall" if x < -8.0 else "shell_dark", Vector3(x, 1.9, -46.0), 1.3, 3.0, true)
		cyl(b, "trim", Vector3(x, 3.45, -46.0), 1.35, 0.12, false)
		box(b, "glow_red" if x < -8.0 else "glow_amber", Vector3(x, 2.4, -44.68), Vector3(0.6, 0.08, 0.02), false)
	cyl(b, "metal", Vector3(-8.75, 4.0, -46.0), 0.25, 4.5, false, Vector3(0, 0, PI * 0.5))
	# Depósitos de oxígeno y control de temperatura.
	for z in [-41.0, -38.5]:
		cyl(b, "wall", Vector3(-5.0, 1.2, z), 0.8, 2.4, true)
		box(b, "glow_cyan", Vector3(-4.18, 1.6, z), Vector3(0.02, 0.4, 0.1), false)
	label("", "O₂", Vector3(-4.17, 2.1, -41.0), PI * 0.5, 0.18, Color(0.55, 0.85, 1.0))
	label("", "TEMP", Vector3(-4.17, 2.1, -38.5), PI * 0.5, 0.14, Color(0.55, 0.85, 1.0))
	# Cuadro auxiliar con palanca (la palanca es un nodo propio para animarla).
	box(b, "furn_dark", Vector3(-14.7, 1.4, -39.0), Vector3(0.4, 1.8, 1.4), true)
	box(b, "trim", Vector3(-14.48, 2.2, -39.0), Vector3(0.02, 0.1, 1.2), false)
	var lever := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.08, 0.5, 0.08)
	lever.mesh = lm
	lever.material_override = mats["trim"]
	lever.layers = Layers.bit(Layers.SHIP_INT)
	lever.position = Vector3(-14.4, 1.3, -39.0)
	lever.rotation.z = -0.6
	base.add_child(lever)
	nodes["palanca"] = lever
	var l := label("panel_aux", "ENERGÍA AUXILIAR\nDESCONECTADA", Vector3(-14.48, 1.85, -39.0), PI * 0.5, 0.08, Color(1.0, 0.55, 0.15))
	l.width = 700.0
	label("", "SALA DE ENERGÍA", Vector3(-1.98, 2.8, -40.5), -PI * 0.5, 0.14)


func _hidroponia() -> void:
	var b := "base:hidroponia"
	for x in [-13.5, -9.0, -4.5]:
		for level in 3:
			var y := 0.4 + level * 0.9
			box(b, "metal", Vector3(x, y, -24.0), Vector3(1.4, 0.06, 16.0), level == 0)
			for i in 8:
				var z := -31.0 + i * 2.0
				var alive := (i * 7 + level * 3 + int(x)) % 5 == 0
				box(b, "plant" if alive else "plant_dead", Vector3(x, y + 0.12, z), Vector3(0.9, 0.18 if alive else 0.08, 1.2), false)
			box(b, "glow_magenta", Vector3(x, y + 0.72, -24.0), Vector3(0.1, 0.03, 15.0), false)
		for z in [-31.8, -16.2]:
			box(b, "metal", Vector3(x, 1.3, z), Vector3(0.08, 2.6, 0.08), true)
	terminal("hidroponia", "cultivos", Vector3(-9.0, 0, -14.0), PI, "CULTIVOS · 11 % VIABLES")


func _hangar() -> void:
	var b := "base:hangar"
	# Marcas en el suelo (plataforma de la nave), andamios, grúa pórtico, cajas y el panel de diagnóstico.
	for s in [-1.0, 1.0]:
		box(b, "trim", Vector3(s * 22.0, 0.01, 66.0), Vector3(0.3, 0.02, 56.0), false)
	box(b, "trim", Vector3(0, 0.01, 38.0), Vector3(44.0, 0.02, 0.3), false)
	box(b, "trim", Vector3(0, 0.01, 94.0), Vector3(44.0, 0.02, 0.3), false)
	for z in [48.0, 84.0]:
		for x in [-30.0, 30.0]:
			box(b, "metal", Vector3(x, 8.0, z), Vector3(0.5, 16.0, 0.5), true)
		box(b, "metal", Vector3(0, 16.2, z), Vector3(60.5, 0.6, 0.8), false)
	box(b, "furn_dark", Vector3(-8.0, 15.4, 48.0), Vector3(2.0, 1.0, 1.4), false)
	cyl(b, "metal", Vector3(-8.0, 12.0, 48.0), 0.03, 6.0, false)
	for i in 10:
		var x := -32.0 + (i % 2) * 1.6
		var z := 40.0 + i * 1.7
		box(b, "metal" if i % 3 else "trim", Vector3(x, 0.6, z), Vector3(1.4, 1.2, 1.4), true)
	for i in 6:
		box(b, "furn_dark", Vector3(30.0 + (i % 2) * 1.8, 0.5, 85.0 + (i / 2) * 2.0), Vector3(1.6, 1.0, 1.6), true)
	terminal("hangar", "diagnostico", Vector3(26.0, 0, 50.0), -PI * 0.5, "DIAGNÓSTICO\nEXP-01 «ESPERANZA»")
	logo(Vector3(0, 13.0, 30.32), PI, 12.0)
	label("", "HANGAR PRINCIPAL · LF-01", Vector3(0, 8.8, 30.32), PI, 0.5)
	label("", "ESCLUSA · EVA →", Vector3(34.78, 3.2, 63.0), -PI * 0.5, 0.2)


## Talleres: bancos de trabajo, herramientas y estanterías (aquí está el componente lunar del NEXUS).
func _taller() -> void:
	var b := "base:taller"
	for z in [19.5, 28.5]:
		box(b, "furn_dark", Vector3(4.0, 0.45, z), Vector3(4.0, 0.9, 1.0), true)
		box(b, "metal", Vector3(4.0, 0.92, z), Vector3(4.1, 0.05, 1.1), false)
		cyl(b, "metal", Vector3(3.0, 1.05, z), 0.15, 0.25, false)
		box(b, "trim", Vector3(5.2, 1.0, z), Vector3(0.5, 0.15, 0.3), false)
	for z in [20.0, 23.0, 26.0]:
		box(b, "metal", Vector3(13.5, 1.6, z), Vector3(0.6, 3.2, 2.4), true)
		for k in 3:
			box(b, "furn" if k % 2 == 0 else "trim", Vector3(13.4, 0.6 + k * 0.9, z), Vector3(0.5, 0.35, 0.6), false)
	box(b, "furn_dark", Vector3(8.0, 2.4, 29.75), Vector3(4.0, 1.6, 0.1), false)
	label("", "MANTENIMIENTO · SECTOR RESTRINGIDO", Vector3(8.0, 2.5, 29.68), PI, 0.12, Color(1.0, 0.3, 0.2))


func _esclusa() -> void:
	var b := "base:esclusa"
	# Taquillas con trajes EVA (blancos con franja naranja), banco y panel del ciclo de presión.
	for i in 3:
		var z := 57.6 + i * 1.3
		box(b, "furn_dark", Vector3(44.5, 1.1, z), Vector3(0.6, 2.2, 1.2), true)
		if i != 1:
			cyl(b, "furn", Vector3(44.3, 1.2, z), 0.28, 1.0, false)
			sphere(b, "furn", Vector3(44.3, 1.95, z), 0.22)
			box(b, "trim", Vector3(44.3, 1.4, z), Vector3(0.3, 0.06, 0.58), false)
	nodes["traje_hueco"] = Vector3(44.3, 1.2, 58.9)
	box(b, "furn", Vector3(38.0, 0.45, 57.0), Vector3(3.0, 0.1, 0.6), true)
	box(b, "furn_dark", Vector3(44.75, 1.4, 66.6), Vector3(0.3, 1.0, 0.8), true)
	var l := label("panel_esclusa", "PRESIÓN 101 kPa\nEXTERIOR: VACÍO", Vector3(44.58, 1.45, 66.6), -PI * 0.5, 0.07, Color(1.0, 0.55, 0.15))
	l.width = 700.0
	box(b, "glow_amber", Vector3(40.0, 3.33, 63.0), Vector3(0.5, 0.06, 0.5), false)
	logo(Vector3(40.0, 2.4, 69.78), PI, 1.6)
	# Panel exterior de la esclusa (para volver a entrar) y baliza verde sobre la escotilla.
	box("base:ext", "furn_dark", Vector3(45.45, 1.3, 61.2), Vector3(0.3, 0.9, 0.6), true)
	box("base:ext", "glow_green", Vector3(45.61, 1.5, 61.2), Vector3(0.02, 0.2, 0.4), false)
	box("base:ext", "trim", Vector3(45.61, 1.05, 61.2), Vector3(0.02, 0.06, 0.5), false)
	label("", "ESCLUSA · ACCESO", Vector3(45.62, 1.9, 61.2), PI * 0.5, 0.09, Color(0.4, 1.0, 0.55), Layers.WORLD)
	box("base:ext", "glow_green", Vector3(45.5, 2.9, 63.0), Vector3(0.25, 0.12, 0.25), false)
	# Rótulo exterior de la base sobre la escotilla.
	logo(Vector3(45.62, 4.0, 63.0), PI * 0.5, 3.5, true)
	label("", "MACSPACES · BASE LUNAR LF-01", Vector3(45.62, 2.9, 63.0), PI * 0.5, 0.22, Color(1.0, 0.55, 0.15), Layers.WORLD)


## Señalización del recorrido: flechas y rótulos en las paredes de los pasillos.
func _signage() -> void:
	label("", "ORIENTACIÓN ↓", Vector3(-1.38, 2.2, -78.0), PI * 0.5, 0.14)
	label("", "ORIENTACIÓN ↓", Vector3(1.38, 2.2, -66.0), -PI * 0.5, 0.14)
	label("", "ENFERMERÍA", Vector3(-1.38, 2.6, -74.0), PI * 0.5, 0.12)
	label("", "OPERACIONES →", Vector3(-1.58, 2.4, -46.0), PI * 0.5, 0.13)
	label("", "← ENERGÍA", Vector3(1.58, 2.4, -46.0), -PI * 0.5, 0.13)
	label("", "ARCHIVO", Vector3(1.98, 2.7, -29.0), PI * 0.5, 0.12)
	label("", "HIDROPONÍA", Vector3(-1.98, 2.7, -23.0), -PI * 0.5, 0.12)
	label("", "SECTOR SUR · HANGAR ↓", Vector3(0, 2.95, -10.22), PI, 0.13)
	label("", "HANGAR ↓", Vector3(-1.58, 2.4, 20.0), PI * 0.5, 0.14)
	label("", "DESPACHO EJECUTIVO · ACCESO RESTRINGIDO", Vector3(1.58, 2.7, 9.0), -PI * 0.5, 0.09, Color(1.0, 0.25, 0.2))
	label("", "SECTOR C", Vector3(-1.58, 2.7, 14.0), PI * 0.5, 0.12)
	for z in [-40.0, -20.0, 5.0, 25.0]:
		logo(Vector3(-1.58, 2.3, z), PI * 0.5, 0.9)
