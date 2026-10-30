class_name PilotHud
extends CanvasLayer
## Interfaz de pilotaje dibujada a mano (ADR-017): sin texturas, escalada a la resolución.
## - Arriba: cinta de rumbo, avisos animados, estado (chips) y velocidad máxima disponible.
## - Centro: marcador del morro, vector de velocidad (hacia dónde vas realmente) y desviación del ratón.
## - Abajo: velocímetro circular (actual + objetivo), horizonte artificial, altímetro con velocidad
##   vertical y barra de acelerador; ayuda de aterrizaje cerca del suelo.
## - Ayuda de controles con teclas dibujadas (H para mostrar/ocultar).
## - Líneas de velocidad a gran velocidad y en modo lumínico.
## Fuera del asiento muestra sólo el aviso de interacción (tecla F).

const A := UiTheme.ACCENT
const AMB := UiTheme.AMBER

var astronaut: Astronaut
var _canvas: Control
var _t := 0.0
var _toast_text := ""
var _toast_t := 0.0
var _help_visible := true
var _was_seated := false
var _lines_seed: Array[float] = []
var _seated_t := 0.0
## Rendimiento (ronda 9): dos lienzos. `_fast` (retículas, horizonte, rumbo, marcadores) se redibuja cada fotograma;
## `_canvas` (paneles, textos, ayuda) a 15 Hz. Redibujarlo todo cada fotograma costaba ~14 ms en gráficos integrados.
var _fast: Control
var _fast_was := false
var _help_ci: Control
var _help_key := ""
var _ci: Control
var _slow_t := 0.0
const SLOW_HZ := 15.0


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
	_help_ci = Control.new()
	_help_ci.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_help_ci.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help_ci.draw.connect(_on_draw_help)
	add_child(_help_ci)
	_ci = _canvas
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 90:
		_lines_seed.append(rng.randf())


func _unhandled_input(event: InputEvent) -> void:
	if astronaut != null and astronaut.pin.event_pressed(event, &"toggle_controls_help") and astronaut.is_piloting():
		# H: abre la ayuda (otros 12 s) si estaba recogida; si está abierta, la recoge.
		if _seated_t > 12.0 or not _help_visible:
			_help_visible = true
			_seated_t = 0.0
		else:
			_seated_t = 12.0


func _process(delta: float) -> void:
	_t += delta
	if astronaut == null:
		return
	var seated := astronaut.is_piloting()
	if seated and not _was_seated:
		_help_visible = true
		_seated_t = 0.0
	_seated_t += delta
	_was_seated = seated
	if astronaut.aboard != null:
		var s := astronaut.aboard.state
		if s.event_time > 0.0 and s.event_text != _toast_text:
			_toast_text = s.event_text
			_toast_t = 4.0
			if astronaut.pin.slot == 0:
				GameAudio.play("beep", -12.0)
	_toast_t = maxf(0.0, _toast_t - delta)
	visible = not GameSettings.ui_hidden
	if not visible:
		return
	# La capa rápida se redibuja pilotando y una vez más al dejar de pilotar (para borrarse).
	var piloting := astronaut.is_piloting()
	if piloting or _fast_was:
		_fast.queue_redraw()
	_fast_was = piloting
	# La ayuda es casi estática: sólo se redibuja si cambia su estado (y su fundido va por la opacidad).
	var collapsed := _seated_t > 12.0
	var key := "%s|%s|%s|%s|%s" % [astronaut.is_piloting(), collapsed, astronaut.pin.uses_mouse,
		astronaut.aboard.state.arcade if astronaut.aboard != null else false, str(_help_ci.get_viewport_rect().size)]
	if key != _help_key:
		_help_key = key
		_help_ci.queue_redraw()
	_help_ci.modulate.a = 1.0 if collapsed else clampf((12.0 - _seated_t) / 0.6, 0.0, 1.0)
	_slow_t -= delta
	if _slow_t <= 0.0:
		_slow_t = 1.0 / SLOW_HZ
		_canvas.queue_redraw()


# --- Utilidades de dibujo -------------------------------------------------------------------

func _f(weight: int = 400) -> Font:
	return UiTheme.font(weight)


func _text(pos: Vector2, text: String, size: int, color: Color = UiTheme.TEXT, weight: int = 400,
		align := HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	var f := _f(weight)
	if size >= 22:
		_ci.draw_string(f, pos + Vector2(1, 1), text, align, width, size, Color(0, 0, 0, 0.6 * color.a))
	_ci.draw_string(f, pos, text, align, width, size, color)


func _panel(r: Rect2, radius: int = 12, bg: Color = UiTheme.GLASS, border: Color = UiTheme.ACCENT_SOFT) -> void:
	_ci.draw_style_box(UiTheme.glass(radius, bg, border), r)


func _chip(pos: Vector2, text: String, color: Color, s: float, filled := false) -> float:
	var size := int(13 * s)
	var f := _f(600)
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 26 * s
	var r := Rect2(pos, Vector2(w, 24 * s))
	var bg := Color(color.r, color.g, color.b, 0.22 if filled else 0.08)
	_ci.draw_style_box(UiTheme.glass(int(12 * s), bg, Color(color.r, color.g, color.b, 0.8)), r)
	_ci.draw_circle(pos + Vector2(11 * s, 12 * s), 3.5 * s, color)
	_ci.draw_string(f, pos + Vector2(19 * s, 17 * s), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	return w + 8 * s


static func _speed_parts(v: float) -> Array:
	var a := absf(v)
	if a < 1000.0:
		return ["%.0f" % v, "m/s"]
	if a < 100000.0:
		return ["%.1f" % (v / 1000.0), "km/s"]
	return ["%.0f" % (v / 1000.0), "km/s"]


static func _log_frac(v: float, maxs: float) -> float:
	if maxs <= 1.0:
		return 0.0
	return clampf(log(1.0 + absf(v)) / log(1.0 + maxs), 0.0, 1.0)


# --- Dibujo principal ---------------------------------------------------------------------

func _on_draw_help() -> void:
	if astronaut == null or not astronaut.is_piloting():
		return
	_ci = _help_ci
	var vp := _help_ci.get_viewport_rect().size
	var s := clampf(vp.y / 720.0, 0.75, 2.0)
	_draw_help(vp, s, astronaut.aboard.state.arcade)
	_ci = _canvas


## Capa rápida: lo que se mueve con la nave o la cámara.
func _on_draw_fast() -> void:
	if astronaut == null or not astronaut.is_piloting():
		return
	_ci = _fast
	var vp := _fast.get_viewport_rect().size
	var s := clampf(vp.y / 720.0, 0.75, 2.0)
	var ship := astronaut.aboard
	var st := ship.state
	var cam := astronaut.view.active_camera() as Camera3D
	var radial := st.pos_bf.normalized().to_vector3()
	_draw_speed_lines(vp, s, st)
	_draw_reticles(vp, s, ship, cam)
	_draw_heading(vp, s, ship, radial)
	var w := 720.0 * s
	var h := 176.0 * s
	var r := Rect2(Vector2((vp.x - w) * 0.5, vp.y - h - 14 * s), Vector2(w, h))
	_draw_attitude(r.position + Vector2(w * 0.5, 84 * s), 62.0 * s, s, st, radial)
	_draw_travel(vp, s, ship, cam)
	var pm := PlanetMarker.nearest(astronaut)
	if not pm.is_empty():
		UiTheme.draw_world_marker(_ci, cam, pm["center"], pm["name"], pm["sub"], UiTheme.DATA, s, true)
	_ci = _canvas


func _on_draw() -> void:
	if astronaut == null:
		return
	_ci = _canvas
	var vp := _ci.get_viewport_rect().size
	var s := clampf(vp.y / 720.0, 0.75, 2.0)
	if not astronaut.is_piloting():
		_draw_interaction(vp, s)
		if astronaut.aboard != null:
			var ag := astronaut.aboard.state.artificial_gravity
			_text(Vector2(0, vp.y - 46 * s), "Gravedad artificial: %s · la controla el piloto" % ("ACTIVADA" if ag else "desactivada (gravedad real)"),
				int(13 * s), A if ag else UiTheme.TEXT_DIM, 600, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
			_draw_toast(vp, s)
		if astronaut.seated:
			var pn := astronaut.pin
			var look := "Ratón" if pn.uses_mouse else "Stick der."
			_text(Vector2(0, vp.y - 24 * s), "%s mirar alrededor · %s música · %s cámara · %s levantarse" % [look,
				pn.glyph(&"music_panel"), pn.glyph(&"toggle_camera"), pn.glyph(&"interact")], int(13 * s), UiTheme.TEXT_DIM, 500,
				HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		return
	var ship := astronaut.aboard
	var radial := ship.state.pos_bf.normalized().to_vector3()
	_draw_status(vp, s, ship)
	_draw_cluster(vp, s, ship, radial)
	_draw_landing(vp, s, ship)
	_draw_environment(vp, s, ship)
	_draw_toast(vp, s)


func _draw_interaction(vp: Vector2, s: float) -> void:
	var hint := astronaut.interaction_hint
	if hint == "":
		return
	var label := hint
	var size := int(18 * s)
	var tw := _f(500).get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var w := tw + 80 * s
	var r := Rect2(Vector2((vp.x - w) * 0.5, vp.y - 120 * s), Vector2(w, 46 * s))
	var pulse := 0.55 + 0.25 * sin(_t * 3.0)
	_panel(r, int(23 * s), UiTheme.GLASS_STRONG, Color(A.r, A.g, A.b, pulse))
	var kw := UiTheme.draw_keycap(_ci, r.position + Vector2(14 * s, 9 * s), astronaut.pin.glyph(&"interact"), int(16 * s))
	_text(r.position + Vector2(maxf(54 * s, kw + 26 * s), 30 * s), label, size, UiTheme.TEXT, 500)


## Líneas de velocidad radiales (sensación de velocidad) por encima de 2 km/s y en modo lumínico.
func _draw_speed_lines(vp: Vector2, s: float, st: ShipState) -> void:
	var v := st.speed()
	var k := clampf(log(maxf(v, 1.0) / 2000.0) / log(10.0) / 3.0, 0.0, 1.0)
	if st.light_active:
		k = 1.0
	if k <= 0.0:
		return
	var c := vp * 0.5
	var maxr := vp.length() * 0.6
	for i in _lines_seed.size():
		var ang := _lines_seed[i] * TAU
		var ph := fposmod(_lines_seed[(i * 7) % _lines_seed.size()] + _t * (0.6 + 1.8 * k), 1.0)
		var r0 := lerpf(80.0 * s, maxr, ph)
		var r1 := r0 + (40.0 + 220.0 * k) * s * ph
		var dir := Vector2(cos(ang), sin(ang))
		var col := Color(0.8, 0.85, 1.0, 0.45 * ph) if st.light_active else Color(0.75, 0.9, 1.0, 0.25 * k * ph)
		_ci.draw_line(c + dir * r0, c + dir * r1, col, 1.5 * s)
	if st.light_active:
		_text(Vector2(0, vp.y * 0.30), "MOTOR LUMÍNICO ACTIVO", int(26 * s), Color(0.8, 0.88, 1.0, 0.9), 700, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		_text(Vector2(0, vp.y * 0.30 + 24 * s), "modelo abstracto, no relativista", int(14 * s), UiTheme.TEXT_DIM, 400, HORIZONTAL_ALIGNMENT_CENTER, vp.x)


## Morro de la nave, vector de velocidad y desviación del ratón.
func _draw_reticles(vp: Vector2, s: float, ship: Ship, cam: Camera3D) -> void:
	var st := ship.state
	var c := vp * 0.5
	var nose_pt := ship.global_position + st.forward() * 5000.0
	if cam != null and not cam.is_position_behind(nose_pt):
		var p := cam.unproject_position(nose_pt)
		_ci.draw_arc(p, 12 * s, 0, TAU, 32, A, 2.0 * s, true)
		_ci.draw_line(p + Vector2(-28 * s, 0), p + Vector2(-14 * s, 0), A, 2.0 * s)
		_ci.draw_line(p + Vector2(14 * s, 0), p + Vector2(28 * s, 0), A, 2.0 * s)
		_ci.draw_line(p + Vector2(0, -12 * s), p + Vector2(0, -20 * s), A, 2.0 * s)
	if st.speed() > 1.0 and cam != null:
		var vel_pt := ship.global_position + st.velocity.normalized() * 5000.0
		if not cam.is_position_behind(vel_pt):
			var q := cam.unproject_position(vel_pt)
			var col := Color(0.4, 1.0, 0.6, 0.95)
			_ci.draw_arc(q, 7 * s, 0, TAU, 24, col, 2.0 * s, true)
			for a: float in [0.0, PI * 0.5, PI]:
				var d := Vector2(cos(a + PI), sin(a + PI))
				_ci.draw_line(q + d * 7 * s, q + d * 15 * s, col, 2.0 * s)
	var stick := astronaut.pilot_input.stick
	if stick.length() > 0.02:
		var sp := c + stick * 110.0 * s
		_ci.draw_line(c, sp, Color(AMB.r, AMB.g, AMB.b, 0.5), 1.5 * s)
		_ci.draw_circle(sp, 4 * s, AMB)


func _draw_heading(vp: Vector2, s: float, ship: Ship, radial: Vector3) -> void:
	var w := 520.0 * s
	var h := 46.0 * s
	var r := Rect2(Vector2((vp.x - w) * 0.5, 14 * s), Vector2(w, h))
	_panel(r, int(10 * s))
	var north := (Vector3.UP - radial * radial.dot(Vector3.UP)).normalized()
	var east := north.cross(radial)
	var fwd := ship.state.forward() - radial * ship.state.forward().dot(radial)
	var heading := 0.0
	if fwd.length_squared() > 1e-6:
		heading = fposmod(rad_to_deg(atan2(fwd.dot(east), fwd.dot(north))), 360.0)
	var px_per_deg := w / 120.0
	var cx := r.position.x + w * 0.5
	var names := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SO", 270: "O", 315: "NO"}
	var start := int(floor(heading - 60.0))
	for d in range(start, start + 121):
		if d % 5 != 0:
			continue
		var x := cx + (d - heading) * px_per_deg
		if x < r.position.x + 8 * s or x > r.end.x - 8 * s:
			continue
		var dm := posmod(d, 360)
		var major := dm % 15 == 0
		_ci.draw_line(Vector2(x, r.end.y - 4 * s), Vector2(x, r.end.y - (14.0 if major else 8.0) * s), Color(1, 1, 1, 0.55 if major else 0.3), 1.0 * s)
		if dm % 45 == 0:
			_text(Vector2(x - 20 * s, r.position.y + 20 * s), names[dm], int(15 * s), AMB if dm == 0 else UiTheme.TEXT, 700, HORIZONTAL_ALIGNMENT_CENTER, 40 * s)
		elif dm % 15 == 0:
			_text(Vector2(x - 20 * s, r.position.y + 19 * s), "%d" % dm, int(11 * s), UiTheme.TEXT_DIM, 400, HORIZONTAL_ALIGNMENT_CENTER, 40 * s)
	var tri := PackedVector2Array([Vector2(cx - 7 * s, r.end.y + 9 * s), Vector2(cx + 7 * s, r.end.y + 9 * s), Vector2(cx, r.end.y + 1 * s)])
	_ci.draw_colored_polygon(tri, A)
	_text(Vector2(cx - 30 * s, r.end.y + 26 * s), "%03d°" % (int(round(heading)) % 360), int(15 * s), A, 700, HORIZONTAL_ALIGNMENT_CENTER, 60 * s)


func _draw_status(vp: Vector2, s: float, ship: Ship) -> void:
	var st := ship.state
	var pos := Vector2(20 * s, 18 * s)
	pos.x += _chip(pos, "ARCADE" if st.arcade else "SIMULACIÓN", A, s, true)
	if st.autopilot != ShipState.Autopilot.OFF:
		var ap_names := {ShipState.Autopilot.HOLD: "PILOTO AUTO", ShipState.Autopilot.APPROACH: "APROXIMACIÓN Y ATERRIZAJE",
			ShipState.Autopilot.RECALL: "LLAMADA"}
		pos.x += _chip(pos, ap_names.get(st.autopilot, "PILOTO AUTO"), UiTheme.OK, s, true)
	if st.artificial_gravity:
		pos.x += _chip(pos, "GRAVEDAD ART.", A, s)
	if st.warp > 1.01:
		pos.x += _chip(pos, "SALTO %.0f c (ficticio)" % st.warp, AMB, s, true)
	if st.atmo_speed_limit < 1.0e8 and st.speed_cap <= st.atmo_speed_limit + 1.0:
		pos.x += _chip(pos, "LIMITADOR ATMOSFÉRICO", AMB, s)
	if st.plasma > 0.05:
		pos.x += _chip(pos, "PLASMA DE ENTRADA", UiTheme.DANGER, s, true)
	if st.ext_pressure > Ship.HULL_PRESSURE_LIMIT * 0.7:
		pos.x += _chip(pos, "PRESIÓN EXTREMA", AMB, s)
	if st.hull_temperature > Ship.HULL_TEMP_LIMIT * 0.7:
		pos.x += _chip(pos, "SOBRECALENTAMIENTO", UiTheme.DANGER, s, true)
	if st.landed:
		pos.x += _chip(pos, "POSADA", UiTheme.OK, s)
	elif st.gear_deployed:
		pos.x += _chip(pos, "TREN FUERA", AMB, s)
	if st.braking:
		pos.x += _chip(pos, "FRENANDO", UiTheme.DANGER, s, true)
	if ship.controls.boost:
		pos.x += _chip(pos, "TURBO", AMB, s, true)
	if not st.flight_assist:
		pos.x += _chip(pos, "SIN ASISTENCIA", UiTheme.DANGER, s)
	if ship.params.is_light(st.regime) and not st.light_active:
		var spool := float(ship.params.regime(st.regime).get("spool_s", 3.0))
		pos.x += _chip(pos, "CARGANDO LUMÍNICO %.1f s" % maxf(0.0, spool - st.light_spool), AMB, s, true)
	# Derecha: velocidad máxima disponible / régimen.
	var rw := 300.0 * s
	var r := Rect2(Vector2(vp.x - rw - 20 * s, 14 * s), Vector2(rw, 62 * s))
	_panel(r, int(10 * s))
	if st.arcade and not ship.params.is_light(st.regime):
		_text(r.position + Vector2(14 * s, 22 * s), "VELOCIDAD MÁXIMA AQUÍ", int(11 * s), UiTheme.TEXT_DIM, 600)
		_text(r.position + Vector2(14 * s, 47 * s), ShipParams.format_speed(st.speed_cap), int(20 * s), UiTheme.TEXT, 700)
		_text(r.position + Vector2(rw - 154 * s, 47 * s), "sube para ir más rápido", int(11 * s), UiTheme.TEXT_DIM, 400, HORIZONTAL_ALIGNMENT_RIGHT, 140 * s)
	else:
		_text(r.position + Vector2(14 * s, 22 * s), "RÉGIMEN %d / %d" % [st.regime + 1, ship.params.regimes.size()], int(11 * s), UiTheme.TEXT_DIM, 600)
		_text(r.position + Vector2(14 * s, 47 * s), str(ship.params.regime(st.regime).get("name", "")), int(16 * s), UiTheme.TEXT, 700)


## Panel inferior: velocímetro, horizonte artificial, altímetro y acelerador.
func _draw_cluster(vp: Vector2, s: float, ship: Ship, radial: Vector3) -> void:
	var st := ship.state
	var w := 720.0 * s
	var h := 176.0 * s
	var r := Rect2(Vector2((vp.x - w) * 0.5, vp.y - h - 14 * s), Vector2(w, h))
	_panel(r, int(18 * s))
	var cap := st.speed_cap
	# Velocímetro.
	var gc := r.position + Vector2(118 * s, 92 * s)
	var gr := 66.0 * s
	var a0 := deg_to_rad(135.0)
	var span := deg_to_rad(270.0)
	_ci.draw_arc(gc, gr, a0, a0 + span, 64, Color(1, 1, 1, 0.12), 9 * s, true)
	var fcur := _log_frac(st.forward_speed(), cap)
	var col := A if st.forward_speed() >= 0.0 else AMB
	if fcur > 0.002:
		_ci.draw_arc(gc, gr, a0, a0 + span * fcur, 64, col, 9 * s, true)
	var ftg := _log_frac(st.target_speed, cap)
	var ta := a0 + span * ftg
	var td := Vector2(cos(ta), sin(ta))
	_ci.draw_line(gc + td * (gr - 14 * s), gc + td * (gr + 10 * s), AMB, 3 * s)
	var parts := _speed_parts(st.speed())
	_text(gc + Vector2(-60 * s, 8 * s), parts[0], int(34 * s), UiTheme.TEXT, 700, HORIZONTAL_ALIGNMENT_CENTER, 120 * s)
	_text(gc + Vector2(-60 * s, 28 * s), parts[1], int(13 * s), UiTheme.TEXT_DIM, 600, HORIZONTAL_ALIGNMENT_CENTER, 120 * s)
	var tparts := _speed_parts(st.target_speed)
	_text(gc + Vector2(-70 * s, 62 * s), "OBJETIVO %s %s" % [tparts[0], tparts[1]], int(12 * s), AMB, 600, HORIZONTAL_ALIGNMENT_CENTER, 140 * s)
	if st.speed() >= ShipParams.C * 0.0005:
		_text(gc + Vector2(-60 * s, -24 * s), "%.4f c" % (st.speed() / ShipParams.C), int(12 * s), Color(0.8, 0.85, 1.0), 600, HORIZONTAL_ALIGNMENT_CENTER, 120 * s)
	# (El horizonte artificial se dibuja en la capa rápida.)
	# Altímetro y velocidad vertical.
	var ax := r.position.x + w - 250 * s
	_text(Vector2(ax, r.position.y + 32 * s), "ALTITUD", int(11 * s), UiTheme.TEXT_DIM, 600)
	_text(Vector2(ax, r.position.y + 66 * s), Units.format_distance(ship.radar_altitude), int(26 * s), UiTheme.TEXT, 700)
	var vs := ship.vertical_speed
	var vs_col := UiTheme.OK if absf(vs) < 3.0 else (AMB if absf(vs) < 15.0 else UiTheme.TEXT)
	var arrow := "SUBE " if vs > 0.2 else ("BAJA " if vs < -0.2 else "")
	_text(Vector2(ax, r.position.y + 96 * s), "VERTICAL  %s%s" % [arrow, ShipParams.format_speed(absf(vs))], int(13 * s), vs_col, 600)
	_text(Vector2(ax, r.position.y + 122 * s), "GRAVEDAD  %.2f m/s²" % ship.gravity_vector().length(), int(12 * s), UiTheme.TEXT_DIM, 400)
	_text(Vector2(ax, r.position.y + 144 * s), "MOTOR  %d %%" % int(st.engine_output * 100.0), int(12 * s), UiTheme.TEXT_DIM, 400)
	# Barra del acelerador (velocidad objetivo vs. actual).
	var bx := r.end.x - 52 * s
	var br := Rect2(Vector2(bx, r.position.y + 22 * s), Vector2(16 * s, h - 50 * s))
	_ci.draw_style_box(UiTheme.glass(int(6 * s), Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.2)), br)
	var fh := br.size.y * fcur
	_ci.draw_rect(Rect2(Vector2(br.position.x + 3 * s, br.end.y - fh), Vector2(br.size.x - 6 * s, fh)), Color(col.r, col.g, col.b, 0.85))
	var ty := br.end.y - br.size.y * ftg
	_ci.draw_rect(Rect2(Vector2(br.position.x - 7 * s, ty - 2 * s), Vector2(br.size.x + 14 * s, 4 * s)), AMB)
	_text(Vector2(br.position.x - 20 * s, br.end.y + 18 * s), "ACEL.", int(10 * s), UiTheme.TEXT_DIM, 600, HORIZONTAL_ALIGNMENT_CENTER, 56 * s)


## Horizonte artificial respecto a la vertical local del cuerpo.
func _draw_attitude(c: Vector2, rad: float, s: float, st: ShipState, radial: Vector3) -> void:
	var fwd := st.forward()
	var pitch := asin(clampf(fwd.dot(radial), -1.0, 1.0))
	var bank := atan2(st.basis.x.dot(radial), st.basis.y.dot(radial))  # > 0: ala derecha alta
	var pts := PackedVector2Array()
	for i in 48:
		var a := TAU * float(i) / 48.0
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	_ci.draw_colored_polygon(pts, Color(0.12, 0.35, 0.55, 0.85))
	# La línea del horizonte se desplaza con el cabeceo y gira con el alabeo (como en un avión).
	var px_per_rad := rad / deg_to_rad(40.0)
	var n := Vector2(sin(bank), -cos(bank))  # normal "hacia el cielo" en pantalla
	var off := pitch * px_per_rad
	var hp := c - n * off  # morro arriba → el horizonte baja
	var ground := _clip_halfplane(pts, hp, n)
	if ground.size() >= 3:
		_ci.draw_colored_polygon(ground, Color(0.42, 0.3, 0.2, 0.9))
	var tangent := Vector2(-n.y, n.x)  # ala derecha alta → el extremo derecho del horizonte baja
	_ci.draw_line(hp - tangent * rad * 0.98, hp + tangent * rad * 0.98, Color(1, 1, 1, 0.9), 2.0 * s)
	for deg: int in [-20, -10, 10, 20]:
		var lp := hp + n * (deg_to_rad(float(deg)) * px_per_rad)
		var half := (14.0 if absi(deg) == 10 else 22.0) * s
		if lp.distance_to(c) < rad - 8 * s:
			_ci.draw_line(lp - tangent * half, lp + tangent * half, Color(1, 1, 1, 0.5), 1.0 * s)
	_ci.draw_arc(c, rad, 0, TAU, 48, UiTheme.ACCENT_SOFT, 2.0 * s, true)
	# Símbolo fijo de la nave.
	_ci.draw_line(c + Vector2(-34 * s, 0), c + Vector2(-10 * s, 0), AMB, 3 * s)
	_ci.draw_line(c + Vector2(10 * s, 0), c + Vector2(34 * s, 0), AMB, 3 * s)
	_ci.draw_circle(c, 3 * s, AMB)
	_text(c + Vector2(-110 * s, rad + 20 * s), "CABECEO %+.0f°   ALABEO %+.0f°" % [rad_to_deg(pitch), rad_to_deg(bank)], int(11 * s), UiTheme.TEXT_DIM, 600, HORIZONTAL_ALIGNMENT_CENTER, 220 * s)


## Recorte de un polígono convexo: se conserva la parte del lado opuesto a `n` (suelo).
static func _clip_halfplane(poly: PackedVector2Array, p0: Vector2, n: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var da := (a - p0).dot(n)
		var db := (b - p0).dot(n)
		if da <= 0.0:
			out.append(a)
		if (da < 0.0 and db > 0.0) or (da > 0.0 and db < 0.0):
			out.append(a + (b - a) * (da / (da - db)))
	return out


func _draw_landing(vp: Vector2, s: float, ship: Ship) -> void:
	var st := ship.state
	if st.landed or ship.radar_altitude > 60.0 or ship.vertical_speed > -0.2:
		return
	var vs := absf(ship.vertical_speed)
	var col := UiTheme.OK if vs <= 3.0 else (AMB if vs <= 6.0 else UiTheme.DANGER)
	var w := 280.0 * s
	var r := Rect2(Vector2((vp.x - w) * 0.5, vp.y * 0.6), Vector2(w, 52 * s))
	_panel(r, int(10 * s), UiTheme.GLASS_STRONG, Color(col.r, col.g, col.b, 0.8))
	_text(r.position + Vector2(0, 21 * s), "ATERRIZAJE" if st.gear_deployed else "¡TREN DENTRO!", int(13 * s), col, 700, HORIZONTAL_ALIGNMENT_CENTER, w)
	_text(r.position + Vector2(0, 41 * s), "descenso %.1f m/s · seguro ≤ 3 m/s" % vs, int(12 * s), UiTheme.TEXT, 500, HORIZONTAL_ALIGNMENT_CENTER, w)


## Panel de entorno (ADR-029): sólo cuando hay atmósfera, calor o daños.
func _draw_environment(vp: Vector2, s: float, ship: Ship) -> void:
	var st := ship.state
	if st.ext_pressure < 1.0 and st.hull_integrity >= 99.9 and st.hull_temperature < 500.0:
		return
	var r := Rect2(Vector2(vp.x - 300 * s, 90 * s), Vector2(280 * s, 150 * s))
	_panel(r, int(10 * s))
	var x := r.position.x + 14 * s
	var y := r.position.y + 24 * s
	_text(Vector2(x, y), "ENTORNO", int(11 * s), UiTheme.TEXT_DIM, 600)
	var p_bar := st.ext_pressure / 1.0e5
	var p_txt := ("%.2f bar" % p_bar) if p_bar >= 0.01 else ("%.1f Pa" % st.ext_pressure)
	var p_col := UiTheme.DANGER if st.ext_pressure > Ship.HULL_PRESSURE_LIMIT * 0.7 else UiTheme.TEXT
	_text(Vector2(x, y + 24 * s), "Presión  %s" % p_txt, int(14 * s), p_col, 600)
	_text(Vector2(x, y + 44 * s), "Temperatura  %.0f K (%.0f °C)" % [st.ext_temperature, st.ext_temperature - 273.15], int(13 * s), UiTheme.TEXT, 500)
	_text(Vector2(x, y + 63 * s), "Viento  %.0f m/s (%.0f km/h)" % [absf(st.wind_speed), absf(st.wind_speed) * 3.6], int(13 * s), UiTheme.TEXT, 500)
	var hc := UiTheme.OK.lerp(UiTheme.DANGER, clampf((80.0 - st.hull_integrity) / 60.0, 0.0, 1.0))
	_text(Vector2(x, y + 85 * s), "CASCO  %.0f %%" % st.hull_integrity, int(14 * s), hc, 700)
	var tc := UiTheme.DANGER if st.hull_temperature > Ship.HULL_TEMP_LIMIT * 0.7 else UiTheme.TEXT_DIM
	_text(Vector2(x + 120 * s, y + 85 * s), "piel %.0f K" % st.hull_temperature, int(13 * s), tc, 600)
	_ci.draw_rect(Rect2(Vector2(x, y + 94 * s), Vector2(250 * s, 7 * s)), Color(1, 1, 1, 0.08))
	_ci.draw_rect(Rect2(Vector2(x, y + 94 * s), Vector2(250 * s * st.hull_integrity / 100.0, 7 * s)), hc)
	_text(Vector2(x, y + 116 * s), "Casco reforzado (ficticio): sólo el Sol lo daña", int(11 * s), UiTheme.TEXT_DIM, 400)


## Viaje en curso: destino, distancia y marcador en pantalla.
func _draw_travel(vp: Vector2, s: float, ship: Ship, cam: Camera3D) -> void:
	var world: Node = astronaut.world
	var target: String = ship.state.travel_target if ship.state.autopilot == ShipState.Autopilot.TRAVEL else str(world.get("nav_target"))
	if target == "" or ship.system == null or not ship.system.has_body(target):
		return
	var b: BodyDef = ship.system.body(target)
	var rel := ship.system.position_in_frame(target, ship.body_def.id).sub(ship.state.pos_bf)
	var d := rel.length() - b.radius_m()
	var to := cam.global_position + rel.mul(1.0 / maxf(rel.length(), 1.0)).to_vector3() * 1000.0
	UiTheme.draw_world_marker(_ci, cam, to, "DESTINO: %s" % b.display_name.to_upper(), Units.format_distance(maxf(d, 0.0)),
		Color(0.45, 1.0, 0.6), s, true)


func _draw_toast(vp: Vector2, s: float) -> void:
	if _toast_t <= 0.0 or _toast_text == "":
		return
	var appear := clampf((4.0 - _toast_t) / 0.25, 0.0, 1.0)
	var alpha := clampf(_toast_t / 0.4, 0.0, 1.0) * appear
	var size := int(16 * s)
	var tw := _f(500).get_string_size(_toast_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var w := tw + 40 * s
	var y := 100 * s - (1.0 - appear) * 10 * s
	var r := Rect2(Vector2((vp.x - w) * 0.5, y), Vector2(w, 34 * s))
	_ci.draw_style_box(UiTheme.glass(int(17 * s), Color(0.079, 0.079, 0.092, 0.85 * alpha), Color(AMB.r, AMB.g, AMB.b, 0.8 * alpha)), r)
	_text(r.position + Vector2(0, 23 * s), _toast_text, size, Color(1, 0.92, 0.8, alpha), 500, HORIZONTAL_ALIGNMENT_CENTER, w)


func _draw_help(vp: Vector2, s: float, arcade: bool) -> void:
	# Ayuda de pilotaje (ronda 8): compacta, en grupos y dos columnas; se recoge sola a los 12 s.
	var pn := astronaut.pin
	var g := func(a: StringName) -> String: return pn.glyph(a)
	var groups: Array
	if not pn.uses_mouse:
		groups = [["VUELO", [[["RT", "LT"], "Acelerar / frenar"], [["Stick der."], "Apuntar"], [["Stick izq."], "Girar"],
				[["A", "B"], "Subir / bajar"], [["LB", "RB"], "Alabeo"], [["L3"], "Turbo"], [["▼"], "Parar en seco"]]],
			["SISTEMAS", [[["◀"], "Piloto automático"], [["▲"], "Motor lumínico"], [["▶"], "Escanear"], [["Select"], "Menú rápido"]]],
			["CABINA", [[["Y"], "Vista exterior"], [["R3"], "Mirar alrededor"], [["X"], "Levantarse"]]]]
	elif arcade:
		groups = [["VUELO", [[[g.call(&"ship_throttle_up"), g.call(&"ship_throttle_down")], "Acelerar / frenar"], [["Ratón"], "Apuntar la nave"],
				[[g.call(&"ship_strafe_left"), g.call(&"ship_strafe_right")], "Girar"], [[g.call(&"ship_up"), g.call(&"ship_down")], "Subir / bajar"],
				[[g.call(&"ship_roll_left"), g.call(&"ship_roll_right")], "Alabeo"], [[g.call(&"ship_boost")], "Turbo"],
				[[g.call(&"ship_stop")], "Parar en seco"]]],
			["SISTEMAS", [[[g.call(&"ship_autopilot")], "Piloto automático"], [[g.call(&"ship_approach")], "Aterrizaje automático"],
				[[g.call(&"ship_light")], "Motor lumínico"], [[g.call(&"ship_gravity")], "Gravedad artificial"],
				[[g.call(&"ship_floodlights")], "Focos"], [[g.call(&"ship_gear")], "Tren de aterrizaje"], [[g.call(&"scan")], "Escanear"]]],
			["CABINA", [[[g.call(&"toggle_camera")], "Vista exterior"], [["Clic der."], "Mirar alrededor"], [[g.call(&"toggle_map")], "Mapa"],
				[[g.call(&"music_panel")], "Música"], [[g.call(&"quick_menu")], "Menú rápido"], [[g.call(&"interact")], "Levantarse"]]]]
	else:
		groups = [["VUELO", [[[g.call(&"ship_throttle_up"), g.call(&"ship_throttle_down")], "Velocidad objetivo"], [["Ratón"], "Palanca virtual"],
				[[g.call(&"ship_strafe_left"), g.call(&"ship_strafe_right")], "Lateral"], [[g.call(&"ship_up"), g.call(&"ship_down")], "Subir / bajar"],
				[[g.call(&"ship_roll_left"), g.call(&"ship_roll_right")], "Alabeo"], [["1–5"], "Régimen"], [[g.call(&"ship_stop")], "Parar en seco"]]],
			["SISTEMAS", [[[g.call(&"ship_assist")], "Asistencia"], [[g.call(&"ship_autopilot")], "Piloto automático"],
				[[g.call(&"ship_approach")], "Aterrizaje automático"], [[g.call(&"ship_gravity")], "Gravedad artificial"], [[g.call(&"scan")], "Escanear"]]],
			["CABINA", [[[g.call(&"toggle_camera")], "Vista exterior"], [["Clic der."], "Mirar alrededor"], [[g.call(&"toggle_map")], "Mapa"],
				[[g.call(&"quick_menu")], "Menú rápido"], [[g.call(&"interact")], "Levantarse"]]]]
	if _seated_t > 12.0:
		# Recogida: una pestaña discreta para volver a abrirla.
		var tab := Rect2(Vector2(20 * s, 54 * s), Vector2(150 * s, 30 * s))
		_panel(tab, int(8 * s), UiTheme.GLASS, UiTheme.ACCENT_SOFT)
		var kw := UiTheme.draw_keycap(_ci, tab.position + Vector2(8 * s, 5 * s), pn.glyph(&"toggle_controls_help"), int(11 * s))
		_text(tab.position + Vector2(kw + 16 * s, 20 * s), "Controles", int(12 * s), UiTheme.TEXT_DIM, 500)
		return
	var fade := 1.0
	var row_h := 22.0 * s
	var col_w := 246.0 * s
	var pad := 12.0 * s
	# Reparto en dos columnas: VUELO a la izquierda; SISTEMAS y CABINA a la derecha.
	var left: Array = groups[0][1]
	var right_rows := 0
	for gi in range(1, groups.size()):
		right_rows += (groups[gi][1] as Array).size() + 1
	var rows := maxi(left.size() + 1, right_rows)
	var r := Rect2(Vector2(20 * s, 54 * s), Vector2(col_w * 2.0 + pad * 2.0, rows * row_h + pad * 2.0 + 18 * s))
	_panel(r, int(10 * s), Color(UiTheme.GLASS.r, UiTheme.GLASS.g, UiTheme.GLASS.b, 0.78 * fade), Color(A.r, A.g, A.b, 0.35 * fade))
	_ci.draw_rect(Rect2(r.position + Vector2(0, 2 * s), Vector2(3 * s, r.size.y - 4 * s)), Color(A.r, A.g, A.b, fade))
	_text(r.position + Vector2(pad, 20 * s), "CONTROLES DE PILOTAJE", int(11 * s), Color(A.r, A.g, A.b, fade), 700)
	_text(r.position + Vector2(0, 20 * s), "%s ocultar" % pn.glyph(&"toggle_controls_help"), int(10 * s), Color(1, 1, 1, 0.45 * fade), 500,
		HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - pad)
	var cols := [[groups[0]], groups.slice(1)]
	for ci in 2:
		var y := r.position.y + 30 * s
		var x0 := r.position.x + pad + ci * col_w
		for grp in cols[ci]:
			_text(Vector2(x0, y + 14 * s), grp[0], int(10 * s), Color(UiTheme.AMBER.r, UiTheme.AMBER.g, UiTheme.AMBER.b, 0.9 * fade), 700)
			y += row_h
			for row in grp[1]:
				var x := x0
				for key in row[0]:
					x += UiTheme.draw_keycap(_ci, Vector2(x, y), str(key), int(10 * s)) + 3 * s
				_text(Vector2(x0 + 104 * s, y + 13 * s), row[1], int(12 * s), Color(UiTheme.TEXT.r, UiTheme.TEXT.g, UiTheme.TEXT.b, fade), 400)
				y += row_h

