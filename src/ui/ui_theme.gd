class_name UiTheme
extends RefCounted
## Estilo visual común (ADR-017, identidad «WE ARE ALONE?» en ADR-036): grafito casi negro, naranja de señal
## (el brillo de la Tierra rota, una baliza solitaria), blanco lunar para el texto y un verde azulado frío para
## datos. Tipografía Bahnschrift (Windows 10+; respaldo Segoe UI / Arial), estrecha en los títulos.

const GAME_TITLE := "WE ARE ALONE?"
const ACCENT := Color(1.0, 0.55, 0.22)
const ACCENT_SOFT := Color(1.0, 0.55, 0.22, 0.32)
const AMBER := Color(1.0, 0.83, 0.52)
const DATA := Color(0.45, 0.85, 0.82)
const OK := Color(0.5, 0.95, 0.62)
const DANGER := Color(1.0, 0.33, 0.3)
const TEXT := Color(0.94, 0.92, 0.88)
const TEXT_DIM := Color(0.63, 0.64, 0.66)
const GLASS := Color(0.035, 0.035, 0.045, 0.74)
const GLASS_STRONG := Color(0.03, 0.03, 0.04, 0.9)
const FONTS := ["Bahnschrift", "Segoe UI", "Arial"]

static var _fonts := {}
static var _theme: Theme


static func font(weight: int = 400) -> Font:
	if not _fonts.has(weight):
		var f := SystemFont.new()
		f.font_names = PackedStringArray(FONTS)
		f.font_weight = weight
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		_fonts[weight] = f
	return _fonts[weight]


## Título: Bahnschrift estrecha (eje de anchura de la fuente variable) y espaciada.
static var _title_font: FontVariation


static func title_font() -> Font:
	if _title_font == null:
		_title_font = FontVariation.new()
		_title_font.base_font = font(700)
		_title_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wdth"): 75.0}
		_title_font.spacing_glyph = 5
	return _title_font


static var _glass_cache := {}


## Panel de cristal. Esquinas más vivas que antes (identidad ADR-036): el radio pedido se reduce a la mitad.
## Con caché (ronda 9): los HUD piden los mismos estilos en cada redibujado y crearlos costaba tiempo.
static func glass(radius: int = 10, bg: Color = GLASS, border: Color = ACCENT_SOFT, border_w: int = 1) -> StyleBoxFlat:
	var key := "%d|%s|%s|%d" % [radius, bg.to_html(), border.to_html(), border_w]
	var hit: StyleBoxFlat = _glass_cache.get(key)
	if hit != null:
		return hit
	if _glass_cache.size() > 600:
		_glass_cache.clear()
	var s := _new_glass(radius, bg, border, border_w)
	_glass_cache[key] = s
	return s


static func _new_glass(radius: int, bg: Color, border: Color, border_w: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(int(radius * 0.5))
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.anti_aliasing = true
	return s


## Tema para menús (Button, Label, PanelContainer, HSlider, CheckBox, OptionButton, PopupMenu).
static func build() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font(400)
	t.default_font_size = 18
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", glass(16, GLASS_STRONG, ACCENT_SOFT, 1))
	t.set_stylebox("panel", "Panel", glass(16, GLASS_STRONG, ACCENT_SOFT, 1))
	for cls in ["Button", "OptionButton", "CheckBox"]:
		var normal := glass(8, Color(0.08, 0.08, 0.1, 0.85), Color(1.0, 0.55, 0.22, 0.22))
		var hover := glass(8, Color(0.16, 0.1, 0.06, 0.95), ACCENT, 2)
		var pressed := glass(8, Color(0.25, 0.14, 0.07, 0.95), ACCENT, 2)
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("focus", cls, glass(8, Color(0, 0, 0, 0), AMBER, 1))
		t.set_stylebox("hover_pressed", cls, pressed)
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, ACCENT)
		t.set_font("font", cls, font(500))
		t.set_font_size("font_size", cls, 18)
	var popup := glass(8, GLASS_STRONG, ACCENT_SOFT)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", glass(6, Color(0.25, 0.14, 0.07, 0.95), ACCENT, 1))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_font("font", "PopupMenu", font(400))
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.18, 0.18, 0.2, 0.9)
	track.set_corner_radius_all(4)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = ACCENT
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	_theme = t
	return t


## Tecla dibujada como una tecla física (para ayudas de control).
## Marca un punto del mundo en la pantalla: rombo con etiqueta si está a la vista; si no, flecha en el borde
## (en una elipse) apuntando hacia él. `ring` dibuja un círculo en lugar del rombo (cuerpos celestes).
static func draw_world_marker(ci: CanvasItem, cam: Camera3D, target: Vector3, label: String, sub: String,
		color: Color, s: float, ring := false) -> void:
	if cam == null:
		return
	# Dirección en el espacio de la cámara: estable aunque el objetivo esté a millones de km, de lado o detrás
	# (proyectar puntos lejanos o casi perpendiculares hacía saltar la flecha de un lado a otro).
	var dir_w := target - cam.global_position
	if dir_w.length_squared() < 1e-6:
		return
	dir_w = dir_w.normalized()
	var v := cam.global_transform.basis.inverse() * dir_w
	var vp := ci.get_viewport_rect().size
	var margin := 60.0 * s
	var f := font(600)
	if v.z < -0.02:
		var p := cam.unproject_position(cam.global_position + dir_w * 100.0)
		if p.x > margin and p.x < vp.x - margin and p.y > margin and p.y < vp.y - margin:
			var d := 7.0 * s
			if ring:
				ci.draw_arc(p, 11.0 * s, 0.0, TAU, 32, color, 2.0 * s, true)
				ci.draw_circle(p, 2.5 * s, color)
			else:
				ci.draw_polyline(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0), p + Vector2(0, -d)]),
					color, 2.0 * s, true)
			ci.draw_string(f, p + Vector2(-90 * s, -18 * s), label, HORIZONTAL_ALIGNMENT_CENTER, 180 * s, int(12 * s), color)
			if sub != "":
				ci.draw_string(font(500), p + Vector2(-90 * s, 30 * s), sub, HORIZONTAL_ALIGNMENT_CENTER, 180 * s, int(11 * s), TEXT_DIM)
			return
	# Fuera de la vista: flecha en el borde hacia donde hay que girar.
	var dir := Vector2(v.x, -v.y)
	if dir.length_squared() < 1e-8:
		dir = Vector2(0, 1)
	dir = dir.normalized()
	var c := vp * 0.5
	var e := c + Vector2(dir.x * (vp.x * 0.5 - margin), dir.y * (vp.y * 0.5 - margin))
	var n := Vector2(-dir.y, dir.x)
	var a := 12.0 * s
	ci.draw_colored_polygon(PackedVector2Array([e + dir * a, e - dir * a * 0.5 + n * a * 0.7, e - dir * a * 0.5 - n * a * 0.7]), color)
	var tp := e - dir * 34 * s + Vector2(-90 * s, 4 * s)
	ci.draw_string(f, tp, label, HORIZONTAL_ALIGNMENT_CENTER, 180 * s, int(12 * s), color)
	if sub != "":
		ci.draw_string(font(500), tp + Vector2(0, 15 * s), sub, HORIZONTAL_ALIGNMENT_CENTER, 180 * s, int(11 * s), TEXT_DIM)


static var _keycap_box: StyleBoxFlat


static func draw_keycap(ci: CanvasItem, pos: Vector2, key: String, size: int = 15) -> float:
	var f := font(600)
	var tw := f.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var w := maxf(tw + 14.0, size * 1.8)
	var h := size * 1.65
	var r := Rect2(pos, Vector2(w, h))
	if _keycap_box == null:
		_keycap_box = StyleBoxFlat.new()
		_keycap_box.bg_color = Color(0.11, 0.11, 0.12, 0.95)
		_keycap_box.border_color = Color(1.0, 0.62, 0.32, 0.75)
		_keycap_box.set_border_width_all(1)
		_keycap_box.border_width_bottom = 2
		_keycap_box.set_corner_radius_all(3)
		_keycap_box.anti_aliasing = true
	var sb := _keycap_box
	ci.draw_style_box(sb, r)
	ci.draw_string(f, pos + Vector2((w - tw) * 0.5, h * 0.5 + size * 0.36), key, HORIZONTAL_ALIGNMENT_LEFT, -1, size, TEXT)
	return w
