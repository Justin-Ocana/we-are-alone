class_name CloudField
extends MultiMeshInstance3D
## Nubes 3D alrededor de la cámara (ADR-037): al atravesar una capa de nubes (Venus, Júpiter, Saturno, Urano,
## Neptuno, Titán…) cientos de cúmulos translúcidos pasan junto a la nave con el viento y con tu velocidad.
## Se colocan en una caja que se repite alrededor de la cámara (siempre hay nubes cerca, nunca un borde) y se
## orientan hacia ella. Color y densidad de la capa del modelo atmosférico; los rayos las iluminan.
## Coste acotado: COUNT quads sin luz con textura procedural (sin sombras ni ordenación).

const COUNT := 140
const BOX := 2600.0               ## m de lado de la caja que se repite
const MIN_SIZE := 140.0
const MAX_SIZE := 520.0
const REBASE_M := 40000.0         ## se rebasa el origen en doble precisión cada 40 km

var _bases: PackedVector3Array = PackedVector3Array()
var _sizes: PackedFloat32Array = PackedFloat32Array()
var _shade: PackedFloat32Array = PackedFloat32Array()
var _origin_bf: DVec3 = null
var _wind_off := Vector3.ZERO
var _amount := 0.0                ## 0..1 (aparece y desaparece suavemente)
var _color := Color(1, 1, 1)
var _mat: StandardMaterial3D


func _ready() -> void:
	layers = Layers.bit(Layers.WORLD)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mm.mesh = q
	mm.instance_count = COUNT
	multimesh = mm
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.vertex_color_use_as_albedo = true
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mat.billboard_keep_scale = true
	_mat.albedo_texture = _make_puff()
	_mat.disable_receive_shadows = true
	_mat.no_depth_test = false
	_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material_override = _mat
	var rng := RandomNumberGenerator.new()
	rng.seed = 1977
	for i in COUNT:
		_bases.append(Vector3(rng.randf(), rng.randf() * 0.5, rng.randf()) * BOX)
		_sizes.append(rng.randf_range(MIN_SIZE, MAX_SIZE))
		_shade.append(rng.randf_range(0.75, 1.1))
	visible = false


## Textura de un cúmulo: ruido suave con borde radial (64×64, generada una vez).
static func _make_puff() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.frequency = 0.06
	n.fractal_octaves = 3
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (0.55 + 0.45 * (n.get_noise_2d(x, y) * 0.5 + 0.5))
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## `cam` cámara activa; `model` atmósfera del cuerpo dominante; `alt` altitud de la cámara sobre la referencia.
## `flash` 0..1 brillo de un rayo.
func update_field(cam: Camera3D, model: AtmosphereModel, alt: float, light: float, wind: Vector3, delta: float, flash: float) -> void:
	var cl := model.cloud_at(alt) if model != null and model.present() else {}
	var want := 0.0
	if not cl.is_empty():
		want = clampf(float(cl.get("opacity", 0.8)), 0.0, 1.0)
		_color = model.color_of(cl)
	_amount = move_toward(_amount, want, delta * 0.8)
	visible = _amount > 0.01
	if not visible:
		return
	var cam_bf := FloatingOrigin.to_global(cam.global_position)
	if _origin_bf == null or cam_bf.distance_to(_origin_bf) > REBASE_M:
		_origin_bf = cam_bf.copy()
	_wind_off += wind * delta
	var rel := cam_bf.sub(_origin_bf).to_vector3() - _wind_off
	var up := cam_bf.normalized().to_vector3()
	# Base ortonormal local (las nubes forman una capa horizontal alrededor de la cámara).
	var east := Vector3.UP.cross(up)
	east = east.normalized() if east.length_squared() > 1e-6 else Vector3.RIGHT
	var north := up.cross(east)
	var local := Vector3(rel.dot(east), rel.dot(up), rel.dot(north))
	var lit := clampf(light * 1.4 + 0.08, 0.05, 1.0) + flash * 0.8
	var mm := multimesh
	var half := BOX * 0.5
	for i in COUNT:
		var b := _bases[i]
		var p := Vector3(fposmod(b.x - local.x, BOX) - half, fposmod(b.y - local.y, BOX * 0.5) - BOX * 0.25,
			fposmod(b.z - local.z, BOX) - half)
		var world_p := cam.global_position + east * p.x + up * p.y + north * p.z
		var s := _sizes[i]
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s * 0.6, s)), world_p))
		# Se desvanecen junto a la cámara (no tapar la cabina) y en los bordes de la caja (sin saltos).
		var dist := p.length()
		var fade := clampf((dist - 60.0) / 250.0, 0.0, 1.0) * clampf((half - absf(p.x)) / 300.0, 0.0, 1.0) \
			* clampf((half - absf(p.z)) / 300.0, 0.0, 1.0) * clampf((BOX * 0.25 - absf(p.y)) / 200.0, 0.0, 1.0)
		var c := _color * lit * _shade[i]
		c.a = 0.55 * _amount * fade
		mm.set_instance_color(i, c)
