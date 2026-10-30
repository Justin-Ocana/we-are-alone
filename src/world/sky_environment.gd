class_name SkyEnvironment
extends Node3D
## Sol (DirectionalLight3D) y cielo.
## - Con Sistema Solar (ADR-024/025): la dirección del Sol sale de las efemérides en el marco fijo del cuerpo
##   ancla (días, noches y estaciones reales), la luz se atenúa con la distancia al Sol (compresión perceptiva,
##   ver ADR-025) y el cielo dibuja todos los cuerpos a su tamaño real (SystemSky).
## - Sin Sistema Solar (mundo ficticio): el Sol gira alrededor del eje polar con el día solar del cuerpo.

var body: BodyDef
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var sky_mat: ShaderMaterial
var time_s := 0.0
var time_scale := 1.0
var _decl := 0.0
var _fog_base_density := 0.0
var _visual_density := 0.0
var _atmo_color := Color(0.6, 0.55, 0.5)
var system: SolarSystem = null
var anchor := ""
var system_sky: SystemSky
var sun_distance_au := 1.0
var _light_factor := 1.0
var earth_light: DirectionalLight3D
var _sky_t := 0.0
var _sky_last: DVec3 = null
var _obs_bf: DVec3 = null               ## último observador (marco BF del ancla)
var observer_sys_override: DVec3 = null   ## observador heliocéntrico ficticio (capturas de prueba)


func setup(p_body: BodyDef, shadows: bool, p_system: SolarSystem = null) -> void:
	body = p_body
	system = p_system
	anchor = body.id
	if system != null and system_sky == null:
		system_sky = SystemSky.new(system)
	_decl = deg_to_rad(body.axial_tilt_deg() * 0.5)
	sun = DirectionalLight3D.new()
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.99, 0.97)   # fuera de la atmósfera el Sol es blanco
	sun.shadow_enabled = shadows
	sun.directional_shadow_max_distance = 120.0
	# Dos divisiones en lugar de cuatro: la mitad de pasadas de sombra (cada división vuelve a dibujar el terreno
	# cercano y las rocas). A 120 m no se nota la diferencia de resolución (ronda 7).
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	# Las luces también se filtran por la máscara de la CÁMARA (sus `layers`): el Sol debe ser visible para la
	# cámara de superposición (nave en exterior alto, ventanas vistas desde dentro), que no dibuja WORLD.
	sun.light_cull_mask = Layers.sun_mask()
	sun.layers = Layers.sun_mask()
	add_child(sun)

	# Resplandor de la Tierra rota (ADR-040, FICTICIO como la propia Tierra destruida): el magma ilumina de
	# naranja el lado que la mira, sobre todo en la noche lunar. Intensidad según su tamaño aparente.
	earth_light = DirectionalLight3D.new()
	earth_light.light_color = Color(1.0, 0.93, 0.86)   # apenas cálido: la Luna debe seguir viéndose gris
	earth_light.light_energy = 0.0
	earth_light.shadow_enabled = false
	earth_light.light_cull_mask = Layers.sun_mask()
	earth_light.layers = Layers.sun_mask()
	earth_light.light_specular = 0.2
	add_child(earth_light)

	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://src/world/sky.gdshader")
	sky_mat.set_shader_parameter("milky_tex", load("res://assets/sky/milky_way.png"))
	var atmo := body.atmosphere()
	sky_mat.set_shader_parameter("atmosphere_density", float(atmo.get("visual_density", 0.0)) if body.has_atmosphere() else 0.0)
	if atmo.has("color"):
		var c: Array = atmo["color"]
		_atmo_color = Color(c[0], c[1], c[2])
		sky_mat.set_shader_parameter("atmosphere_color", _atmo_color)
	_apply_sky_colors(atmo)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_QUALITY

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	# Imagen (ronda 8, ADR-039): mapeo de tonos AgX (luces altas suaves, sin saturar), resplandor en lo más brillante
	# (Sol, toberas, luces de la nave, rayos) y un etalonaje leve. Se puede desactivar en Opciones.
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.92
	env.glow_enabled = false   # el resplandor lo hace post_fx.gdshader (más barato y también dentro de la nave)
	env.glow_intensity = 0.35
	env.glow_strength = 0.8
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	# Sólo radios pequeños: un halo cercano a las luces, sin velo sobre todo el cielo (en el vacío el cielo es negro
	# incluso junto al Sol).
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 0.7)
	env.set_glow_level(2, 0.6)
	env.set_glow_level(3, 0.0)
	env.set_glow_level(4, 0.0)
	env.adjustment_enabled = GameSettings.post_effects
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08
	if body.has_atmosphere():
		env.ambient_light_color = Color(0.55, 0.5, 0.45)
		env.ambient_light_energy = 0.35
		# Bruma por distancia (exponencial, sin niebla de altura: el "arriba" no es +Y).
		# Visibilidad del orden de 100 km en superficie; se desvanece con la altitud.
		_visual_density = float(atmo.get("visual_density", 0.5))
		_fog_base_density = 2.5e-5 * _visual_density
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_density = _fog_base_density
		env.fog_height_density = 0.0
		env.fog_sky_affect = 0.0
		env.fog_sun_scatter = 0.15
		env.fog_light_color = _atmo_color
	else:
		env.ambient_light_color = Color(0.5, 0.52, 0.6)
		env.ambient_light_energy = 0.08  # sin atmósfera: sombras casi negras
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	# Hora inicial: media mañana en la longitud 0.
	time_s = body.solar_day_s() * 0.15
	_update_sun()


## Colores del cielo desde el JSON de la atmósfera (cenit, horizonte, puesta de sol; visibilidad del Sol).
func _apply_sky_colors(atmo: Dictionary) -> void:
	var sky: Dictionary = atmo.get("sky", {})
	if sky.has("horizon"):
		var h: Array = sky["horizon"]
		_atmo_color = Color(h[0], h[1], h[2])
		sky_mat.set_shader_parameter("atmosphere_color", _atmo_color)
	var z: Array = sky.get("zenith", [_atmo_color.r * 0.6, _atmo_color.g * 0.6, _atmo_color.b * 0.6])
	sky_mat.set_shader_parameter("zenith_color", Color(z[0], z[1], z[2]))
	if sky.has("sunset"):
		var s: Array = sky["sunset"]
		sky_mat.set_shader_parameter("sunset_color", Color(s[0], s[1], s[2]))
	var light := float(atmo.get("surface_light", {}).get("value", 1.0)) if atmo.get("surface_light") is Dictionary else 1.0
	sky_mat.set_shader_parameter("sun_visibility", clampf(light * 4.0, 0.0, 1.0))
	if atmo.has("visual_density"):
		sky_mat.set_shader_parameter("atmosphere_density", float(atmo["visual_density"]) if bool(atmo.get("present", false)) else 0.0)


func _update_earth_light(up: Vector3, cam_bf: DVec3) -> void:
	var e := 0.0
	if system != null and cam_bf != null and anchor != "earth" and system.has_body("earth") 			and system.body("earth").surface_type() == "shattered":
		var rel := system.position_in_frame("earth", anchor).sub(cam_bf)
		var d := rel.length()
		var ang := system.body("earth").radius_m() * 1.3 / maxf(d, 1.0)
		var dir := rel.mul(1.0 / maxf(d, 1.0)).to_vector3()
		var above := clampf((dir.dot(up) + 0.05) / 0.15, 0.0, 1.0)
		e = clampf(0.035 * pow(ang / 0.02, 2.0), 0.0, 0.05) * above
		if e > 0.001:
			var hint := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
			earth_light.transform = Transform3D(Basis.looking_at(-dir, hint), Vector3.ZERO)
	earth_light.light_energy = e
	earth_light.visible = e > 0.001


func sun_direction_bf() -> Vector3:
	if system != null:
		var sp := system.sun_in_frame(anchor)
		if _obs_bf != null:
			sp = sp.sub(_obs_bf)   # dirección desde el observador (imprescindible si el ancla es el propio Sol)
		if sp.length() < 1.0:
			return Vector3.UP
		return sp.normalized().to_vector3()
	var day := body.solar_day_s()
	var ang := TAU * time_s / day
	return Vector3(sin(ang) * cos(_decl), sin(_decl), cos(ang) * cos(_decl)).normalized()


## Actualiza el Sol y el cielo para un observador en `up` (unitario) a `altitude_m`.
func update_for_observer(up: Vector3, altitude_m: float, delta: float, cam_bf: DVec3 = null, pixel_angle: float = 0.0015) -> void:
	time_s += delta * time_scale
	if system != null:
		system.time_scale = time_scale
		sun_distance_au = system.sun_in_frame(anchor).length() / Ephemeris.AU
		# Iluminación: 1/d² comprimida (exponente 0,4) para que los planetas exteriores no queden negros en un
		# monitor sin exposición automática; el Sol aparente sí tiene su tamaño real (ADR-025).
		sun.light_energy = clampf(1.25 * pow(1.0 / maxf(sun_distance_au * sun_distance_au, 1e-4), 0.4), 0.05, 4.0) * _light_factor 			* sun_occlusion(cam_bf)
		if observer_sys_override != null:
			cam_bf = Ephemeris.to_frame(system.axes(anchor), observer_sys_override.sub(system.position(anchor)))
		_obs_bf = cam_bf
		if cam_bf != null and system_sky != null:
			# Rendimiento (ronda 9): recalcular todos los cuerpos cuesta ~2 ms; a 10 Hz basta salvo si la cámara
			# se desplaza deprisa (vuelo, viaje), porque entonces cambian sus direcciones.
			_sky_t -= delta
			var moved := 0.0 if _sky_last == null else cam_bf.distance_to(_sky_last)
			if _sky_t <= 0.0 or moved > 2000.0 or _sky_last == null:
				_sky_t = 0.1
				_sky_last = cam_bf.copy()
				system_sky.update(sky_mat, anchor, cam_bf, pixel_angle, delta)
			else:
				sky_mat.set_shader_parameter("time", fmod(system.time_s, 100000.0))
	_update_sun()
	_update_earth_light(up, cam_bf)
	sky_mat.set_shader_parameter("local_up", up)
	var scale_h := 9000.0
	var atmo := body.atmosphere()
	if atmo.has("scale_height"):
		scale_h = float(atmo["scale_height"].get("value", 9000.0))
	var alt_factor := exp(-maxf(altitude_m, 0.0) / scale_h)
	sky_mat.set_shader_parameter("altitude_factor", alt_factor)
	if body.atmosphere().get("surface_light") is Dictionary:
		# Venus y Titán: la luz que atraviesa la atmósfera disminuye al descender.
		var sl := float(body.atmosphere()["surface_light"]["value"])
		_light_factor = lerpf(sl, 1.0, 1.0 - alt_factor) if sl < 0.9 else 1.0
	if _fog_base_density > 0.0:
		var day := clampf(sun_direction_bf().dot(up) * 3.0 + 0.25, 0.0, 1.0)
		var env := world_env.environment
		env.fog_density = _fog_base_density * alt_factor
		# Mismo color que el horizonte del shader del cielo (atmosphere_color·1,1·día·densidad).
		var dens := clampf(_visual_density * alt_factor, 0.0, 1.0)
		env.fog_light_color = _atmo_color * (1.1 * day * dens + 0.03)


## Atmósfera alrededor de la cámara (ADR-029): color del cielo, niebla al atravesar nubes, oscuridad y rayos
## en las profundidades de los gigantes, luz solar atenuada. Se llama cada fotograma tras update_for_observer.
var _flash := 0.0


func flash_amount() -> float:
	return _flash
var _flash_timer := 2.0


func update_atmosphere(model: AtmosphereModel, alt: float, delta: float) -> void:
	if model == null or not model.present():
		sky_mat.set_shader_parameter("deep_amount", 0.0)
		sky_mat.set_shader_parameter("lightning", 0.0)
		return
	var light := model.light_fraction(alt)
	var deep := 0.0
	var deep_col := Color(0, 0, 0)
	var cl := model.cloud_at(alt)
	var env := world_env.environment
	if model.kind == "gas_giant":
		var p_bar := model.pressure(alt) / 1.0e5
		sky_mat.set_shader_parameter("atmosphere_density", clampf(p_bar * 1.2, 0.0, 1.0))
		sky_mat.set_shader_parameter("altitude_factor", 1.0)
		sky_mat.set_shader_parameter("zenith_color", model.sky_color("zenith", Color(0.3, 0.45, 0.8)) * 0.6)
		sky_mat.set_shader_parameter("atmosphere_color", model.sky_color("zenith", Color(0.3, 0.45, 0.8)))
		var dc: Array = body.atmosphere().get("deep_color", [0.3, 0.2, 0.1])
		if not cl.is_empty():
			deep = float(cl["opacity"])
			deep_col = model.color_of(cl)
		var clouds: Array = body.atmosphere().get("clouds", [])
		if not clouds.is_empty() and p_bar > float(clouds[0]["p_top_bar"]):
			deep = maxf(deep, clampf((p_bar - float(clouds[0]["p_top_bar"])) / 2.0, 0.3, 1.0))
			if cl.is_empty():
				deep_col = Color(dc[0], dc[1], dc[2])
	else:
		if not cl.is_empty():
			deep = float(cl["opacity"])
			deep_col = model.color_of(cl)
	deep_col = deep_col * clampf(light * 1.5 + 0.02, 0.0, 1.0)
	# Muy abajo en un gigante el gas está a más de 1000 K: brilla débilmente en rojo (cuerpo negro), lo único
	# que se ve cuando ya no llega la luz del Sol.
	var tk := model.temperature(alt)
	var glow := clampf((tk - 900.0) / 1800.0, 0.0, 1.0)
	if glow > 0.0:
		deep_col += Color(0.55, 0.13, 0.03) * glow
		deep = maxf(deep, glow)
	sky_mat.set_shader_parameter("deep_amount", deep)
	sky_mat.set_shader_parameter("deep_color", deep_col)
	# Niebla para los objetos 3D (la nave por fuera): espesa dentro de las nubes y en las profundidades.
	if deep > 0.05:
		env.fog_enabled = true
		env.fog_density = 3.0 / lerpf(20000.0, 250.0, deep)
		env.fog_light_color = deep_col
		env.fog_sky_affect = 0.0
	# Rayos en las nubes de agua de Júpiter y Saturno (y en las profundidades).
	var storms := bool(body.atmosphere().get("lightning", false)) and model.kind == "gas_giant" \
		and model.pressure(alt) > 3.0e5
	_flash_timer -= delta
	if storms and _flash_timer <= 0.0:
		_flash = randf_range(0.5, 1.0)
		_flash_timer = randf_range(1.5, 6.0)
	_flash = maxf(0.0, _flash - delta * 6.0)
	sky_mat.set_shader_parameter("lightning", _flash)
	_light_factor = clampf(light, 0.0005, 1.0) + _flash * 0.6


## Eclipse por el propio cuerpo (ronda 8): 0 si el planeta está entre el observador y el Sol, con penumbra suave
## del tamaño angular del Sol. Antes el Sol iluminaba desde debajo del horizonte en la cara nocturna.
func sun_occlusion(obs_bf: DVec3) -> float:
	if obs_bf == null:
		return 1.0
	var s := sun_direction_bf()
	var p := obs_bf.to_vector3()
	var along := p.dot(s)
	var r := body.radius_m()
	if along >= 0.0 and p.length() > r * 0.999:
		return 1.0
	var perp := (p - s * along).length()
	var sun_ang := 0.00465 / maxf(sun_distance_au, 0.05) * p.length()   # radio aparente del Sol proyectado (m)
	var edge := r - 2.0
	return clampf((perp - edge) / maxf(sun_ang * 2.0, 50.0) + 0.5, 0.0, 1.0) if along < 0.0 else 1.0


func _update_sun() -> void:
	var d := sun_direction_bf()
	# La luz direccional apunta en su -Z: debe mirar desde el Sol hacia el planeta.
	var up_hint := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	sun.transform = Transform3D(Basis.looking_at(-d, up_hint), Vector3.ZERO)  # el padre está en el origen
