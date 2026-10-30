class_name ScreenFx
extends CanvasLayer
## Efectos de pantalla del astronauta (ADR-019): daño, poca salud y mareo. Por encima de la interfaz de
## juego y por debajo del menú de pausa. Sólo se dibuja (y sólo copia la imagen de pantalla) cuando algún
## efecto está activo. (El desmayo se retiró a petición del jugador.)

var astro: Astronaut
var _rect: ColorRect
var _mat: ShaderMaterial
var _flash := 0.0


func _ready() -> void:
	layer = 8
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://src/player/screen_fx.gdshader")
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	add_child(_rect)
	if astro != null:
		astro.damaged.connect(func(amount: float) -> void: _flash = minf(1.0, _flash + 0.35 + amount / 40.0))


func _process(delta: float) -> void:
	if astro == null:
		return
	_flash = maxf(0.0, _flash - delta * 1.6)
	var low := clampf((40.0 - astro.health) / 40.0, 0.0, 1.0)
	var dz := smoothstep(0.15, 1.0, astro.dizziness)
	var pl := 0.0
	if astro.aboard != null:
		pl = astro.aboard.state.plasma
	var active := _flash > 0.003 or low > 0.003 or dz > 0.003 or pl > 0.003
	_rect.visible = active
	if not active:
		return
	var vp := _rect.get_viewport_rect().size
	_mat.set_shader_parameter("aspect", vp.x / maxf(vp.y, 1.0))
	_mat.set_shader_parameter("damage", _flash)
	_mat.set_shader_parameter("low_health", low)
	_mat.set_shader_parameter("dizzy", dz)
	_mat.set_shader_parameter("blackout", 0.0)
	_mat.set_shader_parameter("plasma", pl)
