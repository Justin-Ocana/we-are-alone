# Hitos verificables

Un hito sólo se marca como terminado con evidencia: pruebas, smoke test, benchmark o capturas.

## Hito 0 — Viabilidad técnica ✅ (2026-10-10)
- [x] Hardware inspeccionado: HD 630, i5-7400, 16 GB, Windows 10.
- [x] Herramientas verificadas: Godot 4.7.2 oficial portable (ejecutado `--version`), git, Python 3.11, .NET.
- [x] Documentación oficial consultada: Large World Coordinates, renderizadores (Compatibility: 24 bits sin Z
      inversa), APIs seguras entre hilos, CharacterBody3D, JPL Horizons API v1.3, ficha NSSDC de la Luna.
- [x] Arquitectura de coordenadas definida (ADR-003) y riesgos documentados (ARCHITECTURE.md).

## Hito 1 — Primera experiencia jugable ✅ (2026-10-10)
| Requisito | Evidencia |
|---|---|
| Astronauta de 1,85 m | `Units.ASTRONAUT_HEIGHT_M`, cápsula 1,85 m; test `test_astronaut_scale`; captura 3ª persona |
| Caminar sobre un planeta esférico | Smoke: 53,8 m (Prototipo-A) y 49,2 m (Luna) en 10 s, sobre el suelo, 0 salvaguardas |
| Gravedad hacia el centro, según el cuerpo | Smoke: g local 8,9929 / 1,6242 m/s²; `up_direction` radial; salto 0,48 m vs 2,74 m (teóricos 0,50/2,77) |
| Cambiar 1ª/3ª persona | Tecla V; benchmark fases `suelo_1p`/`suelo_3p` con capturas |
| Curvatura del horizonte | Capturas de ascenso a 3, 40 y 420 km; posición del limbo coherente con R (ver PERFORMANCE/README) |
| Moverse sin perder precisión | Smoke: vuelo de 10.033 m con 9 recentrados, posición local acotada, aterrizaje correcto; tests de origen flotante |
| Terreno que se carga alrededor | Quadtree hasta el nivel 19/19 (Prototipo-A) y 17/17 (Luna); regeneración en 0,9 s tras 10 km |
| Planeta grande, no una isla | Radios reales: 6.000 km (ficticio) y 1.737,4 km (Luna, NSSDC) |
| Rendimiento en el hardware objetivo | ≈5 ms/fotograma sin vsync, 60 FPS con vsync (PERFORMANCE.md) |

### Hito 1.5 — Cuerpo e inmersión ✅ (2026-10-10)
| Requisito | Evidencia |
|---|---|
| Modelo de astronauta básico pero completo | `AstronautRig` (traje, casco con visor, mochila PLSS, módulo de pecho, guantes, botas); capturas en 3ª persona |
| Verse los pies, las manos y el cuerpo | Capturas `mirar_pies` (muslos, rodillas, punteras, guantes) y `mirar_manos` |
| Pies apoyados sin deslizar | IK con rayos; smoke: tobillos a 6–8 cm sobre los pies del cuerpo; test `test_leg_ik_reaches_target` |
| Cámara inmersiva (no flotante) | Cámara en los ojos del cuerpo; smoke: cámara a 1,700 m; estabilización, inercia, aterrizaje, alabeo, FOV |
| Marcha según la gravedad | Tests `test_body` (Froude, zancada, loping lunar); smoke: RUN en Prototipo-A y LOPE en la Luna |
| Casco / interfaz diegética | `HelmetOverlay` (visor, brújula, lecturas) |
| Rendimiento | 150–310 FPS sin vsync en HD 630 (PERFORMANCE.md) |

### Hito 1.6 — Efectos de vista ✅ (2026-10-10)
| Requisito | Evidencia |
|---|---|
| Enfoque con clic derecho | Captura `enfocar` (FOV 32°, HUD atenuado) |
| Asomarse con Q/E y colisión | Captura `asomarse`; rayos laterales limitan la inclinación |
| Sol en el visor: brillo, oscurecimiento automático, imagen residual | Capturas `mirar_sol` y `residual` |
| Cristal del visor (distorsión/dispersión, desactivable) | Pausa → "Distorsión del cristal del visor" |
| FOV dinámico en vuelo | `BodyCamera` (log10 de la velocidad) |
| Rendimiento | 155–230 FPS sin vsync en HD 630 (≈+1,2 ms) |

## Hito 2 — Nave transitable y pilotable ✅ (2026-10-10)
Evidencia automática: `tools/ship_smoke.ps1` (44/44), `tools/run_tests.ps1` (49/49), `tools/smoke.ps1` (35/35),
capturas y medición con `tools/ship_tour.ps1`. Procedimiento manual: [MANUAL_TESTS.md](MANUAL_TESTS.md).

| # | Criterio | Estado | Evidencia |
|---|---|---|---|
| 1 | Carga y ejecución sin errores | ✅ | Arranque interactivo y headless sin errores de script |
| 2 | Exterior coherente y reconocible | ✅ (estilizado) | Capturas `ship_ext_*`: cabina, morro, góndolas, alas, deriva, toberas, luces, rampa |
| 3 | Ocho áreas construidas y conectadas | ✅ | `test_eight_required_areas_exist`, `test_all_rooms_reachable_from_airlock`; smoke: las 8 visitadas a pie |
| 4 | Entrar y salir por la esclusa | ✅ | Smoke: rampa → esclusa (ciclo) → pasillo; y salida inversa |
| 5 | Recorrer las habitaciones | ✅ | Smoke: recorrido completo sin atascos |
| 6 | Colisiones en paredes, suelo y mobiliario | ✅ | Smoke: rutas que esquivan mobiliario; mínimo sobre el suelo −0,001 m |
| 7 | No atravesar el casco | ✅ | Colisión de casco continua salvo la puerta exterior; las ventanas están cerradas en la colisión |
| 8 | Nave pilotable | ✅ | Smoke: despegue, aceleración, giros, aterrizaje |
| 9 | Velocidad objetivo modificable | ✅ | W/S, rueda, X; `test_target_clamped_to_regime` |
| 10 | Aceleración y frenado graduales | ✅ | Smoke: 10 m/s tras 1 s con objetivo 40; `test_gradual_acceleration_and_cruise` |
| 11 | Interfaz con velocidad actual y objetivo | ✅ | `PilotHud` (barra logarítmica + cifras) y pantallas de cabina; captura `ship_vuelo_*` |
| 12 | Piloto automático mantiene rumbo y velocidad | ✅ | Smoke: error 0,00° y 40,0 m/s tras 10 s; `test_autopilot_holds_heading_and_speed` |
| 13 | Recuperar el control manual | ✅ | Smoke: el alabeo manual lo desactiva |
| 14 | Cámara exterior sigue a la nave real | ✅ | Smoke: a 49,5 m de la nave en vuelo |
| 15 | Caminar dentro mientras la nave se traslada y gira | ✅ | Smoke: cabina → máquinas a 40 m/s con giros de 60° y 20° |
| 16 | Cambios de modo sin entradas bloqueadas ni cámaras erróneas | ✅ (auto) / manual pendiente | Smoke: mandos liberados al levantarse, cámara correcta; M11 manual |
| 17 | Gravedad planetaria y movimiento fuera intactos | ✅ | `tools/smoke.ps1` 35/35; smoke de la nave: 1,624 m/s² al salir |
| 18 | Configuración gráfica prevista | ✅ (media) / ⚠️ alta | Media: 86–145 FPS sin vsync; Alta (sombras): 45–64 FPS |
| 19 | Sin errores críticos ni referencias rotas | ✅ | Ejecuciones limpias |
| 20 | Estructura preparada para multijugador | ✅ (arquitectura) | ADR-015: estado/entradas separados, listas de astronautas, plan de sincronización |

Las pruebas manuales M1–M12 (sensación real con ratón) no las he podido ejecutar yo; están descritas para el jugador.

### Hito 2.5 — Nave grande, física a bordo y sensaciones ✅ (2026-10-10)
- Nave rediseñada (57 m, casco liso, 8 asientos, sala común) — ADR-021.
- Gravedad aparente a bordo, ingravidez, caída libre con giro, propulsores del traje, mareo, salud y desmayo — ADR-018.
- Cámara libre sentado (clic derecho), piloto automático al levantarse, estacionamiento de la nave vacía,
  frenado de emergencia a cualquier velocidad, llamada de la nave (B).
- Efectos de cámara (golpes, motores, inercia, pendientes, enfoque), HUD del casco nuevo, efectos de pantalla,
  F2 oculta la interfaz — ADR-019. Carga del terreno más rápida a gran velocidad — ADR-020.
- Verificado: 58 pruebas unitarias, 35/35 humo de superficie, 63/63 humo de la nave, recorrido con capturas.
- Ronda 2 (ADR-022): música por megafonía (M), puerta del puente, ventana en el suelo del pasillo, mejor luz,
  piloto automático que conserva la inclinación, sin desmayo, corrección de "levantarse de cabeza".
  Verificado: 60 pruebas unitarias, 65/65 humo de la nave.
- Ronda 3 (ADR-023): luces interiores que por fin iluminan (error de capas de cámara), gravedad artificial con G
  (sólo el piloto), indicador del planeta más cercano al pilotar. Verificado: 66/66 humo de la nave, sonda de luces.

## Hito 3 — Sistema Solar ✅ (2026-10-11)
- Catálogo de 470 cuerpos con calidad y fuente (Sol, 8 planetas, Plutón y las 460 lunas del JPL) — ADR-024.
- Efemérides keplerianas en la fecha real; cielo analítico con todos los cuerpos a tamaño real — ADR-025.
- Lore: se aparece en la cara visible de la Luna; la Tierra está destruida en fragmentos reconocibles — ADR-026.
- Cambio de cuerpo dominante, mapa (Tab), viaje con piloto automático y salto ficticio — ADR-027/028.
- Atmósferas físicas, descenso en gigantes gaseosos, rayos, aplastamiento, calor de entrada, aterrizaje en Venus — ADR-029.
- Superficies propias para 16 mundos — ADR-030. Investigación y fuentes en `docs/SOLAR_SYSTEM.md`.
- Ajustes de jugabilidad: caminar a cualquier velocidad, marcadores estables, entrada libre a los planetas,
  viajes de ~2 min, mapa con órbitas/zoom/lunas, modo fiesta y más ventanas — ADR-031.
- Pendiente del plan original: importador de JPL Horizons en línea (se usan las tablas del JPL guardadas; sin red).

## Ronda 7 — «WE ARE ALONE?» ✅ (2026-10-11)
- Cooperativo local a pantalla dividida con mando, etiquetas y "nadie se queda atrás" — ADR-032.
- Menú principal, opciones, controles, pausa y pantalla de carga nuevos — ADR-033.
- Escáner, muestras, laboratorio, puestos de la nave, menú rápido, diario, foto y partida guardada — ADR-034.
- Personalización del astronauta y emotes — ADR-035. Nueva identidad visual y nombre — ADR-036.
- Cielos con espesor óptico, nubes 3D, rendimiento del mapa y de las sombras — ADR-037. Audio sintetizado — ADR-038.

## Ronda 8 — Aspecto del menú en el juego ✅ (2026-10-11)
- Materiales de la nave con chapa, juntas en relieve, suciedad y desgaste; asientos nuevos — ADR-039.
- Imagen: AgX, resplandor, etalonaje, destello del Sol, grano y viñeta; HUD de pilotaje compacto — ADR-039.
- Vía Láctea y estrellas que giran con el cielo real, Tierra incandescente con halo y restos, su resplandor
  naranja, eclipses por el propio cuerpo y regolito oscuro — ADR-040. Sonidos de interfaz suaves.

## Ronda 9 — Rendimiento ✅ (2026-10-11)
- OpenGL nativo, una sola cámara cerca del suelo, salas ocultas, HUD a ritmo reducido, cielo a 10 Hz — ADR-041.

## Ronda 10 — Base LF-01, prólogo y en línea ✅ (2026-10-11)
- Fallos: paredes de la nave que desaparecían, tirones (interpolación de física), sacudidas fantasma de cámara,
  aterrizaje automático suave, Tierra rota 21 → 46 FPS — ADR-041/042.
- Base lunar LF-01 de MacSpaces (22 salas), prólogo completo con 22 audios por evento, mensaje de Magnus con
  subtítulos, objetivos y marcador — ADR-043. Verificado: `--prologue-smoke` 44/44.
- En línea hasta 6 jugadores con el PC como anfitrión (ENet + UPnP + red local), salas y nombres — ADR-044.
  Verificado: `--net-smoke` con dos procesos.

## Ronda 11 — Correcciones y mecánicas ✅ (2026-10-12)
- Colisiones de la base, cápsulas para 6 jugadores, compuerta del hangar real, esclusa reversible, gravedad artificial,
  cámara estable, vuelo progresivo, aterrizaje sin atascos, llamada rápida — ADR-045.
- Nuevas mecánicas: componentes del NEXUS (6 mundos) y balizas de exploración.

## Ronda 12 — Chat de voz y sala de espera ✅ (2026-10-13)
- Voz real por la red: proximidad espacial (distancia, dirección, muros, eco, casco), radio semidúplex con canales,
  canal de la nave por megafonía, indicadores y pestaña «Voz» — ADR-046.
- Sala de espera con «Listo», inicio sólo del anfitrión con todos listos, carga sincronizada y salida simultánea —
  ADR-047. Verificado: `tools/net_smoke.ps1` con tres procesos (anfitrión 15/15, invitados 7/7 y 7/7).

## Ronda 13 — Voz limpia, bases del NEXUS y registros de audio ✅ (2026-10-16)
- Voz de proximidad sin efectos; sólo la radio los tiene — ADR-048.
- Instalaciones del NEXUS en el lado de día y en terreno llano; bases procedurales con 6–9 módulos — ADR-048.
- Al recoger cada pieza del NEXUS suena su registro de audio. Verificado: `--nexus-smoke` 75/75.

## Ronda 14 — Música, megafonía y paquete para amigos ✅ (2026-10-16)
- 12 pistas de banda sonora en rotación (8 CC0 nuevas), controles completos de la música de la nave — ADR-049.
- Música de la nave compartida en línea: lo que pone cualquiera lo oyen todos.
- `build/WeAreAlone.zip` (.exe + .pck + LEEME) con `tools/build.ps1`; versión y avisos de conexión en línea.

## Hito 4 — Viajes espaciales ⏳
## Hito 5 — Generación procedural ⏳
## Hito 6 — Optimización y expansión ⏳
