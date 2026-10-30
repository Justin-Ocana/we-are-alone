class_name VoiceOptions
extends RefCounted
## Pestaña «Voz» de Opciones (ADR-046). Todo es PERSONAL y se guarda (user://settings.cfg); lo que depende de la sala
## (alcance máximo de proximidad) se indica como regla del anfitrión.

var panel: OptionsPanel
var _meter: ProgressBar
var _bind_buttons := {}
var _capturing := ""


func build(p: OptionsPanel) -> void:
	panel = p
	var box := p._page("Voz")
	_section(box, "MICRÓFONO Y AUDIO")
	p._check(box, "Chat de voz", GameSettings.voice_enabled, func(on: bool): GameSettings.voice_enabled = on,
		"Sólo funciona en partidas en línea. Desactivado, ni se envía ni se recibe voz.")
	var ins := AudioServer.get_input_device_list()
	p._option(box, "Micrófono", ins, maxi(0, ins.find(GameSettings.voice_input_device if GameSettings.voice_input_device != "" else "Default")),
		func(i: int): GameSettings.voice_input_device = ins[i]; Voice.apply_settings()).fit_to_longest_item = false
	var outs := AudioServer.get_output_device_list()
	p._option(box, "Salida de audio", outs, maxi(0, outs.find(GameSettings.voice_output_device if GameSettings.voice_output_device != "" else "Default")),
		func(i: int): GameSettings.voice_output_device = outs[i]; Voice.apply_settings()).fit_to_longest_item = false
	var pct := func(x: float): return "%d %%" % int(round(x * 100.0))
	p._slider(box, "Voces cercanas (proximidad)", 0.0, 1.5, 0.01, GameSettings.voice_vol_prox,
		func(x: float): GameSettings.voice_vol_prox = x; Voice.apply_settings(), pct)
	p._slider(box, "Radio del traje", 0.0, 1.5, 0.01, GameSettings.voice_vol_radio,
		func(x: float): GameSettings.voice_vol_radio = x; Voice.apply_settings(), pct)
	p._slider(box, "Altavoces de la nave", 0.0, 1.5, 0.01, GameSettings.voice_vol_ship,
		func(x: float): GameSettings.voice_vol_ship = x; Voice.apply_settings(), pct,
		"Independiente de las voces cercanas. El volumen general de voces está en la pestaña Audio.")
	p._slider(box, "Sensibilidad del micrófono", 0.0, 1.0, 0.01, 1.0 - GameSettings.voice_vad_threshold,
		func(x: float): GameSettings.voice_vad_threshold = 1.0 - x, pct,
		"Con activación por voz: más sensibilidad = transmite con voz más baja (y también más ruido de fondo).")
	_meter = ProgressBar.new()
	_meter.min_value = 0.0
	_meter.max_value = 0.15
	_meter.show_percentage = false
	_meter.custom_minimum_size = Vector2(0, 12)
	_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(UiTheme.TEXT_DIM, 0.25)
	var fill := StyleBoxFlat.new()
	fill.bg_color = VoiceHud.path_color("prox")
	_meter.add_theme_stylebox_override("background", bg)
	_meter.add_theme_stylebox_override("fill", fill)
	p._row(box, "Nivel del micrófono", _meter)
	var test := Button.new()
	test.text = "Probar micrófono (te oirás a ti mismo)"
	test.toggle_mode = true
	test.toggled.connect(func(on: bool): Voice.set_mic_test(on))
	p._row(box, "Prueba", test)
	_section(box, "CONTROLES")
	p._option(box, "Voz de proximidad", ["Activación por voz", "Pulsar para hablar"], 0 if GameSettings.voice_mode == "vad" else 1,
		func(i: int): GameSettings.voice_mode = "vad" if i == 0 else "ptt")
	for a in [["voice_prox", "Hablar (pulsar para hablar)"], ["voice_radio", "Transmitir por radio (mantener)"],
			["voice_ship", "Canal de la nave (mantener)"], ["voice_channel", "Cambiar canal de radio"]]:
		var b := Button.new()
		b.text = PlayerInput.glyph_for(StringName(a[0]), false)
		b.pressed.connect(_start_capture.bind(a[0]))
		_bind_buttons[a[0]] = b
		p._row(box, a[1], b)
	var hint := Label.new()
	hint.text = "Pulsa el botón y después la tecla o el botón del ratón nuevo (Esc cancela). Si la tecla ya la usa otra acción de voz, se intercambian. Con mando, la radio va en el botón Compartir/Captura."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	box.add_child(hint)
	_section(box, "COMPORTAMIENTO")
	p._slider(box, "Distancia de escucha", 5.0, 80.0, 1.0, GameSettings.voice_range, func(x: float): GameSettings.voice_range = x,
		func(x: float): return "%d m" % int(x),
		"Regla de la sala: nunca más de lo que fije el anfitrión (ahora %d m)." % int(Net.rules.get("prox_range", 35.0)))
	p._check(box, "Megafonía de la nave", GameSettings.voice_effects, func(on: bool): GameSettings.voice_effects = on,
		"Los altavoces de la nave suenan a megafonía. La voz cercana siempre suena limpia, sin efectos.")
	p._check(box, "Procesado de radio", GameSettings.voice_radio_fx, func(on: bool): GameSettings.voice_radio_fx = on,
		"Compresión, ruido y cortes con poca cobertura. Desactivado, la radio suena limpia.")
	p._check(box, "Escuchar la radio personal", GameSettings.voice_listen_radio, func(on: bool): GameSettings.voice_listen_radio = on)
	p._check(box, "Vinculado al canal de la nave", GameSettings.voice_ship_linked, func(on: bool): GameSettings.voice_ship_linked = on,
		"Puedes transmitir por el canal de la nave.")
	p._check(box, "Escuchar el canal de la nave", GameSettings.voice_listen_ship, func(on: bool): GameSettings.voice_listen_ship = on)
	p._check(box, "Altavoces de la nave", GameSettings.voice_ship_speakers, func(on: bool): GameSettings.voice_ship_speakers = on,
		"A bordo, el canal de la nave suena por los altavoces; si no, por la radio del traje.")
	if Net.is_online():
		_section(box, "JUGADORES")
		for id in Net.peers:
			if int(id) == Net.my_id():
				continue
			var nm := str(Net.peers[id].get("name", "?"))
			var row := HBoxContainer.new()
			var mute := CheckButton.new()
			mute.text = "Silenciar"
			mute.button_pressed = bool(GameSettings.voice_mutes.get(nm, false))
			mute.toggled.connect(func(on: bool):
				if on:
					GameSettings.voice_mutes[nm] = true
				else:
					GameSettings.voice_mutes.erase(nm)
				Voice.apply_settings()
				p._save())
			row.add_child(mute)
			var vs := HSlider.new()
			vs.min_value = 0.0
			vs.max_value = 2.0
			vs.step = 0.05
			vs.value = float(GameSettings.voice_player_volume.get(nm, 1.0))
			vs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			vs.value_changed.connect(func(x: float):
				GameSettings.voice_player_volume[nm] = x
				Voice.apply_settings()
				p._save())
			row.add_child(vs)
			p._row(box, nm, row)


func _section(box: Container, title: String) -> void:
	var l := Label.new()
	l.text = title
	l.add_theme_color_override("font_color", UiTheme.ACCENT)
	l.add_theme_font_size_override("font_size", 14)
	box.add_child(l)


func process() -> void:
	if _meter != null and is_instance_valid(_meter):
		_meter.value = Voice.mic_level


func _start_capture(action: String) -> void:
	_capturing = action
	_bind_buttons[action].text = "Pulsa una tecla…"


## Reasignación: la siguiente tecla o botón del ratón (Esc cancela). Devuelve true si se ha consumido el evento.
func handle_input(event: InputEvent) -> bool:
	if _capturing == "":
		return false
	var b := []
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			_bind_buttons[_capturing].text = PlayerInput.glyph_for(StringName(_capturing), false)
			_capturing = ""
			return true
		b = ["key", int((event as InputEventKey).physical_keycode)]
	elif event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index > MOUSE_BUTTON_RIGHT:
		b = ["mouse", int((event as InputEventMouseButton).button_index)]
	if b.is_empty():
		return false
	# Sin conflictos entre las acciones de voz: si otra ya usaba esa tecla, se intercambian.
	var old = GameSettings.voice_bindings.get(_capturing, [])
	for other in _bind_buttons:
		if other != _capturing:
			var ob = GameSettings.voice_bindings.get(other, [])
			if ob is Array and ob == b:
				GameSettings.voice_bindings[other] = old
	GameSettings.voice_bindings[_capturing] = b
	GameInput.apply_voice_bindings()
	for a in _bind_buttons:
		_bind_buttons[a].text = PlayerInput.glyph_for(StringName(a), false)
	_capturing = ""
	panel._save()
	return true
