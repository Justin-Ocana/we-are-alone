# Arquitectura

Decisiones y su justificación: [ARCHITECTURE_DECISIONS.md](ARCHITECTURE_DECISIONS.md).

## Módulos

| Módulo | Ubicación | Estado | Responsabilidad |
|---|---|---|---|
| Núcleo / coordenadas | `src/core/dvec3.gd`, `floating_origin.gd`, `units.gd` | ✅ Hito 1 | Doble precisión, origen flotante, constantes SI |
| Entrada y ajustes | `src/core/game_input.gd`, `game_settings.gd` | ✅ básico | Acciones por código, ajustes versionados |
| Datos físicos de cuerpos | `src/astro/body_def.gd`, `body_catalog.gd`, `data/bodies/*.json` | ✅ básico | Carga/validación, calidad y fuente de cada dato |
| Catálogo de sistemas / órbitas | `src/astro/` | ⏳ Hito 3 | Efemérides (JPL Horizons → archivos locales), modelos orbitales |
| Generación procedural (terreno) | `src/terrain/terrain_generator.gd`, `terrain_profiles.gd` | ✅ Hito 1 | Altura y color deterministas por (dirección, semilla, perfil) |
| Generación procedural (sistemas) | — | ⏳ Hito 5 | Sistemas estelares reproducibles por semilla |
| Terreno planetario | `src/terrain/cube_sphere.gd`, `planet_terrain.gd`, `terrain_quad_node.gd`, `terrain_patch_*.gd` | ✅ Hito 1 | Cubo esferizado, quadtree LOD, hilos, colisión, rocas |
| Gravedad y astronauta | `src/player/astronaut.gd` | ✅ Hito 1 | g = GM/r², orientación radial, 1ª/3ª persona, vuelo de depuración |
| Cuerpo e inmersión | `src/player/astronaut_rig.gd`, `gait.gd`, `body_camera.gd`, `helmet_overlay.gd`, `suit_audio.gd` | ✅ Hito 1.5 | Cuerpo articulado con IK, marcha por Froude, cámara corporal estabilizada, casco, sonido |
| Nave: estado y vuelo | `src/ship/ship_state.gd`, `ship_controls.gd`, `ship_params.gd`, `ship_flight_model.gd`, `ship_autopilot.gd`, `data/ships/*.json` | ✅ Hito 2 | Estado replicable, 6 GDL, regímenes, lumínico, piloto automático |
| Nave: estructura | `src/ship/ship_layout.gd`, `ship_builder.gd`, `mesh_batcher.gd`, `ship_door.gd`, `ship_airlock.gd`, `ship_panel.gdshader` | ✅ Hito 2 | Plano, geometría agrupada, colisiones, puertas, esclusa |
| Nave: integración | `src/ship/ship.gd`, `ship_pilot_input.gd`, `ship_camera.gd`, `src/ui/pilot_hud.gd`, `src/world/view_manager.gd` | ✅ Hito 2 | Traslado de pasajeros, aterrizaje, cámaras, interfaz |
| Transiciones superficie/espacio | `ship.gd` (despegue/aterrizaje/órbita) | 🟡 básico | Viaje entre cuerpos: Hito 3-4 |
| Mapa de navegación | — | ⏳ Hito 3 | |
| Interfaz | `src/ui/` | ✅ mínimo | Menú principal, pausa, HUD de diagnóstico |
| Persistencia | `src/core/game_settings.gd` | 🟡 sólo ajustes | Partidas/descubrimientos: Hito 5-6 |
| Rendimiento y diagnóstico | HUD, `PlanetTerrain.profile_text()`, `tests/bench/` | ✅ | FPS, memoria, tiempos por subsistema, capturas |
| Entorno (Sol, cielo) | `src/world/sky_environment.gd`, `sky.gdshader` | ✅ básico | Sol rotando con el día solar, estrellas, atmósfera visual, bruma |
| Escena de superficie | `src/world/surface_world.gd`, `src/game/main.gd` | ✅ | Integración y punto de entrada |

## Marcos de referencia

```
 Galáctico (pc/al, DVec3)            ← Hito 4-5
   └─ Sistema estelar (m, DVec3, baricéntrico, eclíptica J2000)   ← Hito 3
        └─ Cuerpo, fijo al cuerpo "BF" (m, DVec3; +Y = polo norte; rota con el planeta)   ← Hito 1
             └─ Local del motor (m, Vector3 32 bits) = BF − FloatingOrigin.offset
```

- En superficie todo se simula en BF. El Sol se mueve alrededor del eje polar con el día solar.
- `FloatingOrigin.update_focus()` recentra cuando el jugador se aleja > 1.024 m del origen local.
- Transformación BF → local: `local = p_bf − offset` (resta en doble, conversión final a 32 bits).
  Error medido: < 0,1 mm en la ida y vuelta (test `test_floating_origin_round_trip`).

## Terreno (flujo por fotograma)

```
SurfaceWorld._process ─ set_focus(posición BF de la cámara)
PlanetTerrain._process
  1. _collect_finished   tareas terminadas → cola de mallas
  2. _create_meshes      ≤ 4 ArrayMesh por fotograma (hilo principal)
  3. si el foco se movió > 0,5 m o hubo mallas nuevas:
       _update_node (recorrido sin efectos) → lista de dibujado + nodos que faltan
       _apply_draw_list (diferencia: visibilidad, colisión de los niveles finos ≤ 120 m)
  4. _dispatch           ≤ max_jobs TerrainPatchJob en WorkerThreadPool (los más cercanos primero)
```

- Criterio de división: `distancia(foco, centro) < split_factor × arista` (1,5 en calidad media),
  fusión con histéresis ×1,25. Profundidad máxima: arista fina ≈ 18–32 m (≈1–2 m entre vértices).
- Un padre sigue dibujado hasta que sus 4 hijos tienen malla (sin agujeros durante la carga).
- Faldones para grietas entre niveles; normales con corona extra → iluminación continua.
- Rocas: deterministas por parche del nivel `max_level − 2`, generadas en el mismo trabajo, radio 160 m;
  colisión esférica para rocas ≥ 0,7 m.
- Salvaguarda del astronauta: nunca > 1 m por debajo de la altura analítica.

## Riesgos técnicos (Hito 0) y estado

| Riesgo | Mitigación | Estado |
|---|---|---|
| Precisión de 32 bits a escala planetaria | DVec3 + origen flotante + vértices relativos | Mitigado y probado (vuelo de 10 km, 9 recentrados) |
| Profundidad de 24 bits sin Z inversa (Compatibility) | near/far dinámicos | Sin artefactos visibles en las capturas; vigilar con la nave |
| Rendimiento en GPU integrada | LOD por distancia, ~400–480 parches, materiales simples | Medido: ≈5 ms/fotograma (HD 630) |
| Generación en GDScript lenta | Ruido en C++ (FastNoiseLite), hilos | ≈5–7 ms por parche en hilo; carga inicial 2,6–6,6 s |
| Precisión de FastNoiseLite (32 bits) | Longitud de onda mínima 30 m | Documentado |
| Driver OpenGL de Intel | Godot usa ANGLE (D3D11) automáticamente | Funciona |
| Escala Sistema Solar (1e12 m) | Marco de sistema en DVec3, cuerpos lejanos como impostores | Pendiente (Hito 3) |

## Nave (Hito 2)

```
Paso de física (orden por prioridad):
  Ship (−20): órdenes (piloto o piloto automático) → asistencia de aterrizaje → ShipFlightModel
              → posición con prueba de segmento contra el terreno → transform del nodo y del cuerpo de
              colisión (enviado ya al servidor de física) → Δ aplicada a pasajeros → puertas/esclusa/tren
  Astronauta (0): ¿a bordo? → gravedad de la nave o del planeta → caminar (move_and_slide)
Fotograma:
  Astronauta: animación del cuerpo, cámara corporal, casco
  ViewManager (1000): cámara activa, máscaras, superposición de plano cercano, near/far
```

Capas (`src/core/layers.gd`): render WORLD, HEAD, BODY, SHIP_EXT, SHIP_INT, BODY_INT, HEAD_INT; física
TERRAIN (1), ASTRONAUT (2), SHIP (4). El Sol ilumina WORLD/HEAD/BODY/SHIP_EXT; las luces interiores sólo
SHIP_INT/BODY_INT/HEAD_INT. Sincronización futura en red: ADR-015.
