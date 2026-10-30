// Terreno planetario: color de vértice + textura de detalle cercana (desvanecida con la distancia).
// Compatible con el renderizador Compatibility. Las UV son coordenadas de tesela de la cara del
// cubo con periodo entero, calculadas en doble precisión en la CPU (no depende del origen flotante).
// Ronda 8 (ADR-039): el detalle también da RELIEVE (mapa de normales por derivadas de pantalla, Mikkelsen 2010):
// granos y piedrecitas se iluminan con el Sol rasante; una tercera escala fina y una variación grande rompen la
// repetición de la textura.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D detail_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float detail_strength = 0.30;
uniform float detail_fade_m = 220.0;
uniform float bump_strength = 0.035;   // m de relieve equivalente de la textura de detalle

varying float view_dist;

void vertex() {
	view_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	float fade = 1.0 - clamp(view_dist / detail_fade_m, 0.0, 1.0);
	float d1 = texture(detail_tex, UV).r;
	float d2 = texture(detail_tex, UV * 0.125).r;
	float d3 = texture(detail_tex, UV * 4.7 + vec2(0.37, 0.61)).r;
	float macro = texture(detail_tex, UV * 0.0153 + vec2(0.11, 0.73)).r;
	float detail = mix(d2, d1 * 0.75 + d3 * 0.25, fade);
	float k = mix(0.10, detail_strength, fade) * COLOR.a;  // alfa 0: parche sin UV de detalle
	vec3 col = COLOR.rgb * (1.0 - k + 2.0 * k * detail);
	col *= 0.9 + 0.2 * macro * COLOR.a;
	ALBEDO = col;
	ROUGHNESS = 1.0;
	// Relieve cercano: la altura es la propia textura de detalle (fina y media).
	float near = fade * fade * COLOR.a;
	if (near > 0.001) {
		float h = (d1 * 0.7 + d3 * 0.3) * bump_strength * near;
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		float dhdx = dFdx(h);
		float dhdy = dFdy(h);
		vec3 r1 = cross(dpdy, NORMAL);
		vec3 r2 = cross(NORMAL, dpdx);
		float det = dot(dpdx, r1);
		vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
		vec3 nb = abs(det) * NORMAL - grad;
		if (abs(det) > 1e-12 && dot(nb, nb) > 1e-24) {
			NORMAL = normalize(nb);
		}
	}
}
