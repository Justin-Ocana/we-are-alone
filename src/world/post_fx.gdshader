// Efectos de imagen (ronda 8, ADR-039/040), con el aspecto del menú principal:
// - Resplandor (bloom) propio: desenfoque de 12 muestras de lo más brillante. Funciona también dentro de la nave,
//   que se dibuja en otra capa sin el resplandor del entorno.
// - Etalonaje: sombras hacia el azul petróleo, luces altas cálidas (contraste frío/cálido del menú).
// - Destello del Sol (halo, veta horizontal y fantasmas de lente), aberración cromática leve en los bordes,
//   viñeta y grano fino animado. Una pasada a pantalla completa, por debajo de las interfaces.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec2 sun_uv = vec2(-10.0);
uniform float sun_amount = 0.0;
uniform vec3 sun_tint : source_color = vec3(1.0, 0.92, 0.8);
uniform float aspect = 1.7778;
uniform float grain = 0.028;
uniform float vignette = 0.38;
uniform float aberration = 0.0016;
uniform float bloom = 0.35;
uniform bool full = true;            // false (calidad media): una sola lectura, sin resplandor ni aberración
uniform float bloom_threshold = 0.9;
uniform vec3 shadow_tint : source_color = vec3(0.008, 0.014, 0.02);
uniform vec3 highlight_tint : source_color = vec3(1.0, 1.0, 1.0);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 bright(vec2 uv) {
	vec3 c = texture(screen_tex, uv).rgb;
	float l = max(c.r, max(c.g, c.b));
	return c * smoothstep(bloom_threshold, 1.0, l);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r = length(c * vec2(aspect, 1.0));
	vec3 col;
	if (full) {
		vec2 off = c * aberration * (0.4 + r * 1.6);
		col.r = texture(screen_tex, uv + off).r;
		col.g = texture(screen_tex, uv).g;
		col.b = texture(screen_tex, uv - off).b;
	} else {
		col = texture(screen_tex, uv).rgb;
	}
	// Resplandor: seis muestras en espiral.
	if (full && bloom > 0.001) {
		vec3 acc = vec3(0.0);
		// Seis muestras en espiral (radios de 0,8 % a 2,8 %): halo suave con la mitad de lecturas.
		for (int i = 0; i < 6; i++) {
			float a = float(i) * 2.399 + 0.3;
			float rr = 0.008 + 0.004 * float(i);
			acc += bright(uv + vec2(cos(a) / aspect, sin(a)) * rr);
		}
		col += acc / 6.0 * bloom;
	}
	if (sun_amount > 0.001) {
		vec2 ds = (uv - sun_uv) * vec2(aspect, 1.0);
		float d = length(ds);
		vec3 flare = sun_tint * exp(-d * 18.0) * 0.3;
		flare += sun_tint * exp(-abs(ds.y) * 140.0) * exp(-abs(ds.x) * 2.2) * 0.25;
		vec2 axis = vec2(0.5) - sun_uv;
		for (int i = 0; i < 5; i++) {
			float fi = float(i);
			float k = 0.45 + fi * 0.38;
			vec2 gp = sun_uv + axis * k * 2.0;
			float gd = length((uv - gp) * vec2(aspect, 1.0));
			float size = 0.025 + 0.03 * fract(fi * 0.618);
			float ring = smoothstep(size, size * 0.55, gd) * (0.6 + 0.4 * smoothstep(size * 0.4, size * 0.9, gd));
			vec3 gc = mix(vec3(1.0, 0.55, 0.25), vec3(0.35, 0.7, 1.0), fract(fi * 0.37));
			flare += gc * ring * 0.06;
		}
		col += flare * sun_amount;
	}
	// Etalonaje frío/cálido: las sombras reciben un poco de azul petróleo, las luces altas un tono cálido.
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col += shadow_tint * (1.0 - smoothstep(0.0, 0.35, lum));
	col = mix(col, col * highlight_tint, smoothstep(0.4, 1.0, lum));
	col *= 1.0 - vignette * smoothstep(0.45, 1.3, r);
	col += (hash12(uv * 1024.0 + fract(TIME * 7.3) * 113.0) - 0.5) * grain;
	COLOR = vec4(col, 1.0);
}
