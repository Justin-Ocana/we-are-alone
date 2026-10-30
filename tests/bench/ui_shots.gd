extends Node
## Capturas de la interfaz (menú principal y menú de pausa) en user://bench/ui_*.png. Uso: --ui-shots

var main: Node
var _t := 0.0
var _step := 0
var _world: SurfaceWorld


func _ready() -> void:
	main.show_menu()


func _process(delta: float) -> void:
	_t += delta
	match _step:
		0:
			if _t > 1.0:
				_shot("ui_menu_principal")
				_world = main.start_world("moon", -20.0, 140.0, true, true)
				_step = 1
		1:
			if _world.surface_ready and _t > 3.0:
				_world.get_tree().paused = true
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				_world.pause_menu.open()
				_t = 0.0
				_step = 2
		2:
			if _t > 0.6:
				_shot("ui_pausa")
				get_tree().quit(0)


func _shot(name: String) -> void:
	var dir := ProjectSettings.globalize_path("user://bench")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("UI: captura ", name)
