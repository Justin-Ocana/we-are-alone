class_name MapPanel
extends CanvasLayer
## Mapa del Sistema Solar (Tab, ADR-028/031).
## - Vista SISTEMA: órbitas reales (elipses muestreadas con las efemérides) vistas desde el norte de la eclíptica,
##   escala radial logarítmica (a escala lineal Mercurio y Neptuno no caben juntos), posiciones de hoy.
## - Vista LUNAS: el planeta elegido con las órbitas de sus lunas a escala lineal.
## - Rueda: zoom · arrastrar (clic derecho o central): desplazar · clic: elegir · doble clic: ver sus lunas.
## - Panel: buscador, lista de planetas y lunas, ficha completa del cuerpo, tiempo estimado de viaje,
##   botones de destino y de viaje (piloto automático; sólo pilotando).

const A := UiTheme.ACCENT
const AMB := UiTheme.AMBER
const GREEN := Color(0.45, 1.0, 0.6)
const LOG_REF_AU := 0.25
const MAX_AU := 50.0
const ORBIT_SAMPLES := 96

var world: SurfaceWorld
var _open := false
var _root: Control
var _diagram: Control
var _search: LineEdit
var _list: ItemList
var _info: RichTextLabel
var _go: Button
var _mark: Button
var _view_btn: Button
var _list_ids: Array = []
var _selected := ""
var _focus_planet := ""          ## "" = vista sistema; id = vista de lunas de ese planeta
var _zoom := 1.0
var _pan := Vector2.ZERO
var _dragging := false
var _hover := ""
var _orbits := {}                ## id -> PackedVector3Array (posiciones relativas al padre, en m)
var _orbit_time := INF


func _ready() -> void:
	layer = 14
	visible = false
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiTheme.build()
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(0.016, 0.016, 0.019, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	_diagram = Control.new()
	_diagram.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_diagram.anchor_right = 0.64
	_diagram.clip_contents = true
	_diagram.draw.connect(_draw_diagram)
	_diagram.gui_input.connect(_on_diagram_input)
	_root.add_child(_diagram)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.645
	panel.anchor_right = 0.99
	panel.anchor_top = 0.02
	panel.anchor_bottom = 0.98
	_root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	panel.add_child(box)
	var title := Label.new()
	title.text = "MAPA DEL SISTEMA SOLAR"
	title.add_theme_color_override("font_color", A)
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	_search = LineEdit.new()
	_search.placeholder_text = "Buscar cuerpo (p. ej. Titán, Europa, Fobos…)"
	_search.text_changed.connect(func(_t: String): _fill_list())
	box.add_child(_search)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 150)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(i: int): _select(_list_ids[i]))
	_list.item_activated.connect(func(i: int): _enter_moons(_list_ids[i]))
	box.add_child(_list)
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.fit_content = true
	_info.scroll_active = false
	_info.custom_minimum_size = Vector2(0, 180)
	_info.add_theme_font_size_override("normal_font_size", 13)
	_info.add_theme_font_size_override("bold_font_size", 17)
	box.add_child(_info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_mark = Button.new()
	_mark.text = "Marcar destino"
	_mark.pressed.connect(func():
		world.nav_target = _selected
		_refresh_info())
	row.add_child(_mark)
	_go = Button.new()
	_go.text = "Viajar"
	_go.pressed.connect(_travel)
	row.add_child(_go)
	_view_btn = Button.new()
	_view_btn.text = "Ver lunas"
	_view_btn.pressed.connect(func():
		if _focus_planet != "":
			_back_to_system()
		else:
			_enter_moons(_selected))
	row.add_child(_view_btn)
	box.add_child(row)
	var center_btn := Button.new()
	center_btn.text = "Centrar en mi nave"
	center_btn.pressed.connect(_center_on_ship)
	box.add_child(center_btn)
	var hint := Label.new()
	hint.text = "Tab/Esc cerrar · Rueda: zoom · Clic der.: mover · Clic: elegir · Doble clic: lunas"
	hint.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	hint.add_theme_font_size_override("font_size", 12)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)


# --- Apertura ---------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if world == null or world.system == null:
		return
	var typing := _search.has_focus()
	var cancel := event.is_action_pressed(&"ui_cancel") and not typing
	if _open and (event.is_action_pressed(&"pause") or cancel or (event.is_action_pressed(&"toggle_map") and not typing)):
		close()
		get_viewport().set_input_as_handled()
	elif not _open and event.is_action_pressed(&"toggle_map") and not GameSettings.ui_modal:
		open()
		get_viewport().set_input_as_handled()


## Jugador que tiene el mapa abierto (el anfitrión salvo que lo abra otro desde el menú rápido).
func _viewer() -> Astronaut:
	return _who if _who != null else world.player


var _who: Astronaut = null


func open_for(a: Astronaut) -> void:
	_who = a
	open()


func open() -> void:
	world.set_render_paused(true)   # el mapa tapa la pantalla: no se dibuja el mundo 3D detrás
	_open = true
	visible = true
	_viewer().input_blocked = true
	GameSettings.ui_modal = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _selected == "":
		_selected = world.system.system_planet(world.body.id)
	_fill_list()
	_refresh_info()
	if not _viewer().pin.uses_mouse:
		_list.grab_focus()


func close() -> void:
	world.set_render_paused(false)
	_open = false
	visible = false
	_search.release_focus()
	_viewer().input_blocked = false
	_who = null
	GameSettings.ui_modal = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func is_open() -> bool:
	return _open


# --- Lista y ficha ------------------------------------------------------------------------------

func _fill_list() -> void:
	var sys := world.system
	var q := _search.text.strip_edges().to_lower()
	_list.clear()
	_list_ids.clear()
	var planets: Array = sys.children.get("sun", []).duplicate()
	planets.sort_custom(func(a, b): return sys.position(a).length() < sys.position(b).length())
	var order: Array = ["sun"] + planets
	for pid in order:
		var b: BodyDef = sys.body(pid)
		if q == "" or b.display_name.to_lower().contains(q):
			_add_item(pid, "●  %s" % b.display_name, b.render_color("color"))
		var moons: Array = sys.children.get(pid, []).duplicate()
		moons.sort_custom(func(a, c): return sys.body(a).radius_m() > sys.body(c).radius_m())
		var shown := 0
		for mid in moons:
			var m: BodyDef = sys.body(mid)
			var match_q := q != "" and m.display_name.to_lower().contains(q)
			var expanded: bool = q == "" and (pid == sys.system_planet(_selected)) and (m.kind == "moon" or shown < 40)
			if match_q or expanded:
				_add_item(mid, "      ○  %s  (%s)" % [m.display_name, Units.format_distance(m.radius_m())], UiTheme.TEXT_DIM)
				shown += 1
		if q == "" and pid == sys.system_planet(_selected) and moons.size() > shown:
			_list.add_item("      … y %d lunas menores más (búscalas por nombre)" % (moons.size() - shown))
			_list.set_item_disabled(_list.item_count - 1, true)
			_list_ids.append("")
	for i in _list_ids.size():
		if _list_ids[i] == _selected:
			_list.select(i)
			_list.ensure_current_is_visible()


func _add_item(id: String, text: String, col: Color) -> void:
	_list.add_item(text)
	_list.set_item_custom_fg_color(_list.item_count - 1, col.lightened(0.2))
	_list_ids.append(id)


func _select(id: String) -> void:
	if id == "":
		return
	_selected = id
	_fill_list()
	_refresh_info()
	_diagram.queue_redraw()


func _subject_sys() -> DVec3:
	var subject: DVec3 = world.ship.state.pos_bf if world.ship != null and _viewer().aboard == world.ship else _viewer().position_bf()
	return world.system.to_system(subject, world.body.id)


func _distance_to(id: String) -> float:
	var b: BodyDef = world.system.body(id)
	return _subject_sys().distance_to(world.system.position(id)) - b.radius_m()


## Tiempo estimado con el piloto automático de viaje (ADR-028/031): despegue + crucero + frenado exponencial.
static func eta_seconds(d: float) -> float:
	var cruise_v := ShipParams.C * 1000.0
	var t := 15.0
	var d_brake := cruise_v * 5.0
	if d > d_brake:
		t += (d - d_brake) / cruise_v
		d = d_brake
	return t + 5.0 * log(1.0 + d / 2500.0)


func _refresh_info() -> void:
	var sys := world.system
	var b: BodyDef = sys.body(_selected)
	if b == null:
		return
	var d := _distance_to(_selected)
	var kinds := {"star": "Estrella", "planet": "Planeta", "dwarf_planet": "Planeta enano", "moon": "Luna", "moon_minor": "Luna menor"}
	var L := PackedStringArray()
	var star := "  ★ destino marcado" if world.nav_target == _selected else ""
	L.append("[b][color=#%s]%s[/color][/b]  [color=#a2a4a8]%s%s[/color]" % [b.render_color("color").lightened(0.3).to_html(false),
		b.display_name, kinds.get(b.kind, b.kind), star])
	L.append(b.description)
	L.append("")
	var g := b.surface_gravity()
	L.append("[color=#a2a4a8]Radio[/color] %s   [color=#a2a4a8]Masa[/color] %s kg   [color=#a2a4a8]Gravedad[/color] %.2f m/s² (%.2f g)" % [
		Units.format_distance(b.radius_m()), _sci(b.mass_kg()), g, g / 9.80665])
	var rot := absf(b.physical("sidereal_rotation_period", 0.0))
	if rot > 0.0:
		L.append("[color=#a2a4a8]Rotación[/color] %s%s" % [_duration(rot), " (retrógrada)" if b.physical("sidereal_rotation_period", 0.0) < 0.0 else ""])
	var o := b.orbit()
	if str(o.get("model", "")) == "planet":
		var rate := float(o["rates_per_century"][3])
		if rate > 0.0:
			L.append("[color=#a2a4a8]Año[/color] %s   [color=#a2a4a8]Distancia al Sol[/color] %.3f UA" % [_duration(36525.0 * 86400.0 * 360.0 / rate),
				sys.position(_selected).length() / Ephemeris.AU])
	elif str(o.get("model", "")) == "satellite":
		L.append("[color=#a2a4a8]Órbita[/color] a = %s, periodo %s%s" % [Units.format_distance(float(o["a_m"])), _duration(absf(float(o["period_s"]))),
			" (retrógrada)" if float(o["i_deg"]) > 90.0 else ""])
	var atm := b.atmosphere()
	if bool(atm.get("present", false)):
		var m := AtmosphereModel.for_body(b)
		if m.kind == "gas_giant":
			L.append("[color=#a2a4a8]Atmósfera[/color] %.0f K a 1 bar · sin superficie · %s" % [m.temperature(0.0), str(atm.get("composition", "")).substr(0, 70)])
		else:
			L.append("[color=#a2a4a8]Atmósfera[/color] %s bar · %.0f K · %s" % [String.num(m.pressure(0.0) / 1.0e5, 5), m.temperature(0.0),
				str(atm.get("composition", "")).substr(0, 70)])
	elif b.kind != "star":
		L.append("[color=#a2a4a8]Atmósfera[/color] ninguna apreciable")
	var nm: int = sys.children.get(_selected, []).size()
	if nm > 0:
		L.append("[color=#a2a4a8]Lunas[/color] %d (doble clic para verlas)" % nm)
	L.append("")
	L.append("[color=#a2a4a8]Distancia[/color] %s · luz: %s · [color=#7fe39a]viaje ≈ %s[/color]" % [Units.format_distance(maxf(d, 0.0)),
		_duration(maxf(d, 0.0) / ShipParams.C), _duration(eta_seconds(maxf(d, 0.0)))])
	L.append("[color=#7d7f83]Calidad del radio: %s · %s[/color]" % [b.physical_quality("mean_radius"), b.terrain_note()])
	_info.text = "\n".join(L)
	var piloting := _viewer().is_piloting()
	_go.disabled = not piloting or b.kind == "star"
	_go.tooltip_text = "No se puede viajar al Sol" if b.kind == "star" else ("" if piloting else "Siéntate en el puesto de pilotaje")
	_view_btn.text = "Volver al sistema" if _focus_planet != "" else "Ver lunas"
	_view_btn.disabled = _focus_planet == "" and sys.children.get(sys.system_planet(_selected), []).is_empty()


## 5.683e26 → "5,68×10²⁶".
static func _sci(v: float) -> String:
	if v <= 0.0:
		return "?"
	var e := int(floor(log(v) / log(10.0)))
	var sup := "⁰¹²³⁴⁵⁶⁷⁸⁹"
	var es := ""
	for ch in str(e):
		es += sup[int(ch)] if ch != "-" else "⁻"
	return ("%.2f×10" % (v / pow(10.0, e))).replace(".", ",") + es


static func _duration(s: float) -> String:
	if s < 120.0:
		return "%.0f s" % s
	if s < 7200.0:
		return "%.1f min" % (s / 60.0)
	if s < 2.0 * 86400.0:
		return "%.1f h" % (s / 3600.0)
	if s < 730.0 * 86400.0:
		return "%.1f días" % (s / 86400.0)
	return "%.1f años" % (s / (365.25 * 86400.0))


func _travel() -> void:
	if world.ship != null and _viewer().is_piloting() and _selected != "sun":
		world.nav_target = _selected
		world.ship.cmd_travel(_selected)
		close()


func _enter_moons(id: String) -> void:
	if id == "":
		return
	var planet := world.system.system_planet(id)
	if planet == "sun" or world.system.children.get(planet, []).is_empty():
		return
	_focus_planet = planet
	_selected = id
	_zoom = 1.0
	_pan = Vector2.ZERO
	_fill_list()
	_refresh_info()


func _back_to_system() -> void:
	_focus_planet = ""
	_zoom = 1.0
	_pan = Vector2.ZERO
	_refresh_info()


func _center_on_ship() -> void:
	var dom := world.system.dominant_body(_subject_sys(), world.body.id)
	var planet := world.system.system_planet(dom)
	if planet != "sun" and _focus_planet == "":
		_enter_moons(planet)
	_pan = Vector2.ZERO
	_zoom = 1.0


var _redraw_t := 0.0


## 30 redibujados por segundo como máximo (el mapa no necesita más; antes iba a cada fotograma).
func _process(delta: float) -> void:
	if not _open:
		return
	_redraw_t -= delta
	if _redraw_t <= 0.0:
		_minor_budget = 24
		_redraw_t = 1.0 / 30.0
		_pos_cache.clear()
		_diagram.queue_redraw()


var _pos_cache := {}
var _minor_cache := {}           ## lunas menores: id -> posición; se renuevan unas pocas por redibujado (son cientos)
var _minor_budget := 24
var _stars: Array = []
var _star_cols: Array = []
var _orbit_px := {}              ## id -> PackedVector2Array proyectada (válida mientras no cambie la vista)
var _orbit_px_key := ""
var _f_planet_pos: DVec3 = DVec3.new()
var _f_extent := 1.0


## Posición heliocéntrica con caché por redibujado (las lunas menores son cientos).
func _pos(id: String) -> DVec3:
	if _pos_cache.has(id):
		return _pos_cache[id]
	var minor: bool = world.system.body(id).kind == "moon_minor"
	if minor and _minor_cache.has(id):
		if _minor_budget <= 0:
			return _minor_cache[id]
		_minor_budget -= 1
	var p := world.system.position(id)
	if minor:
		_minor_cache[id] = p
	else:
		_pos_cache[id] = p
	return p


## Valores comunes a todo un redibujado (antes se recalculaban en cada punto de cada órbita).
func _prepare_frame() -> void:
	if _focus_planet != "":
		_f_planet_pos = _pos(_focus_planet)
		_f_extent = _moon_extent()


# --- Proyección -------------------------------------------------------------------------------

func _view_params() -> Array:
	var size := _diagram.size
	var center := size * 0.5 + _pan
	var scale_px := minf(size.x, size.y) * 0.46 * _zoom
	return [center, scale_px]


## Posición heliocéntrica → píxel (vista sistema: log; vista lunas: lineal centrada en el planeta).
func _to_px(p_sys: DVec3) -> Vector2:
	var vp := _view_params()
	var center: Vector2 = vp[0]
	var scale_px: float = vp[1]
	if _focus_planet == "":
		var r_au := sqrt(p_sys.x * p_sys.x + p_sys.y * p_sys.y) / Ephemeris.AU
		if r_au < 1e-12:
			return center
		var rp := scale_px * log(1.0 + r_au / LOG_REF_AU) / log(1.0 + MAX_AU / LOG_REF_AU)
		var ang := atan2(p_sys.y, p_sys.x)
		return center + Vector2(cos(ang), -sin(ang)) * rp
	var rel := p_sys.sub(_f_planet_pos)
	return center + Vector2(rel.x, -rel.y) * (scale_px / _f_extent)


func _moon_extent() -> float:
	var sys := world.system
	var best := sys.body(_focus_planet).radius_m() * 4.0
	for mid in sys.children.get(_focus_planet, []):
		var m: BodyDef = sys.body(mid)
		if m.kind == "moon":
			best = maxf(best, float(m.orbit().get("a_m", 0.0)) * 1.08)
	return best


## Órbitas muestreadas (relativas al padre) a lo largo de un periodo; se recalculan si el tiempo avanza mucho.
func _orbit_points(id: String) -> PackedVector3Array:
	var sys := world.system
	if absf(sys.time_s - _orbit_time) > 86400.0 * 30.0:
		_orbits.clear()
		_orbit_time = sys.time_s
	if _orbits.has(id):
		return _orbits[id]
	var b: BodyDef = sys.body(id)
	var o := b.orbit()
	var period := 0.0
	if str(o.get("model", "")) == "planet":
		period = 36525.0 * 86400.0 * 360.0 / maxf(float(o["rates_per_century"][3]), 1e-9)
	else:
		period = absf(float(o.get("period_s", 0.0)))
	var pts := PackedVector3Array()
	if period <= 0.0:
		_orbits[id] = pts
		return pts
	var parent := b.parent_id
	for k in ORBIT_SAMPLES + 1:
		var t := sys.time_s + period * float(k) / ORBIT_SAMPLES
		var p := sys._position_at(id, t)
		var pp := sys._position_at(parent, t) if parent != "" and parent != "sun" else DVec3.new()
		var rel := p.sub(pp)
		pts.append(Vector3(rel.x, rel.y, rel.z))
	_orbits[id] = pts
	return pts


# --- Dibujo -----------------------------------------------------------------------------------

func _draw_diagram() -> void:
	var _t0 := Time.get_ticks_usec()
	var sys := world.system
	_prepare_frame()
	var font := UiTheme.font(500)
	var size := _diagram.size
	# Estrellas de fondo (rectángulos de 1-2 px: los círculos costaban 15 ms por redibujado).
	if _stars.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 42
		for i in 160:
			_stars.append(Rect2(Vector2(rng.randf(), rng.randf()), Vector2.ONE * rng.randf_range(1.0, 2.0)))
			_star_cols.append(Color(1, 1, 1, rng.randf_range(0.08, 0.3)))
	for i in _stars.size():
		var st: Rect2 = _stars[i]
		_diagram.draw_rect(Rect2(st.position * size, st.size), _star_cols[i])
	var bodies: Array
	if _focus_planet == "":
		bodies = sys.children.get("sun", [])
		_draw_scale_rings(font)
		var sunp := _to_px(DVec3.new())
		_diagram.draw_circle(sunp, 9.0, Color(1.0, 0.85, 0.4))
		_diagram.draw_circle(sunp, 15.0, Color(1.0, 0.8, 0.3, 0.15))
		_diagram.draw_string(font, sunp + Vector2(12, -10), "Sol", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.9, 0.6))
	else:
		bodies = sys.children.get(_focus_planet, [])
		var pb: BodyDef = sys.body(_focus_planet)
		var pp := _to_px(_pos(_focus_planet))
		var extent := _f_extent
		var rpx: float = maxf(pb.radius_m() * float(_view_params()[1]) / extent, 6.0)
		_diagram.draw_circle(pp, rpx, pb.render_color("color"))
		_diagram.draw_string(font, pp + Vector2(rpx + 6, 4), pb.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiTheme.TEXT)
		var rd: Dictionary = pb.render()
		for rg in rd.get("rings", []):
			var r_in: float = float(rg["inner_m"]) * _view_params()[1] / extent
			_diagram.draw_arc(pp, r_in, 0, TAU, 96, Color(0.9, 0.85, 0.7, clampf(float(rg["opacity"]) * 0.8, 0.05, 0.5)), 1.0, true)
	var _t1 := Time.get_ticks_usec()
	_hover = ""
	var mouse := _diagram.get_local_mouse_position()
	var best_d := 18.0
	for id in bodies:
		var b: BodyDef = sys.body(id)
		var major := b.kind != "moon_minor"
		var col := b.render_color("color")
		# Órbita real (elipse muestreada).
		if major:
			var poly := _orbit_poly(id)
			if poly.size() > 2:
				var oc := Color(col.r, col.g, col.b, 0.35 if id == _selected else 0.16)
				_diagram.draw_polyline(poly, oc, 1.5 if id == _selected else 1.0)
		var p := _to_px(_pos(id))
		var rad := 2.0 if not major else 3.5 + clampf(log(b.radius_m() / 2.0e5) * 1.3, 0.0, 6.0)
		if major:
			_diagram.draw_circle(p, rad, col)
		else:
			_diagram.draw_rect(Rect2(p - Vector2.ONE * 1.5, Vector2.ONE * 3.0), Color(col.r, col.g, col.b, 0.6))
		if id == _selected or sys.system_planet(_selected) == id:
			_diagram.draw_arc(p, rad + 5.0, 0.0, TAU, 24, AMB, 2.0, true)
		if id == world.nav_target:
			_diagram.draw_arc(p, rad + 9.0, 0.0, TAU, 24, GREEN, 1.5, true)
		var dm := p.distance_to(mouse)
		if dm < best_d:
			best_d = dm
			_hover = id
		# En la vista de lunas, las interiores amontonadas sólo se rotulan al acercarse (o si están elegidas).
		var crowded := _focus_planet != "" and p.distance_to(_to_px(_pos(_focus_planet))) < 45.0
		if major and (id == _selected or (not crowded and (_focus_planet == "" or b.radius_m() > 150000.0))):
			_diagram.draw_string(font, p + Vector2(rad + 4, 4), b.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.TEXT)
	var _t2 := Time.get_ticks_usec()
	# Nave y ruta al destino.
	var subj := _subject_sys()
	var sp2 := _to_px(subj)
	if world.nav_target != "" and sys.has_body(world.nav_target):
		var tp := _to_px(_pos(world.nav_target))
		if sp2.is_finite() and tp.is_finite() and sp2.distance_to(tp) < 20000.0:
			_draw_dashed(sp2, tp, GREEN)
	var view_rect := Rect2(Vector2.ZERO, size).grow(-24.0)
	if view_rect.has_point(sp2):
		_diagram.draw_colored_polygon(PackedVector2Array([sp2 + Vector2(0, -9), sp2 + Vector2(7, 7), sp2 + Vector2(-7, 7)]), A)
		_diagram.draw_string(font, sp2 + Vector2(9, -8), "TU NAVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, A)
	else:
		# Fuera de la vista (p. ej. en la vista de lunas de otro planeta): flecha en el borde hacia la nave.
		var c := size * 0.5
		var dv := (sp2 - c).normalized() if sp2.is_finite() and sp2 != c else Vector2.RIGHT
		var k := minf(absf((size.x * 0.5 - 30.0) / maxf(absf(dv.x), 1e-4)), absf((size.y * 0.5 - 30.0) / maxf(absf(dv.y), 1e-4)))
		var ep := c + dv * k
		var n := Vector2(-dv.y, dv.x)
		_diagram.draw_colored_polygon(PackedVector2Array([ep + dv * 10.0, ep - dv * 6.0 + n * 7.0, ep - dv * 6.0 - n * 7.0]), A)
		_diagram.draw_string(font, ep - dv * 60.0 + Vector2(-24, 4), "TU NAVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, A)
	var _t3 := Time.get_ticks_usec()
	if _hover != "":
		var hb: BodyDef = sys.body(_hover)
		var hp := _to_px(_pos(_hover))
		var txt := "%s · %s" % [hb.display_name, Units.format_distance(maxf(_distance_to(_hover), 0.0))]
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 16
		_diagram.draw_style_box(UiTheme.glass(6), Rect2(hp + Vector2(12, -34), Vector2(w, 24)))
		_diagram.draw_string(font, hp + Vector2(20, -17), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.TEXT)
	# Cabecera.
	var date := Time.get_datetime_string_from_unix_time(int(sys.time_s + Ephemeris.J2000_UNIX), true)
	var view := "Sistema Solar (escala logarítmica)" if _focus_planet == "" else "Lunas de %s (escala lineal)" % sys.body(_focus_planet).display_name
	_diagram.draw_string(UiTheme.font(700), Vector2(18, 30), view, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, A)
	_diagram.draw_string(font, Vector2(18, 52), "Fecha: %s UTC · vista desde el norte de la eclíptica · zoom ×%.1f" % [date, _zoom],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.TEXT_DIM)
	if OS.has_environment("MAP_PROFILE"):
		print("MAPDRAW %.2f ms (fondo %.2f, cuerpos %.2f, nave %.2f)" % [(Time.get_ticks_usec() - _t0) / 1000.0, (_t1 - _t0) / 1000.0,
			(_t2 - _t1) / 1000.0, (_t3 - _t2) / 1000.0])


## Órbita proyectada en píxeles; se reutiliza mientras no cambien el zoom, el desplazamiento ni la vista
## (las órbitas relativas al padre son fijas; en la vista de lunas el planeta está siempre en el centro).
func _orbit_poly(id: String) -> PackedVector2Array:
	var key := "%s|%.4f|%.1f|%.1f|%s|%.0f" % [_focus_planet, _zoom, _pan.x, _pan.y, str(_diagram.size), _orbit_time]
	if key != _orbit_px_key:
		_orbit_px.clear()
		_orbit_px_key = key
	if _orbit_px.has(id):
		return _orbit_px[id]
	var poly := PackedVector2Array()
	var pts := _orbit_points(id)
	var base := DVec3.new() if _focus_planet == "" else _f_planet_pos
	for v in pts:
		poly.append(_to_px(base.add(DVec3.new(v.x, v.y, v.z))))
	_orbit_px[id] = poly
	return poly


func _draw_scale_rings(font: Font) -> void:
	var center: Vector2 = _view_params()[0]
	for au: float in [0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 40.0]:
		var r := _to_px(DVec3.new(au * Ephemeris.AU, 0, 0)).distance_to(center)
		_diagram.draw_arc(center, r, 0.0, TAU, 72, Color(1, 1, 1, 0.04), 1.0)
		_diagram.draw_string(font, center + Vector2(r + 3, 12), "%s UA" % str(au), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.22))


func _draw_dashed(a: Vector2, b: Vector2, col: Color) -> void:
	var d := a.distance_to(b)
	if d < 1.0:
		return
	var dir := (b - a) / d
	var t := 0.0
	while t < d:
		_diagram.draw_line(a + dir * t, a + dir * minf(t + 8.0, d), Color(col.r, col.g, col.b, 0.7), 1.5)
		t += 14.0


func _on_diagram_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, 1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, 1.0 / 1.15)
		elif event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed and _hover != "":
			if event.double_click:
				_enter_moons(_hover)
			else:
				_select(_hover)
	elif event is InputEventMouseMotion and _dragging:
		_pan += event.relative


func _zoom_at(pos: Vector2, factor: float) -> void:
	var center: Vector2 = _view_params()[0]
	var nz := clampf(_zoom * factor, 0.3, 60.0)
	var k := nz / _zoom
	_pan += (pos - center) * (1.0 - k)
	_zoom = nz
