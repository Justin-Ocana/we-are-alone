extends Node
## Prueba de las bases procedurales del NEXUS (ronda 12, ADR-048), headless: en Mercurio, Venus, Marte, Europa y
## Titán comprueba que la instalación se genera (módulos, pasillos, luces, presupuesto de mallas), que está en el
## lado de DÍA, que el suelo interior, la rampa y los vanos tienen la colisión esperada, que el astronauta se
## sostiene dentro del núcleo, que se puede recoger el componente y que entonces suena su registro de audio.
## También que la misma semilla da la misma planta. Uso: --nexus-smoke.

const BODIES := ["mercury", "venus", "mars", "europa", "titan"]

var main: Node
var world: SurfaceWorld
var failures := 0
var checks := 0
var _i := -1
var _step := 0
var _t := 0.0
var _build_ms := 0


func _ready() -> void:
	_next_body()


func check(cond: bool, what: String) -> void:
	checks += 1
	print("  %s  %s" % ["PASA " if cond else "FALLA", what])
	if not cond:
		failures += 1


func _finish() -> void:
	print("NEXUS-SMOKE RESULTADO: %d comprobaciones, %d fallidas" % [checks, failures])
	get_tree().quit(failures)


func _next_body() -> void:
	_i += 1
	if _i >= BODIES.size():
		_finish()
		return
	_step = 0
	_t = 0.0
	var t0 := Time.get_ticks_msec()
	world = main.start_world(BODIES[_i], 12.0, 31.0, false, false)
	_build_ms = Time.get_ticks_msec() - t0
	world.dialogue.simulate = true
	print("NEXUS-SMOKE: ", BODIES[_i])


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.bit(Layers.PHYS_SHIP))
	return world.get_world_3d().direct_space_state.intersect_ray(q)


func _physics_process(delta: float) -> void:
	if world == null or not world.surface_ready:
		return
	_t += delta
	var nx := world.nexus
	var id: String = BODIES[_i]
	match _step:
		0:
			var o := nx.outpost
			check(o != null, "%s: se genera la base del NEXUS (mundo en %d ms)" % [id, _build_ms])
			if o == null:
				_next_body()
				return
			var meshes := 0
			for c in nx._site.get_children():
				if c is MeshInstance3D:
					meshes += 1
			check(o.modules.size() >= 6 and o.modules.size() <= 9, "%s: %d módulos y %d pasillos" % [id, o.modules.size(), o.links.size()])
			check(meshes < 140, "%s: %d mallas agrupadas (presupuesto < 140)" % [id, meshes])
			check(o.lights.size() <= 24, "%s: %d luces" % [id, o.lights.size()])
			var el := nx.sun_elevation(id, nx.site_dir(id))
			check(el > 0.5, "%s: la instalación está de día (Sol a %.0f° de altura)" % [id, rad_to_deg(asin(clampf(el, -1.0, 1.0)))])
			# Misma semilla → misma planta (todos los equipos de la partida generan la misma base).
			var o2 := NexusOutpost.new()
			var holder := Node3D.new()    # fuera del árbol: sin colisiones que estorben
			o2.build(holder, hash("nexus:" + id), o.ground, "x")
			var same := o2.modules.size() == o.modules.size() and o2.links.size() == o.links.size() and absf(o2.floor_y - o.floor_y) < 1e-4
			holder.free()
			check(same, "%s: la misma semilla genera la misma planta" % id)
			# El astronauta, dentro del núcleo junto al pedestal.
			var target := nx._local_to_bf(o.core_local + Vector3(1.4, 0.15, 0))
			var dir := target.normalized()
			world.player.place_on_surface(dir, target.length() - (world.terrain.radius + world.terrain.height_at_dir(dir)))
			_t = 0.0
			_step = 1
		1:
			if _t > 2.5:
				var o := nx.outpost
				var floor_p := FloatingOrigin.to_local(nx._local_to_bf(o.core_local))
				var hgt := (world.player.global_position - floor_p).dot(nx._up.to_vector3())
				var spot := FloatingOrigin.to_local(nx._local_to_bf(o.core_local + Vector3(1.4, 0, 0)))
				var drift := (world.player.global_position - spot).length()
				check(absf(hgt) < 0.25 and drift < 0.3, "%s: el astronauta se sostiene en el suelo del núcleo (%.2f m; desvío %.2f m)" % [id, hgt, drift])
				# Colisiones (ya junto al origen, con precisión): suelo del núcleo, rampa de la entrada, vano libre.
				var core := FloatingOrigin.to_local(nx._local_to_bf(o.core_local + Vector3(2.5, 0, 0)))
				var up := nx._up.to_vector3()
				var hit := _ray(core + up * 1.0, core - up * 1.0)
				check(not hit.is_empty() and absf((hit["position"] - core).dot(up)) < 0.05, "%s: el suelo del núcleo tiene colisión" % id)
				var rend: Vector2 = o.entry["ramp_end"]
				var edge: Vector2 = o.entry["edge"]
				var ramp_ok := true
				for k in 5:
					var p2 := edge.lerp(rend, 0.1 + 0.2 * k)
					var top := FloatingOrigin.to_local(nx._local_to_bf(Vector3(p2.x, o.floor_y + 2.0, p2.y)))
					var h := _ray(top, top - up * 30.0)
					ramp_ok = ramp_ok and not h.is_empty()
				check(ramp_ok, "%s: el rellano y la rampa de la entrada tienen colisión (desnivel %.1f m)" % [id, float(o.entry["drop"])])
				var out: Vector2 = o.entry["out"]
				var a := FloatingOrigin.to_local(nx._local_to_bf(Vector3(edge.x - out.x * 1.5, o.floor_y + 1.2, edge.y - out.y * 1.5)))
				var b := FloatingOrigin.to_local(nx._local_to_bf(Vector3(edge.x + out.x * 1.5, o.floor_y + 1.2, edge.y + out.y * 1.5)))
				check(_ray(a, b).is_empty(), "%s: el vano de la entrada está libre" % id)
				var across := Vector2(-out.y, out.x)
				var wa := edge + across * 2.6
				var c1 := FloatingOrigin.to_local(nx._local_to_bf(Vector3(wa.x - out.x * 1.0, o.floor_y + 1.2, wa.y - out.y * 1.0)))
				var c2 := FloatingOrigin.to_local(nx._local_to_bf(Vector3(wa.x + out.x * 1.0, o.floor_y + 1.2, wa.y + out.y * 1.0)))
				check(not _ray(c1, c2).is_empty(), "%s: la pared junto a la entrada es sólida" % id)
				var it := nx.nearest_interaction(world.player)
				var dcore := FloatingOrigin.to_local(nx._core_bf).distance_to(world.player.global_position + world.player.global_transform.basis.y)
				check(not it.is_empty(), "%s: el componente se puede recoger desde el pedestal (a %.2f m)" % [id, dcore])
				nx.interact(world.player, "nexus", "nexus")
				check(nx.has_component(id), "%s: componente recogido" % id)
				check(world.dialogue.current == "nexus_" + id or world.dialogue.heard.has("nexus_" + id),
					"%s: suena su registro de audio (%s)" % [id, world.dialogue.current])
				check(world.dialogue.has_audio("nexus_" + id), "%s: el audio existe en el proyecto" % id)
				_next_body()
