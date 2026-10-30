extends Node
## Sonda de fallos de renderizado (ronda 11): capturas de los casos reportados. Uso: --render-probe [--only=grupo]
## Grupos: venus, vuelo, base, nave. Salida: user://bench/probe_*.png (y una línea por captura con datos de la vista).

var main: Node
var only := ""
var world: SurfaceWorld
var _queue: Array = []
var _t := 0.0
var _wait := 0.0
var _cur: Dictionary = {}


func _ready() -> void:
	for g in ["venus", "venus_nave", "vuelo", "transicion", "base", "nave", "nexus", "viaje"]:
		if only == "" or only == g:
			_queue.append(g)
	_next_group()


func _next_group() -> void:
	if _queue.is_empty():
		get_tree().quit(0)
		return
	var g: String = _queue.pop_front()
	_cur = {"group": g, "step": 0}
	match g:
		"venus":
			world = main.start_world("venus", 5.0, 40.0, false, false)
		"venus_nave":
			world = main.start_world("venus", 5.0, 40.0, false, true)
		"vuelo", "transicion":
			world = main.start_world("moon", -20.0, 140.0, false, true)
		"base":
			world = main.start_world("moon", BaseLayout.SITE_LAT, BaseLayout.SITE_LON, false, true, false, true)
		"nave":
			world = main.start_world("moon", -20.0, 140.0, false, true)
		"nexus":
			world = main.start_world("mercury", 62.0003, 15.0006, false, false)
		"viaje":
			world = main.start_world("moon", -20.0, 140.0, false, true)
	_t = 0.0
	_wait = 3.0


func _process(delta: float) -> void:
	if world == null or not world.surface_ready:
		return
	_t += delta
	if _t < _wait:
		return
	_t = 0.0
	_wait = 2.0
	var pl := world.player
	var step: int = _cur["step"]
	_cur["step"] = step + 1
	match str(_cur["group"]):
		"venus":
			match step:
				0:
					pl.set_look_pitch(-0.2)
				1:
					_shot("probe_venus_1p")
					pl.first_person = false
					pl._apply_camera()
				2:
					_shot("probe_venus_3p")
					pl.first_person = true
					pl._apply_camera()
					_next_group()
		"venus_nave":
			var vs := world.ship
			var alts := [20000.0, 3000.0, 400.0]
			match step:
				0:
					pl.global_transform = vs.global_transform * Transform3D(Basis(), ShipLayout.SEAT_EXIT)
				1:
					pl._interact()
				2, 4, 6:
					var alt: float = alts[(step - 2) / 2]
					var st := vs.state
					st.landed = false
					var up := st.pos_bf.normalized()
					st.pos_bf = up.mul(world.terrain.radius + world.terrain.height_at_dir(up) + alt)
					st.velocity = Vector3.ZERO
					vs.autopilot.engage(st, ShipState.Autopilot.HOLD)
					st.autopilot_speed = 0.0
					vs._sync_node()
					pl.first_person = true
					pl._apply_camera()
					_wait = 3.0
					if step > 2:
						_shot("probe_venusnave_%d_3p" % int(alts[(step - 4) / 2]))
				3, 5, 7:
					_shot("probe_venusnave_%d_1p" % int(alts[(step - 3) / 2]))
					pl.first_person = false
					pl._apply_camera()
				8:
					_shot("probe_venusnave_400_3p")
					_next_group()
		"transicion":
			var ts := world.ship
			if step == 0:
				pl.global_transform = ts.global_transform * Transform3D(Basis(), ShipLayout.SEAT_EXIT)
			elif step == 1:
				pl._interact()
			elif step == 2:
				var st := ts.state
				st.landed = false
				var up := st.pos_bf.normalized()
				st.pos_bf = up.mul(world.terrain.radius + world.terrain.height_at_dir(up) + 380.0)
				st.velocity = up.to_vector3() * 25.0
				ts._sync_node()
				Input.action_press(&"ship_up")
				_wait = 0.0
			elif step < 60:
				_wait = 0.1
				if step % 2 == 0:
					_shot("probe_trans_%02d" % step)
			else:
				Input.action_release(&"ship_up")
				_next_group()
		"vuelo":
			var ship := world.ship
			match step:
				0:
					pl.global_transform = ship.global_transform * Transform3D(Basis(), ShipLayout.SEAT_EXIT)
				1:
					pl._interact()
				2:
					_shot("probe_vuelo_posada_1p")
					Input.action_press(&"ship_up")
					_wait = 4.0
				3:
					Input.action_release(&"ship_up")
					_shot("probe_vuelo_despegue_1p")
					pl.first_person = false
					pl._apply_camera()
				4:
					_shot("probe_vuelo_despegue_3p")
					pl.first_person = true
					pl._apply_camera()
					var st := ship.state
					st.velocity = -st.basis.z * 3000.0
					st.target_speed = 3000.0
					ship.autopilot.engage(st, ShipState.Autopilot.HOLD)
					st.autopilot_speed = 3000.0
					_wait = 3.0
				5:
					_shot("probe_vuelo_3kms_1p")
					pl.first_person = false
					pl._apply_camera()
				6:
					_shot("probe_vuelo_3kms_3p")
					pl.first_person = true
					pl._apply_camera()
					var st2 := ship.state
					st2.pos_bf = st2.pos_bf.normalized().mul(world.terrain.radius + 200000.0)
					st2.velocity = -st2.basis.z * 60000.0
					st2.target_speed = 60000.0
					st2.autopilot_speed = 60000.0
					ship._sync_node()
					_wait = 3.0
				7:
					_shot("probe_vuelo_60kms_1p")
					pl.first_person = false
					pl._apply_camera()
				8:
					_shot("probe_vuelo_60kms_3p")
					_next_group()
		"base":
			var b := world.base
			world.prologue.active = false
			world.prologue.step = "completado"
			world.story_hud.wake = 0.0
			world.story_hud.blink = 0.0
			world.dialogue.stop_all()
			var views := [[Vector3(80, 0, 20), Vector3(0, 3, 0)], [Vector3(-60, 0, 30), Vector3(0, 4, 40)],
				[Vector3(0, 0, 140), Vector3(0, 6, 60)], [Vector3(30, 0, -130), Vector3(0, 3, -60)],
				[Vector3(40, 60, 120), Vector3(0, 0, 0)]]
			if step > 0:
				_shot("probe_base_ext_%d" % (step - 1))
			if step >= views.size():
				_next_group()
				return
			var v: Array = views[step]
			pl.move_locked = false
			if v[0].y > 1.0:
				pl.set_flying(true)
				pl.global_position = b.to_engine(v[0])
			else:
				pl.place_on_surface(b.point_bf(v[0]).normalized(), 0.05)
			var up := pl.global_transform.basis.y
			var dir: Vector3 = (b.to_engine(v[1]) - pl.global_position).normalized()
			var flat := (dir - up * dir.dot(up)).normalized()
			pl.global_transform.basis = Basis(up.cross(-flat).normalized(), up, -flat).orthonormalized()
			pl.set_look_pitch(asin(clampf(dir.dot(up), -1.0, 1.0)))
		"nexus":
			_nexus_step(step)
		"viaje":
			var vs2 := world.ship
			if step == 0:
				pl.global_transform = vs2.global_transform * Transform3D(Basis(), ShipLayout.SEAT_EXIT)
			elif step == 1:
				pl._interact()
			elif step == 2:
				vs2.state.landed = false
				vs2.state.pos_bf = vs2.state.pos_bf.normalized().mul(world.terrain.radius + 3000.0)
				vs2._sync_node()
				vs2.cmd_travel("venus")
				_wait = 4.0
			elif step < 14:
				_wait = 3.0
				_shot("probe_viaje_%02d" % step)
				print("   v=%.0f km/s regimen=%d luz=%s ancla=%s" % [vs2.state.speed() / 1000.0, vs2.state.regime, vs2.state.light_active, world.body.id])
			else:
				_next_group()
		"nave":
			var ship := world.ship
			# Rincones del interior con las puertas cerradas (ocultación de salas activa).
			var spots := [[Vector3(-1.2, 0.05, -16.5), Vector3(-8.5, 1.5, -17.8)], [Vector3(1.2, 0.05, 9.0), Vector3(8.8, 1.5, 9.8)],
				[Vector3(0.0, 0.05, -17.0), Vector3(0, 1.5, -25.0)], [Vector3(-1.3, 0.05, 1.0), Vector3(-8.8, 1.5, 2.0)],
				[Vector3(0.0, 0.05, 9.5), Vector3(5.0, 1.5, 21.0)]]
			if step > 0:
				_shot("probe_nave_%d" % (step - 1))
			if step >= spots.size():
				_next_group()
				return
			var s: Array = spots[step]
			if pl.aboard == null:
				world._bring_aboard(pl, ship)
			var p: Vector3 = ship.global_transform * s[0]
			var look: Vector3 = ship.global_transform * s[1]
			var up2 := ship.global_transform.basis.y
			var d2 := (look - p).normalized()
			var flat2 := (d2 - up2 * d2.dot(up2)).normalized()
			pl.global_transform = Transform3D(Basis(up2.cross(-flat2).normalized(), up2, -flat2).orthonormalized(), p)
			pl.set_look_pitch(0.0)


func _nexus_step(step: int) -> void:
	var pl := world.player
	if step == 0:
		var up := pl.global_transform.basis.y
		var tgt: Vector3 = FloatingOrigin.to_local(world.nexus._site_bf)
		var dir := (tgt - pl.global_position).normalized()
		var flat := (dir - up * dir.dot(up)).normalized()
		pl.global_transform.basis = Basis(up.cross(-flat).normalized(), up, -flat).orthonormalized()
		pl.set_look_pitch(0.05)
	elif step == 1:
		_shot("probe_nexus_mercurio")
		_next_group()


func _shot(name: String) -> void:
	var dir := ProjectSettings.globalize_path("user://bench")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	var v := world.view
	var cam := v.active_camera()
	print("PROBE %-26s single=%s overlay=%s near=%.3f far=%.0f mask=%x fp=%s seated=%s alt=%.0f" % [name, v.single, v.overlay_active,
		cam.near, cam.far, cam.cull_mask, world.player.first_person, world.player.seated,
		world.ship.radar_altitude if world.ship != null else -1.0])
