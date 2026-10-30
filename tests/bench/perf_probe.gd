extends Node
## Sonda de rendimiento (ronda 7): en la Luna, junto a la nave, mide durante 8 s el tiempo de proceso, de física,
## de dibujo y las llamadas de dibujo, y el coste de los sistemas del mundo (cielo, terreno, HUD).
## Uso: --perf-probe [--coop]. Escribe user://bench/perf_probe.txt.

var main: Node
var world: SurfaceWorld
var _t := 0.0
var _n := 0
var _acc := {}


func _ready() -> void:
	var coop := OS.get_cmdline_user_args().has("--coop")
	if coop:
		GameInput.configure_players(0)
	world = main.start_world("moon", main.SPAWN_LAT, main.SPAWN_LON, false, true, coop)


func _process(delta: float) -> void:
	if world == null or not world.surface_ready:
		return
	_t += delta
	if _t < 3.0:
		return
	_n += 1
	_add("fps", Engine.get_frames_per_second())
	_add("proceso_ms", Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_add("fisica_ms", Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_add("llamadas", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_add("primitivas", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	for k in world.prof:
		_add(k, world.prof[k])
	var pc = ClassDB.class_exists("Prof")
	var ps = load("res://src/core/prof.gd") if ResourceLoader.exists("res://src/core/prof.gd") else null
	if ps != null:
		for k in ps.t:
			_add("p:" + k, ps.t[k])
		ps.t.clear()
	if _t > 11.0:
		var lines := PackedStringArray()
		for k in _acc:
			lines.append("%s = %.2f" % [k, _acc[k] / _n])
		var txt := "\n".join(lines)
		print("PERF\n" + txt)
		var dir := ProjectSettings.globalize_path("user://bench")
		DirAccess.make_dir_recursive_absolute(dir)
		var f := FileAccess.open(dir.path_join("perf_probe.txt"), FileAccess.WRITE)
		f.store_string(txt)
		get_tree().quit(0)


func _add(k: String, v: float) -> void:
	_acc[k] = _acc.get(k, 0.0) + v
