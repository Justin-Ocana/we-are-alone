class_name StoryHud
extends CanvasLayer
## Interfaz de la historia (ADR-043): subtítulos y quién habla, indicador de voz (líneas sin transcripción),
## «Espacio · Omitir» en los mensajes obligatorios, panel de objetivo con marcador en pantalla (rombo o flecha
## en el borde), barra de progreso (diagnóstico, energía) y el efecto de despertar (visión borrosa, tinte naranja,
## parpadeos). Se dibuja sobre la vista del jugador 1 (en cooperativo, sobre las dos mitades).

const WAKE_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float blur = 0.0;
uniform float dark = 0.0;
uniform float tint = 0.0;
void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * (1.0 + blur * 9.0);
	vec3 c = texture(screen_tex, SCREEN_UV).rgb * 0.2;
	c += texture(screen_tex, SCREEN_UV + vec2(px.x, 0.0)).rgb * 0.1;
	c += texture(screen_tex, SCREEN_UV - vec2(px.x, 0.0)).rgb * 0.1;
	c += texture(screen_tex, SCREEN_UV + vec2(0.0, px.y)).rgb * 0.1;
	c += texture(screen_tex, SCREEN_UV - vec2(0.0, px.y)).rgb * 0.1;
	c += texture(screen_tex, SCREEN_UV + px * 1.6).rgb * 0.1;
	c += texture(screen_tex, SCREEN_UV - px * 1.6).rgb * 0.1;
	c += texture(screen_tex, SCREEN_UV + vec2(px.x, -px.y) * 1.6).rgb * 0.1;
	c += texture(screen_tex, SCREEN_UV + vec2(-px.x, px.y) * 1.6).rgb * 0.1;
	vec2 q = SCREEN_UV - 0.5;
	float vig = smoothstep(0.85, 0.2, length(q) * (1.0 + dark));
	c = mix(c, c * vec3(1.25, 0.72, 0.45) + vec3(0.04, 0.012, 0.0), tint);
	COLOR = vec4(c * vig * (1.0 - dark * 0.85), 1.0);
}
"""

var world: SurfaceWorld
var dialogue: DialogueDirector
var objective := ""
var objective_point := Vector3.ZERO      ## marco de la base
var has_point := false
var _world_getter := Callable()          ## objetivo en el mundo (posición del motor), fuera de la base
var progress := -1.0                     ## 0..1 (−1 = sin barra)
var progress_text := ""
var wake := 0.0                          ## 0..1 intensidad del efecto de despertar
var blink := 0.0                         ## 0..1 párpados cerrados
var _canvas: Control
var _wake_rect: ColorRect
var _wake_mat: ShaderMaterial
var _speaker := ""
var _sub := ""
var _skippable := false
var _talking := false
var _obj_flash := 0.0
var _t := 0.0


func _ready() -> void:
	layer = 6
	_wake_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = WAKE_SHADER
	_wake_mat.shader = sh
	_wake_rect = ColorRect.new()
	_wake_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wake_rect.material = _wake_mat
	_wake_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wake_rect.visible = false
	add_child(_wake_rect)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)
	if dialogue != null:
		dialogue.line_started.connect(func(_id: String, sp: String, sk: bool):
			_speaker = sp
			_skippable = sk
			_talking = true)
		dialogue.line_finished.connect(func(_id: String, _s: bool):
			_talking = false
			_skippable = false
			_sub = "")
		dialogue.subtitle_changed.connect(func(t: String): _sub = t)


## Objetivo con un punto del mundo (p. ej. una instalación del NEXUS en otro planeta).
func set_objective_world(text: String, getter: Callable) -> void:
	set_objective(text, "")
	_world_getter = getter


func set_objective(text: String, point_id: String = "") -> void:
	_world_getter = Callable()
	if text != objective:
		_obj_flash = 1.0
		if text != "":
			GameAudio.play("notify", -8.0)
	objective = text
	has_point = point_id != "" and (BaseLayout.POINTS.has(point_id) or BaseLayout.TERMINALS.has(point_id))
	if has_point:
		objective_point = BaseLayout.POINTS[point_id] if BaseLayout.POINTS.has(point_id) else BaseLayout.TERMINALS[point_id][2] + Vector3(0, 0.4, 0)


func _process(delta: float) -> void:
	_t += delta
	_obj_flash = maxf(0.0, _obj_flash - delta * 0.8)
	var w := clampf(maxf(wake, blink), 0.0, 1.0)
	_wake_rect.visible = w > 0.001
	if _wake_rect.visible:
		_wake_mat.set_shader_parameter("blur", wake)
		_wake_mat.set_shader_parameter("dark", maxf(wake * 0.35, blink))
		_wake_mat.set_shader_parameter("tint", wake * 0.8)
	_canvas.queue_redraw()


func _on_draw() -> void:
	var vp := _canvas.get_viewport_rect().size
	var s := clampf(vp.y / 720.0, 0.8, 1.6) * GameSettings.ui_scale
	var f := UiTheme.font(500)
	var fb := UiTheme.font(700)
	# --- Objetivo (arriba a la izquierda) y su marcador.
	if objective != "" and not GameSettings.ui_hidden:
		var box_w := 360.0 * s
		var pos := Vector2(24 * s, 96 * s)
		if world != null and world.player != null and world.player.is_piloting():
			pos = Vector2(vp.x - box_w - 24 * s, 270 * s)   # pilotando, a la derecha: a la izquierda está la ayuda de vuelo
		var lines := _wrap(objective, f, int(16 * s), box_w - 28 * s)
		var h := (34 + 22 * lines.size()) * s
		var border := UiTheme.ACCENT.lerp(Color.WHITE, _obj_flash * 0.6)
		_canvas.draw_style_box(UiTheme.glass(8, UiTheme.GLASS, Color(border, 0.45 + 0.5 * _obj_flash)), Rect2(pos, Vector2(box_w, h)))
		_canvas.draw_rect(Rect2(pos, Vector2(4 * s, h)), UiTheme.ACCENT)
		_canvas.draw_string(fb, pos + Vector2(16 * s, 22 * s), "OBJETIVO", HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 * s), UiTheme.ACCENT)
		for i in lines.size():
			_canvas.draw_string(f, pos + Vector2(16 * s, (44 + 22 * i) * s), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * s), UiTheme.TEXT)
		if _world_getter.is_valid() and world != null and world.view != null:
			var cam2 := world.view.active_camera()
			var tgt: Vector3 = _world_getter.call()
			if tgt.is_finite():
				var d2 := world.player.global_position.distance_to(tgt)
				UiTheme.draw_world_marker(_canvas, cam2, tgt, "NEXUS", Units.format_distance(d2), Color(0.4, 0.9, 1.0), s)
		elif has_point and world != null and world.base != null and world.player != null:
			var cam := world.view.active_camera() if world.view != null else null
			if cam != null:
				var target := world.base.to_engine(objective_point)
				var dist := world.player.global_position.distance_to(target)
				UiTheme.draw_world_marker(_canvas, cam, target, "OBJETIVO", "%d m" % int(dist), UiTheme.ACCENT, s)
	# --- Barra de progreso (centro).
	if progress >= 0.0:
		var bw := 360.0 * s
		var bp := Vector2((vp.x - bw) * 0.5, vp.y * 0.62)
		_canvas.draw_string(fb, bp + Vector2(0, -10 * s), progress_text, HORIZONTAL_ALIGNMENT_CENTER, bw, int(14 * s), UiTheme.TEXT)
		_canvas.draw_rect(Rect2(bp, Vector2(bw, 8 * s)), Color(1, 1, 1, 0.12))
		_canvas.draw_rect(Rect2(bp, Vector2(bw * clampf(progress, 0.0, 1.0), 8 * s)), UiTheme.ACCENT)
	# --- Subtítulos / indicador de voz (abajo, centrados).
	if _talking:
		var y := vp.y - 150 * s
		if _sub != "":
			var sw := minf(vp.x - 80 * s, 900 * s)
			var lines := _wrap(_sub, f, int(19 * s), sw - 40 * s)
			var h := (16 + 26 * lines.size() + (22 if _speaker != "" else 0)) * s
			var r := Rect2(Vector2((vp.x - sw) * 0.5, y - h), Vector2(sw, h))
			_canvas.draw_style_box(UiTheme.glass(8, Color(0.02, 0.02, 0.025, 0.72), Color(0, 0, 0, 0)), r)
			var ty := r.position.y + 22 * s
			if _speaker != "":
				_canvas.draw_string(fb, Vector2(r.position.x, ty), _speaker.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, sw, int(13 * s), UiTheme.ACCENT)
				ty += 22 * s
			for i in lines.size():
				_canvas.draw_string(f, Vector2(r.position.x, ty + 26 * s * i), lines[i], HORIZONTAL_ALIGNMENT_CENTER, sw, int(19 * s), UiTheme.TEXT)
		else:
			# Sin transcripción: indicador discreto de que alguien habla.
			var c := Vector2(vp.x * 0.5, y - 16 * s)
			var label := _speaker.to_upper() if _speaker != "" else "AUDIO"
			_canvas.draw_style_box(UiTheme.glass(14, UiTheme.GLASS, UiTheme.ACCENT_SOFT), Rect2(c - Vector2(90 * s, 16 * s), Vector2(180 * s, 32 * s)))
			for i in 5:
				var bh := (4.0 + 9.0 * absf(sin(_t * 7.0 + i * 1.3))) * s
				_canvas.draw_rect(Rect2(c + Vector2((-70 + i * 9) * s, -bh * 0.5), Vector2(4 * s, bh)), UiTheme.ACCENT)
			_canvas.draw_string(fb, c + Vector2(-20 * s, 5 * s), label, HORIZONTAL_ALIGNMENT_LEFT, 110 * s, int(12 * s), UiTheme.TEXT)
		if _skippable:
			var kp := Vector2(vp.x - 210 * s, vp.y - 44 * s)
			var kw := UiTheme.draw_keycap(_canvas, kp, "ESPACIO", int(13 * s))
			_canvas.draw_string(f, kp + Vector2(kw + 10 * s, 15 * s), "Omitir mensaje", HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * s), UiTheme.TEXT)


func _wrap(text: String, f: Font, size: int, width: float) -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""
	for word in text.split(" "):
		var test := word if line == "" else line + " " + word
		if f.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width and line != "":
			out.append(line)
			line = word
		else:
			line = test
	if line != "":
		out.append(line)
	return out
