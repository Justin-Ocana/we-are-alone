class_name HelmetOverlay
extends CanvasLayer
## Interior del casco en 1ª persona (ADR-009, ADR-010). Capas, de abajo arriba:
## 1. Refracción del cristal curvo (distorsión + dispersión cromática en el borde; opcional).
## 2. Marco del visor con inercia, oscurecimiento automático e imagen residual del Sol.
## 3. Brillo aditivo del Sol en el visor (halo, destello, reflejos fantasma).
## La interfaz de datos del casco está en HelmetHud (ADR-019).
##
## Oscurecimiento automático: como un visor de soldador, reacciona con ~0,5 s de retraso al brillo del Sol
## cerca del centro de la vista. Mirar fijamente el Sol acumula exposición; al apartar la vista queda una
## imagen residual fija en la retina que se desvanece en unos segundos.

const STARE_COS := 0.978        ## cos 12°: se considera "mirar al Sol"
const GLARE_COS := 0.82         ## cos 35°: empieza el brillo

var _refraction: ColorRect
var _refraction_mat: ShaderMaterial
var _frame: ColorRect
var _mat: ShaderMaterial
var _glare: ColorRect
var _glare_mat: ShaderMaterial
var _lag := Vector2.ZERO

var auto_tint := 0.0
var exposure := 0.0
var afterimage := 0.0
var _afterimage_uv := Vector2(0.5, 0.5)
var _sun_uv := Vector2(0.5, 0.5)
var _sun_vis := 0.0


func _ready() -> void:
	layer = 4
	_refraction_mat = _shader_mat("res://src/player/visor_refraction.gdshader")
	_refraction = _rect(_refraction_mat)
	_mat = _shader_mat("res://src/player/helmet_visor.gdshader")
	_frame = _rect(_mat)
	_glare_mat = _shader_mat("res://src/player/visor_glare.gdshader")
	_glare = _rect(_glare_mat)


func _shader_mat(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	return m


func _rect(mat: ShaderMaterial) -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.material = mat
	add_child(r)
	return r


## `turn` = velocidad angular de la vista (rad/s); `light` ≈ iluminación solar (0..1);
## `cam` = cámara activa; `sun_dir` = dirección hacia el Sol (marco del motor); `focus` = enfoque 0..1;
## `sun_blocked` = el Sol está tapado por el terreno o bajo el horizonte.
func update_view(delta: float, turn: Vector2, light: float, show: bool, cam: Camera3D, sun_dir: Vector3,
		focus: float, sun_blocked: bool) -> void:
	visible = show
	if not show or cam == null:
		return
	var target := Vector2(clampf(-turn.x * 0.006, -0.025, 0.025), clampf(turn.y * 0.006, -0.02, 0.02))
	_lag = _lag.lerp(target, 1.0 - exp(-8.0 * delta))
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)

	# --- Sol: posición en pantalla, visibilidad y exposición.
	var fwd := -cam.global_transform.basis.z
	var facing := fwd.dot(sun_dir)
	var sun_point := cam.global_position + sun_dir * 1000.0
	var on_screen := not cam.is_position_behind(sun_point)
	if on_screen:
		_sun_uv = cam.unproject_position(sun_point) / vp
	var vis_t := 0.0
	if on_screen and not sun_blocked:
		var inside := clampf(1.0 - maxf(absf(_sun_uv.x - 0.5), absf(_sun_uv.y - 0.5)) * 1.6, 0.0, 1.0)
		vis_t = smoothstep(GLARE_COS, 1.0, facing) * maxf(inside, 0.15) * light
	_sun_vis = lerpf(_sun_vis, vis_t, 1.0 - exp(-20.0 * delta))
	var staring := _sun_vis > 0.1 and facing > STARE_COS
	exposure = move_toward(exposure, 1.0 if staring else 0.0, delta * (0.35 if staring else 0.2))
	if staring:
		_afterimage_uv = _sun_uv
	var ai_target := smoothstep(0.25, 1.0, exposure) * (0.25 if staring else 1.0)
	afterimage = lerpf(afterimage, ai_target, 1.0 - exp(-3.0 * delta))
	# Oscurecimiento automático con retraso de reacción (~0,5 s).
	var tint_t := smoothstep(0.08, 0.5, _sun_vis)
	auto_tint = lerpf(auto_tint, tint_t, 1.0 - exp(-(4.0 if tint_t > auto_tint else 1.5) * delta))

	for m in [_refraction_mat, _mat, _glare_mat]:
		m.set_shader_parameter("aspect", aspect)
	_refraction.visible = GameSettings.visor_effects
	_refraction_mat.set_shader_parameter("lag", _lag)
	_mat.set_shader_parameter("lag", _lag)
	_mat.set_shader_parameter("light", light)
	_mat.set_shader_parameter("auto_tint", auto_tint)
	_mat.set_shader_parameter("afterimage", afterimage)
	_mat.set_shader_parameter("afterimage_uv", _afterimage_uv)
	_mat.set_shader_parameter("focus", focus)
	_glare.visible = _sun_vis > 0.002
	_glare_mat.set_shader_parameter("sun_uv", _sun_uv)
	_glare_mat.set_shader_parameter("sun_vis", _sun_vis)
	_glare_mat.set_shader_parameter("tint", auto_tint)


