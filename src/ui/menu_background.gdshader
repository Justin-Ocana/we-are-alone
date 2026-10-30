shader_type canvas_item;
// Fondo animado de los menús (ADR-033): cielo estrellado con nebulosa tenue, la Tierra destruida en fragmentos
// (grietas de magma, restos girando) sobre el horizonte de la Luna. Todo procedural, sin texturas.

uniform vec2 size = vec2(1280.0, 720.0);
uniform float dim = 0.0;          // oscurece el fondo cuando hay un panel abierto (0..1)
uniform vec2 planet_pos = vec2(0.70, 0.40);
uniform float planet_r = 0.23;    // radio en unidades de altura de pantalla

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec3 hash33(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash33(i).x;
	float n100 = hash33(i + vec3(1, 0, 0)).x;
	float n010 = hash33(i + vec3(0, 1, 0)).x;
	float n110 = hash33(i + vec3(1, 1, 0)).x;
	float n001 = hash33(i + vec3(0, 0, 1)).x;
	float n101 = hash33(i + vec3(1, 0, 1)).x;
	float n011 = hash33(i + vec3(0, 1, 1)).x;
	float n111 = hash33(i + vec3(1, 1, 1)).x;
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y), mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm3(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * noise3(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

// Distancia al borde de la celda de Voronoi más cercana (grietas entre fragmentos) en 3D.
vec2 voronoi_edge(vec3 p) {
	vec3 ip = floor(p);
	vec3 fp = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int z = -1; z <= 1; z++)
	for (int y = -1; y <= 1; y++)
	for (int x = -1; x <= 1; x++) {
		vec3 g = vec3(float(x), float(y), float(z));
		vec3 o = hash33(ip + g);
		vec3 r = g + o - fp;
		float d = dot(r, r);
		if (d < d1) {
			d2 = d1;
			d1 = d;
			id = hash33(ip + g + 7.0).x;
		} else if (d < d2) {
			d2 = d;
		}
	}
	return vec2(sqrt(d2) - sqrt(d1), id);
}

vec3 rot_y(vec3 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

vec3 stars(vec2 uv, float t) {
	vec3 col = vec3(0.0);
	for (int l = 0; l < 3; l++) {
		float scale = 90.0 + float(l) * 110.0;
		vec2 p = uv * scale + vec2(t * (0.15 + 0.1 * float(l)), 0.0);
		vec2 cell = floor(p);
		vec2 f = fract(p) - 0.5;
		float h = hash21(cell + float(l) * 17.0);
		if (h > 0.93) {
			vec2 off = vec2(hash21(cell + 3.1), hash21(cell + 9.7)) - 0.5;
			float d = length(f - off * 0.7);
			float tw = 0.65 + 0.35 * sin(t * (1.0 + h * 3.0) + h * 40.0);
			float b = smoothstep(0.08, 0.0, d) * tw * (h - 0.93) * 14.0;
			vec3 tint = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.85, 0.7), hash21(cell + 1.3));
			col += tint * b;
		}
	}
	return col;
}

void fragment() {
	float t = TIME;
	vec2 px = UV * size;
	vec2 uv = px / size.y;                 // y en 0..1, x escalado por el aspecto
	float aspect = size.x / size.y;

	// --- Cielo: estrellas + nebulosa.
	vec3 col = vec3(0.004, 0.008, 0.02);
	float neb = noise3(vec3(uv * 2.2, t * 0.01)) * 0.6 + noise3(vec3(uv * 4.4, 3.0)) * 0.4;
	float neb2 = noise3(vec3(uv * 4.0 + 10.0, t * 0.015)) * 0.7 + noise3(vec3(uv * 9.0, 7.0)) * 0.3;
	col += vec3(0.05, 0.03, 0.11) * smoothstep(0.45, 0.85, neb) * 0.9;
	col += vec3(0.0, 0.06, 0.09) * smoothstep(0.55, 0.9, neb2) * 0.7;
	col += stars(uv, t);

	// --- La Tierra destruida.
	vec2 pc = vec2(planet_pos.x * aspect, planet_pos.y);
	vec2 q = (uv - pc) / planet_r;
	float r2 = dot(q, q);
	vec3 light = normalize(vec3(-0.55, 0.35, 0.75));
	// Halo de polvo y gas alrededor.
	float halo = exp(-max(sqrt(r2) - 1.0, 0.0) * 3.5);
	col += vec3(1.0, 0.45, 0.15) * 0.10 * halo * step(1.0, r2);
	col += vec3(0.25, 0.5, 1.0) * 0.06 * exp(-max(sqrt(r2) - 1.0, 0.0) * 9.0) * step(1.0, r2);
	if (r2 < 1.0) {
		vec3 n = vec3(q.x, -q.y, sqrt(1.0 - r2));
		vec3 sp = rot_y(n, t * 0.03);
		vec2 vo = voronoi_edge(sp * 1.55);
		float crack = smoothstep(0.075, 0.0, vo.x);
		float gap = smoothstep(0.03, 0.0, vo.x);
		float land = smoothstep(0.52, 0.58, fbm3(sp * 2.4 + 3.0));
		vec3 surf = mix(vec3(0.03, 0.10, 0.25), vec3(0.18, 0.22, 0.10), land);
		surf = mix(surf, vec3(0.32, 0.22, 0.14), smoothstep(0.62, 0.7, fbm3(sp * 5.0)) * land);
		// Fragmentos desplazados: cada celda con su propio tono y sombra en el borde (placas separadas).
		surf *= 0.8 + 0.35 * vo.y;
		surf *= 0.55 + 0.45 * smoothstep(0.0, 0.18, vo.x);
		float diff = clamp(dot(n, light), 0.0, 1.0);
		vec3 lit = surf * (0.05 + 1.1 * diff);
		// Nubes rotas.
		float cl = smoothstep(0.6, 0.8, fbm3(sp * 3.5 + vec3(t * 0.02, 0.0, 0.0)));
		lit = mix(lit, vec3(0.9) * (0.08 + diff), cl * 0.55 * (1.0 - crack));
		// Grietas de magma (brillan también en la cara nocturna) y huecos al espacio entre placas.
		float pulse = 0.8 + 0.2 * sin(t * 1.3 + vo.y * 20.0);
		lit = mix(lit, vec3(1.0, 0.36, 0.07) * 1.25 * pulse, crack * 0.7);
		// En el centro de la grieta se ve el espacio entre los fragmentos.
		lit = mix(lit, vec3(0.01, 0.005, 0.0), gap * 0.75);
		// Atmósfera (Fresnel) sólo del lado iluminado.
		float rim = pow(1.0 - n.z, 3.0);
		lit += vec3(0.25, 0.5, 1.0) * rim * (0.2 + diff) * 0.7;
		float edge = smoothstep(1.0, 0.985, r2);
		col = mix(col, lit, edge);
	}
	// Restos en órbita: puntos que giran alrededor del planeta (sólo se evalúan cerca de él).
	for (int i = 0; i < 26 && length(q) < 2.0; i++) {
		float fi = float(i);
		float ang = t * (0.05 + 0.03 * hash21(vec2(fi, 2.0))) + fi * 2.399;
		float rad = 1.15 + 0.6 * hash21(vec2(fi, 5.0));
		float incl = 0.35 + 0.2 * hash21(vec2(fi, 8.0));
		vec2 dpos = pc + planet_r * vec2(cos(ang) * rad, sin(ang) * rad * incl - 0.1);
		bool behind = sin(ang) < 0.0 && length((dpos - pc) / planet_r) < 1.0;
		float d = length(uv - dpos);
		float sz = planet_r * (0.012 + 0.02 * hash21(vec2(fi, 11.0)));
		float rock = smoothstep(sz, sz * 0.4, d);
		if (!behind) {
			col = mix(col, vec3(0.5, 0.42, 0.36) * (0.4 + 0.6 * hash21(vec2(fi, 13.0))), rock);
			col += vec3(1.0, 0.5, 0.2) * smoothstep(sz * 3.0, 0.0, d) * 0.08;
		}
	}

	// --- Horizonte lunar en primer plano (abajo).
	float hx = uv.x / aspect;
	float horizon = 0.80 + 0.035 * sin(hx * 5.0 + 1.0) + 0.02 * sin(hx * 13.0) + 0.012 * noise3(vec3(hx * 30.0, 0.0, 0.0));
	if (uv.y > horizon) {
		float depth = (uv.y - horizon) / (1.0 - horizon);
		float g = noise3(vec3(uv * vec2(14.0, 40.0), 1.0)) * 0.6 + noise3(vec3(uv * vec2(40.0, 120.0), 2.0)) * 0.4;
		float crater = smoothstep(0.62, 0.66, noise3(vec3(uv * 9.0, 4.0)));
		vec3 ground = vec3(0.10, 0.10, 0.11) * (0.55 + 0.6 * g) * (1.0 - 0.3 * crater);
		ground *= 0.55 + 0.45 * (1.0 - depth);
		// Luz rasante de la Tierra (rojiza por el magma) en el borde del horizonte.
		ground += vec3(0.35, 0.16, 0.08) * 0.25 * exp(-depth * 12.0);
		col = mix(col, ground, smoothstep(0.0, 0.004, uv.y - horizon));
	}

	// Viñeta y oscurecido del lado del menú (izquierda) para legibilidad.
	vec2 vc = UV - 0.5;
	col *= 1.0 - 0.55 * dot(vc, vc);
	col *= mix(1.0, 0.55, smoothstep(0.45, 0.0, UV.x) * 0.8);
	col *= 1.0 - dim * 0.55;
	COLOR = vec4(col, 1.0);
}
