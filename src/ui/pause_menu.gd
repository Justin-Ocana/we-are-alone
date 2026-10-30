class_name PauseMenu
extends CanvasLayer
## Menú de pausa (ADR-033): misma estética que el principal. Reanudar, diario, opciones, controles, guardar,
## volver al menú (guarda) y salir. Funciona con ratón, teclado y mando.

signal resume_requested
signal main_menu_requested
signal save_requested
signal journal_requested

var _dim: ColorRect
var _col: VBoxContainer
var _right: PanelContainer
var _right_content: Control
var _buttons: Array[Button] = []
var _status: Label
var _online: Label
var _status_t := 0.0


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.02, 0.025, 0.74)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.build()
	add_child(root)
	_col = VBoxContainer.new()
	_col.offset_left = 70
	_col.offset_top = 80
	_col.add_theme_constant_override("separation", 4)
	root.add_child(_col)
	var t := Label.new()
	t.text = "PAUSA"
	t.add_theme_font_override("font", UiTheme.title_font())
	t.add_theme_font_size_override("font_size", 44)
	t.add_theme_color_override("font_color", UiTheme.ACCENT)
	_col.add_child(t)
	var bar := ColorRect.new()
	bar.color = UiTheme.AMBER
	bar.custom_minimum_size = Vector2(70, 3)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_col.add_child(bar)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 20)
	_col.add_child(sp)
	_item("REANUDAR", func(): resume_requested.emit())
	_item("DIARIO DE EXPLORACIÓN", func(): journal_requested.emit())
	_item("OPCIONES", _open_options)
	_item("CONTROLES", _open_controls)
	_item("GUARDAR PARTIDA", func(): save_requested.emit())
	_item("MENÚ PRINCIPAL (guarda)", func(): main_menu_requested.emit())
	_item("SALIR DEL JUEGO", func(): get_tree().quit())
	_status = Label.new()
	_status.add_theme_color_override("font_color", UiTheme.OK)
	_status.custom_minimum_size = Vector2(0, 30)
	_col.add_child(_status)
	_online = Label.new()
	_online.add_theme_color_override("font_color", UiTheme.DATA)
	_online.add_theme_font_size_override("font_size", 14)
	_online.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_online.custom_minimum_size = Vector2(420, 0)
	_online.visible = false
	_col.add_child(_online)
	var hint := Label.new()
	hint.text = "F2 oculta la interfaz · H ayuda de pilotaje · Esc / Start reanudar"
	hint.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	hint.add_theme_font_size_override("font_size", 13)
	_col.add_child(hint)
	_right = PanelContainer.new()
	_right.anchor_left = 0.42
	_right.anchor_right = 0.97
	_right.anchor_top = 0.08
	_right.anchor_bottom = 0.92
	_right.visible = false
	root.add_child(_right)
	visible = false


func _item(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(340, 40)
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
	for st in ["hover", "focus", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, hot)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.pressed.connect(cb)
	b.mouse_entered.connect(func(): b.grab_focus())
	_col.add_child(b)
	_buttons.append(b)


func _process(delta: float) -> void:
	if _status_t > 0.0:
		_status_t -= delta
		if _status_t <= 0.0:
			_status.text = ""


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel") and _right.visible:
		_close_right()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"pause") or (InputMap.has_action(&"p2_pause") and event.is_action_pressed(&"p2_pause")):
		resume_requested.emit()
		get_viewport().set_input_as_handled()


## Información de la sala en línea (jugadores e IP para invitar); vacío = partida sin conexión.
func set_online_info(lines: PackedStringArray) -> void:
	_online.text = "\n".join(lines)
	_online.visible = not lines.is_empty()


func show_status(text: String) -> void:
	_status.text = text
	_status_t = 3.0


func _show_right(c: Control) -> void:
	if _right_content != null:
		_right_content.queue_free()
	_right_content = c
	_right.add_child(c)
	_right.visible = true


func _close_right() -> void:
	if _right_content != null:
		_right_content.queue_free()
		_right_content = null
	_right.visible = false
	_buttons[0].grab_focus()


func _open_options() -> void:
	var o := OptionsPanel.new()
	o.closed.connect(_close_right)
	_show_right(o)
	o.focus_first.call_deferred()


func _open_controls() -> void:
	var c := ControlsPanel.new()
	c.closed.connect(_close_right)
	_show_right(c)
	c.focus_first.call_deferred()


func open() -> void:
	visible = true
	_close_right()
	_buttons[0].grab_focus()


func close() -> void:
	_close_right()
	visible = false
