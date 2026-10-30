extends Node
## Capturas del mapa (Tab): vista del sistema, zoom al interior y vista de las lunas de Júpiter.
## Uso: --map-shots. Salida: user://bench/map_*.png.

var main: Node
var world: SurfaceWorld
var _t := 0.0
var _step := 0


func _ready() -> void:
	world = main.start_world("moon", main.SPAWN_LAT, main.SPAWN_LON, false, true)


func _process(delta: float) -> void:
	if world == null or not world.surface_ready or world.map_panel == null:
		return
	_t += delta
	if _t < 1.5:
		return
	_t = 0.0
	var mp := world.map_panel
	match _step:
		0:
			mp.open()
			mp._select("saturn")
		1:
			_shot("map_sistema")
			mp._zoom_at(mp._diagram.size * 0.5, 4.0)
		2:
			_shot("map_interior")
			mp._enter_moons("jupiter")
		3:
			_shot("map_lunas_jupiter")
			mp._select("titan")
			mp._enter_moons("titan")
		4:
			_shot("map_lunas_saturno")
			get_tree().quit(0)
	_step += 1


func _shot(name: String) -> void:
	var dir := ProjectSettings.globalize_path("user://bench")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("CAPTURA ", name, " fps=", Engine.get_frames_per_second())
