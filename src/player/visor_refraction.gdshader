// Cristal curvo del visor: ligera distorsión y separación cromática que crecen hacia el borde de la
// abertura (como mirar a través de un visor esférico). Lee la imagen ya renderizada (hint_screen_texture,
// soportado en Compatibility). Se dibuja antes que el marco del casco.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float aspect = 1.7778;
uniform vec2 lag = vec2(0.0);
uniform float strength = 1.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 p = (uv - 0.5 - lag) * vec2(aspect, 1.0);
	float a = 0.5 * aspect * 1.05;
	float b = 0.53;
	float d = pow(abs(p.x / a), 3.0) + pow(abs((p.y + 0.03) / b), 3.0);
	float edge = smoothstep(0.35, 1.0, d);
	vec2 from_center = uv - 0.5;
	vec2 off = from_center * edge * edge * 0.016 * strength;   // magnifica levemente hacia el borde
	vec2 ca = from_center * edge * edge * 0.0045 * strength;    // dispersión cromática
	vec3 col;
	col.r = texture(screen_tex, uv - off + ca).r;
	col.g = texture(screen_tex, uv - off).g;
	col.b = texture(screen_tex, uv - off - ca).b;
	COLOR = vec4(col, 1.0);
}
