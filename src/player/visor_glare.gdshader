// Brillo del Sol en el visor (aditivo): halo, destello horizontal por la curvatura del cristal y
// "fantasmas" reflejados en la línea Sol–centro. Se atenúa con el oscurecimiento automático del visor.
shader_type canvas_item;
render_mode blend_add;

uniform vec2 sun_uv = vec2(0.5);
uniform float sun_vis = 0.0;     // 0..1: Sol delante, en pantalla y no tapado
uniform float aspect = 1.7778;
uniform float tint = 0.0;        // oscurecimiento automático del visor (0..1)

void fragment() {
	vec2 p = (UV - sun_uv) * vec2(aspect, 1.0);
	float r = length(p);
	float glow = exp(-r * 5.0) * 0.45 + exp(-r * 22.0) * 0.9;
	float streak = exp(-abs(p.y) * 70.0) * exp(-abs(p.x) * 1.8) * 0.45;
	vec3 ghosts = vec3(0.0);
	for (int i = 1; i <= 3; i++) {
		float t = float(i) * 0.6;
		vec2 g = mix(sun_uv, vec2(0.5), 1.0 + t);
		float gr = length((UV - g) * vec2(aspect, 1.0));
		float size = 0.07 / float(i) + 0.02;
		ghosts += vec3(0.95, 0.65, 0.35) * smoothstep(size, size * 0.6, gr) * 0.06;
	}
	vec3 col = vec3(1.0, 0.93, 0.78) * (glow + streak) + ghosts;
	COLOR = vec4(col * sun_vis * (1.0 - 0.8 * tint), 1.0);
}
