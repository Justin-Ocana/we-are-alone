class_name ViewManager
extends Node
## Gestión de cámaras y capas de render (ADR-014).
##
## - Elige la cámara activa: 1ª/3ª persona del astronauta o cámara exterior de la nave (pilotando, V).
## - Profundidad: Compatibility usa 24 bits sin Z inversa. Con la cabina visible a 5 cm y un planeta a
##   cientos de km, un único par near/far haría parpadear el terreno. Cuando la cámara está DENTRO de una
##   nave, la nave y el cuerpo se renderizan con una segunda cámara de plano cercano (near 3 cm, far
##   150 m) en un SubViewport transparente superpuesto; la cámara principal sólo dibuja el mundo con
##   near/far adaptados a la altitud. Fuera de la nave se usa una sola cámara.
## - Ajusta near/far y máscaras cada fotograma. Se ejecuta después del resto (process_priority alto).

const OVERLAY_FAR := 150.0

var world: Node                 ## SurfaceWorld
var astronaut: Astronaut
var ship_camera: ShipCamera
var ship_exterior := false
var override_camera: Camera3D = null  ## cámara libre (pruebas/capturas); tiene prioridad
var overlay_active := false
var render_paused := false
var single := false               ## una sola cámara dentro de la nave (cerca del suelo)
const SINGLE_MAX_ALT := 400.0
const SINGLE_NEAR := 0.06
const SINGLE_FAR := 30000.0      ## un panel opaco tapa la vista: la superposición tampoco se dibuja
var _post_layer: CanvasLayer
var _post_rect: ColorRect
var _post_mat: ShaderMaterial
var _light_mat: ShaderMaterial
var _flare_mat: ShaderMaterial
var _flare_rect: ColorRect
var _sun_seen := 0.0

var _overlay_vp: SubViewport
var _overlay_cam: Camera3D
var _overlay_layer: CanvasLayer
var _overlay_rect: TextureRect
var _active: Camera3D
var _env_interior: Environment
var _env_exterior: Environment
const HIGH_ALTITUDE := 150.0      ## m sobre el terreno: por encima, objetos cercanos en la superposición
const OVERLAY_FAR_EXTERIOR := 6000.0
const INTERIOR_AMBIENT := 0.3    ## luz ambiente interior (de relleno: la iluminación la dan las luces de la nave)


func _ready() -> void:
	process_priority = 1000
	ship_camera = ShipCamera.new()
	ship_camera.name = "ShipCamera"
	add_child(ship_camera)
	_overlay_vp = SubViewport.new()
	_overlay_vp.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # los viewports no heredan: sólo naves y astronautas interpolan (ADR-042)
	_overlay_vp.transparent_bg = true
	_overlay_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_overlay_vp.size = get_viewport().get_visible_rect().size
	add_child(_overlay_vp)
	_overlay_cam = Camera3D.new()
	_overlay_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # copia la cámara activa cada fotograma (ADR-042)
	_overlay_cam.near = 0.03
	_overlay_cam.far = OVERLAY_FAR
	_overlay_vp.add_child(_overlay_cam)
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 3
	add_child(_overlay_layer)
	_overlay_rect = TextureRect.new()
	_overlay_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_overlay_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_rect.texture = _overlay_vp.get_texture()
	_overlay_layer.add_child(_overlay_rect)
	# Efectos de imagen (ADR-039): justo encima de la superposición de la nave y debajo del casco y las interfaces.
	_post_layer = CanvasLayer.new()
	_post_layer.layer = 3
	add_child(_post_layer)
	_post_rect = ColorRect.new()
	_post_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = load("res://src/world/post_fx.gdshader")
	_post_rect.material = _post_mat
	_post_layer.add_child(_post_rect)
	# Versión ligera (calidad media): capa que oscurece + capa aditiva del destello, sin copiar la pantalla.
	_light_mat = ShaderMaterial.new()
	_light_mat.shader = load("res://src/world/post_fx_light.gdshader")
	_flare_rect = ColorRect.new()
	_flare_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flare_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flare_mat = ShaderMaterial.new()
	_flare_mat.shader = load("res://src/world/post_fx_flare.gdshader")
	_flare_mat.set_shader_parameter("flare_pass", true)
	_flare_rect.material = _flare_mat
	_post_layer.add_child(_flare_rect)


## Entorno del SubViewport: el del mundo pero con fondo transparente y sin niebla.
func set_world_environment(env: Environment) -> void:
	var e := env.duplicate() as Environment
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.fog_enabled = false
	e.glow_enabled = false   # la superposición es transparente: el resplandor se aplica en la vista principal
	# Interior presurizado e iluminado: luz ambiente propia (la de la Luna, 0,08, lo dejaría a oscuras).
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.84, 0.92)
	e.ambient_light_energy = INTERIOR_AMBIENT
	_env_interior = e
	# Exterior (nave vista desde fuera a gran altitud): la misma luz que el mundo.
	var x := env.duplicate() as Environment
	x.background_mode = Environment.BG_CLEAR_COLOR
	x.fog_enabled = false
	x.glow_enabled = false
	_env_exterior = x
	_overlay_cam.environment = e


func active_camera() -> Camera3D:
	return _active if _active != null else astronaut.active_camera()


func _unhandled_input(event: InputEvent) -> void:
	if astronaut == null or not astronaut.seated or astronaut.input_blocked:
		return
	var pin := astronaut.pin
	if not pin.owns(event):
		return
	if pin.event_pressed(event, &"toggle_camera"):
		ship_exterior = not ship_exterior
		get_viewport().set_input_as_handled()
	elif ship_exterior and astronaut.seated_looking():
		var rel := pin.mouse_motion(event)
		if rel != Vector2.ZERO:
			ship_camera.orbit(rel, GameSettings.mouse_sensitivity)
		elif pin.event_pressed(event, &"speed_up"):
			ship_camera.zoom(0.85)
		elif pin.event_pressed(event, &"speed_down"):
			ship_camera.zoom(1.18)


func _process(delta: float) -> void:
	if astronaut == null:
		return
	if not astronaut.seated:
		ship_exterior = false
	var cam: Camera3D
	if override_camera != null:
		cam = override_camera
	elif astronaut.seated and ship_exterior and astronaut.aboard != null:
		ship_camera.ship = astronaut.aboard
		var looking := astronaut.seated_looking()
		if looking:
			var px := astronaut.pin.look_pixels(delta)
			if px != Vector2.ZERO:
				ship_camera.orbit(px, GameSettings.mouse_sensitivity)
		ship_camera.update_view(delta, looking)
		cam = ship_camera
	else:
		cam = astronaut.active_camera()
	if not cam.current:
		cam.current = true
	_active = cam
	var inside := (astronaut.aboard != null or astronaut.seated) and cam != ship_camera and cam != override_camera
	var own_fp := cam == astronaut.cam.fp_camera
	var hl := Layers.head_layers(astronaut.pin.slot)
	var own_head := Layers.bits([hl.x, hl.y]) if own_fp else 0
	var all_layers := Layers.all_view_layers()
	# Fuera de la nave y lejos del suelo, el near del mundo es grande (≈1 % de la altitud) y recortaría la
	# nave en vista exterior o el propio cuerpo al salir al espacio: esos objetos van a la superposición.
	var above := _above_terrain(cam)
	var high := not inside and above > HIGH_ALTITUDE
	# Ronda 9 (rendimiento): dentro de la nave y cerca del suelo, una sola cámara dibuja todo (interior y mundo):
	# el horizonte está a pocos km y la precisión de profundidad basta. Ahorra un render 3D completo.
	# Histéresis (ronda 10): entra bajo 350 m y sale sobre 450 m; antes alternaba en cada oscilación junto a 400 m.
	single = inside and astronaut.aboard != null and above < (SINGLE_MAX_ALT + 50.0 if single else SINGLE_MAX_ALT - 50.0)
	overlay_active = (inside and not single) or high
	_overlay_layer.visible = overlay_active
	# El SubViewport sólo se renderiza cuando se usa (si no, duplicaría el coste de toda la escena).
	_overlay_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if overlay_active and not render_paused else SubViewport.UPDATE_DISABLED
	if overlay_active:
		var vp_size := Vector2i(get_viewport().get_visible_rect().size)
		if _overlay_vp.size != vp_size:
			_overlay_vp.size = vp_size
		if _overlay_vp.scaling_3d_scale != get_viewport().scaling_3d_scale:
			_overlay_vp.scaling_3d_scale = get_viewport().scaling_3d_scale   # sólo si cambia: reconfigura los búferes
		_overlay_cam.global_transform = cam.global_transform
		_overlay_cam.fov = cam.fov
	if single:
		cam.cull_mask = all_layers & ~own_head
	elif inside:
		_overlay_cam.far = OVERLAY_FAR
		_overlay_cam.environment = _env_interior
		_overlay_cam.cull_mask = Layers.bits([Layers.SHIP_EXT, Layers.SHIP_INT, Layers.BODY_INT, Layers.HEAD_INT, Layers.HEAD_INT_P2]) & ~own_head
		cam.cull_mask = Layers.bits([Layers.WORLD, Layers.HEAD, Layers.BODY, Layers.HEAD_P2]) & ~own_head
	elif high:
		_overlay_cam.far = OVERLAY_FAR_EXTERIOR
		_overlay_cam.environment = _env_exterior
		_overlay_cam.cull_mask = (all_layers & ~Layers.bit(Layers.WORLD)) & ~own_head
		cam.cull_mask = Layers.bit(Layers.WORLD)
	else:
		cam.cull_mask = all_layers & ~own_head
	_update_planes(cam, (inside and not single) or high)
	if single:
		cam.near = SINGLE_NEAR
		cam.far = minf(cam.far, SINGLE_FAR)
	_update_post(cam, delta)


## Destello del Sol: posición en pantalla y visibilidad (un rayo comprueba que no lo tapen el terreno ni la nave;
## se atenúa con la atmósfera). El resto de efectos es constante.
func _update_post(cam: Camera3D, delta: float) -> void:
	var mode := GameSettings.effective_post()
	_post_layer.visible = not render_paused and mode != "off"
	var full := mode == "full"
	_post_rect.material = _post_mat if full else _light_mat
	_flare_rect.visible = not full and _sun_seen > 0.002
	if not _post_layer.visible:
		return
	var vp := _post_rect.get_viewport_rect().size
	var mat: ShaderMaterial = _post_rect.material
	mat.set_shader_parameter("aspect", vp.x / maxf(vp.y, 1.0))
	_flare_mat.set_shader_parameter("aspect", vp.x / maxf(vp.y, 1.0))
	var env: SkyEnvironment = world.env
	var sd := env.sun_direction_bf()
	var fwd := -cam.global_transform.basis.z
	var want := 0.0
	var uv := Vector2(-10, -10)
	if sd.dot(fwd) > 0.2:
		var p := cam.unproject_position(cam.global_position + sd * 1000.0)
		uv = p / vp
		if uv.x > -0.2 and uv.x < 1.2 and uv.y > -0.2 and uv.y < 1.2:
			var space := cam.get_world_3d().direct_space_state
			var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + sd * 3000.0, Layers.solid_mask())
			if space.intersect_ray(q).is_empty():
				var vis := float(env.sky_mat.get_shader_parameter("sun_visibility"))
				var dens := float(env.sky_mat.get_shader_parameter("atmosphere_density")) * float(env.sky_mat.get_shader_parameter("altitude_factor"))
				want = clampf(vis, 0.0, 1.0) * (1.0 - 0.6 * clampf(dens, 0.0, 1.0)) * clampf((sd.dot(fwd) - 0.2) / 0.3, 0.0, 1.0)
	_sun_seen = move_toward(_sun_seen, want, delta * 6.0)
	var target: ShaderMaterial = _post_mat if _post_rect.material == _post_mat else _flare_mat
	target.set_shader_parameter("sun_uv", uv)
	target.set_shader_parameter("sun_amount", _sun_seen)


func _above_terrain(cam: Camera3D) -> float:
	var terrain: PlanetTerrain = world.terrain
	var cam_bf := FloatingOrigin.to_global(cam.global_position)
	return cam_bf.length() - terrain.ground_radius_at(cam_bf)


## Near/far del mundo según la altitud de la cámara (y la distancia a la nave en vista exterior).
func _update_planes(cam: Camera3D, inside: bool) -> void:
	var terrain: PlanetTerrain = world.terrain
	var cam_bf := FloatingOrigin.to_global(cam.global_position)
	var r := cam_bf.length()
	var above_terrain := maxf(r - terrain.ground_radius_at(cam_bf), 0.0)
	var above_datum := maxf(r - terrain.radius, 0.0)
	var far := Units.horizon_distance(terrain.radius, above_datum) \
		+ Units.horizon_distance(terrain.radius, terrain.max_elevation()) + 2000.0
	cam.far = clampf(far, 3000.0, 1.0e13)
	var near := above_terrain * 0.01
	if inside:
		pass  # nave y cuerpos los dibuja la superposición; el mundo puede usar un near grande
	elif cam == ship_camera and ship_camera.ship != null:
		near = minf(near, cam.global_position.distance_to(ship_camera.ship.global_position) * 0.05)
	else:
		# Fuera, cerca de una nave posada: el casco puede estar a pocos metros.
		for s in astronaut.ships:
			near = minf(near, maxf(0.05, cam.global_position.distance_to(s.global_position) - 25.0))
	# Near mínimo algo mayor (ronda 11): con 0,03 m y un horizonte de cientos de km la precisión de profundidad era
	# de metros a 1 km (Compatibility no usa Z invertida) y el terreno lejano parpadeaba.
	var min_near := 0.05 if cam == astronaut.cam.fp_camera else 0.08
	cam.near = clampf(near, min_near, 1.0e9)
