class_name LoadingScreen
extends CanvasLayer
## Pantalla de carga (ADR-033): mientras se genera el terreno alrededor de la aparición. Fondo del menú,
## destino con coordenadas, barra de progreso estimada a partir de los trabajos de terreno pendientes,
## frases del diario de a bordo y consejos que rotan. Se desvanece al terminar.

const LINES := [
	"Registro de a bordo, día 1: la Tierra ya no está. Sólo quedan sus pedazos, girando.",
	"Si alguien más sobrevivió, la señal tardaría horas en cruzar el Sistema Solar.",
	"La Luna no tiene aire: aquí el silencio es real. Sólo oyes tu traje.",
	"Júpiter no tiene suelo. Bajo sus nubes, la presión aplastaría cualquier nave real.",
	"En Titán la atmósfera es más densa que la de la Tierra: podrías volar con alas en los brazos.",
	"Venus: 92 veces la presión de la Tierra y 460 °C. El cielo allí es amarillo.",
	"Una puesta de sol en Marte es azul.",
	"Neptuno está a 4 horas luz. Nuestro salto (ficticio) lo deja a dos minutos.",
	"Todas las posiciones de planetas y lunas son las reales de hoy.",
]
const TIPS := [
	"Consejo: R mirando al suelo recoge una muestra; analízala en el laboratorio del almacén.",
	"Consejo: Y (o Select en el mando) abre el menú rápido de la nave.",
	"Consejo: Tab abre el mapa; elige destino y pulsa «Viajar» sentado a los mandos.",
	"Consejo: en las literas puedes dormir 8 horas; en la enfermería, curarte.",
	"Consejo: F12 hace una foto sin la interfaz.",
	"Consejo: 1-4 a pie: emotes (saludar, bailar…).",
	"Consejo: G sentado a los mandos activa la gravedad artificial.",
]

var world: SurfaceWorld
var _root: Control
var _bar_fill: ColorRect
var _status: Label
var _line: Label
var _tip: Label
var _progress := 0.0
var _max_pending := 1
var _t := 0.0
var _line_i := 0
var _done := false
var _alpha := 1.0


func _ready() -> void:
	layer = 40
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiTheme.build()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/ui/menu_background.gdshader")
	mat.set_shader_parameter("size", get_viewport().get_visible_rect().size)
	mat.set_shader_parameter("dim", 0.45)
	mat.set_shader_parameter("planet_pos", Vector2(0.78, 0.36))
	mat.set_shader_parameter("planet_r", 0.16)
	bg.material = mat
	_root.add_child(bg)
	var col := VBoxContainer.new()
	col.anchor_left = 0.0
	col.anchor_right = 0.62
	col.anchor_top = 1.0
	col.anchor_bottom = 1.0
	col.offset_left = 70
	col.offset_top = -250
	col.offset_bottom = -60
	col.add_theme_constant_override("separation", 10)
	_root.add_child(col)
	var title := Label.new()
	title.text = UiTheme.GAME_TITLE
	title.add_theme_font_override("font", UiTheme.title_font())
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", UiTheme.TEXT)
	col.add_child(title)
	var dest := Label.new()
	var b := world.body
	var ll := Vector2(world.spawn_lat, world.spawn_lon)
	dest.text = "Destino: %s · %.2f° %s, %.2f° %s" % [b.display_name, absf(ll.x), "N" if ll.x >= 0.0 else "S", absf(ll.y), "E" if ll.y >= 0.0 else "O"]
	dest.add_theme_color_override("font_color", UiTheme.ACCENT)
	dest.add_theme_font_size_override("font_size", 18)
	col.add_child(dest)
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(1, 1, 1, 0.08)
	bar_bg.custom_minimum_size = Vector2(520, 4)
	bar_bg.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(bar_bg)
	_bar_fill = ColorRect.new()
	_bar_fill.color = UiTheme.ACCENT
	_bar_fill.size = Vector2(0, 4)
	bar_bg.add_child(_bar_fill)
	_status = Label.new()
	_status.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_status.add_theme_font_size_override("font_size", 14)
	col.add_child(_status)
	_line = Label.new()
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.custom_minimum_size = Vector2(560, 0)
	_line.add_theme_font_override("font", UiTheme.font(400))
	_line.add_theme_font_size_override("font_size", 17)
	_line.add_theme_color_override("font_color", UiTheme.TEXT)
	col.add_child(_line)
	_tip = Label.new()
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.custom_minimum_size = Vector2(560, 0)
	_tip.add_theme_font_size_override("font_size", 14)
	_tip.add_theme_color_override("font_color", UiTheme.AMBER)
	col.add_child(_tip)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_line_i = rng.randi() % LINES.size()
	_line.text = LINES[_line_i]
	_tip.text = TIPS[rng.randi() % TIPS.size()]


func _process(delta: float) -> void:
	_t += delta
	if world == null:
		return
	if world.surface_ready and world.net_hold:
		# Inicio coordinado: el mundo está listo; se espera a los demás para empezar todos a la vez.
		var n := 0
		for id in Net.peers:
			if str(Net.peers[id].get("status", "")) in ["cargado", "en partida"]:
				n += 1
		_progress = 1.0
		_status.text = "Esperando a los demás jugadores… %d/%d listos para empezar" % [n, Net.peers.size()]
		_bar_fill.size.x = 520.0
		return
	if world.surface_ready and not _done:
		_done = true
		_progress = 1.0
	if _done:
		_alpha = move_toward(_alpha, 0.0, delta * 2.0)
		_root.modulate.a = _alpha
		if _alpha <= 0.0:
			queue_free()
	else:
		var pend: int = world.terrain.pending_count()
		_max_pending = maxi(_max_pending, pend)
		var est := 1.0 - float(pend) / float(maxi(_max_pending, 1))
		# Nunca retrocede; avanza poco a poco aunque el terreno aún no haya empezado (los primeros trabajos).
		_progress = maxf(_progress, minf(est * 0.92 + 0.05, 0.97))
		_progress = minf(0.97, _progress + delta * 0.01)
		_status.text = "Generando el relieve de %s… %d %%" % [world.body.display_name, int(_progress * 100.0)]
	_bar_fill.size.x = 520.0 * _progress
	if fmod(_t, 6.0) < delta and _t > 1.0:
		_line_i = (_line_i + 1) % LINES.size()
		_line.text = LINES[_line_i]
