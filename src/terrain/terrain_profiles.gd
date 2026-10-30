class_name TerrainProfiles
extends RefCounted
## Perfiles de generación de terreno. Las amplitudes están en metros y las escalas de ruido
## "local" en metros de longitud de onda (≥ 30 m, ver ADR-004 sobre precisión del ruido).
##
## continent_*: ruido de baja frecuencia sobre la esfera unitaria (regiones / mares lunares).
## mountain_*: ruido "ridged" modulado por el continente (cordilleras).
## hills_*: colinas en escala métrica. detail_*: rugosidad fina.
## craters: capas de cráteres basados en ruido celular (cell_m = tamaño de celda).

const PROFILES := {
	"arid_rocky": {
		"continent_scale": 1.6, "continent_amp": 1800.0, "continent_octaves": 5,
		"mountain_scale": 7.0, "mountain_amp": 3200.0, "mountain_octaves": 6,
		"hills_wavelength": 6000.0, "hills_amp": 260.0, "hills_octaves": 6,
		"detail_wavelength": 180.0, "detail_amp": 6.0, "detail_octaves": 3,
		"craters": [
			{"cell_m": 90000.0, "depth": 900.0, "radius": 0.20, "chance": 0.10},
			{"cell_m": 4000.0, "depth": 90.0, "radius": 0.20, "chance": 0.06},
		],
		"colors": {
			"low": Color(0.62, 0.47, 0.33), "mid": Color(0.55, 0.36, 0.24),
			"high": Color(0.36, 0.30, 0.28), "peak": Color(0.86, 0.86, 0.88),
			"slope": Color(0.40, 0.27, 0.20), "polar": Color(0.88, 0.89, 0.92),
		},
		"rock_density": 0.010,  # rocas por m²
		"snow_height": 3600.0,
		"polar_lat": 72.0,
	},
	"cratered_airless": {
		"continent_scale": 2.0, "continent_amp": 1400.0, "continent_octaves": 5,
		"mountain_scale": 9.0, "mountain_amp": 1200.0, "mountain_octaves": 5,
		"hills_wavelength": 5000.0, "hills_amp": 120.0, "hills_octaves": 6,
		"detail_wavelength": 120.0, "detail_amp": 2.5, "detail_octaves": 3,
		"craters": [
			{"cell_m": 120000.0, "depth": 2500.0, "radius": 0.20, "chance": 0.35},
			{"cell_m": 15000.0, "depth": 600.0, "radius": 0.20, "chance": 0.40},
			{"cell_m": 1500.0, "depth": 70.0, "radius": 0.20, "chance": 0.45},
			{"cell_m": 160.0, "depth": 7.0, "radius": 0.20, "chance": 0.50},
		],
		"colors": {
			"low": Color(0.30, 0.30, 0.31), "mid": Color(0.50, 0.49, 0.48),
			"high": Color(0.62, 0.61, 0.60), "peak": Color(0.70, 0.69, 0.68),
			"slope": Color(0.42, 0.41, 0.40), "polar": Color(0.55, 0.55, 0.56),
		},
		"rock_density": 0.020,
		"snow_height": 1.0e9,
		"polar_lat": 95.0,
	},
	# --- Sistema Solar (ADR-030). Amplitudes para un cuerpo del tamaño de la Luna; for_body() las escala.
	"mercury": {
		"continent_scale": 2.2, "continent_amp": 1500.0, "continent_octaves": 5,
		"mountain_scale": 8.0, "mountain_amp": 1400.0, "mountain_octaves": 5,
		"hills_wavelength": 5000.0, "hills_amp": 140.0, "hills_octaves": 6,
		"detail_wavelength": 120.0, "detail_amp": 2.5, "detail_octaves": 3,
		"craters": [
			{"cell_m": 160000.0, "depth": 3000.0, "radius": 0.20, "chance": 0.30},
			{"cell_m": 20000.0, "depth": 800.0, "radius": 0.20, "chance": 0.45},
			{"cell_m": 2000.0, "depth": 90.0, "radius": 0.20, "chance": 0.5},
			{"cell_m": 200.0, "depth": 8.0, "radius": 0.20, "chance": 0.5},
		],
		# Regolito oscuro (albedo real de la Luna ≈ 0,12; ronda 8): más contraste con el cielo y el resplandor de la Tierra.
		"colors": {"low": Color(0.23, 0.22, 0.21), "mid": Color(0.33, 0.315, 0.30), "high": Color(0.40, 0.385, 0.37),
			"peak": Color(0.44, 0.43, 0.41), "slope": Color(0.26, 0.25, 0.24), "polar": Color(0.36, 0.355, 0.35)},
		"rock_density": 0.02, "snow_height": 1.0e9, "polar_lat": 95.0,
	},
	"venus": {
		"continent_scale": 1.4, "continent_amp": 2200.0, "continent_octaves": 5,
		"mountain_scale": 6.0, "mountain_amp": 4500.0, "mountain_octaves": 6,
		"hills_wavelength": 8000.0, "hills_amp": 220.0, "hills_octaves": 6,
		"detail_wavelength": 150.0, "detail_amp": 3.0, "detail_octaves": 3,
		"craters": [{"cell_m": 60000.0, "depth": 500.0, "radius": 0.18, "chance": 0.04}],
		"colors": {"low": Color(0.42, 0.33, 0.22), "mid": Color(0.36, 0.28, 0.19), "high": Color(0.30, 0.25, 0.20),
			"peak": Color(0.50, 0.45, 0.40), "slope": Color(0.26, 0.21, 0.16), "polar": Color(0.36, 0.28, 0.19)},
		"rock_density": 0.03, "snow_height": 1.0e9, "polar_lat": 95.0,
		"lava_flows": true,
	},
	"mars": {
		"continent_scale": 1.6, "continent_amp": 3000.0, "continent_octaves": 5,
		"mountain_scale": 7.0, "mountain_amp": 4000.0, "mountain_octaves": 6,
		"hills_wavelength": 6000.0, "hills_amp": 240.0, "hills_octaves": 6,
		"detail_wavelength": 160.0, "detail_amp": 5.0, "detail_octaves": 3,
		"craters": [
			{"cell_m": 140000.0, "depth": 2000.0, "radius": 0.20, "chance": 0.20},
			{"cell_m": 12000.0, "depth": 400.0, "radius": 0.20, "chance": 0.25},
			{"cell_m": 1500.0, "depth": 60.0, "radius": 0.20, "chance": 0.20},
		],
		"colors": {"low": Color(0.62, 0.36, 0.22), "mid": Color(0.70, 0.42, 0.26), "high": Color(0.52, 0.32, 0.22),
			"peak": Color(0.75, 0.55, 0.42), "slope": Color(0.45, 0.27, 0.18), "polar": Color(0.92, 0.90, 0.88)},
		"rock_density": 0.012, "snow_height": 1.0e9, "polar_lat": 78.0,
	},
	"io": {
		"continent_scale": 1.8, "continent_amp": 900.0, "continent_octaves": 4,
		"mountain_scale": 6.0, "mountain_amp": 6000.0, "mountain_octaves": 4,
		"hills_wavelength": 7000.0, "hills_amp": 90.0, "hills_octaves": 5,
		"detail_wavelength": 140.0, "detail_amp": 2.0, "detail_octaves": 3,
		"craters": [{"cell_m": 50000.0, "depth": 900.0, "radius": 0.12, "chance": 0.25}],
		"colors": {"low": Color(0.90, 0.80, 0.40), "mid": Color(0.88, 0.70, 0.30), "high": Color(0.80, 0.55, 0.25),
			"peak": Color(0.95, 0.92, 0.80), "slope": Color(0.55, 0.32, 0.12), "polar": Color(0.62, 0.45, 0.35)},
		"rock_density": 0.004, "snow_height": 1.0e9, "polar_lat": 60.0,
		"mountain_mask": 0.55, "spots": {"cell_m": 160000.0, "chance": 0.5, "color": Color(0.12, 0.08, 0.06), "ring": Color(0.75, 0.30, 0.10)},
	},
	"europa": {
		"continent_scale": 2.0, "continent_amp": 250.0, "continent_octaves": 4,
		"mountain_scale": 8.0, "mountain_amp": 200.0, "mountain_octaves": 4,
		"hills_wavelength": 4000.0, "hills_amp": 40.0, "hills_octaves": 5,
		"detail_wavelength": 100.0, "detail_amp": 1.5, "detail_octaves": 3,
		"craters": [{"cell_m": 80000.0, "depth": 300.0, "radius": 0.15, "chance": 0.05}],
		"colors": {"low": Color(0.80, 0.72, 0.62), "mid": Color(0.88, 0.84, 0.78), "high": Color(0.93, 0.92, 0.90),
			"peak": Color(0.95, 0.95, 0.95), "slope": Color(0.70, 0.55, 0.45), "polar": Color(0.93, 0.93, 0.95)},
		"rock_density": 0.002, "snow_height": 1.0e9, "polar_lat": 95.0,
		"cracks": {"scale": 18.0, "width": 0.035, "color": Color(0.55, 0.30, 0.20), "depth": 60.0},
	},
	"ganymede": {
		"continent_scale": 2.0, "continent_amp": 1200.0, "continent_octaves": 5,
		"mountain_scale": 10.0, "mountain_amp": 600.0, "mountain_octaves": 5,
		"hills_wavelength": 4000.0, "hills_amp": 100.0, "hills_octaves": 6,
		"detail_wavelength": 120.0, "detail_amp": 2.0, "detail_octaves": 3,
		"craters": [
			{"cell_m": 90000.0, "depth": 1500.0, "radius": 0.20, "chance": 0.25},
			{"cell_m": 9000.0, "depth": 300.0, "radius": 0.20, "chance": 0.35},
			{"cell_m": 900.0, "depth": 40.0, "radius": 0.20, "chance": 0.35},
		],
		"colors": {"low": Color(0.40, 0.37, 0.33), "mid": Color(0.58, 0.55, 0.50), "high": Color(0.72, 0.70, 0.66),
			"peak": Color(0.85, 0.85, 0.85), "slope": Color(0.45, 0.42, 0.38), "polar": Color(0.82, 0.82, 0.84)},
		"rock_density": 0.01, "snow_height": 1.0e9, "polar_lat": 70.0,
		"cracks": {"scale": 9.0, "width": 0.06, "color": Color(0.75, 0.74, 0.70), "depth": -80.0},
	},
	"callisto": {
		"continent_scale": 2.0, "continent_amp": 900.0, "continent_octaves": 5,
		"mountain_scale": 9.0, "mountain_amp": 500.0, "mountain_octaves": 5,
		"hills_wavelength": 4000.0, "hills_amp": 120.0, "hills_octaves": 6,
		"detail_wavelength": 120.0, "detail_amp": 2.5, "detail_octaves": 3,
		"craters": [
			{"cell_m": 120000.0, "depth": 2000.0, "radius": 0.20, "chance": 0.40},
			{"cell_m": 15000.0, "depth": 600.0, "radius": 0.20, "chance": 0.55},
			{"cell_m": 1500.0, "depth": 70.0, "radius": 0.20, "chance": 0.60},
			{"cell_m": 160.0, "depth": 7.0, "radius": 0.20, "chance": 0.60},
		],
		"colors": {"low": Color(0.24, 0.22, 0.20), "mid": Color(0.33, 0.31, 0.28), "high": Color(0.45, 0.43, 0.40),
			"peak": Color(0.85, 0.85, 0.86), "slope": Color(0.70, 0.70, 0.72), "polar": Color(0.40, 0.38, 0.36)},
		"rock_density": 0.02, "snow_height": 1.0e9, "polar_lat": 95.0,
	},
	"titan": {
		"continent_scale": 1.8, "continent_amp": 600.0, "continent_octaves": 5,
		"mountain_scale": 9.0, "mountain_amp": 800.0, "mountain_octaves": 5,
		"hills_wavelength": 3000.0, "hills_amp": 80.0, "hills_octaves": 6,
		"detail_wavelength": 120.0, "detail_amp": 2.0, "detail_octaves": 3,
		"craters": [{"cell_m": 90000.0, "depth": 300.0, "radius": 0.15, "chance": 0.03}],
		"colors": {"low": Color(0.30, 0.22, 0.14), "mid": Color(0.48, 0.36, 0.22), "high": Color(0.60, 0.48, 0.32),
			"peak": Color(0.70, 0.62, 0.50), "slope": Color(0.38, 0.30, 0.20), "polar": Color(0.48, 0.36, 0.22)},
		"rock_density": 0.006, "snow_height": 1.0e9, "polar_lat": 95.0,
		"dunes": {"wavelength": 2500.0, "amp": 60.0, "lat_max": 30.0},
		"sea": {"level": -250.0, "color": Color(0.05, 0.05, 0.07), "lat_min": 55.0},
	},
	"enceladus": {
		"continent_scale": 2.5, "continent_amp": 600.0, "continent_octaves": 4,
		"mountain_scale": 8.0, "mountain_amp": 400.0, "mountain_octaves": 4,
		"hills_wavelength": 3000.0, "hills_amp": 50.0, "hills_octaves": 5,
		"detail_wavelength": 100.0, "detail_amp": 1.5, "detail_octaves": 3,
		"craters": [{"cell_m": 30000.0, "depth": 600.0, "radius": 0.20, "chance": 0.30},
			{"cell_m": 3000.0, "depth": 80.0, "radius": 0.20, "chance": 0.25}],
		"colors": {"low": Color(0.90, 0.92, 0.95), "mid": Color(0.95, 0.96, 0.98), "high": Color(0.98, 0.98, 0.99),
			"peak": Color(1.0, 1.0, 1.0), "slope": Color(0.80, 0.86, 0.92), "polar": Color(0.97, 0.98, 1.0)},
		"rock_density": 0.004, "snow_height": 1.0e9, "polar_lat": 95.0,
		"cracks": {"scale": 6.0, "width": 0.05, "color": Color(0.45, 0.65, 0.85), "depth": -300.0, "lat_max": -55.0},
	},
	"icy_cratered": {
		"continent_scale": 2.0, "continent_amp": 1000.0, "continent_octaves": 5,
		"mountain_scale": 9.0, "mountain_amp": 600.0, "mountain_octaves": 5,
		"hills_wavelength": 4000.0, "hills_amp": 80.0, "hills_octaves": 6,
		"detail_wavelength": 110.0, "detail_amp": 2.0, "detail_octaves": 3,
		"craters": [
			{"cell_m": 110000.0, "depth": 2500.0, "radius": 0.22, "chance": 0.35},
			{"cell_m": 12000.0, "depth": 500.0, "radius": 0.20, "chance": 0.45},
			{"cell_m": 1200.0, "depth": 50.0, "radius": 0.20, "chance": 0.45},
		],
		"colors": {"low": Color(0.70, 0.70, 0.72), "mid": Color(0.80, 0.80, 0.82), "high": Color(0.86, 0.86, 0.88),
			"peak": Color(0.92, 0.92, 0.93), "slope": Color(0.62, 0.62, 0.64), "polar": Color(0.88, 0.88, 0.90)},
		"rock_density": 0.01, "snow_height": 1.0e9, "polar_lat": 95.0,
	},
	"iapetus": {
		"continent_scale": 2.0, "continent_amp": 1500.0, "continent_octaves": 5,
		"mountain_scale": 9.0, "mountain_amp": 800.0, "mountain_octaves": 5,
		"hills_wavelength": 4000.0, "hills_amp": 90.0, "hills_octaves": 6,
		"detail_wavelength": 110.0, "detail_amp": 2.0, "detail_octaves": 3,
		"craters": [{"cell_m": 120000.0, "depth": 3000.0, "radius": 0.22, "chance": 0.35},
			{"cell_m": 12000.0, "depth": 500.0, "radius": 0.20, "chance": 0.40}],
		"colors": {"low": Color(0.80, 0.78, 0.74), "mid": Color(0.84, 0.82, 0.78), "high": Color(0.88, 0.86, 0.82),
			"peak": Color(0.92, 0.90, 0.86), "slope": Color(0.70, 0.68, 0.64), "polar": Color(0.90, 0.88, 0.84)},
		"rock_density": 0.008, "snow_height": 1.0e9, "polar_lat": 95.0,
		"two_tone": {"color": Color(0.11, 0.09, 0.08)}, "equatorial_ridge": 13000.0,
	},
	"miranda": {
		"continent_scale": 3.0, "continent_amp": 2500.0, "continent_octaves": 5,
		"mountain_scale": 12.0, "mountain_amp": 2500.0, "mountain_octaves": 5,
		"hills_wavelength": 3000.0, "hills_amp": 120.0, "hills_octaves": 6,
		"detail_wavelength": 100.0, "detail_amp": 2.0, "detail_octaves": 3,
		"craters": [{"cell_m": 30000.0, "depth": 800.0, "radius": 0.20, "chance": 0.30}],
		"colors": {"low": Color(0.55, 0.55, 0.56), "mid": Color(0.68, 0.68, 0.70), "high": Color(0.78, 0.78, 0.80),
			"peak": Color(0.85, 0.85, 0.86), "slope": Color(0.45, 0.45, 0.47), "polar": Color(0.70, 0.70, 0.72)},
		"rock_density": 0.01, "snow_height": 1.0e9, "polar_lat": 95.0,
		"cracks": {"scale": 5.0, "width": 0.08, "color": Color(0.85, 0.85, 0.88), "depth": -900.0},
	},
	"triton": {
		"continent_scale": 2.2, "continent_amp": 400.0, "continent_octaves": 5,
		"mountain_scale": 10.0, "mountain_amp": 300.0, "mountain_octaves": 4,
		"hills_wavelength": 2500.0, "hills_amp": 60.0, "hills_octaves": 6,
		"detail_wavelength": 100.0, "detail_amp": 1.5, "detail_octaves": 3,
		"craters": [{"cell_m": 30000.0, "depth": 200.0, "radius": 0.18, "chance": 0.05}],
		"colors": {"low": Color(0.78, 0.68, 0.66), "mid": Color(0.86, 0.78, 0.76), "high": Color(0.90, 0.86, 0.84),
			"peak": Color(0.95, 0.93, 0.92), "slope": Color(0.70, 0.60, 0.58), "polar": Color(0.92, 0.82, 0.78)},
		"rock_density": 0.004, "snow_height": 1.0e9, "polar_lat": -50.0,
		"spots": {"cell_m": 20000.0, "chance": 0.35, "color": Color(0.62, 0.52, 0.50), "ring": Color(0.90, 0.84, 0.82)},
	},
	"pluto": {
		"continent_scale": 1.6, "continent_amp": 1800.0, "continent_octaves": 5,
		"mountain_scale": 8.0, "mountain_amp": 3000.0, "mountain_octaves": 5,
		"hills_wavelength": 3000.0, "hills_amp": 80.0, "hills_octaves": 6,
		"detail_wavelength": 100.0, "detail_amp": 1.5, "detail_octaves": 3,
		"craters": [{"cell_m": 60000.0, "depth": 1200.0, "radius": 0.20, "chance": 0.20},
			{"cell_m": 6000.0, "depth": 200.0, "radius": 0.20, "chance": 0.20}],
		"colors": {"low": Color(0.92, 0.88, 0.82), "mid": Color(0.62, 0.42, 0.30), "high": Color(0.45, 0.28, 0.20),
			"peak": Color(0.85, 0.82, 0.80), "slope": Color(0.50, 0.35, 0.28), "polar": Color(0.80, 0.72, 0.62)},
		"rock_density": 0.006, "snow_height": 1.0e9, "polar_lat": 95.0,
		"smooth_basins": 0.5,
	},
	"charon": {
		"continent_scale": 2.0, "continent_amp": 1200.0, "continent_octaves": 5,
		"mountain_scale": 9.0, "mountain_amp": 1500.0, "mountain_octaves": 5,
		"hills_wavelength": 3000.0, "hills_amp": 80.0, "hills_octaves": 6,
		"detail_wavelength": 100.0, "detail_amp": 1.5, "detail_octaves": 3,
		"craters": [{"cell_m": 50000.0, "depth": 1500.0, "radius": 0.20, "chance": 0.25}],
		"colors": {"low": Color(0.50, 0.49, 0.48), "mid": Color(0.58, 0.57, 0.56), "high": Color(0.64, 0.63, 0.62),
			"peak": Color(0.70, 0.70, 0.70), "slope": Color(0.45, 0.44, 0.43), "polar": Color(0.48, 0.28, 0.22)},
		"rock_density": 0.008, "snow_height": 1.0e9, "polar_lat": 70.0,
	},
	"small_irregular": {
		"continent_scale": 3.5, "continent_amp": 2500.0, "continent_octaves": 5,
		"mountain_scale": 9.0, "mountain_amp": 1500.0, "mountain_octaves": 4,
		"hills_wavelength": 3000.0, "hills_amp": 200.0, "hills_octaves": 5,
		"detail_wavelength": 80.0, "detail_amp": 2.0, "detail_octaves": 3,
		"craters": [{"cell_m": 60000.0, "depth": 3000.0, "radius": 0.24, "chance": 0.45},
			{"cell_m": 6000.0, "depth": 400.0, "radius": 0.22, "chance": 0.5},
			{"cell_m": 600.0, "depth": 40.0, "radius": 0.20, "chance": 0.5}],
		"colors": {"low": Color(0.34, 0.32, 0.30), "mid": Color(0.42, 0.40, 0.38), "high": Color(0.48, 0.46, 0.44),
			"peak": Color(0.55, 0.53, 0.51), "slope": Color(0.30, 0.28, 0.27), "polar": Color(0.42, 0.40, 0.38)},
		"rock_density": 0.02, "snow_height": 1.0e9, "polar_lat": 95.0,
	},

}


static func get_profile(id: String) -> Dictionary:
	if PROFILES.has(id):
		return PROFILES[id]
	push_warning("Perfil de terreno desconocido '%s'; se usa arid_rocky" % id)
	return PROFILES["arid_rocky"]


## Cota máxima teórica (m) por encima del radio medio; usada para LOD y planos de cámara.
static func max_elevation(profile: Dictionary) -> float:
	return float(profile["continent_amp"]) + float(profile["mountain_amp"]) \
		+ float(profile["hills_amp"]) + float(profile["detail_amp"])


## Perfil de un cuerpo concreto (ADR-030): copia del perfil base con los colores del JSON
## (`surface.colors_override`) y el relieve escalado a su tamaño (amplitudes ∝ (R/R_Luna)^0,7, tamaño de los
## cráteres ∝ (R/R_Luna)^0,8 para los cuerpos pequeños; longitudes de onda ≥ 30 m por la precisión del ruido).
static func for_body(body: BodyDef) -> Dictionary:
	var base := get_profile(body.terrain_profile())
	var p := base.duplicate(true)
	var k_amp := pow(clampf(body.radius_m() / 1737400.0, 0.003, 2.0), 0.7)
	var k_size := pow(clampf(body.radius_m() / 1737400.0, 0.003, 1.0), 0.8)
	for key in ["continent_amp", "mountain_amp", "hills_amp"]:
		p[key] = float(p[key]) * k_amp
	p["detail_amp"] = float(p["detail_amp"]) * maxf(k_amp, 0.3)
	p["hills_wavelength"] = maxf(float(p["hills_wavelength"]) * k_size, 200.0)
	var craters: Array = []
	for c in p.get("craters", []):
		var cc: Dictionary = c.duplicate()
		cc["cell_m"] = maxf(float(c["cell_m"]) * k_size, 120.0)
		cc["depth"] = float(c["depth"]) * maxf(k_size, k_amp)
		craters.append(cc)
	p["craters"] = craters
	if p.has("cracks"):
		var cr: Dictionary = p["cracks"].duplicate()
		cr["depth"] = float(cr["depth"]) * k_amp
		p["cracks"] = cr
	var ov: Dictionary = body.surface().get("colors_override", {})
	if ov.has("base") and str(body.terrain_profile()) in ["icy_cratered", "small_irregular"]:
		var b: Array = ov["base"]
		var a: Array = ov.get("alt", b)
		var cb := Color(b[0], b[1], b[2])
		var ca := Color(a[0], a[1], a[2])
		var cols: Dictionary = p["colors"].duplicate()
		cols["low"] = cb.lerp(ca, 0.5)
		cols["mid"] = cb
		cols["high"] = cb.lightened(0.08)
		cols["peak"] = cb.lightened(0.15)
		cols["slope"] = ca
		cols["polar"] = cb
		p["colors"] = cols
	return p
