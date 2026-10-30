extends Node
## Benchmark con render real: recorrido automático por fases, medición de tiempos de fotograma
## y capturas de pantalla en user://bench/. Resultados en user://bench/results.json.

var main: Node
var world_id := "proto_a"
var world: SurfaceWorld

const PHASES := [
	{"name": "suelo_1p", "dur": 6.0},
	{"name": "mirar_pies", "dur": 3.0},
	{"name": "mirar_manos", "dur": 2.0},
	{"name": "enfocar", "dur": 2.5},
	{"name": "asomarse", "dur": 2.0},
	{"name": "mirar_sol", "dur": 5.0},
	{"name": "residual", "dur": 1.2},
	{"name": "suelo_3p", "dur": 4.0},
	{"name": "caminar_3p", "dur": 3.0},
	{"name": "caminar", "dur": 8.0},
	{"name": "caminar_pies", "dur": 2.4},
	{"name": "ascenso", "dur": 24.0},
	{"name": "orbita", "dur": 5.0},
]

var _phase := -1
var _t := 0.0
var _frames: PackedFloat32Array = []
var _results := []
var _load_t0 := 0
var _load_ms := 0
var _out_dir := ""
const ASCENT_SHOTS := [150.0, 3000.0, 40000.0, 400000.0]
var _shots_taken := {}
var _tag := ""


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--novsync"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_tag = "_novsync"
	_out_dir = ProjectSettings.globalize_path("user://bench")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	world = main.start_world(world_id, 12.0, 31.0, false, false)
	_load_t0 = Time.get_ticks_msec()
	print("BENCH: renderer=%s adaptador=%s" % [
		ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		RenderingServer.get_video_adapter_name()])


func _process(delta: float) -> void:
	if world == null or world.player == null:
		return
	if _phase == -1:
		if world.surface_ready:
			_load_ms = Time.get_ticks_msec() - _load_t0
			world.hud._set_debug_visible(false)  # capturas limpias (el HUD de depuración es F3)
			print("BENCH: terreno listo en %d ms" % _load_ms)
			_start_phase(0)
		return
	_t += delta
	_frames.append(delta * 1000.0)
	var pl := world.player
	var name: String = PHASES[_phase]["name"]
	match name:
		"suelo_1p":
			_set_pitch(-0.05)
		"mirar_pies":
			_set_pitch(-1.48)  # límite de la vista (85°)
		"mirar_manos":
			_set_pitch(-0.75)
		"enfocar":
			_set_pitch(-0.03)
			Input.action_press(&"focus")
		"asomarse":
			Input.action_release(&"focus")
			Input.action_press(&"lean_right")
		"mirar_sol":
			Input.action_release(&"lean_right")
			_face(pl.sun_dir, 0.0)
		"residual":
			_face(pl.sun_dir, 0.6)  # se aparta la vista: queda la imagen residual
		"suelo_3p":
			_set_pitch(-0.25)
		"caminar_3p", "caminar_pies":
			Input.action_press(&"move_forward")
			_set_pitch(-0.25 if name == "caminar_3p" else -1.1)
		"caminar":
			Input.action_press(&"move_forward")
			Input.action_press(&"sprint")
		"ascenso":
			Input.action_release(&"move_forward")
			Input.action_release(&"sprint")
			Input.action_press(&"jump")
			var alt := pl.altitude_m
			pl.fly_speed = maxf(20.0, maxf(pl.altitude_m, 0.0) * 0.5) if alt < 420000.0 else 1.0
			_set_pitch(-0.3)
			for mark in ASCENT_SHOTS:
				if alt > mark and not _shots_taken.has(mark):
					_shots_taken[mark] = true
					_save_shot("ascenso_%dm" % int(mark))
		"orbita":
			Input.action_release(&"jump")
			pl.fly_speed = 1.0
			_set_pitch(-0.9)
	if _t >= float(PHASES[_phase]["dur"]):
		_end_phase()


## Gira el cuerpo y la vista hacia `dir` (marco del motor), con `yaw_offset` rad a la derecha.
func _face(dir: Vector3, yaw_offset: float) -> void:
	var pl := world.player
	var up := pl.global_transform.basis.y
	var local := pl.global_transform.basis.orthonormalized().transposed() * dir
	var yaw := atan2(-local.x, -local.z) - yaw_offset
	if absf(yaw) > 0.001:
		pl.rotate(up, yaw)
	_set_pitch(asin(clampf(dir.dot(up), -1.0, 1.0)))


func _set_pitch(p: float) -> void:
	world.player.set_look_pitch(p)


func _save_shot(tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := _out_dir.path_join("%s_%s.png" % [world_id, tag])
	img.save_png(path)
	print("BENCH: captura ", path)


func _start_phase(i: int) -> void:
	_phase = i
	_t = 0.0
	_frames = PackedFloat32Array()
	var pl := world.player
	match PHASES[i]["name"]:
		"suelo_3p":
			pl.first_person = false
			pl._apply_camera()
		"caminar":
			pl.first_person = true
			pl._apply_camera()
		"caminar_pies":
			Input.action_release(&"sprint")
		"ascenso":
			pl.set_flying(true)


func _end_phase() -> void:
	var sorted := _frames.duplicate()
	sorted.sort()
	var sum := 0.0
	for f in _frames:
		sum += f
	var n := maxi(1, _frames.size())
	var avg := sum / n
	var p99: float = sorted[mini(sorted.size() - 1, int(sorted.size() * 0.99))] if sorted.size() > 0 else 0.0
	var tr := world.terrain
	var pl := world.player
	var res := {
		"phase": PHASES[_phase]["name"],
		"avg_fps": snappedf(1000.0 / maxf(avg, 0.001), 0.1),
		"avg_frame_ms": snappedf(avg, 0.01),
		"p99_frame_ms": snappedf(p99, 0.01),
		"drawn_patches": tr.stat_drawn,
		"tree_nodes": tr.stat_nodes,
		"deepest_level": tr.stat_deepest,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"static_mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"altitude_m": snappedf(pl.altitude_m, 0.1),
		"job_ms": snappedf(tr.stat_job_usec_avg / 1000.0, 0.01),
	}
	_results.append(res)
	print("BENCH: ", JSON.stringify(res))
	_save_shot(PHASES[_phase]["name"])
	if _phase + 1 < PHASES.size():
		_start_phase(_phase + 1)
	else:
		var summary := {
			"world": world_id,
			"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
			"adapter": RenderingServer.get_video_adapter_name(),
			"driver": RenderingServer.get_video_adapter_api_version(),
			"quality": GameSettings.quality,
			"vsync": _tag == "",
			"load_ms": _load_ms,
			"phases": _results,
		}
		var f := FileAccess.open(_out_dir.path_join("results_%s%s.json" % [world_id, _tag]), FileAccess.WRITE)
		f.store_string(JSON.stringify(summary, "  "))
		f.close()
		print("BENCH: fin")
		get_tree().quit(0)
