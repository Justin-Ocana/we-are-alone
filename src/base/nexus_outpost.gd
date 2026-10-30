class_name NexusOutpost
extends RefCounted
## Base procedural del NEXUS en cada mundo (ronda 12, ADR-048). Misma estética que LF-01 (paneles blancos, metal,
## naranja de MacSpaces) pero generada a partir de una semilla por cuerpo, igual en todos los equipos de la partida:
## - Planta: módulo central (con el componente del NEXUS en su pedestal) y de 5 a 8 módulos en una cuadrícula,
##   unidos por pasillos (árbol con algún anillo). Cada módulo tiene un uso (dormitorios, laboratorio, almacén,
##   energía, comunicaciones, enfermería, taller, hidroponía o comedor) y su mobiliario.
## - Todo a un mismo nivel de suelo, por encima del terreno procedural, sobre cimentaciones que bajan hasta él; la
##   entrada tiene una rampa hasta el suelo. No se aplana el terreno: el sitio se decide al llegar (lado de día).
## - Exterior: plataforma de aterrizaje, paneles solares, radiadores, mástil de comunicaciones con baliza, depósitos,
##   contenedores y farolas hasta la plataforma.
## Interior en SHIP_INT (no le da el Sol; lo iluminan sus luces), un lote por módulo (límite de 8 luces por malla);
## exterior en WORLD. Marco local como BaseLayout: X este, Y arriba, Z sur; origen en el suelo del centro.

const CELL := 18.0              ## separación entre centros de módulos (m)
const COR_W := 2.8              ## pasillo: ancho interior
const COR_H := 2.7
const DOOR_W := 2.0             ## vanos entre módulo y pasillo
const DOOR_H := 2.35
const ENTRY_W := 2.2
const ENTRY_H := 2.5
const RAMP_SLOPE_DEG := 17.0
const KINDS := ["dormitorios", "laboratorio", "almacen", "energia", "comunicaciones", "enfermeria", "taller",
	"hidroponia", "comedor"]
const KIND_NAMES := {"hub": "Núcleo NEXUS", "dormitorios": "Dormitorios", "laboratorio": "Laboratorio",
	"almacen": "Almacén", "energia": "Energía", "comunicaciones": "Comunicaciones", "enfermeria": "Enfermería",
	"taller": "Taller", "hidroponia": "Hidroponía", "comedor": "Comedor"}
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var bb: BaseBuilder
var root: Node3D
var body: StaticBody3D
var rng := RandomNumberGenerator.new()
var ground: Callable              ## (x, z) → altura local del suelo (m)
var modules: Array = []           ## [{cell, pos: Vector2 (x, z), w, d, h, kind, sides: {lado: "door"|"entry"}, low}]
var links: Array = []             ## [[i, j, low]]
var floor_y := 0.0
var core_local := Vector3.ZERO    ## pedestal del componente (centro del núcleo, al nivel del suelo interior)
var beacon_local := Vector3.ZERO  ## baliza del mástil
var entry := {}                   ## {module, side, out: Vector2, door: Vector3, foot: Vector3}
var lights: Array = []
var footprints: Array = []        ## Rect2 (x, z) ocupados (módulos, pasillos, rampa y objetos exteriores)
var site_name := ""


func build(p_root: Node3D, seed: int, p_ground: Callable, p_name: String) -> void:
	root = p_root
	ground = p_ground
	site_name = p_name
	rng.seed = seed
	body = StaticBody3D.new()
	body.name = "Colisiones"
	body.collision_layer = Layers.bit(Layers.PHYS_SHIP)
	body.collision_mask = 0
	root.add_child(body)
	bb = BaseBuilder.new()
	bb.base = root
	bb.body = body
	bb._make_materials()
	bb.mats["lamp_on"] = BaseBuilder._glow(Color(1.0, 0.96, 0.88))
	bb.mats["lamp_emerg"] = BaseBuilder._glow(BaseBuilder.EMERGENCY * 0.85)
	bb.mats["solar"] = BaseBuilder._std(Color(0.05, 0.08, 0.16), 0.2, 0.6)
	bb.mats["screen_on"] = BaseBuilder._glow(Color(0.12, 0.34, 0.46))
	# Carcasa exterior más clara que la de LF-01 (aquí no hay regolito encima).
	bb.mats["shell"] = bb._panel(Color(0.80, 0.80, 0.78), 2.4, 0.55, 0.15, 0.0, 0.3, {"exterior": 1.0, "grime": 0.45, "wear": 0.35, "bevel": 1.2})
	_layout()
	_levels()
	_choose_entry()
	for i in modules.size():
		_module(i)
	for l in links:
		_corridor(l)
	_entrance()
	_exterior()
	bb.batcher.build(root, bb.mats, func(b: String) -> int:
		return Layers.SHIP_INT if b.begins_with("int:") else Layers.WORLD)
	for b in bb.batcher.meshes_by_batch:
		for mi: MeshInstance3D in bb.batcher.meshes_by_batch[b]:
			mi.visibility_range_end = 140.0 if b.begins_with("int:") else 0.0


# --- Planta -----------------------------------------------------------------------------------

func _layout() -> void:
	var used := {Vector2i.ZERO: 0}
	modules.append(_new_module(Vector2i.ZERO, "hub"))
	var kinds: Array = KINDS.duplicate()
	for i in range(kinds.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = kinds[i]
		kinds[i] = kinds[j]
		kinds[j] = tmp
	var target := rng.randi_range(5, 8) + 1
	var guard := 0
	while modules.size() < target and guard < 400:
		guard += 1
		var from := rng.randi_range(0, modules.size() - 1)
		var c: Vector2i = modules[from]["cell"] + DIRS[rng.randi_range(0, 3)]
		if used.has(c) or absi(c.x) > 3 or absi(c.y) > 3:
			continue
		used[c] = modules.size()
		modules.append(_new_module(c, str(kinds[(modules.size() - 1) % kinds.size()])))
		_link(from, modules.size() - 1)
	# Algún pasillo más entre vecinos que no están unidos (la planta deja de ser un árbol).
	for c: Vector2i in used:
		for dv: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			var o: Vector2i = c + dv
			if used.has(o) and not _linked(int(used[c]), int(used[o])) and rng.randf() < 0.3:
				_link(int(used[c]), int(used[o]))


func _new_module(cell: Vector2i, kind: String) -> Dictionary:
	var hub := kind == "hub"
	var w := 13.0 if hub else snappedf(rng.randf_range(7.5, 11.0), 0.5)
	var d := 13.0 if hub else snappedf(rng.randf_range(7.5, 11.0), 0.5)
	return {"cell": cell, "pos": Vector2(cell.x * CELL, cell.y * CELL), "w": w, "d": d,
		"h": 4.6 if hub else snappedf(rng.randf_range(3.3, 3.9), 0.1), "kind": kind, "sides": {}, "low": 0.0,
		"emergency": not hub and rng.randf() < 0.35}


func _link(a: int, b: int) -> void:
	var ca: Vector2i = modules[a]["cell"]
	var cb: Vector2i = modules[b]["cell"]
	var dv := cb - ca
	modules[a]["sides"][_side_of(dv)] = "door"
	modules[b]["sides"][_side_of(-dv)] = "door"
	links.append([a, b, 0.0])


func _linked(a: int, b: int) -> bool:
	for l in links:
		if (int(l[0]) == a and int(l[1]) == b) or (int(l[0]) == b and int(l[1]) == a):
			return true
	return false


static func _side_of(dv: Vector2i) -> String:
	if dv.x > 0:
		return "e"
	if dv.x < 0:
		return "w"
	return "s" if dv.y > 0 else "n"


static func _side_vec(side: String) -> Vector2:
	match side:
		"e":
			return Vector2(1, 0)
		"w":
			return Vector2(-1, 0)
		"s":
			return Vector2(0, 1)
	return Vector2(0, -1)


## Nivel del suelo interior: por encima del punto más alto del terreno bajo toda la planta.
func _levels() -> void:
	var hi := -INF
	for m: Dictionary in modules:
		var r := _rect(m, 1.0)
		var s := _sample(r)
		hi = maxf(hi, s.y)
		m["low"] = s.x
		footprints.append(_rect(m, 1.5))
	for l in links:
		var r := _corridor_rect(l, 0.6)
		var s := _sample(r)
		hi = maxf(hi, s.y)
		l[2] = s.x
		footprints.append(r)
	floor_y = hi + 0.35
	var hub: Dictionary = modules[0]
	core_local = Vector3(hub["pos"].x, floor_y, hub["pos"].y)


func _rect(m: Dictionary, margin: float) -> Rect2:
	var p: Vector2 = m["pos"]
	return Rect2(p.x - m["w"] * 0.5 - margin, p.y - m["d"] * 0.5 - margin, m["w"] + margin * 2.0, m["d"] + margin * 2.0)


func _corridor_rect(l: Array, margin: float) -> Rect2:
	var a: Dictionary = modules[int(l[0])]
	var b: Dictionary = modules[int(l[1])]
	var pa: Vector2 = a["pos"]
	var pb: Vector2 = b["pos"]
	var lo := Vector2(minf(pa.x, pb.x), minf(pa.y, pb.y))
	var hi := Vector2(maxf(pa.x, pb.x), maxf(pa.y, pb.y))
	var half := COR_W * 0.5 + 0.3 + margin
	if absf(pa.y - pb.y) < 0.1:
		return Rect2(lo.x, lo.y - half, hi.x - lo.x, half * 2.0)
	return Rect2(lo.x - half, lo.y, half * 2.0, hi.y - lo.y)


## (mínimo, máximo) del terreno en el rectángulo (muestras cada ~2,5 m).
func _sample(r: Rect2) -> Vector2:
	var lo := INF
	var hi := -INF
	var nx := maxi(2, int(ceil(r.size.x / 2.5)) + 1)
	var nz := maxi(2, int(ceil(r.size.y / 2.5)) + 1)
	for i in nx:
		for j in nz:
			var h: float = ground.call(r.position.x + r.size.x * float(i) / float(nx - 1),
				r.position.y + r.size.y * float(j) / float(nz - 1))
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return Vector2(lo, hi)


## Entrada: un lado libre que mire a una celda vacía (preferencia: el núcleo, después módulos del borde).
func _choose_entry() -> void:
	var used := {}
	for m: Dictionary in modules:
		used[m["cell"]] = true
	var options: Array = []
	for i in modules.size():
		var m: Dictionary = modules[i]
		for side: String in ["s", "e", "w", "n"]:
			if m["sides"].has(side):
				continue
			var dv := _side_vec(side)
			var c: Vector2i = m["cell"] + Vector2i(int(dv.x), int(dv.y))
			var clear := 0
			for k in range(1, 4):
				if used.has(m["cell"] + Vector2i(int(dv.x), int(dv.y)) * k):
					break
				clear += 1
			if used.has(c):
				continue
			options.append([i, side, clear * 2 + (3 if i == 0 else 0)])
	options.sort_custom(func(x: Array, y: Array) -> bool: return int(x[2]) > int(y[2]))
	var pick: Array = options[0] if not options.is_empty() else [0, "s", 0]
	var m: Dictionary = modules[int(pick[0])]
	var side := str(pick[1])
	m["sides"][side] = "entry"
	var out := _side_vec(side)
	var p: Vector2 = m["pos"]
	var edge: Vector2 = p + out * (float(m["w"] if absf(out.x) > 0.5 else m["d"]) * 0.5)
	entry = {"module": int(pick[0]), "side": side, "out": out, "edge": edge}


# --- Primitivas -----------------------------------------------------------------------------------

func _box(batch: String, mat: String, xf: Transform3D, size: Vector3, collide := false) -> void:
	bb.batcher.box(batch, mat, xf, size)
	if collide:
		_shape(xf, size)


func _boxp(batch: String, mat: String, center: Vector3, size: Vector3, collide := false) -> void:
	_box(batch, mat, Transform3D(Basis(), center), size, collide)


func _shape(xf: Transform3D, size: Vector3) -> void:
	var s := BoxShape3D.new()
	s.size = size
	var cs := CollisionShape3D.new()
	cs.shape = s
	cs.transform = xf
	body.add_child(cs)


func _cyl(batch: String, mat: String, center: Vector3, radius: float, height: float, rot := Vector3.ZERO,
		collide := false, segments := 14) -> void:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	var xf := Transform3D(Basis.from_euler(rot), center)
	bb.batcher.primitive(batch, mat, c, xf)
	if collide:
		var s := CylinderShape3D.new()
		s.radius = radius
		s.height = height
		var cs := CollisionShape3D.new()
		cs.shape = s
		cs.transform = xf
		body.add_child(cs)


func _sphere(batch: String, mat: String, center: Vector3, radius: float, scl := Vector3.ONE, hemi := false) -> void:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * (1.0 if hemi else 2.0)
	s.is_hemisphere = hemi
	s.radial_segments = 20
	s.rings = 8
	bb.batcher.primitive(batch, mat, s, Transform3D(Basis().scaled(scl), center))


func _omni(pos: Vector3, rng_m: float, energy: float, col: Color, interior := true) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.omni_range = rng_m
	l.light_energy = energy
	l.light_color = col
	l.omni_attenuation = 1.2
	l.shadow_enabled = false
	l.light_cull_mask = (Layers.interior_light_mask() | Layers.bits([Layers.BODY, Layers.HEAD, Layers.HEAD_P2])) if interior \
		else Layers.bits([Layers.WORLD, Layers.BODY, Layers.HEAD, Layers.HEAD_P2, Layers.SHIP_EXT])
	root.add_child(l)
	lights.append(l)
	return l


# --- Módulos ----------------------------------------------------------------------------------

func _batch(i: int) -> String:
	return "int:nx%d" % i


func _module(i: int) -> void:
	var m: Dictionary = modules[i]
	var b := _batch(i)
	var p: Vector2 = m["pos"]
	var w: float = m["w"]
	var d: float = m["d"]
	var h: float = m["h"]
	var c := Vector3(p.x, floor_y, p.y)
	# Suelo (con colisión), techo, cubierta exterior y cimentación hasta el terreno.
	_boxp(b, "floor", c + Vector3(0, -0.1, 0), Vector3(w, 0.2, d), true)
	_boxp(b, "ceiling", c + Vector3(0, h + 0.05, 0), Vector3(w, 0.1, d))
	_boxp("nx:ext", "shell", c + Vector3(0, h + 0.3, 0), Vector3(w + 0.44, 0.3, d + 0.44), true)
	_stilts(p, w, d)
	# Zócalo naranja a ras del terreno y remate superior.
	_boxp("nx:ext", "trim", c + Vector3(0, h + 0.47, 0), Vector3(w + 0.5, 0.06, d + 0.5))
	for side: String in ["n", "s", "e", "w"]:
		_wall(i, side)
	_roof(i)
	# Plafón y luz de la sala.
	var lamp := "lamp_emerg" if m["emergency"] else "lamp_on"
	var lw := minf(w, d) * 0.5
	_boxp(b, lamp, c + Vector3(0, h - 0.02, 0), Vector3(lw, 0.04, 0.5))
	_boxp(b, lamp, c + Vector3(0, h - 0.02, 0), Vector3(0.5, 0.04, lw))
	var col := Color(1.0, 0.5, 0.2) if m["emergency"] else Color(1.0, 0.95, 0.86)
	_omni(c + Vector3(0, h - 0.5, 0), maxf(w, d) * 1.1, 0.95 if m["emergency"] else 1.8, col)
	# Cartel con el nombre de la sala sobre una puerta.
	var lab_side := ""
	for side: String in ["n", "s", "e", "w"]:
		if m["sides"].get(side, "") != "":
			lab_side = side
			break
	if lab_side != "":
		var n := _side_vec(lab_side)
		var off := Vector3(n.x * (w * 0.5 - 0.12), DOOR_H + 0.45, n.y * (d * 0.5 - 0.12))
		bb.label("", str(KIND_NAMES.get(m["kind"], "")).to_upper(), c + off, atan2(-n.x, -n.y), 0.55)
	if m["kind"] == "hub":
		_hub(i)
	else:
		_furnish(i)


## Tabique de un lado: interior (paneles, zócalo, franja) y carcasa exterior, con el vano de la puerta si lo hay.
func _wall(i: int, side: String) -> void:
	var m: Dictionary = modules[i]
	var b := _batch(i)
	var p: Vector2 = m["pos"]
	var w: float = m["w"]
	var d: float = m["d"]
	var h: float = m["h"]
	var along_x := side == "n" or side == "s"
	var length := w if along_x else d
	var n := _side_vec(side)
	var half_depth := (d if along_x else w) * 0.5
	var kind := str(m["sides"].get(side, ""))
	var hole_w := 0.0
	var hole_h := 0.0
	if kind == "door":
		hole_w = DOOR_W
		hole_h = DOOR_H
	elif kind == "entry":
		hole_w = ENTRY_W
		hole_h = ENTRY_H
	var spans: Array = []
	if hole_w > 0.0:
		spans = [[-length * 0.5, -hole_w * 0.5, 0.0, h], [hole_w * 0.5, length * 0.5, 0.0, h],
			[-hole_w * 0.5, hole_w * 0.5, hole_h, h]]
	else:
		spans = [[-length * 0.5, length * 0.5, 0.0, h]]
	for s: Array in spans:
		var a0: float = s[0]
		var a1: float = s[1]
		var y0: float = s[2]
		var y1: float = s[3]
		var mid := (a0 + a1) * 0.5
		var seg_len := a1 - a0
		var hh := y1 - y0
		# Interior (cara hacia dentro), carcasa (cara hacia fuera, sube hasta la cubierta) y colisión.
		_wall_piece(b, "wall", p, along_x, n, half_depth - 0.04, mid, seg_len, floor_y + y0, hh, 0.08)
		var ext_len := seg_len + (0.44 if y0 == 0.0 and (absf(a0) > length * 0.5 - 0.01 or absf(a1) > length * 0.5 - 0.01) else 0.0)
		var ext_mid := mid + (0.22 * signf(mid) if ext_len > seg_len else 0.0)
		var ext_h := hh + (0.15 if y1 >= h else 0.0)
		_wall_piece("nx:ext", "shell", p, along_x, n, half_depth + 0.08, ext_mid, ext_len, floor_y + y0, ext_h, 0.16)
		var cxf := _wall_xf(p, along_x, n, half_depth + 0.02, mid, floor_y + y0 + hh * 0.5)
		_shape(cxf, Vector3(seg_len, hh, 0.26) if along_x else Vector3(0.26, hh, seg_len))
		if y0 == 0.0:
			_wall_piece(b, "wall_dark", p, along_x, n, half_depth - 0.09, mid, seg_len, floor_y, 0.18, 0.02)
			_wall_piece(b, "trim", p, along_x, n, half_depth - 0.09, mid, seg_len, floor_y + 1.05, 0.07, 0.02)
	if hole_w > 0.0:
		# Marco del vano (naranja dentro, oscuro fuera).
		for sx: float in [-1.0, 1.0]:
			_wall_piece(b, "trim", p, along_x, n, half_depth - 0.06, sx * (hole_w * 0.5 + 0.06), 0.12, floor_y, hole_h, 0.14)
			_wall_piece("nx:ext", "shell_dark", p, along_x, n, half_depth + 0.18, sx * (hole_w * 0.5 + 0.1), 0.2, floor_y, hole_h + 0.1, 0.2)
		_wall_piece(b, "trim", p, along_x, n, half_depth - 0.06, 0.0, hole_w + 0.24, floor_y + hole_h, 0.12, 0.14)
	else:
		# Costillas verticales de la carcasa en los lados sin puerta.
		var k := int(length / 2.6)
		for j in range(1, k + 1):
			var t := -length * 0.5 + length * float(j) / float(k + 1)
			_wall_piece("nx:ext", "shell_dark", p, along_x, n, half_depth + 0.2, t, 0.18, floor_y, h + 0.3, 0.1)


func _wall_xf(p: Vector2, along_x: bool, n: Vector2, depth: float, t: float, y: float) -> Transform3D:
	var pos := Vector3(p.x + n.x * depth + (t if along_x else 0.0), y, p.y + n.y * depth + (0.0 if along_x else t))
	return Transform3D(Basis(), pos)


func _wall_piece(b: String, mat: String, p: Vector2, along_x: bool, n: Vector2, depth: float, t: float, seg_len: float,
		y0: float, hh: float, thick: float) -> void:
	var xf := _wall_xf(p, along_x, n, depth, t, y0 + hh * 0.5)
	_box(b, mat, xf, Vector3(seg_len, hh, thick) if along_x else Vector3(thick, hh, seg_len))


## Apoyos: zócalo bajo el suelo y pilotes hasta el terreno (cada ~4 m), con su zapata. Bajo los módulos queda
## hueco donde el terreno baja (como una base sobre pilotes, sin bloques macizos).
func _stilts(c: Vector2, w: float, d: float) -> void:
	_boxp("nx:ext", "shell_dark", Vector3(c.x, floor_y - 0.45, c.y), Vector3(w + 0.3, 0.5, d + 0.3), true)
	_boxp("nx:ext", "trim", Vector3(c.x, floor_y - 0.68, c.y), Vector3(w + 0.34, 0.05, d + 0.34))
	var nx := maxi(2, int(ceil(w / 4.0)) + 1)
	var nz := maxi(2, int(ceil(d / 4.0)) + 1)
	for i in nx:
		for j in nz:
			var q := c + Vector2(-w * 0.5 + 0.4 + (w - 0.8) * float(i) / float(nx - 1), -d * 0.5 + 0.4 + (d - 0.8) * float(j) / float(nz - 1))
			var g := float(ground.call(q.x, q.y))
			var top := floor_y - 0.7
			if top - g < 0.25:
				continue
			var bot := g - 0.4
			_cyl("nx:ext", "metal", Vector3(q.x, (top + bot) * 0.5, q.y), 0.16, top - bot, Vector3.ZERO, true, 8)
			_boxp("nx:ext", "shell_dark", Vector3(q.x, g + 0.05, q.y), Vector3(0.8, 0.3, 0.8))


## Cubierta: rejillas, equipos y, en el núcleo, una cúpula con lucernario.
func _roof(i: int) -> void:
	var m: Dictionary = modules[i]
	var p: Vector2 = m["pos"]
	var top := floor_y + float(m["h"]) + 0.45
	if m["kind"] == "hub":
		_sphere("nx:ext", "shell", Vector3(p.x, top, p.y), 1.0, Vector3(4.6, 2.4, 4.6), true)
		_cyl("nx:ext", "glow_cyan", Vector3(p.x, top + 0.05, p.y), 4.75, 0.1, Vector3.ZERO, false, 24)
		_cyl("nx:ext", "shell_dark", Vector3(p.x, top + 2.45, p.y), 0.7, 0.3)
		return
	var n := rng.randi_range(1, 3)
	for j in n:
		var off := Vector2(rng.randf_range(-0.3, 0.3) * m["w"], rng.randf_range(-0.3, 0.3) * m["d"])
		var sz := Vector3(rng.randf_range(0.8, 1.8), rng.randf_range(0.4, 1.0), rng.randf_range(0.8, 1.8))
		_boxp("nx:ext", "metal" if rng.randf() < 0.5 else "shell_dark", Vector3(p.x + off.x, top + sz.y * 0.5, p.y + off.y), sz)
	if rng.randf() < 0.6:
		_cyl("nx:ext", "metal", Vector3(p.x - m["w"] * 0.3, top + 0.6, p.y + m["d"] * 0.3), 0.18, 1.2)


# --- Núcleo y mobiliario ------------------------------------------------------------------------

func _hub(i: int) -> void:
	var m: Dictionary = modules[i]
	var b := _batch(i)
	var p: Vector2 = m["pos"]
	var c := Vector3(p.x, floor_y, p.y)
	# Anillo en el suelo alrededor del pedestal y consolas en diagonal (los ejes son los pasos a las puertas).
	_cyl(b, "trim", c + Vector3(0, 0.012, 0), 1.6, 0.02, Vector3.ZERO, false, 24)
	_cyl(b, "floor", c + Vector3(0, 0.02, 0), 1.45, 0.02, Vector3.ZERO, false, 24)
	for k in 4:
		var ang := PI * 0.25 + PI * 0.5 * float(k)
		var dir := Vector3(sin(ang), 0, cos(ang))
		var pos := c + dir * 4.2
		var yaw := atan2(dir.x, dir.z)
		var basis := Basis(Vector3.UP, yaw)
		_box(b, "furn_dark", Transform3D(basis, pos + Vector3(0, 0.45, 0)), Vector3(1.6, 0.9, 0.7), true)
		var sb := basis * Basis(Vector3.RIGHT, deg_to_rad(-25.0))
		_box(b, "screen_on", Transform3D(sb, pos + Vector3(0, 1.25, 0) + dir * 0.1), Vector3(1.1, 0.55, 0.05))
		_box(b, "glow_cyan", Transform3D(basis, pos + Vector3(0, 0.92, 0) - dir * 0.36), Vector3(1.5, 0.03, 0.03))
	# Logotipo y nombre de la instalación en una pared sin puerta.
	for side: String in ["n", "w", "e", "s"]:
		if m["sides"].has(side):
			continue
		var n := _side_vec(side)
		var depth: float = float(m["d"] if absf(n.y) > 0.5 else m["w"]) * 0.5 - 0.1
		var pos := c + Vector3(n.x * depth, 2.4, n.y * depth)
		var yaw := atan2(-n.x, -n.y)
		bb.logo(pos, yaw, 3.2)
		bb.label("", "MACSPACES · " + site_name.to_upper(), pos + Vector3(0, 1.45, 0) - Vector3(n.x, 0, n.y) * 0.02, yaw, 0.5)
		break
	_omni(c + Vector3(0, 3.2, 0), 7.0, 0.8, Color(0.5, 0.85, 1.0))


## Mobiliario según el uso, contra las paredes (dejando libres los vanos) y en el centro.
func _furnish(i: int) -> void:
	var m: Dictionary = modules[i]
	var kind := str(m["kind"])
	for side: String in ["n", "s", "e", "w"]:
		var along_x := side == "n" or side == "s"
		var length: float = m["w"] if along_x else m["d"]
		var spans: Array = []
		var hole := 0.0
		if m["sides"].has(side):
			hole = (ENTRY_W if m["sides"][side] == "entry" else DOOR_W) * 0.5 + 0.7
			spans = [[-length * 0.5 + 0.25, -hole], [hole, length * 0.5 - 0.25]]
		else:
			spans = [[-length * 0.5 + 0.25, length * 0.5 - 0.25]]
		for s: Array in spans:
			var t: float = s[0]
			var t1: float = s[1]
			while t1 - t > 0.6:
				var used := _wall_item(i, side, kind, t, t1 - t)
				if used <= 0.0:
					break
				t += used + 0.15
	_center_props(i)


## Coloca un mueble contra la pared desde `t` (a lo largo) con `room` m libres; devuelve el ancho usado (0 si nada).
func _wall_item(i: int, side: String, kind: String, t: float, room: float) -> float:
	var m: Dictionary = modules[i]
	var b := _batch(i)
	var opts: Array = []
	match kind:
		"dormitorios":
			opts = [["litera", 2.1, 0.95], ["taquilla", 0.6, 0.55]]
		"laboratorio":
			opts = [["banco", 2.2, 0.8], ["armario", 1.0, 0.6]]
		"almacen":
			opts = [["estanteria", 2.0, 0.6], ["cajas", 1.2, 1.0]]
		"energia":
			opts = [["baterias", 1.0, 0.7]]
		"comunicaciones":
			opts = [["consola", 1.6, 0.75], ["rack", 0.7, 0.8]]
		"enfermeria":
			opts = [["cama", 2.0, 0.95], ["armario", 1.0, 0.6]]
		"taller":
			opts = [["banco", 2.2, 0.8], ["herramientas", 1.6, 0.15]]
		"hidroponia":
			opts = [["jardinera", 2.2, 0.7]]
		"comedor":
			opts = [["barra", 2.4, 0.7], ["armario", 1.0, 0.6]]
	var fits: Array = []
	for o: Array in opts:
		if float(o[1]) <= room:
			fits.append(o)
	if fits.is_empty():
		return 0.0
	var o: Array = fits[rng.randi_range(0, fits.size() - 1)]
	var wdt: float = o[1]
	var dep: float = o[2]
	var mid := t + wdt * 0.5
	var p: Vector2 = m["pos"]
	var along_x := side == "n" or side == "s"
	var n := _side_vec(side)
	var half_depth: float = (m["d"] if along_x else m["w"]) * 0.5 - 0.08
	var base_pos := Vector3(p.x + n.x * (half_depth - dep * 0.5) + (mid if along_x else 0.0), floor_y,
		p.y + n.y * (half_depth - dep * 0.5) + (0.0 if along_x else mid))
	var basis := Basis(Vector3.UP, atan2(-n.x, -n.y))    # local +Z mira al centro de la sala
	var put := func(mat: String, off: Vector3, size: Vector3, collide: bool) -> void:
		_box(b, mat, Transform3D(basis, base_pos + basis * off), size, collide)
	match str(o[0]):
		"litera":
			put.call("furn", Vector3(0, 0.25, 0), Vector3(wdt, 0.5, dep), true)
			put.call("fabric", Vector3(0, 0.56, 0), Vector3(wdt - 0.1, 0.12, dep - 0.1), false)
			put.call("furn", Vector3(0, 1.45, 0), Vector3(wdt, 0.12, dep), true)
			put.call("fabric", Vector3(0, 1.57, 0), Vector3(wdt - 0.1, 0.12, dep - 0.1), false)
			for sx: float in [-1.0, 1.0]:
				put.call("metal", Vector3(sx * (wdt * 0.5 - 0.04), 0.95, dep * 0.5 - 0.04), Vector3(0.06, 1.9, 0.06), false)
		"taquilla", "armario":
			var hh := 2.0 if str(o[0]) == "taquilla" else 1.8
			put.call("furn_dark" if str(o[0]) == "taquilla" else "furn", Vector3(0, hh * 0.5, 0), Vector3(wdt - 0.04, hh, dep), true)
			put.call("metal", Vector3(0, hh * 0.55, dep * 0.5 + 0.01), Vector3(0.04, 0.3, 0.02), false)
		"banco":
			put.call("furn" if kind == "laboratorio" else "metal", Vector3(0, 0.45, 0), Vector3(wdt, 0.9, dep), true)
			put.call("furn_dark", Vector3(0, 0.92, 0), Vector3(wdt + 0.04, 0.04, dep + 0.04), false)
			if kind == "laboratorio":
				put.call("screen_on", Vector3(0, 1.45, -dep * 0.5 + 0.08), Vector3(1.0, 0.6, 0.04), false)
				for k in 3:
					put.call("frost", Vector3(-0.7 + 0.35 * k, 1.1, 0.1), Vector3(0.12, 0.32, 0.12), false)
			else:
				put.call("wall_dark", Vector3(0, 1.5, -dep * 0.5 + 0.03), Vector3(wdt, 0.9, 0.04), false)
		"estanteria":
			for k in 4:
				put.call("metal", Vector3(0, 0.15 + 0.6 * k, 0), Vector3(wdt, 0.05, dep), false)
				if rng.randf() < 0.75:
					var cw := rng.randf_range(0.4, 0.9)
					put.call("furn_dark" if rng.randf() < 0.5 else "trim", Vector3(rng.randf_range(-0.4, 0.4), 0.36 + 0.6 * k, 0), Vector3(cw, 0.38, dep - 0.1), false)
			_box(b, "metal", Transform3D(basis, base_pos + basis * Vector3(0, 1.1, 0)), Vector3(wdt, 2.2, dep), false)
			_shape(Transform3D(basis, base_pos + basis * Vector3(0, 1.1, 0)), Vector3(wdt, 2.2, dep))
		"cajas":
			var hh := 0.0
			for k in rng.randi_range(1, 3):
				var sz := rng.randf_range(0.7, 1.0)
				put.call("furn_dark" if k % 2 == 0 else "trim", Vector3(rng.randf_range(-0.1, 0.1), hh + sz * 0.5, 0), Vector3(sz, sz, sz), true)
				hh += sz
		"baterias":
			put.call("furn_dark", Vector3(0, 0.95, 0), Vector3(wdt - 0.06, 1.9, dep), true)
			for k in 4:
				put.call("glow_green" if rng.randf() < 0.7 else "glow_red", Vector3(-0.3 + 0.2 * k, 1.6, dep * 0.5 + 0.01), Vector3(0.08, 0.04, 0.02), false)
		"consola":
			put.call("furn_dark", Vector3(0, 0.42, 0), Vector3(wdt, 0.85, dep), true)
			var sb := Basis(Vector3.RIGHT, deg_to_rad(-20.0))
			_box(b, "screen_on", Transform3D(basis * sb, base_pos + basis * Vector3(0, 1.25, -dep * 0.3)), Vector3(wdt - 0.2, 0.65, 0.05))
			put.call("glow_cyan", Vector3(0, 0.87, dep * 0.3), Vector3(wdt - 0.3, 0.02, 0.15), false)
		"rack":
			put.call("furn_dark", Vector3(0, 1.0, 0), Vector3(wdt - 0.04, 2.0, dep), true)
			for k in 6:
				put.call("glow_green" if k % 3 != 0 else "glow_amber", Vector3(0.2, 0.4 + 0.27 * k, dep * 0.5 + 0.01), Vector3(0.05, 0.03, 0.02), false)
		"cama":
			put.call("furn", Vector3(0, 0.3, 0), Vector3(wdt, 0.6, dep), true)
			put.call("fabric", Vector3(0, 0.66, 0), Vector3(wdt - 0.1, 0.12, dep - 0.1), false)
			put.call("glow_red", Vector3(0, 1.6, -dep * 0.5 + 0.02), Vector3(0.3, 0.08, 0.02), false)
			put.call("glow_red", Vector3(0, 1.6, -dep * 0.5 + 0.02), Vector3(0.08, 0.3, 0.02), false)
		"herramientas":
			put.call("wall_dark", Vector3(0, 1.4, 0), Vector3(wdt, 1.2, 0.05), false)
			for k in 5:
				put.call("metal", Vector3(-0.6 + 0.3 * k, 1.4 + rng.randf_range(-0.3, 0.3), 0.06), Vector3(0.05, rng.randf_range(0.2, 0.5), 0.04), false)
		"jardinera":
			put.call("metal", Vector3(0, 0.4, 0), Vector3(wdt, 0.8, dep), true)
			put.call("plant" if rng.randf() < 0.4 else "plant_dead", Vector3(0, 0.88, 0), Vector3(wdt - 0.1, 0.18, dep - 0.1), false)
			put.call("glow_magenta", Vector3(0, 2.2, 0), Vector3(wdt - 0.2, 0.04, 0.12), false)
			var hang: float = float(m["h"]) - 2.2
			for sx: float in [-1.0, 1.0]:
				put.call("metal", Vector3(sx * (wdt * 0.5 - 0.25), 2.2 + hang * 0.5, 0), Vector3(0.03, hang, 0.03), false)
		"barra":
			put.call("furn", Vector3(0, 0.5, 0), Vector3(wdt, 1.0, dep), true)
			put.call("furn_dark", Vector3(0, 1.02, 0), Vector3(wdt + 0.04, 0.04, dep + 0.04), false)
	return wdt


func _center_props(i: int) -> void:
	var m: Dictionary = modules[i]
	var b := _batch(i)
	var p: Vector2 = m["pos"]
	var c := Vector3(p.x, floor_y, p.y)
	match str(m["kind"]):
		"almacen":
			for k in rng.randi_range(2, 4):
				var off := Vector3(rng.randf_range(-1.2, 1.2), 0, rng.randf_range(-1.2, 1.2))
				var sz := rng.randf_range(0.8, 1.2)
				_boxp(b, "trim" if k % 2 == 0 else "furn_dark", c + off + Vector3(0, sz * 0.5, 0), Vector3(sz, sz, sz), true)
		"energia":
			_cyl(b, "metal", c + Vector3(0, 0.15, 0), 1.3, 0.3, Vector3.ZERO, true, 20)
			_cyl(b, "furn_dark", c + Vector3(0, 1.2, 0), 0.9, 1.8, Vector3.ZERO, true, 20)
			_cyl(b, "glow_amber", c + Vector3(0, 1.2, 0), 0.92, 0.12, Vector3.ZERO, false, 20)
			_cyl(b, "metal", c + Vector3(0, 2.3, 0), 0.3, 0.4)
		"taller":
			_boxp(b, "shell", c + Vector3(0, 0.8, 0), Vector3(2.0, 0.7, 3.0), true)
			_boxp(b, "glass", c + Vector3(0, 1.4, 0.5), Vector3(1.6, 0.5, 1.2))
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					_cyl(b, "fabric", c + Vector3(sx * 1.1, 0.4, sz * 1.0), 0.4, 0.3, Vector3(0, 0, PI * 0.5))
		"hidroponia":
			for k in 2:
				var z := -0.9 + 1.8 * k
				_boxp(b, "metal", c + Vector3(0, 0.45, z), Vector3(minf(m["w"] - 3.0, 4.0), 0.9, 0.7), true)
				_boxp(b, "plant" if rng.randf() < 0.4 else "plant_dead", c + Vector3(0, 0.95, z), Vector3(minf(m["w"] - 3.0, 4.0) - 0.1, 0.2, 0.6))
		"comedor":
			_boxp(b, "furn", c + Vector3(0, 0.75, 0), Vector3(2.4, 0.06, 1.0), true)
			_boxp(b, "metal", c + Vector3(0, 0.37, 0), Vector3(0.2, 0.74, 0.2))
			for sz: float in [-1.0, 1.0]:
				_boxp(b, "furn_dark", c + Vector3(0, 0.23, sz * 0.85), Vector3(2.2, 0.46, 0.4), true)
		"laboratorio":
			_boxp(b, "furn", c + Vector3(0, 0.45, 0), Vector3(1.0, 0.9, 2.0), true)
			_boxp(b, "frost", c + Vector3(0, 1.2, 0), Vector3(0.6, 0.6, 0.6))


# --- Pasillos ---------------------------------------------------------------------------------

func _corridor(l: Array) -> void:
	var ia := int(l[0])
	var a: Dictionary = modules[ia]
	var bm: Dictionary = modules[int(l[1])]
	var b := _batch(ia)
	var pa: Vector2 = a["pos"]
	var pb: Vector2 = bm["pos"]
	var along_x := absf(pa.y - pb.y) < 0.1
	var dir := (pb - pa).normalized()
	var start: Vector2 = pa + dir * (float(a["w"] if along_x else a["d"]) * 0.5 + 0.12)
	var end: Vector2 = pb - dir * (float(bm["w"] if along_x else bm["d"]) * 0.5 + 0.12)
	var mid := (start + end) * 0.5
	var seg_len := start.distance_to(end)
	var c := Vector3(mid.x, floor_y, mid.y)
	var sz := func(l_along: float, h: float, across: float) -> Vector3:
		return Vector3(l_along, h, across) if along_x else Vector3(across, h, l_along)
	var side := func(off: float) -> Vector3:
		return Vector3(0, 0, off) if along_x else Vector3(off, 0, 0)
	_boxp(b, "floor", c + Vector3(0, -0.1, 0), sz.call(seg_len + 0.3, 0.2, COR_W), true)
	_boxp(b, "ceiling", c + Vector3(0, COR_H + 0.05, 0), sz.call(seg_len + 0.3, 0.1, COR_W))
	_boxp(b, "lamp_on" if not a["emergency"] else "lamp_emerg", c + Vector3(0, COR_H - 0.02, 0), sz.call(seg_len - 0.4, 0.03, 0.3))
	_boxp("nx:ext", "shell", c + Vector3(0, COR_H + 0.28, 0), sz.call(seg_len + 0.3, 0.3, COR_W + 0.5), true)
	for sgn: float in [-1.0, 1.0]:
		_boxp(b, "wall", c + side.call(sgn * (COR_W * 0.5 + 0.04)) + Vector3(0, COR_H * 0.5, 0), sz.call(seg_len + 0.3, COR_H, 0.08))
		_boxp(b, "trim", c + side.call(sgn * (COR_W * 0.5 - 0.01)) + Vector3(0, 1.05, 0), sz.call(seg_len + 0.3, 0.07, 0.02))
		_boxp(b, "wall_dark", c + side.call(sgn * (COR_W * 0.5 - 0.01)) + Vector3(0, 0.09, 0), sz.call(seg_len + 0.3, 0.18, 0.02))
		_boxp("nx:ext", "shell", c + side.call(sgn * (COR_W * 0.5 + 0.17)) + Vector3(0, (COR_H + 0.15) * 0.5, 0), sz.call(seg_len + 0.3, COR_H + 0.15, 0.18))
		_shape(Transform3D(Basis(), c + side.call(sgn * (COR_W * 0.5 + 0.12)) + Vector3(0, COR_H * 0.5, 0)), sz.call(seg_len + 0.3, COR_H, 0.26))
	# Costillas exteriores cada ~2 m y cimentación.
	var k := maxi(1, int(seg_len / 2.0))
	for j in k + 1:
		var t := -seg_len * 0.5 + seg_len * float(j) / float(k)
		var at := c + (Vector3(t, 0, 0) if along_x else Vector3(0, 0, t))
		_boxp("nx:ext", "shell_dark", at + Vector3(0, COR_H + 0.46, 0), sz.call(0.2, 0.08, COR_W + 0.7))
		for sgn: float in [-1.0, 1.0]:
			_boxp("nx:ext", "shell_dark", at + side.call(sgn * (COR_W * 0.5 + 0.3)) + Vector3(0, (COR_H + 0.5) * 0.5, 0), sz.call(0.2, COR_H + 0.5, 0.08))
	_stilts(mid, seg_len + 0.3 if along_x else COR_W + 0.4, COR_W + 0.4 if along_x else seg_len + 0.3)
	if seg_len > 3.0:
		_omni(c + Vector3(0, COR_H - 0.4, 0), seg_len * 0.6 + 2.0, 0.55, Color(1.0, 0.92, 0.82))


# --- Entrada ----------------------------------------------------------------------------------

func _entrance() -> void:
	var out: Vector2 = entry["out"]
	var edge: Vector2 = entry["edge"]
	var across := Vector2(-out.y, out.x)
	# Rellano exterior y rampa hasta el terreno (o un escalón si casi no hay desnivel).
	var landing := 2.2
	var lc := edge + out * (landing * 0.5 + 0.25)
	_boxp("nx:ext", "floor", Vector3(lc.x, floor_y - 0.1, lc.y), _xz(out, landing + 0.5, 0.2, ENTRY_W + 1.4), true)
	var lsize := _xz(out, landing + 0.5, 0.0, ENTRY_W + 1.4)
	_stilts(lc, lsize.x, lsize.z)
	var start := edge + out * (landing + 0.5)
	var dh := floor_y - float(ground.call(start.x, start.y))
	var run := 1.2
	for it in 3:
		run = maxf(1.2, dh / tan(deg_to_rad(RAMP_SLOPE_DEG)))
		var e := start + out * run
		dh = floor_y - float(ground.call(e.x, e.y)) + 0.05
	run = maxf(1.2, dh / tan(deg_to_rad(RAMP_SLOPE_DEG)))
	var slope := atan2(dh, run)
	var rl := sqrt(run * run + dh * dh)
	var rc := start + out * (run * 0.5)
	var yaw := atan2(out.x, out.y)
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, slope)
	var rxf := Transform3D(basis, Vector3(rc.x, floor_y - dh * 0.5 - 0.1, rc.y))
	_box("nx:ext", "floor", rxf, Vector3(ENTRY_W + 0.6, 0.2, rl + 0.1), true)
	for sgn: float in [-1.0, 1.0]:
		var rail := Transform3D(basis, Vector3(rc.x, floor_y - dh * 0.5 + 0.9, rc.y) + Vector3(across.x, 0, across.y) * sgn * (ENTRY_W * 0.5 + 0.25))
		_box("nx:ext", "trim", rail, Vector3(0.06, 0.06, rl), false)
		for k in 3:
			var t := float(k) / 2.0
			var pp: Vector2 = start + out * (run * t) + across * float(sgn) * (ENTRY_W * 0.5 + 0.25)
			var y_top := floor_y - dh * t + 0.9
			var y_bot := float(ground.call(pp.x, pp.y)) - 0.3
			_boxp("nx:ext", "metal", Vector3(pp.x, (y_top + y_bot) * 0.5, pp.y), Vector3(0.07, y_top - y_bot, 0.07))
	footprints.append(Rect2(minf(edge.x, (start + out * run).x) - 2.5, minf(edge.y, (start + out * run).y) - 2.5,
		absf(out.x) * (run + landing + 1.0) + 5.0, absf(out.y) * (run + landing + 1.0) + 5.0))
	entry["foot"] = start + out * (run + 1.0)
	entry["ramp_end"] = start + out * run
	entry["drop"] = dh
	# Pórtico de la entrada: marco grande, franjas de aviso, luz y cartel.
	var door := Vector3(edge.x, floor_y, edge.y) + Vector3(out.x, 0, out.y) * 0.32
	for sgn: float in [-1.0, 1.0]:
		var pc: Vector3 = door + Vector3(across.x, 0, across.y) * float(sgn) * (ENTRY_W * 0.5 + 0.35)
		_boxp("nx:ext", "shell_dark", pc + Vector3(0, (ENTRY_H + 0.6) * 0.5, 0), _xz(out, 0.5, ENTRY_H + 0.6, 0.5))
		_boxp("nx:ext", "trim", pc + Vector3(0, 0.9, 0) + Vector3(out.x, 0, out.y) * 0.26, _xz(out, 0.02, 1.2, 0.45))
	_boxp("nx:ext", "shell_dark", door + Vector3(0, ENTRY_H + 0.45, 0), _xz(out, 0.5, 0.3, ENTRY_W + 1.2))
	_boxp("nx:ext", "glow_amber", door + Vector3(0, ENTRY_H + 0.27, 0) + Vector3(out.x, 0, out.y) * 0.26, _xz(out, 0.03, 0.06, ENTRY_W))
	_omni(door + Vector3(0, ENTRY_H + 0.4, 0) + Vector3(out.x, 0, out.y) * 1.2, 9.0, 1.2, Color(1.0, 0.75, 0.45), false)
	var lbl := bb.label("", site_name.to_upper(), door + Vector3(0, ENTRY_H + 1.05, 0) + Vector3(out.x, 0, out.y) * 0.3, yaw, 0.75,
		Color(1.0, 0.55, 0.15), Layers.WORLD)
	lbl.double_sided = true
	bb.logo(door + Vector3(0, ENTRY_H + 2.35, 0) + Vector3(out.x, 0, out.y) * 0.3, yaw, 2.4, true)


static func _xz(out: Vector2, along: float, h: float, across: float) -> Vector3:
	return Vector3(along, h, across) if absf(out.x) > 0.5 else Vector3(across, h, along)


# --- Exterior ---------------------------------------------------------------------------------

func _free(r: Rect2) -> bool:
	for f: Rect2 in footprints:
		if f.intersects(r):
			return false
	return true


## Busca un sitio libre de tamaño `size` (x, z) a una distancia del centro de la planta.
func _spot(size: Vector2, r0: float, r1: float, tries := 60) -> Vector2:
	var center := Vector2.ZERO
	for m: Dictionary in modules:
		center += m["pos"]
	center /= float(modules.size())
	for k in tries:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(r0, r1)
		var p := center + Vector2(cos(ang), sin(ang)) * r
		var rect := Rect2(p - size * 0.5 - Vector2(1.5, 1.5), size + Vector2(3, 3))
		if _free(rect):
			footprints.append(rect)
			return p
	return Vector2.INF


## Radio despejado de rocas alrededor del origen: la planta y los objetos exteriores.
func clear_radius() -> float:
	var r := _extent() + 10.0
	for f: Rect2 in footprints:
		for c in [f.position, f.end, Vector2(f.position.x, f.end.y), Vector2(f.end.x, f.position.y)]:
			r = maxf(r, (c as Vector2).length() + 3.0)
	return r


func _extent() -> float:
	var e := 0.0
	for m: Dictionary in modules:
		var p: Vector2 = m["pos"]
		e = maxf(e, p.length() + maxf(m["w"], m["d"]) * 0.7)
	return e


func _exterior() -> void:
	var ext := _extent()
	_landing_pad()
	# Mástil de comunicaciones con baliza (siempre).
	var mp := _spot(Vector2(4, 4), ext + 4.0, ext + 14.0)
	if mp == Vector2.INF:
		mp = Vector2(ext + 8.0, 0)
	_mast(mp)
	for k in rng.randi_range(2, 4):
		var sp := _spot(Vector2(12, 4), ext + 6.0, ext + 34.0)
		if sp != Vector2.INF:
			_solar(sp, rng.randf() < 0.5)
	for k in rng.randi_range(1, 2):
		var sp := _spot(Vector2(5, 3), ext + 3.0, ext + 20.0)
		if sp != Vector2.INF:
			_radiator(sp)
	for k in rng.randi_range(2, 3):
		var sp := _spot(Vector2(7, 3.5), ext + 4.0, ext + 22.0)
		if sp != Vector2.INF:
			_tank(sp, rng.randf() < 0.5)
	for k in rng.randi_range(3, 6):
		var sp := _spot(Vector2(6.5, 6.5), ext + 3.0, ext + 26.0)
		if sp != Vector2.INF:
			_container(sp)


func _gy(p: Vector2) -> float:
	return float(ground.call(p.x, p.y))


## Plataforma de aterrizaje frente a la entrada, con farolas desde el pie de la rampa.
func _landing_pad() -> void:
	var out: Vector2 = entry["out"]
	var foot: Vector2 = entry["foot"]
	var pc := Vector2.INF
	for dist: float in [14.0, 20.0, 27.0, 35.0]:
		for lateral: float in [0.0, 10.0, -10.0]:
			var p: Vector2 = foot + out * dist + Vector2(-out.y, out.x) * lateral
			var rect := Rect2(p - Vector2(10, 10), Vector2(20, 20))
			if _free(rect):
				pc = p
				footprints.append(rect)
				break
		if pc != Vector2.INF:
			break
	if pc == Vector2.INF:
		return
	var lo := INF
	var hi := -INF
	for i in 5:
		for j in 5:
			var h := _gy(pc + Vector2(-8.0 + 4.0 * i, -8.0 + 4.0 * j))
			lo = minf(lo, h)
			hi = maxf(hi, h)
	var top := hi + 0.25
	_boxp("nx:ext", "shell_dark", Vector3(pc.x, (top + lo - 1.0) * 0.5, pc.y), Vector3(16, top - lo + 1.0, 16), true)
	_boxp("nx:ext", "floor", Vector3(pc.x, top + 0.01, pc.y), Vector3(15.4, 0.02, 15.4))
	_cyl("nx:ext", "trim", Vector3(pc.x, top + 0.03, pc.y), 5.5, 0.02, Vector3.ZERO, false, 32)
	_cyl("nx:ext", "floor", Vector3(pc.x, top + 0.04, pc.y), 5.0, 0.02, Vector3.ZERO, false, 32)
	_boxp("nx:ext", "trim", Vector3(pc.x, top + 0.05, pc.y), Vector3(0.5, 0.02, 4.0))
	_boxp("nx:ext", "trim", Vector3(pc.x, top + 0.05, pc.y), Vector3(2.6, 0.02, 0.5))
	for sx: float in [-1.0, 1.0]:
		_boxp("nx:ext", "trim", Vector3(pc.x + sx * 1.3, top + 0.05, pc.y), Vector3(0.5, 0.02, 4.0))
		for sz: float in [-1.0, 1.0]:
			_boxp("nx:ext", "glow_amber", Vector3(pc.x + sx * 7.6, top + 0.12, pc.y + sz * 7.6), Vector3(0.3, 0.2, 0.3))
	# Farolas del camino.
	var path := pc - foot
	var n := maxi(2, int(path.length() / 6.0))
	var across := Vector2(-path.y, path.x).normalized()
	for k in n:
		var p: Vector2 = foot + path * (float(k) + 0.5) / float(n) + across * 2.2
		var g := _gy(p)
		_cyl("nx:ext", "metal", Vector3(p.x, g + 1.1, p.y), 0.06, 2.2)
		_boxp("nx:ext", "glow_amber", Vector3(p.x, g + 2.25, p.y), Vector3(0.18, 0.12, 0.18))


func _mast(p: Vector2) -> void:
	var g := _gy(p)
	var h := rng.randf_range(14.0, 20.0)
	_boxp("nx:ext", "shell_dark", Vector3(p.x, g + 0.2, p.y), Vector3(2.4, 1.0, 2.4), true)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_cyl("nx:ext", "metal", Vector3(p.x + sx * 0.55, g + h * 0.5, p.y + sz * 0.55), 0.06, h, Vector3.ZERO, false, 6)
	var k := int(h / 2.0)
	for j in k:
		var y := g + 1.0 + float(j) * 2.0
		_boxp("nx:ext", "metal", Vector3(p.x, y, p.y + 0.55), Vector3(1.1, 0.05, 0.05))
		_boxp("nx:ext", "metal", Vector3(p.x, y, p.y - 0.55), Vector3(1.1, 0.05, 0.05))
		_boxp("nx:ext", "metal", Vector3(p.x + 0.55, y + 1.0, p.y), Vector3(0.05, 0.05, 1.1))
		_boxp("nx:ext", "metal", Vector3(p.x - 0.55, y + 1.0, p.y), Vector3(0.05, 0.05, 1.1))
	_shape(Transform3D(Basis(), Vector3(p.x, g + h * 0.5, p.y)), Vector3(1.2, h, 1.2))
	_sphere("nx:ext", "shell", Vector3(p.x + 0.9, g + h * 0.72, p.y), 1.0, Vector3(1.1, 0.35, 1.1), true)
	_cyl("nx:ext", "trim", Vector3(p.x, g + h - 0.6, p.y), 0.75, 0.25)
	beacon_local = Vector3(p.x, g + h + 0.35, p.y)


func _solar(p: Vector2, along_x: bool) -> void:
	var n := rng.randi_range(3, 5)
	var tilt := deg_to_rad(rng.randf_range(20.0, 40.0))
	for k in n:
		var t := -float(n - 1) * 1.3 + 2.6 * k
		var q := p + (Vector2(t, 0) if along_x else Vector2(0, t))
		var g := _gy(q)
		_cyl("nx:ext", "metal", Vector3(q.x, g + 0.75, q.y), 0.07, 1.5, Vector3.ZERO, false, 6)
		var basis := Basis(Vector3.UP, 0.0 if along_x else PI * 0.5) * Basis(Vector3.RIGHT, tilt)
		_box("nx:ext", "solar", Transform3D(basis, Vector3(q.x, g + 1.6, q.y)), Vector3(2.4, 0.05, 1.6), false)
		_box("nx:ext", "metal", Transform3D(basis, Vector3(q.x, g + 1.57, q.y)), Vector3(2.5, 0.03, 1.7), false)


func _radiator(p: Vector2) -> void:
	var g := _gy(p)
	_boxp("nx:ext", "shell_dark", Vector3(p.x, g + 0.4, p.y), Vector3(4.2, 0.8, 1.0), true)
	for k in 6:
		_boxp("nx:ext", "shell", Vector3(p.x - 1.75 + 0.7 * k, g + 2.0, p.y), Vector3(0.05, 2.4, 1.6))


func _tank(p: Vector2, along_x: bool) -> void:
	var g := _gy(p)
	var rot := Vector3(0, 0, PI * 0.5) if along_x else Vector3(PI * 0.5, 0, 0)
	_cyl("nx:ext", "shell", Vector3(p.x, g + 1.5, p.y), 1.2, 5.5, rot, true, 16)
	_cyl("nx:ext", "trim", Vector3(p.x, g + 1.5, p.y), 1.23, 0.4, rot, false, 16)
	for sgn: float in [-1.0, 1.0]:
		var o := Vector3(sgn * 1.8, 0, 0) if along_x else Vector3(0, 0, sgn * 1.8)
		_boxp("nx:ext", "shell_dark", Vector3(p.x, g + 0.3, p.y) + o, Vector3(0.4 if along_x else 2.2, 0.8, 2.2 if along_x else 0.4))


func _container(p: Vector2) -> void:
	var g := _gy(p)
	var yaw := rng.randf_range(-0.4, 0.4) + (PI * 0.5 if rng.randf() < 0.5 else 0.0)
	var basis := Basis(Vector3.UP, yaw)
	var mat := "trim" if rng.randf() < 0.4 else ("shell" if rng.randf() < 0.6 else "shell_dark")
	_box("nx:ext", mat, Transform3D(basis, Vector3(p.x, g + 1.15, p.y)), Vector3(6.0, 2.5, 2.5), true)
	_box("nx:ext", "shell_dark", Transform3D(basis, Vector3(p.x, g + 1.15, p.y)), Vector3(6.06, 0.15, 2.56), false)
	if rng.randf() < 0.35:
		_box("nx:ext", "shell" if mat != "shell" else "trim", Transform3D(basis, Vector3(p.x, g + 3.65, p.y)), Vector3(6.0, 2.5, 2.5), true)
