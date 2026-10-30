class_name CustomizePanel
extends HBoxContainer
## Personalización del astronauta (ADR-035): vista previa 3D que gira (con emotes de muestra), nombre, colores
## del traje, de las franjas y del visor, patrón de franjas y mochila. Un perfil por jugador (1 y 2);
## se guarda en los ajustes y se aplica al entrar en el mundo.

signal closed

const SUIT_COLORS := [Color(0.94, 0.92, 0.88), Color(0.28, 0.3, 0.34), Color(0.12, 0.12, 0.14), Color(0.86, 0.45, 0.18),
	Color(0.2, 0.42, 0.62), Color(0.55, 0.6, 0.38), Color(0.62, 0.2, 0.22), Color(0.82, 0.76, 0.6)]
const ACCENT_COLORS := [Color(1.0, 0.55, 0.22), Color(0.72, 0.09, 0.08), Color(0.35, 0.85, 0.8), Color(0.95, 0.85, 0.2),
	Color(0.3, 0.5, 1.0), Color(0.55, 0.95, 0.4), Color(0.85, 0.35, 0.85), Color(0.95, 0.95, 0.95)]
const VISOR_COLORS := [Color(0.85, 0.62, 0.25), Color(0.3, 0.75, 0.9), Color(0.12, 0.12, 0.14), Color(0.75, 0.75, 0.8),
	Color(0.55, 0.3, 0.8), Color(0.25, 0.8, 0.45), Color(0.9, 0.3, 0.25), Color(0.95, 0.85, 0.5)]

var _slot := 0
var _rig: AstronautRig
var _pivot: Node3D
var _name: LineEdit
var _t := 0.0
var _swatch_rows := {}
var _pattern: OptionButton
var _pack: OptionButton
var _slot_btns: Array[Button] = []


func _ready() -> void:
	add_theme_constant_override("separation", 18)
	# --- Vista previa
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(240, 380)
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(svc)
	var sv := SubViewport.new()
	sv.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # los viewports no heredan: sólo naves y astronautas interpolan (ADR-042)
	sv.own_world_3d = true
	sv.transparent_bg = true
	svc.add_child(sv)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.5, 0.48)
	e.ambient_light_energy = 0.7
	env.environment = e
	sv.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.6, 0.7, 0)
	key.light_energy = 1.3
	sv.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(-0.2, PI + 0.6, 0)
	rim.light_color = UiTheme.ACCENT
	rim.light_energy = 0.9
	sv.add_child(rim)
	var cam := Camera3D.new()
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam.position = Vector3(0, 1.0, 4.6)
	cam.fov = 32.0
	sv.add_child(cam)
	_pivot = Node3D.new()
	sv.add_child(_pivot)
	_rig = AstronautRig.new()
	_pivot.add_child(_rig)
	# --- Controles
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 9)
	add_child(box)
	var head := HBoxContainer.new()
	var t := Label.new()
	t.text = "TU ASTRONAUTA"
	t.add_theme_font_override("font", UiTheme.title_font())
	t.add_theme_font_size_override("font_size", 26)
	t.add_theme_color_override("font_color", UiTheme.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var back := Button.new()
	back.text = "Volver"
	back.pressed.connect(func():
		GameSettings.save_settings()
		closed.emit())
	head.add_child(back)
	box.add_child(head)
	var slots := HBoxContainer.new()
	for i in 2:
		var b := Button.new()
		b.text = "Jugador %d" % (i + 1)
		b.toggle_mode = true
		b.pressed.connect(func(): _select_slot(i))
		slots.add_child(b)
		_slot_btns.append(b)
	box.add_child(slots)
	var nrow := HBoxContainer.new()
	var nl := Label.new()
	nl.text = "Nombre"
	nl.custom_minimum_size = Vector2(120, 0)
	nrow.add_child(nl)
	_name = LineEdit.new()
	_name.max_length = 16
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.text_changed.connect(func(s: String): _prof()["name"] = s if s.strip_edges() != "" else "Jugador %d" % (_slot + 1))
	nrow.add_child(_name)
	box.add_child(nrow)
	_swatches(box, "Traje", "suit", SUIT_COLORS)
	_swatches(box, "Franjas", "accent", ACCENT_COLORS)
	_swatches(box, "Visor", "visor", VISOR_COLORS)
	_pattern = _option_row(box, "Franjas", ["De comandante (izquierda)", "Dobles", "Traje liso"], "pattern")
	_pack = _option_row(box, "Mochila", ["Soporte vital estándar", "Tanques dobles"], "backpack")
	var hint := Label.new()
	hint.text = "En el juego: 1 saludar · 2 bailar · 3 baile robot · 4 celebrar (con mando, en el menú rápido)."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	box.add_child(hint)
	_select_slot(0)


func focus_first() -> void:
	_slot_btns[0].grab_focus()


func _prof() -> Dictionary:
	return GameSettings.profile(_slot)


func _select_slot(i: int) -> void:
	_slot = i
	for k in _slot_btns.size():
		_slot_btns[k].button_pressed = k == i
	var p := _prof()
	_name.text = str(p["name"])
	_pattern.select(int(p["pattern"]))
	_pack.select(int(p["backpack"]))
	_refresh()


func _refresh() -> void:
	_rig.apply_profile(_prof())
	for key in _swatch_rows:
		var cur: Color = _prof()[key]
		for b: Button in _swatch_rows[key]:
			var c: Color = b.get_meta("color")
			var sb := StyleBoxFlat.new()
			sb.bg_color = c
			sb.set_corner_radius_all(4)
			var sel := c.is_equal_approx(cur)
			sb.border_color = UiTheme.TEXT if sel else Color(0, 0, 0, 0.5)
			sb.set_border_width_all(3 if sel else 1)
			for st in ["normal", "hover", "pressed", "focus"]:
				b.add_theme_stylebox_override(st, sb)


func _swatches(box: Container, label: String, key: String, colors: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(120, 0)
	row.add_child(l)
	var btns: Array = []
	for c: Color in colors:
		var b := Button.new()
		b.custom_minimum_size = Vector2(30, 30)
		b.set_meta("color", c)
		b.pressed.connect(func():
			_prof()[key] = c
			_refresh())
		row.add_child(b)
		btns.append(b)
	_swatch_rows[key] = btns
	box.add_child(row)


func _option_row(box: Container, label: String, items: Array, key: String) -> OptionButton:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(120, 0)
	row.add_child(l)
	var o := OptionButton.new()
	for i in items.size():
		o.add_item(items[i], i)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.item_selected.connect(func(i: int):
		_prof()[key] = i
		_refresh())
	row.add_child(o)
	box.add_child(row)
	return o


func _process(delta: float) -> void:
	_t += delta
	_pivot.rotation.y = _t * 0.6
	# Ciclo de emotes de muestra en la vista previa.
	var cyc := fmod(_t, 12.0)
	_rig.reset_pose()
	if cyc < 3.0:
		_rig.apply_emote("wave", cyc)
	elif cyc >= 6.0 and cyc < 9.5:
		_rig.apply_emote("dance", cyc - 6.0)
