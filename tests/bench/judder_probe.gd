extends Node
## Sonda de tirones (ronda 10, ADR-042): vuela a 300 m/s a ras de suelo con los FPS limitados (45 por defecto, que no
## coinciden con los 60 Hz de la física) y mide, fotograma a fotograma, cuánto avanza la cámara respecto a lo que
## debería según el tiempo del fotograma. Con movimiento suave la razón es ≈1 siempre; sin él alterna 0,75 / 1,5.
## Uso: --judder-probe [--nosmooth] [--fps=45]

var main: Node
var smooth := true
var fps := 45
var world: SurfaceWorld
var ship: Ship
var pl: Astronaut
var _step := 0
var _t := 0.0
var _prev_bf: DVec3
var _prev_local := Vector3.ZERO
var _ratios: Array[float] = []
var _rel: Array[float] = []


func _ready() -> void:
	process_priority = 2000  # mide después de que todo se haya colocado para dibujar
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
			_step = 1
			_t = 0.0
		1:
			if _t > 1.0:
				pl._interact()  # sentarse a pilotar
				_step = 2
				_t = 0.0
		2:
			if _t > 1.0:
				get_tree().physics_interpolation = smooth
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
				Engine.max_fps = fps
				var st := ship.state
				st.landed = false
				var up := st.pos_bf.normalized()
				st.pos_bf = up.mul(world.terrain.radius + world.terrain.height_at_dir(up) + 150.0)
				var fwd := st.forward() - up.to_vector3() * st.forward().dot(up.to_vector3())
				st.basis = Basis(up.to_vector3().cross(-fwd.normalized()).normalized(), up.to_vector3(), -fwd.normalized())
				st.velocity = -st.basis.z * 300.0
				st.target_speed = 300.0
				ship.autopilot.engage(st, ShipState.Autopilot.HOLD)
				st.autopilot_speed = 300.0
				_step = 3
				_t = 0.0
		3:
			if _t > 2.0:
				_step = 4
				_t = 0.0
		4:
			var cam := world.view.active_camera()
			var bf := FloatingOrigin.to_global(cam.global_position)
			var sx := ship.get_global_transform_interpolated() if ship.is_physics_interpolated_and_enabled() else ship.global_transform
			var local := sx.affine_inverse() * cam.global_position
			if _prev_bf != null:
				_rel.append(local.distance_to(_prev_local))
			if _prev_bf != null and FloatingOrigin.shift_count >= 0:
				var step := bf.sub(_prev_bf).length()
				var v := ship.state.velocity.length()
				if v > 50.0 and step < v * delta * 4.0:
					_ratios.append(step / (v * delta))
			_prev_bf = bf
			_prev_local = local
			if _t > 6.0:
				_report()


func _report() -> void:
	var n := _ratios.size()
	var mean := 0.0
	for r in _ratios:
		mean += r
	mean /= maxf(n, 1)
	var var_sum := 0.0
	var worst := 0.0
	for r in _ratios:
		var_sum += (r - mean) * (r - mean)
		worst = maxf(worst, absf(r - 1.0))
	var rel_max := 0.0
	var rel_sum := 0.0
	for r in _rel:
		rel_max = maxf(rel_max, r)
		rel_sum += r
	print("JUDDER: cámara respecto a la nave dibujada: media %.4f m, máx %.4f m por fotograma" % [rel_sum / maxf(_rel.size(), 1), rel_max])
	print("JUDDER: suave=%s fps_lim=%d fotogramas=%d avance/esperado medio=%.3f desviación=%.3f peor=%.3f fps=%.0f recentrados=%d" % [
		smooth, fps, n, mean, sqrt(var_sum / maxf(n, 1)), worst, Engine.get_frames_per_second(), FloatingOrigin.shift_count])
	get_tree().quit(0)
