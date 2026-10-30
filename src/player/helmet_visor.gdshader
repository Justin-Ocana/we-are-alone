// Interior del casco visto desde los ojos: abertura del visor (superelipse), acolchado oscuro en los
// bordes, borde metálico iluminado, tinte dorado muy leve y un reflejo tenue en el cristal.
// `lag` desplaza el marco al girar la cabeza (inercia del casco). Funciona en Compatibility.
shader_type canvas_item;

uniform vec2 lag = vec2(0.0);
uniform float aspect = 1.7778;
uniform vec3 padding_color : source_color = vec3(0.06, 0.06, 0.07);
uniform vec3 rim_color : source_color = vec3(0.55, 0.56, 0.6);
uniform vec3 tint : source_color = vec3(1.0, 0.86, 0.6);
uniform float tint_strength = 0.035;
uniform float light = 1.0;
uniform float auto_tint = 0.0;                  // oscurecimiento automático del visor (soldador)
uniform vec2 afterimage_uv = vec2(0.5);         // posición en la retina de la imagen residual del Sol
uniform float afterimage = 0.0;
uniform float focus = 0.0;                      // enfoque (clic derecho): estrecha un poco la visión

void fragment() {
	vec2 p = (UV - 0.5 - lag) * vec2(aspect, 1.0);
	float a = 0.5 * aspect * 1.05;
	float b = 0.53;
	float n = 3.0;
	float d = pow(abs(p.x / a), n) + pow(abs((p.y + 0.03) / b), n);
	d *= 1.0 + 0.10 * focus;
	float inside = 1.0 - smoothstep(0.86, 1.0, d);
	float rim = smoothstep(0.90, 0.985, d) * (1.0 - smoothstep(0.985, 1.06, d));
	float shade = smoothstep(1.0, 1.35, d);
	vec3 helmet = mix(rim_color * (0.35 + 0.65 * light) * (0.6 + 0.4 * (0.5 - p.y)), padding_color, shade);
	float helmet_a = 1.0 - inside;
	// Cristal: tinte dorado y un reflejo diagonal suave en la parte superior.
	float streak = smoothstep(0.035, 0.0, abs(p.x * 0.45 + p.y - 0.33)) * smoothstep(0.1, 0.45, p.y) * 0.06;
	vec3 glass = mix(tint, vec3(0.22, 0.15, 0.04), auto_tint);
	float glass_a = inside * (tint_strength + streak + auto_tint * 0.55);
	vec3 col = mix(glass, helmet, helmet_a);
	float alpha = max(helmet_a * (0.6 + 0.4 * max(rim, shade)), glass_a);
	// Imagen residual (negativa) tras mirar el Sol: mancha oscura azulada fija en la retina.
	vec2 q = (UV - afterimage_uv) * vec2(aspect, 1.0);
	float ai = afterimage * exp(-dot(q, q) * 160.0);
	col = mix(col, vec3(0.08, 0.12, 0.22), clamp(ai, 0.0, 1.0));
	alpha = max(alpha, ai * 0.65);
	COLOR = vec4(col, alpha);
}
