extends Node
## Capturas de la base lunar LF-01 y del prólogo (ADR-043). Empieza una partida nueva (cápsula) y recorre las salas
## colocando al jugador en cada una mirando a lo importante. Uso: --base-shots. Salida: user://bench/base_*.png.
## Imprime los FPS de cada vista.

var main: Node
var world: SurfaceWorld
var _t := 0.0
var _step := 0
var _frames := 0
var _time := 0.0

## [nombre, posición (marco de la base), punto al que mirar]
const VIEWS := [
	["capsula", Vector3(0.0, 0.0, -98.15), Vector3(0.0, 1.4, -90.0)],
	["crio", Vector3(4.5, 0.0, -86.5), Vector3(-2.0, 1.2, -97.0)],
	["recuperacion", Vector3(0.0, 0.0, -82.0), Vector3(0.0, 1.5, -64.0)],
	["orientacion", Vector3(-4.5, 0.0, -56.0), Vector3(6.6, 2.0, -56.0)],
	["observatorio", Vector3(-9.0, 0.0, -56.0), Vector3(-18.0, 3.0, -56.0)],
	["operaciones", Vector3(3.5, 0.0, -48.0), Vector3(9.0, 1.0, -40.0)],
	["energia", Vector3(-3.0, 0.0, -48.5), Vector3(-12.0, 1.5, -40.0)],
	["hidroponia", Vector3(-3.5, 0.0, -30.0), Vector3(-10.0, 1.0, -20.0)],
	["eje", Vector3(0.0, 0.0, -48.0), Vector3(0.0, 1.5, -12.0)],
	["hangar", Vector3(-24.0, 0.0, 36.0), Vector3(0.0, 4.0, 66.0)],
	["esclusa", Vector3(37.0, 0.0, 63.0), Vector3(44.5, 1.2, 59.0)],
	["exterior", Vector3(70.0, 0.0, 70.0), Vector3(20.0, 3.0, 40.0)],
	["exterior2", Vector3(-45.0, 0.0, -110.0), Vector3(0.0, 2.0, -60.0)],
]


func _ready() -> void:
	world = main.start_world("moon", BaseLayout.SITE_LAT, BaseLayout.SITE_LON, false, true, false, true)


func _process(delta: float) -> void:
	if world == null or not world.surface_ready:
		return
	_t += delta
	if _step >= 1 and _t > 1.5:
		_frames += 1
		_time += delta
	if _t < 3.0:
		return
	if _step > 0:
		var v: Array = VIEWS[_step - 1]
		print("BASE %-13s %5.1f FPS  llamadas %d" % [v[0], _frames / maxf(_time, 0.001),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
		_shot("base_" + str(v[0]))
	if _step >= VIEWS.size():
		get_tree().quit(0)
		return
	var v2: Array = VIEWS[_step]
	if _step == 1:
		# Tras la cápsula: sin efecto de despertar ni objetivos (se recorre la base libremente).
		world.prologue.active = false
		world.prologue.step = "completado"
		world.story_hud.wake = 0.0
		world.story_hud.blink = 0.0
		world.dialogue.stop_all()
	if v2[0] == "eje":
		world.base.set_power_aux(true)
	_place(v2[1], v2[2])
	_step += 1
	_t = 0.0
	_frames = 0
	_time = 0.0


func _place(p: Vector3, look: Vector3) -> void:
	var pl := world.player
	var b := world.base
	pl.move_locked = false
	pl.cinematic = false
	pl.place_on_surface(b.point_bf(p).normalized(), 0.05)
	var up := pl.global_transform.basis.y
	var dir := (b.to_engine(look) - (pl.global_position + up * 1.7)).normalized()
	var flat := (dir - up * dir.dot(up)).normalized()
	pl.global_transform.basis = Basis(up.cross(-flat).normalized(), up, -flat).orthonormalized()
	pl.set_look_pitch(asin(clampf(dir.dot(up), -1.0, 1.0)))


func _shot(name: String) -> void:
	var dir := ProjectSettings.globalize_path("user://bench")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
