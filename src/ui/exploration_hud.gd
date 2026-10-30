class_name ExplorationHud
extends CanvasLayer
## Interfaz de exploración de UN jugador (ADR-034), en su mitad de pantalla en el cooperativo:
## - Avisos apilados (muestra recogida, primera visita, foto guardada…).
## - Ficha del escáner con los datos del cuerpo escaneado.
## - Menú rápido de la nave (Y / Select): lista navegable con el teclado o el mando de ESE jugador.
## - Fundido a negro (dormir) y destello (foto).

const A := UiTheme.ACCENT
const AMB := UiTheme.AMBER

var astro: Astronaut
var others: Array = []           ## los demás jugadores (etiqueta con su nombre; cooperativo)
var _canvas: Control
var _notes: Array = []           ## [{text, t, col}]
var _card_title := ""
var _card_lines: PackedStringArray = []
var _card_t := 0.0
var _menu_items: Array = []      ## [{label, cb, enabled, hint}]
var _menu_sel := 0
var _menu_open := false
var _fade := 0.0
var _fade_target := 0.0
var _fade_text := ""
var _flash := 0.0
var _t := 0.0


func _ready() -> void:
	layer = 7
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)
	# Título de cada pista de la banda sonora, discreto y sin sonido (ronda 14).
	GameAudio.track_started.connect(func(title: String, author: String):
		if GameSettings.music_titles and title != "":
			notify("♪ %s · %s" % [title, author], UiTheme.TEXT_DIM, true))


func notify(text: String, col: Color = AMB, silent := false) -> void:
	if not silent:
		GameAudio.play("error" if col == UiTheme.DANGER else "notify", -12.0 if col == UiTheme.TEXT_DIM else -7.0)
	_notes.push_front({"text": text, "t": 5.0, "col": col})
	if _notes.size() > 4:
		_notes.resize(4)


func show_card(title: String, lines: PackedStringArray, seconds: float = 9.0) -> void:
	_card_title = title
	_card_lines = lines
	_card_t = seconds


func flash() -> void:
	_flash = 1.0


## Fundido a negro con un texto (is_black() indica cuándo está completamente negro).
func fade_out(text: String) -> void:
	_fade_text = text
	_fade_target = 1.0


func fade_in() -> void:
	_fade_target = 0.0


func is_black() -> bool:
	return _fade > 0.995


# --- Menú rápido -----------------------------------------------------------------------------

func open_menu(items: Array) -> void:
	_menu_items = items
	_menu_sel = 0
	for i in items.size():
		if bool(items[i].get("enabled", true)):
			_menu_sel = i
			break
	_menu_open = true
	astro.input_blocked = true
	GameAudio.play("ui_open", -6.0)


func close_menu() -> void:
	if _menu_open:
		GameAudio.play("ui_back", -8.0)
	_menu_open = false
	astro.input_blocked = false


func menu_open() -> bool:
	return _menu_open


func menu_input(event: InputEvent) -> void:
	var pin := astro.pin
	if not pin.owns(event):
		return
	var up := pin.event_pressed(event, &"move_forward") or (event is InputEventJoypadButton and pin.event_pressed(event, &"recall_ship"))
	var down := pin.event_pressed(event, &"move_back") or (event is InputEventJoypadButton and pin.event_pressed(event, &"stabilize"))
	if up:
		_move(-1)
		GameAudio.play("ui_hover", -10.0)
	elif down:
		_move(1)
		GameAudio.play("ui_hover", -10.0)
	elif pin.event_pressed(event, &"jump") or pin.event_pressed(event, &"interact") \
			or (pin.uses_mouse and event is InputEventKey and event.pressed and event.keycode == KEY_ENTER):
		var it: Dictionary = _menu_items[_menu_sel]
		if bool(it.get("enabled", true)):
			close_menu()
			(it["cb"] as Callable).call()
	elif pin.event_pressed(event, &"quick_menu") or pin.event_pressed(event, &"crouch_down") \
			or (pin.uses_mouse and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		close_menu()
	else:
		return
	get_viewport().set_input_as_handled()


func _move(d: int) -> void:
	for i in _menu_items.size():
		_menu_sel = posmod(_menu_sel + d, _menu_items.size())
		if bool(_menu_items[_menu_sel].get("enabled", true)):
			return


# --- Dibujo ----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	for n in _notes:
		n["t"] -= delta
	_notes = _notes.filter(func(n): return n["t"] > 0.0)
	_card_t = maxf(0.0, _card_t - delta)
	_fade = move_toward(_fade, _fade_target, delta * 1.2)
	_flash = maxf(0.0, _flash - delta * 2.5)
	visible = not GameSettings.ui_hidden or _fade > 0.0
	_canvas.queue_redraw()


func _text(pos: Vector2, text: String, size: int, col: Color, weight := 500, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	_canvas.draw_string(UiTheme.font(weight), pos, text, align, width, size, col)


func _on_draw() -> void:
	var vp := _canvas.get_viewport_rect().size
	var s := clampf(vp.y / 720.0, 0.75, 2.0) * GameSettings.ui_scale
	# Avisos.
	var y := 150.0 * s
	for n in _notes:
		var a := clampf(float(n["t"]) / 0.5, 0.0, 1.0)
		var size := int(15 * s)
		var tw := UiTheme.font(500).get_string_size(n["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var w := tw + 36 * s
		var r := Rect2(Vector2((vp.x - w) * 0.5, y), Vector2(w, 30 * s))
		var c: Color = n["col"]
		_canvas.draw_style_box(UiTheme.glass(int(15 * s), Color(0.060, 0.060, 0.070, 0.85 * a), Color(c.r, c.g, c.b, 0.85 * a)), r)
		_text(r.position + Vector2(0, 21 * s), n["text"], size, Color(1, 1, 1, a), 500, HORIZONTAL_ALIGNMENT_CENTER, w)
		y += 36 * s
	# Ficha del escáner.
	if _card_t > 0.0 and _card_title != "":
		var a2 := clampf(_card_t / 0.6, 0.0, 1.0)
		var w2 := minf(390.0 * s, vp.x * 0.46)
		var h2 := (58.0 + _card_lines.size() * 21.0) * s
		var r2 := Rect2(Vector2(vp.x - w2 - 20 * s, vp.y * 0.24), Vector2(w2, h2))
		_canvas.draw_style_box(UiTheme.glass(int(12 * s), Color(0.057, 0.057, 0.066, 0.88 * a2), Color(A.r, A.g, A.b, 0.7 * a2), 1), r2)
		_text(r2.position + Vector2(14 * s, 26 * s), "ESCÁNER", int(11 * s), Color(A.r, A.g, A.b, a2), 700)
		_text(r2.position + Vector2(84 * s, 26 * s), _card_title, int(17 * s), Color(1, 1, 1, a2), 700)
		var ly := r2.position.y + 50 * s
		for line in _card_lines:
			_text(Vector2(r2.position.x + 14 * s, ly), line, int(13 * s), Color(0.85, 0.93, 1.0, a2), 400, HORIZONTAL_ALIGNMENT_LEFT, w2 - 24 * s)
			ly += 21 * s
	_draw_nametags(s)
	if _menu_open:
		_draw_menu(vp, s)
	if _flash > 0.0:
		_canvas.draw_rect(Rect2(Vector2.ZERO, vp), Color(1, 1, 1, _flash * 0.8))
	if _fade > 0.0:
		_canvas.draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, _fade))
		if _fade_text != "":
			_text(Vector2(0, vp.y * 0.5), _fade_text, int(20 * s), Color(0.8, 0.9, 1.0, _fade), 500, HORIZONTAL_ALIGNMENT_CENTER, vp.x)


## Etiqueta de cada compañero: nombre y distancia sobre su cabeza (o flecha en el borde si no se le ve).
func _draw_nametags(s: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for o in others:
		if not is_instance_valid(o):
			continue
		var prof: Dictionary = NetSession.profile_from_dict(o.profile) if o is RemoteAstronaut else GameSettings.profile(o.pin.slot)
		var col: Color = prof.get("accent", UiTheme.ACCENT)
		var head: Vector3 = o.global_position + o.global_transform.basis.y * 2.15
		var d := cam.global_position.distance_to(head)
		var where := ""
		if o.seated:
			where = "sentado: %s" % o.seat_id
		elif o.aboard != null:
			where = "a bordo"
		var sub := Units.format_distance(d) + ("" if where == "" else " · " + where)
		if o is RemoteAstronaut:
			var vp := Voice.is_speaking(o.peer_id)
			if vp != "":
				# Habla ahora: la etiqueta toma el color de la vía (verde cerca, azul radio, naranja nave).
				col = VoiceHud.path_color(vp)
				sub = "◉ " + VoiceHud.path_label(vp) + " · " + sub
		UiTheme.draw_world_marker(_canvas, cam, head, str(prof["name"]).to_upper(), sub, col, s * (1.0 if d > 3.0 else 0.85))


func _draw_menu(vp: Vector2, s: float) -> void:
	var row := 34.0 * s
	var w := minf(360.0 * s, vp.x * 0.8)
	var h := 56.0 * s + row * _menu_items.size() + 26 * s
	var r := Rect2(Vector2((vp.x - w) * 0.5, (vp.y - h) * 0.5), Vector2(w, h))
	_canvas.draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0.02, 0.05, 0.35))
	_canvas.draw_style_box(UiTheme.glass(int(14 * s), Color(0.051, 0.051, 0.059, 0.94), Color(A.r, A.g, A.b, 0.7), 1), r)
	_text(r.position + Vector2(18 * s, 30 * s), "MENÚ RÁPIDO", int(14 * s), A, 700)
	var y := r.position.y + 50 * s
	for i in _menu_items.size():
		var it: Dictionary = _menu_items[i]
		var en := bool(it.get("enabled", true))
		var rr := Rect2(Vector2(r.position.x + 10 * s, y), Vector2(w - 20 * s, row - 4 * s))
		if i == _menu_sel:
			_canvas.draw_rect(rr, Color(A.r, A.g, A.b, 0.16))
			_canvas.draw_rect(Rect2(rr.position, Vector2(4 * s, rr.size.y)), A)
		var col := UiTheme.TEXT if en else Color(0.5, 0.58, 0.64)
		_text(rr.position + Vector2(16 * s, 21 * s), str(it["label"]), int(16 * s), col, 600 if i == _menu_sel else 500)
		var hint := str(it.get("hint", ""))
		if hint != "":
			_text(rr.position + Vector2(0, 21 * s), hint, int(12 * s), UiTheme.TEXT_DIM, 400, HORIZONTAL_ALIGNMENT_RIGHT, rr.size.x - 10 * s)
		y += row
	var pin := astro.pin
	var foot := ("%s/%s elegir · %s aceptar · %s cerrar" % ["W", "S", "Espacio", "Y"]) if pin.uses_mouse else "Stick/cruceta elegir · A aceptar · B cerrar"
	_text(Vector2(r.position.x, r.end.y - 10 * s), foot, int(11 * s), UiTheme.TEXT_DIM, 400, HORIZONTAL_ALIGNMENT_CENTER, w)
