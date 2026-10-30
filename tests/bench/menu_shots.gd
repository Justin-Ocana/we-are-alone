extends Node
## Capturas de los menús (ADR-033): principal, opciones, controles, cooperativo, créditos, voz y sala de espera.
## Uso: --menu-shots. Salida: user://bench/menu_*.png.

var main: Node
var _t := 0.0
var _step := 0


func _ready() -> void:
	main.show_menu()


func _process(delta: float) -> void:
	_t += delta
	if _t < 1.6:
		return
	_t = 0.0
	var menu: MainMenu = main._menu
	match _step:
		0:
			_shot("menu_principal")
			menu._open_options()
		1:
			_shot("menu_opciones")
			menu._open_controls()
		2:
			_shot("menu_controles")
			menu._open_coop()
		3:
			_shot("menu_cooperativo")
			menu._open_credits()
		4:
			_shot("menu_creditos")
			menu._open_customize()
		5:
			_shot("menu_astronauta")
			menu._open_online()
		6:
			_shot("menu_en_linea")
			var op: OnlinePanel = menu._right_content
			op._tabs.current_tab = 1
		7:
			_shot("menu_en_linea_unirse")
			menu._open_options()
			var opt: OptionsPanel = menu._right_content
			for i in opt._tabs.get_tab_count():
				if opt._tabs.get_tab_title(i) == "Voz":
					opt._tabs.current_tab = i
		8:
			_shot("menu_opciones_voz")
			# Sala de espera (ADR-047) en un puerto de pruebas, sin UPnP.
			Net.host("Sala de capturas", 7795, 6, false)
			menu._open_lobby()
		9:
			_shot("menu_sala_espera")
			Net.leave()
			print("MENU fps=%d" % Engine.get_frames_per_second())
			get_tree().quit(0)
	_step += 1


func _shot(name: String) -> void:
	var dir := ProjectSettings.globalize_path("user://bench")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("CAPTURA ", name, " fps=", Engine.get_frames_per_second())
