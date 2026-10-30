extends Node
## Sonda de temblor de cámara (diagnóstico): sentarse, despegar, volar, aterrizar, levantarse y medir el
## movimiento fotograma a fotograma de la cámara estando quieto. Uso: --shake-probe [--hover]

var main: Node
var hover := false
var third := false
var fast := false
var world: SurfaceWorld
var ship: Ship
var pl: Astronaut
var _step := 0
var _t := 0.0
var _prev_ship := Vector3.ZERO
var _prev_body := Vector3.ZERO
var _prev_rot := Quaternion.IDENTITY
var _prev_rel := Quaternion.IDENTITY
var _prev_d := 0.0
var _sign_changes := 0
var _samples := []


func _ready() -> void:
	world = main.start_world("moon", -20.0, 140.0, false, true)


func _process(delta: float) -> void:
	if world == null or not world.surface_ready:
		return
	ship = world.ship
	pl = world.player
	_t += delta
	match _step:
		0:
			pl.global_transform = ship.global_transform * Transform3D(Basis(), ShipLayout.SEAT_EXIT)
			if third:
				pl.first_person = false
				pl._apply_camera()
			_step = 1
			_t = 0.0
		1:
			if _t > 1.0:
				pl._interact()
				Input.action_press(&"ship_up")
				_step = 2
				_t = 0.0
		2:
			if _t > (8.0 if fast else 3.0):
				if not fast:
					Input.action_release(&"ship_up")
				Input.action_press(&"ship_throttle_up")
				if fast:
					Input.action_press(&"ship_boost")
				_step = 3
				_t = 0.0
		3:
			if _t > (15.0 if fast else 3.0):
				Input.action_release(&"ship_up")
				Input.action_release(&"ship_boost")
				Input.action_release(&"ship_throttle_up")
				ship.cmd_stop()
				_step = 4
				_t = 0.0
		4:
			if _t > 4.0:
				if hover:
					_step = 6
				else:
					Input.action_press(&"ship_down")
					_step = 5
				_t = 0.0
		5:
			if ship.state.landed:
				Input.action_release(&"ship_down")
				_step = 6
				_t = 0.0
		6:
			pl._interact()  # levantarse
			_step = 7
			_t = 0.0
		7:
			if _t > 2.0:
				_step = 8
				_t = 0.0
		8:
			var cam := world.view.active_camera()
			var in_ship := ship.to_local(cam.global_position)
			var in_body := pl.to_local(cam.global_position)
			var rot := cam.global_transform.basis.get_rotation_quaternion()
			var rel := (pl.global_transform.basis.inverse() * cam.global_transform.basis).get_rotation_quaternion()
			if _t > 0.05:
				var d := (_prev_rel.inverse() * rel).get_angle()
				var signed := (rel.get_euler() - _prev_rel.get_euler()).x
				if signed * _prev_d < 0.0:
					_sign_changes += 1
				_prev_d = signed
				_samples.append([in_ship.distance_to(_prev_ship), in_body.distance_to(_prev_body), (_prev_rot.inverse() * rot).get_angle(),
					ship.state.velocity.length(), d])
			_prev_ship = in_ship
			_prev_body = in_body
			_prev_rot = rot
			_prev_rel = rel
			if _t > 5.0:
				_report()


func _report() -> void:
	var n := _samples.size()
	var sums := [0.0, 0.0, 0.0, 0.0, 0.0]
	var maxs := [0.0, 0.0, 0.0, 0.0, 0.0]
	for s in _samples:
		for i in 5:
			sums[i] += s[i]
			maxs[i] = maxf(maxs[i], s[i])
	print("SHAKE: muestras=%d landed=%s seated=%s aboard=%s overlay=%s" % [n, ship.state.landed, pl.seated, pl.aboard != null, world.view.overlay_active])
	print("SHAKE: Δcám/nave medio=%.5f m máx=%.5f m" % [sums[0] / n, maxs[0]])
	print("SHAKE: Δcám/cuerpo medio=%.5f m máx=%.5f m" % [sums[1] / n, maxs[1]])
	print("SHAKE: Δrot medio=%.6f rad máx=%.6f rad" % [sums[2] / n, maxs[2]])
	print("SHAKE: Δrot relativa al cuerpo medio=%.6f rad máx=%.6f rad · cambios de signo del cabeceo=%d en %d fotogramas" % [sums[4] / n, maxs[4], _sign_changes, n])
	print("SHAKE: pitch=%.4f yaw_cabeza=%.4f giro=%.4f esfuerzo=%.3f mirada=%s" % [pl.look_pitch, pl.head_yaw, pl.turn_rate, pl.exertion, str(pl.look_rate)])
	print("SHAKE: alt radar %.0f m · recentrados %d" % [ship.radar_altitude, FloatingOrigin.shift_count])
	print("SHAKE: tercera persona=%s brazo=%.3f" % [not pl.first_person, pl.cam.tp_arm.get_hit_length()])
	print("SHAKE: aceleración de la nave %s, origen %s" % [str(ship.state.velocity), str(FloatingOrigin.offset)])
	get_tree().quit(0)
