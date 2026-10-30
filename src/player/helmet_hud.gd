class_name HelmetHud
extends CanvasLayer
## Interfaz del casco (ADR-019), dibujada a mano con el mismo estilo que la de pilotaje (ADR-017).
## - Arriba: cinta de brújula con el rumbo de la nave marcado; avisos (caída libre, ingravidez, mareo,
##   salud crítica, sin combustible) y mensajes de la nave.
## - Abajo a la izquierda: constantes del traje (salud, combustible de los propulsores, estado).
## - Abajo a la derecha: altitud, velocidad (con la vertical), gravedad, Sol y coordenadas.
## - Marcador de la nave con distancia (flecha en el borde si está fuera de la vista).
## Sólo fuera de la nave: al subir a bordo el visor se levanta y esta interfaz desaparece.
## Se mueve un poco con la cabeza (inercia del casco) en 1ª persona.

const A := UiTheme.ACCENT
const AMB := UiTheme.AMBER

var astro: Astronaut
var sun_elevation_deg := 0.0      ## la fija el mundo
var _canvas: Control
var _t := 0.0
var _fade := 0.0
var _toast := ""
var _toast_t := 0.0
var _redraw_t := 0.0
var _fast: Control                ## brújula y marcador de la nave (cada fotograma); el resto a 10 Hz (ronda 9)
var _ci: Control


func _ready() -> void:
	layer = 6
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)
	_fast = Control.new()
	_fast.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fast.draw.connect(_on_draw_fast)
	add_child(_fast)


func _process(delta: float) -> void:
	_t += delta
	if astro == null:
		return
	var want := astro.aboard == null and not astro.seated and not GameSettings.ui_hidden \
		and not astro.frozen and astro.suit_on
	_fade = move_toward(_fade, 1.0 if want else 0.0, delta * (2.5 if want else 4.0))
	visible = _fade > 0.0
	var ship := _nearest_ship()
	if ship != null and ship.state.event_time > 0.0 and ship.state.event_text != _toast:
		_toast = ship.state.event_text
		_toast_t = 4.0
	_toast_t = maxf(0.0, _toast_t - delta)
	if visible:
		# Inercia del casco: la interfaz se retrasa un poco respecto a la vista.
		var lag := Vector2(clampf(-astro.look_rate.x * 4.0, -14.0, 14.0), clampf(astro.look_rate.y * 4.0, -10.0, 10.0))
		_canvas.position = _canvas.position.lerp(lag if astro.first_person else Vector2.ZERO, 1.0 - exp(-8.0 * delta))
		_canvas.modulate.a = _fade * (1.0 - 0.8 * astro.cam.focus_zoom)
		_fast.position = _canvas.position
		_fast.modulate.a = _canvas.modulate.a
		_fast.queue_redraw()
		# 30 redibujados por segundo bastan para cifras y brújula (dibujarla costaba ~2 ms por fotograma).
		_redraw_t -= delta
		if _redraw_t <= 0.0:
			_redraw_t = 1.0 / 10.0
			_canvas.queue_redraw()


func _nearest_ship() -> Ship:
	var best: Ship = null
	var best_d := INF
	for s in astro.ships:
		if is_instance_valid(s):
			var d: float = astro.global_position.distance_squared_to(s.global_position)
			if d < best_d:
				best_d = d
				best = s
	return best


# --- Utilidades de dibujo -------------------------------------------------------------------

func _text(pos: Vector2, text: String, size: int, color: Color = UiTheme.TEXT, weight: int = 400,
		align := HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	var f := UiTheme.font(weight)
	_ci.draw_string(f, pos + Vector2(1, 1), text, align, width, size, Color(0, 0, 0, 0.6 * color.a))
	_ci.draw_string(f, pos, text, align, width, size, color)


func _panel(r: Rect2, radius: int, border: Color = UiTheme.ACCENT_SOFT) -> void:
	_ci.draw_style_box(UiTheme.glass(radius, Color(0.057, 0.057, 0.066, 0.55), border), r)


func _bar(pos: Vector2, w: float, h: float, frac: float, color: Color) -> void:
	_ci.draw_rect(Rect2(pos, Vector2(w, h)), Color(1, 1, 1, 0.08))
	_ci.draw_rect(Rect2(pos, Vector2(w * clampf(frac, 0.0, 1.0), h)), color)
	for i in range(1, 10):
		var x := pos.x + w * i / 10.0
		_ci.draw_line(Vector2(x, pos.y), Vector2(x, pos.y + h), Color(0, 0, 0, 0.35), 1.0)


func _chip(pos: Vector2, text: String, color: Color, s: float) -> float:
	var size := int(13 * s)
	var f := UiTheme.font(600)
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 26 * s
	var pulse := 0.6 + 0.4 * sin(_t * 5.0)
	_ci.draw_style_box(UiTheme.glass(int(12 * s), Color(color.r, color.g, color.b, 0.18), Color(color.r, color.g, color.b, pulse)),
		Rect2(pos, Vector2(w, 24 * s)))
	_ci.draw_circle(pos + Vector2(11 * s, 12 * s), 3.5 * s, color)
	_ci.draw_string(f, pos + Vector2(19 * s, 17 * s), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	return w


# --- Dibujo -------------------------------------------------------------------------------

func _on_draw_fast() -> void:
	if astro == null:
		return
	_ci = _fast
	var vp := _ci.get_viewport_rect().size
	var s := clampf(vp.y / 720.0, 0.75, 2.0)
	var up := astro.position_bf().normalized().to_vector3()
	var ship := _nearest_ship()
	_draw_compass(vp, s, up, ship)
	if ship != null:
		_draw_ship_marker(vp, s, ship)
	_ci = _canvas


func _on_draw() -> void:
	if astro == null:
		return
	_ci = _canvas
	var vp := _ci.get_viewport_rect().size
	var s := clampf(vp.y / 720.0, 0.75, 2.0)
	var up := astro.position_bf().normalized().to_vector3()
	_draw_warnings(vp, s)
	_draw_vitals(vp, s)
	_draw_readouts(vp, s, up)
	_draw_toast(vp, s)


func _bearing(dir: Vector3, up: Vector3) -> float:
	var north := Vector3.UP - up * up.dot(Vector3.UP)
	if north.length_squared() < 1e-8:
		return 0.0
	north = north.normalized()
	var east := north.cross(up)
	return fposmod(rad_to_deg(atan2(dir.dot(east), dir.dot(north))), 360.0)


func _draw_compass(vp: Vector2, s: float, up: Vector3, ship: Ship) -> void:
	var w := 440.0 * s
	var h := 40.0 * s
	var r := Rect2(Vector2((vp.x - w) * 0.5, 14 * s), Vector2(w, h))
	_panel(r, int(10 * s))
	var heading := astro.heading_deg()
	var px := w / 110.0
	var cx := r.position.x + w * 0.5
	var names := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SO", 270: "O", 315: "NO"}
	var start := int(floor(heading - 55.0))
	for d in range(start, start + 111):
		if d % 5 != 0:
			continue
		var x := cx + (d - heading) * px
		if x < r.position.x + 8 * s or x > r.end.x - 8 * s:
			continue
		var dm := posmod(d, 360)
		var major := dm % 15 == 0
		_ci.draw_line(Vector2(x, r.end.y - 4 * s), Vector2(x, r.end.y - (12.0 if major else 7.0) * s), Color(1, 1, 1, 0.55 if major else 0.28), s)
		if dm % 45 == 0:
			_text(Vector2(x - 20 * s, r.position.y + 18 * s), names[dm], int(14 * s), AMB if dm == 0 else UiTheme.TEXT, 700, HORIZONTAL_ALIGNMENT_CENTER, 40 * s)
		elif dm % 15 == 0:
			_text(Vector2(x - 20 * s, r.position.y + 17 * s), "%d" % dm, int(10 * s), UiTheme.TEXT_DIM, 400, HORIZONTAL_ALIGNMENT_CENTER, 40 * s)
	# Rumbo hacia la nave (rombo ámbar en la cinta, o flecha en el extremo).
	if ship != null:
		var to := ship.global_position - astro.global_position
		to -= up * to.dot(up)
		if to.length() > 2.0:
			var delta_deg := wrapf(_bearing(to.normalized(), up) - heading, -180.0, 180.0)
			var x := cx + clampf(delta_deg, -52.0, 52.0) * px
			var y := r.position.y + 6 * s
			var d := 5.0 * s
			_ci.draw_colored_polygon(PackedVector2Array([Vector2(x, y - d * 0.2), Vector2(x + d, y + d * 0.8), Vector2(x, y + d * 1.8), Vector2(x - d, y + d * 0.8)]), AMB)
	var tri := PackedVector2Array([Vector2(cx - 6 * s, r.end.y + 8 * s), Vector2(cx + 6 * s, r.end.y + 8 * s), Vector2(cx, r.end.y + 1 * s)])
	_ci.draw_colored_polygon(tri, A)
	_text(Vector2(cx - 30 * s, r.end.y + 24 * s), "%03d°" % (int(round(heading)) % 360), int(14 * s), A, 700, HORIZONTAL_ALIGNMENT_CENTER, 60 * s)


func _draw_warnings(vp: Vector2, s: float) -> void:
	var chips: Array = []
	if astro.floating and astro.aboard == null and astro.gravity_mps2 >= Astronaut.ZERO_G:
		chips.append(["CAÍDA LIBRE", UiTheme.DANGER])
	elif astro.floating:
		chips.append(["INGRAVIDEZ", A])
	if astro.dizziness > 0.25:
		chips.append(["MAREO %d %%" % int(astro.dizziness * 100.0), AMB])
	if astro.health < 30.0:
		chips.append(["SALUD CRÍTICA", UiTheme.DANGER])
	if astro.floating and astro.jet_fuel <= 0.0:
		chips.append(["SIN COMBUSTIBLE", UiTheme.DANGER])
	var f := UiTheme.font(600)
	var total := 0.0
	for c in chips:
		total += f.get_string_size(c[0], HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * s)).x + 34 * s
	var x := (vp.x - total) * 0.5
	for c in chips:
		x += _chip(Vector2(x, 86 * s), c[0], c[1], s) + 8 * s
	if astro.floating:
		var line := "WASD · Espacio · Ctrl  propulsores      Q / E  alabeo      X  estabilizar"
		_text(Vector2(0, 132 * s), line, int(12 * s), UiTheme.TEXT_DIM, 500, HORIZONTAL_ALIGNMENT_CENTER, vp.x)


func _draw_vitals(vp: Vector2, s: float) -> void:
	var r := Rect2(Vector2(22 * s, vp.y - 128 * s), Vector2(250 * s, 106 * s))
	_panel(r, int(12 * s))
	var x := r.position.x + 14 * s
	var bw := r.size.x - 28 * s
	var hp := astro.health / 100.0
	var hp_col := UiTheme.OK.lerp(UiTheme.DANGER, clampf((0.6 - hp) / 0.4, 0.0, 1.0))
	_text(Vector2(x, r.position.y + 22 * s), "SALUD", int(11 * s), UiTheme.TEXT_DIM, 600)
	_text(Vector2(x, r.position.y + 22 * s), "%d" % int(round(astro.health)), int(13 * s), hp_col, 700, HORIZONTAL_ALIGNMENT_RIGHT, bw)
	_bar(Vector2(x, r.position.y + 28 * s), bw, 8 * s, hp, hp_col)
	_text(Vector2(x, r.position.y + 58 * s), "PROPULSORES", int(11 * s), UiTheme.TEXT_DIM, 600)
	var fuel_col := A if astro.jet_fuel > 0.2 else AMB
	_text(Vector2(x, r.position.y + 58 * s), "%d %%" % int(round(astro.jet_fuel * 100.0)), int(13 * s), fuel_col, 700, HORIZONTAL_ALIGNMENT_RIGHT, bw)
	_bar(Vector2(x, r.position.y + 64 * s), bw, 8 * s, astro.jet_fuel, fuel_col)
	var status := "Traje presurizado · soporte vital nominal"
	if astro.jet_active > 0.1:
		status = "Propulsores activos"
	elif astro.floating:
		status = "Sin apoyo · orientación libre"
	_text(Vector2(x, r.position.y + 94 * s), status, int(11 * s), UiTheme.TEXT_DIM, 400)


func _draw_readouts(vp: Vector2, s: float, up: Vector3) -> void:
	var r := Rect2(Vector2(vp.x - 272 * s, vp.y - 128 * s), Vector2(250 * s, 106 * s))
	_panel(r, int(12 * s))
	var x := r.position.x + 14 * s
	var w := r.size.x - 28 * s
	_text(Vector2(x, r.position.y + 22 * s), "ALTITUD", int(11 * s), UiTheme.TEXT_DIM, 600)
	_text(Vector2(x, r.position.y + 46 * s), Units.format_distance(astro.altitude_m), int(20 * s), UiTheme.TEXT, 700)
	var v := astro.velocity
	var vv := v.dot(up)
	_text(Vector2(x + w * 0.5, r.position.y + 22 * s), "VELOCIDAD", int(11 * s), UiTheme.TEXT_DIM, 600)
	_text(Vector2(x + w * 0.5, r.position.y + 46 * s), Units.format_speed(v.length()), int(20 * s), UiTheme.TEXT, 700)
	var vcol := UiTheme.DANGER if vv < -Astronaut.SAFE_IMPACT else UiTheme.TEXT_DIM
	_text(Vector2(x + w * 0.5, r.position.y + 64 * s), "%s %.1f m/s" % ["▲" if vv >= 0.0 else "▼", absf(vv)], int(12 * s), vcol, 600)
	var ll := CubeSphere.dir_to_latlon(astro.position_bf())
	_text(Vector2(x, r.position.y + 72 * s), "g %.2f m/s²   Sol %+.0f°" % [astro.gravity_mps2, sun_elevation_deg], int(12 * s), UiTheme.TEXT_DIM, 500)
	_text(Vector2(x, r.position.y + 94 * s), "%.4f°   %.4f°" % [ll.x, ll.y], int(11 * s), UiTheme.TEXT_DIM, 400)


func _draw_ship_marker(vp: Vector2, s: float, ship: Ship) -> void:
	var dist := astro.global_position.distance_to(ship.global_position)
	if dist < 25.0:
		return
	UiTheme.draw_world_marker(_ci, astro.get_viewport().get_camera_3d(), ship.global_transform * Vector3(0, 3.0, 0),
		"NAVE  %s" % Units.format_distance(dist), ("%s — llamar" % astro.pin.glyph(&"recall_ship")) if dist > 80.0 else "", AMB, s)


func _draw_toast(vp: Vector2, s: float) -> void:
	if _toast_t <= 0.0 or _toast == "":
		return
	var alpha := clampf(_toast_t / 0.4, 0.0, 1.0) * clampf((4.0 - _toast_t) / 0.25, 0.0, 1.0)
	var size := int(15 * s)
	var tw := UiTheme.font(500).get_string_size(_toast, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var w := tw + 40 * s
	var r := Rect2(Vector2((vp.x - w) * 0.5, vp.y - 190 * s), Vector2(w, 32 * s))
	_ci.draw_style_box(UiTheme.glass(int(16 * s), Color(0.079, 0.079, 0.092, 0.8 * alpha), Color(AMB.r, AMB.g, AMB.b, 0.8 * alpha)), r)
	_text(r.position + Vector2(0, 22 * s), _toast, size, Color(1, 0.92, 0.8, alpha), 500, HORIZONTAL_ALIGNMENT_CENTER, w)
