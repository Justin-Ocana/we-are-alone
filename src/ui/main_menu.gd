class_name MainMenu
extends CanvasLayer
## Menú principal (ADR-033). Fondo animado (la Tierra destruida sobre el horizonte lunar), columna de opciones
## a la izquierda y paneles a la derecha: cooperativo local, opciones, controles y créditos.
## Se maneja con ratón, teclado (flechas, Intro, Esc) o mando (cruceta/stick, A, B).

signal start_requested(mode: String, opts: Dictionary)   ## "continue", "new", "coop", "test"

const VERSION_TEXT := "v" + NetSession.GAME_VERSION + " · antes REAL SPACE EXPLORER"

var catalog: BodyCatalog
var _bg: ColorRect
var _bg_mat: ShaderMaterial
var _menu_box: VBoxContainer
var _desc: Label
var _right: PanelContainer
var _right_content: Control
var _buttons: Array[Button] = []
var _coop_p2 := -1
var _coop_label: Label
var _coop_start: Button
var _intro := 0.0
var _left: Control
var _dim := 0.0


func _ready() -> void:
	layer = 10
	_bg = ColorRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = load("res://src/ui/menu_background.gdshader")
	_bg.material = _bg_mat
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.build()
	add_child(root)
	_build_left(root)
	_build_footer(root)
	_right = PanelContainer.new()
	_right.anchor_left = 0.44
	_right.anchor_right = 0.97
	_right.anchor_top = 0.08
	_right.anchor_bottom = 0.9
	_right.visible = false
	root.add_child(_right)
	get_viewport().size_changed.connect(_on_resize)
	Input.joy_connection_changed.connect(func(_d: int, _c: bool): _update_coop_label())
	_on_resize()
	_buttons[0].grab_focus()
	if not catalog.errors.is_empty():
		var err := Label.new()
		err.text = "Errores en el catálogo:\n" + "\n".join(catalog.errors)
		err.modulate = Color(1, 0.5, 0.4)
		err.position = Vector2(70, 40)
		root.add_child(err)


func _on_resize() -> void:
	var sz := get_viewport().get_visible_rect().size
	_bg_mat.set_shader_parameter("size", sz)


func _process(delta: float) -> void:
	_intro = minf(1.0, _intro + delta * 1.4)
	var e := 1.0 - pow(1.0 - _intro, 3.0)
	_left.modulate.a = e
	_left.position.x = -40.0 * (1.0 - e)
	var want_dim := 1.0 if _right.visible else 0.0
	_dim = move_toward(_dim, want_dim, delta * 3.0)
	_bg_mat.set_shader_parameter("dim", _dim)


func _input(event: InputEvent) -> void:
	# Antes que la interfaz: la A del mando del jugador 2 no debe pulsar el botón enfocado.
	if _right.visible and _right_content != null and _right_content.name == "Coop":
		_coop_input(event)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and _right.visible:
		_close_right()
		get_viewport().set_input_as_handled()


# --- Columna izquierda ----------------------------------------------------------------------

func _build_left(root: Control) -> void:
	_left = Control.new()
	_left.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_left)
	var col := VBoxContainer.new()
	col.anchor_left = 0.0
	col.anchor_right = 0.4
	col.anchor_top = 0.0
	col.anchor_bottom = 1.0
	col.offset_left = 70
	col.offset_top = 46
	col.offset_bottom = -60
	col.add_theme_constant_override("separation", 0)
	_left.add_child(col)
	# Logotipo: «WE ARE» en blanco lunar y «ALONE?» con la interrogación en naranja de señal.
	var big := UiTheme.title_font()
	var l1 := Label.new()
	l1.text = "WE ARE"
	l1.add_theme_font_override("font", big)
	l1.add_theme_font_size_override("font_size", 54)
	l1.add_theme_color_override("font_color", UiTheme.TEXT)
	col.add_child(l1)
	var l2 := RichTextLabel.new()
	l2.bbcode_enabled = true
	l2.fit_content = true
	l2.scroll_active = false
	l2.autowrap_mode = TextServer.AUTOWRAP_OFF
	l2.custom_minimum_size = Vector2(420, 0)
	l2.add_theme_font_override("normal_font", big)
	l2.add_theme_font_size_override("normal_font_size", 72)
	l2.add_theme_constant_override("line_separation", -10)
	l2.text = "[color=#%s]ALONE[/color][color=#%s]?[/color]" % [UiTheme.TEXT.to_html(false), UiTheme.ACCENT.to_html(false)]
	col.add_child(l2)
	var sub := Label.new()
	sub.text = "La Tierra ya no existe. ¿Queda alguien ahí fuera?"
	sub.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	sub.add_theme_font_size_override("font_size", 16)
	col.add_child(sub)
	var bar := ColorRect.new()
	bar.color = UiTheme.AMBER
	bar.custom_minimum_size = Vector2(90, 3)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	col.add_child(spacer)
	col.add_child(bar)
	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 14)
	col.add_child(spacer2)
	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 4)
	col.add_child(_menu_box)
	var save := SaveGame.summary()
	if not save.is_empty():
		var when := Time.get_datetime_string_from_unix_time(int(save["saved"]) + _tz_offset(), true).substr(0, 16)
		_add_item("CONTINUAR", "Seguir donde lo dejaste: %s · guardada el %s%s." % [save["body"], when.replace("T", " "),
			" (cooperativo)" if save["coop"] else ""], func(): start_requested.emit("continue", {"coop": false}))
	_add_item("NUEVA PARTIDA", "Despiertas en una cápsula criogénica de la base lunar LF-01 de MacSpaces. Nadie responde.",
		func(): start_requested.emit("new", {}))
	_add_item("COOPERATIVO LOCAL", "Dos jugadores en el mismo PC a pantalla dividida: teclado y ratón + mando, o dos mandos.",
		func(): _open_coop())
	_add_item("EN LÍNEA", "Hasta 6 jugadores: crea una sala en tu PC (sin servidores de pago) o únete a la de un amigo.",
		func(): _open_online())
	_add_item("ASTRONAUTA", "Personaliza tu traje: nombre, colores, visor, franjas y mochila (también el del jugador 2).",
		func(): _open_customize())
	_add_item("OPCIONES", "Gráficos, controles, audio y juego.", func(): _open_options())
	_add_item("CONTROLES", "Teclado, ratón y mando: a pie, pilotando y en la nave.", func(): _open_controls())
	_add_item("CRÉDITOS Y FUENTES", "De dónde salen los datos del Sistema Solar y qué es ficticio.", func(): _open_credits())
	if catalog.get_body("proto_a") != null:
		_add_item("MUNDO DE PRUEBAS", "Prototipo-A: planeta ficticio para probar mecánicas.", func(): start_requested.emit("test", {}))
	_add_item("SALIR", "Cerrar el juego.", func(): get_tree().quit())
	var sp3 := Control.new()
	sp3.custom_minimum_size = Vector2(0, 18)
	col.add_child(sp3)
	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(380, 60)
	_desc.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_desc.add_theme_font_size_override("font_size", 15)
	col.add_child(_desc)


static func _tz_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


func _add_item(text: String, desc: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(360, 36)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_font_override("font", UiTheme.font(600))
	b.add_theme_font_size_override("font_size", 19)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0)
	normal.content_margin_left = 18
	var hot := StyleBoxFlat.new()
	hot.bg_color = Color(1.0, 0.55, 0.22, 0.12)
	hot.border_color = UiTheme.ACCENT
	hot.border_width_left = 4
	hot.content_margin_left = 28
	hot.corner_radius_top_right = 6
	hot.corner_radius_bottom_right = 6
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hot)
	b.add_theme_stylebox_override("focus", hot)
	b.add_theme_stylebox_override("pressed", hot)
	b.add_theme_stylebox_override("hover_pressed", hot)
	b.add_theme_color_override("font_color", UiTheme.TEXT if text != "SALIR" else UiTheme.TEXT_DIM)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.pressed.connect(cb)
	b.focus_entered.connect(func(): _desc.text = desc)
	b.mouse_entered.connect(func():
		b.grab_focus())
	_menu_box.add_child(b)
	_buttons.append(b)


func _build_footer(root: Control) -> void:
	var foot := Label.new()
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.offset_left = 70
	foot.offset_top = -40
	foot.text = "↑↓ / cruceta: elegir   ·   Intro / A: aceptar   ·   Esc / B: volver"
	foot.add_theme_font_size_override("font_size", 13)
	foot.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	root.add_child(foot)
	var ver := Label.new()
	ver.anchor_left = 1.0
	ver.anchor_right = 1.0
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.offset_left = -520
	ver.offset_right = -30
	ver.offset_top = -40
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var date := Time.get_date_string_from_system()
	ver.text = "%s   ·   fecha del juego: %s (real)" % [VERSION_TEXT, date]
	ver.add_theme_font_size_override("font_size", 13)
	ver.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	root.add_child(ver)


# --- Panel derecho --------------------------------------------------------------------------

func _show_right(content: Control) -> void:
	if _right_content != null:
		_right_content.queue_free()
	_right_content = content
	_right.add_child(content)
	_right.visible = true
	_right.modulate.a = 0.0
	create_tween().tween_property(_right, "modulate:a", 1.0, 0.18)


func _close_right() -> void:
	if _right_content != null:
		_right_content.queue_free()
		_right_content = null
	_right.visible = false
	_buttons[0].grab_focus()


func _open_online() -> void:
	var o := OnlinePanel.new()
	o.closed.connect(_close_right)
	o.start_requested.connect(func(m: String, opts: Dictionary):
		if m == "net_lobby":
			_open_lobby.call_deferred()
		else:
			start_requested.emit(m, opts))
	_show_right(o)
	o.focus_first.call_deferred()


## Sala de espera en línea (ADR-047): crear o unirse NO inicia la partida.
func _open_lobby() -> void:
	var l := LobbyPanel.new()
	l.closed.connect(_close_right)
	_show_right(l)
	l.focus_first.call_deferred()


## Aviso al volver al menú (por ejemplo, el anfitrión cerró la sala).
func show_notice(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", UiTheme.DANGER)
	_show_right(l)


func _open_options() -> void:
	var o := OptionsPanel.new()
	o.closed.connect(_close_right)
	_show_right(o)
	o.focus_first.call_deferred()


func _open_customize() -> void:
	var c := CustomizePanel.new()
	c.closed.connect(_close_right)
	_show_right(c)
	c.focus_first.call_deferred()


func _open_controls() -> void:
	var c := ControlsPanel.new()
	c.closed.connect(_close_right)
	_show_right(c)
	c.focus_first.call_deferred()


func _open_credits() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var head := HBoxContainer.new()
	var t := Label.new()
	t.text = "CRÉDITOS Y FUENTES"
	t.add_theme_font_override("font", UiTheme.title_font())
	t.add_theme_font_size_override("font_size", 26)
	t.add_theme_color_override("font_color", UiTheme.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var back := Button.new()
	back.text = "Volver"
	back.pressed.connect(_close_right)
	head.add_child(back)
	box.add_child(head)
	var txt := RichTextLabel.new()
	txt.bbcode_enabled = true
	txt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	txt.custom_minimum_size = Vector2(0, 380)
	txt.focus_mode = Control.FOCUS_ALL
	txt.add_theme_font_size_override("normal_font_size", 15)
	txt.text = """[color=#ff8c38][b]Datos reales[/b][/color]
• Órbitas de los planetas: elementos keplerianos del JPL (Standish y Williams, «Keplerian Elements for Approximate Positions of the Major Planets»).
• Lunas: elementos medios y parámetros físicos del JPL Solar System Dynamics (satélites planetarios).
• Radios, masas, rotación y atmósferas: NASA NSSDC Planetary Fact Sheets; orientación de los polos: IAU WGCCRE.
• Atmósfera de Júpiter validada con la sonda Galileo (≈ 23 bar, ≈ 426 K); Venus con las Venera/Magellan; Titán con Huygens.

[color=#ff8c38][b]Lo que es ficticio (por jugabilidad)[/b][/color]
• La Tierra destruida en fragmentos (argumento del juego).
• El salto por encima de la velocidad de la luz (hasta 1000 c) y la compensación inercial.
• Casco y traje que resisten cualquier atmósfera (sólo el Sol daña) y el rescate de emergencia.
• El relieve de todos los cuerpos es procedural (inspirado en cada uno, no son mapas reales).
• La composición de las muestras de roca es plausible pero procedural.

[color=#ff8c38][b]Hecho con[/b][/color]
Godot Engine 4 (renderizador Compatibility), GDScript. Tipografía del sistema (Bahnschrift).
Sonido: efectos grabados de Kenney (kenney.nl, CC0: Sci-Fi Sounds, UI Audio, Impact Sounds); el resto del audio y
la banda sonora, sintetizados para el juego (CC0).
Desarrollo asistido por Claude (Anthropic).
"""
	box.add_child(txt)
	_show_right(box)
	back.grab_focus.call_deferred()


# --- Cooperativo local ---------------------------------------------------------------------

func _open_coop() -> void:
	_coop_p2 = -1
	var box := VBoxContainer.new()
	box.name = "Coop"
	box.add_theme_constant_override("separation", 14)
	var head := HBoxContainer.new()
	var t := Label.new()
	t.text = "COOPERATIVO LOCAL"
	t.add_theme_font_override("font", UiTheme.title_font())
	t.add_theme_font_size_override("font_size", 26)
	t.add_theme_color_override("font_color", UiTheme.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var back := Button.new()
	back.text = "Volver"
	back.pressed.connect(_close_right)
	head.add_child(back)
	box.add_child(head)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 16)
	box.add_child(cards)
	cards.add_child(_player_card("JUGADOR 1", "Teclado y ratón\n(y cualquier otro mando)", UiTheme.ACCENT))
	var c2 := _player_card("JUGADOR 2", "", UiTheme.AMBER)
	_coop_label = c2.get_meta("label")
	cards.add_child(c2)
	_update_coop_label()
	var split := OptionButton.new()
	split.add_item("Pantalla dividida: lado a lado", 0)
	split.add_item("Pantalla dividida: arriba y abajo", 1)
	split.select(0 if GameSettings.split_mode == "vertical" else 1)
	split.item_selected.connect(func(i: int):
		GameSettings.split_mode = "vertical" if i == 0 else "horizontal"
		GameSettings.save_settings())
	box.add_child(split)
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 14)
	info.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	info.text = "Compartís la nave: uno pilota y el otro puede ir de copiloto, explorar a pie o manejar los sistemas. " \
		+ "A escala real sólo se puede simular una zona a la vez, así que si os separáis más de 3 km, quien esté fuera vuelve a la nave. " \
		+ "La pantalla dividida pide más al equipo: en gráficos integrados conviene la calidad baja."
	box.add_child(info)
	_coop_start = Button.new()
	_coop_start.text = "COMENZAR EN LA LUNA"
	_coop_start.disabled = true
	_coop_start.custom_minimum_size = Vector2(0, 48)
	_coop_start.pressed.connect(func():
		GameInput.configure_players(_coop_p2)
		start_requested.emit("coop", {"p2": _coop_p2}))
	box.add_child(_coop_start)
	_show_right(box)
	split.grab_focus.call_deferred()


func _player_card(title: String, body: String, col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", UiTheme.glass(12, Color(0.073, 0.073, 0.084, 0.9), Color(col.r, col.g, col.b, 0.6), 2))
	var v := VBoxContainer.new()
	p.add_child(v)
	var t := Label.new()
	t.text = title
	t.add_theme_font_override("font", UiTheme.title_font())
	t.add_theme_color_override("font_color", col)
	v.add_child(t)
	var l := Label.new()
	l.text = body
	l.custom_minimum_size = Vector2(0, 64)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	p.set_meta("label", l)
	return p


func _update_coop_label() -> void:
	if _coop_label == null:
		return
	var pads := Input.get_connected_joypads()
	if _coop_p2 >= 0:
		_coop_label.text = "Mando %d listo\n%s\n(B en ese mando: soltar)" % [_coop_p2 + 1, Input.get_joy_name(_coop_p2)]
	elif pads.is_empty():
		_coop_label.text = "Conecta un mando (Xbox, PlayStation o genérico)…"
	else:
		_coop_label.text = "Pulsa A en el mando del jugador 2\n(%d mando%s conectado%s)" % [pads.size(), "" if pads.size() == 1 else "s",
			"" if pads.size() == 1 else "s"]
	if _coop_start != null:
		_coop_start.disabled = _coop_p2 < 0


func _coop_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		if _coop_p2 < 0 and event.button_index == JOY_BUTTON_A:
			_coop_p2 = event.device
			_update_coop_label()
			_coop_start.grab_focus()
			get_viewport().set_input_as_handled()
		elif _coop_p2 == event.device and event.button_index == JOY_BUTTON_B:
			_coop_p2 = -1
			_update_coop_label()
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_update_coop_label()
