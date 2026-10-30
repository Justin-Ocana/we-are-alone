extends Node
## Recorrido visual de la nave con render real: capturas del exterior, de cada habitación, de la cabina
## pilotando y en vuelo, más tiempos de fotograma por fase. Salida en user://bench/ship_*.png y
## user://bench/results_ship.json. Uso: --ship-tour [--novsync]

var main: Node
var no_vsync := false
var world: SurfaceWorld
var ship: Ship
var pl: Astronaut
var free_cam: Camera3D

## [nombre, tipo, datos...]. Tipos: "ext" (cámara libre en local de la nave: pos, objetivo),
## "room" (astronauta en local: pos, yaw, pitch), "seat", "fly", "chase", "cockpit_fly".
const SHOTS := [
	["ext_frontal", "ext", Vector3(-40, 10, -66), Vector3(0, 1, -8)],
	["ext_estribor_rampa", "ext", Vector3(38, 4, 4), Vector3(8, 0, -3)],
	["ext_popa", "ext", Vector3(-24, 12, 64), Vector3(0, 1, 12)],
	["ext_superior", "ext", Vector3(36, 48, -32), Vector3(0, 0, 0)],
	["ext_lateral", "ext", Vector3(-62, 6, 4), Vector3(0, 1, 0)],
	["llegada_rampa", "room", Vector3(16.5, -2.0, -3.0), PI / 2, 0.05],
	["esclusa", "room", Vector3(6.5, 0, -3.0), PI / 2, -0.1],
	["pasillo", "room", Vector3(0, 0, 8.5), 0.0, -0.05],
	["cabina", "room", Vector3(0, 0, -19.0), 0.0, -0.1],
	["comedor", "room", Vector3(-2.0, 0, -8.8), PI / 4 + 0.1, -0.2],
	["dormitorios", "room", Vector3(-2.0, 0, 1.5), PI / 4 + 0.25, -0.2],
	["bano", "room", Vector3(1.8, 0, -6.4), -PI / 4 - 0.2, -0.25],
	["enfermeria", "room", Vector3(1.8, 0, -10.6), -PI / 4 - 0.3, -0.2],
	["vestuario", "room", Vector3(1.8, 0, 0.4), -PI * 0.75 + 0.3, -0.15],
	["salon", "room", Vector3(1.9, 0, 9.4), -PI / 4 - 0.25, -0.1],
	["almacen", "room", Vector3(-1.8, 0, 2.4), PI * 0.75 - 0.3, -0.15],
	["maquinas", "room", Vector3(-3.5, 0, 12.0), PI + 0.45, -0.1],
	["asiento_piloto", "seat"],
	["despegue", "fly"],
	["vuelo_exterior", "chase"],
	["vuelo_cabina", "cockpit_fly"],
	["exterior_alto_rapido", "high_ext"],
	["astronauta_en_el_espacio", "space_walk"],
]

var _i := -1
var _t := 0.0
var _frames := PackedFloat32Array()
var _results := []
var _out := ""


func _ready() -> void:
	if no_vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_out = ProjectSettings.globalize_path("user://bench")
	DirAccess.make_dir_recursive_absolute(_out)
	world = main.start_world("moon", -20.0, 140.0, false, true)
	free_cam = Camera3D.new()
	free_cam.top_level = true
	free_cam.fov = 70.0
	add_child(free_cam)


func _process(delta: float) -> void:
	if world == null or not world.surface_ready:
		return
	if _i == -1:
		ship = world.ship
		pl = world.player
		world.hud._set_debug_visible(false)
		pl.helmet_enabled = false
		_start(0)
		return
	_t += delta
	_frames.append(delta * 1000.0)
	var shot: Array = SHOTS[_i]
	match shot[1]:
		"ext":
			free_cam.global_position = ship.global_transform * (shot[2] as Vector3)
			free_cam.look_at(ship.global_transform * (shot[3] as Vector3), ship.global_transform.basis.y)
			free_cam.far = 5000.0
		"room":
			pl.set_look_pitch(shot[4])
		"fly":
			if _t > 0.2:
				Input.action_press(&"ship_up")
		"chase":
			Input.action_release(&"ship_up")
		"cockpit_fly":
			pl.set_look_pitch(-0.05)
	if _t >= _duration(shot[1]):
		_finish_shot()


func _duration(kind: String) -> float:
	match kind:
		"fly":
			return 6.0
		"chase":
			return 5.0
		"cockpit_fly":
			return 4.0
		"high_ext":
			return 3.0
		"space_walk":
			return 2.0
	return 2.0


func _start(i: int) -> void:
	_i = i
	_t = 0.0
	_frames = PackedFloat32Array()
	var shot: Array = SHOTS[i]
	world.view.override_camera = free_cam if shot[1] == "ext" else null
	match shot[1]:
		"room":
			var xf := ship.global_transform * Transform3D(Basis(Vector3.UP, shot[3]), shot[2])
			pl.global_transform = xf
			pl.velocity = Vector3.ZERO
		"seat":
			pl.global_transform = ship.global_transform * Transform3D(Basis(), ShipLayout.SEAT_EXIT)
		"chase":
			ship.cmd_set_regime(1)
			ship.model.set_target(ship.state, 120.0)
			world.view.ship_exterior = true
		"cockpit_fly":
			world.view.ship_exterior = false
		"high_ext":
			# 5 km más arriba, volando a 1 km/s, vista exterior.
			var up := ship.state.pos_bf.normalized()
			ship.state.pos_bf = ship.state.pos_bf.add(up.mul(5000.0))
			ship.model.set_target(ship.state, 1000.0)
			ship.state.velocity = ship.state.forward() * 1000.0
			world.view.ship_exterior = true
		"space_walk":
			# El piloto se levanta (la nave frena sola) y sale al espacio junto a la nave, en 3ª persona.
			world.view.ship_exterior = false
			pl._interact()
			ship.state.velocity = Vector3.ZERO
			ship.model.set_target(ship.state, 0.0)
			pl.global_transform = ship.global_transform * Transform3D(Basis(Vector3.UP, PI / 2), Vector3(21, 0.5, -3))
			pl.velocity = Vector3.ZERO
			pl.first_person = false
			pl._apply_camera()


func _finish_shot() -> void:
	var shot: Array = SHOTS[_i]
	if shot[1] == "seat" and not pl.seated:
		pl._interact()
	var sorted := _frames.duplicate()
	sorted.sort()
	var sum := 0.0
	for f in _frames:
		sum += f
	var avg := sum / maxi(1, _frames.size())
	var res := {
		"shot": shot[0], "avg_fps": snappedf(1000.0 / maxf(avg, 0.001), 0.1),
		"p99_ms": snappedf(sorted[mini(sorted.size() - 1, int(sorted.size() * 0.99))] if sorted.size() > 0 else 0.0, 0.01),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"overlay": world.view.overlay_active,
		"room": ShipLayout.room_at(ship.to_local(pl.global_position + Vector3(0, 0.9, 0))),
	}
	_results.append(res)
	print("TOUR: ", JSON.stringify(res))
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out.path_join("ship_%s.png" % shot[0]))
	if _i + 1 < SHOTS.size():
		_start(_i + 1)
	else:
		var f := FileAccess.open(_out.path_join("results_ship%s.json" % ("_novsync" if no_vsync else "")), FileAccess.WRITE)
		f.store_string(JSON.stringify({"adapter": RenderingServer.get_video_adapter_name(), "shots": _results}, "  "))
		f.close()
		print("TOUR: fin")
		get_tree().quit(0)
