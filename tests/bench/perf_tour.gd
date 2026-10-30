extends Node
## Recorrido de rendimiento por situaciones (ronda 9): fuera junto a la nave, pasillo, cabina pilotando, vuelo bajo
## a 1,5 km y espacio a 150 km. Sin vsync; mide FPS medios, llamadas de dibujo y primitivas en cada una.
## Uso: --perf-tour [--quality=low|medium|high]. Escribe user://bench/perf_tour.txt.

var main: Node
var world: SurfaceWorld
var _t := 0.0
var _step := -1
var _frames := 0
var _time := 0.0
var _calls := 0.0
var _prims := 0.0
var _cpu := 0.0
var _wprof := {}
var _phys := 0.0
var _proc := 0.0
var _cheap_done := false
var _gpu := 0.0
var _out := PackedStringArray()
const NAMES := ["exterior", "pasillo", "cabina", "vuelo_bajo", "espacio", "tierra"]
const WARM := 2.5
const MEASURE := 4.0


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var args := OS.get_cmdline_user_args()
	if args.has("--nopost"):
		GameSettings.post_effects = false
	world = main.start_world("moon", main.SPAWN_LAT, main.SPAWN_LON, false, true)
	_nomilky = args.has("--nomilky")
	_nobodies = args.has("--nobodies")
	_noscripts = args.has("--nohud")


var _nomilky := false
var _nobodies := false
var _noscripts := false


func _process(delta: float) -> void:
	if world == null or not world.surface_ready:
		return
	if OS.get_cmdline_user_args().has("--halfres") and get_viewport().scaling_3d_scale != 0.5:
		get_viewport().scaling_3d_scale = 0.5
	var a2 := OS.get_cmdline_user_args()
	if a2.has("--skyrt") and world.env.world_env.environment.sky.process_mode != Sky.PROCESS_MODE_REALTIME:
		world.env.world_env.environment.sky.process_mode = Sky.PROCESS_MODE_REALTIME
	if a2.has("--skyinc") and world.env.world_env.environment.sky.process_mode != Sky.PROCESS_MODE_INCREMENTAL:
		world.env.world_env.environment.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	if a2.has("--cheapship") and not _cheap_done:
		_cheap_done = true
		for k in world.ship.dyn["mats"]:
			var m = world.ship.dyn["mats"][k]
			if m is ShaderMaterial:
				m.set_shader_parameter("grime", 0.0)
				m.set_shader_parameter("wear", 0.0)
				m.set_shader_parameter("rivets", 0.0)
				m.set_shader_parameter("bevel", 0.0)
	if a2.has("--nooverlay"):
		world.view._overlay_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if a2.has("--noworldcam") and world.view.overlay_active:
		world.view.active_camera().cull_mask = 0
	if a2.has("--plainship") and not _cheap_done:
		_cheap_done = true
		var plain := StandardMaterial3D.new()
		plain.albedo_color = Color(0.7, 0.7, 0.7)
		for mi in world.ship.find_children("*", "MeshInstance3D", true, false):
			if mi.material_override is ShaderMaterial:
				mi.material_override = plain
	if a2.has("--noterrain"):
		world.terrain.visible = false
	if a2.has("--nosky"):
		world.env.world_env.environment.background_mode = Environment.BG_CLEAR_COLOR
	if a2.has("--nohelmet"):
		world.player.helmet.visible = false
		world.player.screen_fx.visible = false
	if a2.has("--noship") and _step == 1:
		world.ship.set_process(false)
		world.ship.set_physics_process(false)
	if a2.has("--noastro") and _step == 1:
		world.player.set_process(false)
		world.player.set_physics_process(false)
	if a2.has("--nohuds") and _step == 1:
		for n in [world.pilot_hud, world.player.hud, world.player.exploration_hud, world.hud]:
			n.visible = false
			n.set_process(false)
	if a2.has("--noworldproc") and _step == 1:
		world.set_process(false)
	if a2.has("--nolights"):
		for e in world.ship.dyn.get("lights", []):
			e[0].visible = false
	if _nomilky:
		world.env.sky_mat.set_shader_parameter("milky_way", 0.0)
	if _nobodies:
		world.env.system_sky = null
		world.env.sky_mat.set_shader_parameter("body_count", 0)
	if _noscripts:
		for a in world.players:
			a.hud.visible = false
		for h in world.pilot_huds:
			h.process_mode = Node.PROCESS_MODE_DISABLED
			h.visible = false
	if _step < 0:
		_setup(0)
		return
	_t += delta
	if _t < WARM:
		return
	_frames += 1
	_time += delta
	_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	for k in world.prof:
		_wprof[k] = _wprof.get(k, 0.0) + float(world.prof[k])
	var vrid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vrid, true)
	_cpu += RenderingServer.viewport_get_measured_render_time_cpu(vrid) + RenderingServer.get_frame_setup_time_cpu()
	var orid: RID = world.view._overlay_vp.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(orid, true)
	_gpu += RenderingServer.viewport_get_measured_render_time_cpu(orid)
	_phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	if _time >= MEASURE:
		var fps := _frames / _time
		_out.append("%-11s %5.1f FPS  %5.1f ms  render cpu %5.1f ms  superposición cpu %5.1f ms  llamadas %4d  primitivas %7d" % [NAMES[_step], fps,
			1000.0 / fps, _cpu / _frames, _gpu / _frames, int(_calls / _frames), int(_prims / _frames)])
		print("PERF ", _out[-1])
		print("     modo: una cámara=%s superposición=%s altura cámara=%.0f m" % [world.view.single, world.view.overlay_active,
			world.view._above_terrain(world.view.active_camera())])
		var bdir := ProjectSettings.globalize_path("user://bench")
		DirAccess.make_dir_recursive_absolute(bdir)
		get_viewport().get_texture().get_image().save_png(bdir.path_join("perf_%s.png" % NAMES[_step]))
		print("     física/paso %.2f ms · proceso %.2f ms" % [_phys / _frames, _proc / _frames])
		_phys = 0.0
		_proc = 0.0
		var ps = load("res://src/core/prof.gd") if ResourceLoader.exists("res://src/core/prof.gd") else null
		if ps != null:
			var keys: Array = ps.t.keys()
			keys.sort_custom(func(a, b): return ps.t[a] > ps.t[b])
			var parts := PackedStringArray()
			for k in keys.slice(0, 7):
				parts.append("%s %.2f" % [k, ps.t[k] / _frames])
			print("     cpu/fotograma (ms): ", ", ".join(parts))
			ps.t.clear()
		var wp := PackedStringArray()
		for k in _wprof:
			wp.append("%s %.2f" % [k, _wprof[k] / _frames])
		print("     mundo (ms): ", ", ".join(wp))
		_wprof.clear()
		var scat := 0
		for c in world.terrain.get_children():
			if c is MultiMeshInstance3D and c.visible:
				scat += 1
		var ship_mi := 0
		for c in world.ship.find_children("*", "MeshInstance3D", true, false):
			if c.visible:
				ship_mi += 1
		print("     terreno: parches %d, rocas (multimallas) %d · nave: mallas %d · luces nave %d" % [world.terrain.stat_drawn, scat, ship_mi,
			world.ship.dyn.get("lights", []).size()])
		if _step + 1 >= NAMES.size():
			var dir := ProjectSettings.globalize_path("user://bench")
			DirAccess.make_dir_recursive_absolute(dir)
			var f := FileAccess.open(dir.path_join("perf_tour.txt"), FileAccess.WRITE)
			f.store_string("\n".join(_out))
			get_tree().quit(0)
			return
		_setup(_step + 1)


func _setup(i: int) -> void:
	_step = i
	_t = 0.0
	_frames = 0
	_time = 0.0
	_calls = 0.0
	_prims = 0.0
	_cpu = 0.0
	_gpu = 0.0
	var pl := world.player
	var ship := world.ship
	match NAMES[i]:
		"exterior":
			pl.set_look_pitch(-0.05)
		"pasillo":
			world._bring_aboard(pl, ship)
			pl.global_transform = Transform3D(ship.global_transform.basis, ship.global_transform * Vector3(0, 0.05, 6.0))
			pl.set_look_pitch(0.0)
		"cabina":
			pl.global_transform = Transform3D(ship.global_transform.basis, ship.global_transform * ShipLayout.SEAT_EXIT)
			pl._sit_down("piloto")
		"vuelo_bajo":
			ship.state.landed = false
			ship.state.pos_bf = ship.state.pos_bf.normalized().mul(world.terrain.radius + 1500.0)
			ship.state.velocity = Vector3.ZERO
			ship.state.autopilot = ShipState.Autopilot.HOLD
			ship.state.autopilot_heading = -ship.state.basis.z
			ship.state.autopilot_up = ship.state.pos_bf.normalized().to_vector3()
			ship.state.autopilot_speed = 0.0
			ship._sync_node()
		"espacio":
			ship.state.pos_bf = ship.state.pos_bf.normalized().mul(world.terrain.radius + 150000.0)
			ship._sync_node()
		"tierra":
			# Llegada a la Tierra destruida (ronda 10): sus fragmentos llenan media pantalla; era donde más caían los FPS.
			world.set_anchor("earth")
			var up := ship.state.pos_bf.normalized()
			ship.state.pos_bf = up.mul(world.body.radius_m() * 2.4)
			var u := up.to_vector3()
			var side := u.cross(Vector3.UP if absf(u.y) < 0.9 else Vector3.RIGHT).normalized()
			ship.state.basis = Basis(side, u.cross(side).normalized(), u)  # morro (−Z) hacia el centro
			ship.state.velocity = Vector3.ZERO
			ship._sync_node()
