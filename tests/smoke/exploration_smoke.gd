extends Node
## Prueba de integración de las acciones de exploración y de la nave (ADR-034) y del guardado (SaveGame).
## Uso: --exploration-smoke (headless). Sale con el número de fallos.

var main: Node
var world: SurfaceWorld
var failures := 0
var checks := 0
var _step := 0
var _t := 0.0
var _saved_time := 0.0
var _saved_ship := DVec3.new()


func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("  %s %s" % ["PASA  " if ok else "FALLA ", msg])


func _finish() -> void:
	print("EXPLORATION-SMOKE RESULTADO: %d comprobaciones, %d fallidas" % [checks, failures])
	get_tree().quit(failures)


func _ready() -> void:
	print("EXPLORATION-SMOKE: inicio")
	world = main.start_world("moon", main.SPAWN_LAT, main.SPAWN_LON, false, true)


func _hud() -> ExplorationHud:
	return world.player.exploration_hud


func _goto(local: Vector3) -> void:
	var pl := world.player
	pl.global_transform = Transform3D(world.ship.global_transform.basis, world.ship.global_transform * local)
	pl.velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if world == null or not world.surface_ready:
		return
	_t += delta
	var pl := world.player
	var log := world.exploration
	match _step:
		0:
			if _t < 1.0:
				return
			check(pl.exploration_hud != null and world.journal != null, "interfaz de exploración y diario creados")
			# Balizas (ronda 11): plantar dos, recoger una con la interacción.
			world.exploration_ctl._on_action("beacon", pl)
			world.exploration_ctl._on_action("beacon", pl)
			check(log.beacons.size() == 2 and world.beacons._nodes.size() == 2, "dos balizas plantadas (%d)" % log.beacons.size())
			var bit: Dictionary = world.beacons.nearest_interaction(pl)
			check(str(bit.get("id", "")).begins_with("beacon:"), "baliza al alcance para recogerla (%s)" % str(bit))
			pl._interact()
			check(log.beacons.size() == 1, "baliza recogida con la tecla de interactuar (%d)" % log.beacons.size())
			# Muestra: mirando al suelo, fuera de la nave.
			pl.set_look_pitch(-1.2)
			_next()
		1:
			if _t < 0.5:
				return
			world.exploration_ctl._on_action("scan", pl)
			check(log.samples.size() == 1 and log.pending_samples() == 1, "muestra recogida mirando al suelo (%d)" % log.samples.size())
			# Escáner mirando al cielo: la Tierra destruida está a ~40° sobre el horizonte.
			pl.set_look_pitch(0.0)
			world.exploration_ctl._scan(pl)
			check(log.scans.size() >= 1, "escaneo registrado (%s)" % str(log.scans.keys()))
			check(log.visited.has("moon"), "primera visita a la Luna anotada")
			_goto(Vector3(-8.0, 0.05, 0.8) + Vector3(0.6, 0, 0))
			_next()
		2:
			if _t < 0.6:
				return
			check(pl.aboard == world.ship, "a bordo para usar los puestos")
			check(pl.interaction_hint.contains("Dormir"), "indicación junto a la litera: '%s'" % pl.interaction_hint)
			_saved_time = world.system.time_s
			pl.health = 40.0
			pl._interact()
			_next()
		3:
			if _t < 5.0:
				return
			check(world.system.time_s - _saved_time > 8.0 * 3600.0 - 10.0, "dormir adelanta el reloj 8 h (%.1f h)" % ((world.system.time_s - _saved_time) / 3600.0))
			check(pl.health >= 99.0 and not pl.input_blocked, "tras dormir: salud %.0f, control devuelto" % pl.health)
			_goto(Vector3(-4.0, 0.05, 3.6))
			_next()
		4:
			if _t < 0.6:
				return
			check(pl.interaction_hint.contains("Laboratorio"), "indicación junto al laboratorio: '%s'" % pl.interaction_hint)
			pl._interact()
			check(log.pending_samples() == 0 and str(log.samples[0]["report"]).contains("Composición"), "muestra analizada en el laboratorio")
			_goto(Vector3(5.0, 0.05, 2.7))
			pl.jet_fuel = 0.1
			_next()
		5:
			if _t < 0.6:
				return
			pl._interact()
			check(pl.jet_fuel >= 0.99, "taquilla de trajes: propulsores recargados")
			world.ship.state.hull_integrity = 55.0
			_goto(Vector3(4.5, 0.05, 10.2))
			_next()
		6:
			if _t < 0.6:
				return
			pl._interact()
			check(world.ship.state.hull_integrity >= 99.9, "consola de ingeniería: casco reparado")
			world.exploration_ctl._quick_menu(pl)
			check(_hud().menu_open() and pl.input_blocked, "menú rápido abierto")
			_hud().close_menu()
			check(not _hud().menu_open() and not pl.input_blocked, "menú rápido cerrado")
			world.open_journal(pl)
			check(world.journal.is_open(), "diario abierto")
			world.journal.close()
			# Guardado: estado actual → archivo → mundo nuevo.
			_saved_ship = world.ship.state.pos_bf.copy()
			_saved_time = world.system.time_s
			check(SaveGame.save(world), "partida guardada en %s" % SaveGame.path)
			var d := SaveGame.load_data()
			check(not d.is_empty() and d["anchor"] == "moon" and d["players"][0]["aboard"] == true, "partida legible (a bordo)")
			var ll := SaveGame.spawn_latlon(d)
			world = main.start_world(str(d["anchor"]), ll.x, ll.y, false, true)
			SaveGame.apply(world, d)
			_next()
		7:
			if _t < 2.0:
				return
			check(world.ship.state.pos_bf.distance_to(_saved_ship) < 1.0, "nave restaurada en su posición (%.3f m)" % world.ship.state.pos_bf.distance_to(_saved_ship))
			check(absf(world.system.time_s - _saved_time) < 120.0, "fecha del juego restaurada (dif %.1f s)" % (world.system.time_s - _saved_time))
			check(world.player.aboard == world.ship, "jugador restaurado a bordo")
			check(world.exploration.samples.size() == 1 and world.exploration.scans.size() >= 1, "diario restaurado")
			check(world.exploration.beacons.size() == 1 and world.beacons._nodes.size() == 1, "la baliza se guarda y se restaura")
			_finish()


func _next() -> void:
	_step += 1
	_t = 0.0
