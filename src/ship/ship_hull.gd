class_name ShipHull
extends RefCounted
## Casco exterior liso de la nave (ADR-021). Sustituye a las cajas del diseño anterior por superficies
## suaves generadas por secciones:
## - Fuselaje: secciones superelípticas (exponente 4: costados casi planos, esquinas redondeadas) cuya
##   anchura sigue una curva monótona por la eslora (hombros que se estrechan hacia el puente, popa con
##   toberas). Encierra por completo el interior (comprobado en las pruebas).
## - Ventanas y la puerta de la esclusa: recortes EXACTOS del casco (la malla incluye líneas en sus
##   bordes) con marcos que unen el casco con la pared interior; la colisión del casco también se recorta.
## - Morro bajo el parabrisas, lomo dorsal, alas en flecha con góndolas de motor y dos derivas inclinadas.
## - Pintura en dos tonos con franja naranja; juntas de panel por el sombreador de la nave.
## Devuelve las caras de colisión (ConcavePolygonShape3D, por ambas caras) de todas las superficies.

const N_FUS := 4.0
const C_Y := 1.5            ## centro vertical de las secciones del fuselaje (m)
const B_FUS := 2.6          ## semialtura del fuselaje: fondo y = −1,1, techo y = 4,1
const RING := 64
const Z_FRONT := -26.35
const Z_REAR := 23.4
const BATCH := "ext:casco"
## Semiancho del fuselaje por la eslora (z, a). Interpolación monótona (sin sobreoscilación).
const KEYS_A := [[-26.35, 6.2], [-24.0, 6.25], [-22.0, 6.35], [-21.0, 6.8], [-19.6, 8.3], [-18.4, 10.1],
	[-17.0, 10.2], [19.0, 10.2], [21.0, 10.15], [22.45, 10.05], [23.4, 9.3]]
const KEYS_B := [[-26.35, B_FUS], [22.45, B_FUS], [23.4, 2.3]]
const WINDSHIELD_OUT := Rect2(-4.5, 0.9, 9.0, 1.95)  ## hueco del parabrisas en la cara frontal

var b: Object                  ## ShipBuilder (primitivas con lote, material y colisión)
var faces := PackedVector3Array()
var _acc := {}                 ## material -> [verts, normals, indices]


func build(builder: Object) -> PackedVector3Array:
	b = builder
	_fuselage()
	_chin()
	_spine()
	for side: float in [-1.0, 1.0]:
		_wing(side)
		_nacelle(side)
		_fin(side)
	_opening_frames()
	_details()
	for mat in _acc:
		var a: Array = _acc[mat]
		b.batcher.triangles(BATCH, mat, a[0], a[1], a[2])
	return faces


# --- Utilidades geométricas --------------------------------------------------------------

static func se(t: float, n: float) -> Vector2:
	var c := cos(t)
	var s := sin(t)
	return Vector2(signf(c) * pow(absf(c), 2.0 / n), signf(s) * pow(absf(s), 2.0 / n))


## Interpolación cúbica monótona (Fritsch–Carlson) de pares [x, y] ordenados por x.
static func pchip(keys: Array, x: float) -> float:
	var n := keys.size()
	if x <= keys[0][0]:
		return keys[0][1]
	if x >= keys[n - 1][0]:
		return keys[n - 1][1]
	var i := 0
	while x > keys[i + 1][0]:
		i += 1
	var x0: float = keys[i][0]
	var x1: float = keys[i + 1][0]
	var y0: float = keys[i][1]
	var y1: float = keys[i + 1][1]
	var h := x1 - x0
	var d := (y1 - y0) / h
	var m0 := _slope(keys, i, d)
	var m1 := _slope(keys, i + 1, d)
	var t := (x - x0) / h
	var t2 := t * t
	var t3 := t2 * t
	return (2 * t3 - 3 * t2 + 1) * y0 + (t3 - 2 * t2 + t) * h * m0 + (-2 * t3 + 3 * t2) * y1 + (t3 - t2) * h * m1


static func _slope(keys: Array, i: int, d_seg: float) -> float:
	if i == 0 or i == keys.size() - 1:
		return 0.0 * d_seg  # extremos planos
	var d0: float = (keys[i][1] - keys[i - 1][1]) / (keys[i][0] - keys[i - 1][0])
	var d1: float = (keys[i + 1][1] - keys[i][1]) / (keys[i + 1][0] - keys[i][0])
	if d0 * d1 <= 0.0:
		return 0.0
	return 2.0 / (1.0 / d0 + 1.0 / d1)


static func fus_a(z: float) -> float:
	return pchip(KEYS_A, z)


static func fus_b(z: float) -> float:
	return pchip(KEYS_B, z)


## |x| del casco a la altura y en la estación z (para los marcos de las ventanas).
static func shell_x(z: float, y: float) -> float:
	var a := fus_a(z)
	var bb := fus_b(z)
	var s := clampf(absf(y - C_Y) / bb, 0.0, 1.0)
	return a * pow(maxf(0.0, 1.0 - pow(s, N_FUS)), 1.0 / N_FUS)


## Parámetro t del anillo cuyo punto (lado derecho) está a la altura y.
static func t_for_y(y: float) -> float:
	var s := clampf((y - C_Y) / B_FUS, -1.0, 1.0)
	return signf(s) * asin(pow(absf(s), N_FUS * 0.5))


func _acc_for(mat: String) -> Array:
	if not _acc.has(mat):
		_acc[mat] = [PackedVector3Array(), PackedVector3Array(), PackedInt32Array()]
	return _acc[mat]


## Cuadrilátero con normales por vértice; orientación comprobada con la normal media; colisión.
func _quad(mat: String, p: Array, n: Array, collide := true) -> void:
	var a := _acc_for(mat)
	var verts: PackedVector3Array = a[0]
	var norms: PackedVector3Array = a[1]
	var idx: PackedInt32Array = a[2]
	var base := verts.size()
	var nm: Vector3 = (n[0] + n[1] + n[2] + n[3]).normalized()
	for k in 4:
		verts.append(p[k])
		norms.append(n[k])
	var flip: bool = (p[2] - p[0]).cross(p[1] - p[0]).dot(nm) < 0.0
	var tri := [0, 1, 2, 0, 2, 3] if not flip else [0, 2, 1, 0, 3, 2]
	for k in tri:
		idx.append(base + k)
	if collide:
		for k in tri:
			faces.append(p[k])
	a[0] = verts
	a[1] = norms
	a[2] = idx


## Malla de anillos (todos con el mismo número de puntos, cerrados). `centers[i]` = centro de cada anillo
## (para orientar las normales hacia fuera). `paint` = Callable(centro, normal) -> material;
## `cut` = Callable(centro, normal) -> bool (recorte); `cap_end` cierra el último anillo.
func _loft(rings: Array, centers: Array, paint: Callable, cut: Callable = Callable(), cap_start := false, cap_end := false) -> void:
	var ns := rings.size()
	var m: int = rings[0].size()
	var normals := []
	for i in ns:
		var row := []
		for j in m:
			var p: Vector3 = rings[i][j]
			var dt: Vector3 = rings[i][(j + 1) % m] - rings[i][(j - 1 + m) % m]
			var dz: Vector3 = rings[mini(i + 1, ns - 1)][j] - rings[maxi(i - 1, 0)][j]
			var nn := dt.cross(dz)
			var out: Vector3 = p - centers[i]
			if nn.length_squared() < 1e-12:
				nn = out
			if nn.dot(out) < 0.0:
				nn = -nn
			row.append(nn.normalized())
		normals.append(row)
	for i in ns - 1:
		for j in m:
			var j1 := (j + 1) % m
			var p := [rings[i][j], rings[i][j1], rings[i + 1][j1], rings[i + 1][j]]
			var n := [normals[i][j], normals[i][j1], normals[i + 1][j1], normals[i + 1][j]]
			var c: Vector3 = (p[0] + p[1] + p[2] + p[3]) * 0.25
			var nc: Vector3 = (n[0] + n[1] + n[2] + n[3]).normalized()
			if cut.is_valid() and cut.call(c, nc):
				continue
			_quad(paint.call(c, nc), p, n)
	if cap_start:
		_fan(rings[0], centers[0], (centers[0] - centers[1]).normalized(), paint)
	if cap_end:
		_fan(rings[ns - 1], centers[ns - 1], (centers[ns - 1] - centers[ns - 2]).normalized(), paint)


func _fan(ring: Array, center: Vector3, normal: Vector3, paint: Callable) -> void:
	var m := ring.size()
	var mat: String = paint.call(center, normal)
	for j in m:
		var p := [center, ring[j], ring[(j + 1) % m], center]
		_quad(mat, p, [normal, normal, normal, normal])


# --- Fuselaje ---------------------------------------------------------------------------

## Recortes del casco: [lado (±1), z0, z1, y0, y1].
static func openings() -> Array:
	var r := []
	for o in ShipLayout.HULL_OPENINGS_LEFT:
		r.append([-1.0, o[0] - o[1] * 0.5, o[0] + o[1] * 0.5, o[2], o[3]])
	for o in ShipLayout.HULL_OPENINGS_RIGHT:
		r.append([1.0, o[0] - o[1] * 0.5, o[0] + o[1] * 0.5, o[2], o[3]])
	var w: Array = ShipLayout.COCKPIT_SIDE_WINDOW
	for side: float in [-1.0, 1.0]:
		r.append([side, w[0] - w[1] * 0.5, w[0] + w[1] * 0.5, w[2], w[3]])
	return r


func _fuselage() -> void:
	# Estaciones: más densas en hombros y popa, y exactamente en los bordes de los recortes.
	var zs := []
	var z := Z_FRONT
	while z < Z_REAR - 0.01:
		zs.append(z)
		z += 0.5 if (z < -16.5 or z > 18.5) else 1.0
	zs.append(Z_REAR)
	var ts := []
	for j in RING:
		ts.append(TAU * j / RING)
	var ys := [0.15, 0.4]
	for o in openings():
		zs.append(o[1])
		zs.append(o[2])
		ys.append(o[3])
		ys.append(o[4])
	for y: float in ys:
		var t := t_for_y(y)
		ts.append(fposmod(t, TAU))
		ts.append(fposmod(PI - t, TAU))
	# Ventana del suelo del pasillo: bordes exactos del recorte inferior.
	var fw := ShipLayout.FLOOR_WINDOW
	zs.append(fw.position.y)
	zs.append(fw.end.y)
	var dt := asin(pow(absf(fw.position.x) / 10.2, N_FUS * 0.5))
	for t: float in [1.5 * PI - dt, 1.5 * PI + dt]:
		ts.append(t)
	# Límite del panel dorsal oscuro (|x| = 3,2 m en el tramo de manga máxima).
	var tx := acos(pow(3.2 / 10.2, N_FUS * 0.5))
	for t: float in [tx, PI - tx]:
		ts.append(t)
	zs = _unique_sorted(zs, 0.05)
	ts = _unique_sorted(ts, 0.004)
	var rings := []
	var centers := []
	for zz: float in zs:
		var a := fus_a(zz)
		var bb := fus_b(zz)
		var ring := []
		for t: float in ts:
			var q := se(t, N_FUS)
			ring.append(Vector3(a * q.x, C_Y + bb * q.y, zz))
		rings.append(ring)
		centers.append(Vector3(0, C_Y, zz))
	var ops := openings()
	var cut := func(c: Vector3, _n: Vector3) -> bool:
		if c.y < 0.0 and absf(c.x) < absf(fw.position.x) and c.z > fw.position.y and c.z < fw.end.y:
			return true
		for o in ops:
			if signf(c.x) == o[0] and c.z > o[1] and c.z < o[2] and c.y > o[3] and c.y < o[4]:
				return true
		return false
	_loft(rings, centers, _paint_fuselage, cut, false, true)
	_front_cap(rings[0])


func _paint_fuselage(c: Vector3, n: Vector3) -> String:
	if c.y < 0.15:
		return "hull_dark"
	if c.y < 0.4 and absf(n.x) > 0.5:
		return "trim"
	if c.y > 3.6 and absf(c.x) < 3.2 and c.z > -18.0 and c.z < 21.0:
		return "hull_accent"
	return "hull"


static func _unique_sorted(values: Array, eps: float) -> Array:
	var v := values.duplicate()
	v.sort()
	var out := []
	for x: float in v:
		if out.is_empty() or x - out[out.size() - 1] > eps:
			out.append(x)
	return out


## Cara frontal del puente: del contorno del fuselaje al hueco rectangular del parabrisas.
func _front_cap(ring: Array) -> void:
	var r := WINDSHIELD_OUT
	var pc := Vector3(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5, Z_FRONT)
	var hx := r.size.x * 0.5
	var hy := r.size.y * 0.5
	var m := ring.size()
	var inner := []
	for j in m:
		var d: Vector3 = ring[j] - pc
		var s := minf(hx / maxf(absf(d.x), 1e-6), hy / maxf(absf(d.y), 1e-6))
		inner.append(pc + Vector3(d.x * s, d.y * s, 0.0))
	var nrm := Vector3(0, 0, -1)
	for j in m:
		var j1 := (j + 1) % m
		var p := [ring[j], ring[j1], inner[j1], inner[j]]
		_quad("hull_dark" if (ring[j] as Vector3).y < 0.15 else "hull", p, [nrm, nrm, nrm, nrm])


# --- Morro, lomo, alas, góndolas, derivas -------------------------------------------------

func _section_ring(center: Vector3, u: Vector3, v: Vector3, n: float, count: int) -> Array:
	var ring := []
	for j in count:
		var q := se(TAU * j / count, n)
		ring.append(center + u * q.x + v * q.y)
	return ring


func _loft_sections(secs: Array, n: float, count: int, paint: Callable, cap_start := false, cap_end := true) -> void:
	var rings := []
	var centers := []
	for s in secs:
		rings.append(_section_ring(s[0], s[1], s[2], n, count))
		centers.append(s[0])
	_loft(rings, centers, paint, Callable(), cap_start, cap_end)


func _paint_lower_dark(c: Vector3, n: Vector3) -> String:
	return "hull_dark" if n.y < -0.3 or c.y < 0.15 else "hull"


## Morro bajo el parabrisas (queda por debajo del alféizar: no tapa la vista).
func _chin() -> void:
	var keys := [[-26.2, 5.6, 0.98, -0.1], [-27.5, 5.2, 0.92, -0.12], [-28.8, 4.3, 0.8, -0.16],
		[-29.9, 3.0, 0.6, -0.2], [-30.7, 1.6, 0.38, -0.24], [-31.15, 0.45, 0.14, -0.26]]
	var secs := []
	for k in keys:
		secs.append([Vector3(0, k[3], k[0]), Vector3(k[1], 0, 0), Vector3(0, k[2], 0)])
	_loft_sections(secs, 2.8, 48, _paint_lower_dark, false, true)


func _spine() -> void:
	var secs := []
	for k in [[-16.0, 0.25, 0.1], [-14.0, 1.1, 0.4], [-8.0, 1.35, 0.5], [10.0, 1.35, 0.5], [15.0, 1.0, 0.38], [17.0, 0.25, 0.1]]:
		secs.append([Vector3(0, C_Y + B_FUS - 0.12, k[0]), Vector3(k[1], 0, 0), Vector3(0, k[2], 0)])
	_loft_sections(secs, 3.0, 24, func(_c: Vector3, _n: Vector3) -> String: return "hull_dark", true, true)


func _wing(side: float) -> void:
	var secs := []
	for i in 9:
		var u := i / 8.0
		var x := side * (9.4 + 10.2 * u)
		var lead := 3.0 + 10.5 * u
		var trail := 19.0 - 0.5 * u
		var y := 0.45 - 0.4 * u
		var th := 0.45 - 0.33 * u
		secs.append([Vector3(x, y, (lead + trail) * 0.5), Vector3(0, 0, (trail - lead) * 0.5), Vector3(0, th, 0)])
	_loft_sections(secs, 2.4, 28, func(c: Vector3, n: Vector3) -> String:
		if n.y < -0.2:
			return "hull_dark"
		return "trim" if c.z < 3.3 + 10.5 * clampf((absf(c.x) - 9.4) / 10.2, 0.0, 1.0) + 0.6 else "hull", false, true)


func _nacelle(side: float) -> void:
	var x := side * 15.5
	var y := 0.3
	var secs := []
	for k in [[7.6, 0.9], [8.0, 1.25], [9.0, 1.42], [13.0, 1.5], [19.0, 1.45], [21.5, 1.25], [22.6, 1.05]]:
		secs.append([Vector3(x, y, k[0]), Vector3(k[1], 0, 0), Vector3(0, k[1], 0)])
	_loft_sections(secs, 2.0, 32, func(c: Vector3, n: Vector3) -> String:
		if c.z < 8.3:
			return "trim"
		return "hull_dark" if n.y < -0.5 else "hull", false, false)
	# Toma de aire (ventilador oscuro con cono) y tobera.
	b.cyl(BATCH, "hull_dark", Vector3(x, y, 7.75), 0.92, 0.1, false, Vector3(PI / 2, 0, 0))
	b.sphere(BATCH, "metal", Vector3(x, y, 7.8), 0.32, Vector3(1, 1, 1.6))
	b.cyl(BATCH, "hull_dark", Vector3(x, y, 23.0), 1.05, 0.8, false, Vector3(PI / 2, 0, 0), 0.9)
	b.ring(BATCH, "trim", Vector3(x, y, 13.0), 1.47, 1.55, Vector3(PI / 2, 0, 0))
	# Luz de navegación en la punta del ala: roja a babor, verde a estribor.
	b.sphere(BATCH, "glow_red" if side < 0 else "glow_green", Vector3(side * 19.7, 0.05, 16.3), 0.14)


func _fin(side: float) -> void:
	var cant := 0.35
	var e := Vector3(side * sin(cant), cos(cant), 0)        # dirección de la envergadura de la deriva
	var thick := Vector3(side * cos(cant), -sin(cant), 0)   # espesor (perpendicular al plano)
	var root := Vector3(side * 4.6, 3.85, 0)
	var secs := []
	for i in 6:
		var u := i / 5.0
		var p := root + e * (3.6 * u)
		var lead := 13.0 + 6.0 * u
		var trail := 21.6 + 1.2 * u
		secs.append([Vector3(p.x, p.y, (lead + trail) * 0.5), Vector3(0, 0, (trail - lead) * 0.5), thick * (0.24 - 0.16 * u)])
	_loft_sections(secs, 2.4, 24, func(c: Vector3, _n: Vector3) -> String:
		return "trim" if c.y > 3.85 + 3.6 * cos(cant) * 0.82 else "hull", false, true)
	b.sphere(BATCH, "glow_white", root + e * 3.62 + Vector3(0, 0, 22.6), 0.09)


# --- Marcos de los recortes ----------------------------------------------------------------

## Une cada recorte del casco con la pared interior (sin huecos visibles). La puerta de la esclusa tiene
## además suelo y colisión (paso al exterior).
func _opening_frames() -> void:
	for o in openings():
		var side: float = o[0]
		var z0: float = o[1]
		var z1: float = o[2]
		var y0: float = o[3]
		var y1: float = o[4]
		var bridge := z1 < ShipLayout.FRONT_Z
		var x_in := (ShipLayout.COCKPIT_HALF if bridge else ShipLayout.HALF_WIDTH) + 0.1
		var x_out := 0.0
		for zz: float in [z0, z1]:
			for yy: float in [y0, y1]:
				x_out = maxf(x_out, shell_x(zz, yy))
		x_out += 0.04
		var depth := x_out - x_in
		var xc := side * (x_in + depth * 0.5)
		var door := y0 <= 0.01
		var f := 0.12
		# Dintel y alféizar (o umbral), jambas delantera y trasera.
		b.box(BATCH, "hull_dark", Vector3(xc, y1 + f * 0.5, (z0 + z1) * 0.5), Vector3(depth, f, z1 - z0 + 2 * f), door)
		if door:
			# El umbral termina justo donde empieza la rampa (sin escalón).
			var x_end := shell_x((z0 + z1) * 0.5, 0.0) + 0.05
			b.box(BATCH, "floor", Vector3(side * (x_in + x_end) * 0.5, -0.1, (z0 + z1) * 0.5), Vector3(x_end - x_in, 0.2, z1 - z0), true)
		else:
			b.box(BATCH, "hull_dark", Vector3(xc, y0 - f * 0.5, (z0 + z1) * 0.5), Vector3(depth, f, z1 - z0 + 2 * f), false)
		for zz: float in [z0 - f * 0.5, z1 + f * 0.5]:
			b.box(BATCH, "hull_dark", Vector3(xc, (y0 + y1) * 0.5, zz), Vector3(depth, y1 - y0, f), door)
		# Moldura exterior clara alrededor de las ventanas.
		if not door:
			b.box(BATCH, "trim" if bridge else "metal", Vector3(side * (x_out - 0.01), y1 + 0.06, (z0 + z1) * 0.5), Vector3(0.05, 0.05, z1 - z0 + 0.2), false)
	# Ventana del suelo: paredes que bajan del suelo de la cubierta al fondo del casco.
	var fw := ShipLayout.FLOOR_WINDOW
	var bottom := C_Y - B_FUS - 0.03
	var wh := -0.05 - bottom
	var zc0 := (fw.position.y + fw.end.y) * 0.5
	for x: float in [fw.position.x - 0.03, fw.end.x + 0.03]:
		b.box(BATCH, "hull_dark", Vector3(x, bottom + wh * 0.5, zc0), Vector3(0.06, wh, fw.size.y), false)
	for z: float in [fw.position.y - 0.03, fw.end.y + 0.03]:
		b.box(BATCH, "hull_dark", Vector3(0, bottom + wh * 0.5, z), Vector3(fw.size.x + 0.12, wh, 0.06), false)
	# Parabrisas: marco entre la cara frontal y la pared interior del puente, con montantes.
	var r := WINDSHIELD_OUT
	var z_in := ShipLayout.COCKPIT_FRONT_Z - 0.06
	var dz := z_in - Z_FRONT
	var zc := (Z_FRONT + z_in) * 0.5
	b.box(BATCH, "hull_dark", Vector3(0, r.position.y - 0.03, zc), Vector3(r.size.x, 0.06, dz), false)
	b.box(BATCH, "hull_dark", Vector3(0, r.end.y + 0.03, zc), Vector3(r.size.x, 0.06, dz), false)
	for sx: float in [-1.0, 1.0]:
		b.box(BATCH, "hull_dark", Vector3(sx * (r.size.x * 0.5 + 0.03), r.position.y + r.size.y * 0.5, zc), Vector3(0.06, r.size.y, dz), false)
	for x: float in [-1.55, 1.55]:
		b.box(BATCH, "hull_dark", Vector3(x, r.position.y + r.size.y * 0.5, Z_FRONT + 0.05), Vector3(0.12, r.size.y, 0.14), false)
	# Visera sobre el parabrisas.
	b.box(BATCH, "hull_dark", Vector3(0, r.end.y + 0.22, Z_FRONT - 0.35), Vector3(r.size.x + 0.6, 0.12, 0.8), false, Vector3(0.22, 0, 0))


# --- Detalles -----------------------------------------------------------------------------

func _details() -> void:
	# Toberas principales en la popa.
	for sx: float in [-1.0, 1.0]:
		b.cyl(BATCH, "hull_dark", Vector3(sx * 3.4, C_Y, 24.0), 1.3, 1.3, false, Vector3(PI / 2, 0, 0), 1.08)
		b.ring(BATCH, "metal", Vector3(sx * 3.4, C_Y, 24.62), 1.08, 1.22, Vector3(PI / 2, 0, 0))
	# Cúpula de sensores y antena sobre el lomo; baliza.
	b.sphere(BATCH, "metal", Vector3(0, C_Y + B_FUS + 0.38, -11.0), 0.7, Vector3(1, 0.45, 1.3))
	b.cyl(BATCH, "metal", Vector3(0.6, C_Y + B_FUS + 1.0, 6.0), 0.035, 1.6, false)
	b.sphere(BATCH, "glow_red", Vector3(0.6, C_Y + B_FUS + 1.82, 6.0), 0.07)
	# Faros de aterrizaje bajo el morro y bajo las alas.
	for p: Vector3 in [Vector3(-1.2, -0.95, -27.6), Vector3(1.2, -0.95, -27.6), Vector3(-12.0, 0.0, 12.0), Vector3(12.0, 0.0, 12.0)]:
		b.sphere(BATCH, "glow_white", p, 0.16, Vector3(1, 0.4, 1))
	# Rejillas de ventilación y escotillas de servicio en los costados (detalle a media distancia).
	for side: float in [-1.0, 1.0]:
		for i in 4:
			var zz := 12.0 + i * 2.2
			var x := side * (shell_x(zz, 1.4) + 0.01)
			b.box(BATCH, "hull_dark", Vector3(x, 1.4, zz), Vector3(0.04, 0.9, 1.4), false)
			for k in 4:
				b.box(BATCH, "metal", Vector3(x + side * 0.015, 1.1 + k * 0.2, zz), Vector3(0.03, 0.04, 1.25), false)
	# --- Detalle añadido (ronda 7, ADR-036) ---
	var roof := C_Y + B_FUS
	# Radiadores en el techo a ambos lados del lomo: paneles oscuros con aletas y marco naranja.
	for side: float in [-1.0, 1.0]:
		var rx := side * 4.2
		b.box(BATCH, "hull_dark", Vector3(rx, roof - 0.02, 3.0), Vector3(3.0, 0.1, 12.0), false)
		for k in 11:
			b.box(BATCH, "metal", Vector3(rx, roof + 0.06, -2.5 + k * 1.1), Vector3(2.8, 0.06, 0.08), false)
		for e: float in [-1.0, 1.0]:
			b.box(BATCH, "trim", Vector3(rx + e * 1.52, roof + 0.02, 3.0), Vector3(0.06, 0.12, 12.1), false)
	# Mástil de comunicaciones con antena parabólica orientable.
	b.cyl(BATCH, "metal", Vector3(-1.6, roof + 0.7, 14.0), 0.09, 1.4, false)
	b.sphere(BATCH, "metal", Vector3(-1.6, roof + 1.55, 14.0), 0.85, Vector3(1, 0.22, 1))
	b.cyl(BATCH, "hull_dark", Vector3(-1.6, roof + 1.75, 14.0), 0.04, 0.6, false)
	b.sphere(BATCH, "glow_white", Vector3(-1.6, roof + 2.06, 14.0), 0.06)
	# Bloques de propulsores de maniobra (RCS) en las cuatro esquinas, con tres toberas cada uno.
	for zc: float in [-14.5, 19.5]:
		for side: float in [-1.0, 1.0]:
			var x := side * (shell_x(zc, 3.0) - 0.1)
			b.box(BATCH, "hull_dark", Vector3(x, 3.2, zc), Vector3(0.7, 0.55, 0.7), false)
			for d: Vector3 in [Vector3(side, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1 if zc > 0 else -1)]:
				var rot := Vector3.ZERO
				if absf(d.x) > 0.5:
					rot = Vector3(0, 0, PI / 2)
				elif absf(d.z) > 0.5:
					rot = Vector3(PI / 2, 0, 0)
				b.cyl(BATCH, "metal", Vector3(x, 3.2, zc) + d * 0.42, 0.11, 0.18, false, rot, 0.07)
	# Franjas de aviso alrededor de la esclusa y de las toberas.
	var door: Vector2 = ShipLayout.DOORS["esclusa_ext"][2]
	for i in 8:
		var zz: float = door.y - 1.2 + i * 0.3
		b.box(BATCH, "trim" if i % 2 == 0 else "hull_dark", Vector3(shell_x(zz, -0.3) + 0.02, -0.3, zz), Vector3(0.04, 0.22, 0.28), false)
	# Matrícula junto al morro y marca de la misión.
	for side: float in [-1.0, 1.0]:
		var reg := Label3D.new()
		reg.text = "EXP-01"
		reg.font_size = 64
		reg.pixel_size = 0.006
		reg.modulate = Color(0.95, 0.5, 0.18)
		reg.double_sided = false
		reg.shaded = true
		reg.layers = Layers.bit(Layers.SHIP_EXT)
		var rz := -20.6
		reg.position = Vector3(side * (shell_x(rz, 2.2) + 0.03), 2.2, rz)
		reg.rotation = Vector3(0, side * PI / 2.0, 0)
		b.ship.add_child(reg)
	# Nombre de la nave en los costados.
	for side: float in [-1.0, 1.0]:
		var l := Label3D.new()
		l.text = "ESPERANZA"
		l.font_size = 110
		l.pixel_size = 0.0075
		l.outline_size = 0
		l.modulate = Color(0.12, 0.16, 0.22)
		l.double_sided = false
		l.shaded = true
		l.layers = Layers.bit(Layers.SHIP_EXT)
		var lz := -7.0 if side < 0.0 else 15.5
		var x := side * (shell_x(lz, 1.95) + 0.03)
		l.position = Vector3(x, 2.4, lz)
		l.rotation = Vector3(0, side * PI / 2.0, 0)
		b.ship.add_child(l)
