class_name PlanetMarker
extends RefCounted
## Indicador del cuerpo celeste más cercano (ADR-023): dirección a su centro, nombre y altitud sobre la
## superficie. Hoy cada mundo carga un único cuerpo (el marco BF tiene su centro en el origen); la búsqueda
## del más cercano está preparada para cuando haya varios (Hito 3).


## Punto a 1 km de la cámara en la dirección del centro del cuerpo (evita proyectar puntos a millones de km).
static func _toward_center(astro: Astronaut) -> Vector3:
	var cam := astro.get_viewport().get_camera_3d()
	var from := cam.global_position if cam != null else astro.global_position
	var to_c := FloatingOrigin.to_global(from).mul(-1.0).normalized().to_vector3()
	return from + to_c * 1000.0


## {center: Vector3 (motor), name: String, sub: String} o {} si no hay cuerpo.
static func nearest(astro: Astronaut) -> Dictionary:
	if astro == null or astro.body_def == null or astro.terrain == null:
		return {}
	var bodies := [astro.body_def]   # Hito 3: todos los cuerpos cargados
	var best: BodyDef = null
	var best_alt := INF
	var p_bf := astro.position_bf()
	for body in bodies:
		var alt: float = p_bf.length() - astro.terrain.radius
		if alt < best_alt:
			best_alt = alt
			best = body
	if best == null:
		return {}
	var surface_alt := maxf(0.0, astro.altitude_m)
	return {
		"center": _toward_center(astro),
		"name": best.display_name.to_upper(),
		"sub": "%s de altitud" % Units.format_distance(surface_alt),
	}
