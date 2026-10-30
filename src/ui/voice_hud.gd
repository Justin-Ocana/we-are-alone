class_name VoiceHud
extends CanvasLayer
## Indicadores de voz (ADR-046), discretos, a la izquierda a media altura:
## - Micrófono propio: gris en reposo; verde = proximidad (late con el nivel), azul = radio (canal), naranja = nave.
## - Estado del canal de radio seleccionado: libre / TRANSMITIENDO / OCUPADO por alguien.
## - Quién habla ahora y por qué vía (proximidad, radio Cn, altavoces de la nave, sala de espera).
## - Avisos: canal ocupado, sin señal de radio, micrófono no disponible.
## Cada indicador lee el estado real de VoiceChat (nada es decorativo).

const COL_PROX := Color(0.45, 0.95, 0.55)
const COL_RADIO := Color(0.45, 0.75, 1.0)
const COL_SHIP := Color(1.0, 0.6, 0.22)
const COL_IDLE := Color(0.6, 0.62, 0.66)

var voice: VoiceChat
var _canvas: Control
var _t := 0.0
var _active_t := 0.0


func _ready() -> void:
	layer = 9
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)


func _process(delta: float) -> void:
	_t += delta
	visible = voice != null and voice.active() and not GameSettings.ui_hidden
	_active_t = _active_t + delta if visible else 0.0
	if visible:
		_canvas.queue_redraw()


static func path_color(path: String) -> Color:
	match path:
		"radio":
			return COL_RADIO
		"speaker":
			return COL_SHIP
	return COL_PROX


static func path_label(path: String, ch: int = 0) -> String:
	match path:
		"radio":
			return "RADIO" + (" C%d" % ch if ch > 0 else "")
		"speaker":
			return "NAVE · altavoces"
		"lobby":
			return "SALA"
	return "PROXIMIDAD"


func _on_draw() -> void:
	var vp := _canvas.get_viewport_rect().size
	var s := clampf(vp.y / 720.0, 0.8, 1.6) * GameSettings.ui_scale
	var f := UiTheme.font(600)
	var fs := UiTheme.font(500)
	var base := Vector2(24 * s, vp.y * 0.56)
	# --- Micrófono propio.
	var col := COL_IDLE
	var mode := "MICRO"
	if voice.tx_ship:
		col = COL_SHIP
		mode = "NAVE"
	elif voice.tx_radio:
		col = COL_RADIO
		mode = "RADIO C%d" % voice.radio_channel
	elif voice.tx_prox:
		col = COL_PROX
		mode = "PROXIMIDAD"
	var r := 13.0 * s
	var c := base + Vector2(r, r)
	_canvas.draw_style_box(UiTheme.glass(10, UiTheme.GLASS, Color(col, 0.5)), Rect2(base - Vector2(6, 6) * s, Vector2(250 * s, 52 * s)))
	var pulse := 1.0
	if voice.tx_prox or voice.tx_radio or voice.tx_ship:
		pulse = 1.0 + clampf(voice.mic_level * 12.0, 0.0, 0.5)
		_canvas.draw_circle(c, r * pulse, Color(col, 0.25))
	_canvas.draw_circle(c, r * 0.72, col)
	# Silueta del micrófono.
	_canvas.draw_rect(Rect2(c + Vector2(-2.5, -6) * s, Vector2(5, 9) * s), Color(0.05, 0.05, 0.06))
	_canvas.draw_line(c + Vector2(0, 4) * s, c + Vector2(0, 7) * s, Color(0.05, 0.05, 0.06), 1.5 * s)
	_canvas.draw_string(f, base + Vector2(34 * s, 12 * s), mode, HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * s), col)
	# Estado del canal de radio.
	var owner := int(voice.radio_owners.get(voice.radio_channel, 0))
	var st := "C%d · libre" % voice.radio_channel
	var st_col := UiTheme.TEXT_DIM
	if owner == Net.my_id():
		st = "C%d · TRANSMITIENDO" % voice.radio_channel
		st_col = COL_RADIO
	elif owner != 0:
		st = "C%d · OCUPADO · %s" % [voice.radio_channel, Net.peers.get(owner, {}).get("name", "?")]
		st_col = UiTheme.DANGER
	_canvas.draw_string(fs, base + Vector2(34 * s, 30 * s), st, HORIZONTAL_ALIGNMENT_LEFT, 210 * s, int(11 * s), st_col)
	var keys := "%s radio · %s nave · %s canal" % [PlayerInput.glyph_for(&"voice_radio", false), PlayerInput.glyph_for(&"voice_ship", false),
		PlayerInput.glyph_for(&"voice_channel", false)]
	if GameSettings.voice_mode == "ptt":
		keys = "%s hablar · " % PlayerInput.glyph_for(&"voice_prox", false) + keys
	_canvas.draw_string(fs, base + Vector2(0, 58 * s), keys, HORIZONTAL_ALIGNMENT_LEFT, -1, int(10 * s), UiTheme.TEXT_DIM)
	# --- Quién habla.
	var y := base.y + 78 * s
	for id in voice.sources():
		var path := voice.is_speaking(int(id))
		if path == "":
			continue
		var name := str(Net.peers.get(int(id), {}).get("name", "?"))
		var pc := path_color(path)
		var ch := 0
		for k in voice.radio_owners:
			if int(voice.radio_owners[k]) == int(id):
				ch = int(k)
		var bars := 3
		for b in bars:
			var h := (4.0 + 6.0 * absf(sin(_t * 9.0 + b * 1.7 + int(id)))) * s
			_canvas.draw_rect(Rect2(Vector2(base.x + b * 5 * s, y - h), Vector2(3 * s, h)), pc)
		_canvas.draw_string(f, Vector2(base.x + 20 * s, y), name, HORIZONTAL_ALIGNMENT_LEFT, 130 * s, int(13 * s), UiTheme.TEXT)
		_canvas.draw_string(fs, Vector2(base.x + 150 * s, y), path_label(path, ch), HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * s), pc)
		y += 20 * s
	# --- Avisos.
	var now := Time.get_ticks_msec()
	var warn := ""
	if now < voice.radio_busy_until:
		warn = "Canal C%d ocupado: espera a que quede libre" % voice.radio_channel
	elif now < voice.no_signal_until:
		warn = "Sin señal de radio: demasiado lejos"
	elif not voice.mic_ok and _active_t > 3.0:
		warn = "Micrófono no disponible (revisa Opciones > Voz)"
	elif not Net.is_online() and not voice.mic_test:
		warn = "Sin conexión"
	if warn != "":
		_canvas.draw_string(f, Vector2(base.x, base.y - 16 * s), warn, HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 * s), UiTheme.DANGER)
