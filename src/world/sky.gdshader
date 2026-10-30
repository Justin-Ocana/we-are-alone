// Cielo del Sistema Solar (ADR-024/025). Dibuja de forma ANALÍTICA (trazado de rayos por píxel) todos los
// cuerpos lejanos a su tamaño angular real: el Sol (disco con oscurecimiento al limbo y corona), planetas y
// lunas con fase, bandas, tormentas, achatamiento, limbo atmosférico y anillos con la sombra del planeta.
// Los cuerpos menores que un píxel se dibujan como puntos con su magnitud aparente.
// También el cielo desde dentro de una atmósfera (colores del JSON) y el interior de un gigante gaseoso.
// Las magnitudes llegan relativas a la cámara y calculadas en doble precisión en GDScript (SystemSky).
shader_type sky;

const int MAX_BODIES = 24;
const int MAX_RINGS = 6;
const int MAX_STORMS = 4;

uniform vec3 local_up = vec3(0.0, 1.0, 0.0);
uniform float atmosphere_density = 0.0;      // atmósfera en la que está la cámara (0 = ninguna)
uniform float altitude_factor = 1.0;
uniform vec3 atmosphere_color : source_color = vec3(0.62, 0.55, 0.48);
uniform vec3 zenith_color : source_color = vec3(0.3, 0.3, 0.35);
uniform vec3 sunset_color : source_color = vec3(0.9, 0.45, 0.2);
uniform float sun_visibility = 1.0;          // 0 en Venus/Titán: el disco no se ve desde el suelo
uniform float star_density = 0.9975;
uniform float time = 0.0;
uniform float pixel_angle = 0.0015;          // radianes por píxel (FOV / alto de la ventana)

// Interior de un gigante gaseoso (0 = fuera): color y densidad de la capa actual, rayos.
uniform float deep_amount = 0.0;
uniform vec3 deep_color : source_color = vec3(0.4, 0.3, 0.2);
uniform float lightning = 0.0;

uniform int body_count = 0;
uniform vec4 b_dir[MAX_BODIES];     // xyz: dirección cámara→centro; w: radio angular (rad)
uniform vec4 b_geo[MAX_BODIES];     // x: radio (m), y: altitud de la cámara sobre la esfera (m), z: achatamiento, w: tipo
uniform vec4 b_col[MAX_BODIES];     // rgb: color; w: brillo del punto (si es menor que un píxel)
uniform vec4 b_col2[MAX_BODIES];    // rgb: color secundario; w: número de bandas
uniform vec4 b_pole[MAX_BODIES];    // xyz: polo; w: turbulencia
uniform vec4 b_pm[MAX_BODIES];      // xyz: meridiano 0; w: contraste de bandas
uniform vec4 b_sun[MAX_BODIES];     // xyz: dirección cuerpo→Sol; w: espesor relativo de la atmósfera
uniform vec4 b_atm[MAX_BODIES];     // rgb: color del limbo; w: intensidad

uniform int ring_body = -1;
uniform float ring_outer = 0.0;     // radio exterior del sistema de anillos (m): amplía el área a trazar
uniform vec4 ring_a[MAX_RINGS];     // x: radio interior (m), y: exterior (m), z: opacidad
uniform vec4 ring_c[MAX_RINGS];     // rgb: color
uniform int storm_count = 0;
uniform vec4 storm_a[MAX_STORMS];   // x: índice de cuerpo, y: latitud, z: longitud (rad), w: semiancho (rad)
uniform vec4 storm_b[MAX_STORMS];   // rgb: color, w: semialto (rad)
uniform float hexagon_body = -1.0;
uniform vec4 hexagon = vec4(0.0);   // x: colatitud del borde (rad), rgb en hexagon_color
uniform vec3 hexagon_color : source_color = vec3(0.45, 0.55, 0.6);

// Tierra destruida (ADR-026): fragmentos de una esfera partida por celdas de Voronoi.
uniform int shatter_body = -1;
uniform vec4 debris_dir[28];
uniform vec4 debris_group[4];
uniform float debris_cos = 0.9999;
uniform vec4 frag_sw[12];
uniform int frag_count = 0;
uniform vec4 frag_seed[12];         // xyz: semilla (dirección de la celda, marco del cuerpo); w: desplazamiento (radios)
uniform vec4 frag_rot[12];          // cuaternión de volteo de cada fragmento
uniform sampler2D land_mask : filter_linear, repeat_enable;
uniform float core_fraction = 0.33;
// Cielo profundo (ronda 8, ADR-040): giro del marco del cuerpo a la eclíptica (las estrellas giran con el cielo
// real) y la Vía Láctea con su orientación real (polo y centro galácticos en coordenadas eclípticas J2000).
uniform mat3 sky_basis = mat3(1.0);
uniform float milky_way = 2.4;
uniform sampler2D milky_tex : source_color, filter_linear, repeat_enable;
const vec3 GAL_POLE = vec3(-0.8676, -0.0003, 0.4971);
const vec3 GAL_CENTER = vec3(-0.0548, -0.9939, -0.0965);

float day_factor(float sun_h) {
	return clamp(sun_h * 3.0 + 0.25, 0.0, 1.0);
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1, 0, 0));
	float n010 = hash13(i + vec3(0, 1, 0));
	float n110 = hash13(i + vec3(1, 1, 0));
	float n001 = hash13(i + vec3(0, 0, 1));
	float n101 = hash13(i + vec3(1, 0, 1));
	float n011 = hash13(i + vec3(0, 1, 1));
	float n111 = hash13(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y), mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

float fbm3o(vec3 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.03 + 5.1) * 0.3 + vnoise(p * 4.1 + 9.7) * 0.15;
}

// Vía Láctea: textura equirectangular precalculada en la eclíptica (tools/gen_sky_tex.py; una sola lectura en
// lugar de varias capas de ruido por píxel, ronda 9). Guardada ×4 para aprovechar los 8 bits.
vec3 milky(vec3 e) {
	if (milky_way <= 0.0) {
		return vec3(0.0);
	}
	vec2 uv = vec2(atan(e.y, e.x) / TAU + 0.5, acos(clamp(e.z, -1.0, 1.0)) / PI);
	return textureLod(milky_tex, uv, 0.0).rgb * (0.25 * milky_way);
}

// Grietas de magma en la superficie de la Tierra rota: bordes de celdas de Voronoi en 3D.
// Ronda 10: vecindad de 2×2×2 celdas (la mitad más cercana en cada eje) y un hash vectorial: 8 celdas en lugar de 27
// y un hash por celda en lugar de tres. Con la Tierra llenando la pantalla era lo más caro del cielo.
vec3 hash33(vec3 p3) {
	p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yxx) * p3.zyx);
}

float crack_edge(vec3 p) {
	vec3 ip = floor(p);
	vec3 fp = fract(p);
	vec3 base = step(0.5, fp) - 1.0;   // celda inicial: −1 o 0 en cada eje, según la mitad en la que cae el punto
	float d1 = 8.0;
	float d2 = 8.0;
	for (int z = 0; z <= 1; z++)
	for (int y = 0; y <= 1; y++)
	for (int x = 0; x <= 1; x++) {
		vec3 g = base + vec3(float(x), float(y), float(z));
		vec3 r = g + hash33(ip + g) - fp;
		float dd = dot(r, r);
		if (dd < d1) { d2 = d1; d1 = dd; } else if (dd < d2) { d2 = dd; }
	}
	return sqrt(d2) - sqrt(d1);
}

vec3 stars(vec3 d) {
	vec3 c = d * 420.0;
	vec3 cell = floor(c);
	float h = hash13(cell);
	// Más estrellas en la banda de la Vía Láctea.
	float gb = dot(d, GAL_POLE);
	float dens_thr = star_density - 0.0018 * exp(-gb * gb / (2.0 * 0.15 * 0.15));
	if (h < dens_thr) {
		return vec3(0.0);
	}
	vec3 center = cell + vec3(hash13(cell + 1.7), hash13(cell + 5.3), hash13(cell + 9.1));
	float dist = length(c - center);
	float b = smoothstep(0.6, 0.0, dist) * (h - dens_thr) / (1.0 - dens_thr);
	float t = hash13(cell + 3.3);
	// Colores de las estrellas por temperatura: rojizas, amarillas, blancas y azuladas.
	vec3 tint = t < 0.15 ? vec3(1.0, 0.62, 0.45) : (t < 0.45 ? vec3(1.0, 0.88, 0.7) : (t < 0.8 ? vec3(0.95, 0.95, 1.0) : vec3(0.68, 0.8, 1.0)));
	float tw = 0.85 + 0.15 * sin(time * (2.0 + 5.0 * hash13(cell + 8.8)) + h * 50.0);
	return tint * b * 1.8 * tw;
}

vec3 qrot(vec4 q, vec3 v) {
	return v + 2.0 * cross(q.xyz, cross(q.xyz, v) + q.w * v);
}

// Intersección rayo-esfera estable con la altitud h (distancia al centro − R) calculada en doble precisión.
// d: rayo unitario; oc: cámara − centro (=-dir·dist). Devuelve t de entrada (o -1).
float sphere_hit(vec3 d, vec3 dir, float dist, float r, float h) {
	float b = -dist * dot(d, dir);
	float c = h * (h + 2.0 * r);
	float disc = b * b - c;
	if (disc < 0.0) {
		return -1.0;
	}
	float s = sqrt(disc);
	if (c > 0.0) {
		// Fuera de la esfera: sólo vale si el rayo va hacia ella (b < 0). Forma estable: t = c / (−b + s).
		if (b >= 0.0) {
			return -1.0;
		}
		return c / (-b + s);
	}
	return -b + s;  // dentro: salida
}

// Color de la superficie de un cuerpo en el punto unitario n (marco del cuerpo: y = polo).
vec3 surface_color(int i, vec3 nb, float lat, float lon) {
	float kind = b_geo[i].w;
	vec3 c1 = b_col[i].rgb;
	vec3 c2 = b_col2[i].rgb;
	if (kind > 0.5 && kind < 1.5) {
		// Gigante gaseoso: bandas por latitud con turbulencia y rotación diferencial suave.
		float bands = b_col2[i].w;
		float turb = b_pole[i].w;
		// Ruido 3D sobre (x, z) del ecuador: continuo en longitud (sin costura en ±180°).
		float wob = fbm(vec3(nb.x * 5.0 + time * 0.002 * sin(lat * 7.0), lat * 30.0, nb.z * 5.0 + 1.7 * float(i))) - 0.5;
		// Cada banda con su propio tono (zonas claras / cinturones oscuros de intensidad variable).
		float bl = lat * bands / PI + wob * turb * 0.9;
		float band_id = floor(bl);
		float frac_b = fract(bl);
		float tone = hash13(vec3(band_id, float(i), 7.0));
		float edge = smoothstep(0.0, 0.18, frac_b) * smoothstep(1.0, 0.82, frac_b);
		float k = (mod(band_id, 2.0) < 0.5 ? tone * 0.45 : 0.55 + tone * 0.45) * b_pm[i].w;
		vec3 c = mix(c1, c2, k);
		c = mix(c, c * 0.92 + vec3(0.04, 0.02, 0.0), (1.0 - edge) * 0.5);
		c *= 0.9 + 0.2 * fbm(vec3(nb.x * 18.0, lat * 60.0, nb.z * 18.0 + float(i)));
		// Remolinos finos en los bordes de las bandas.
		c = mix(c, c1 * 1.08, smoothstep(0.62, 0.8, fbm(vec3(nb.x * 40.0, lat * 120.0, nb.z * 40.0))) * 0.35 * turb);
		for (int s = 0; s < MAX_STORMS; s++) {
			if (s >= storm_count) {
				break;
			}
			if (int(storm_a[s].x + 0.5) != i) {
				continue;
			}
			float dl = (lon - storm_a[s].z);
			dl = mod(dl + PI, TAU) - PI;
			vec2 e = vec2(dl * cos(lat) / storm_a[s].w, (lat - storm_a[s].y) / storm_b[s].w);
			float rr = length(e);
			float swirl = fbm(vec3(e * 3.0 + vec2(time * 0.01, 0.0), 3.0));
			c = mix(c, storm_b[s].rgb * (0.85 + 0.3 * swirl), smoothstep(1.05, 0.75, rr));
			c = mix(c, c1 * 1.05, smoothstep(1.3, 1.05, rr) * smoothstep(0.95, 1.05, rr) * 0.6);
		}
		if (float(i) == hexagon_body) {
			float colat = PI * 0.5 - lat;
			float ang = mod(lon + PI / 6.0, PI / 3.0) - PI / 6.0;
			float edge = hexagon.x * cos(PI / 6.0) / cos(ang);
			c = mix(c, hexagon_color, smoothstep(edge * 1.02, edge * 0.97, colat));
			c = mix(c, hexagon_color * 0.55, smoothstep(0.06, 0.02, colat));
		}
		return c;
	}
	if (kind > 2.5) {
		// Nubes (Venus, Titán): suaves con remolinos en "Y".
		float w = fbm(vec3(nb.x * 3.0 + time * 0.003, lat * 8.0, nb.z * 3.0));
		return mix(c1, c2, w * 0.6);
	}
	// Rocoso/helado: manchas de albedo (mares, regiones) y cráteres suaves; casquetes polares si los hay.
	float m = fbm(nb * 3.0 + vec3(float(i) * 7.1));
	float m2 = fbm(nb * 14.0 + vec3(float(i) * 3.3));
	vec3 c = mix(c1, c2, smoothstep(0.42, 0.62, m));
	c *= 0.85 + 0.3 * m2;
	if (b_atm[i].w > 0.5 && abs(lat) > 1.30) {
		c = mix(c, vec3(0.92), smoothstep(1.30, 1.36, abs(lat)));
	}
	return c;
}

// Fragmentos de la Tierra: devuelve t y color (rgba, a = 1 si hay impacto).
vec4 shattered(int i, vec3 d, out float t_hit) {
	t_hit = -1.0;
	vec3 dir = b_dir[i].xyz;
	float dist = b_geo[i].y + b_geo[i].x;
	float r = b_geo[i].x;
	vec3 center = dir * dist;     // centro relativo a la cámara (m)
	vec3 pole = b_pole[i].xyz;
	vec3 pm = b_pm[i].xyz;
	vec3 east = cross(pole, pm);
	vec4 best = vec4(0.0);
	float best_t = 1e30;
	int hit_f = -1;
	bool hit_outer = true;
	vec3 hit_n0 = vec3(0.0);
	vec3 hit_p = vec3(0.0);
	vec4 hit_q = vec4(0.0, 0.0, 0.0, 1.0);
	// Núcleo al rojo vivo.
	{
		float rc = r * core_fraction;
		vec3 oc = -center;
		float b = dot(d, oc);
		float c = dot(oc, oc) - rc * rc;
		float disc = b * b - c;
		if (disc > 0.0 && b < 0.0) {
			float t = -b - sqrt(disc);
			if (t > 0.0 && t < best_t) {
				vec3 n = normalize(oc + d * t);
				float glow = 0.75 + 0.25 * fbm(n * 6.0 + vec3(time * 0.02));
				best = vec4(vec3(1.6, 0.55, 0.12) * glow, 1.0);
				best_t = t;
			}
		}
	}
	for (int f = 0; f < 12; f++) {
		if (f >= frag_count) {
			break;
		}
		vec4 q = frag_rot[f];
		vec3 sw = frag_sw[f].xyz;
		// Origen del fragmento: su centroide (≈0,6 R hacia fuera) desplazado por la explosión; gira sobre él.
		vec3 fc = center + sw * r * (frag_seed[f].w + 0.6);
		// Rayo en el marco del fragmento (rotación inversa del volteo).
		vec4 qi = vec4(-q.xyz, q.w);
		vec3 ro = qrot(qi, -fc);
		vec3 rd = qrot(qi, d);
		// Esfera original (centrada en −sw·r·w respecto al centro del fragmento).
		vec3 sc = -sw * r * 0.6;
		vec3 oc = ro - sc;
		float b = dot(rd, oc);
		float c = dot(oc, oc) - r * r;
		float disc = b * b - c;
		if (disc <= 0.0) {
			continue;
		}
		float sq = sqrt(disc);
		float t0 = -b - sq;
		float t1 = -b + sq;
		vec3 n0 = vec3(0.0);
		bool outer = true;
		// Recorte por los planos de Voronoi (pasan por el centro original): dot(p − sc, s_f − s_g) ≥ 0.
		for (int g = 0; g < 12; g++) {
			if (g >= frag_count || g == f) {
				continue;
			}
			vec3 pn = sw - frag_sw[g].xyz;   // sin normalizar: el corte t = num/denom no depende de su longitud
			float denom = dot(rd, pn);
			float num = -dot(oc, pn);
			if (abs(denom) < 1e-12) {
				if (num > 0.0) { t0 = 1e30; }
				continue;
			}
			float tp = num / denom;
			if (denom > 0.0) {
				if (tp > t0) { t0 = tp; n0 = -pn; outer = false; }
			} else {
				t1 = min(t1, tp);
			}
		}
		if (t0 > t1 || t1 < 0.0 || t0 > best_t) {
			continue;
		}
		// Sólo se recuerda el más cercano; se sombrea UNA vez al final (ronda 10: antes se sombreaba cada fragmento
		// que tapaba al anterior, con ruido y grietas caros, y de cerca la Tierra llenaba la pantalla).
		hit_f = f;
		hit_outer = outer;
		hit_n0 = n0;
		hit_p = oc + rd * t0;
		hit_q = q;
		best_t = t0;
	}
	if (hit_f >= 0) {
		vec4 q = hit_q;
		vec4 qi = vec4(-q.xyz, q.w);
		vec3 p = hit_p;
		bool outer = hit_outer;
		float pr = length(p);
		vec3 col;
		vec3 n;
		vec3 emit = vec3(0.0);
		if (outer) {
			n = p / pr;
			// Superficie terrestre reconocible: máscara de continentes (lat/lon) con relieve.
			vec3 nb = vec3(dot(n, qrot(qi, east)), dot(n, qrot(qi, pole)), dot(n, qrot(qi, pm)));
			float lat = asin(clamp(nb.y, -1.0, 1.0));
			float lon = atan(nb.x, nb.z);
			float land = texture(land_mask, vec2(lon / TAU + 0.5, 0.5 - lat / PI)).r;
			float rough = fbm3o(nb * 18.0);
			vec3 ground = mix(vec3(0.42, 0.36, 0.26), vec3(0.24, 0.30, 0.16), smoothstep(0.4, 0.7, fbm3o(nb * 7.0)));
			vec3 seabed = mix(vec3(0.16, 0.20, 0.26), vec3(0.28, 0.27, 0.25), rough);
			col = mix(seabed, ground, smoothstep(0.35, 0.65, land)) * (0.8 + 0.4 * rough);
			if (abs(lat) > 1.2) { col = mix(col, vec3(0.85, 0.87, 0.9), 0.6); }
			// Red de grietas de magma: Voronoi grande y, de detalle, una cresta de ruido (antes un segundo Voronoi 3D
			// de 27 celdas, lo más caro del cielo).
			float ce = crack_edge(nb * 5.0);
			float ridge = abs(vnoise(nb * 14.0 + 4.0) - 0.5);
			emit = vec3(1.4, 0.42, 0.07) * (smoothstep(0.07, 0.0, ce) * 0.9 + smoothstep(0.035, 0.0, ridge) * 0.3)
				* (0.75 + 0.25 * sin(time * 0.9 + rough * 12.0));
		} else {
			n = normalize(hit_n0);
			// Cara de rotura: corteza, manto y magma hacia el interior.
			float depth = 1.0 - pr / r;
			vec3 crust = vec3(0.30, 0.26, 0.22);
			vec3 mantle = vec3(0.45, 0.20, 0.10);
			col = mix(crust, mantle, smoothstep(0.02, 0.25, depth));
			float fn = fbm3o(p / r * 25.0);
			col *= 0.7 + 0.5 * fn;
			col += vec3(1.4, 0.45, 0.08) * smoothstep(0.35, 0.6, depth) * (0.6 + 0.4 * fn);
		}
		vec3 nw = qrot(q, n);
		float lit = max(dot(nw, b_sun[i].xyz), 0.0);
		best = vec4(col * (0.03 + 0.97 * lit) + emit, 1.0);
		if (!outer) {
			best.rgb = max(best.rgb, col * smoothstep(0.35, 0.6, 1.0 - pr / r));
		}
	}
	t_hit = best_t < 1e29 ? best_t : -1.0;
	return best;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 sun_dir = LIGHT0_DIRECTION;
	float h = dot(d, local_up);
	float sun_h = dot(sun_dir, local_up);
	float dens = atmosphere_density * altitude_factor;
	float px = pixel_angle;

	// De día, el brillo del cielo tapa las estrellas en cuanto hay algo de atmósfera (de noche se ven).
	vec3 e = normalize(sky_basis * d);   // dirección en la eclíptica (cielo inercial)
	float deep_vis = 1.0 - clamp(dens * 4.0, 0.0, 1.0) * day_factor(sun_h);
	vec3 col = vec3(0.0);
	if (deep_vis > 0.01) {
		col = (stars(e) + milky(e)) * deep_vis;
	}
	float nearest_t = 1e30;

	for (int i = 0; i < MAX_BODIES; i++) {
		if (i >= body_count) {
			break;
		}
		vec3 dir = b_dir[i].xyz;
		float ang = b_dir[i].w;
		float cosd = dot(d, dir);
		float kind = b_geo[i].w;
		if (kind > 1.5 && kind < 2.5) {
			// El Sol: disco con oscurecimiento al limbo, corona y resplandor.
			float a = acos(clamp(cosd, -1.0, 1.0));
			float disc = 1.0 - smoothstep(ang * 0.98, ang * 1.02, a);
			float mu = sqrt(max(0.0, 1.0 - pow(min(a / max(ang, 1e-6), 1.0), 2.0)));
			// Granulación de la fotosfera (visible de cerca) y oscurecimiento al limbo.
			float gran = 0.9 + 0.1 * vnoise(d * (0.5 / max(ang, 1e-5)) * 40.0 + vec3(time * 0.05));
			vec3 sun_col = b_col[i].rgb * (0.35 + 0.65 * mu) * gran * 3.0;
			float corona = exp(-max(a - ang, 0.0) / max(ang * 0.6, 1e-5)) * 0.6 + pow(max(cosd, 0.0), 800.0) * 0.25
				+ pow(max(cosd, 0.0), 60.0) * 0.06;
			col += (sun_col * disc + b_col[i].rgb * corona * (0.3 + dens)) * sun_visibility;
			continue;
		}
		if (ang < px * 0.7) {
			// Punto de luz (más pequeño que un píxel): brillo por magnitud aparente.
			float a = acos(clamp(cosd, -1.0, 1.0));
			col += b_col[i].rgb * b_col[i].w * exp(-pow(a / (px * 0.9), 2.0)) * (1.0 - clamp(dens * day_factor(sun_h), 0.0, 1.0));
			continue;
		}
		float ext = ang;
		if (i == shatter_body) {
			ext = ang * 3.2;   // halo de gas y polvo y restos en órbita
		}
		if (i == ring_body) {
			ext = asin(clamp(ring_outer / max(b_geo[i].x + b_geo[i].y, 1.0), 0.0, 1.0));
		}
		if (cosd < cos(min(ext * 1.25 + px * 2.0, 3.14159))) {
			continue;
		}
		if (i == shatter_body) {
			// Sólo dentro del cono que pueden ocupar los fragmentos (≤ 1,6 R del centro): el halo, mucho más ancho,
			// cubría toda la pantalla al llegar y se trazaban 12 fragmentos por píxel sin tocar ninguno (ronda 10).
			float th = -1.0;
			vec4 sc = vec4(0.0);
			float rb = b_geo[i].x * 1.6;
			float dist_c = b_geo[i].x + b_geo[i].y;
			if (dist_c < rb || cosd > cos(asin(clamp(rb / dist_c, 0.0, 1.0)) + px * 2.0)) {
				sc = shattered(i, d, th);
			}
			// Halo anaranjado de gas incandescente y polvo, y restos pequeños en órbita (ADR-040, como en el menú).
			float ad = acos(clamp(cosd, -1.0, 1.0)) / max(ang, 1e-6);
			vec3 halo = vec3(1.0, 0.42, 0.14) * 0.09 * exp(-max(ad - 1.25, 0.0) * 2.2) * step(1.0, ad);
			vec3 pole_s = b_pole[i].xyz;
			vec3 pm_s = b_pm[i].xyz;
			vec3 east_s = cross(pole_s, pm_s);
			vec3 cen = dir * (b_geo[i].x + b_geo[i].y);
			if (sc.a > 0.5 && th < nearest_t) {
				col = sc.rgb;
				nearest_t = th;
			} else {
				// Restos en órbita: sólo donde no tapa un fragmento (ronda 10: se calculaban en todo el halo).
				vec3 debris = vec3(0.0);
				for (int gi = 0; gi < 4; gi++) {
					if (dot(d, debris_group[gi].xyz) < debris_group[gi].w) {
						continue;
					}
					for (int j = 0; j < 7; j++) {
						vec4 dd = debris_dir[gi * 7 + j];
						float cd = dot(d, dd.xyz);
						if (cd > debris_cos) {
							float da = acos(clamp(cd, -1.0, 1.0));
							debris += vec3(0.85, 0.6, 0.45) * exp(-pow(da / (px * 1.1), 2.0)) * dd.w;
						}
					}
				}
				col += halo + debris;
			}
			continue;
		}
		float r = b_geo[i].x;
		float hh = b_geo[i].y;
		float dist = r + hh;
		vec3 pole = b_pole[i].xyz;
		float flt = b_geo[i].z;
		// Achatamiento (elipsoide de revolución): en un espacio con el eje polar estirado por k = 1/(1−f) es una
		// esfera. Lejos se resuelve la cuadrática general; cerca (h < 0,2 R) se usa la esfera con la fórmula estable.
		float t = -1.0;
		vec3 hitp = vec3(0.0);       // punto de impacto relativo al centro (espacio real)
		if (flt > 0.0 && hh > 0.2 * r) {
			float k = 1.0 / (1.0 - flt);
			vec3 oc = -dir * dist;
			vec3 ocs = oc + pole * dot(oc, pole) * (k - 1.0);
			vec3 ds = d + pole * dot(d, pole) * (k - 1.0);
			float qa = dot(ds, ds);
			float qb = dot(ocs, ds);
			float qc = dot(ocs, ocs) - r * r;
			float disc = qb * qb - qa * qc;
			if (disc > 0.0 && qb < 0.0) {
				t = qc / (-qb + sqrt(disc));
				hitp = oc + d * t;
			}
		} else {
			t = sphere_hit(d, dir, dist, r, hh);
			if (t > 0.0) {
				hitp = d * t - dir * dist;
			}
		}
		// Anillos (antes o detrás del planeta).
		vec4 ring = vec4(0.0);
		float ring_t = -1.0;
		if (i == ring_body) {
			float denom = dot(d, pole);
			if (abs(denom) > 1e-6) {
				float tp = dot(dir * dist, pole) / denom;
				if (tp > 0.0) {
					vec3 rp = d * tp - dir * dist;
					float rr = length(rp);
					for (int k = 0; k < MAX_RINGS; k++) {
						if (rr >= ring_a[k].x && rr <= ring_a[k].y) {
							float grain = 0.75 + 0.25 * vnoise(vec3(rr / 300000.0, 0.0, 0.0)) + 0.1 * sin(rr / 9000.0);
							ring = vec4(ring_c[k].rgb * grain, ring_a[k].z);
						}
					}
					if (ring.a > 0.0) {
						// Sombra del planeta sobre los anillos.
						vec3 s = b_sun[i].xyz;
						float bb = dot(s, rp);
						float cc = dot(rp, rp) - r * r;
						bool shadow = bb < 0.0 && bb * bb - cc > 0.0;
						float lit = 0.25 + 0.75 * abs(dot(s, pole));
						ring.rgb *= shadow ? 0.06 : lit;
						ring_t = tp;
					}
				}
			}
		}
		vec3 body_col = vec3(0.0);
		float body_a = 0.0;
		if (t > 0.0) {
			vec3 n = normalize(hitp);
			if (flt > 0.0) {
				float k = 1.0 / (1.0 - flt);
				n = normalize(hitp + pole * dot(hitp, pole) * (k * k - 1.0));   // gradiente del elipsoide
			}
			vec3 pm = b_pm[i].xyz;
			vec3 east = cross(pole, pm);
			vec3 nb = vec3(dot(n, east), dot(n, pole), dot(n, pm));
			float lat = asin(clamp(nb.y, -1.0, 1.0));
			float lon = atan(nb.x, nb.z);
			vec3 sc = surface_color(i, nb, lat, lon);
			float lit = dot(n, b_sun[i].xyz);
			float terminator = smoothstep(-0.02, 0.12, lit);
			body_col = sc * (0.004 + terminator * max(lit, 0.0) * 0.85);
			// Rayos en el lado nocturno de los gigantes (Júpiter, Saturno).
			if (kind > 0.5 && kind < 1.5 && lightning > 0.0) {
				body_col += vec3(0.7, 0.75, 1.0) * lightning * step(0.995, hash13(floor(nb * 400.0) + floor(time * 3.0))) * (1.0 - terminator);
			}
			body_a = 1.0;
			if (t < nearest_t) {
				nearest_t = t;
			}
		}
		// Limbo atmosférico. Sobre el disco: brillo de borde (Fresnel) con la normal real; fuera del disco: halo
		// donde el rayo roza la capa de gas, iluminado según el punto de máxima aproximación.
		if (b_atm[i].w > 0.0) {
			float thick = r * b_sun[i].w;
			if (t > 0.0) {
				vec3 n = normalize(hitp);
				float rim = pow(1.0 - abs(dot(n, -d)), 3.0);
				float sl = smoothstep(-0.2, 0.35, dot(n, b_sun[i].xyz));
				body_col += b_atm[i].rgb * rim * 0.6 * sl * b_atm[i].w;
			} else {
				float b = -dist * dot(d, dir);
				if (b < 0.0) {
					float closest = sqrt(max(dist * dist - b * b, 0.0));
					float x = (closest - r) / max(thick, 1.0);
					if (x >= 0.0 && x < 4.0) {
						vec3 lp = normalize(d * (-b) - dir * dist);
						float sl = smoothstep(-0.25, 0.3, dot(lp, b_sun[i].xyz));
						float glow = exp(-x * 2.5) * sl * b_atm[i].w;
						body_col = b_atm[i].rgb * glow;
						body_a = clamp(glow, 0.0, 1.0);
					}
				}
			}
		}
		// Composición: anillo delante del planeta, planeta, anillo detrás.
		if (ring_t > 0.0 && (t < 0.0 || ring_t < t)) {
			vec3 behind = mix(col, body_col, body_a);
			col = mix(behind, ring.rgb, ring.a);
		} else {
			if (ring_t > 0.0) {
				col = mix(col, ring.rgb, ring.a);
			}
			col = mix(col, body_col, body_a);
		}
	}

	// Atmósfera en la que está la cámara (ADR-037): espesor óptico a lo largo de la visual (masa de aire de una
	// atmósfera plano-paralela). La luz dispersada ilumina el cielo y el fondo (estrellas, planetas) se extingue.
	// Marte (τ≈1) da un cielo de día color caramelo sin estrellas; Venus y Titán, opacos; Plutón, casi espacio.
	if (dens > 0.0) {
		float day = day_factor(sun_h);
		float tau0 = dens * 3.0;
		float hh = max(h, 0.0);
		float airmass = 1.0 / (hh * 0.92 + 0.08);
		float tau = tau0 * airmass;
		float ext = exp(-tau);
		float opac = 1.0 - ext;
		float horizon = pow(1.0 - clamp(abs(h), 0.0, 1.0), 3.0);
		vec3 atmo = mix(zenith_color, atmosphere_color * 1.1, horizon);
		float cs = max(dot(d, sun_dir), 0.0);
		float sunset = clamp(1.0 - abs(sun_h) * 4.0, 0.0, 1.0) * pow(cs, 3.0);
		atmo = mix(atmo, sunset_color, sunset * 0.75);
		// Dispersión hacia delante (aerosoles): halo alrededor del Sol.
		atmo += atmosphere_color * (pow(cs, 8.0) * 0.35 + pow(cs, 64.0) * 0.6) * min(tau0, 1.2);
		// Crepúsculo: el cielo cercano al Sol sigue algo iluminado justo después de la puesta.
		float twilight = clamp((sun_h + 0.18) / 0.18, 0.0, 1.0) * (1.0 - day) * pow(cs, 2.0) * 0.5;
		atmo *= day + twilight;
		atmo *= sun_visibility * 0.5 + 0.5;
		float below = h < -0.05 ? 0.4 : 1.0;
		col = col * mix(1.0, ext, below) + atmo * opac * below;
		col += vec3(1.0, 0.9, 0.7) * pow(cs, 400.0) * min(dens, 1.0) * 0.4 * sun_visibility;
	}
	// Dentro de un gigante gaseoso: la luz se apaga con la profundidad; destellos de rayos.
	if (deep_amount > 0.0) {
		float up = h * 0.5 + 0.5;
		vec3 fog = deep_color * (0.35 + 0.65 * up);
		col = mix(col, fog, deep_amount);
		col += vec3(0.75, 0.8, 1.0) * lightning * (0.4 + 0.6 * vnoise(d * 3.0 + vec3(time)));
	}
	COLOR = col;
}
