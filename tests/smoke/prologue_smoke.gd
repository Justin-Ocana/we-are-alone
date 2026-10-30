extends Node
## Prueba de integración del prólogo en la base LF-01 (ADR-043, headless): partida nueva en la cápsula y recorrido
## completo hasta la superficie, comprobando objetivos, puertas, energía, diálogos (orden, sin voces superpuestas,
## una sola vez), mensaje obligatorio de Magnus, traje, esclusa, fin del prólogo y guardado/carga a mitad.
## Los diálogos se simulan (0,3 s por línea). Uso: --prologue-smoke.

var main: Node
var world: SurfaceWorld
var failures := 0
var checks := 0
var _step := 0
var _t := 0.0
var _started: Array = []          ## ids de las líneas que empezaron, en orden
var _overlap := false
var _playing := false
var _saved := {}
var _phase_t := 0.0


func _ready() -> void:
	world = main.start_world("moon", BaseLayout.SITE_LAT, BaseLayout.SITE_LON, false, true, false, true)
	_hook()


func _hook() -> void:
	world.dialogue.simulate = true
	world.dialogue.line_started.connect(func(id: String, _sp: String, _sk: bool):
		if _playing:
			_overlap = true
		_playing = true
		_started.append(id))
	world.dialogue.line_finished.connect(func(_id: String, _s: bool): _playing = false)


func check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
	print(("  PASA   " if cond else "  FALLA  ") + what)


func _finish() -> void:
	print("PROLOGUE-SMOKE RESULTADO: %d comprobaciones, %d fallidas" % [checks, failures])
	get_tree().quit(failures)


## Coloca al jugador en un punto de la base mirando a otro.
func _go(p: Vector3, look: Vector3 = Vector3.INF) -> void:
	var pl := world.player
	var b := world.base
	pl.place_on_surface(b.point_bf(p).normalized(), 0.05)
	if look != Vector3.INF:
		var up := pl.global_transform.basis.y
		var dir := b.to_engine(look) - pl.global_position
		var flat := (dir - up * dir.dot(up)).normalized()
		pl.global_transform.basis = Basis(up.cross(-flat).normalized(), up, -flat).orthonormalized()


func _use(id: String) -> void:
	var t: Array = BaseLayout.TERMINALS[id]
	world.base.interact(world.player, id, t[3])


## Oída o al menos pedida (las líneas duran 0,3 s simulados y se encadenan con pausas).
func _heard(id: String) -> bool:
	return world.dialogue.heard.has(id) or id in _started or world.dialogue.current == id or id in world.dialogue._queue


func _next() -> void:
	_step += 1
	_t = 0.0


func _saved_reload() -> void:
	var ll := SaveGame.spawn_latlon(_saved)
	world = main.start_world("moon", ll.x, ll.y, false, true)
	_hook()
	_step = 17
	_t = 0.0


func _process(delta: float) -> void:
	if world == null or not world.surface_ready:
		return
	_t += delta
	var pr := world.prologue
	var pl := world.player
	var base := world.base
	match _step:
		0:
			check(pr.step == "despertar" and pl.move_locked and not pl.suit_on, "partida nueva: despierta en la cápsula, sin traje y sin poder andar")
			check(world.ship != null and world.ship.immobilized, "la nave está inmovilizada en el hangar")
			var ship_local := base.to_base(world.ship.global_position)
			check(BaseLayout.room_at(ship_local + Vector3(0, 1, 0)) == "hangar", "la nave descansa dentro del hangar (%s)" % str(ship_local))
			check(base.room_of(pl) == "crio", "el jugador está en la cámara criogénica")
			var lp := base.to_base(pl.global_position)
			check(Vector2(lp.x, lp.z).distance_to(Vector2(0.0, -98.6)) < 0.3, "despierta DENTRO de su cápsula (%s)" % str(lp))
			# Colisiones de la base (ronda 11: la capa estaba mal y se atravesaban las paredes).
			var space := pl.get_world_3d().direct_space_state
			var a := base.to_engine(Vector3(0.0, 1.2, -73.0))
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(a, base.to_engine(Vector3(4.0, 1.2, -73.0)), Layers.solid_mask()))
			check(not hit.is_empty() and base.to_base(hit["position"]).x < 1.7, "las paredes de la base son sólidas para el astronauta")
			var hit2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(base.to_engine(Vector3(lp.x, 1.0, lp.z)),
				base.to_engine(Vector3(lp.x, 1.0, lp.z + 1.5)), Layers.solid_mask(), [pl.get_rid()]))
			check(not hit2.is_empty(), "la puerta cerrada de la cápsula impide salir antes de tiempo")
			_next()
		1:
			if pr.step == "salir_capsula":
				check(_started.slice(0, 1) == ["p01"] and _heard("p02"), "audio 1 al empezar y audio 2 al abrirse la cápsula (%s)" % str(_started))
				check(pl.move_locked, "hasta salir de la cápsula no se anda")
				_use("capsula")
				check(not pl.move_locked and pr.step == "terminal_medico", "salir de la cápsula libera el movimiento")
				_go(Vector3(1.0, 0, -97.4), Vector3(2.2, 1.1, -97.4))
				_next()
			elif _t > 20.0:
				check(false, "la cápsula no se abrió (paso %s)" % pr.step)
				_finish()
		2:
			if _t > 0.5:
				var it := base.nearest_interaction(pl)
				check(it.get("id", "") == "terminal_medico", "el terminal médico está al alcance (%s)" % str(it))
				_use("terminal_medico")
				check(pr.step == "orientacion", "tras el terminal: objetivo sala de orientación")
				_next()
		3:
			if _t > 1.0:
				check(_heard("p03") and _heard("p04"), "audios 3 y 4 del terminal médico")
				_go(Vector3(0, 0, -80.0))
				_next()
		4:
			if _t > 1.0 and not world.dialogue.is_busy():
				check(_heard("p05"), "audio 5 al poder moverse por el pasillo de recuperación")
				_use("terminal_danado")
				check(world.dialogue.current == "p08", "audio 8 al usar el terminal dañado")
				_go(Vector3(0, 0, -66.0))
				_next()
		5:
			if _t > 1.0:
				check(_heard("p09"), "audio 9 en el pasillo señalizado hacia orientación")
				_go(Vector3(-2.0, 0, -56.0), Vector3(6.6, 2.0, -56.0))
				_next()
		6:
			if pr.step == "mensaje" and world.dialogue.current == "magnus":
				check(_heard("p10") and _heard("p11") and _heard("p12"), "audios 10, 11 y 12 antes del mensaje de Magnus")
				check(pl.cinematic, "durante el mensaje el jugador sólo puede mirar")
				check(base.doors["d_eje"].is_locked(), "la puerta al eje sigue cerrada durante el mensaje")
				world.dialogue.skip()   # Espacio
				_next()
			elif _t > 20.0:
				check(false, "el mensaje de Magnus no empezó (paso %s, oídas %s)" % [pr.step, str(world.dialogue.heard.keys())])
				_finish()
		7:
			if _t > 1.0 and not world.dialogue.is_busy():
				check(not pl.cinematic and pr.step == "operaciones", "al omitir el mensaje: libre y objetivo operaciones")
				check(not base.doors["d_eje"].is_locked(), "se abre la puerta al eje central")
				check(_heard("p13"), "audio 13 al terminar la grabación")
				check(String(base.builder.labels["pantalla"].text).begins_with("OBJETIVOS"), "la pantalla muestra los objetivos")
				base.interact(pl, "door:d_sector", "door")
				check(world.dialogue.current == "p06", "audio 6 en una puerta sin energía")
				_go(Vector3(6.0, 0, -45.0), Vector3(8.4, 1.0, -43.0))
				_next()
		8:
			if _t > 1.0:
				check(pr.step == "consola", "en operaciones: usar la consola")
				_use("energia_aux")
				check(not base.lever_on, "la energía auxiliar no arranca sin pasar por la consola")
				_use("consola_ops")
				check(pr.step == "energia", "tras la consola: objetivo energía auxiliar")
				_go(Vector3(-13.0, 0, -39.0), Vector3(-14.4, 1.2, -39.0))
				_next()
		9:
			if _t > 1.0:
				_use("energia_aux")
				check(base.lever_on and pr.step == "restableciendo", "palanca de la energía auxiliar")
				_next()
		10:
			if pr.step == "hangar":
				check(base.power_aux and not base.doors["d_sector"].is_locked() and not base.doors["d_hangar"].is_locked(),
					"energía restablecida: se abren sólo las puertas hacia el hangar")
				check(base.doors["d_taller"].is_locked() and base.doors["d_despacho"].is_locked(), "las demás siguen cerradas")
				check(_heard("p14") and _heard("p15"), "audios 14 y 15")
				check(base.artificial_gravity and pl.in_habitat and pl.gravity_mps2 > 9.0,
					"con la energía, gravedad artificial de 1 g en la base (%.2f m/s²)" % pl.gravity_mps2)
				_saved = SaveGame.capture(world)
				_go(Vector3(0, 0, 36.0))
				_next()
			elif _t > 15.0:
				check(false, "la energía no se restableció")
				_finish()
		11:
			if _t > 1.5:
				check(_heard("p17"), "audio 17 (nuevo objetivo) aunque falte el 16")
				check(_heard("p18") and pr.step == "diagnostico", "audio 18 al entrar en el hangar")
				_go(Vector3(25.0, 0, 50.0), Vector3(26.0, 1.0, 50.0))
				_use("diagnostico")
				_next()
		12:
			if pr.step == "traje":
				check(_heard("p19"), "audio 19 tras el diagnóstico")
				_go(Vector3(43.4, 0, 59.0), Vector3(44.4, 1.1, 59.0))
				_use("traje")
				_next()
			elif _t > 12.0:
				check(false, "el diagnóstico no terminó")
				_finish()
		13:
			if _t > 2.5:
				check(pl.suit_on and pr.step == "oxigeno", "traje equipado (visor e interfaz)")
				_use("traje")
				_next()
		14:
			if pr.step == "esclusa":
				check(_heard("p20"), "audio 20 con el traje conectado")
				_go(Vector3(43.0, 0, 66.0), Vector3(44.4, 1.3, 66.6))
				_use("panel_esclusa")
				check(pr.step == "despresurizando" and base.doors["d_esclusa"].force_closed, "ciclo de la esclusa iniciado")
				_next()
			elif _t > 8.0:
				check(false, "no se completó la comprobación de oxígeno")
				_finish()
		15:
			if pr.step == "salir":
				check(_heard("p21") and _heard("p22"), "audios 21 y 22 en la esclusa")
				check(base.doors["d_exterior"].open > 0.0 or base.doors["d_exterior"].force_open, "la escotilla exterior se abre")
				_go(Vector3(52.0, 0, 63.0))
				_next()
			elif _t > 15.0:
				check(false, "la esclusa no terminó el ciclo")
				_finish()
		16:
			if _t > 1.0:
				check(pr.step == "completado" and not world.ship.immobilized and base.roof_target > 0.5,
					"fin del prólogo en la superficie: techo del hangar abriéndose y nave libre")
				check(not _overlap, "nunca sonaron dos voces a la vez")
				var counts := {}
				for id in _started:
					counts[id] = counts.get(id, 0) + 1
				var dup := []
				for id in counts:
					if counts[id] > 1 and not id in ["p06", "p07", "p08"]:
						dup.append(id)
				check(dup.is_empty(), "cada diálogo importante sonó una sola vez (%s)" % str(dup))
				check(pl.gravity_mps2 < 2.0, "fuera, gravedad lunar (%.2f m/s²)" % pl.gravity_mps2)
				# Reingreso por la esclusa: dentro, panel interior → presuriza → puerta al hangar libre.
				_go(Vector3(40.0, 0, 63.0), Vector3(44.4, 1.3, 66.6))
				_step = 50
				_t = 0.0
		50:
			if _t > 0.5:
				_go(Vector3(43.0, 0, 66.0), Vector3(44.4, 1.3, 66.6))
				_use("panel_esclusa")
				check(base.airlock_phase == "presurizando", "el panel interior presuriza para volver a entrar (%s)" % base.airlock_phase)
				_step = 51
				_t = 0.0
		51:
			if base.airlock_phase == "":
				check(not base.doors["d_esclusa"].force_closed and pl.in_habitat, "presurizada: la puerta al hangar se abre y vuelve el ambiente interior")
				check(base.roof_target > 0.99 and base.roof_open > 0.5, "las compuertas del techo del hangar se abren (%.2f)" % base.roof_open)
				# Desde fuera, el panel exterior vuelve a abrir la esclusa.
				_go(Vector3(47.0, 0, 61.2), Vector3(45.75, 1.3, 61.2))
				base.interact(pl, "panel_exterior", "airlock_ext")
				check(base.airlock_phase == "despresurizando", "el panel exterior abre la esclusa desde fuera")
				_step = 52
				_t = 0.0
		52:
			if _t > 0.5:
				check(not base.doors["d_taller"].is_locked(), "tras el prólogo se abren los talleres (componente lunar del NEXUS)")
				_go(Vector3(8.0, 0, 24.6), Vector3(8.0, 1.2, 26.0))
				_step = 53
				_t = 0.0
		53:
			if _t > 0.5:
				var it: Dictionary = world.nexus.nearest_interaction(pl)
				check(it.get("id", "") == "nexus", "el componente lunar del NEXUS está al alcance (%s)" % str(it))
				world.nexus.interact(pl, "nexus", "nexus")
				check(world.exploration.nexus == ["moon"] and world.nexus.next_body() == "mercury",
					"componente lunar recuperado; siguiente: Mercurio (%s)" % str(world.exploration.nexus))
				_saved_reload()
			elif _t > 20.0:
				check(false, "la esclusa no se presurizó (%s)" % base.airlock_phase)
				_finish()
		17:
			if world.surface_ready and _t > 0.2 and _phase_t == 0.0:
				_phase_t = 1.0
				SaveGame.apply(world, _saved)
			if _phase_t > 0.0:
				_phase_t += delta
			if _phase_t > 2.0:
				var p2 := world.prologue
				check(p2.step == "hangar" and p2.active, "al cargar se reanuda en el objetivo guardado (%s)" % p2.step)
				check(world.base.power_aux and not world.base.doors["d_hangar"].is_locked(), "la energía y las puertas se recuperan")
				check(world.dialogue.heard.has("p14") and world.dialogue.heard.has("magnus"), "los diálogos oídos se recuerdan")
				check(not world.player.move_locked and not world.player.cinematic, "el jugador puede moverse tras cargar")
				check(world.ship.immobilized, "la nave sigue inmovilizada hasta acabar el prólogo")
				_finish()
