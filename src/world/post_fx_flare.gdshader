// Destello del Sol aditivo de la versión ligera (generado a partir de post_fx_light.gdshader): sin leer la pantalla (esa copia completa era cara en gráficos
// integrados). Viñeta y grano como capa que oscurece; el destello del Sol va en otra capa aditiva.
shader_type canvas_item;
render_mode blend_add;   // copia aditiva para el destello (post_fx_flare)

uniform float aspect = 1.7778;
uniform float grain = 0.05;
uniform float vignette = 0.38;
uniform bool flare_pass = false;
uniform vec2 sun_uv = vec2(-10.0);
uniform float sun_amount = 0.0;
uniform vec3 sun_tint : source_color = vec3(1.0, 0.92, 0.8);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	if (flare_pass) {
		vec3 flare = vec3(0.0);
		if (sun_amount > 0.001) {
			vec2 ds = (uv - sun_uv) * vec2(aspect, 1.0);
			float d = length(ds);
			flare = sun_tint * exp(-d * 18.0) * 0.3;
			flare += sun_tint * exp(-abs(ds.y) * 140.0) * exp(-abs(ds.x) * 2.2) * 0.25;
			vec2 axis = vec2(0.5) - sun_uv;
			for (int i = 0; i < 4; i++) {
				float fi = float(i);
				vec2 gp = sun_uv + axis * (0.45 + fi * 0.45) * 2.0;
				float gd = length((uv - gp) * vec2(aspect, 1.0));
				float size = 0.025 + 0.03 * fract(fi * 0.618);
				flare += mix(vec3(1.0, 0.55, 0.25), vec3(0.35, 0.7, 1.0), fract(fi * 0.37)) * smoothstep(size, size * 0.55, gd) * 0.06;
			}
			flare *= sun_amount;
		}
		COLOR = vec4(flare, 1.0);
	} else {
		float r = length(c * vec2(aspect, 1.0));
		float dark = vignette * smoothstep(0.45, 1.3, r);
		dark += (hash12(uv * 1024.0 + fract(TIME * 7.3) * 113.0) - 0.5) * grain;
		COLOR = vec4(0.0, 0.0, 0.0, clamp(dark, 0.0, 1.0));
	}
}
