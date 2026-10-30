# El Sistema Solar de WE ARE ALONE? (Hito 3)

Este documento resume la investigación y cómo se convirtió en datos y modelos del juego. Los valores físicos
viven en `data/bodies/*.json` (generados por `tools/gen_bodies.py`), cada uno con su `quality` y su `source`.

## Lore
El jugador aparece en la **cara visible de la Luna** junto a su nave. **La Tierra ha sido destruida**: once
grandes fragmentos (celdas de Voronoi de la esfera original) se separan lentamente y giran sobre sí mismos
alrededor de un núcleo al rojo vivo. Los continentes siguen siendo reconocibles en las caras exteriores
(contornos aproximados en `data/earth_land.json`); las caras de rotura muestran corteza, manto y magma.
La Luna conserva su órbita (simplificación: la masa total no cambia). Todo esto es **ficción del juego** y así
está marcado en los datos (`terrain_note`, `quality`).

## Fuentes principales
| Tema | Fuente |
|---|---|
| Masas, radios, rotación, atmósferas | NASA NSSDCA Planetary Fact Sheets (Sol, Mercurio…Plutón), consultadas el 2026-10-11 |
| Órbitas de los planetas | JPL SSD *Approximate Positions of the Planets*, Tabla 1 (Standish & Williams 1992), válida 1800-2050 |
| Órbitas de 460 satélites | JPL SSD *Planetary Satellite Mean Elements* (copia en `data/sources/jpl_sat_elem.json`) |
| Masas y radios de 46 satélites | JPL SSD *Planetary Satellite Physical Parameters* (`data/sources/jpl_sat_phys.json`) |
| Orientación de rotación | IAU WGCCRE 2015 (Archinal et al. 2018); polos contrastados con NSSDC |
| Interior de Júpiter | Sonda Galileo (1995): pérdida de señal a ≈23 bar y ≈425 K, ~150 km bajo 1 bar; modelos con Juno (núcleo diluido; hidrógeno metálico hacia 0,8-0,9 radios, incierto) |
| Gran Mancha Roja | Hubble OPAL: 15 590 km (2009) → 12 410 km (2020) → 14 893 km (2021); vientos de 370-435 km/h |
| Hexágono de Saturno | Voyager/Cassini: 78° N, lados de ~14 500 km, vientos de ~300-450 km/h según la profundidad |
| Anillos de Saturno | Tablas Voyager/Cassini y USGS (D 67 000 → F 140 700 km; Cassini 117 500-122 050 km; espesor < 1 km) |
| Neptuno | Voyager 2 (1989): Gran Mancha Oscura (desapareció en 1994); vientos hasta 580 m/s (NSSDC) |
| Titán | Huygens HASI: 1467 hPa y 93,7 K en superficie; neblina hasta ~20-30 km; lagos polares (Cassini) |
| Venus | NSSDC (92 bar, 737 K, CO₂ 96,5 %); nubes de H₂SO₄ en tres capas entre ~47,5 y 70 km; superrotación de ~100 m/s |

## Cuerpos incluidos (470)
- **Sol** (estrella; fotosfera 5772 K; la nave se destruye al acercarse).
- **8 planetas** con elementos JPL y **Plutón** (elementos NSSDC J2000).
- **Todas las lunas catalogadas por el JPL (460)**: Saturno 291, Júpiter 115, Urano 30, Neptuno 16, Plutón 5,
  Marte 2 y la Luna. 21 tienen ficha propia con superficie diseñada; el resto usa la forma genérica de satélite
  pequeño. 414 no tienen radio publicado por el JPL: se usa un valor típico **marcado como `estimated`**.

## Modelos
### Efemérides (`Ephemeris`, `SolarSystem`)
Ecuación de Kepler con los elementos y sus tasas; satélites en su plano de referencia (eclíptica, plano de
Laplace o ecuador del planeta) con precesión del periastro y del nodo; `P` del JPL es el periodo sidéreo (la
longitud media avanza 360°/P). Pruebas: Tierra en J2000 (−0,1771; 0,9672 UA) igual que DE; longitud del Sol
280,4°; Marte cierra su órbita en 687 d; Ío en un periodo; oblicuidad terrestre 23,44°.

### Atmósferas (`AtmosphereModel`)
- Rocosas: `P = P0·e^(−z/H)`, `T = max(T0 − Γz, Tmin)`, `ρ = Pμ/(RT)`.
- Gigantes: estratosfera por encima de 1 bar; adiabática seca por debajo (`Γ = g/cp`). En Júpiter da **≈430 K
  en el nivel de 23 bar**, como midió Galileo (≈425 K); ese nivel queda a ~125 km bajo 1 bar (Galileo ≈150 km;
  la referencia de profundidad es incierta).
- Capas de nubes por presión: Júpiter NH₃ 0,5-0,9 bar, NH₄SH 1,5-3 bar, H₂O 5-7 bar (modelo de condensación;
  la sonda Galileo cayó en una zona casi despejada). Saturno, Urano y Neptuno con capas más profundas (modelos).
- Vientos zonales por latitud (chorros alternos en Júpiter, chorro ecuatorial ancho en Saturno, ecuador
  retrógrado y chorros a ~60-70° en Urano y Neptuno).

### Lo que se siente al entrar
- **Arrastre** con el viento real; **calentamiento de entrada** (Sutton-Graves) con plasma visible.
- **Limitador atmosférico** en Arcade: la velocidad se reduce para que el casco no supere ~1500 K.
- **Presión**: el casco de la Kestrel aguanta 100 bar (valor **ficticio** de diseño). En Venus (92 bar) se puede
  aterrizar; en Júpiter, a unos cientos de km bajo las nubes, el casco se aplasta → rescate de emergencia
  (ficticio, por jugabilidad).
- **Luz**: se apaga con la profundidad y las nubes; en las nubes de agua de Júpiter y Saturno hay **rayos**.
- **Sol**: la radiación absorbida calienta el casco (`T ≈ (q/εσ)^¼`); dentro de la fotosfera, destrucción.
- **Traje**: aguanta hasta 5 bar y 600 K (ficticio): la superficie de Venus mata en segundos.

### Superficies
Perfiles propios: Mercurio, Venus (llanuras volcánicas), Marte (casquetes), Ío (calderas volcánicas oscuras en
azufre), Europa (grietas pardas sobre hielo), Ganímedes (surcos claros), Calisto (saturada de cráteres), Titán
(dunas ecuatoriales y lagos de metano en latitudes altas), Encélado ("rayas de tigre" en el polo sur), Jápeto
(bicolor + cresta ecuatorial), Miranda (cañones), Tritón (casquete sur rosado), Plutón (llanuras heladas
brillantes), Caronte (polo rojizo) y satélites pequeños. El relieve se escala con el radio del cuerpo.
**Todo el relieve es procedural**: no reproduce la topografía real de ningún cuerpo.

## Licencias de los datos
Datos de la NASA y del JPL: dominio público (obra del gobierno de EE. UU.). Los contornos continentales se
trazaron a mano de forma aproximada para este proyecto.
