class_name TerrainPatchBuilder
extends RefCounted
## Construye la geometría de un parche: cuadrícula (n+1)² sobre la esfera, normales con una
## corona extra de muestras (iluminación continua entre parches), color de vértice, UV de detalle
## con periodo entero (continuas entre parches), faldones contra grietas y caras de colisión.
## Todas las posiciones se calculan en doble precisión y se guardan relativas al centro del parche.

const UV_BASE_STEP := 8.0
const UV_MAX_RANGE := 32768.0


static func build(job: TerrainPatchJob) -> void:
	var gen := TerrainGenerator.new(job.radius, job.seed_value, job.profile if not job.profile.is_empty() else TerrainProfiles.get_profile(job.profile_id))
	var n := job.segments
	var tiles := 1 << job.level
	var size := 2.0 / float(tiles)
	var u0 := -1.0 + float(job.ix) * size
	var v0 := -1.0 + float(job.iy) * size
	var step := size / float(n)
	var g := n + 3  # cuadrícula extendida: índices -1 .. n+1

	var px := PackedFloat64Array()
	var py := PackedFloat64Array()
	var pz := PackedFloat64Array()
	var hs := PackedFloat64Array()
	px.resize(g * g)
	py.resize(g * g)
	pz.resize(g * g)
	hs.resize(g * g)
	var radius := job.radius
	for j in g:
		var v := v0 + float(j - 1) * step
		for i in g:
			var u := u0 + float(i - 1) * step
			var d := CubeSphere.face_uv_to_dir(job.face, u, v)
			var h := gen.height_at(d.x, d.y, d.z)
			var r := radius + h
			var k := j * g + i
			px[k] = d.x * r
			py[k] = d.y * r
			pz[k] = d.z * r
			hs[k] = h

	# Centro = vértice central de la cuadrícula interior.
	var ck := (n / 2 + 1) * g + (n / 2 + 1)
	var cx := px[ck]
	var cy := py[ck]
	var cz := pz[ck]
	job.center = DVec3.new(cx, cy, cz)

	var vcount := (n + 1) * (n + 1)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uv := PackedVector2Array()
	verts.resize(vcount)
	norms.resize(vcount)
	cols.resize(vcount)
	uv.resize(vcount)

	var face_edge := CubeSphere.face_edge_length(radius)
	var tiles_per_unit := face_edge * 0.5 / job.tile_m  # teselas por unidad de u
	# UV relativas al parche: se resta un entero múltiplo de UV_BASE_STEP (la textura se repite
	# con periodo 1 y el shader también muestrea a UV/8), así son continuas entre parches sin
	# saltos de periodo dentro de un cuadro. Parches enormes (lejanos) no llevan detalle.
	var base_u := floorf((u0 + 1.0) * tiles_per_unit / UV_BASE_STEP) * UV_BASE_STEP
	var base_v := floorf((v0 + 1.0) * tiles_per_unit / UV_BASE_STEP) * UV_BASE_STEP
	var uv_enabled := size * tiles_per_unit < UV_MAX_RANGE
	var min_h := INF
	var max_h := -INF
	var bound2 := 0.0
	for j in n + 1:
		for i in n + 1:
			var k := (j + 1) * g + (i + 1)
			var lx := px[k] - cx
			var ly := py[k] - cy
			var lz := pz[k] - cz
			var vi := j * (n + 1) + i
			verts[vi] = Vector3(lx, ly, lz)
			bound2 = maxf(bound2, lx * lx + ly * ly + lz * lz)
			# Normal: diferencias centradas en doble precisión.
			var kr := k + 1
			var kl := k - 1
			var ku := k + g
			var kd := k - g
			var ax := px[kr] - px[kl]
			var ay := py[kr] - py[kl]
			var az := pz[kr] - pz[kl]
			var bx := px[ku] - px[kd]
			var by := py[ku] - py[kd]
			var bz := pz[ku] - pz[kd]
			var nx := ay * bz - az * by
			var ny := az * bx - ax * bz
			var nz := ax * by - ay * bx
			var nl := sqrt(nx * nx + ny * ny + nz * nz)
			var rl := sqrt(px[k] * px[k] + py[k] * py[k] + pz[k] * pz[k])
			var dx := px[k] / rl
			var dy := py[k] / rl
			var dz := pz[k] / rl
			if nl > 0.0:
				nx /= nl
				ny /= nl
				nz /= nl
			else:
				nx = dx
				ny = dy
				nz = dz
			norms[vi] = Vector3(nx, ny, nz)
			var h := hs[k]
			min_h = minf(min_h, h)
			max_h = maxf(max_h, h)
			var col := gen.color_at(dx, dy, dz, h, nx * dx + ny * dy + nz * dz)
			col.a = 1.0 if uv_enabled else 0.0  # alfa = detalle activo (lo lee el shader)
			cols[vi] = col
			if uv_enabled:
				var gu := (u0 + float(i) * step + 1.0) * tiles_per_unit - base_u
				var gv := (v0 + float(j) * step + 1.0) * tiles_per_unit - base_v
				uv[vi] = Vector2(gu, gv)

	# Índices de la cuadrícula. Godot usa sentido horario para las caras frontales:
	# con (u→derecha, v→arriba) vistos desde fuera, (i,j) → (i,j+1) → (i+1,j+1) es horario.
	var idx := PackedInt32Array()
	idx.resize(n * n * 6)
	var w := 0
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			var b := (j + 1) * (n + 1) + i
			var c := b + 1
			var d2 := a + 1
			idx[w] = a; idx[w + 1] = b; idx[w + 2] = c
			idx[w + 3] = a; idx[w + 4] = c; idx[w + 5] = d2
			w += 6

	if job.build_collision:
		var faces := PackedVector3Array()
		faces.resize(idx.size())
		for t in idx.size():
			faces[t] = verts[idx[t]]
		job.collision_faces = faces

	# Faldones: copia de cada vértice del borde hundida radialmente; quads de doble cara.
	var skirt_depth := CubeSphere.patch_edge_length(radius, job.level) / float(n) * 1.5 + 2.0
	var border := _border_indices(n)
	var first_skirt := verts.size()
	for bi in border:
		var p := verts[bi]
		var abs_x := float(p.x) + cx
		var abs_y := float(p.y) + cy
		var abs_z := float(p.z) + cz
		var rl2 := sqrt(abs_x * abs_x + abs_y * abs_y + abs_z * abs_z)
		var down := Vector3(abs_x / rl2, abs_y / rl2, abs_z / rl2) * skirt_depth
		verts.append(p - down)
		norms.append(norms[bi])
		cols.append(cols[bi])
		uv.append(uv[bi])
	var bc := border.size()
	for s in bc:
		var s2 := (s + 1) % bc
		var top_a: int = border[s]
		var top_b: int = border[s2]
		var bot_a := first_skirt + s
		var bot_b := first_skirt + s2
		idx.append_array([top_a, bot_a, top_b, top_b, bot_a, bot_b])
		idx.append_array([top_a, top_b, bot_a, top_b, bot_b, bot_a])

	if job.rock_count > 0:
		_scatter_rocks(job, gen, u0, v0, size)

	job.vertices = verts
	job.normals = norms
	job.colors = cols
	job.uvs = uv
	job.indices = idx
	job.bound_radius = sqrt(bound2)
	job.min_height = min_h
	job.max_height = max_h


## Rocas deterministas: posición, tamaño y orientación dependen sólo de (semilla, cara, nivel, i, j).
## Se apoyan sobre la altura analítica y se hunden un 30 % para tapar la diferencia con la malla.
static func _scatter_rocks(job: TerrainPatchJob, gen: TerrainGenerator, u0: float, v0: float, size: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([job.seed_value, job.face, job.level, job.ix, job.iy])
	var out: Array[Transform3D] = []
	for k in job.rock_count:
		var d := CubeSphere.face_uv_to_dir(job.face, u0 + rng.randf() * size, v0 + rng.randf() * size)
		if gen.on_pad(d.x, d.y, d.z, 20.0):
			continue   # explanada de la base: sin rocas
		var h := gen.height_at(d.x, d.y, d.z)
		var s := 0.12 + pow(rng.randf(), 5.0) * 1.8  # mayoría pequeñas, alguna roca grande
		var up := d.to_vector3()
		var p := d.mul(job.radius + h - s * 0.3).sub(job.center).to_vector3()
		var tangent := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
		var basis := Basis(tangent, up, tangent.cross(up)).rotated(up, rng.randf() * TAU)
		basis = basis.scaled_local(Vector3(s * rng.randf_range(0.8, 1.3), s * rng.randf_range(0.45, 0.8), s))
		out.append(Transform3D(basis, p))
	job.rock_transforms = out


## Índices de los vértices del borde en orden circular.
static func _border_indices(n: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var row := n + 1
	for i in n:
		out.append(i)                       # borde inferior (j = 0)
	for j in n:
		out.append(j * row + n)             # borde derecho (i = n)
	for i in range(n, 0, -1):
		out.append(n * row + i)             # borde superior (j = n)
	for j in range(n, 0, -1):
		out.append(j * row)                 # borde izquierdo (i = 0)
	return out


static func to_array_mesh(job: TerrainPatchJob) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = job.vertices
	arrays[Mesh.ARRAY_NORMAL] = job.normals
	arrays[Mesh.ARRAY_COLOR] = job.colors
	arrays[Mesh.ARRAY_TEX_UV] = job.uvs
	arrays[Mesh.ARRAY_INDEX] = job.indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
