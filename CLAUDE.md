# CLAUDE.md — Reglas permanentes de WE ARE ALONE? (antes REAL SPACE EXPLORER)

Juego de exploración espacial a **escala real** en Godot 4.7.2 (GDScript, renderizador
Compatibility). Núcleo: exploración, libertad, sensación de escala. Sin combate, árboles de habilidades ni
progresión artificial. Cooperativo local a pantalla dividida (ADR-032) y en línea hasta 6 jugadores con el PC de
un jugador como anfitrión (ADR-044). La partida nueva empieza con el prólogo en la base lunar LF-01 (ADR-043).

## Entorno verificado
- Windows 10 Pro, i5-7400 (4 núcleos), 16 GB RAM, **Intel HD Graphics 630** (sin GPU dedicada).
- Motor: `..\Godot_v4.7.2-stable_win64.exe` (binario oficial portable, precisión simple, sin .NET).
  Por defecto OpenGL nativo (ANGLE triplicaba el coste por llamada; ADR-041); ANGLE es una opción de Gráficos.
- Python 3.11, git y .NET están instalados pero el juego no depende de ellos.

## Comandos (desde la carpeta del proyecto)
```
..\Godot_v4.7.2-stable_win64.exe --path .                                  # jugar (menú)
..\Godot_v4.7.2-stable_win64.exe --path . -- --world=moon                  # directo a un mundo
..\Godot_v4.7.2-stable_win64.exe --headless --path . --import              # tras añadir class_name nuevos
..\Godot_v4.7.2-stable_win64.exe --headless --path . -- --run-tests        # pruebas unitarias
..\Godot_v4.7.2-stable_win64.exe --headless --fixed-fps 60 --path . -- --smoke-test   # integración
..\Godot_v4.7.2-stable_win64.exe --path . -- --benchmark --world=proto_a [--novsync]  # rendimiento + capturas
..\Godot_v4.7.2-stable_win64.exe --headless --fixed-fps 60 --path . -- --ship-smoke     # integración de la nave
..\Godot_v4.7.2-stable_win64.exe --path . -- --ship-tour [--novsync] [--quality=medium] # capturas de la nave
..\Godot_v4.7.2-stable_win64.exe --headless --fixed-fps 60 --path . -- --exploration-smoke  # escáner, puestos, guardado
..\Godot_v4.7.2-stable_win64.exe --path . -- --world=moon --coop     # cooperativo (jugador 2 = primer mando)
..\Godot_v4.7.2-stable_win64.exe --path . -- --menu-shots | --coop-shots | --map-shots | --descent-tour | --perf-probe
..\Godot_v4.7.2-stable_win64.exe --headless --fixed-fps 60 --path . -- --prologue-smoke   # prólogo en la base LF-01
..\Godot_v4.7.2-stable_win64.exe --path . -- --base-shots | --prologue-shots | --perf-tour | --judder-probe [--nosmooth]
..\Godot_v4.7.2-stable_win64.exe --headless --fixed-fps 60 --path . -- --nexus-smoke   # bases del NEXUS (5 mundos)
..\Godot_v4.7.2-stable_win64.exe --path . -- --nexus-shots [--only=mars]                 # capturas de las bases del NEXUS
..\Godot_v4.7.2-stable_win64.exe --headless --path . -- --audio-smoke                 # banda sonora y megafonía
powershell tools/build.ps1                                                  # paquete para compartir: build/WeAreAlone.zip
powershell tools/net_smoke.ps1                                              # red: anfitrión + 2 invitados, sala y voz (sin --fixed-fps)
python tools/gen_audio.py                                                 # regenera TODO el audio (ADR-038)
```
Atajos: `tools/*.ps1`. Las capturas y resultados del benchmark quedan en
`%APPDATA%\WeAreAlone\bench\` (carpeta de usuario propia: el nombre del juego lleva «?», que Windows no admite).

## Reglas de unidades y escala (innegociables)
- SI en todo el código: metros, segundos, kilogramos, m/s, m/s². Grados sólo en datos/JSON e interfaz.
- Astronauta 1,85 m (`Units.ASTRONAUT_HEIGHT_M`), ojos a 1,70 m. Toda geometría humana se dimensiona en metros reales.
- **Nunca** alterar silenciosamente radios, masas o distancias para resolver un problema técnico.
  Si hace falta una transformación de representación, debe ser explícita, documentada y probada.
- Cada dato físico en `data/` lleva `quality` (`measured|estimated|approximate|fictional`) y `source`.
- El terreno de cuerpos reales es procedural y debe declararlo (`terrain_note`). No afirmar superficies conocidas.

## Sistema Solar (ADR-024..030)
- Los datos de cuerpos se GENERAN: editar `tools/gen_bodies.py` y ejecutarlo; no editar `data/bodies/*.json` a mano.
- El juego trabaja en el marco fijo del cuerpo DOMINANTE (`SurfaceWorld.body`); todo lo demás se sitúa con
  `SolarSystem` (doble precisión). El cambio de cuerpo pasa por `SurfaceWorld.set_anchor`.
- Lo que sea ficticio por jugabilidad (salto > c, límites del casco y del traje, rescates) se marca como tal.
- Pruebas del hito: `--travel-smoke` (viajes, descensos) y capturas con `--system-tour` / `--surface-tour`.

## Reglas de coordenadas (ADR-003)
- Posiciones absolutas (planetarias/astronómicas) en `DVec3` (64 bits). `Vector3` (32 bits) sólo para
  posiciones locales cerca del origen del motor (≲ 2 km).
- `FloatingOrigin` (autoload) convierte BF↔local. Los nodos que deben seguir al mundo se añaden al grupo
  `FloatingOriginService.GROUP`; los sistemas con posiciones DVec3 escuchan `origin_shifted` y recalculan
  desde cero (nunca acumulan desplazamientos).
- Las mallas guardan vértices relativos a su propio centro (DVec3).
- `FastNoiseLite` es de 32 bits: longitudes de onda de ruido ≥ 30 m para radios de hasta ~6.400 km.

## Reglas de naves y capas (ADR-011..015)
- Capas de render y física SIEMPRE desde `Layers` (`src/core/layers.gd`), nunca números sueltos. `collision_layer` y
  `collision_mask` son MÁSCARAS: `Layers.bit(Layers.PHYS_SHIP)`, nunca `Layers.PHYS_SHIP` a secas (fallo de la ronda 11).
- Rayos y cámaras que deben chocar con el suelo usan `Layers.solid_mask()` (terreno + naves).
- A bordo rige la gravedad APARENTE `Ship.apparent_gravity()` (planeta − aceleración de la nave, o la
  artificial con G; ADR-018); la nave traslada a sus pasajeros (`carry`). No emparentar astronautas a naves
  ni reactivar `platform_floor_layers`.
- Coordenadas de la nave SIEMPRE desde `ShipLayout` (plano de ADR-021); el casco exterior lo genera `ShipHull`.
- Tras mover un cuerpo de colisión en `_physics_process`, enviar su transform con `PhysicsServer3D.body_set_state`
  si otros cuerpos se mueven en el mismo paso.
- El estado replicable de la nave vive en `ShipState`; las entradas en `ShipControls`; nada de referencias
  globales a un único jugador (listas del mundo).
- Velocidades extremas: integrar en `DVec3` y comprobar el segmento recorrido contra el terreno.

## Reglas de jugadores, interfaz y audio (ADR-032..038)
- Los astronautas leen sus controles SIEMPRE con su `PlayerInput` (`pin`), nunca con `Input` directamente.
- En el cooperativo los nodos de cada jugador viven en su `CoopViewport`; la entrada la reparte `SurfaceWorld`.
- Colores y tipografía sólo desde `UiTheme` (identidad ADR-036). Los textos visibles nombran las teclas con
  `PlayerInput.glyph()` (teclado o mando según el jugador).
- El audio se genera con `tools/gen_audio.py`; los efectos se reproducen con `GameAudio.play/play_at`. La banda sonora
  se declara en `data/music.json` (contextos y `gain_db`); los ajustes de la megafonía, en `GameSettings.ship_*`.

## Reglas de la base, la historia y la red (ADR-042..044)
- Lo que se mueve en pasos de física (naves, astronautas) usa interpolación de física; lo que se coloca cada
  fotograma va en `PHYSICS_INTERPOLATION_MODE_OFF`. Tras teletransportar algo: `reset_physics_interpolation()`;
  los recentrados del origen ya llaman a `FloatingOrigin.teleported()`. Las cámaras siguen la posición interpolada.
- Coordenadas de la base SIEMPRE desde `BaseLayout` (marco local: X este, Y arriba, Z sur). Cada sala tiene sus
  tabiques; nunca compartir geometría entre lotes que se ocultan por separado (ni en la base ni en la nave).
- Los audios de la historia se disparan por EVENTOS con `DialogueDirector.say(id)` (nunca por tiempo ni dos a la vez);
  las líneas están en `data/dialogue/prologue.json`. Los objetivos, en `PrologueDirector.OBJECTIVES`.
- En línea: el anfitrión manda en la historia y guarda; cada jugador en su astronauta; quien pilota en la nave.
  Las RPC viven en `/root/Net`; la lógica de juego en `NetWorld`. Las posiciones viajan en BF de 64 bits con su cuerpo.

## Reglas de la voz y la sala (ADR-046/047)
- La voz pasa SIEMPRE por el anfitrión (`Voice.host_route`), que valida la radio y recorta la proximidad lejana; cada
  receptor reproduce cada trama por UNA sola vía. Volúmenes y teclas, de `GameSettings.voice_*`; colores de vía, de
  `VoiceHud.path_color`. Sin sonido de respiración en el casco (preferencia del usuario).
- La voz de proximidad va SIN efectos (petición del usuario); sólo la radio lleva procesado (ADR-048).
- Las bases del NEXUS las genera `NexusOutpost` con una semilla por cuerpo (igual en todos los equipos); la ubicación la
  decide `NexusQuest.site_dir` (de día, terreno llano) y en línea la del anfitrión. Sus audios: líneas `nexus_<cuerpo>`.
- Al cambiar cualquier RPC, subir `NetSession.PROTOCOL` (y `GAME_VERSION` al repartir un paquete nuevo).
- Crear o unirse a una sala NUNCA arranca el mundo: sólo `Net.start_match` (anfitrión, todos listos). Los mundos en
  línea se cargan con `net_hold` y se sueltan con `Net.go`.

## Reglas de código
- GDScript con tipos estáticos (`:=`, tipos en firmas). `class_name` en PascalCase, archivos en snake_case.
- Comentarios y textos de interfaz en español. Comentarios de documentación con `##`.
- Un módulo por responsabilidad (ver `docs/ARCHITECTURE.md`). Las escenas se construyen por código salvo `scenes/main.tscn`.
- Hilos: sólo `WorkerThreadPool` con trabajos autocontenidos (`TerrainPatchJob`); nada de tocar el árbol
  de escena desde hilos; cada tarea se espera con `wait_for_task_completion`. Tareas de terreno en alta prioridad.
  Única excepción: el `Thread` del UPnP de `NetSession` (no toca el árbol; devuelve el resultado con `call_deferred`).
- GDScript no admite `%g` en cadenas de formato; usar `%s` con `str()` o `String.num_scientific()`.

## Reglas de proceso
- Antes de dar un hito por terminado: `--run-tests`, `--smoke-test` y `--ship-smoke` en verde y benchmark/tour en el hardware objetivo.
- En pruebas guiadas por fases: soltar entradas al cambiar de fase y pulsar DESPUÉS (`_next()` y luego `action_press`).
- No afirmar que algo funciona sin haberlo ejecutado. Registrar mediciones en `docs/PERFORMANCE.md`.
- Toda decisión estructural nueva → entrada en `docs/ARCHITECTURE_DECISIONS.md`. No reescribir un sistema
  funcional sin ADR que lo justifique.
- Mantener `docs/KNOWN_LIMITATIONS.md` y `docs/MILESTONES.md` al día.
- Prioridad: jugabilidad y estabilidad > gráficos > complejidad.
