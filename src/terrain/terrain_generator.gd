class_name TerrainGenerator
extends RefCounted
## Función de altura determinista: h = f(dirección unitaria, semilla, perfil), en metros sobre
## el radio medio. No tiene estado mutable tras construirse; cada hilo de trabajo crea su propia
## instancia (las instancias de FastNoiseLite no se comparten entre hilos).

const CRATER_JITTER := 0.45  # con radio ≤ 0,2 celdas el cráter nunca cruza una frontera de Voronoi

var radius: float
var seed_value: int
var profile: Dictionary
var max_elevation: float

var _continent: FastNoiseLite
var _mountain: FastNoiseLite
var _hills: FastNoiseLite
var _detail: FastNoiseLite
var _crater_dist: Array[FastNoiseLite] = []
var _crater_val: Array[FastNoiseLite] = []
var _crater_layers: Array = []
var _cracks: FastNoiseLite = null
var _spots_d: FastNoiseLite = null
var _spots_v: FastNoiseLite = null
var _dunes: FastNoiseLite = null
var _pads: Array = []   ## explanadas [dir, radio m, transición m, altura] (base lunar LF-01; ADR-043)

var _continent_scale: float
var _continent_amp: float
var _mountain_scale: float
var _mountain_amp: float
var _hills_amp: float
var _detail_amp: float


func _init(p_radius: float, p_seed: int, p_profile: Dictionary) -> void:
	radius = p_radius
	seed_value = p_seed
	profile = p_profile
	max_elevation = TerrainProfiles.max_elevation(profile)
	_continent_scale = float(profile["continent_scale"])
	_continent_amp = float(profile["continent_amp"])
	_mountain_scale = float(profile["mountain_scale"])
	_mountain_amp = float(profile["mountain_amp"])
	_hills_amp = float(profile["hills_amp"])
	_detail_amp = float(profile["detail_amp"])
	_continent = _make_noise(p_seed + 11, 1.0, int(profile["continent_octaves"]), FastNoiseLite.FRACTAL_FBM)
	_mountain = _make_noise(p_seed + 23, 1.0, int(profile["mountain_octaves"]), FastNoiseLite.FRACTAL_RIDGED)
	_hills = _make_noise(p_seed + 37, 1.0 / float(profile["hills_wavelength"]), int(profile["hills_octaves"]), FastNoiseLite.FRACTAL_FBM)
	_detail = _make_noise(p_seed + 41, 1.0 / float(profile["detail_wavelength"]), int(profile["detail_octaves"]), FastNoiseLite.FRACTAL_FBM)
	if profile.has("cracks"):
		_cracks = _make_noise(p_seed + 61, 1.0, 3, FastNoiseLite.FRACTAL_RIDGED)
	if profile.has("spots"):
		var sp: Dictionary = profile["spots"]
		_spots_d = _make_cellular(p_seed + 71, 1.0 / float(sp["cell_m"]), FastNoiseLite.RETURN_DISTANCE)
		_spots_v = _make_cellular(p_seed + 71, 1.0 / float(sp["cell_m"]), FastNoiseLite.RETURN_CELL_VALUE)
	if profile.has("dunes"):
		_dunes = _make_noise(p_seed + 81, 1.0 / float(profile["dunes"]["wavelength"]), 2, FastNoiseLite.FRACTAL_RIDGED)
	var layer_index := 0
	for layer in profile.get("craters", []):
		var freq := 1.0 / float(layer["cell_m"])
		var s := p_seed + 101 + layer_index * 7
		var nd := _make_cellular(s, freq, FastNoiseLite.RETURN_DISTANCE)
		var nv := _make_cellular(s, freq, FastNoiseLite.RETURN_CELL_VALUE)
		_crater_dist.append(nd)
		_crater_val.append(nv)
		_crater_layers.append([float(layer["depth"]), float(layer["radius"]), float(layer["chance"])])
		layer_index += 1
	# Explanadas: la altura del centro se calcula sin ellas, igual en todos los hilos (mismo perfil → mismo valor).
	for pad in profile.get("pads", []):
		var dv := Vector3(pad["dir"][0], pad["dir"][1], pad["dir"][2]).normalized()
		_pads.append([dv, float(pad["radius_m"]), float(pad["blend_m"]), _natural_height(dv.x, dv.y, dv.z)])


static func _make_noise(s: int, freq: float, octaves: int, fractal: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = fractal
	n.fractal_octaves = octaves
	n.fractal_lacunarity = 2.0
	n.fractal_gain = 0.5
	return n


static func _make_cellular(s: int, freq: float, ret: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	n.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	n.cellular_return_type = ret
	n.cellular_jitter = CRATER_JITTER
	return n


## Ruido continental en [-1, 1] aprox. (también se usa para el color).
func continent_at(dx: float, dy: float, dz: float) -> float:
	var s := _continent_scale
	return _continent.get_noise_3d(dx * s, dy * s, dz * s)


## Altura (m) sobre el radio medio en la dirección unitaria (dx, dy, dz).
func height_at(dx: float, dy: float, dz: float) -> float:
	var h := _natural_height(dx, dy, dz)
	for pad in _pads:
		var k := pad_blend(pad, dx, dy, dz)
		if k < 1.0:
			h = lerpf(float(pad[3]), h, k)
	return h


## 0 dentro de la explanada, 1 fuera de su transición (suave entre medias).
func pad_blend(pad: Array, dx: float, dy: float, dz: float) -> float:
	var pd: Vector3 = pad[0]
	var dist := Vector3(dx - pd.x, dy - pd.y, dz - pd.z).length() * radius   # cuerda ≈ arco a esta escala
	var r: float = pad[1]
	if dist <= r:
		return 0.0
	var t := clampf((dist - r) / float(pad[2]), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## ¿Está el punto sobre alguna explanada (para no sembrar rocas encima)?
func on_pad(dx: float, dy: float, dz: float, margin_m: float = 0.0) -> bool:
	for pad in _pads:
		var pd: Vector3 = pad[0]
		if Vector3(dx - pd.x, dy - pd.y, dz - pd.z).length() * radius < float(pad[1]) + margin_m:
			return true
	return false


func _natural_height(dx: float, dy: float, dz: float) -> float:
	var c := continent_at(dx, dy, dz)
	var h := c * _continent_amp
	var mask := smoothstep(-0.05, 0.45, c)
	if mask > 0.0:
		var s := _mountain_scale
		var m := (_mountain.get_noise_3d(dx * s, dy * s, dz * s) + 1.0) * 0.5
		h += mask * m * m * _mountain_amp
	# Coordenadas métricas sobre la esfera de radio medio (longitudes de onda ≥ 30 m).
	var px := dx * radius
	var py := dy * radius
	var pz := dz * radius
	h += _hills.get_noise_3d(px, py, pz) * _hills_amp
	h += _detail.get_noise_3d(px, py, pz) * _detail_amp
	for i in _crater_layers.size():
		h += _crater_height(i, px, py, pz)
	h += _feature_height(dx, dy, dz, px, py, pz)
	if profile.has("sea"):
		h = maxf(h, float(profile["sea"]["level"]) * (1.0 if absf(dy) > sin(deg_to_rad(float(profile["sea"]["lat_min"]))) else 1.0e6))
	return h


## Grietas (Europa, Ganímedes, Encélado, Miranda), dunas (Titán), cresta ecuatorial (Jápeto).
func _feature_height(dx: float, dy: float, dz: float, px: float, py: float, pz: float) -> float:
	var h := 0.0
	if _cracks != null:
		var c := crack_at(dx, dy, dz)
		h += c * float(profile["cracks"]["depth"])
	if _dunes != null:
		var lat := rad_to_deg(asin(clampf(dy, -1.0, 1.0)))
		var dn: Dictionary = profile["dunes"]
		if absf(lat) < float(dn["lat_max"]):
			h += (_dunes.get_noise_3d(px * 0.3, py * 2.0, pz * 0.3) + 1.0) * 0.5 * float(dn["amp"])
	if profile.has("equatorial_ridge"):
		h += exp(-pow(dy / 0.02, 2.0)) * float(profile["equatorial_ridge"]) * pow(clampf(radius / 1737400.0, 0.0, 1.0), 0.7)
	return h


## Intensidad de grieta (0..1) en la dirección dada.
func crack_at(dx: float, dy: float, dz: float) -> float:
	if _cracks == null:
		return 0.0
	var cr: Dictionary = profile["cracks"]
	if cr.has("lat_max") and dy > sin(deg_to_rad(float(cr["lat_max"]))):
		return 0.0  # rayas de tigre sólo en el polo sur
	var s := float(cr["scale"])
	var v := _cracks.get_noise_3d(dx * s, dy * s, dz * s)
	return smoothstep(1.0 - float(cr["width"]) * 2.0, 1.0, v)


func _crater_height(i: int, px: float, py: float, pz: float) -> float:
	var params: Array = _crater_layers[i]
	var cv := _crater_val[i].get_noise_3d(px, py, pz)  # valor aleatorio estable por celda, [-1, 1]
	var r01 := cv * 0.5 + 0.5
	var chance: float = params[2]
	if r01 > chance:
		return 0.0
	var size01 := r01 / chance  # reutiliza el valor de la celda para el tamaño
	var r: float = params[1] * (0.45 + 0.55 * size01)
	var d := _crater_dist[i].get_noise_3d(px, py, pz) + 1.0  # distancia al punto de la celda
	var x := d / r
	var depth: float = params[0] * (r / params[1])
	var rim := depth * 0.22
	if x < 1.0:
		var bowl := maxf(x * x - 1.0, -0.85)  # fondo ligeramente plano
		return bowl * depth + rim * x * x * x * x
	var t := (x - 1.0) / 0.6
	if t >= 1.0:
		return 0.0
	return rim * (1.0 - t) * (1.0 - t)


## Color de vértice según altura, pendiente (coseno respecto a la vertical) y latitud.
func color_at(dx: float, dy: float, dz: float, h: float, slope_cos: float) -> Color:
	var cols: Dictionary = profile["colors"]
	var t := clampf((h + _continent_amp * 0.4) / maxf(1.0, max_elevation * 0.7), 0.0, 1.0)
	var base: Color = (cols["low"] as Color).lerp(cols["mid"], smoothstep(0.0, 0.45, t))
	base = base.lerp(cols["high"], smoothstep(0.45, 0.85, t))
	var steep := 1.0 - slope_cos
	base = base.lerp(cols["slope"], smoothstep(0.06, 0.30, steep))
	var snow_h: float = profile["snow_height"]
	if h > snow_h and steep < 0.35:
		base = base.lerp(cols["peak"], smoothstep(snow_h, snow_h + 500.0, h))
	var lat := rad_to_deg(asin(clampf(dy, -1.0, 1.0)))
	var polar_lat: float = profile["polar_lat"]
	if polar_lat < 0.0:
		# Casquete en un solo polo (Tritón: casquete sur de nitrógeno rosado).
		if lat < polar_lat + 3.0:
			base = base.lerp(cols["polar"], smoothstep(polar_lat + 3.0, polar_lat - 2.0, lat))
	elif absf(lat) > polar_lat - 3.0 and steep < 0.4:
		base = base.lerp(cols["polar"], smoothstep(polar_lat - 3.0, polar_lat + 2.0, absf(lat)))
	# Rasgos de color propios de cada cuerpo.
	if _cracks != null:
		base = base.lerp(profile["cracks"]["color"], crack_at(dx, dy, dz) * 0.85)
	if _spots_d != null:
		var sp: Dictionary = profile["spots"]
		var px := dx * radius
		var py := dy * radius
		var pz := dz * radius
		var cv := _spots_v.get_noise_3d(px, py, pz) * 0.5 + 0.5
		if cv < float(sp["chance"]):
			var dd := _spots_d.get_noise_3d(px, py, pz) + 1.0
			base = base.lerp(sp["ring"], smoothstep(0.32, 0.18, dd) * 0.7)
			base = base.lerp(sp["color"], smoothstep(0.16, 0.08, dd))
	if profile.has("two_tone") and dx < 0.0:
		# Jápeto: hemisferio delantero oscuro como el carbón, con transición irregular.
		var k := smoothstep(-0.05, -0.35, dx + continent_at(dx, dy, dz) * 0.15)
		base = base.lerp(profile["two_tone"]["color"], k)
	if profile.has("sea") and h <= float(profile["sea"]["level"]) + 0.5:
		base = profile["sea"]["color"]
	if profile.has("smooth_basins"):
		# Plutón: llanuras heladas brillantes en las cuencas (tipo Sputnik Planitia).
		var c := continent_at(dx, dy, dz)
		base = base.lerp(cols["low"], smoothstep(-0.05, -0.25, c) * float(profile["smooth_basins"]) * 1.6)
	return base
