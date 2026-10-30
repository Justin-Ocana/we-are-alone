extends TestCase
## Terreno: proyección, determinismo, continuidad entre parches y escala (ADR-004).

const R := 6.0e6


func _gen(seed_value: int = 424242, profile: String = "arid_rocky") -> TerrainGenerator:
	return TerrainGenerator.new(R, seed_value, TerrainProfiles.get_profile(profile))


func test_cube_sphere_points_are_unit() -> void:
	for f in 6:
		for u in [-1.0, -0.3, 0.0, 0.77, 1.0]:
			for v in [-1.0, 0.25, 1.0]:
				assert_near(CubeSphere.face_uv_to_dir(f, u, v).length(), 1.0, 1e-12, "cara %d" % f)


func test_cube_faces_are_right_handed() -> void:
	for f in 6:
		var n := CubeSphere.AXIS_U[f].cross(CubeSphere.AXIS_V[f])
		assert_true(n.is_equal_approx(CubeSphere.NORMALS[f]), "a × b = n en la cara %d" % f)


func test_cube_face_seams_match() -> void:
	# Cada punto de la arista de una cara debe coincidir con un punto de la cara vecina.
	var samples := 9
	for f in 6:
		for e in 4:
			for s in samples:
				var t := -1.0 + 2.0 * float(s) / float(samples - 1)
				var uv := [Vector2(1, t), Vector2(-1, t), Vector2(t, 1), Vector2(t, -1)][e] as Vector2
				var p := CubeSphere.face_uv_to_dir(f, uv.x, uv.y)
				var found := false
				for g in 6:
					if g == f:
						continue
					var n := CubeSphere.NORMALS[g]
					var a := CubeSphere.AXIS_U[g]
					var b := CubeSphere.AXIS_V[g]
					# La arista común está en el plano del cubo de la cara g: invertir la proyección
					# buscando por fuerza bruta sobre la arista de g.
					for e2 in 4:
						for s2 in samples:
							var t2 := -1.0 + 2.0 * float(s2) / float(samples - 1)
							var uv2 := [Vector2(1, t2), Vector2(-1, t2), Vector2(t2, 1), Vector2(t2, -1)][e2] as Vector2
							if CubeSphere.face_uv_to_dir(g, uv2.x, uv2.y).is_equal_approx_tol(p, 1e-12):
								found = true
				assert_true(found, "punto de arista de la cara %d sin pareja" % f)


func test_height_is_deterministic() -> void:
	var a := _gen()
	var b := _gen()
	var d := CubeSphere.latlon_to_dir(12.3, 45.6)
	assert_eq(a.height_at(d.x, d.y, d.z), b.height_at(d.x, d.y, d.z), "misma semilla → misma altura")
	var c := _gen(7)
	assert_true(a.height_at(d.x, d.y, d.z) != c.height_at(d.x, d.y, d.z), "otra semilla → otra altura")


func test_height_within_profile_bounds() -> void:
	var g := _gen()
	var max_e := g.max_elevation + 1000.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 400:
		var d := CubeSphere.latlon_to_dir(rng.randf_range(-90, 90), rng.randf_range(-180, 180))
		var h := g.height_at(d.x, d.y, d.z)
		assert_true(absf(h) < max_e, "altura %.1f fuera de rango" % h)


func test_height_is_continuous_at_metre_scale() -> void:
	# Dos puntos a ~1 m no pueden diferir decenas de metros (sin acantilados espurios).
	var g := _gen(1737400, "cratered_airless")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var radius := 1737400.0
	g = TerrainGenerator.new(radius, 1737400, TerrainProfiles.get_profile("cratered_airless"))
	for i in 300:
		var d := CubeSphere.latlon_to_dir(rng.randf_range(-80, 80), rng.randf_range(-180, 180))
		var e := DVec3.new(d.x + 1.0 / radius, d.y, d.z).normalized()
		var dh := absf(g.height_at(d.x, d.y, d.z) - g.height_at(e.x, e.y, e.z))
		assert_true(dh < 3.0, "salto de %.2f m en 1 m" % dh)


func test_max_level_reaches_target_resolution() -> void:
	var lvl := CubeSphere.max_level_for(R, 32.0)
	assert_true(CubeSphere.patch_edge_length(R, lvl) <= 32.0, "arista del parche más fino ≤ 32 m")
	assert_true(CubeSphere.patch_edge_length(R, lvl - 1) > 32.0, "nivel mínimo suficiente")
	assert_eq(lvl, 19, "nivel máximo para R = 6.000 km")


func _build(face: int, level: int, ix: int, iy: int) -> TerrainPatchJob:
	var job := TerrainPatchJob.new()
	job.face = face
	job.level = level
	job.ix = ix
	job.iy = iy
	job.segments = 8
	job.radius = R
	job.seed_value = 424242
	job.profile_id = "arid_rocky"
	job.run()
	return job


func test_neighbour_patches_share_edge_vertices() -> void:
	# Parches vecinos del mismo nivel deben tener exactamente los mismos vértices en su borde
	# (en coordenadas BF), es decir, sin grietas. Nivel profundo: cerca de la escala humana.
	var lvl := 14
	var a := _build(4, lvl, 8000, 8000)
	var b := _build(4, lvl, 8001, 8000)  # vecino en +u
	var n := 8
	var max_err := 0.0
	for j in n + 1:
		var va := a.vertices[j * (n + 1) + n]  # borde derecho de a
		var vb := b.vertices[j * (n + 1)]      # borde izquierdo de b
		var pa := a.center.add_vector3(va)
		var pb := b.center.add_vector3(vb)
		max_err = maxf(max_err, pa.distance_to(pb))
	assert_true(max_err < 0.005, "error máximo en el borde común %.4f m" % max_err)


func test_patch_vertices_are_relative_and_small() -> void:
	var job := _build(2, 16, 30000, 12345)
	assert_true(job.center.length() > R * 0.99, "centro sobre la superficie")
	assert_true(job.bound_radius < 400.0, "vértices relativos al centro (radio %.1f m)" % job.bound_radius)
	assert_eq(job.collision_faces.size(), 8 * 8 * 6, "caras de colisión de la cuadrícula interior")


func test_patch_winding_faces_outward() -> void:
	# Con el orden horario de Godot, la normal geométrica de (a,b,c) es (c−a)×(b−a); debe apuntar hacia fuera.
	var job := _build(0, 10, 300, 600)
	var out := job.center.normalized().to_vector3()
	var i0 := job.vertices[job.indices[0]]
	var i1 := job.vertices[job.indices[1]]
	var i2 := job.vertices[job.indices[2]]
	var geo_n := (i2 - i0).cross(i1 - i0)
	assert_true(geo_n.dot(out) > 0.0, "el triángulo debe ser frontal visto desde fuera")
	assert_true(job.normals[0].dot(out) > 0.5, "normal de vértice hacia fuera")
