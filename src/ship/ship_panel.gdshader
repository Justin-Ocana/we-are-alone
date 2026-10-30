// Material procedural de la nave (ronda 8, ADR-039): chapa con paneles irregulares (cada panel se parte en
// placas de distinto tamaño), juntas con relieve real (mapa de normales por derivadas de pantalla), remaches junto a
// las juntas, suciedad acumulada en las juntas y en la parte baja, chorretones verticales, hollín cerca de las
// toberas (exterior), desgaste en los cantos y variación de rugosidad por placa. Suelos: chapa estriada o rejilla.
// Coordenadas triplanares en el espacio local de la nave: estable aunque la nave se mueva. Sin texturas.
shader_type spatial;
render_mode diffuse_burley;

uniform vec3 albedo : source_color = vec3(0.8);
uniform float panel = 1.2;          // tamaño de panel (m)
uniform float line_dark = 0.35;
uniform float line_width = 0.025;   // m
uniform float roughness_value = 0.7;
uniform float metallic_value = 0.0;
uniform float grate = 0.0;          // 1 = suelo: chapa estriada con rejilla
uniform float variation = 0.06;
uniform float bevel = 1.0;          // relieve de las juntas
uniform float grime = 0.35;         // suciedad (0..1)
uniform float wear = 0.25;          // desgaste de la pintura (0..1)
uniform float rivets = 1.0;         // 1 = remaches junto a las juntas
uniform float exterior = 0.0;       // 1 = casco exterior (hollín de las toberas, chorretones)
uniform bool high_detail = true;
uniform float fill = 0.0;          // luz de relleno propia (base LF-01: sin ambiente, las caras en sombra no son negras)    // calidad media: una sola capa de ruido y detalle fino sólo de cerca (ronda 9)

varying vec3 lp;
varying vec3 ln;
varying float vdist;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

float fbm2(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.13 + 7.1) * 0.3 + vnoise(p * 4.37 + 3.3) * 0.15;
}

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	vdist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	vec3 an = abs(normalize(ln));
	vec2 uv = (an.x > an.y && an.x > an.z) ? lp.zy : ((an.y > an.z) ? lp.xz : lp.xy);
	// --- Paneles irregulares: cada celda se divide (o no) en dos placas, en una dirección al azar.
	vec2 cell = floor(uv / panel);
	vec2 f = fract(uv / panel);
	float hc = hash12(cell);
	float split = hash12(cell + 17.3);
	vec2 sub_id = cell;
	vec2 dist2 = min(f, 1.0 - f) * panel;            // distancia a los bordes de la celda (m)
	if (split > 0.45) {
		float cut = 0.35 + 0.3 * hash12(cell + 5.1);
		if (hc > 0.5) {
			dist2.x = min(dist2.x, abs(f.x - cut) * panel);
			sub_id += vec2(step(cut, f.x) * 0.5, 0.0);
		} else {
			dist2.y = min(dist2.y, abs(f.y - cut) * panel);
			sub_id += vec2(0.0, step(cut, f.y) * 0.5);
		}
	}
	float d = min(dist2.x, dist2.y);
	// Antialiasing (ronda 10): metros por píxel. Si las juntas o los remaches son más finos que un par de píxeles
	// se desvanecen; antes, de lejos, formaban una cuadrícula de moiré sobre el casco.
	float mpp = max(length(fwidth(uv)), 1e-6);
	float detail = 1.0 - smoothstep(line_width * 0.5, line_width * 2.5, mpp);
	float groove = (1.0 - smoothstep(line_width * 0.4, line_width * 1.4, d)) * detail;   // fondo de la junta
	float lip = smoothstep(line_width * 1.2, line_width * 3.5, d);                       // borde redondeado de la placa
	float height = (lip - groove * 0.6) * detail;
	// --- Remaches: en las esquinas y a lo largo de las juntas, a 8 cm de ellas.
	float rivet = 0.0;
	float near_k = high_detail ? 1.0 : 1.0 - smoothstep(4.0, 8.0, vdist);
	if (rivets > 0.5 && grate < 0.5 && near_k > 0.01) {
		float sp = 0.18;
		vec2 q = uv / sp;
		vec2 rq = abs(fract(q) - 0.5) * sp;
		float near_seam = 1.0 - smoothstep(0.06, 0.11, d);
		float on_line = smoothstep(0.045, 0.07, d);
		rivet = (1.0 - smoothstep(0.008, 0.016, length(rq))) * near_seam * on_line * near_k
			* (1.0 - smoothstep(0.004, 0.012, mpp));
		height += rivet * 0.5;
	}
	// --- Suelo: chapa estriada (diamantes en relieve) y rejilla oscura.
	float shade_grate = 1.0;
	if (grate > 0.5) {
		vec2 gq = uv * 6.0;
		vec2 dg = abs(fract(vec2(gq.x + gq.y, gq.x - gq.y) * 0.7071) - 0.5);
		float diamond = 1.0 - smoothstep(0.08, 0.16, min(dg.x, dg.y));
		height += diamond * 0.35 * (1.0 - smoothstep(0.01, 0.04, mpp));
		vec2 gg = abs(fract(uv * 5.0) - 0.5);
		shade_grate = 0.85 + 0.15 * step(0.12, min(gg.x, gg.y));
	}
	// --- Relieve: mapa de normales a partir de la altura (derivadas de pantalla; Mikkelsen 2010).
	float bump_k = bevel * 0.012;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhdx = dFdx(height);
	float dhdy = dFdy(height);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
	vec3 nb = abs(det) * NORMAL - bump_k * grad;
	// De canto (det ≈ 0) la normal quedaba indefinida: píxeles negros o parpadeantes. Sólo se aplica si es válida.
	if (abs(det) > 1e-12 && dot(nb, nb) > 1e-24) {
		NORMAL = normalize(nb);
	}
	// --- Color: variación por placa, suciedad, chorretones, hollín y desgaste.
	float hp = hash12(sub_id * 3.7);
	vec3 col = albedo * (1.0 - variation + 2.0 * variation * hp);
	col *= 1.0 - groove * line_dark;
	col *= shade_grate;
	float n_big = 0.5;
	float n_fine = 0.5;
	if (grime > 0.001 || wear > 0.001) {
		if (high_detail) {
			n_big = fbm2(uv * 0.35 + vec2(hc * 13.0));
			n_fine = vnoise(uv * 9.0);
		} else {
			n_big = vnoise(uv * 0.35 + vec2(hc * 13.0));
			n_fine = near_k > 0.01 ? vnoise(uv * 9.0) : 0.5;
		}
	}
	float dirt = grime * (0.5 * (1.0 - smoothstep(0.0, 0.12, d)) + 0.35 * smoothstep(0.45, 0.85, n_big));
	if (exterior > 0.5) {
		// Chorretones verticales bajo las juntas horizontales y en la mitad inferior del casco.
		float streak = smoothstep(0.55, 0.9, vnoise(vec2(uv.x * 7.0, lp.y * 0.6))) * clamp(1.6 - lp.y * 0.35, 0.0, 1.0);
		dirt += grime * 0.3 * streak;
		// Hollín junto a las toberas de popa.
		float soot = smoothstep(17.0, 24.5, lp.z) * (0.55 + 0.45 * n_big);
		col = mix(col, vec3(0.06, 0.055, 0.05), clamp(soot * 0.65, 0.0, 0.8));
	}
	col *= 1.0 - clamp(dirt, 0.0, 0.7) * 0.45;
	// Desgaste: la pintura salta en los cantos de las placas y muestra el metal (más claro y metálico).
	float chip = wear * smoothstep(0.62, 0.8, n_fine * 0.6 + n_big * 0.6) * (1.0 - smoothstep(0.0, 0.09, d));
	col = mix(col, vec3(0.55, 0.56, 0.58), clamp(chip, 0.0, 1.0));
	col = mix(col, col * 1.35, rivet * 0.6);
	ALBEDO = col;
	ROUGHNESS = clamp(roughness_value + (hp - 0.5) * 0.18 + dirt * 0.25 - chip * 0.25 - rivet * 0.2, 0.05, 1.0);
	METALLIC = clamp(metallic_value + chip * 0.5 + rivet * 0.4, 0.0, 1.0);
	EMISSION = col * fill;
}
