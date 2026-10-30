class_name DebugHud
extends CanvasLayer
## HUD de exploración y diagnóstico: posición, altitud, gravedad, rendimiento, terreno, memoria.

var world: Node  # SurfaceWorld
var _info: Label
var _help: Label
var _status: Label
var _crosshair: Label
var _accum := 0.0


func _ready() -> void:
	layer = 5
	_info = _make_label(Vector2(12, 10), 15)
	_status = _make_label(Vector2(0, 0), 22)
	_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crosshair = _make_label(Vector2.ZERO, 18)
	_crosshair.text = "+"
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help = _make_label(Vector2(12, 0), 14)
	_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_help.position = Vector2(12, -150)
	_help.text = "WASD mover · Mayús correr · Espacio saltar · V cámara 1ª/3ª · Alt mirada libre\n" \
		+ "Clic derecho enfocar · Q/E asomarse · F interactuar · B llamar a la nave\n" \
		+ "Flotando: WASD/Espacio/Ctrl propulsores · Q/E alabeo · X estabilizar\n" \
		+ "N vuelo depuración (rueda = velocidad, Espacio/Ctrl subir/bajar)\n" \
		+ ", / . velocidad del tiempo · F2 ocultar interfaz · F3 rendimiento · F1 ayuda · Esc pausa"
	_help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_set_debug_visible(GameSettings.show_hud)


func _make_label(pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	add_child(l)
	return l


## El HUD de depuración (F3) se oculta por defecto; el aviso de estado siempre es visible.
func _set_debug_visible(on: bool) -> void:
	_info.visible = on
	_crosshair.visible = on


func set_status(text: String) -> void:
	_status.text = text


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_hud"):
		GameSettings.show_hud = not GameSettings.show_hud
		_set_debug_visible(GameSettings.show_hud)
		GameSettings.save_settings()
	elif event.is_action_pressed(&"toggle_help"):
		_help.visible = not _help.visible


func _process(delta: float) -> void:
	var show := GameSettings.show_hud and not GameSettings.ui_hidden
	if _info.visible != show:
		_set_debug_visible(show)
	_help.modulate.a = 0.0 if GameSettings.ui_hidden else 1.0
	_accum += delta
	if _accum < 0.25 or world == null or not _info.visible:
		return
	_accum = 0.0
	_info.text = world.debug_text()
