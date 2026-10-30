# Mediciones de rendimiento

Hardware: Intel HD Graphics 630 (driver 31.0.101.2140), i5-7400, 16 GB, Windows 10.
Renderizador: Compatibility → ANGLE 2.1.1 sobre Direct3D 11 (Godot lo elige automáticamente).
Calidad: `medium` (16 segmentos por parche, split_factor 1,5). Resolución 1280×720.
Comando: `tools/bench.ps1` (= `--benchmark --world=<id> [--novsync]`). Fecha: 2026-10-10.

## Sin vsync (coste real por fotograma)

| Mundo | Fase | FPS medios | ms medios | ms p99 | Parches dibujados | Primitivas | RAM estática | VRAM |
|---|---|---|---|---|---|---|---|---|
| Prototipo-A (R 6.000 km) | suelo, 1ª persona | 205 | 4,9 | 6,1 | 465 | 157 k | 91 MB | 34 MB |
| Prototipo-A | suelo, 3ª persona | 191 | 5,2 | 6,5 | 465 | 174 k | 91 MB | 34 MB |
| Prototipo-A | caminando | 191 | 5,2 | 6,2 | 483 | 174 k | 92 MB | 35 MB |
| Prototipo-A | ascenso a 420 km | 233 | 4,3 | 8,3 | 132 | 34 k | 77 MB | 28 MB |
| Prototipo-A | órbita (420 km) | 294 | 3,4 | 4,0 | 132 | 51 k | 77 MB | 28 MB |
| Luna (R 1.737,4 km) | suelo, 1ª persona | 204 | 4,9 | 5,6 | 417 | 223 k | 91 MB | 29 MB |
| Luna | caminando | 201 | 5,0 | 7,4 | 432 | 212 k | 92 MB | 30 MB |
| Luna | órbita (420 km) | 324 | 3,1 | 3,8 | 90 | 38 k | 75 MB | 23 MB |

Con vsync activado (por defecto) todas las fases se mantienen en 58–60 FPS con p99 ≤ 22 ms.

## Con el cuerpo completo y la cámara corporal (ADR-009), sin vsync

| Mundo | Fase | FPS | ms | ms p99 | Llamadas de dibujo |
|---|---|---|---|---|---|
| Prototipo-A | suelo, 1ª persona | 193 | 5,2 | 6,3 | 186 |
| Prototipo-A | mirando los pies | 310 | 3,2 | 3,7 | 51 |
| Prototipo-A | 3ª persona caminando | 185 | 5,4 | 5,6 | 212 |
| Prototipo-A | corriendo, 1ª persona | 170 | 5,9 | 8,6 | 185 |
| Luna | suelo, 1ª persona | 201 | 5,0 | 6,7 | 160 |
| Luna | "loping", 1ª persona | 186 | 5,4 | 10,6 | 172 |
| Luna | órbita | 269 | 3,7 | 5,5 | 51 |

## Con los efectos de vista (ADR-010), sin vsync — Prototipo-A

| Fase | FPS | ms | ms p99 |
|---|---|---|---|
| suelo, 1ª persona | 155 | 6,5 | 9,8 |
| enfocando | 189 | 5,3 | 8,3 |
| asomado | 159 | 6,3 | 8,3 |
| mirando al Sol (brillo + visor oscurecido) | 201 | 5,0 | 5,0 |
| corriendo, 1ª persona | 163 | 6,1 | 7,9 |
| órbita | 225 | 4,4 | 4,6 |

La refracción del visor (copia de pantalla) y las capas del casco cuestan ≈1,2 ms; se puede desactivar en Pausa.

## Nave (Hito 2), Luna, sin vsync — `tools/ship_tour.ps1 -NoVsync`

| Escena | Media: FPS | Media: llamadas | Alta (sombras): FPS | Alta: llamadas |
|---|---|---|---|---|
| Exterior, nave posada | 93–122 | 320–380 | 52–59 | 750–980 |
| Interiores (cámara superpuesta) | 113–132 | 180–300 | 54–64 | 430–650 |
| Sentado en la cabina | 145 | 172 | 64 | 430 |
| Vuelo, vista exterior | 86 | 352 | 45 | 599 |
| Vuelo, vista de cabina | 93 | 167 | 47 | 341 |

Primer intento: 1.500 llamadas de dibujo y 30 FPS porque el SubViewport de la cámara superpuesta se
renderizaba siempre (aunque estuviera oculto); ahora sólo se actualiza cuando la cámara está dentro de la nave.

## Carga y generación

- Terreno inicial listo (hasta el nivel máximo, con colisión): 2,6–6,6 s con render; 2,0–2,5 s headless.
- Regeneración tras un desplazamiento de 10 km: ≈0,9 s.
- Generación de un parche (16×16 + corona + faldones + color): 5–7 ms en un hilo de trabajo.
- Hilo principal (headless, carga inicial): ≈0,6–0,8 ms por fotograma para todo el sistema de terreno.

## Historial de optimizaciones

1. **Oscilación de colisiones** (corregido): un hijo listo creaba su colisión y se ocultaba en la misma
   pasada si un hermano no estaba listo → 45 ms/fotograma creando y destruyendo `ConcavePolygonShape3D`.
   Solución: recorrido en dos fases (decidir lista de dibujado, luego aplicar diferencias) y colisión sólo en los
   5 niveles más finos. Carga inicial: 96 s → 2 s (headless).
2. **Criterio LOD**: `distancia−radio < 2·arista` daba 1.434 parches (≈730 k triángulos). Con
   `distancia al centro < 1,5·arista`: 465 parches.
3. **WorkerThreadPool**: las tareas de baja prioridad se limitan a una fracción de los hilos
   (`low_priority_thread_ratio`); las tareas de terreno pasan a alta prioridad y se despachan cada fotograma.


## Hito 2.5 — nave rediseñada (57 m), Luna, calidad media, con vsync (59 Hz) — `--ship-tour --quality=medium`

| Escena | FPS medios | Llamadas de dibujo |
|---|---|---|
| Exterior de la nave (5 vistas) | 49–53 | 440–490 |
| Interiores (11 salas) | 53–58 | 224–377 |
| Sentado en el puesto de pilotaje | 58 | 260 |
| Despegue / vuelo (exterior y cabina) | 31–37 | 297–518 |
| Paseo espacial junto a la nave | 55 | 243 |

El vuelo baja de los 59 FPS del monitor a 31–37: queda pendiente perfilarlo en vuelo (la generación de terreno
en movimiento es la principal sospechosa).

### Carga del terreno (prueba de humo, Luna, sin cabeza, `--fixed-fps 60`)
| Medida | Antes (ADR-004) | Después (ADR-020) |
|---|---|---|
| Regeneración completa tras un vuelo de 10 km | 2851 ms | 2542–2552 ms |
| Detalle máximo bajo el jugador | — | 2121 ms (2175 ms sin descenso especulativo) |
| Árbol + despacho por fotograma (primera versión, con DVec3) | 0,62 ms | 7,1 ms → corregido a 2,3–3,0 ms (centros en 32 bits, prioridad precalculada) |


## Ronda 10 — HD 630, OpenGL nativo, calidad alta, vsync — `--perf-tour --quality=high` y `--base-shots`

| Escena | FPS | Notas |
|---|---|---|
| Exterior junto a la nave | 57 | |
| Pasillo de la nave | 45 | paredes compartidas en lotes que nunca se ocultan |
| Cabina pilotando | 63 | |
| Vuelo bajo | 69 | |
| Espacio (150 km) | 58 | |
| Frente a la Tierra rota (2,4 R) | 21 → 39 → 46 | sombreado único, cono de fragmentos, restos en CPU agrupados |
| Base LF-01 (13 vistas, interior y exterior) | 55-60 | 100-600 llamadas; salas visibles por puertas abiertas |

Coste del cielo frente a la Tierra (experimentos): sin restos orbitales +5 ms, sin fragmentos +2 ms; sin cuerpos 73 FPS.

### Tirones (sonda `--judder-probe`, 300 m/s a 150 m del suelo, FPS limitados a 45)
| | Avance por fotograma / esperado (desviación) | Cámara respecto a la cabina |
|---|---|---|
| Sin interpolación | 0,26-0,37 | — |
| Con interpolación (ADR-042) | 0,03-0,05 | 0,1 mm (máx. 2,6 mm) |

## Ronda 11 — HD 630, calidad alta, vsync, SIN otra copia del juego abierta
| Escena | FPS | Llamadas |
|---|---|---|
| Base LF-01 (12 vistas interiores y exteriores) | 55-60 | 109-669 |
| Exterior junto a la nave (la base a 1,5 km en el horizonte) | 55,5 | 571 (842 antes de limitar a 80 m el detalle interior de la base) |
| Pasillo / cabina / vuelo bajo / espacio / Tierra | 45 / 62 / 68 / 59 / 47 | |

Nota: las cifras de 13-26 FPS de la ronda 10 en la base estaban falseadas por otra copia del juego abierta a la vez.
