// Efectos de pantalla del astronauta (ADR-019): destello rojo al recibir daño, viñeta pulsante y
// desaturación con poca salud, visión doble y viñeta al marearse, y túnel/fundido a negro al desmayarse.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float damage = 0.0;
uniform float low_health = 0.0;
uniform float blackout = 0.0;
uniform float dizzy = 0.0;
uniform float aspect = 1.7778;
uniform float plasma = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = (uv - 0.5) * vec2(aspect, 1.0);
	float r = length(c);
	vec3 col = texture(screen_tex, uv).rgb;
	if (dizzy > 0.001) {
		vec2 off = vec2(sin(TIME * 1.7), cos(TIME * 1.3)) * 0.012 * dizzy;
		vec3 ghost = texture(screen_tex, uv + off).rgb;
		col = mix(col, ghost, 0.45 * dizzy);
		col *= 1.0 - smoothstep(0.35, 1.0, r) * (0.55 + 0.25 * sin(TIME * 2.0)) * dizzy;
	}
	float edge = smoothstep(0.3, 1.05, r);
	float pulse = 0.75 + 0.25 * sin(TIME * 5.5);
	col = mix(col, vec3(0.55, 0.02, 0.0), clamp(edge * (damage * 0.85 + low_health * 0.5 * pulse), 0.0, 0.9));
	// Plasma de entrada: resplandor anaranjado parpadeante en los bordes (la nave atraviesa aire a gran velocidad).
	col = mix(col, vec3(1.0, 0.5, 0.15) * (0.8 + 0.4 * sin(TIME * 37.0 + uv.x * 40.0)), clamp(edge * plasma * 0.65, 0.0, 0.8));
	float g = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(g), low_health * 0.5);
	// Desmayo: la visión se cierra desde los bordes y después todo queda a negro.
	float tunnel = smoothstep(1.2 - blackout * 1.5, 1.25 - blackout * 1.2, r);
	col *= (1.0 - tunnel) * (1.0 - smoothstep(0.6, 1.0, blackout));
	COLOR = vec4(col, 1.0);
}
