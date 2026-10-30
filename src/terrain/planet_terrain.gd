class_name PlanetTerrain
extends Node3D
## Terreno planetario explorable: cubo esferizado + quadtree por cara (ADR-004).
##
## - El foco (cámara/jugador) se indica en el marco BF con `set_focus()`.
## - Los parches se generan en WorkerThreadPool; la malla y la colisión se crean aquí, en el hilo
##   principal, con un presupuesto de parches por fotograma.
## - Cada parche guarda su centro en DVec3; su posición local se recalcula tras cada recentrado
##   del origen flotante, sin acumular error.
## - Este nodo debe permanecer en el origen del motor con transformación identidad.
## - Carga rápida a gran velocidad (ADR-020): descenso especulativo (se piden a la vez los parches de
##   todos los niveles que harán falta, sin esperar a que el padre esté generado), prioridad por
##   importancia (distancia / tamaño), anticipación según la velocidad del foco, más trabajos y más
##   mallas por fotograma cuando hay cola (con límite de tiempo) y caché de parches ya construidos.

signal stats_changed

const TARGET_FINEST_EDGE_M := 32.0
const MERGE_HYSTERESIS := 1.25
const COLLISION_RADIUS_M := 120.0
const COLLISION_LEVELS := 4  ## sólo los 4+1 niveles más finos tienen colisión de malla
const COLLISION_LAYER := 1
const SCATTER_LEVELS_ABOVE_MAX := 2   ## las rocas viven en parches de nivel max_level − 2
const SCATTER_RADIUS_M := 160.0
const ROCK_COLLISION_MIN_SIZE := 0.7  ## rocas mayores que esto (m) tienen colisión
const LOOKAHEAD_S := 1.5              ## s de anticipación según la velocidad del foco
const LOOKAHEAD_MAX_M := 30000.0
const MESH_BUDGET_USEC := 3000        ## tiempo máximo por fotograma creando mallas con cola grande
const CACHE_SIZE := 600               ## parches generados que se guardan tras fusionar (reaparición inmediata)
const FAR_RADII := 30.0                ## más lejos, la malla se oculta y el cielo dibuja el cuerpo (ADR-027)
const MAX_SPECULATIVE := 4            ## niveles que se piden por delante del último antepasado generado

var body: BodyDef
var radius: float
var seed_value: int
var profile_id: String
var profile: Dictionary
var segments: int = 16
var split_factor: float = 2.0
var max_jobs: int = 3
var meshes_per_frame: int = 4
var max_level: int
var material: Material
var scatter_level: int
var rocks_per_patch: int = 0
var rock_mesh: Mesh
var rock_material: Material

var generator: TerrainGenerator  # instancia del hilo principal (consultas de altura)
var solid := true               ## false: gigante gaseoso, Sol o Tierra destruida (sin malla ni suelo)
var core_depth_fraction := 0.9  ## sin suelo: "fondo" inalcanzable a esta fracción del radio bajo la referencia
var roots: Array = []
var focus: DVec3 = DVec3.new()

var _running: Array = []      # TerrainQuadNode con tarea en curso (incluye descartados)
var _ready_queue: Array = []  # nodos con trabajo terminado, pendientes de crear malla
var _wanted: Array = []       # nodos EMPTY solicitados en esta pasada
var _draw_list: Array = []   # nodos a dibujar en la pasada actual
var _drawn_prev: Array = []  # nodos dibujados en la pasada anterior
var _draw_epoch := 0
var _wanted_dirty := false
var _tree_dirty := true
var _last_focus := DVec3.new(INF, INF, INF)
var focus_ahead: DVec3 = DVec3.new()   ## foco anticipado (foco + velocidad × LOOKAHEAD_S)
var focus2: DVec3 = null                ## segundo foco: el jugador 2 en el cooperativo local (ADR-032)
var _focus2_f := Vector3.ZERO
var _last_focus2 := DVec3.new(INF, INF, INF)
var focus_velocity := Vector3.ZERO
var _focus_prev: DVec3 = null
var _focus_f := Vector3.ZERO
var _ahead_f := Vector3.ZERO
var _use_ahead := false
var _focus_prev_usec := 0
var _cache := {}                       ## clave de parche -> TerrainPatchJob terminado
var _cache_order: Array = []
var stat_cache_hits := 0

# Estadísticas
var stat_nodes := 0
var stat_drawn := 0
var stat_colliders := 0
var stat_deepest := 0
var stat_jobs_done := 0
var stat_job_usec_avg := 0.0
# Perfilado acumulado del hilo principal (µs)
var prof_frames := 0
var prof_update_usec := 0
var prof_mesh_usec := 0
var prof_collision_usec := 0
var prof_collect_usec := 0


func setup(p_body: BodyDef, p_segments: int, p_split_factor: float, p_max_jobs: int) -> void:
	body = p_body
	radius = body.radius_m()
	solid = body.has_solid_surface()
	if not solid:
		max_level = 0
		return
	seed_value = body.terrain_seed()
	profile_id = body.terrain_profile()
	profile = TerrainProfiles.for_body(body)
	if body.id == "moon":
		# Explanada bajo la base LF-01 (ADR-043): el terreno sigue siendo procedural, sólo se aplana ahí.
		profile = profile.duplicate()
		profile["pads"] = [BaseLayout.terrain_pad()]
	segments = p_segments
	split_factor = p_split_factor
	max_jobs = maxi(1, p_max_jobs)
	max_level = CubeSphere.max_level_for(radius, TARGET_FINEST_EDGE_M * float(segments) / 16.0)
	generator = TerrainGenerator.new(radius, seed_value, profile)
	material = _make_material()
	scatter_level = maxi(0, max_level - SCATTER_LEVELS_ABOVE_MAX)
	var patch_area := pow(CubeSphere.patch_edge_length(radius, scatter_level), 2.0)
	rocks_per_patch = clampi(int(patch_area * float(profile.get("rock_density", 0.0))), 0, 400)
	rock_mesh = _make_rock_mesh()
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = (profile["colors"]["slope"] as Color).darkened(0.15)
	rmat.roughness = 1.0
	rock_material = rmat
	for f in CubeSphere.FACE_COUNT:
		roots.append(TerrainQuadNode.new(f, 0, 0, 0, radius))


func _ready() -> void:
	FloatingOrigin.origin_shifted.connect(_on_origin_shifted)


func _exit_tree() -> void:
	# Las tareas del pool deben esperarse siempre.
	for n in _running:
		WorkerThreadPool.wait_for_task_completion(n.task_id)
	_running.clear()


func set_focus(p_bf: DVec3) -> void:
	focus = p_bf
	if not solid:
		return
	visible = p_bf.length() < radius * FAR_RADII
	var now := Time.get_ticks_usec()
	if _focus_prev != null and now > _focus_prev_usec:
		var dt := float(now - _focus_prev_usec) / 1.0e6
		var v := p_bf.sub(_focus_prev).to_vector3() / maxf(dt, 1e-3)
		if v.length() > 1.0e7:
			v = Vector3.ZERO  # salto (teletransporte), no velocidad
		focus_velocity = focus_velocity.lerp(v, 1.0 - exp(-4.0 * dt))
	_focus_prev = p_bf.copy()
	_focus_prev_usec = now
	var ahead := focus_velocity * LOOKAHEAD_S
	if focus_velocity.length() < 30.0:
		ahead = Vector3.ZERO
	focus_ahead = p_bf.add_vector3(ahead.limit_length(LOOKAHEAD_MAX_M))
	_focus_f = p_bf.to_vector3()
	_ahead_f = focus_ahead.to_vector3()
	_use_ahead = ahead != Vector3.ZERO
	if focus.distance_to(_last_focus) > 0.5:
		_tree_dirty = true


## Segundo foco (o null): el terreno se refina y tiene colisión también alrededor del jugador 2.
func set_secondary_focus(p_bf: DVec3) -> void:
	focus2 = p_bf
	if p_bf == null:
		return
	_focus2_f = p_bf.to_vector3()
	if p_bf.distance_to(_last_focus2) > 0.5:
		_last_focus2 = p_bf.copy()
		_tree_dirty = true


## Distancia de importancia (32 bits): la menor al foco, al foco anticipado y al segundo foco.
func _focus_dist(n: TerrainQuadNode) -> float:
	var d := n.cf.distance_to(_focus_f)
	if _use_ahead:
		d = minf(d, n.cf.distance_to(_ahead_f))
	if focus2 != null:
		d = minf(d, n.cf.distance_to(_focus2_f))
	return d


## Distancia real a los jugadores (sin anticipación): colisión y rocas.
func _near_dist(n: TerrainQuadNode) -> float:
	var d := n.cf.distance_to(_focus_f)
	if focus2 != null:
		d = minf(d, n.cf.distance_to(_focus2_f))
	return d


## Altura analítica (m) sobre el radio medio en una dirección. Hilo principal.
func height_at_dir(dir: DVec3) -> float:
	if not solid:
		return -radius * core_depth_fraction
	var d := dir.normalized()
	return generator.height_at(d.x, d.y, d.z)


## Radio del suelo (m desde el centro) bajo la posición BF dada.
func ground_radius_at(p_bf: DVec3) -> float:
	return radius + height_at_dir(p_bf)


func max_elevation() -> float:
	return generator.max_elevation if solid else 0.0


## True cuando el área alrededor del foco está generada al nivel máximo y tiene colisión.
func is_ready_at_focus() -> bool:
	if not solid:
		return true
	return stat_colliders > 0 and _running.is_empty() and _ready_queue.is_empty() and not _tree_dirty


func profile_text() -> String:
	var f := maxf(1.0, float(prof_frames))
	return "fotogramas %d · por fotograma: recoger %.2f ms, mallas %.2f ms, árbol+despacho %.2f ms (colisión %.2f ms) · trabajos %d" % [
		prof_frames, prof_collect_usec / f / 1000.0, prof_mesh_usec / f / 1000.0,
		prof_update_usec / f / 1000.0, prof_collision_usec / f / 1000.0, stat_jobs_done]


func pending_count() -> int:
	return _running.size() + _ready_queue.size()


var last_process_usec := 0


func _process(_delta: float) -> void:
	if not solid:
		return
	var _tp := Time.get_ticks_usec()
	_process_inner()
	last_process_usec = Time.get_ticks_usec() - _tp


func _process_inner() -> void:
	prof_frames += 1
	var t0 := Time.get_ticks_usec()
	_collect_finished()
	var t1 := Time.get_ticks_usec()
	var created := _create_meshes()
	var t2 := Time.get_ticks_usec()
	prof_collect_usec += t1 - t0
	prof_mesh_usec += t2 - t1
	if created > 0:
		_tree_dirty = true
	if _tree_dirty:
		_tree_dirty = false
		_last_focus = focus.copy()
		_wanted.clear()
		_wanted_dirty = true
		_draw_list.clear()
		stat_nodes = 0
		for r in roots:
			_update_node(r)
		_apply_draw_list()
		prof_update_usec += Time.get_ticks_usec() - t2
		stats_changed.emit()
	_dispatch()


# --- Quadtree ---------------------------------------------------------------

## Recorre el subárbol sin efectos visibles: decide qué nodos se dibujan (en `_draw_list`).
## Devuelve true si el área del nodo queda cubierta.
func _update_node(n: TerrainQuadNode, spec: int = 0) -> bool:
	stat_nodes += 1
	var d := _focus_dist(n)
	var split_d := split_factor * n.edge_m
	var want_split := n.level < max_level and d < split_d
	if n.state != TerrainQuadNode.State.READY:
		if n.state == TerrainQuadNode.State.EMPTY:
			n.priority = d / n.edge_m
			_request(n)
		# Descenso especulativo: si este nodo se va a dividir, se piden ya sus hijos (y así hasta el
		# nivel necesario) en lugar de esperar a que él esté generado. Si todos los hijos quedan
		# listos, cubren el área aunque el padre no exista todavía.
		if not want_split and not n.is_leaf() and d > split_d * MERGE_HYSTERESIS:
			_free_children(n)
		if (not want_split or spec >= MAX_SPECULATIVE) and n.is_leaf():
			return false
		if n.is_leaf():
			_make_children(n)
		var mark := _draw_list.size()
		var covered := true
		for c in n.children:
			covered = _update_node(c, spec + 1) and covered
		if covered:
			return true
		_draw_list.resize(mark)
		return false
	if n.level == scatter_level:
		_update_scatter(n, _near_dist(n))
	if not n.is_leaf() and not want_split and d > split_d * MERGE_HYSTERESIS:
		_free_children(n)
	elif not n.is_leaf():
		want_split = true  # banda de histéresis: mantener la división
	if want_split:
		if n.is_leaf():
			_make_children(n)
		var mark := _draw_list.size()
		var covered := true
		for c in n.children:
			covered = _update_node(c) and covered
		if covered:
			return true
		_draw_list.resize(mark)  # algún hijo no está listo: se dibuja el padre entero
	_draw_list.append(n)
	return true


func _make_children(n: TerrainQuadNode) -> void:
	var cl := n.level + 1
	for c in 4:
		n.children.append(TerrainQuadNode.new(n.face, cl, n.ix * 2 + (c & 1), n.iy * 2 + (c >> 1), radius))


## Pide un parche: si está en la caché se reutiliza al instante; si no, se pone en cola.
func _request(n: TerrainQuadNode) -> void:
	var key := _key(n)
	if _cache.has(key):
		n.job = _cache[key]
		_cache.erase(key)
		_cache_order.erase(key)
		n.state = TerrainQuadNode.State.PENDING
		_ready_queue.push_front(n)
		stat_cache_hits += 1
		return
	_wanted.append(n)


static func _key(n: TerrainQuadNode) -> int:
	return (n.face << 58) | (n.level << 52) | (n.ix << 26) | n.iy


## Aplica la diferencia entre el conjunto dibujado anterior y el nuevo (visibilidad y colisión).
func _apply_draw_list() -> void:
	_draw_epoch += 1
	for n in _draw_list:
		n.draw_epoch = _draw_epoch
	for n in _drawn_prev:
		if n.draw_epoch != _draw_epoch:
			n.drawn = false
			if n.mesh_instance != null:
				n.mesh_instance.visible = false
			_set_collision(n, false)
	stat_drawn = _draw_list.size()
	stat_deepest = 0
	var min_collision_level := max_level - COLLISION_LEVELS
	for n in _draw_list:
		n.drawn = true
		n.mesh_instance.visible = true
		stat_deepest = maxi(stat_deepest, n.level)
		_set_collision(n, n.level >= min_collision_level and _near_dist(n) - n.bound_radius < COLLISION_RADIUS_M)
	_drawn_prev = _draw_list.duplicate()


func _free_children(n: TerrainQuadNode) -> void:
	for c in n.children:
		_free_children(c)
		_release(c)
	n.children.clear()


func _release(n: TerrainQuadNode) -> void:
	n.released = true
	if n.state == TerrainQuadNode.State.READY and n.mesh_instance != null and n.level >= 6:
		_cache_store(n)
	if n.scatter != null:
		n.scatter.queue_free()
		n.scatter = null
	_set_collision(n, false)
	if n.mesh_instance != null:
		n.mesh_instance.queue_free()
		n.mesh_instance = null
	n.collision_faces = PackedVector3Array()
	if n.state == TerrainQuadNode.State.PENDING:
		n.job = null  # la tarea sigue en _running; su resultado se descartará
	n.state = TerrainQuadNode.State.EMPTY
	_ready_queue.erase(n)
	n.drawn = false


## Guarda lo generado de un parche que se fusiona (para no regenerarlo si se vuelve enseguida).
func _cache_store(n: TerrainQuadNode) -> void:
	var job := TerrainPatchJob.new()
	job.face = n.face
	job.level = n.level
	job.ix = n.ix
	job.iy = n.iy
	job.center = n.center
	job.bound_radius = n.bound_radius
	job.collision_faces = n.collision_faces
	job.rock_transforms = n.rock_transforms
	job.cached_mesh = n.mesh_instance.mesh
	var key := _key(n)
	if not _cache.has(key):
		_cache_order.append(key)
	_cache[key] = job
	while _cache_order.size() > CACHE_SIZE:
		_cache.erase(_cache_order.pop_front())


func _set_collision(n: TerrainQuadNode, want: bool) -> void:
	if want and n.collider == null and not n.collision_faces.is_empty() and n.mesh_instance != null:
		var tc := Time.get_ticks_usec()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(n.collision_faces)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		var sb := StaticBody3D.new()
		sb.collision_layer = COLLISION_LAYER
		sb.collision_mask = 0
		sb.add_child(cs)
		n.mesh_instance.add_child(sb)
		n.collider = sb
		stat_colliders += 1
		prof_collision_usec += Time.get_ticks_usec() - tc
	elif not want and n.collider != null:
		n.collider.queue_free()
		n.collider = null
		stat_colliders -= 1


# --- Rocas ------------------------------------------------------------------

## Zonas sin rocas añadidas en juego (bases del NEXUS, ronda 12): [centro BF, radio m]. Se filtran al instanciar las
## rocas (hilo principal); las que ya estaban a la vista se rehacen.
var rock_exclusions: Array = []


func exclude_rocks(center_bf: DVec3, radius_m: float) -> void:
	rock_exclusions.append([center_bf, radius_m])
	for r in roots:
		_drop_scatter(r)


func _drop_scatter(n: TerrainQuadNode) -> void:
	if n.scatter != null:
		n.scatter.queue_free()
		n.scatter = null
	for c in n.children:
		_drop_scatter(c)


func _rocks_kept(n: TerrainQuadNode) -> Array:
	if rock_exclusions.is_empty():
		return n.rock_transforms
	var near: Array = []
	for e in rock_exclusions:
		if (e[0] as DVec3).distance_to(n.center) < float(e[1]) + n.edge_m * 1.5:
			near.append([(e[0] as DVec3).sub(n.center).to_vector3(), float(e[1])])
	if near.is_empty():
		return n.rock_transforms
	var out: Array = []
	for t: Transform3D in n.rock_transforms:
		var keep := true
		for e in near:
			if t.origin.distance_to(e[0]) < float(e[1]):
				keep = false
				break
		if keep:
			out.append(t)
	return out


func _update_scatter(n: TerrainQuadNode, dist: float) -> void:
	var want := dist < SCATTER_RADIUS_M + n.edge_m
	if want and n.scatter == null and not n.rock_transforms.is_empty():
		var rocks := _rocks_kept(n)
		var root := Node3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = rock_mesh
		mm.instance_count = rocks.size()
		var body: StaticBody3D = null
		for i in rocks.size():
			var t: Transform3D = rocks[i]
			mm.set_instance_transform(i, t)
			var size := t.basis.z.length()
			if size >= ROCK_COLLISION_MIN_SIZE:
				if body == null:
					body = StaticBody3D.new()
					body.collision_layer = COLLISION_LAYER
					body.collision_mask = 0
					root.add_child(body)
				var cs := CollisionShape3D.new()
				var sph := SphereShape3D.new()
				sph.radius = size * 0.32
				cs.shape = sph
				cs.position = t.origin + t.basis.y.normalized() * size * 0.12
				body.add_child(cs)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = rock_material
		root.add_child(mmi)
		add_child(root)
		root.position = FloatingOrigin.to_local(n.center)
		n.scatter = root
	elif not want and n.scatter != null and dist > (SCATTER_RADIUS_M + n.edge_m) * 1.2:
		n.scatter.queue_free()
		n.scatter = null


## Roca facetada de diámetro ≈ 1 m: esfera de baja resolución con desplazamiento determinista.
func _make_rock_mesh() -> Mesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 7
	sphere.rings = 4
	var arrays := sphere.get_mesh_arrays()
	var src: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 1.6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in idx:
		var v: Vector3 = src[i]
		st.add_vertex(v * (1.0 + 0.35 * noise.get_noise_3dv(v.snapped(Vector3.ONE * 0.001))))
	st.generate_normals()
	return st.commit()


# --- Trabajos en hilos ------------------------------------------------------

func _dispatch() -> void:
	# Con mucha cola (llegada rápida) se usan todos los núcleos menos uno.
	var jobs := max_jobs
	if _wanted.size() > 6:
		jobs = maxi(max_jobs, OS.get_processor_count() - 1)
	if _wanted.is_empty() or _running.size() >= jobs:
		return
	if _wanted_dirty:
		# Importancia: primero lo grande y cercano (distancia relativa al tamaño del parche), así se
		# cubre antes el área visible y el detalle bajo el foco llega sin esperar a niveles intermedios.
		_wanted.sort_custom(func(a: TerrainQuadNode, b: TerrainQuadNode) -> bool: return a.priority < b.priority)
		_wanted_dirty = false
	while not _wanted.is_empty() and _running.size() < jobs:
		var n: TerrainQuadNode = _wanted.pop_front()
		if n.released or n.state != TerrainQuadNode.State.EMPTY:
			continue
		var job := TerrainPatchJob.new()
		job.face = n.face
		job.level = n.level
		job.ix = n.ix
		job.iy = n.iy
		job.segments = segments
		job.radius = radius
		job.seed_value = seed_value
		job.profile_id = profile_id
		job.profile = profile
		job.rock_count = rocks_per_patch if n.level == scatter_level else 0
		n.job = job
		n.state = TerrainQuadNode.State.PENDING
		# Alta prioridad: las tareas de baja prioridad sólo usan una fracción de los hilos
		# (threading/worker_pool/low_priority_thread_ratio).
		n.task_id = WorkerThreadPool.add_task(job.run, true, "terrain patch")
		_running.append(n)


func _collect_finished() -> void:
	var i := 0
	while i < _running.size():
		var n: TerrainQuadNode = _running[i]
		if WorkerThreadPool.is_task_completed(n.task_id):
			WorkerThreadPool.wait_for_task_completion(n.task_id)
			_running.remove_at(i)
			var job := n.job
			n.task_id = -1
			if job == null or n.released or n.state != TerrainQuadNode.State.PENDING:
				continue  # descartado mientras se generaba
			_ready_queue.append(n)
			stat_jobs_done += 1
			stat_job_usec_avg = lerpf(stat_job_usec_avg, float(job.elapsed_usec), 0.1)
			_tree_dirty = true
		else:
			i += 1


func _create_meshes() -> int:
	var count := 0
	var t0 := Time.get_ticks_usec()
	# Presupuesto: `meshes_per_frame` como mínimo; con cola, todas las que quepan en MESH_BUDGET_USEC.
	while not _ready_queue.is_empty() and (count < meshes_per_frame or Time.get_ticks_usec() - t0 < MESH_BUDGET_USEC):
		var n: TerrainQuadNode = _ready_queue.pop_front()
		var job := n.job
		if job == null or n.released:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = job.cached_mesh if job.cached_mesh != null else TerrainPatchBuilder.to_array_mesh(job)
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if n.level < max_level - 6 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.visible = false
		add_child(mi)
		mi.position = FloatingOrigin.to_local(job.center)
		n.mesh_instance = mi
		n.center = job.center
		n.cf = job.center.to_vector3()
		n.bound_radius = job.bound_radius
		n.collision_faces = job.collision_faces
		n.rock_transforms = job.rock_transforms
		n.job = null
		n.state = TerrainQuadNode.State.READY
		count += 1
	return count


func _on_origin_shifted(_delta: Vector3) -> void:
	for r in roots:
		_reposition(r)


func _reposition(n: TerrainQuadNode) -> void:
	if n.mesh_instance != null:
		n.mesh_instance.position = FloatingOrigin.to_local(n.center)
	if n.scatter != null:
		n.scatter.position = FloatingOrigin.to_local(n.center)
	for c in n.children:
		_reposition(c)


# --- Material -----------------------------------------------------------------

func _make_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/terrain/terrain.gdshader")
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.noise = noise
	mat.set_shader_parameter("detail_tex", tex)
	return mat
