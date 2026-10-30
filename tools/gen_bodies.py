"""Genera data/bodies/*.json del Sistema Solar (Hito 3, ADR-024).

Fuentes (todas citadas campo a campo en el JSON generado):
- NASA NSSDCA Planetary Fact Sheets (https://nssdc.gsfc.nasa.gov/planetary/factsheet/), consultadas 2026-10-11.
- JPL SSD, elementos keplerianos aproximados de los planetas, Tabla 1 (Standish & Williams 1992), 1800-2050
  (https://ssd.jpl.nasa.gov/planets/approx_pos.html).
- JPL SSD, elementos medios y parámetros físicos de satélites (data/sources/jpl_sat_*.json).
- IAU WGCCRE 2015 (Archinal et al. 2018) para la orientación de rotación (W0, Wdot). Los polos se contrastaron
  con las fichas NSSDC; W0/Wdot se marcan como 'approximate'.
- Galileo, Cassini, Huygens, Voyager 2 y Hubble para atmósferas y tormentas (ver docs/SOLAR_SYSTEM.md).

Uso:  python tools/gen_bodies.py   (desde la carpeta del proyecto)
"""
import json
import zlib
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "data", "bodies")
SRC = os.path.join(ROOT, "data", "sources")

NSSDC = "NASA NSSDCA Planetary Fact Sheet"
JPL_PL = "JPL SSD Approximate Positions of the Planets, Tabla 1 (Standish & Williams 1992)"
IAU = "IAU WGCCRE 2015 (Archinal et al. 2018)"
AU = 1.495978707e11
G = 6.67430e-11


def q(value, unit, quality, source):
    return {"value": value, "unit": unit, "quality": quality, "source": source}


def rgb(*c):
    return [round(x, 3) for x in c]


# ------------------------------------------------------------------------------------------------
# Planetas: elementos J2000 + tasas por siglo (JPL Tabla 1). [a, e, I, L, varpi, node], [tasas]
PLANET_ELEMENTS = {
    "mercury": ([0.38709927, 0.20563593, 7.00497902, 252.25032350, 77.45779628, 48.33076593],
                [0.00000037, 0.00001906, -0.00594749, 149472.67411175, 0.16047689, -0.12534081]),
    "venus": ([0.72333566, 0.00677672, 3.39467605, 181.97909950, 131.60246718, 76.67984255],
              [0.00000390, -0.00004107, -0.00078890, 58517.81538729, 0.00268329, -0.27769418]),
    "earth": ([1.00000261, 0.01671123, -0.00001531, 100.46457166, 102.93768193, 0.0],
              [0.00000562, -0.00004392, -0.01294668, 35999.37244981, 0.32327364, 0.0]),
    "mars": ([1.52371034, 0.09339410, 1.84969142, -4.55343205, -23.94362959, 49.55953891],
             [0.00001847, 0.00007882, -0.00813131, 19140.30268499, 0.44441088, -0.29257343]),
    "jupiter": ([5.20288700, 0.04838624, 1.30439695, 34.39644051, 14.72847983, 100.47390909],
                [-0.00011607, -0.00013253, -0.00183714, 3034.74612775, 0.21252668, 0.20469106]),
    "saturn": ([9.53667594, 0.05386179, 2.48599187, 49.95424423, 92.59887831, 113.66242448],
               [-0.00125060, -0.00050991, 0.00193609, 1222.49362201, -0.41897216, -0.28867794]),
    "uranus": ([19.18916464, 0.04725744, 0.77263783, 313.23810451, 170.95427630, 74.01692503],
               [-0.00196176, -0.00004397, -0.00242939, 428.48202785, 0.40805281, 0.04240589]),
    "neptune": ([30.06992276, 0.00859048, 1.77004347, -55.12002969, 44.96476227, 131.78422574],
                [0.00026291, 0.00005105, 0.00035372, 218.45945325, -0.32241464, -0.00508664]),
    # Plutón: elementos osculadores J2000 de la ficha NSSDC; tasa de L por su periodo (90 560 d).
    "pluto": ([39.48168677, 0.24880766, 17.14175, 238.92881, 224.06676, 110.30347],
              [0.0, 0.0, 0.0, 36525.0 * 360.0 / 90560.0, 0.0, 0.0]),
}


def planet_orbit(pid):
    el, rt = PLANET_ELEMENTS[pid]
    src = JPL_PL if pid != "pluto" else NSSDC + " (Pluto; elementos J2000, tasa de L por el periodo orbital)"
    return {"model": "planet", "frame": "ecliptic_j2000", "elements": el, "rates_per_century": rt,
            "element_order": ["a_au", "e", "i_deg", "L_deg", "varpi_deg", "node_deg"],
            "quality": "measured" if pid != "pluto" else "approximate",
            "source": src, "valid": "1800-2050" if pid != "pluto" else "época J2000 (deriva fuera de ±50 años)"}


def rotation_iau(ra, dec, w0, wdot, ra_rate=0.0, dec_rate=0.0, pole_src=None):
    return {"model": "iau", "pole_ra": ra, "pole_dec": dec, "pole_ra_rate": ra_rate, "pole_dec_rate": dec_rate,
            "w0": w0, "wdot": wdot, "quality": "approximate",
            "source": IAU + ("; polo contrastado con " + pole_src if pole_src else "")}


# ------------------------------------------------------------------------------------------------
# Atmósferas.

def gas_atmosphere(name, t1, t01, rho1, h_km, mu, winds, comp, clouds, sky_top, sky_deep, cp, wind_model,
                   lightning, extra_note=""):
    """Gigante gaseoso. Referencia de altitud 0 = nivel de 1 bar. Bajo 1 bar el modelo sigue una adiabática
    seca (T = T1 + Γ·profundidad, Γ = g/cp; P ∝ T^(cp/Rs)), que reproduce los ~22 bar y ~425 K de la sonda
    Galileo a ~150 km bajo 1 bar en Júpiter."""
    return {
        "present": True, "kind": "gas_giant", "reference_level": "1 bar",
        "pressure_1bar": q(1.0e5, "Pa", "measured", "Definición del nivel de referencia (1 bar)"),
        "temperature_1bar": q(t1, "K", "measured", NSSDC + " (" + name + ": temperatura a 1 bar)"),
        "temperature_0p1bar": q(t01, "K", "measured", NSSDC + " (" + name + ": temperatura a 0,1 bar)"),
        "density_1bar": q(rho1, "kg/m3", "measured", NSSDC + " (" + name + ": densidad a 1 bar)"),
        "scale_height": q(h_km * 1000.0, "m", "measured", NSSDC + " (" + name + ": altura de escala)"),
        "mean_molecular_weight": q(mu, "g/mol", "measured", NSSDC),
        "specific_heat_cp": q(cp, "J/(kg K)", "approximate", "Mezcla H2/He ideal (cp ≈ 3,5 R/μ)"),
        "composition": comp,
        "clouds": clouds,
        "winds": winds,
        "wind_model": wind_model,
        "lightning": lightning,
        "sky_above_clouds": sky_top,
        "deep_color": sky_deep,
        "note": "Sin superficie sólida: la presión y la temperatura crecen sin límite al descender. " + extra_note,
    }


def cloud(name, p_top_bar, p_base_bar, color, opacity, note, quality="approximate"):
    return {"name": name, "p_top_bar": p_top_bar, "p_base_bar": p_base_bar, "color": color, "opacity": opacity,
            "quality": quality, "note": note}


def rocky_atmosphere(p0, t0, h_m, mu, lapse, t_min, comp, sky, visual_density, surface_light, visibility_m,
                     clouds=None, winds=None, src=NSSDC, quality="measured", note=""):
    return {
        "present": True, "kind": "rocky", "reference_level": "surface",
        "surface_pressure": q(p0, "Pa", quality, src),
        "surface_temperature": q(t0, "K", quality, src),
        "scale_height": q(h_m, "m", quality, src),
        "mean_molecular_weight": q(mu, "g/mol", quality, src),
        "lapse_rate": q(lapse, "K/m", "approximate", "Gradiente térmico típico de la troposfera"),
        "min_temperature": q(t_min, "K", "approximate", "Temperatura mínima de la troposfera (tropopausa)"),
        "composition": comp, "sky": sky, "visual_density": visual_density,
        "surface_light": q(surface_light, "fracción", "approximate", "Fracción de la luz solar que llega al suelo"),
        "visibility": q(visibility_m, "m", "approximate", "Visibilidad horizontal típica en superficie"),
        "clouds": clouds or [], "winds": winds or {}, "note": note,
    }


# ------------------------------------------------------------------------------------------------
# Cuerpos principales (fichas curadas).

def major_bodies():
    B = []

    B.append({
        "id": "sun", "name": "Sol", "kind": "star", "parent": "",
        "description": "Estrella G2V. Fotosfera a 5772 K; la nave no sobrevive a la proximidad de la fotosfera.",
        "physical": {
            "mean_radius": q(695700e3, "m", "measured", NSSDC + " (Sun: volumetric mean radius)"),
            "mass": q(1.9884e30, "kg", "measured", NSSDC + " (Sun)"),
            "gm": q(1.32712e20, "m3/s2", "measured", NSSDC + " (Sun)"),
            "sidereal_rotation_period": q(25.05 * 86400.0, "s", "approximate", NSSDC + " (14,37°/día en el ecuador)"),
            "axial_tilt": q(7.25, "deg", "measured", NSSDC + " (oblicuidad respecto a la eclíptica)"),
            "luminosity": q(3.828e26, "W", "measured", NSSDC + " (Sun: 382.8e24 J/s)"),
            "effective_temperature": q(5772.0, "K", "measured", NSSDC + " (Sun)"),
        },
        "rotation": rotation_iau(286.13, 63.87, 84.176, 14.1844, pole_src=NSSDC),
        "orbit": {"model": "fixed", "note": "Origen del marco heliocéntrico (no se modela el baricentro)."},
        "atmosphere": {"present": False, "note": "Cromosfera y corona: sólo visuales."},
        "surface": {"type": "plasma", "terrain_note": "Sin superficie: plasma."},
        "render": {"kind": "star", "color": rgb(1.0, 0.96, 0.88), "corona": True},
    })

    def planet(pid, name, desc, r_mean, gm, rot_h, day_h, tilt, albedo, rot, extra=None, phys_extra=None):
        d = {
            "id": pid, "name": name, "kind": "planet" if pid != "pluto" else "dwarf_planet", "parent": "sun",
            "description": desc,
            "physical": {
                "mean_radius": q(r_mean, "m", "measured", NSSDC + " (" + pid + ": volumetric mean radius)"),
                "mass": q(gm / G, "kg", "measured", NSSDC + " (" + pid + ": GM/G)"),
                "gm": q(gm, "m3/s2", "measured", NSSDC + " (" + pid + ")"),
                "sidereal_rotation_period": q(rot_h * 3600.0, "s", "measured", NSSDC + " (negativo = retrógrado)"),
                "solar_day": q(day_h * 3600.0, "s", "measured", NSSDC + " (length of day)"),
                "axial_tilt": q(tilt, "deg", "measured", NSSDC + " (obliquity to orbit)"),
                "geometric_albedo": q(albedo, "", "measured", NSSDC),
            },
            "rotation": rot,
            "orbit": planet_orbit(pid),
        }
        if phys_extra:
            d["physical"].update(phys_extra)
        d.update(extra or {})
        return d

    B.append(planet("mercury", "Mercurio",
                    "El planeta más cercano al Sol. Sin atmósfera (exosfera < 5e-15 bar): de 100 K de noche a 700 K de día.",
                    2439.7e3, 2.2032e13, 1407.6, 4222.6, 0.034, 0.142,
                    rotation_iau(281.0103, 61.4155, 329.5988, 6.1385108, -0.0328, -0.0049, NSSDC), {
                        "atmosphere": {"present": False, "note": "Exosfera de Na, Mg, O, H, K: vacío a efectos prácticos."},
                        "surface": {"type": "solid", "terrain_profile": "mercury", "seed": 2439700,
                                    "terrain_note": "Topografía PROCEDURAL inspirada en Mercurio (MESSENGER); no son datos reales.",
                                    "temperature_day_k": 700, "temperature_night_k": 100},
                        "render": {"kind": "rocky", "color": rgb(0.55, 0.52, 0.49), "color2": rgb(0.40, 0.38, 0.36)},
                    }))

    B.append(planet("venus", "Venus",
                    "Infierno de CO2: 92 bar y 737 K en superficie, nubes de ácido sulfúrico entre 48 y 70 km y vientos de "
                    "~100 m/s en la cima de las nubes (superrotación); en el suelo apenas 0,3-1 m/s. Rotación retrógrada de 243 días.",
                    6051.8e3, 3.2486e14, -5832.6, 2802.0, 177.36, 0.689,
                    rotation_iau(272.76, 67.16, 160.20, -1.4813688, pole_src=NSSDC), {
                        "atmosphere": rocky_atmosphere(
                            92.0e5, 737.0, 15900.0, 43.45, 0.0078, 230.0,
                            "CO2 96,5 %, N2 3,5 %; SO2 150 ppm, Ar 70 ppm, H2O 20 ppm (NSSDC)",
                            {"zenith": rgb(0.55, 0.42, 0.22), "horizon": rgb(0.80, 0.60, 0.32), "sunset": rgb(0.7, 0.4, 0.15),
                             "space_limb": rgb(0.95, 0.90, 0.75)},
                            1.0, 0.04, 9000.0,
                            clouds=[
                                {"name": "Capa inferior (H2SO4)", "bottom_m": 47500, "top_m": 50500, "color": rgb(0.85, 0.78, 0.55), "opacity": 0.9},
                                {"name": "Capa media (H2SO4)", "bottom_m": 50500, "top_m": 56500, "color": rgb(0.92, 0.85, 0.62), "opacity": 0.95},
                                {"name": "Capa superior (H2SO4)", "bottom_m": 56500, "top_m": 70000, "color": rgb(0.96, 0.92, 0.75), "opacity": 0.8},
                            ],
                            winds={"surface_mps": 1.0, "cloud_top_mps": 100.0, "note": "Superrotación retrógrada (~4 días en la cima de las nubes)"},
                            note="Capas de nubes según Pioneer Venus/Venus Express (≈47,5-70 km); la luz en el suelo (≈2-10 %) es incierta: se usa 4 %."),
                        "surface": {"type": "solid", "terrain_profile": "venus", "seed": 6051800,
                                    "terrain_note": "Topografía PROCEDURAL inspirada en Venus (Magellan); no son datos reales.",
                                    "temperature_k": 737},
                        "render": {"kind": "clouded", "color": rgb(0.93, 0.86, 0.70), "color2": rgb(0.85, 0.75, 0.55)},
                    }))

    B.append(planet("earth", "Tierra",
                    "LORE: la Tierra ha sido destruida. Sus grandes fragmentos, todavía reconocibles (continentes, fondos "
                    "oceánicos secos), giran despacio alrededor de un núcleo al rojo; la Luna sigue en su órbita.",
                    6371.0e3, 3.98600e14, 23.9345, 24.0, 23.44, 0.434,
                    rotation_iau(0.0, 90.0, 190.147, 360.9856235, -0.641, -0.557, NSSDC), {
                        "atmosphere": {"present": False, "note": "LORE: atmósfera y océanos perdidos tras la destrucción."},
                        "surface": {"type": "shattered", "seed": 6371000,
                                    "terrain_note": "LORE (ficción del juego): Tierra fragmentada. Contornos continentales aproximados.",
                                    "fragments": 11, "expansion": 1.32, "core_radius_fraction": 0.33,
                                    "tumble_period_h": [30.0, 140.0]},
                        "render": {"kind": "shattered", "color": rgb(0.35, 0.42, 0.30), "color2": rgb(0.15, 0.22, 0.38)},
                    }))

    B.append(planet("mars", "Marte",
                    "Desierto helado de óxido de hierro: 6,36 mbar de CO2, ~214 K de media, tormentas de polvo de hasta 30 m/s. "
                    "Cielo de color caramelo de día y puestas de sol azules por el polvo.",
                    3389.5e3, 4.2828e13, 24.6229, 24.6597, 25.19, 0.170,
                    rotation_iau(317.681, 52.887, 176.630, 350.89198226, -0.106, -0.061, NSSDC), {
                        "atmosphere": rocky_atmosphere(
                            636.0, 214.0, 11000.0, 43.49, 0.0025, 150.0,
                            "CO2 95,1 %, N2 2,59 %, Ar 1,94 %, O2 0,16 %, CO 0,06 % (NSSDC)",
                            {"zenith": rgb(0.55, 0.40, 0.30), "horizon": rgb(0.78, 0.60, 0.44), "sunset": rgb(0.45, 0.62, 0.88),
                             "space_limb": rgb(0.85, 0.65, 0.50)},
                            0.35, 0.85, 40000.0,
                            winds={"surface_mps": 7.0, "storm_mps": 30.0, "note": "2-7 m/s verano, 5-10 otoño, 17-30 tormenta (NSSDC, Viking)"},
                            note="Puesta de sol azul: el polvo dispersa la luz roja hacia delante (Curiosity, Spirit)."),
                        "surface": {"type": "solid", "terrain_profile": "mars", "seed": 3389500,
                                    "terrain_note": "Topografía PROCEDURAL inspirada en Marte (MOLA); no son datos reales."},
                        "render": {"kind": "rocky", "color": rgb(0.74, 0.42, 0.26), "color2": rgb(0.55, 0.30, 0.20),
                                   "polar_caps": True},
                    }))

    B.append(planet("jupiter", "Júpiter",
                    "Gigante de H2/He sin superficie. Bandas de nubes de amoníaco, la Gran Mancha Roja (anticiclón de "
                    "~12 400-14 900 km, vientos de ~430 km/h) y chorros de hasta 150 m/s. La sonda Galileo (1995) dejó de "
                    "transmitir a ~23 bar y ~425 K.",
                    69911e3, 1.26687e17, 9.925, 9.925, 3.13, 0.538,
                    rotation_iau(268.057, 64.495, 284.95, 870.536, -0.006, 0.002, NSSDC), {
                        "atmosphere": gas_atmosphere(
                            "Jupiter", 165.0, 112.0, 0.16, 27.0, 2.22,
                            {"max_mps": 150.0, "high_lat_mps": 40.0, "note": "Hasta 150 m/s (<30°), 40 m/s (>30°) (NSSDC)"},
                            "H2 89,8 %, He 10,2 %; CH4 3000 ppm, NH3 260 ppm, HD 28 ppm, C2H6 5,8 ppm, H2O ~4 ppm (NSSDC)",
                            [cloud("Nubes de amoníaco (NH3)", 0.5, 0.9, rgb(0.95, 0.92, 0.85), 0.85, "Zonas blancas; modelo de condensación"),
                             cloud("Hidrosulfuro de amonio (NH4SH)", 1.5, 3.0, rgb(0.72, 0.48, 0.30), 0.9, "Cinturones pardos/anaranjados"),
                             cloud("Nubes de agua (H2O)", 5.0, 7.0, rgb(0.55, 0.60, 0.68), 0.95, "Origen de los rayos (Galileo, Juno)")],
                            rgb(0.32, 0.45, 0.72), rgb(0.35, 0.18, 0.10), 12350.0,
                            {"type": "jets", "jets": 12, "max_mps": 150.0, "equator_mps": 100.0},
                            True,
                            "Hidrógeno metálico a partir de ~0,8-0,9 radios (modelos con Juno, incierto)."),
                        "surface": {"type": "none", "terrain_note": "Gigante gaseoso: no hay suelo."},
                        "physical_extra": None,
                        "render": {"kind": "gas", "color": rgb(0.90, 0.84, 0.72), "color2": rgb(0.66, 0.47, 0.32),
                                   "band_count": 18, "band_contrast": 0.9, "flattening": 0.06487, "turbulence": 0.6,
                                   "storms": [
                                       {"name": "Gran Mancha Roja", "lat": -22.4, "lon": 50.0, "width_km": 13500.0, "height_km": 10500.0,
                                        "color": rgb(0.78, 0.36, 0.22), "wind_mps": 120.0, "quality": "measured",
                                        "source": "Hubble OPAL: 15 590 km (2009) → 12 410 km (2020), 14 893 km (2021); vientos ~370-435 km/h"},
                                       {"name": "Óvalo BA (Mancha Roja Junior)", "lat": -33.5, "lon": 160.0, "width_km": 7000.0, "height_km": 5500.0,
                                        "color": rgb(0.88, 0.62, 0.55), "wind_mps": 100.0, "quality": "approximate", "source": "Hubble (2006)"}],
                                   "rings": [{"name": "Anillo principal", "inner_m": 122500e3, "outer_m": 129000e3, "opacity": 0.03,
                                              "color": rgb(0.55, 0.45, 0.38), "quality": "approximate", "source": "Voyager/Galileo"}]},
                    }, {"equatorial_radius": q(71492e3, "m", "measured", NSSDC + " (1 bar)"),
                        "polar_radius": q(66854e3, "m", "measured", NSSDC)}))

    B.append(planet("saturn", "Saturno",
                    "Gigante de H2/He con el sistema de anillos más extenso (radios 67 000-140 700 km, < 1 km de espesor). "
                    "Vientos ecuatoriales de hasta ~400-500 m/s y el hexágono polar norte (lados de ~14 500 km, 78° N).",
                    58232e3, 3.7931e16, 10.656, 10.656, 26.73, 0.499,
                    rotation_iau(40.589, 83.537, 38.90, 810.7939024, -0.036, -0.004, NSSDC), {
                        "atmosphere": gas_atmosphere(
                            "Saturn", 134.0, 84.0, 0.19, 59.5, 2.07,
                            {"max_mps": 400.0, "high_lat_mps": 150.0, "note": "Hasta 400 m/s (<30°), 150 m/s (>30°) (NSSDC)"},
                            "H2 96,3 %, He 3,25 %; CH4 4500 ppm, NH3 125 ppm, HD 110 ppm, C2H6 7 ppm (NSSDC)",
                            [cloud("Nubes de amoníaco (NH3)", 0.8, 1.6, rgb(0.95, 0.90, 0.75), 0.8, "Modelo de condensación (más profundas que en Júpiter)"),
                             cloud("Hidrosulfuro de amonio (NH4SH)", 3.0, 6.0, rgb(0.80, 0.65, 0.42), 0.9, "Modelo de condensación"),
                             cloud("Nubes de agua (H2O)", 10.0, 20.0, rgb(0.55, 0.58, 0.62), 0.95, "Modelo de condensación")],
                            rgb(0.45, 0.55, 0.72), rgb(0.40, 0.28, 0.15), 14100.0,
                            {"type": "broad", "max_mps": 400.0, "width_deg": 35.0},
                            True),
                        "surface": {"type": "none", "terrain_note": "Gigante gaseoso: no hay suelo."},
                        "render": {"kind": "gas", "color": rgb(0.92, 0.84, 0.62), "color2": rgb(0.80, 0.68, 0.46),
                                   "band_count": 16, "band_contrast": 0.45, "flattening": 0.09796, "turbulence": 0.3,
                                   "hexagon": {"lat": 78.0, "side_km": 14500.0, "wind_mps": 90.0, "color": rgb(0.45, 0.55, 0.60),
                                               "quality": "measured", "source": "Cassini (Godfrey 1988, Sánchez-Lavega 2014)"},
                                   "rings": [
                                       {"name": "Anillo D", "inner_m": 67000e3, "outer_m": 74500e3, "opacity": 0.03, "color": rgb(0.55, 0.50, 0.45)},
                                       {"name": "Anillo C", "inner_m": 74500e3, "outer_m": 92000e3, "opacity": 0.12, "color": rgb(0.62, 0.56, 0.48)},
                                       {"name": "Anillo B", "inner_m": 92000e3, "outer_m": 117500e3, "opacity": 0.85, "color": rgb(0.86, 0.80, 0.66)},
                                       {"name": "División de Cassini", "inner_m": 117500e3, "outer_m": 122050e3, "opacity": 0.05, "color": rgb(0.4, 0.38, 0.35)},
                                       {"name": "Anillo A", "inner_m": 122050e3, "outer_m": 136800e3, "opacity": 0.55, "color": rgb(0.80, 0.75, 0.64)},
                                       {"name": "Anillo F", "inner_m": 140180e3, "outer_m": 140700e3, "opacity": 0.3, "color": rgb(0.85, 0.82, 0.75)}],
                                   "rings_source": "USGS Planetary Nomenclature / tablas Voyager-Cassini (los límites varían ±1 % según la fuente)"},
                    }, {"equatorial_radius": q(60268e3, "m", "measured", NSSDC + " (1 bar)"),
                        "polar_radius": q(54364e3, "m", "measured", NSSDC)}))

    B.append(planet("uranus", "Urano",
                    "Gigante de hielo inclinado 97,8°: rueda sobre su órbita. El metano (2,3 %) absorbe el rojo y le da su "
                    "color cian. 76 K a 1 bar, vientos de hasta 250 m/s.",
                    25362e3, 5.7940e15, -17.24, 17.24, 97.77, 0.488,
                    rotation_iau(257.311, -15.175, 203.81, -501.1600928, pole_src=NSSDC), {
                        "atmosphere": gas_atmosphere(
                            "Uranus", 76.0, 53.0, 0.42, 27.7, 2.64,
                            {"max_mps": 250.0, "note": "0-250 m/s (NSSDC)"},
                            "H2 82,5 %, He 15,2 %, CH4 2,3 %; HD 148 ppm (NSSDC)",
                            [cloud("Nubes de metano (CH4)", 1.0, 1.5, rgb(0.80, 0.95, 0.97), 0.6, "Modelo de condensación"),
                             cloud("Sulfuro de hidrógeno (H2S)", 3.0, 5.0, rgb(0.62, 0.78, 0.80), 0.85, "Modelo; detectado por Gemini (2018)"),
                             cloud("Hidrosulfuro de amonio (NH4SH)", 20.0, 40.0, rgb(0.45, 0.55, 0.58), 0.95, "Modelo de condensación")],
                            rgb(0.45, 0.75, 0.85), rgb(0.12, 0.25, 0.30), 13000.0,
                            {"type": "ice", "equator_mps": -100.0, "max_mps": 250.0, "jet_lat": 60.0},
                            False),
                        "surface": {"type": "none", "terrain_note": "Gigante de hielo: no hay suelo."},
                        "render": {"kind": "gas", "color": rgb(0.66, 0.87, 0.90), "color2": rgb(0.58, 0.80, 0.84),
                                   "band_count": 6, "band_contrast": 0.06, "flattening": 0.02293, "turbulence": 0.1,
                                   "rings": [{"name": "Anillo ε", "inner_m": 51100e3, "outer_m": 51200e3, "opacity": 0.4, "color": rgb(0.5, 0.5, 0.5)},
                                             {"name": "Anillos 6-δ", "inner_m": 41800e3, "outer_m": 48300e3, "opacity": 0.04, "color": rgb(0.4, 0.4, 0.4)}]},
                    }, {"equatorial_radius": q(25559e3, "m", "measured", NSSDC + " (1 bar)")}))

    B.append(planet("neptune", "Neptuno",
                    "Gigante de hielo azul intenso por el metano. Los vientos más rápidos del Sistema Solar (hasta 580 m/s; "
                    "~2400 km/h medidos cerca de la Gran Mancha Oscura de 1989, desaparecida en 1994).",
                    24622e3, 6.8351e15, 16.11, 16.11, 28.32, 0.442,
                    rotation_iau(299.36, 43.46, 249.978, 541.1397757, pole_src=NSSDC), {
                        "atmosphere": gas_atmosphere(
                            "Neptune", 72.0, 55.0, 0.45, 19.7, 2.6,
                            {"max_mps": 580.0, "note": "0-580 m/s (NSSDC)"},
                            "H2 80 %, He 19 %, CH4 1,5 %; HD 192 ppm, C2H6 1,5 ppm (NSSDC)",
                            [cloud("Nubes de metano (CH4)", 1.0, 1.5, rgb(0.85, 0.92, 1.0), 0.5, "Nubes blancas altas (Voyager 2)"),
                             cloud("Sulfuro de hidrógeno (H2S)", 3.0, 5.0, rgb(0.45, 0.55, 0.85), 0.85, "Modelo de condensación"),
                             cloud("Hidrosulfuro de amonio (NH4SH)", 20.0, 40.0, rgb(0.25, 0.30, 0.55), 0.95, "Modelo de condensación")],
                            rgb(0.30, 0.45, 0.85), rgb(0.06, 0.08, 0.25), 13000.0,
                            {"type": "ice", "equator_mps": -400.0, "max_mps": 250.0, "jet_lat": 70.0},
                            False),
                        "surface": {"type": "none", "terrain_note": "Gigante de hielo: no hay suelo."},
                        "render": {"kind": "gas", "color": rgb(0.28, 0.44, 0.86), "color2": rgb(0.22, 0.35, 0.75),
                                   "band_count": 8, "band_contrast": 0.12, "flattening": 0.01708, "turbulence": 0.35,
                                   "storms": [{"name": "Mancha oscura (tipo Gran Mancha Oscura)", "lat": -22.0, "lon": 120.0,
                                               "width_km": 13000.0, "height_km": 6600.0, "color": rgb(0.10, 0.16, 0.42),
                                               "wind_mps": 600.0, "quality": "approximate",
                                               "source": "Voyager 2 (1989); manchas similares observadas por Hubble (2018)"}],
                                   "rings": [{"name": "Anillo Adams", "inner_m": 62900e3, "outer_m": 62950e3, "opacity": 0.1, "color": rgb(0.4, 0.38, 0.35)}]},
                    }, {"equatorial_radius": q(24764e3, "m", "measured", NSSDC + " (1 bar)")}))

    B.append(planet("pluto", "Plutón",
                    "Planeta enano de hielos de N2, CH4 y CO. Atmósfera tenue (~13 µbar) con neblinas azules; llanura helada "
                    "Sputnik Planitia (forma de corazón) y montañas de hielo de agua.",
                    1188e3, 8.70e11, -153.2928, 153.2928, 119.51, 0.52,
                    rotation_iau(132.99, -6.16, 302.695, 56.3625225, pole_src=NSSDC), {
                        "atmosphere": rocky_atmosphere(
                            1.3, 40.0, 50000.0, 28.0, 0.0, 30.0,
                            "N2 99 %, CH4 0,5 %, CO 0,05 % (NSSDC)",
                            {"zenith": rgb(0.02, 0.02, 0.05), "horizon": rgb(0.15, 0.22, 0.40), "sunset": rgb(0.3, 0.4, 0.7),
                             "space_limb": rgb(0.35, 0.55, 0.95)},
                            0.03, 1.0, 1.0e6, src=NSSDC + " (Pluto: ~13 µbar, 24-38 K)", quality="measured",
                            note="Neblinas azules en capas vistas por New Horizons (2015)."),
                        "surface": {"type": "solid", "terrain_profile": "pluto", "seed": 1188000,
                                    "terrain_note": "Topografía PROCEDURAL inspirada en Plutón (New Horizons); no son datos reales."},
                        "render": {"kind": "rocky", "color": rgb(0.82, 0.70, 0.58), "color2": rgb(0.45, 0.28, 0.22)},
                    }))
    return B


# Lunas curadas: id → (nombre, perfil, color, color2, descripción, atmósfera)
CURATED_MOONS = {
    ("Earth", "Moon"): ("moon", "Luna", "cratered_airless", rgb(0.55, 0.55, 0.55), rgb(0.32, 0.32, 0.33),
                        "Satélite de la Tierra y punto de partida. Superficie de regolito, mares de basalto y cráteres.", None),
    ("Mars", "Phobos"): ("phobos", "Fobos", "small_irregular", rgb(0.36, 0.33, 0.30), rgb(0.25, 0.23, 0.21),
                         "Luna irregular de Marte (27×22×18 km) con el cráter Stickney; cae hacia Marte ~2 m por siglo.", None),
    ("Mars", "Deimos"): ("deimos", "Deimos", "small_irregular", rgb(0.42, 0.38, 0.34), rgb(0.30, 0.28, 0.26),
                         "Pequeña luna de Marte (15×12×10 km), cubierta de regolito suave.", None),
    ("Jupiter", "Io"): ("io", "Ío", "io", rgb(0.90, 0.82, 0.45), rgb(0.55, 0.30, 0.12),
                        "El mundo más volcánico del Sistema Solar: más de 400 volcanes activos, lagos de lava y llanuras de azufre.", None),
    ("Jupiter", "Europa"): ("europa", "Europa", "europa", rgb(0.86, 0.80, 0.72), rgb(0.55, 0.35, 0.25),
                            "Corteza de hielo surcada de grietas (lineae) sobre un océano global de agua salada.", None),
    ("Jupiter", "Ganymede"): ("ganymede", "Ganímedes", "ganymede", rgb(0.62, 0.58, 0.52), rgb(0.38, 0.35, 0.32),
                              "La luna más grande del Sistema Solar (mayor que Mercurio), con campo magnético propio y terreno de surcos.", None),
    ("Jupiter", "Callisto"): ("callisto", "Calisto", "callisto", rgb(0.38, 0.35, 0.32), rgb(0.80, 0.80, 0.82),
                              "La superficie más craterizada conocida: oscura, antigua, con cráteres de hielo brillante.", None),
    ("Saturn", "Mimas"): ("mimas", "Mimas", "icy_cratered", rgb(0.80, 0.80, 0.80), rgb(0.62, 0.62, 0.63),
                          "Pequeña luna helada dominada por el cráter Herschel (130 km).", None),
    ("Saturn", "Enceladus"): ("enceladus", "Encélado", "enceladus", rgb(0.97, 0.97, 0.98), rgb(0.55, 0.75, 0.90),
                              "Hielo casi blanco puro (albedo ~1). Géiseres de agua en las 'rayas de tigre' del polo sur alimentan el anillo E.", None),
    ("Saturn", "Tethys"): ("tethys", "Tetis", "icy_cratered", rgb(0.88, 0.88, 0.88), rgb(0.70, 0.70, 0.72),
                           "Luna de hielo de agua con el gran cañón Ithaca Chasma.", None),
    ("Saturn", "Dione"): ("dione", "Dione", "icy_cratered", rgb(0.82, 0.82, 0.82), rgb(0.60, 0.60, 0.62),
                          "Luna helada con acantilados brillantes ('wispy terrain').", None),
    ("Saturn", "Rhea"): ("rhea", "Rea", "icy_cratered", rgb(0.78, 0.78, 0.78), rgb(0.58, 0.58, 0.60),
                         "Segunda luna de Saturno, hielo muy craterizado.", None),
    ("Saturn", "Titan"): ("titan", "Titán", "titan", rgb(0.85, 0.62, 0.30), rgb(0.35, 0.25, 0.15),
                          "Única luna con atmósfera densa (1,47 bar de N2, 94 K). Neblina naranja, dunas oscuras, ríos y lagos de "
                          "metano/etano líquido cerca de los polos (Cassini-Huygens).", "titan"),
    ("Saturn", "Iapetus"): ("iapetus", "Jápeto", "iapetus", rgb(0.80, 0.78, 0.74), rgb(0.12, 0.10, 0.09),
                            "Bicolor: un hemisferio oscuro como el carbón y otro brillante, con una cresta ecuatorial de 13 km.", None),
    ("Uranus", "Miranda"): ("miranda", "Miranda", "miranda", rgb(0.70, 0.70, 0.70), rgb(0.50, 0.50, 0.52),
                            "Mosaico caótico de terrenos ('coronae') y Verona Rupes, quizá el acantilado más alto del Sistema Solar (~20 km).", None),
    ("Uranus", "Ariel"): ("ariel", "Ariel", "icy_cratered", rgb(0.72, 0.72, 0.72), rgb(0.55, 0.55, 0.57),
                          "La luna más brillante de Urano, con valles de fallas.", None),
    ("Uranus", "Umbriel"): ("umbriel", "Umbriel", "icy_cratered", rgb(0.35, 0.35, 0.36), rgb(0.70, 0.70, 0.70),
                            "La más oscura de las grandes lunas de Urano.", None),
    ("Uranus", "Titania"): ("titania", "Titania", "icy_cratered", rgb(0.62, 0.60, 0.58), rgb(0.48, 0.47, 0.46),
                            "La mayor luna de Urano, con cañones de cientos de km.", None),
    ("Uranus", "Oberon"): ("oberon", "Oberón", "icy_cratered", rgb(0.55, 0.52, 0.50), rgb(0.40, 0.38, 0.37),
                           "Luna exterior de Urano, antigua y craterizada.", None),
    ("Neptune", "Triton"): ("triton", "Tritón", "triton", rgb(0.86, 0.78, 0.76), rgb(0.62, 0.50, 0.48),
                            "Órbita retrógrada (probable objeto capturado del cinturón de Kuiper); géiseres de nitrógeno y terreno de 'piel de melón'.",
                            "triton"),
    ("Pluto", "Charon"): ("charon", "Caronte", "charon", rgb(0.56, 0.54, 0.53), rgb(0.45, 0.25, 0.20),
                          "Compañera de Plutón (mitad de su tamaño); casquete polar rojizo (Mordor Macula).", None),
}

MOON_ATMOSPHERES = {
    "titan": rocky_atmosphere(
        1.467e5, 93.7, 20600.0, 27.8, 0.0012, 70.0,
        "N2 ~95 %, CH4 ~4,9-5,7 % cerca de la superficie (Huygens GCMS), hidrocarburos y tolinas",
        {"zenith": rgb(0.55, 0.38, 0.16), "horizon": rgb(0.85, 0.60, 0.28), "sunset": rgb(0.7, 0.4, 0.15),
         "space_limb": rgb(0.95, 0.65, 0.30)},
        1.0, 0.01, 30000.0,
        clouds=[{"name": "Neblina de tolinas", "bottom_m": 30000, "top_m": 300000, "color": rgb(0.85, 0.58, 0.25), "opacity": 0.9},
                {"name": "Nubes de metano", "bottom_m": 8000, "top_m": 20000, "color": rgb(0.9, 0.85, 0.75), "opacity": 0.3}],
        winds={"surface_mps": 1.0, "note": "Vientos suaves en superficie (Huygens); fuertes en la estratosfera"},
        src="Huygens HASI (Fulchignoni et al. 2005): 1467 hPa, 93,7 K", quality="measured",
        note="La neblina se aclaró a menos de ~20-30 km de altitud durante el descenso de Huygens; luz en superficie ~0,1-1 %."),
    "triton": rocky_atmosphere(
        1.4, 38.0, 14000.0, 28.0, 0.0, 30.0,
        "N2 con trazas de CH4 y CO (Voyager 2)",
        {"zenith": rgb(0.01, 0.01, 0.02), "horizon": rgb(0.10, 0.12, 0.18), "sunset": rgb(0.2, 0.25, 0.35),
         "space_limb": rgb(0.5, 0.6, 0.9)},
        0.02, 1.0, 1.0e6, src="Voyager 2 (1989): ~14 µbar, 38 K", quality="measured",
        note="Géiseres de nitrógeno de hasta 8 km de altura."),
}


def load_sources():
    el = json.load(open(os.path.join(SRC, "jpl_sat_elem.json"), encoding="utf-8"))["satellites"]
    ph = json.load(open(os.path.join(SRC, "jpl_sat_phys.json"), encoding="utf-8"))["satellites"]
    phys = {(p["planet"], p["name"]): p for p in ph}
    return el, phys


def epoch_jd(s):
    # "2000-01-01.5" → JD (TDB)
    y, m, d = s.split("-")
    y, m, d = int(y), int(m), float(d)
    if m <= 2:
        y -= 1
        m += 12
    a = y // 100
    b = 2 - a + a // 4
    return int(365.25 * (y + 4716)) + int(30.6001 * (m + 1)) + d + b - 1524.5


def fnum(x, default=0.0):
    try:
        return float(x)
    except (TypeError, ValueError):
        return default


PLANET_ID = {"Earth": "earth", "Mars": "mars", "Jupiter": "jupiter", "Saturn": "saturn", "Uranus": "uranus",
             "Neptune": "neptune", "Pluto": "pluto"}
PLANET_RADIUS = {"earth": 6371e3, "mars": 3389.5e3, "jupiter": 69911e3, "saturn": 58232e3, "uranus": 25362e3,
                 "neptune": 24622e3, "pluto": 1188e3}


def slug(name):
    t = name.lower()
    for a, b in (("á", "a"), ("é", "e"), ("í", "i"), ("ó", "o"), ("ú", "u"), ("ñ", "n"), ("/", "_"), (" ", "_"),
                 ("(", ""), (")", ""), ("'", "")):
        t = t.replace(a, b)
    return t


def sat_orbit(r):
    frame = r["frame"].lower()
    o = {
        "model": "satellite", "frame": frame,
        "epoch_jd": epoch_jd(r["epoch"]),
        "a_m": fnum(r["a_km"]) * 1000.0, "e": fnum(r["e"]), "w_deg": fnum(r["w_deg"]), "M_deg": fnum(r["M_deg"]),
        "i_deg": fnum(r["i_deg"]), "node_deg": fnum(r["node_deg"]), "period_s": fnum(r["P_days"]) * 86400.0,
        "apsis_period_s": fnum(r["Papsis_yr"]) * 365.25 * 86400.0,
        "node_period_s": fnum(r["Pnode_yr"]) * 365.25 * 86400.0,
        "quality": "measured",
        "source": "JPL SSD Planetary Satellite Mean Elements (%s, ref. %s)" % (r["ephemeris"], r["ref"]),
    }
    if frame == "laplace" and r["ra_deg"]:
        o["laplace_pole_ra"] = fnum(r["ra_deg"])
        o["laplace_pole_dec"] = fnum(r["dec_deg"])
    return o


def moon_body(r, phys):
    planet = r["planet"]
    pid = PLANET_ID[planet]
    key = (planet, r["name"])
    p = phys.get(key)
    cur = CURATED_MOONS.get(key)
    mid = cur[0] if cur else pid + "_" + slug(r["name"])
    if p and fnum(p["radius_km"]) > 0:
        radius = fnum(p["radius_km"]) * 1000.0
        r_q = q(radius, "m", "measured", "JPL SSD Planetary Satellite Physical Parameters")
    else:
        # Sin radio publicado en el JPL: satélites irregulares pequeños (descubiertos por su brillo débil).
        a_rel = fnum(r["a_km"]) * 1000.0 / PLANET_RADIUS[pid]
        radius = 1500.0 if planet in ("Jupiter", "Saturn") else (6000.0 if planet in ("Uranus", "Neptune") else 3000.0)
        if a_rel < 5.0:
            radius *= 2.0
        r_q = q(radius, "m", "estimated",
                "Radio no publicado por el JPL: valor típico de satélites irregulares débiles de " + planet)
    gm = fnum(p["gm_km3s2"]) * 1e9 if p and fnum(p["gm_km3s2"]) > 0 else None
    if gm:
        m_q = q(gm / G, "kg", "measured", "JPL SSD Planetary Satellite Physical Parameters (GM/G)")
    else:
        dens = 1500.0 if planet != "Mars" else 1900.0
        m_q = q(4.0 / 3.0 * math.pi * radius ** 3 * dens, "kg", "estimated",
                "Masa estimada con densidad típica de %d kg/m3" % dens)
    period = fnum(r["P_days"]) * 86400.0
    name_es = cur[1] if cur else r["name"]
    d = {
        "id": mid, "name": name_es, "kind": "moon" if cur else "moon_minor", "parent": pid,
        "description": cur[5] if cur else "Satélite de %s (elementos medios JPL)." % planet,
        "jpl_code": r["code"],
        "physical": {
            "mean_radius": r_q, "mass": m_q,
            "sidereal_rotation_period": q(abs(period), "s", "approximate",
                                          "Rotación síncrona supuesta (igual al periodo orbital)"),
        },
        "rotation": {"model": "synchronous", "quality": "approximate",
                     "source": "Rotación síncrona (cara fija hacia el planeta); válido para las lunas regulares"},
        "orbit": sat_orbit(r),
    }
    if cur:
        prof = cur[2]
        d["surface"] = {"type": "solid", "terrain_profile": prof, "seed": zlib.crc32(mid.encode()) % 9000000 + 1000,
                        "terrain_note": "Topografía PROCEDURAL inspirada en %s; no son datos reales." % name_es,
                        "colors_override": {"base": cur[3], "alt": cur[4]}}
        d["render"] = {"kind": "rocky", "color": cur[3], "color2": cur[4]}
        if cur[6]:
            d["atmosphere"] = MOON_ATMOSPHERES[cur[6]]
            d["render"]["kind"] = "clouded" if cur[6] == "titan" else "rocky"
        else:
            d["atmosphere"] = {"present": False}
        if mid == "moon":
            d["physical"]["sidereal_rotation_period"] = q(2360592.0, "s", "measured", NSSDC + " (Moon: 655.720 h)")
            d["physical"]["solar_day"] = q(2551443.0, "s", "measured", "Mes sinódico medio 29,53059 d (NSSDC)")
            d["physical"]["axial_tilt"] = q(1.54, "deg", "measured", "Ecuador lunar respecto a la eclíptica (IAU)")
            d["surface"]["seed"] = 1737400
            d["surface"]["terrain_note"] = "Topografía PROCEDURAL inspirada en terreno lunar. No representa los datos reales LOLA/LRO."
    else:
        d["surface"] = {"type": "solid", "terrain_profile": "small_irregular", "seed": int(fnum(r["code"])) + 77,
                        "terrain_note": "Satélite pequeño: forma y superficie PROCEDURALES (esfera craterizada)."}
        d["atmosphere"] = {"present": False}
        d["render"] = {"kind": "rocky", "color": rgb(0.45, 0.43, 0.41), "color2": rgb(0.32, 0.31, 0.30)}
    d["schema_version"] = 1
    return d


def main():
    os.makedirs(OUT, exist_ok=True)
    count = 0
    for b in major_bodies():
        b["schema_version"] = 1
        if "physical_extra" in b:
            del b["physical_extra"]
        json.dump(b, open(os.path.join(OUT, b["id"] + ".json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        count += 1
    el, phys = load_sources()
    minor = {}
    for r in el:
        if r["planet"] not in PLANET_ID:
            continue
        m = moon_body(r, phys)
        if m["kind"] == "moon":
            json.dump(m, open(os.path.join(OUT, m["id"] + ".json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        else:
            minor.setdefault(m["parent"], []).append(m)
        count += 1
    for pid, lst in minor.items():
        json.dump({"schema_version": 1, "collection": "moons_" + pid,
                   "source": "JPL SSD Planetary Satellite Mean Elements / Physical Parameters (data/sources)",
                   "bodies": lst},
                  open(os.path.join(OUT, "moons_" + pid + ".json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("cuerpos generados:", count)


if __name__ == "__main__":
    main()
