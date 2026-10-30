class_name ControlsPanel
extends VBoxContainer
## Referencia de controles (ADR-033): teclado y ratón junto a mando, por situación. Se genera a partir de las
## asignaciones reales de GameInput, así no puede quedarse desfasada.

signal closed

const SECTIONS := [
	["A pie", [
		["Moverse", ["move_forward", "move_left", "move_back", "move_right"], "Stick izq."],
		["Mirar", [], "Stick der.", "Ratón"],
		["Saltar / subir (propulsores)", ["jump"]],
		["Agacharse / bajar", ["crouch_down"]],
		["Correr", ["sprint"]],
		["Interactuar (sentarse, camas, taquillas…)", ["interact"]],
		["Asomarse / alabeo flotando", ["lean_left", "lean_right"]],
		["Estabilizar el giro (flotando)", ["stabilize"]],
		["Mirada libre", ["freelook"]],
		["Enfocar la vista", ["focus"]],
		["Cámara 1ª / 3ª persona", ["toggle_camera"]],
		["Llamar a la nave", ["recall_ship"]],
		["Escanear / tomar muestra", ["scan"]],
	]],
	["Pilotaje (sentado en el puesto del piloto)", [
		["Acelerar / frenar", ["ship_throttle_up", "ship_throttle_down"]],
		["Apuntar la nave", [], "Stick der.", "Ratón"],
		["Girar (arcade) / lateral (simulación)", ["ship_strafe_left", "ship_strafe_right"]],
		["Subir / bajar", ["ship_up", "ship_down"]],
		["Alabeo", ["ship_roll_left", "ship_roll_right"]],
		["Turbo", ["ship_boost"]],
		["Parar en seco", ["ship_stop"]],
		["Piloto automático", ["ship_autopilot"]],
		["Aterrizaje automático", ["ship_approach"]],
		["Motor lumínico", ["ship_light"]],
		["Gravedad artificial", ["ship_gravity"]],
		["Focos exteriores", ["ship_floodlights"]],
		["Tren de aterrizaje", ["ship_gear"]],
		["Vista exterior", ["toggle_camera"]],
		["Mirar alrededor", ["freelook"], "", "Clic der."],
		["Ayuda de pilotaje", ["toggle_controls_help"]],
	]],
	["General", [
		["Mapa del Sistema Solar", ["toggle_map"]],
		["Diario de exploración", ["journal"]],
		["Menú rápido de la nave", ["quick_menu"]],
		["Música de la nave", ["music_panel"]],
		["Modo fiesta (a bordo)", ["party_mode"]],
		["Foto (captura)", ["photo"]],
		["Plantar baliza", ["beacon"]],
		["Ocultar la interfaz", ["toggle_all_ui"]],
		["Pausa", ["pause"]],
	]],
]


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "CONTROLES"
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
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_ALL
	add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	for sec in SECTIONS:
		var h := Label.new()
		h.text = sec[0].to_upper()
		h.add_theme_font_override("font", UiTheme.title_font())
		h.add_theme_font_size_override("font_size", 15)
		h.add_theme_color_override("font_color", UiTheme.AMBER)
		box.add_child(h)
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 18)
		grid.add_theme_constant_override("v_separation", 3)
		box.add_child(grid)
		for e in sec[1]:
			_cell(grid, e[0], UiTheme.TEXT, 300)
			_cell(grid, _keys(e, false), UiTheme.ACCENT, 170)
			_cell(grid, _keys(e, true), Color(0.6, 1.0, 0.7), 150)
		box.add_child(HSeparator.new())
	var note := Label.new()
	note.text = "Columna central: teclado y ratón · derecha: mando (disposición Xbox). Con dos jugadores, el jugador 2 usa su mando."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	box.add_child(note)


func focus_first() -> void:
	(get_child(1) as Control).grab_focus()


func _cell(grid: GridContainer, text: String, col: Color, w: float) -> void:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(w, 0)
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", col)
	grid.add_child(l)


static func _keys(e: Array, pad: bool) -> String:
	if pad and e.size() > 2 and e[2] != "":
		return e[2]
	if not pad and e.size() > 3:
		return e[3]
	var out := PackedStringArray()
	for a in e[1]:
		var g := PlayerInput.glyph_for(StringName(a), pad)
		if g != "—" and not out.has(g):
			out.append(g)
	if out.is_empty():
		return "menú rápido" if pad else "—"
	return " / ".join(out)
