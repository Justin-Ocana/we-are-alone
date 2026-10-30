class_name OptionsPanel
extends VBoxContainer
## Opciones del juego por pestañas (ADR-033), compartidas por el menú principal y el de pausa.
## Cada cambio se aplica al momento y se guarda en user://settings.cfg.

signal closed

var _tabs: TabContainer
var _voice := VoiceOptions.new()


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "OPCIONES"
	title.add_theme_font_override("font", UiTheme.title_font())
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var back := Button.new()
	back.text = "Volver"
	back.pressed.connect(func(): closed.emit())
	head.add_child(back)
	add_child(head)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.custom_minimum_size = Vector2(0, 380)
	add_child(_tabs)
	_build_graphics()
	_build_controls()
	_build_audio()
	_voice.build(self)
	_build_game()


func focus_first() -> void:
	var tb := _tabs.get_tab_bar()
	tb.grab_focus()


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		_voice.process()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if _voice.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	# LB/RB o Q/E cambian de pestaña (cómodo con mando).
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			_tabs.current_tab = posmod(_tabs.current_tab - 1, _tabs.get_tab_count())
			get_viewport().set_input_as_handled()
		elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			_tabs.current_tab = posmod(_tabs.current_tab + 1, _tabs.get_tab_count())
			get_viewport().set_input_as_handled()


func _page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	return box


func _save() -> void:
	GameSettings.save_settings()
	GameSettings.apply_runtime()
	Voice.apply_settings()


func _row(box: Container, label: String, ctrl: Control, hint: String = "") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(260, 0)
	l.add_theme_color_override("font_color", UiTheme.TEXT)
	row.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ctrl)
	box.add_child(row)
	if hint != "":
		var h := Label.new()
		h.text = hint
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.add_theme_font_size_override("font_size", 13)
		h.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		box.add_child(h)


func _option(box: Container, label: String, items: Array, current: int, cb: Callable, hint: String = "") -> OptionButton:
	var o := OptionButton.new()
	for i in items.size():
		o.add_item(items[i], i)
	o.select(current)
	o.item_selected.connect(func(i: int):
		cb.call(i)
		_save())
	_row(box, label, o, hint)
	return o


func _check(box: Container, label: String, value: bool, cb: Callable, hint: String = "") -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = value
	c.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var flat := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		c.add_theme_stylebox_override(st, flat)
	c.text = "Sí" if value else "No"
	c.toggled.connect(func(on: bool): c.text = "Sí" if on else "No")
	c.toggled.connect(func(on: bool):
		cb.call(on)
		_save())
	_row(box, label, c, hint)
	return c


func _slider(box: Container, label: String, lo: float, hi: float, step: float, value: float, cb: Callable,
		fmt: Callable = Callable(), hint: String = "") -> HSlider:
	var wrap := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v := Label.new()
	v.custom_minimum_size = Vector2(70, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_theme_color_override("font_color", UiTheme.ACCENT)
	var show := func(x: float): v.text = fmt.call(x) if fmt.is_valid() else str(snappedf(x, step))
	show.call(value)
	s.value_changed.connect(func(x: float):
		cb.call(x)
		show.call(x)
		_save())
	wrap.add_child(s)
	wrap.add_child(v)
	_row(box, label, wrap, hint)
	return s


func _build_graphics() -> void:
	var box := _page("Gráficos")
	var keys: Array = GameSettings.QUALITY_PRESETS.keys()
	var names := {"low": "Baja (más FPS)", "medium": "Media (recomendada)", "high": "Alta (sombras)"}
	var items := []
	for k in keys:
		items.append(names.get(k, k))
	_option(box, "Calidad gráfica", items, maxi(0, keys.find(GameSettings.quality)), func(i: int): GameSettings.quality = keys[i],
		"El detalle del terreno se aplica al entrar en un mundo; la escala de render, al momento.")
	_option(box, "Controlador gráfico", ["OpenGL nativo (más rápido)", "ANGLE / Direct3D (compatibilidad)"],
		0 if GameSettings.graphics_driver != "angle" else 1, func(i: int): GameSettings.graphics_driver = "opengl" if i == 0 else "angle",
		"Se aplica al reiniciar el juego. Si ves fallos gráficos o cierres, prueba ANGLE.")
	_check(box, "Pantalla completa", GameSettings.fullscreen, func(on: bool): GameSettings.fullscreen = on)
	_check(box, "Sincronización vertical", GameSettings.vsync, func(on: bool): GameSettings.vsync = on,
		"Evita el desgarro de la imagen. Desactívala sólo para medir rendimiento.")
	var fps_vals := [0, 30, 60, 120]
	_option(box, "Límite de FPS", ["Sin límite", "30", "60", "120"], maxi(0, fps_vals.find(GameSettings.max_fps)),
		func(i: int): GameSettings.max_fps = fps_vals[i])
	_slider(box, "Campo de visión", 55.0, 100.0, 1.0, GameSettings.fov, func(x: float): GameSettings.fov = x,
		func(x: float): return "%d°" % int(x))
	_check(box, "Movimiento suave (interpolación)", GameSettings.motion_smoothing, func(on: bool): GameSettings.motion_smoothing = on,
		"Evita los tirones cuando los FPS no coinciden con los 60 Hz de la simulación.")
	_check(box, "Distorsión del cristal del visor", GameSettings.visor_effects, func(on: bool): GameSettings.visor_effects = on)
	var modes := ["auto", "off", "light", "full"]
	_option(box, "Efectos de imagen", ["Automático (según la calidad)", "Desactivados", "Ligeros (viñeta, grano, destello)",
		"Completos (resplandor, etalonaje…)"], maxi(0, modes.find(GameSettings.post_mode)), func(i: int):
			GameSettings.post_mode = modes[i]
			GameSettings.post_effects = true,
		"Automático: completos en calidad alta y desactivados en media y baja (para mantener 60 FPS).")
	_check(box, "Datos de rendimiento (F3)", GameSettings.show_hud, func(on: bool): GameSettings.show_hud = on)


func _build_controls() -> void:
	var box := _page("Controles")
	_option(box, "Modo de pilotaje", ["Arcade (sencillo)", "Simulación (realista)"], 0 if GameSettings.flight_mode == "arcade" else 1,
		func(i: int): GameSettings.flight_mode = "arcade" if i == 0 else "simulacion",
		"Se aplica la próxima vez que te sientes a pilotar.")
	_slider(box, "Sensibilidad del ratón", 0.0005, 0.008, 0.0001, GameSettings.mouse_sensitivity,
		func(x: float): GameSettings.mouse_sensitivity = x, func(x: float): return "%.1f" % (x * 1000.0))
	_check(box, "Invertir eje Y del ratón", GameSettings.mouse_invert_y, func(on: bool): GameSettings.mouse_invert_y = on)
	_slider(box, "Velocidad de giro con mando", 0.5, 6.0, 0.1, GameSettings.pad_look_speed,
		func(x: float): GameSettings.pad_look_speed = x, func(x: float): return "%.1f" % x)
	_check(box, "Invertir eje Y del mando", GameSettings.pad_invert_y, func(on: bool): GameSettings.pad_invert_y = on)
	var pads := Input.get_connected_joypads()
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 14)
	info.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	if pads.is_empty():
		info.text = "Mandos conectados: ninguno. Funciona cualquier mando compatible con XInput o SDL (Xbox, PlayStation, genéricos)."
	else:
		var names := PackedStringArray()
		for d in pads:
			names.append("%d: %s" % [d + 1, Input.get_joy_name(d)])
		info.text = "Mandos conectados: " + ", ".join(names)
	box.add_child(info)


func _build_audio() -> void:
	var box := _page("Audio")
	var pct := func(x: float): return "%d %%" % int(round(x * 100.0))
	_slider(box, "Volumen general", 0.0, 1.0, 0.01, GameSettings.master_volume, func(x: float): GameSettings.master_volume = x, pct)
	_slider(box, "Banda sonora", 0.0, 1.0, 0.01, GameSettings.music_volume,
		func(x: float): GameSettings.music_volume = x, pct)
	var gaps := ["continua", "normal", "a_ratos", "nunca"]
	_option(box, "Frecuencia de la banda sonora", ["Continua", "Con pausas (normal)", "A ratos", "Desactivada"],
		maxi(0, gaps.find(GameSettings.music_gaps)), func(i: int): GameSettings.music_gaps = gaps[i],
		"Silencio entre pistas: el espacio también suena a vacío. Hay %d pistas en %s." % [GameAudio.tracks.size(), "rotación"])
	_check(box, "Avisar del título de cada pista", GameSettings.music_titles, func(on: bool): GameSettings.music_titles = on)
	_slider(box, "Música de la nave (megafonía)", 0.0, 1.0, 0.01, GameSettings.ship_music_volume,
		func(x: float): GameSettings.ship_music_volume = x, pct,
		"Tu música por los altavoces de la nave (M sentado a bordo). Mientras suena, la banda sonora calla. Más ajustes en el panel M.")
	_slider(box, "Efectos e interfaz", 0.0, 1.0, 0.01, GameSettings.sfx_volume, func(x: float): GameSettings.sfx_volume = x, pct)
	_slider(box, "Voces y diálogos", 0.0, 1.0, 0.01, GameSettings.voice_volume, func(x: float): GameSettings.voice_volume = x, pct)
	_check(box, "Subtítulos", GameSettings.subtitles, func(on: bool): GameSettings.subtitles = on)
	_slider(box, "Ambiente (viento, nave, motores)", 0.0, 1.0, 0.01, GameSettings.ambient_volume,
		func(x: float): GameSettings.ambient_volume = x, pct)


func _build_game() -> void:
	var box := _page("Juego")
	_slider(box, "Movimiento de cámara", 0.0, 1.0, 0.05, GameSettings.camera_motion, func(x: float): GameSettings.camera_motion = x,
		func(x: float): return "estática" if x < 0.01 else "%d %%" % int(round(x * 100.0)), "Balanceo de la cabeza al caminar, sacudidas y aterrizajes.")
	_slider(box, "Tamaño de la interfaz", 0.8, 1.3, 0.05, GameSettings.ui_scale, func(x: float): GameSettings.ui_scale = x,
		func(x: float): return "%d %%" % int(round(x * 100.0)))
	_option(box, "Pantalla dividida (cooperativo)", ["Lado a lado (vertical)", "Arriba y abajo (horizontal)"],
		0 if GameSettings.split_mode == "vertical" else 1, func(i: int): GameSettings.split_mode = "vertical" if i == 0 else "horizontal",
		"Se aplica al empezar una partida cooperativa.")
