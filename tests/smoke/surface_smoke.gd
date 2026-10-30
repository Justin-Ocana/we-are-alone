extends Node
## Prueba de integración del Hito 1 (headless, con --fixed-fps 60):
## carga real del terreno → reposo sobre el suelo → caminar → saltar → volar 10 km con
## recentrados del origen → aterrizar → repetir lo básico en la Luna.
## Sale con código = nº de comprobaciones fallidas.

var main: Node
var world: SurfaceWorld
var failures := 0
var checks := 0

var _phase := ""
var _t := 0.0
var _t_real0 := 0
var _start_bf: DVec3
var _start_r := 0.0
var _max_r := 0.0
var _shifts0 := 0
var _world_queue := [["proto_a", 12.0, 31.0], ["moon", -20.0, 140.0]]
var _full_run := true


var _t_detail := -1

func _ready() -> void:
	_next_world()


func _next_world() -> void:
	if _world_queue.is_empty():
		_finish()
		return
	var w: Array = _world_queue.pop_front()
	print("SMOKE: mundo %s (lat %.1f, lon %.1f)" % w)
	world = main.start_world(w[0], w[1], w[2], false, false)  # sin nave: prueba aislada del planeta
	_set_phase("load")
	_t_real0 = Time.get_ticks_msec()


func _set_phase(p: String) -> void:
	_phase = p
	_t = 0.0
	for a in [&"move_forward", &"sprint", &"jump"]:
		Input.action_release(a)


func check(cond: bool, what: String) -> void:
	checks += 1
	if cond:
		print("  PASA  ", what)
	else:
		failures += 1
		print("  FALLA ", what)


func _physics_process(delta: float) -> void:
	if world == null or not is_instance_valid(world) or world.player == null:
		return
	_t += delta
	var pl := world.player
	var tr := world.terrain
	match _phase:
		"load":
			if world.surface_ready:
				var ms := Time.get_ticks_msec() - _t_real0
				check(tr.stat_deepest >= tr.max_level - 1, "terreno generado hasta el nivel %d/%d en %d ms (nodos %d, dibujados %d)" % [tr.stat_deepest, tr.max_level, ms, tr.stat_nodes, tr.stat_drawn])
				print("  PERF  ", tr.profile_text())
				check(tr.stat_colliders > 0, "hay colisión bajo el jugador (%d parches)" % tr.stat_colliders)
				_set_phase("settle")
			elif Time.get_ticks_msec() - _t_real0 > 120000:
				check(false, "el terreno no estuvo listo a tiempo")
				_finish()
		"settle":
			if _t > 2.0:
				check(pl.is_on_floor(), "el astronauta reposa sobre el suelo")
				check(absf(pl.altitude_m) < 0.6, "altitud sobre el terreno analítico %.3f m" % pl.altitude_m)
				var g_expected := world.body.gravity_at_distance(pl.position_bf().length())
				check(absf(pl.gravity_mps2 - g_expected) < 1e-9, "gravedad local %.4f m/s²" % pl.gravity_mps2)
				check(pl.up_direction.dot(pl.position_bf().normalized().to_vector3()) > 0.99999, "up_direction radial")
				_check_body(pl, "de pie")
				_start_bf = pl.position_bf()
				_set_phase("walk")
				Input.action_press(&"move_forward")
				Input.action_press(&"sprint")
		"walk":
			if _t > 10.0:
				Input.action_release(&"move_forward")
				Input.action_release(&"sprint")
				var dist := pl.position_bf().distance_to(_start_bf)
				var expected_run := Astronaut.RUN_SPEED * Gait.max_speed_factor(pl.gravity_mps2) * 10.0
				check(dist > expected_run * 0.7, "corrió %.1f m en 10 s (máx. teórico %.0f m, marcha: %s)" % [dist, expected_run, Gait.Kind.keys()[pl.rig.gait_kind]])
				check(pl.altitude_m > -0.5 and pl.altitude_m < 1.5, "sigue sobre el terreno tras caminar (alt %.3f m)" % pl.altitude_m)
				check(pl.ground_clamps == 0, "sin intervenciones de la salvaguarda de suelo (%d)" % pl.ground_clamps)
				_set_phase("prejump")
		"prejump":
			if _t > 1.5:
				_start_r = pl.position_bf().length()
				_max_r = _start_r
				_set_phase("jump")
				Input.action_press(&"jump")
		"jump":
			if _t > 0.05:
				Input.action_release(&"jump")
			_max_r = maxf(_max_r, pl.position_bf().length())
			if _t > 4.0:
				var g := world.body.surface_gravity()
				var expected := Astronaut.JUMP_TAKEOFF_SPEED * Astronaut.JUMP_TAKEOFF_SPEED / (2.0 * g)
				var got := _max_r - _start_r
				check(absf(got - expected) < maxf(0.15, expected * 0.25), "altura del salto %.2f m (teórica %.2f m)" % [got, expected])
				check(pl.is_on_floor(), "aterriza tras el salto")
				if not _full_run:
					_next_world()
					return
				_start_bf = pl.position_bf()
				_shifts0 = FloatingOrigin.shift_count
				pl.set_flying(true)
				pl.fly_speed = 2000.0
				pl.set_look_pitch(0.3)  # 17° hacia arriba: la trayectoria recta libra el relieve
				_set_phase("fly")
				Input.action_press(&"move_forward")
		"fly":
			if _t > 5.0:
				Input.action_release(&"move_forward")
				var dist := pl.position_bf().distance_to(_start_bf)
				check(absf(dist - 10000.0) < 100.0, "vuelo de %.1f m (esperado 10.000 m)" % dist)
				check(FloatingOrigin.shift_count - _shifts0 >= 8, "recentrados del origen durante el vuelo: %d" % (FloatingOrigin.shift_count - _shifts0))
				check(pl.global_position.length() < FloatingOrigin.threshold_m + 2000.0 * delta + 1.0, "posición local acotada (%.1f m)" % pl.global_position.length())
				world.wait_for_surface()
				_t_real0 = Time.get_ticks_msec()
				_t_detail = -1
				_set_phase("reload")
		"reload":
			if _t_detail < 0 and world.terrain.stat_deepest >= world.terrain.max_level:
				_t_detail = Time.get_ticks_msec() - _t_real0
				print("  INFO  detalle máximo bajo el jugador en %d ms" % _t_detail)
			if world.surface_ready:
				print("  INFO  terreno regenerado tras el vuelo en %d ms" % (Time.get_ticks_msec() - _t_real0))
				_set_phase("settle2")
			elif Time.get_ticks_msec() - _t_real0 > 120000:
				check(false, "el terreno no se regeneró tras el vuelo")
				_finish()
		"settle2":
			if _t > 2.0:
				check(pl.is_on_floor(), "aterrizaje a 10 km: sobre el suelo")
				check(absf(pl.altitude_m) < 0.6, "aterrizaje a 10 km: altitud %.3f m" % pl.altitude_m)
				_full_run = false
				_next_world()


## Comprobaciones del cuerpo: pies sobre el suelo, ojos a la altura correcta, cámara válida.
func _check_body(pl: Astronaut, when: String) -> void:
	var up := pl.global_transform.basis.y
	for s in 2:
		var foot := pl.rig.ankles[s].global_position
		var foot_alt := (foot - pl.global_position).dot(up)
		check(foot_alt > 0.0 and foot_alt < 0.2, "%s: tobillo %d a %.3f m sobre los pies del cuerpo" % [when, s, foot_alt])
	var eye_h := (pl.rig.eye_marker.global_position - pl.global_position).dot(up)
	check(absf(eye_h - Units.ASTRONAUT_EYE_HEIGHT_M) < 0.06, "%s: ojos a %.3f m" % [when, eye_h])
	var cam := pl.active_camera()
	var cam_h := (cam.global_position - pl.global_position).dot(up)
	check(cam.current and absf(cam_h - eye_h) < 0.15, "%s: cámara en los ojos (%.3f m)" % [when, cam_h])


func _finish() -> void:
	print("SMOKE RESULTADO: %d comprobaciones, %d fallidas" % [checks, failures])
	set_physics_process(false)
	get_tree().quit(failures)
