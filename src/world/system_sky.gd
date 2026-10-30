class_name SystemSky
extends RefCounted
## Prepara cada fotograma los cuerpos del Sistema Solar que dibuja el cielo analítico (ADR-025).
## - Todo se calcula en doble precisión relativo a la CÁMARA y se pasa al shader como dirección, radio angular,
##   radio y altitud (la altitud evita la cancelación numérica del trazado de rayos en 32 bits).
## - Selección: el Sol, los planetas, Plutón y las lunas del sistema planetario local; de las lunas menores
##   (cientos en Saturno y Júpiter) sólo las potencialmente visibles, revisadas dos veces por segundo.
## - Los cuerpos que ocupan menos de un píxel se dibujan como puntos con su magnitud aparente
##   m = −26,74 − 2,5·log10(p·(R/d)²·(1 UA/d☉)²·fase).
## - El cuerpo ancla con terreno sólido no se dibuja aquí (lo cubre la malla del terreno).

const MAX_BODIES := 24
const MAX_STORMS := 4
const MAX_RINGS := 6
const KIND := {"rocky": 0.0, "gas": 1.0, "star": 2.0, "clouded": 3.0, "shattered": 4.0}

var system: SolarSystem
var _candidates: Array = []       ## ids de lunas menores potencialmente visibles
var _cand_timer := 0.0
var _cand_planet := ""
const DEBRIS_COUNT := 28
const DEBRIS_GROUPS := 4
const DEBRIS_PER_GROUP := 7
var _shatter_axes: Array = [Vector3.UP, Vector3.BACK]   ## polo y meridiano de la Tierra en el marco del cielo
var _debris_k: Array = []          ## [fase, velocidad, radio (R), inclinación, brillo] de cada resto
var _frag_seeds: Array = []        ## [Vector4(dir, desplazamiento)]
var _frag_axes: Array = []         ## [Vector4(eje de volteo, periodo s)]
var visible_ids: Array = []        ## ids dibujados en el último fotograma (para la interfaz)


func _init(p_system: SolarSystem) -> void:
	system = p_system
	_build_fragments()


func _build_fragments() -> void:
	var earth: BodyDef = system.body("earth")
	if earth == null:
		return
	var s: Dictionary = earth.surface()
	var n := int(s.get("fragments", 11))
	var expansion := float(s.get("expansion", 1.3))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(s.get("seed", 6371000))
	var tumble: Array = s.get("tumble_period_h", [30.0, 140.0])
	# Semillas repartidas (espiral de Fibonacci con ruido) para celdas de Voronoi de tamaño parecido.
	for i in n:
		var y := 1.0 - (float(i) + 0.5) / n * 2.0
		var r := sqrt(maxf(0.0, 1.0 - y * y))
		var phi := float(i) * 2.39996 + rng.randf_range(-0.3, 0.3)
		var d := Vector3(cos(phi) * r, y, sin(phi) * r) + Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(-0.15, 0.15), rng.randf_range(-0.15, 0.15))
		_frag_seeds.append(Vector4(d.normalized().x, d.normalized().y, d.normalized().z, (expansion - 1.0) * rng.randf_range(0.7, 1.3)))
		var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		_frag_axes.append(Vector4(axis.x, axis.y, axis.z, rng.randf_range(float(tumble[0]), float(tumble[1])) * 3600.0))


## Rellena los parámetros del shader del cielo. `anchor`: cuerpo del marco; `cam_bf`: cámara en ese marco (m).
func update(mat: ShaderMaterial, anchor: String, cam_bf: DVec3, pixel_angle: float, delta: float) -> void:
	var ax: Array = system.axes(anchor)
	# Marco del cuerpo → eclíptica: las estrellas y la Vía Láctea giran con el cielo real (ADR-040).
	mat.set_shader_parameter("sky_basis", Basis((ax[0] as DVec3).to_vector3(), (ax[1] as DVec3).to_vector3(), (ax[2] as DVec3).to_vector3()))
	var cam_sys := system.position(anchor).add(Ephemeris.from_frame(ax, cam_bf))
	var sun_pos := system.position("sun")
	# Sistema planetario local: el del cuerpo dominante en la posición de la cámara (no el del ancla).
	var local_planet := system.system_planet(system.dominant_body(cam_sys, anchor))
	_refresh_candidates(local_planet, cam_sys, delta)

	var entries: Array = []
	var ids: Array = ["sun"]
	for id in system.children.get("sun", []):
		ids.append(id)
	for id in system.children.get(local_planet, []):
		var b: BodyDef = system.body(id)
		if b.kind == "moon" or id in _candidates:
			ids.append(id)
	for id in ids:
		var b: BodyDef = system.body(id)
		if b == null:
			continue
		if id == anchor and b.has_solid_surface() and cam_bf.length() < b.radius_m() * PlanetTerrain.FAR_RADII:
			continue  # cerca: lo dibuja la malla del terreno
		if id == anchor and not b.has_solid_surface() and b.surface_type() != "shattered" \
				and cam_bf.length() < b.radius_m():
			continue  # dentro de un gigante gaseoso o del Sol: lo resuelven la niebla y el color profundo
		var rel := system.position(id).sub(cam_sys)
		var dist := rel.length()
		var r := b.radius_m()
		if b.surface_type() == "shattered":
			r *= float(b.surface().get("expansion", 1.3))
		var ang := asin(clampf(r / maxf(dist, r), 0.0, 1.0))
		var brightness := 0.0
		var score := ang
		if id != "sun":
			var to_sun := sun_pos.sub(system.position(id))
			var d_sun := to_sun.length()
			var phase_cos := rel.mul(-1.0 / maxf(dist, 1.0)).dot(to_sun.mul(1.0 / maxf(d_sun, 1.0)))
			var phase := maxf(0.02, (1.0 + phase_cos) * 0.5)
			var albedo := b.physical("geometric_albedo", 0.3)
			var flux := albedo * pow(r / dist, 2.0) * pow(Ephemeris.AU / d_sun, 2.0) * phase
			var mag := -26.74 - 2.5 * log(maxf(flux, 1e-40)) / log(10.0)
			brightness = clampf(pow(10.0, -0.4 * (mag + 1.0)), 0.0, 6.0)
			score = maxf(ang / maxf(pixel_angle, 1e-6), brightness * 2.0)
			if score < 0.02:
				continue
		else:
			score = 1e9
		entries.append({"id": id, "b": b, "rel": rel, "dist": dist, "r": r, "ang": ang, "bright": brightness, "score": score})
	entries.sort_custom(func(a, c): return a["score"] > c["score"])
	if entries.size() > MAX_BODIES:
		entries.resize(MAX_BODIES)

	var dirs := PackedVector4Array()
	var geos := PackedVector4Array()
	var cols := PackedVector4Array()
	var cols2 := PackedVector4Array()
	var poles := PackedVector4Array()
	var pms := PackedVector4Array()
	var suns := PackedVector4Array()
	var atms := PackedVector4Array()
	var storm_a := PackedVector4Array()
	var storm_b := PackedVector4Array()
	var ring_body := -1
	var ring_a := PackedVector4Array()
	var ring_c := PackedVector4Array()
	var hex_body := -1.0
	var shatter := -1
	var best_ring_ang := 0.0
	visible_ids.clear()
	for i in entries.size():
		var e: Dictionary = entries[i]
		var b: BodyDef = e["b"]
		var rd: Dictionary = b.render()
		var rel: DVec3 = e["rel"]
		var dist: float = e["dist"]
		var dir := Ephemeris.to_frame(ax, rel.mul(1.0 / maxf(dist, 1.0))).to_vector3()
		var kind_name := str(rd.get("kind", "rocky"))
		var kind: float = KIND.get(kind_name, 0.0)
		visible_ids.append(e["id"])
		dirs.append(Vector4(dir.x, dir.y, dir.z, e["ang"]))
		geos.append(Vector4(e["r"], dist - float(e["r"]), b.flattening(), kind))
		var c1 := b.render_color("color")
		var c2 := b.render_color("color2", c1 * 0.8)
		cols.append(Vector4(c1.r, c1.g, c1.b, e["bright"]))
		cols2.append(Vector4(c2.r, c2.g, c2.b, float(rd.get("band_count", 10))))
		var bax: Array = system.axes(e["id"])
		var pole := Ephemeris.to_frame(ax, bax[1]).to_vector3()
		var pm := Ephemeris.to_frame(ax, bax[2]).to_vector3()
		poles.append(Vector4(pole.x, pole.y, pole.z, float(rd.get("turbulence", 0.3))))
		pms.append(Vector4(pm.x, pm.y, pm.z, float(rd.get("band_contrast", 0.4))))
		var to_sun := Ephemeris.to_frame(ax, sun_pos.sub(system.position(e["id"])).normalized()).to_vector3()
		var atm := b.atmosphere()
		var thick := 0.0
		var atm_col := Vector4(0, 0, 0, 0)
		if bool(atm.get("present", false)):
			var sky: Dictionary = atm.get("sky", {})
			var lc: Array = sky.get("space_limb", [0.6, 0.7, 1.0])
			if str(atm.get("kind", "")) == "gas_giant":
				lc = atm.get("sky_above_clouds", [0.4, 0.55, 0.8])
				thick = 0.012
			else:
				thick = clampf(float(atm.get("scale_height", {}).get("value", 10000.0)) * 6.0 / maxf(b.radius_m(), 1.0), 0.004, 0.25)
			atm_col = Vector4(lc[0], lc[1], lc[2], clampf(float(atm.get("visual_density", 0.6)) * 1.5, 0.15, 1.2))
		if rd.get("polar_caps", false):
			atm_col.w = maxf(atm_col.w, 0.6)
		suns.append(Vector4(to_sun.x, to_sun.y, to_sun.z, thick))
		atms.append(atm_col)
		for st in rd.get("storms", []):
			if storm_a.size() >= MAX_STORMS:
				break
			var lat := deg_to_rad(float(st["lat"]))
			var half_w := float(st["width_km"]) * 500.0 / b.radius_m()
			var half_h := float(st["height_km"]) * 500.0 / b.radius_m()
			var sc: Array = st["color"]
			storm_a.append(Vector4(i, lat, deg_to_rad(float(st["lon"])), half_w))
			storm_b.append(Vector4(sc[0], sc[1], sc[2], half_h))
		if rd.has("rings") and float(e["ang"]) > best_ring_ang:
			best_ring_ang = e["ang"]
			ring_body = i
			ring_a = PackedVector4Array()
			ring_c = PackedVector4Array()
			for rg in rd["rings"]:
				if ring_a.size() >= MAX_RINGS:
					break
				var rc: Array = rg["color"]
				ring_a.append(Vector4(float(rg["inner_m"]), float(rg["outer_m"]), float(rg["opacity"]), 0))
				ring_c.append(Vector4(rc[0], rc[1], rc[2], 0))
		if rd.has("hexagon"):
			hex_body = i
			var hx: Dictionary = rd["hexagon"]
			mat.set_shader_parameter("hexagon", Vector4(deg_to_rad(90.0 - float(hx["lat"])) * 1.15, 0, 0, 0))
		if kind_name == "shattered":
			shatter = i
			_update_debris(mat, dir * dist, float(e["r"]), pole, pm, pixel_angle)
			_shatter_axes = [pole, pm]
	while ring_a.size() < MAX_RINGS:
		ring_a.append(Vector4(0, 0, 0, 0))
		ring_c.append(Vector4(0, 0, 0, 0))
	_pad(dirs, MAX_BODIES)
	for arr in [geos, cols, cols2, poles, pms, suns, atms]:
		_pad(arr, MAX_BODIES)
	_pad(storm_a, MAX_STORMS)
	_pad(storm_b, MAX_STORMS)
	mat.set_shader_parameter("body_count", entries.size())
	mat.set_shader_parameter("b_dir", dirs)
	mat.set_shader_parameter("b_geo", geos)
	mat.set_shader_parameter("b_col", cols)
	mat.set_shader_parameter("b_col2", cols2)
	mat.set_shader_parameter("b_pole", poles)
	mat.set_shader_parameter("b_pm", pms)
	mat.set_shader_parameter("b_sun", suns)
	mat.set_shader_parameter("b_atm", atms)
	mat.set_shader_parameter("storm_count", 0 if OS.has_environment("SKY_NO_STORMS") else mini(storm_a.size(), MAX_STORMS))
	mat.set_shader_parameter("storm_a", storm_a)
	mat.set_shader_parameter("storm_b", storm_b)
	mat.set_shader_parameter("ring_body", ring_body)
	var outer := 0.0
	for ra in ring_a:
		outer = maxf(outer, ra.y)
	mat.set_shader_parameter("ring_outer", outer)
	mat.set_shader_parameter("ring_a", ring_a)
	mat.set_shader_parameter("ring_c", ring_c)
	mat.set_shader_parameter("hexagon_body", hex_body)
	mat.set_shader_parameter("pixel_angle", pixel_angle)
	mat.set_shader_parameter("time", fmod(system.time_s, 100000.0))
	mat.set_shader_parameter("shatter_body", shatter)
	if shatter >= 0:
		_update_fragments(mat)


## Restos en órbita de la Tierra rota (ronda 10): sus direcciones se calculan aquí (10 veces por segundo) en lugar de
## en cada píxel del halo, que con la Tierra cerca era toda la pantalla (28 órbitas con trigonometría por píxel).
func _update_debris(mat: ShaderMaterial, center: Vector3, r: float, pole: Vector3, pm: Vector3, px: float) -> void:
	if _debris_k.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 2841
		for k in DEBRIS_COUNT:
			_debris_k.append([rng.randf() * TAU, 0.0004 + 0.0006 * rng.randf(), 1.6 + 1.4 * rng.randf(),
				(rng.randf() - 0.5) * 0.9, 0.35 + 0.65 * rng.randf()])
	var east := pole.cross(pm)
	var t := fmod(system.time_s, 100000.0)
	var items := []
	for k in DEBRIS_COUNT:
		var d: Array = _debris_k[k]
		var a0: float = d[0] + t * d[1]
		var lp: Vector3 = (cos(a0) * pm + sin(a0) * (east * cos(d[3]) + pole * sin(d[3]))) * r * float(d[2])
		items.append([fposmod(a0, TAU), (center + lp).normalized(), d[4]])
	# Cuatro grupos de 7 contiguos en su órbita, cada uno con su cono envolvente: el píxel sólo recorre los grupos
	# cuyo cono le toca (antes, los 28 restos en todo el halo: ~5 ms con la Tierra cerca en la HD 630).
	items.sort_custom(func(a, b): return a[0] < b[0])
	var arr := PackedVector4Array()
	var groups := PackedVector4Array()
	var margin := px * 4.0
	for g in DEBRIS_GROUPS:
		var axis := Vector3.ZERO
		for j in DEBRIS_PER_GROUP:
			axis += items[g * DEBRIS_PER_GROUP + j][1]
		axis = axis.normalized() if axis.length_squared() > 1e-12 else Vector3.UP
		var max_a := 0.0
		for j in DEBRIS_PER_GROUP:
			var it: Array = items[g * DEBRIS_PER_GROUP + j]
			var to: Vector3 = it[1]
			max_a = maxf(max_a, axis.angle_to(to))
			arr.append(Vector4(to.x, to.y, to.z, it[2]))
		groups.append(Vector4(axis.x, axis.y, axis.z, cos(minf(max_a + margin, PI))))
	mat.set_shader_parameter("debris_dir", arr)
	mat.set_shader_parameter("debris_group", groups)
	mat.set_shader_parameter("debris_cos", cos(margin))


static func _pad(arr: PackedVector4Array, n: int) -> void:
	while arr.size() < n:
		arr.append(Vector4(0, 0, 0, 0))


func _update_fragments(mat: ShaderMaterial) -> void:
	var seeds := PackedVector4Array()
	var rots := PackedVector4Array()
	for i in _frag_seeds.size():
		seeds.append(_frag_seeds[i])
		var a: Vector4 = _frag_axes[i]
		var q := Quaternion(Vector3(a.x, a.y, a.z), fmod(system.time_s / a.w, 1.0) * TAU * 0.02)
		rots.append(Vector4(q.x, q.y, q.z, q.w))
	# Dirección de cada semilla en el marco del cielo (antes se recalculaba y normalizaba 144 veces por píxel).
	var pole: Vector3 = _shatter_axes[0]
	var pm: Vector3 = _shatter_axes[1]
	var east := pole.cross(pm)
	var sws := PackedVector4Array()
	for sd: Vector4 in _frag_seeds:
		var sw := (pm * sd.z + pole * sd.y + east * sd.x).normalized()
		sws.append(Vector4(sw.x, sw.y, sw.z, 0.0))
	_pad(sws, 12)
	mat.set_shader_parameter("frag_sw", sws)
	_pad(seeds, 12)
	_pad(rots, 12)
	mat.set_shader_parameter("frag_count", _frag_seeds.size())
	mat.set_shader_parameter("frag_seed", seeds)
	mat.set_shader_parameter("frag_rot", rots)
	mat.set_shader_parameter("land_mask", LandMask.texture())
	var earth: BodyDef = system.body("earth")
	mat.set_shader_parameter("core_fraction", float(earth.surface().get("core_radius_fraction", 0.33)))


## Lunas menores del sistema local que podrían verse (radio angular o brillo apreciable). Dos veces por segundo.
func _refresh_candidates(local_planet: String, cam_sys: DVec3, delta: float) -> void:
	_cand_timer -= delta
	if _cand_timer > 0.0 and local_planet == _cand_planet:
		return
	_cand_timer = 0.5
	_cand_planet = local_planet
	_candidates.clear()
	for id in system.children.get(local_planet, []):
		var b: BodyDef = system.body(id)
		if b.kind != "moon_minor":
			continue
		var d := system.position(id).distance_to(cam_sys)
		if b.radius_m() / d > 2.0e-5:  # ≈ 0,01 píxeles: puede verse como punto
			_candidates.append(id)
