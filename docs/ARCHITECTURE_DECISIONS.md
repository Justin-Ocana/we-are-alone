# Registro de decisiones arquitectónicas (ADR)

Formato: cada decisión tiene contexto, decisión, consecuencias y estado.
No se reemplaza un sistema funcional sin añadir aquí una nueva entrada que lo justifique.

---

## ADR-001 — Motor: Godot 4.7.2 stable (oficial, precisión simple), GDScript

**Contexto.** El entorno tiene `Godot_v4.7.2-stable_win64.exe` (portable, oficial, sin .NET).
La documentación oficial 4.7 (Large world coordinates) indica que las compilaciones
oficiales usan `real_t` de 32 bits; la doble precisión exige recompilar el motor y las
plantillas de exportación con `precision=double`. El `float` de GDScript es siempre de 64 bits;
`Vector3`, `Transform3D`, etc. son de 32 bits.

**Decisión.** Usar el binario oficial 4.7.2 y GDScript. No compilar el motor. La precisión
se resuelve en la capa de juego (ADR-003). C# no aporta ventaja: el binario no es .NET y el
cuello de botella (ruido procedural) ya está en C++ (`FastNoiseLite`).

**Consecuencias.** Ninguna dependencia externa. Todo cálculo astronómico/planetario se hace en
`float` (64 bits) con `DVec3`; los `Vector3` sólo aparecen cerca del origen del motor.

**Estado.** Aceptada (Hito 0).

---

## ADR-002 — Renderizador: Compatibility (OpenGL 3.3) por defecto

**Contexto.** Hardware objetivo: Intel HD Graphics 630 (integrada, 1 GB compartido),
i5-7400, 16 GB RAM, Windows 10. El proyecto venía creado con Forward+/D3D12.
Según la documentación 4.7, Compatibility usa profundidad de 24 bits **sin Z inversa**
(Forward+ usa 32 bits con Z inversa), lo que es un riesgo a escala planetaria.

**Decisión.** Compatibility como primera opción (lo exige el proyecto y es el más ligero).
La precisión de profundidad se mitiga con planos near/far dinámicos (near = 0,05 m a pie,
crece con la altitud; far ajustado a la distancia al horizonte geométrico + horizonte de las
montañas). Se mide con el benchmark (`tools/bench.ps1`) y se compara con `mobile`.
Si los artefactos de profundidad fueran inaceptables, la alternativa documentada es el
renderizador Mobile (Z inversa) — ver resultados en `docs/PERFORMANCE.md`.

**Medición (2026-10-10).** En el HD 630 Godot cambia automáticamente a ANGLE (D3D11) porque el driver
OpenGL de Intel figura como de baja calidad. Resultado: ≈5 ms/fotograma sin vsync en superficie
(190–205 FPS), 60 FPS estables con vsync, sin artefactos de profundidad visibles en las capturas de
superficie, 3 km, 40 km y 420 km. No se ha necesitado probar Mobile.

**Estado.** Aceptada (medida). Revisar cuando existan objetos cercanos sobre terreno lejano (nave, Hito 2).

---

## ADR-003 — Coordenadas: jerarquía de marcos en doble precisión + origen flotante

**Contexto.** Un `Vector3` de 32 bits tiene un ulp de ~0,5 m a 6.000 km y de ~16 km a 1 UA.
La documentación recomienda mantener el contenido a menos de ~2.048 unidades del origen en
primera persona.

**Decisión.** Tres niveles, todos en metros SI:

| Marco | Tipo | Origen | Uso |
|---|---|---|---|
| Galáctico / sistema | `DVec3` (64 bits) | baricentro del sistema | posiciones orbitales (Hito 3+) |
| Cuerpo (body-fixed, BF) | `DVec3` (64 bits) | centro del planeta, ejes fijos al planeta (+Y = polo norte) | terreno, jugador en superficie, nave cerca |
| Local del motor | `Vector3` (32 bits) | `FloatingOrigin.offset` (en BF) | renderizado y física de Godot |

- `FloatingOrigin` (autoload) guarda `offset: DVec3`. `to_local(p_bf) = p_bf − offset`.
- Cuando el foco (jugador o nave) supera `threshold_m` (1.024 m) se recentra: `offset += foco`
  y todos los nodos del grupo `floating_origin` se desplazan `−foco`. El foco queda exactamente
  en (0,0,0) (resta exacta por el lema de Sterbenz).
- El terreno **no** se desplaza incrementalmente: cada parche guarda su centro en `DVec3`
  y su posición local se recalcula desde cero en cada recentrado (sin error acumulado).
- Los vértices de cada parche se guardan relativos a su propio centro (|v| ≲ tamaño del parche),
  por lo que la malla de 32 bits es exacta al centímetro en cualquier punto del planeta.
- En superficie se trabaja en el marco BF (rotante). Se ignoran las fuerzas ficticias de la
  rotación (Coriolis/centrífuga ≤ 0,034 m/s² en la Tierra) — simplificación documentada.
  La rotación planetaria se ve como movimiento del Sol.

**Consecuencias.** Sin temblores a cualquier distancia del centro del planeta. La conversión
es explícita y verificable (tests `test_dvec3`, `test_floating_origin`, smoke test de vuelo).

**Estado.** Aceptada.

---

## ADR-004 — Terreno: cubo esferizado + quadtree por cara + parches con faldones

**Contexto.** Se necesita caminar por planetas de radio real (1.737 km – 6.371 km o más)
sin subdividir uniformemente una esfera, en una GPU integrada.

**Alternativas.**
- *Esfera icosaédrica*: subdivisión uniforme, pero el direccionamiento de vecinos/LOD es más complejo.
- *Clipmaps geométricos*: excelentes en planos; sobre una esfera exigen reproyección y
  shaders de desplazamiento por vértice (lectura de texturas en el vértice) — más arriesgado en GLES3.
- *Cubed-sphere + quadtree (Chunked LOD)*: 6 caras, cada una un quadtree; cada nodo es un
  parche de N×N cuadros generado en CPU. Direccionamiento trivial (cara, nivel, i, j),
  generación por hilos, colisión por parche. Usado ampliamente (Outerra, KSP-like, etc.).

**Decisión.** Cubed-sphere con la proyección "esferizada" (x√(1−y²/2−z²/2+y²z²/3)), que reparte
mejor el área que la normalización directa. Quadtree por cara con criterio de división
`distancia_al_centro_del_parche < split_factor × arista` (1,2 / 1,5 / 2,2 según calidad) e histéresis
×1,25 para fusionar. (La primera versión usaba distancia − radio envolvente < 2·arista: 1.434 parches;
se cambió tras medir — ver PERFORMANCE.md.)
Profundidad máxima calculada para que la arista del parche más fino sea ≈ 32 m
(≈2 m entre vértices con 16 segmentos). Las grietas entre niveles se tapan con **faldones**
(skirts) — robustos y baratos. Normales calculadas con una corona de muestras extra, por lo
que la iluminación es continua entre parches del mismo nivel.

**Generación.** Determinista: altura = f(dirección unitaria, semilla, perfil). Los parches se
generan en `WorkerThreadPool` (un generador de ruido por tarea, sin estado compartido) y la
malla (`ArrayMesh`) y la colisión (`ConcavePolygonShape3D`) se crean en el hilo principal con
presupuesto por fotograma.

**Visibilidad en dos fases.** El recorrido del árbol no tiene efectos: produce la lista de dibujado; después se
aplica la diferencia (visibilidad y colisión). Evita la oscilación crear/destruir colisión que costaba 45 ms/fotograma.

**Colisión.** Sólo los parches visibles de los 5 niveles más finos a menos de 120 m tienen `StaticBody3D`.
Salvaguarda adicional: el astronauta consulta la altura analítica y nunca puede quedar más de
1 m bajo ella (evita caer a través del suelo durante cambios de LOD o viajes rápidos).

**Precisión del ruido.** `FastNoiseLite` recibe `real_t` (32 bits). Las octavas finas se evalúan
en `dirección × R` metros; con R = 6.000 km la coordenada máxima es ~6e6 y el ulp ≈ 0,5 m.
Por eso la longitud de onda mínima del ruido se limita a ≥ 30 m, con lo que el error de altura
resultante es de milímetros. Documentado en KNOWN_LIMITATIONS.

**Estado.** Aceptada.

---

## ADR-005 — Datos astronómicos: JSON versionado con calidad de cada valor

**Decisión.** Cada cuerpo es un JSON en `data/bodies/` (`schema_version`). Cada magnitud física
es `{ "value", "unit", "quality", "source" }`, con `quality ∈ {measured, estimated, approximate,
fictional}`. El terreno de cuerpos reales es procedural y se etiqueta explícitamente
(`terrain_note`): **no** representa topografía real. Las efemérides se importarán desde JPL
Horizons API v1.3 (Hito 3) a archivos locales con caché; el juego no depende de la red.

**Estado.** Aceptada (estructura). Importador de Horizons: pendiente (Hito 3).

---

## ADR-006 — Gravedad y astronauta

**Decisión.** Gravedad newtoniana g = GM/r² hacia el centro del cuerpo dominante, calculada en
doble precisión desde la posición BF. `CharacterBody3D` con `up_direction` dinámico = dirección
radial; la base del cuerpo se reorienta cada paso con el arco mínimo (quaternion). Velocidad de
despegue del salto fija (3,0 m/s, músculo humano), de modo que la altura del salto emerge de la
gravedad (≈0,46 m con 9,8 m/s², ≈2,8 m en la Luna). Cápsula de 1,85 m, ojos a 1,70 m.
Control aéreo mínimo (en el vacío no hay aire: concesión de jugabilidad documentada).

**Estado.** Aceptada.

---

## ADR-007 — Pruebas sin dependencias externas

**Decisión.** Ejecutor de pruebas propio (`tests/test_runner.gd`) lanzado con
`godot --headless -- --run-tests`. Pruebas unitarias de sistemas críticos + smoke test de
integración (carga real de terreno, caminar, volar, recentrar) en modo headless. Benchmark con
render real y capturas de pantalla para medir en el hardware objetivo. No se descargan plugins
de terceros (GUT) para no introducir dependencias no verificadas.

**Estado.** Aceptada.

---

## ADR-008 — Rocas dispersas en un nivel fijo del quadtree

**Contexto.** Con vértices cada 1–2 m y ruido ≥ 30 m de longitud de onda, el suelo cercano carece de
referencias de escala y de sensación de movimiento.

**Decisión.** Las rocas pertenecen a los parches del nivel `max_level − 2` (no al LOD dibujado), se generan
de forma determinista en el mismo trabajo del hilo (semilla = hash(semilla, cara, nivel, i, j)), se apoyan en la
altura analítica (hundidas un 30 %) y se instancian con `MultiMesh` dentro de 160 m. Rocas ≥ 0,7 m con
colisión esférica. Densidad por perfil (`rock_density`, rocas/m²).

**Consecuencias.** Sin "popping" al cambiar el LOD del terreno; coste medido despreciable (≈+50 k
primitivas). Al ser deterministas, persistentes sin guardar nada.

**Estado.** Aceptada.

---

## ADR-009 — Cuerpo completo, cámara corporal e interior del casco ("true first person")

**Contexto.** El jugador pidió sentirse dentro del traje: verse pies, manos y cuerpo, con una cámara que no
sea la cámara flotante habitual. Referencias investigadas:
- *Star Citizen*: un único cuerpo para 1ª y 3ª persona. Poner la cámara en el hueso de la cabeza resultó como
  manejar un muñeco cabezón; lo resolvieron estabilizando la cabeza contrarrestando el movimiento del cuerpo,
  como hacen las aves (Kotaku, "Star Citizen's first person view is based on birds").
- *Mirror's Edge*: el cuerpo forma parte de la experiencia; al mirar abajo te ves; los aterrizajes se sienten.
- *Arma 3*: mirada libre manteniendo una tecla, que vuelve al centro al soltarla.
- *Escape from Tarkov* y debates de diseño: la inercia y el balanceo gustan si son sutiles, proporcionales a la
  velocidad y regulables; en exceso marean.
- *Outer Wilds* (blog de Mobius Digital): interfaz del casco proyectada, estilo "NASA retro" minimalista.
- Biomecánica: Carr & McGee 2009 (PLoS ONE, "The Apollo Number"): transición caminar→correr en Fr ≈ 0,5;
  con traje en 1/6 g, Fr* ≈ 0,36. Rader, Newman & Carr 2007 (SAE): "loping" de los astronautas del Apolo.
  Hewes et al. 1966 (NASA): velocidades máximas en gravedad lunar ≈ 60 %. Alexander 1976: λ/L ≈ 2,3·Fr^0,3.

**Decisión.**
1. `AstronautRig`: cuerpo articulado de primitivas a escala (1,85 m, ojos a 1,70 m), sin recursos externos.
   Piernas con IK analítica de dos huesos hacia objetivos de pie apoyados por rayos físicos; durante el apoyo
   el pie retrocede `duty·zancada`, exactamente lo que avanza el cuerpo (sin deslizamiento). Al mirar abajo el
   torso se inclina y la cabeza se adelanta para que se vean piernas, punteras y guantes. Postura de brazos de
   traje presurizado (codos doblados): los guantes entran en la vista al bajar la mirada ~40°.
2. `Gait`: tipo de marcha, zancada y bote balístico según Froude y la gravedad real del cuerpo. En la Luna el
   astronauta avanza a saltitos; la velocidad máxima se escala (60 % en 1/6 g).
3. `BodyCamera`: cámara en los ojos del rig; se contrarresta parte del bote de la pelvis (estabilización de
   cabeza), inercia por muelle amortiguado, golpe al aterrizar, alabeo al desplazarse de lado o girar, +6° de FOV
   al correr. La vista no hereda la rotación del cuerpo (estabilización ocular). Todo escalado por
   `GameSettings.camera_motion` (deslizador en pausa; 0 = cámara estática).
4. Mirada libre con Alt (±110°), vuelve al centro al soltar.
5. `HelmetOverlay`: marco del visor como capa 2D con shader (independiente de los planos near/far), con
   inercia al girar; brújula y lecturas proyectadas. El HUD de depuración pasa a F3, oculto por defecto.
6. `SuitAudio`: pisadas transmitidas por el traje (en vacío sólo golpe grave; con atmósfera, crujido) y
   zumbido del soporte vital, sintetizados por código. **La respiración se retiró a petición del usuario.**

**Consecuencias.** Coste medido: 150–310 FPS sin vsync en el HD 630 (antes 190–320). El mismo cuerpo servirá
para el asiento del piloto en el Hito 2.

**Estado.** Aceptada.

---

## ADR-010 — Efectos de vista: enfoque, asomarse, Sol en el visor, cristal del visor

**Contexto.** El jugador pidió más efectos centrados en la vista (no en el caminar). Referencias:
- *Arma 3* / mods "Realistic Eye Zoom" y "Human Focus" (Arma Reforger): mantener clic derecho estrecha el FOV para
  representar la agudeza del ojo que un monitor no reproduce; el enfoque es más débil al moverse o cansado.
- Asomarse (Tarkov, Opsive "First Person Lean"): desplazamiento + alabeo de cámara con sonda de colisión.
- Debate sobre destellos (Space Engineers, Celestia): en 1ª persona sólo tienen sentido si hay un cristal; el visor
  del casco lo justifica. Visores de pilotos (DCS): el oscurecimiento debe "funcionar", no ser un velo cosmético.
- Mod "Sun-Blinded": mirar el Sol acumula exposición y deja imagen residual que se desvanece.

**Decisión.**
1. Enfoque (clic derecho): FOV → 32° con suavizado; fuerza 45–100 % según velocidad y esfuerzo; la sensibilidad del
   ratón se escala con el FOV; el HUD del visor se atenúa.
2. Asomarse (Q/E): el torso se inclina desde la cintura (el cuerpo lo muestra en 3ª persona), la cámara sigue a los
   ojos y se añade alabeo; dos rayos laterales a la altura de la cabeza limitan la inclinación.
3. Sol en el visor: brillo aditivo (halo, destello horizontal, reflejos fantasma); oscurecimiento automático
   del visor con ~0,5 s de reacción; exposición acumulada al mirarlo y imagen residual fija en la retina. El brillo
   se apaga si el Sol está bajo el horizonte o tapado por relieve con colisión (rayo de 3 km).
4. Cristal del visor: distorsión y dispersión cromática hacia el borde (lectura de `hint_screen_texture`),
   desactivable en Pausa.
5. FOV dinámico en vuelo de depuración: se abre con log10(velocidad), hasta +18°.
6. Controles: interactuar pasa a F, vuelo de depuración a N; Q/E asomarse; clic derecho enfocar.

**Consecuencias.** Coste medido ≈1,2 ms/fotograma en el HD 630 (155–230 FPS sin vsync).

**Estado.** Aceptada.

---

## ADR-011 — Astronautas dentro de una nave en movimiento: traslado explícito y gravedad de la nave

**Contexto.** El astronauta (CharacterBody3D) debe caminar por la nave mientras esta acelera, gira y viaja
a velocidades enormes, sin quedarse atrás ni atravesar el suelo, y con varios astronautas en el futuro.

**Alternativas evaluadas.**
- *Emparentar el astronauta a la nave*: cambia la jerarquía de un cuerpo físico, mezcla la gravedad y el
  origen flotante, y complica el multijugador (¿quién es el padre de cada jugador?).
- *Plataforma móvil de CharacterBody3D*: depende de la velocidad que el motor atribuye al cuerpo del suelo;
  falla con rotaciones y con velocidades de km/s, y no traslada a quien no está tocando el suelo.
- *Traslado explícito* (elegida): cada paso de física, la nave (que se ejecuta antes, prioridad −20)
  calcula su variación de transform Δ = T_nueva · T_anterior⁻¹ y la aplica a cada pasajero registrado
  (posición, orientación y velocidad relativa). Independiente de la velocidad y del número de astronautas.

**Decisión.**
- Pasajero = astronauta cuyo punto a 0,9 m de los pies está dentro del volumen presurizado
  (`ShipLayout.is_aboard`). Al entrar/salir se resta/suma la velocidad del punto de la nave (v + ω×r): se
  conserva la velocidad absoluta.
- **Separación explícita de gravedad**: a bordo rige la gravedad artificial de la nave (9,81 m/s² según su
  "arriba"); fuera, la planetaria. Nunca ambas. Dentro de la nave no se sienten sus aceleraciones
  (compensación inercial ficticia, documentada en `data/ships/explorer.json`).
- `platform_floor_layers = 0` en el astronauta: sin esto Godot sumaba la velocidad de la nave por segunda vez
  (el astronauta avanzaba a 40 m/s respecto a la nave al levantarse del asiento; detectado por el smoke test).
- El casco es un `StaticBody3D` recolocado cada paso y su transform se envía de inmediato al servidor de
  física (`PhysicsServer3D.body_set_state`): Godot encola las notificaciones de transform y las aplica más
  tarde, y las colisiones interiores iban un paso por detrás (0,67 m a 40 m/s; detectado por el smoke test).
- Sentado, el astronauta no hace física: su transform se fija al asiento y el control pasa a `ShipPilotInput`.

**Estado.** Aceptada (verificada: caminar de la cabina a la sala de máquinas a 40 m/s con giros de 60° y 20°).

---

## ADR-012 — Modelo de vuelo, regímenes de velocidad, modo lumínico y piloto automático

**Decisión.**
- `ShipFlightModel` es puro (sólo modifica `ShipState`) y se prueba sin escena. 6 grados de libertad:
  velocidad angular perseguida con aceleración angular limitada (giros graduales, estabilización); con
  asistencia de vuelo, la nave persigue una velocidad deseada (objetivo hacia delante + maniobra lateral/
  vertical) con aceleración limitada por eje y compensación de la gravedad; sin asistencia, empuje newtoniano.
- Velocidad objetivo seleccionable (no "mantener W"): W/S la cambian de forma progresiva, la rueda la
  multiplica ×1,25/÷1,25, X la pone a cero; la nave acelera y frena gradualmente hasta ella (crucero).
- Regímenes en `data/ships/explorer.json`: Maniobra (60 m/s, 10 m/s²), Vuelo normal (2,5 km/s, 35 m/s²),
  Crucero (120 km/s, 3.000 m/s²*), Alta velocidad experimental (0,1 c, 10⁶ m/s²*), Lumínico (c, 3·10⁷ m/s²*).
  *Aceleraciones ficticias (compensación inercial), marcadas en la interfaz.
- Modo lumínico: abstracto y **no relativista** (sin dilatación temporal). Sólo a ≥ 3 radios del cuerpo,
  tras 3 s de carga; nunca supera c; salida automática si se acerca a un cuerpo masivo. La nave se mueve de
  verdad en coordenadas de doble precisión (≈5.000 km por paso a c); la colisión con el planeta se comprueba
  analíticamente sobre todo el segmento recorrido, así que nada atraviesa el terreno a ninguna velocidad.
- Aterrizaje: contacto con el terreno a ≤ 3 m/s, inclinación ≤ 18° y tren fuera → nave posada; si no,
  impacto (aviso, sin sistema de daños). Asistencia de aterrizaje: con el tren fuera y < 25 m, la velocidad
  de descenso pedida se limita a 1,5 m/s + 0,9 m/s por metro.
- Piloto automático (`ShipAutopilot`): genera `ShipControls` que pasan por el MISMO modelo de vuelo (mismos
  límites; nunca teletransporta). HOLD mantiene rumbo y velocidad; APPROACH apunta al cuerpo y frena según
  la altitud. Cualquier entrada manual de rotación/traslación (> 15 %) lo desactiva; el acelerador ajusta
  la velocidad de crucero sin desactivarlo. Sigue volando si el piloto se levanta.

**Estado.** Aceptada (pruebas `test_ship_flight` y smoke de la nave).

---

## ADR-013 — Nave construida a partir de un plano de datos

**Decisión.** `ShipLayout` describe habitaciones, puertas, asiento y volumen presurizado; `ShipBuilder` genera
la geometría y las colisiones desde esos datos, y las pruebas comprueban conectividad, escala y recorrido.
- Geometría agrupada por zona y material (`MeshBatcher`): ≈120 mallas para toda la nave. Los lotes se separan
  por habitación por el límite de 8 luces omnidireccionales por malla de Compatibility.
- Colisión simplificada: losas continuas de suelo/techo (sin juntas), paredes por tramos alrededor de los
  huecos de puerta (las ventanas se cierran en la colisión), cajas para el mobiliario importante (≈100 formas).
- Puertas correderas automáticas por proximidad; nunca se cierran sobre alguien en el umbral.
- Esclusa con interbloqueo (nunca ambas puertas abiertas) y ciclo de 2,5 s con indicadores rojo/ámbar/verde.
  **No simula presión ni aire**: es una transición sencilla y fiable.
- Rampa de 4,6 m (≈26°) que llega a 2 m bajo la cubierta, para enlazar con terreno irregular sin escalón.
- Sólo el interior de la nave se ilumina con luces interiores; el Sol no lo ilumina a través del casco
  (capas de render separadas, ver `Layers`).

**Estado.** Aceptada.

---

## ADR-014 — Cámaras de la nave y doble cámara de plano cercano

**Contexto.** Compatibility usa profundidad de 24 bits sin Z inversa. Desde la cabina hay geometría a 5 cm y
terreno a cientos de km: un único par near/far haría parpadear el terreno (o recortaría la cabina).

**Decisión.** `ViewManager` elige la cámara (1ª/3ª persona del astronauta o exterior de la nave) y, cuando la
cámara está dentro de una nave, dibuja la nave y el cuerpo con una segunda cámara (near 3 cm, far 150 m) en un
SubViewport transparente superpuesto; la cámara principal dibuja sólo el mundo con near/far según la altitud.
El SubViewport sólo se renderiza cuando se usa (si no, duplicaba el coste: 1.500 llamadas de dibujo).
La cámara exterior (`ShipCamera`) se calcula cada fotograma desde el transform real de la nave, con el
suavizado en el espacio local de la nave: sigue al mismo objeto físico a cualquier velocidad.

**Estado.** Aceptada.

---

## ADR-015 — Preparación para multijugador (sin implementarlo)

**Decisión.** Separar estado, entradas y presentación, y evitar referencias globales a "el jugador":
- `ShipState`: transform (posición BF en doble), velocidades, régimen, objetivo, asistencia, piloto automático,
  ocupante del asiento (id), estado de puertas y esclusa. Serializable (`to_dict`).
- `ShipControls`: entradas instantáneas de quien pilota (jugador, piloto automático o red).
- Los astronautas se guardan en listas del mundo (`SurfaceWorld.astronauts`, `ships`); la nave sólo conoce
  identificadores (`pilot_id`) y la lista de pasajeros; puertas y esclusa funcionan con todos los astronautas.

**Plan de sincronización futuro.**
1. Autoridad por nave: el servidor (o el cliente del piloto) simula `ShipFlightModel` con los `ShipControls`
   recibidos del piloto y difunde `ShipState` (≈20 Hz) con interpolación en los demás clientes.
2. Astronautas a bordo: se sincroniza su transform **relativo a la nave** (`ship.to_local`) + id de nave;
   cada cliente lo recompone con el transform interpolado de la nave → no hay temblor aunque la nave vaya a
   km/s. Fuera de naves: transform BF (doble precisión) relativo al cuerpo.
3. Puertas/esclusa: estado autoritativo en el servidor (las puertas ya dependen sólo de posiciones de astronautas).
4. Asiento: petición de sentarse resuelta por la autoridad (`seat_free`/`sit` ya son atómicos por nave).
El escenario "un jugador pilota mientras otro entra por la esclusa y camina" ya es compatible: el traslado de
pasajeros, las puertas y la esclusa tratan a todos los astronautas por igual.

**Estado.** Aceptada (arquitectura); red no implementada.

---

## ADR-016 — Pilotaje Arcade por defecto (sencillo y divertido); Simulación opcional

**Contexto.** El jugador encontró el esquema de simulación confuso: no sabía cómo parar ni cómo ir hacia
delante o atrás, y pidió un pilotaje sencillo y divertido.

**Decisión.** Modo **Arcade** por defecto (Pausa → "Pilotaje"); el modelo realista queda como "Simulación".
- Ratón: apunta la nave con respuesta casi directa (palanca con retorno rápido, 11 s⁻¹).
- W acelera / S frena y, ya parada, da marcha atrás (≤ 30 m/s); la velocidad se mantiene al soltar (crucero).
- X: frenado de emergencia (deceleración ×2,5 y respuesta de 0,2 s) hasta detenerse.
- Shift: turbo (×2,5 velocidad y ×2 aceleración mientras se mantiene). A/D: girar. Q/E: alabeo.
- Sin regímenes: la velocidad máxima crece con la altitud (60 m/s + 1,2 m/s por metro, hasta 300 km/s) y
  el objetivo se recorta solo al descender → la nave frena al acercarse al suelo. Aceleración ≈ 30 % del
  máximo por segundo (ficticia). L: motor lumínico (lejos de cuerpos masivos), T: volver al planeta.
- Autonivelado: cerca de un cuerpo y sin alabeo manual, las alas vuelven a la horizontal (también desde
  invertida). Un primer intento tenía el signo invertido y volteaba la nave; ahora lo cubre `test_auto_level_rights_the_ship`.
- Frenar usa todo el empuje en Arcade (en Simulación los retropropulsores dan la mitad).
- Al levantarse del asiento sin piloto automático, la nave frena sola ("no se va sin ti").

**Estado.** Aceptada.

---

## ADR-017 — Interfaz rediseñada (dibujada a mano) y superposición también en exterior alto

**Interfaz.** `UiTheme` (paneles de cristal, Bahnschrift, cian/ámbar) y `PilotHud` dibujado con `_draw`:
cinta de rumbo, chips de estado, velocidad máxima disponible, velocímetro circular con objetivo, horizonte
artificial, altímetro con velocidad vertical, barra de acelerador, marcador del morro y vector de velocidad,
ayuda de aterrizaje, avisos animados, ayuda de controles con teclas dibujadas (H) y líneas de velocidad. Menús
principal y de pausa con el mismo tema.

**Cámara (corrección).** Fuera de la nave y a más de 150 m sobre el terreno, el near del mundo (≈1 % de la
altitud) recortaba la nave en vista exterior y al propio astronauta al salir al espacio ("la nave desaparece").
Ahora, en ese caso, naves y cuerpos se dibujan en la superposición de plano cercano (far 6 km) con la luz del
exterior, y el mundo en la cámara principal. Verificado con capturas a 5 km de altura y en un paseo espacial.

**Estado.** Aceptada.

---

## ADR-018 — Gravedad aparente a bordo, ingravidez y caída libre

**Contexto.** El jugador pidió que la inclinación de la nave le afecte si no está sentado ("como en la vida
real") y que salir de la nave en pleno vuelo se sienta como caer al espacio sin control.

**Decisión.**
- A bordo rige la **gravedad aparente** `Ship.apparent_gravity(punto)` = gravedad del cuerpo − aceleración del
  punto (lineal + angular α×r + centrípeta ω×(ω×r)). La "compensación inercial" (ficticia) limita a 6 m/s² lo
  que se siente de las maniobras; las aceleraciones se filtran (τ = 0,12 s) para no tener picos de un paso.
  Si la nave se inclina, el suelo se inclina respecto a la vertical y el astronauta se reorienta
  suavemente (`POSTURE_RATE`, "cambios de postura"); con la nave en caída libre, ingravidez.
- **Gravedad artificial** opcional (tecla G sentado): 1 g hacia el suelo de la nave, como antes. Por defecto
  DESACTIVADA (realismo pedido). Sustituye la regla anterior de CLAUDE.md "a bordo rige sólo la gravedad
  artificial".
- **Flotar** (`Astronaut.floating`): con |g| < 0,25 m/s² o cayendo desde más de 12 m fuera de la nave, el
  cuerpo pasa a orientación libre (CharacterBody3D en modo FLOATING): conserva su velocidad angular (al salir
  de una nave en vuelo hereda su giro más un empujón aleatorio de 0,5–1,3 rad/s), el ratón gira todo el cuerpo,
  propulsores del traje WASD/Espacio/Ctrl (1,2 m/s², 90 s de combustible, se recarga a bordo), Q/E alabeo y
  X estabilizar. Al tocar suelo con gravedad se recupera la postura de pie.
- **Mareo**: el giro por encima de 0,6 rad/s lo acumula; al llegar al máximo, desmayo de ~4 s.
- **Salud**: golpes por encima de 5,5 m/s hacen 14 puntos por m/s; los impactos de la nave sacuden y, sin
  ir sentado, dañan; regeneración de 3/s tras 6 s; a 0, desmayo de 6 s y se despierta con 25.
- Al levantarse del puesto de pilotaje en marcha se activa el piloto automático (mantener rumbo y velocidad);
  si la nave se queda vacía en vuelo, se estaciona sola (frenado de emergencia). Tecla B: llamar a la nave
  (piloto automático RECALL: vuela a 140 m de altura y se posa a ~30 m del astronauta).
- Frenado de emergencia (X) a cualquier velocidad: deceleración constante fijada al pulsar (parada en ≈1,5 s,
  saliendo del modo lumínico si hace falta). Ficticio, por jugabilidad.

**Estado.** Aceptada. Pruebas: `ship_smoke` (inclinación de 25°, caída libre, estabilización, daño, desmayo,
llamada, estacionamiento) y `test_ship_flight` (frenado desde 50 m/s, 5 km/s, 250 km/s y 0,9 c).

---

## ADR-019 — Efectos de cámara, interfaz del casco y efectos de pantalla

**Decisión.**
- `BodyCamera`: sacudida por "trauma" (golpes, impactos, daño; amplitud ∝ trauma², decae 1,4/s), vibración de
  los motores sólo con empuje claro (nunca posada ni en estacionario), inercia de la cabeza al frenar/arrancar,
  postura en pendientes, estabilización al enfocar (el clic derecho reduce un 80 % el movimiento involuntario),
  enfoque de instrumentos a menos de 1,2 m (FOV 50° en lugar de 32°) y desorientación al flotar/marearse.
- Sentado, clic derecho (o Alt) + ratón gira la cabeza hasta 160° sin mover la nave; en vista exterior orbita
  la cámara de persecución. En los asientos sin mandos (copiloto, navegante, ingeniero, comunicaciones, sofás)
  se mira libremente.
- `HelmetHud` (dibujado, estilo de ADR-017): brújula con rumbo a la nave, salud y combustible, altitud,
  velocidad con componente vertical, gravedad, Sol, coordenadas, avisos y marcador de la nave con flecha en el
  borde. Se oculta a bordo (visor levantado) junto con el marco del visor.
- `ScreenFx`: destello rojo al recibir daño, viñeta y desaturación con poca salud, visión doble al marearse,
  túnel y fundido a negro al desmayarse. Sólo copia la pantalla cuando hay un efecto activo.
- F2 oculta toda la interfaz; la pausa tiene "Mostrar datos de rendimiento (F3)".

**Estado.** Aceptada.

---

## ADR-020 — Carga rápida del terreno a gran velocidad

**Contexto.** Al llegar muy rápido a una zona, el terreno tardaba en aparecer: cada nivel del quadtree esperaba
a que su padre estuviera generado (≈16 niveles en serie).

**Decisión.**
- **Descenso especulativo**: un nodo que se va a dividir pide ya sus hijos aunque él no esté generado; si todos
  los hijos quedan listos, cubren su área (sin huecos: si no, se dibuja el antepasado listo más cercano).
- **Prioridad por importancia** (distancia / tamaño del parche) en lugar de sólo distancia.
- **Anticipación**: el foco se adelanta según su velocidad (1,5 s, hasta 30 km) para dividir antes de llegar.
- Más trabajos (núcleos − 1) y más mallas por fotograma (límite de 3 ms) cuando hay cola.
- **Caché** de 600 parches ya construidos (malla y colisión) para volver sin regenerar.

**Estado.** Aceptada. Medición en `docs/PERFORMANCE.md`.

---

## ADR-021 — Rediseño de la nave: más grande, espaciosa y con casco liso

**Decisión.** Plano nuevo (57 m de eslora, 20 m de manga de casco, 39 m con alas): cubierta de 3 m, pasillo de
2,4 m, puertas de 1,4 × 2,3 m, puente de 10 × 8 m con cinco puestos, comedor con mesa para seis, dormitorios
con dos literas, sala común con sofá frente a un ventanal, sala de máquinas de 18 × 12 m. El exterior lo
genera `ShipHull`: secciones superelípticas con anchura por interpolación monótona, recortes exactos para
ventanas y puerta (con marcos y colisión), morro bajo el parabrisas, lomo, alas en flecha con góndolas y dos
derivas inclinadas, pintura en dos tonos y nombre en los costados. La colisión exterior es una malla
(`ConcavePolygonShape3D`, ambas caras) con los mismos recortes. `test_hull_encloses_interior` garantiza que
el casco contiene todo el interior.

**Estado.** Aceptada.


---

## ADR-022 — Música de la nave por megafonía; ajustes tras la primera prueba del jugador

**Música.** `ShipMusic` (hijo de cada nave) reproduce MP3/OGG de la carpeta Música del sistema y de
`user://music`, y enlaces DIRECTOS a archivos .mp3/.ogg (descarga con `HTTPRequest`, límite 60 MB). Spotify,
YouTube y SoundCloud **no** se admiten: Spotify cifra su audio (DRM, sólo suena en sus apps) y descargar el audio
de YouTube infringe sus condiciones de uso; el juego lo explica al pegar uno de esos enlaces. Se controla con
`MusicPanel` (tecla M sentado en cualquier asiento; ratón libre, teclado bloqueado para no pilotar mientras se
escribe). Escucha según el oyente local: limpia en el puente; en el resto de la nave "por altavoces" (bus
`MusicaNave` con paso alto, paso bajo, saturación y reverberación, transición suave); fuera, silencio. Pista y
estado en `ShipState` (replicables). La pantalla de comunicaciones del puente muestra la pista.

**Ajustes pedidos por el jugador.**
- Sin pérdida de conocimiento (se retiró el desmayo por salud a 0 y por mareo; quedan los efectos de vista).
- El piloto automático de rumbo conserva la actitud completa, incluida la inclinación lateral (no se autonivela).
- Compensación inercial a 1,2 m/s² (antes 6): en la Luna las maniobras inclinan la gravedad aparente pero ya no
  ponen al astronauta "de cabeza".
- Corregido "levantarse de cabeza": con el cuerpo opuesto a la gravedad, `Quaternion(a, b)` giraba alrededor de un
  eje fijo inservible; ahora se usa media vuelta alrededor del eje lateral del cuerpo.
- Con la nave inclinada, el alcance para sentarse crece hasta +2 m, y también se puede agarrar un asiento flotando.
- Puerta automática en la entrada del puente; las franjas del pasillo ya no cruzan los vanos de las puertas.
- Ventana en el suelo del pasillo (24 × 1,7 m): cristal transitable (la colisión del suelo sigue), recorte en el
  casco con paredes hasta el fondo.
- Iluminación interior: seis luces en el pasillo, una luz baja junto a la ventana del suelo, atenuación más suave,
  algo más de energía y luz ambiente interior más clara.

**Estado.** Aceptada.


---

## ADR-023 — Luces visibles en la superposición; gravedad artificial en toda la nave; indicador del planeta

**Iluminación (error encontrado).** En Godot 4 una luz es un `VisualInstance3D`: las cámaras la descartan si sus
`layers` no están en su `cull_mask`. Las luces interiores tenían la capa por defecto (WORLD) y la cámara de la
superposición —que dibuja el interior y no dibuja WORLD— las descartaba todas: el interior sólo recibía luz
ambiente (plano y "feo"; los ajustes de energía anteriores no tenían efecto). Ahora las luces interiores usan
`layers = interior_light_mask()`, y el Sol y el foco exterior `layers = sun_mask()` (el Sol tampoco iluminaba la
nave vista en la superposición; además ahora no ilumina el interior: `light_cull_mask = sun_mask()`).
Se recalibró con la luz de verdad: ambiente interior 0,22 (relleno), energía ×1,15, atenuación 1,0. Verificado con
`--light-probe` (capturas con/sin luces y sin ambiente): el pasillo pasa de 0,34 a 0,55 de brillo medio con las
luces encendidas (antes: idéntico con y sin luces).

**Gravedad artificial.** Sólo el capitán la activa o desactiva (tecla G en el puesto de pilotaje); el resto de la
tripulación ve su estado a bordo. Activada:
1 g hacia el suelo de la nave sin importar su rotación, sin ingravidez. Desactivada: gravedad aparente real
(ADR-018). El estado se muestra a bordo. Prueba: nave de costado (90°) → el astronauta sigue de pie en su suelo.

**Indicador del planeta.** `PlanetMarker` marca la dirección al centro del cuerpo más cercano con su nombre y la
altitud (círculo si está a la vista, flecha en el borde si no), sólo en el HUD de pilotaje. Hoy cada
mundo tiene un solo cuerpo; la búsqueda del más cercano queda preparada para el Hito 3.

**Estado.** Aceptada.

---

## ADR-024 — Sistema Solar real: catálogo generado, efemérides keplerianas y marco del sistema

**Contexto.** Hito 3: Sol, planetas y lunas a escala real con datos verificables.

**Decisión.**
- Catálogo de **470 cuerpos** generado por `tools/gen_bodies.py` a partir de las fichas NSSDC, la Tabla 1 del JPL
  (planetas) y las tablas del JPL de satélites (460 lunas; copia local en `data/sources/`). Las lunas sin ficha
  propia van en colecciones (`moons_<planeta>.json`); las que no tienen radio publicado se marcan `estimated`.
- `Ephemeris`: Kepler con elementos y tasas (planetas), elementos medios de satélites en su plano de referencia
  con precesión, Tierra = baricentro − μ·r_Luna, orientación IAU (polo + W). Todo en doble precisión.
- `SolarSystem`: posiciones heliocéntricas (eclíptica J2000), ejes de cada cuerpo con la convención del motor
  (X = 90° E, Y = norte, Z = meridiano 0), esferas de influencia de Laplace (mínimo 4 radios) y cuerpo dominante.
- Tiempo de juego = fecha real del sistema al empezar (efemérides de hoy); `,`/`.` lo aceleran.

**Estado.** Aceptada. Pruebas `test_ephemeris` (8).

---

## ADR-025 — Cielo analítico: todos los cuerpos a su tamaño angular real

**Decisión.** El shader del cielo traza rayos por píxel contra hasta 24 cuerpos que `SystemSky` elige cada
fotograma (Sol, planetas, lunas del sistema local y lunas menores visibles), con posiciones relativas a la cámara
calculadas en doble precisión y la intersección estable `t = c/(−b + √(b²−c))` con `c = h(h+2R)`. Incluye Sol con
oscurecimiento al limbo, granulación y corona; fases; bandas, tormentas (Gran Mancha Roja, óvalo BA, mancha oscura
de Neptuno) y hexágono de Saturno; elipsoides achatados; limbo atmosférico (Fresnel); anillos con la sombra del
planeta; puntos con magnitud aparente para lo que ocupa menos de un píxel. La luz del Sol se atenúa como
(1/d²)^0,4 (compresión perceptiva: sin exposición automática los planetas exteriores serían negros); el tamaño
del disco solar sí es el real.

**Estado.** Aceptada.

---

## ADR-026 — Lore: la Tierra destruida

**Decisión.** La Tierra se dibuja como 11 fragmentos (celdas de Voronoi de la esfera) desplazados ~0,3 radios y
girando lentamente alrededor de un núcleo incandescente, todo analítico en el shader (sin mallas ni problemas de
precisión). La cara exterior usa una máscara de continentes (`data/earth_land.json`, contornos trazados a mano,
`approximate`); las caras de rotura muestran corteza, manto y magma. Sin colisión con los fragmentos (limitación).

**Estado.** Aceptada.

---

## ADR-027 — Cuerpo dominante y cambio de marco

**Decisión.** El juego sigue trabajando en el marco fijo (rotante) de UN cuerpo, el dominante en la posición de la
nave (o del astronauta). Al entrar en otra esfera de influencia, `SurfaceWorld.set_anchor` convierte naves y
astronautas en doble precisión (posición), gira orientación y velocidades, recoloca el origen flotante y
reconstruye terreno y cielo. Las velocidades orbitales de los cuerpos NO se suman (compensación ficticia: evita
saltos de decenas de km/s). Cuerpos sin suelo (gigantes, Sol, Tierra destruida): `PlanetTerrain.solid = false`
(sin malla; "fondo" inalcanzable a 0,1 R). Con el ancla a más de 30 radios, la malla se oculta y el cuerpo lo
dibuja el cielo.

**Estado.** Aceptada. Prueba `--travel-smoke`.

---

## ADR-028 — Navegación: mapa, piloto automático de viaje y salto ficticio

**Decisión.** Mapa (Tab) con posiciones reales, lista de cuerpos y lunas, datos y destino. Piloto automático de
viaje: despegue vertical, evasión del cuerpo si la recta al destino lo atraviesa, motor lumínico a más de 3 radios
con un **salto automático de hasta 1000 c (FICTICIO)** para que un viaje dure minutos (a c, Neptuno queda a 4 h),
frenado exponencial y llegada nivelada a 2,5 radios. El apuntado usa el eje delante × objetivo (sin la singularidad
de cabeceo/guiñada a 90°).

**Estado.** Aceptada.

---

## ADR-029 — Atmósferas, descenso y casco

**Decisión.** `AtmosphereModel` (rocosas exponenciales; gigantes con adiabática bajo 1 bar, validada con Galileo),
nubes por presión, vientos zonales, luz en profundidad. En la nave: arrastre con el viento, calentamiento
Sutton-Graves y radiación solar, plasma visible, limitador atmosférico en Arcade (~1500 K), presión de diseño de
100 bar y escudo de 2000 K (FICTICIOS), integridad del casco y rescate de emergencia (ficticio) a 3 radios. En el
cielo: niebla al atravesar nubes, oscuridad y rayos en las profundidades de Júpiter y Saturno. Traje: 5 bar, 600 K.

**Estado.** Aceptada. Pruebas `test_atmosphere` (4) y descensos en `--travel-smoke`.

---

## ADR-030 — Superficies propias de cada cuerpo

**Decisión.** Perfiles de terreno por cuerpo con rasgos nuevos del generador (grietas, calderas volcánicas, dunas,
mares de metano, bicolor, cresta ecuatorial, casquete de un solo polo) y escala del relieve con el radio
(`TerrainProfiles.for_body`). Los trabajos de terreno reciben el perfil ya ajustado.

**Estado.** Aceptada. Captura de todas las superficies con `--surface-tour`.

---

## ADR-031 — Jugabilidad del Sistema Solar: pasajeros a gran velocidad, marcadores, entrada libre, fiesta

**Contexto.** Pruebas del usuario: a velocidad lumínica no se podía caminar a bordo (e incluso se salía uno de la
nave), los marcadores de dirección saltaban de lado, los viajes eran largos y la presión impedía ver los planetas.

**Decisión.**
- Pasajeros: la nave guarda la transformación RELATIVA de cada pasajero antes de moverse y la reaplica después
  (`Astronaut.carry_relative`); si hay alguien a bordo, el origen flotante sigue a la nave en el mismo paso. Así el
  error de precisión ya no crece con la velocidad.
- Marcadores (`UiTheme.draw_world_marker`): la dirección se calcula en el espacio de la cámara y se proyecta un
  punto a 100 m; detrás de la cámara, flecha en el borde con el signo correcto. Nada de proyectar puntos a
  millones de km (el error de 32 bits invertía el lado).
- Entrada libre (FICTICIO): el casco sólo sufre con el calor del Sol (o dentro de 1,02 R☉); la presión y el traje
  ya no dañan. Se puede bajar a cualquier atmósfera, incluso a las profundidades de los gigantes.
- Velocidad: ley de viaje v = d/5 s + 500 m/s con salto de hasta 1000 c → cualquier viaje dura ~1,5-2,5 min.
  Arcade: 80 m/s + 2 m/s por metro de altitud, hasta 1000 km/s, aceleración 0,45·límite.
  Durante el viaje automático no hay arrastre ni limitador atmosférico, y en cuerpos sin suelo el tope sube a
  0,1 c (FICTICIO): desde 450 km bajo las nubes de Júpiter se llega a Venus en ~1 min.
  Medido (`--travel-smoke`): Luna→Tierra 76 s, Tierra→Júpiter 47 s, Júpiter profundo→Venus 56 s.
- Modo fiesta (P a bordo): las luces interiores y los materiales emisivos ciclan en color a ~120 pulsaciones/min.
- Más ventanas laterales en el casco (`ShipLayout.HULL_OPENINGS_*`).
- Mapa (Tab): órbitas reales muestreadas, escala logarítmica en el sistema y lineal en la vista de lunas, zoom,
  desplazamiento, buscador, ficha completa y tiempo estimado de viaje (`MapPanel.eta_seconds`).

**Estado.** Aceptada.


---

## ADR-032 — Cooperativo local a pantalla dividida

**Contexto.** El usuario pidió multijugador local. A escala real sólo hay un origen flotante y un cuerpo dominante.

**Decisión.**
- `PlayerInput` por astronauta: el jugador 1 usa las acciones sin prefijo (teclado, ratón y los mandos que no use
  el 2); el jugador 2, copias `p2_*` ligadas sólo a su mando (`GameInput.configure_players`). Nada lee `Input`
  directamente para controlar a un astronauta. El stick derecho se convierte en "píxeles de ratón".
- `CoopViewport` (SubViewportContainer): cada jugador vive DENTRO de su SubViewport (astronauta, ViewManager,
  PilotHud, ExplorationHud), que comparte el World3D de la ventana; así sus cámaras y CanvasLayers se dibujan sólo
  en su mitad sin código especial. La entrada no se propaga por el contenedor: `SurfaceWorld` la reparte.
- Capas de cabeza por jugador (`HEAD_P2`, `HEAD_INT_P2`): cada cámara oculta sólo su propia cabeza.
- Sólo el anfitrión mueve el origen flotante (`drives_origin`); la nave lo mueve sólo si él va a bordo.
- `PlanetTerrain.set_secondary_focus`: terreno y colisión también alrededor del jugador 2.
- Nadie se queda atrás: si la nave despega (> 600 m, viaje o lumínico) con alguien a bordo, quien esté fuera sube
  (`_bring_aboard` + `Astronaut.board`, en el mismo paso). A pie, separación libre hasta 20 km.
- Etiquetas con el nombre del compañero; preset de calidad reducido en pantalla dividida.

**Estado.** Aceptada. Capturas `--coop-shots`.

---

## ADR-033 — Menús, opciones y pantalla de carga

**Decisión.** Menú principal con fondo procedural (la Tierra rota sobre el horizonte lunar, `menu_background.gdshader`),
columna de opciones y paneles a la derecha: cooperativo, astronauta, opciones por pestañas (`OptionsPanel`,
compartido con la pausa), controles generados desde las asignaciones reales (`ControlsPanel`) y créditos con las
fuentes de datos y lo ficticio. Pausa con la misma estética. Pantalla de carga con destino, progreso estimado por
los trabajos de terreno pendientes, frases del diario y consejos. Todo navegable con mando.

**Estado.** Aceptada. Capturas `--menu-shots`.

---

## ADR-034 — Exploración, puestos de la nave y partida guardada

**Decisión.** `ExplorationLog` (registro, no progresión): visitas, escaneos, muestras, fotos y estadísticas.
`ExplorationController` atiende las acciones de cada jugador: escáner del cuerpo apuntado (datos reales), muestras
mirando al suelo, laboratorio (informe con mineralogía PROCEDURAL marcada como tal), dormir 8 h (adelanta el reloj
del sistema), enfermería, café, recarga del traje, reparación del casco, diario, foto y menú rápido navegable con
mando (`ExplorationHud`). Puestos definidos en `ShipLayout.STATIONS`. `SaveGame`: un JSON con la nave en doble
precisión, cada jugador relativo a la nave si va a bordo, fecha del juego y diario; guardado al salir, desde la
pausa y cada 3 min.

**Estado.** Aceptada. Prueba `--exploration-smoke` (21 comprobaciones).

---

## ADR-035 — Personalización del astronauta y emotes

**Decisión.** Perfil por jugador en los ajustes (nombre, traje, franjas, visor, patrón, mochila) aplicado al
`AstronautRig` (`apply_profile`), con vista previa 3D en el menú. Emotes procedurales sobre la animación
(`apply_emote`: saludar, bailar, robot, celebrar, señalar) con cámara en 3ª persona mientras duran; teclas 1-4 a
pie y menú rápido con mando. El baile pone la pieza "fiesta".

**Estado.** Aceptada.

---

## ADR-036 — Identidad «WE ARE ALONE?»

**Decisión.** Nuevo nombre (antes REAL SPACE EXPLORER) con carpeta de usuario propia `WeAreAlone` (el «?» no es
válido en Windows) y migración automática de ajustes, partida y música. Paleta: grafito, naranja de señal, blanco
lunar y verde azulado para datos; títulos en Bahnschrift estrecha; paneles de esquinas más vivas. La nave pasa a
llamarse Esperanza (matrícula EXP-01) y gana detalle exterior (radiadores, antena, RCS, luces que parpadean,
focos). Todo el color sale de `UiTheme`.

**Estado.** Aceptada.

---

## ADR-037 — Cielo con espesor óptico, nubes 3D y rendimiento

**Decisión.**
- Cielo: espesor óptico τ = 3·densidad visual·masa de aire; el fondo se extingue (exp(−τ)) y el cielo se ilumina
  con la luz dispersada, halo solar por dispersión hacia delante y crepúsculo. Marte de día color caramelo sin
  estrellas, Venus y Titán opacos, Plutón casi espacio.
- `CloudField`: 140 cúmulos en una caja que se repite alrededor de la cámara al atravesar una capa de nubes, con el
  viento zonal y la velocidad; brillo térmico rojo en las profundidades de los gigantes (> 900 K).
- Rendimiento: el mapa deja de dibujar el mundo 3D mientras está abierto, cachea posiciones y órbitas proyectadas y
  redibuja a 30 Hz (Saturno: de 5 a ~37 FPS); `SolarSystem` cachea la posición del padre y su polo por instante;
  sombras con 2 divisiones; preset alto más ligero; HUD del casco a 30 Hz.

**Estado.** Aceptada. Medido con `--perf-probe`: alto 48 → 54 FPS (1366×768, HD 630); medio 60.

---

## ADR-038 — Audio sintetizado

**Decisión.** Todo el audio se genera con `tools/gen_audio.py` (numpy, determinista, CC0 propio): 20 efectos,
4 ambientes en bucle y 4 piezas de banda sonora (menú, exploración, profundidades, fiesta). `GameAudio` (autoload):
buses Efectos/Ambiente/Música, sonido automático en todos los controles de interfaz, banda sonora por contexto que
calla si suena tu música por la megafonía. `AmbientAudio`: zumbido de la nave, viento según presión y velocidad
(nada en el vacío), motores, rumor de las profundidades, truenos tras los rayos.

**Ampliación.** Con permiso del usuario se añadieron 56 sonidos grabados de tres paquetes CC0 de Kenney (Sci-Fi
Sounds, UI Audio, Impact Sounds) en `assets/audio/kenney/`: interfaz, puertas, pisadas según la superficie
(cubierta, suelo con aire, golpe apagado en el vacío), motor, propulsores del traje, minería y golpes.
`GameAudio.VARIANTS` elige una variante al azar; lo demás sigue sintetizado. Créditos en `assets/audio/CREDITOS.md`.

**Estado.** Aceptada.


---

## ADR-039 — Materiales de la nave, imagen y HUD de pilotaje (ronda 8)

**Decisión.**
- `ship_panel.gdshader` v2: paneles irregulares, juntas con relieve real (normales por derivadas de pantalla),
  remaches, suciedad en juntas y parte baja, chorretones y hollín de las toberas en el casco, desgaste en los cantos
  y rugosidad por placa; suelos de chapa estriada. Parámetros por material (`exterior`, `grime`, `wear`, `rivets`,
  `bevel`). Asientos ergonómicos nuevos (base de cinco patas, cojines, arnés, mandos).
- Terreno: relieve de detalle con iluminación (Mikkelsen 2010), tercera escala fina y variación grande.
- Imagen: mapeo de tonos AgX, `post_fx.gdshader` (resplandor propio que funciona también dentro de la nave,
  etalonaje frío/cálido, destello del Sol con oclusión por rayo, aberración leve, viñeta, grano). Opción
  "Efectos de imagen". El resplandor del entorno se desactiva (más caro y no llega a la superposición interior).
- HUD de pilotaje compacto por grupos en dos columnas que se recoge a los 12 s; teclas con el estilo nuevo.
- Sonidos de interfaz y avisos sintetizados de nuevo, cálidos y graves (los clics y el tono de "teléfono" molestaban).

**Estado.** Aceptada. Rendimiento (`--perf-probe`, de noche en la Luna, 1366×768): medio 59 FPS, alto 49.

---

## ADR-040 — Aspecto del menú en el juego: cielo profundo, Tierra incandescente y eclipses

**Contexto.** Al usuario le gustó el contraste del fondo del menú y pidió que el juego se viera así.

**Decisión.**
- Las estrellas y la Vía Láctea se calculan en la eclíptica (`sky_basis`, marco del cuerpo → eclíptica): giran con
  el cielo real (antes estaban fijas al terreno). Vía Láctea con su orientación real (polo y centro galácticos
  J2000), carriles de polvo, bulbo cálido hacia Sagitario y nebulosas tenues; más estrellas en la banda y colores
  por temperatura.
- Tierra rota como en el menú: red de grietas de magma emisivas (también en la cara nocturna), halo de gas y polvo
  y restos en órbita. Su resplandor ilumina de naranja el lado que la mira (`earth_light`, FICTICIO como la propia
  destrucción), según su tamaño aparente.
- Eclipse por el propio cuerpo (`SkyEnvironment.sun_occlusion`): el Sol ya no ilumina desde debajo del horizonte;
  la noche es noche, con penumbra suave.
- Regolito de los cuerpos sin aire más oscuro (albedo real de la Luna ≈ 0,12).

**Estado.** Aceptada. Capturas `--look-shots` (noche, cielo, nave, cabina, día, Sol).

## ADR-041 — Rendimiento (rondas 9 y 10): OpenGL nativo, una sola cámara cerca del suelo, salas ocultas y cielo

**Contexto.** Objetivo del usuario en la HD 630: 40-50 FPS en calidad alta y 60 en media. Tirones cerca de los
cuerpos grandes (sobre todo la Tierra rota) y un fallo grave: desde el pasillo de la nave se veía el exterior.

**Decisión.**
- OpenGL nativo por defecto (ANGLE triplicaba el coste por llamada de dibujo); ANGLE queda como opción
  (`user://graficos.cfg`). Nunca escala de render < 1 (en Compatibility es más lenta).
- Dentro de la nave y bajo 350/450 m (histéresis), una sola cámara dibuja interior y mundo (`ViewManager.single`).
- Ocultación de salas de la nave con la puerta cerrada. Ronda 10: los tabiques COMPARTIDOS (pasillo↔sala y mamparos)
  pasan a lotes «int:estructura_*» que nunca se ocultan; antes eran de la sala vecina y desaparecían con ella.
- HUD de pilotaje y del casco: capa rápida cada fotograma y texto a 10-15 Hz. Cielo a 10 Hz salvo movimiento.
- Tierra rota (ronda 10): se sombrea sólo el fragmento visible más cercano, el trazado de fragmentos se limita a su
  cono (≤ 1,6 R), las semillas de los fragmentos y las direcciones de los 28 restos orbitales se calculan en la CPU
  (los restos agrupados en 4 conos) y las grietas usan un Voronoi de 8 celdas con hash vectorial. Frente a la Tierra:
  21 → 46 FPS en calidad alta.
- Antialiasing de juntas y remaches por metros/píxel y normales protegidas contra NaN (moiré y píxeles negros).

**Estado.** Aceptada. `--perf-tour` (añadido el escenario «tierra») y capturas en `docs/PERFORMANCE.md`.

## ADR-042 — Movimiento suave: interpolación de física, aterrizaje automático y fin de las sacudidas fantasma

**Contexto.** «La cámara se vuelve loca y tiembla mucho, incluso andando». Dos causas medidas: (1) con la física a
60 Hz y el dibujo a 40-50 FPS unos fotogramas avanzaban un paso y otros dos (tirones); (2) una nave apoyada en el suelo
sin llegar a «posarse» (tren recogido o algo inclinada) registraba un choque CADA paso y la sacudida se saturaba para
todos a bordo. Además, el piloto automático bajaba a fondo y se estrellaba.

**Decisión.**
- Interpolación de física de Godot sólo para lo que se mueve en pasos de física (naves y astronautas, modo ON); el
  resto del árbol queda en OFF (se coloca cada fotograma). Las cámaras del astronauta son `top_level` y siguen la
  posición INTERPOLADA del cuerpo con su orientación actual (el ratón no se retrasa). Cada recentrado del origen
  flotante y cada teletransporte reinicia la interpolación de todo el árbol (`FloatingOrigin.teleported`).
  Opción «Movimiento suave» para desactivarla. Medido a 45 FPS: variación del avance por fotograma 0,26 → 0,03 y
  cámara fija respecto a la cabina (0,1 mm). Sonda `--judder-probe [--nosmooth]`.
- Contacto con el suelo: casi quieta (< 1 m/s) se posa aunque no tenga el tren o esté inclinada; los roces lentos no
  sacuden y como mucho hay un golpe cada 0,4 s. Corregido además que el contacto suave midiera siempre 0 m/s.
- Aterrizaje automático (tecla de «Aterrizaje automático», antes «Volver al planeta»): se acerca hasta 3 km y desciende
  en vertical con un perfil seguro v = min(0,8 + 0,3·h, 0,8 + √(2·3·h)) expresado como velocidad DESEADA en el marco
  del cuerpo (independiente de la actitud); se detiene la deriva lateral antes de tocar. La llamada a la nave usa el
  mismo perfil. Asistencia de aterrizaje manual: 1 + 0,45·h m/s bajo 55 m. Prueba: Venus desde 3 km, contacto a
  < 2,5 m/s y sin golpes.

**Estado.** Aceptada.

## ADR-043 — Base lunar LF-01 de MacSpaces, prólogo y diálogos

**Contexto.** El usuario describe la base LF-01 (semienterrada, cámara criogénica del programa CajaFuerte, mensaje
grabado de Magnus Blackwell, operaciones, energía, hangar con la nave inmovilizada, esclusa) y el prólogo de una
partida nueva, con 32 audios disparados por EVENTOS y el discurso de Magnus obligatorio con subtítulos.

**Decisión.**
- La base es un sitio fijo de la Luna (12° N, 47,95° O, 1,5 km al este del punto de aparición clásico). El terreno
  sigue siendo procedural; `TerrainGenerator` sólo lo aplana en una explanada (radio 135 m + 90 m de transición,
  altura del centro calculada sin explanada en todos los hilos) y no siembra rocas encima. Se declara en
  KNOWN_LIMITATIONS: es un aplanado explícito, no un cambio silencioso del relieve.
- `BaseLayout` (datos: 22 salas, 22 puertas con estado, 18 interactivos, puntos de objetivo), `BaseBuilder` (geometría
  agrupada por sala, carcasa exterior con taludes de regolito recortados para no invadir otras salas, luces, carteles,
  logotipos, mobiliario), `BaseDoor` (abierta, sin energía, restringida, obstruida, guion, escotilla) y `LunarBase`
  (colocación desde su posición BF exacta en cada recentrado, luces de emergencia parpadeantes, energía auxiliar,
  salas visibles por puertas abiertas a dos saltos, cápsula, palanca, esclusa, techo del hangar, interacciones,
  guardado). Cada sala tiene sus propios tabiques: ocultar una nunca abre huecos en otra.
- `PrologueDirector`: pasos con objetivo y marcador; audios por evento (nunca por tiempo); sólo se abren las puertas
  necesarias para llegar al hangar; la nave no despega hasta salir a la superficie (entonces se abre el techo).
- `DialogueDirector`: una voz a la vez (cola con pausa), cada diálogo importante una sola vez (se guarda), errores
  repetibles con pausa mínima y nunca encima de otra voz, subtítulos sincronizados, Espacio omite lo omitible, bus
  «Voces» con volumen propio que atenúa música y ambiente. Los audios que faltan (16, 24-32) se saltan sin error.
- `StoryHud`: objetivo con marcador, subtítulos, indicador de voz para audios sin transcripción, barra de progreso y
  efecto de despertar (desenfoque de 9 muestras, tinte naranja, parpadeos).
- La partida nueva empieza poco después del amanecer lunar en la base (al salir hay luz rasante y la Tierra).

**Estado.** Aceptada. `--prologue-smoke` (44 comprobaciones, con guardado y carga a mitad), `--base-shots`,
`--prologue-shots`.

## ADR-044 — En línea sin servidor de pago: el anfitrión es el PC de un jugador

**Contexto.** El usuario quiere jugar en línea sin pagar servidores, con su PC como anfitrión, salas, nombres y hasta
6 jugadores. Investigación: ENet (UDP) incluido en Godot; UPnP incluido para abrir el puerto (no siempre funciona);
la perforación de NAT con relé (netfox.noray, MIT) exige otro servidor; Steam no es gratis.

**Decisión.**
- `Net` (autoload `NetSession`): anfitrión ENet en el puerto 7777 (configurable), máximo 6; UPnP en un hilo con la IP
  pública; anuncio de salas por difusión UDP (7778) para la red local; unión por IP o desde la lista; nombres únicos;
  expulsión. Si UPnP falla: puerto UDP a mano o una red virtual gratuita (ZeroTier, Tailscale, Radmin VPN); el juego
  sólo necesita una IP alcanzable. Todas las RPC viven en /root/Net (misma ruta en todos los equipos).
- `NetWorld` (en cada mundo en línea): cada jugador manda en su astronauta (20 estados/s; a bordo, pose relativa a la
  nave); quien pilota manda en la nave (`Ship.net_puppet` en los demás, con extrapolación y corrección suave); el
  anfitrión manda en la historia (prólogo, base, diálogos, hora) y en el guardado. Los clientes PIDEN interacciones,
  omitir el mensaje o llamar a la nave. Cada equipo tiene su origen flotante y su cuerpo dominante; las posiciones se
  convierten de marco con `SolarSystem.convert_point`.
- `RemoteAstronaut`: sólo el cuerpo animado, suavizado, con nombre y colores del perfil del dueño.
- En línea el menú de pausa no detiene el mundo; muestra la sala, los jugadores y las IP para invitar.

**Estado.** Aceptada (v1). `--net-smoke=host|join` con dos procesos (`tools/net_smoke.ps1`).

## ADR-045 — Ronda 11: colisiones de la base, cápsulas, compuerta del hangar, vuelo y mecánicas nuevas

**Contexto.** Lista de fallos del usuario (física, renderizado, audio, entorno y vuelo) y petición de más jugabilidad.

**Decisión.**
- Colisiones: la base usaba el NÚMERO de capa (`Layers.PHYS_SHIP` = 4) como máscara; el astronauta detecta bits 1 y 4
  (valores 1 y 8). Todos los cuerpos de la base usan ahora `Layers.bit(...)`. Regla en CLAUDE.md. Prueba con rayos.
- Cápsulas: seis cápsulas con puerta animada (`BaseLayout.PODS`); cada jugador (cooperativo o en línea) despierta en
  el CENTRO de la suya mirando a la puerta; el anfitrión reserva cápsula a quien entra (`LunarBase.assign_pod`).
- Suelo de la base a +5 cm de la explanada (z-fighting con el terreno). Carcasa exterior visible también desde el
  observatorio, el hangar abierto y la esclusa abierta; taludes de doble cara.
- Hangar: marco perimetral macizo, dos hojas de 0,8 m con costillas y franjas de aviso sobre raíles que salen a
  pórticos exteriores, motores, contrafuertes, balizas giratorias y alarma; 12 s con arranque y frenado suaves; panel
  manual; se abre sola con alguien a los mandos de la nave dentro del recinto y bloquea el despegue hasta abrir
  (`Ship.takeoff_guard`).
- Esclusa reversible con panel exterior para volver a entrar (despresurizar desde fuera, presurizar desde dentro).
- Gravedad artificial de 1 g en la base al conectar la red (FICTICIO); el parpadeo de arranque ya no la alterna.
- Mensaje de Blackwell: música a 0, ambiente al 12 %, voz +4 dB (datos en prologue.json).
- Cámara: muelle de la cabeza en subpasos de 1/240 s (inestable con tirones de FPS) y aceleración corporal medida por
  paso de física (picos alternos). 3ª persona sentado: por encima del respaldo. Near mínimo 0,05/0,08 m.
- Visor: el oscurecimiento por el Sol se atenúa con la luz que deja pasar la atmósfera (Venus se veía negro en 1ª).
- Casco de la nave de doble cara y forro interior continuo detrás de las paredes del casco y bajo la cubierta (en un
  lote que nunca se oculta): las rendijas entre tabiques muestran pared iluminada, no el exterior.
- Plafones del hangar colgados bajo las cerchas (flotaban en el aire con las compuertas abiertas).
- Vuelo: rampa de despegue (15 → 100 % en 9 s bajo 5 km) y aceleración reducida en aire denso; maniobra vertical que
  escala con la altitud (25 m/s junto al suelo, +2 cm/s por metro, máx. 3 km/s): bajar desde la llegada de un viaje
  ya no «se atasca»; aviso de aterrizaje automático al llegar; llamada a la nave a velocidad máxima con altura de
  crucero proporcional a la distancia, turbo y frenado con margen.
- Cabina invisible en 1ª persona a gran velocidad (reproducido con las capturas del usuario): los ocupantes de los
  asientos se colocan en el mismo paso de física que la nave y, si hubo recentrado del origen, se reinicia la
  interpolación DESPUÉS de mover nave, pasajeros y ocupantes (antes la cámara se interpolaba desde la posición vieja).
- La base sólo existe con la Luna como cuerpo dominante (antes, al viajar, quedaba mal colocada con colisiones).
- Mecánicas nuevas: componentes del NEXUS (6 instalaciones de MacSpaces, objetivo con distancia, diario, guardado;
  ubicaciones FICTICIAS) y balizas de exploración (hasta 8 por mundo, tecla O o menú rápido, marcador en el HUD).

**Estado.** Aceptada. `--prologue-smoke` (cápsula, colisiones, gravedad, esclusa, hangar, NEXUS), `--exploration-smoke`
(balizas), `--render-probe [--only=grupo]` para los casos de renderizado.

## ADR-046 — Chat de voz real: proximidad espacial, radio semidúplex y canal de la nave

**Contexto.** El usuario pide voz multijugador real (no una simulación local): proximidad con distancia, dirección,
oclusión, eco del entorno y filtro de casco; radio personal por canales, semidúplex, con pulsar para hablar, aviso de
canal ocupado, pitido y ruido; canal de grupo de la nave por megafonía a bordo; indicadores, ajustes guardados.
Godot 4.7 no trae códec de voz (Opus haría falta compilarlo o una extensión de terceros).

**Decisión.**
- Captura: `AudioStreamMicrophone` → bus «Microfono» (silenciado) con `AudioEffectCapture`; se remuestrea a 12 kHz y
  se trocea en tramas de 40 ms (480 muestras). Códec propio μ-law de 8 bits (`VoiceCodec`): ~12 KB/s por quien habla,
  sin dependencias. Detección de voz con umbral ajustable y 0,35 s de cola; o pulsar para hablar.
- Rutas con autoridad del ANFITRIÓN: los clientes sólo mandan sus tramas al anfitrión (`voice_frame`, no fiable y
  ordenado, canal ENet 1); el anfitrión valida (la radio sólo pasa si el canal es de quien emite), recorta la voz
  SÓLO de proximidad para quien está a más de 1,6 × el alcance (ni se reenvía ni se reproduce) y reenvía
  (`voice_deliver`). Las peticiones de canal (`voice_radio_req/state/denied`) van fiables por el canal 2.
- Cada receptor elige UNA sola vía por trama (sin duplicados): proximidad si está al alcance; si no, radio del canal
  o canal de la nave (por los ALTAVOCES si está a bordo, por la radio del traje si no). En el vacío no hay proximidad
  por el aire: con casco entre astronautas se oye por el enlace del traje (filtro de casco).
- Radio semidúplex: un canal (4 por sala) lo ocupa quien lo pide primero; los demás reciben «canal ocupado por X» y no
  transmiten. Pitido de apertura/cierre y ráfaga de estática (`VoiceFx.squelch`). Cobertura: limpia hasta 50.000 km,
  degradada (ruido, cortes) hasta 2 millones de km, fuera de alcance después.
- Sonido: proximidad con `AudioStreamPlayer3D` en la cabeza del compañero (atenuación y dirección reales); oclusión
  por rayo contra muros (paso bajo a 900 Hz y −5 dB); buses VozProx (reverberación según la sala del oyente: hangar,
  pasillos, nave), VozRadio (compresor) y VozNave (ecualizador + reverberación), todos hacia «Voces». DSP por vía
  (`VoiceFx`): aire, casco (banda 250–3400 Hz con resonancia), radio (450–2700 Hz, saturación, compresión, ruido según
  cobertura) y megafonía; casco dañado (traje con poca integridad) añade interferencias.
- Sin respiración en el casco: preferencia de inmersión del usuario.
- `VoiceHud`: micrófono (verde proximidad, azul radio, naranja nave), canal (libre / transmitiendo / ocupado por X),
  quién habla y por qué vía, avisos (sin micrófono, fuera de cobertura, canal ocupado). Las etiquetas de nombre de los
  compañeros toman el color de la vía al hablar. Pestaña «Voz» en Opciones: dispositivos, volumen por vía (también
  altavoces de la nave), sensibilidad con medidor, prueba de micrófono (te oyes con el procesado), modo, teclas
  reasignables (intercambio si chocan), alcance (nunca mayor que la regla de la sala), efectos, silenciar y volumen
  por jugador. Todo en `user://settings.cfg`, sección «voz».

**Estado.** Aceptada (v1). `--net-smoke` con tres procesos y voz sintética: proximidad, radio a distancia, canal
ocupado, recorte en el anfitrión, altavoces de la nave. F3 muestra contadores de voz.

## ADR-047 — Sala de espera con «Listo», carga sincronizada y salida simultánea

**Contexto.** Crear una sala arrancaba la partida del anfitrión al instante y cada invitado entraba cuando podía.

**Decisión.**
- Estados de la sala en `Net.lobby_state`: esperando → iniciando → cargando → en_partida; por jugador: en la sala,
  listo, cargando, cargado, en partida (o «sin cargar» si agotó el tiempo). `LobbyPanel` muestra nombre, estado,
  ping (ENet RTT), listo ✔/✗ y expulsión; el botón «Listo» se puede cancelar.
- Sólo el anfitrión inicia y sólo con TODOS listos (validado en el anfitrión); un segundo inicio se rechaza; quien entra
  durante la carga es rechazado; en partida entra directamente (como en ADR-044).
- Inicio: el anfitrión reparte cápsulas y manda `begin(config)`; todos cargan con el mundo retenido (`net_hold`:
  astronautas congelados, prólogo parado). Cada cliente avisa al cargar, recibe el estado inicial (`start_sync`), lo
  aplica y confirma; con todos confirmados (o a los 90 s) el anfitrión manda `go_now` y todos se sueltan a la vez.
- Desconexiones: si se va un invitado en la sala o durante la carga, se le quita de la lista y la carga no le espera.
  Si se va el ANFITRIÓN, la sala se cierra para todos y vuelven al menú con aviso (no hay migración de anfitrión: él
  tiene el mundo y el guardado).
- Prueba: `--fixed-fps` no se usa en la prueba de red (con él, el anfitrión en la sala no completaba las conexiones).

**Estado.** Aceptada. `tools/net_smoke.ps1`: sin inicio automático, inicio rechazado sin «Listo», cancelación de
«Listo», doble inicio ignorado, carga retenida, salida simultánea, cada uno en su cápsula.

## ADR-048 — Ronda 13: voz cercana limpia, bases procedurales del NEXUS de día y registros de audio

**Contexto.** El usuario pide: (1) que la voz de proximidad no tenga ningún efecto (sólo la radio); (2) que las
instalaciones del NEXUS estén en el lado iluminado de cada mundo, no en la cara oculta; (3) que las bases del NEXUS de
cada planeta dejen de ser un puesto pequeño y sean como LF-01 pero aleatorias y procedurales; (4) que al recoger cada
pieza del NEXUS suene uno de los audios que ha grabado (5 archivos, repartidos al azar por ahora).

**Decisión.**
- Voz (modifica ADR-046): la proximidad suena LIMPIA: sin filtro de casco, sin reverberación de sala, sin oclusión por
  muros y sin el pasa-bajo de la distancia del reproductor 3D; sólo dirección y volumen por distancia. Radio (y radio
  del traje para el canal de la nave fuera de ella) con todo su procesado; los altavoces de la nave conservan la
  megafonía (opción «Megafonía de la nave»).
- Ubicación (`NexusQuest.site_dir`): al llegar al cuerpo se calcula el punto subsolar y hacia dónde avanza (Sol ahora y
  dentro de una hora); la instalación va 35° por delante (mañana local: Sol a ~55° y subiendo durante horas). Entre 28
  candidatos a 0,3–5 km se elige el de menor desnivel en 90 m. Se guarda en el diario (`nexus_sites`); si al volver es
  de noche y el componente sigue allí, se elige otra vez. En línea manda la ubicación del anfitrión (estado del mundo).
- Base procedural (`NexusOutpost`, semilla = cuerpo, igual en todos los equipos): núcleo de 13 m con cúpula y el
  pedestal, 5–8 módulos en cuadrícula de 18 m unidos por pasillos (árbol + algún anillo), uso y mobiliario por módulo,
  salas en emergencia al azar, entrada con rellano, rampa de 17° y pórtico; exterior con plataforma de aterrizaje,
  farolas, mástil con la baliza, paneles solares, radiadores, depósitos y contenedores. Reutiliza los materiales y
  primitivas de `BaseBuilder`. No se aplana el terreno (la ubicación se decide después de crearlo): todo va a un nivel
  por encima del punto más alto, sobre pilotes con zapatas y un zócalo. `PlanetTerrain.exclude_rocks` quita las rocas
  de la zona (filtradas en el hilo principal al instanciarlas). Interior en SHIP_INT con un lote por módulo (límite de 8
  luces por malla), exterior en WORLD; 70–105 mallas agrupadas y 13–20 luces por base.
- Audios: `assets/audio/nexus/<cuerpo>.mp3` (copias de la carpeta del usuario), líneas `nexus_<cuerpo>` de
  `data/dialogue/prologue.json` (orden al azar, se reordena allí). Suenan con `DialogueDirector.say` al recoger la pieza;
  en línea se replican como el resto de diálogos. El director de diálogos existe ahora en todos los mundos.
- Clientes en línea: reciben del anfitrión los componentes recogidos y las ubicaciones (antes no se enteraban).

**Estado.** Aceptada. `--nexus-smoke` (5 mundos: generación, día, determinismo, colisiones de suelo/rampa/vano/pared,
recoger, audio) y `--nexus-shots [--only=mars]`.

## ADR-049 — Ronda 14: banda sonora con listas, controles de la megafonía, paquete para compartir y red para amigos

**Contexto.** El usuario quiere más música de fondo (sólo se oía una pista por situación), más control de la música
de la nave (altavoces, etc.), probar el juego con un amigo por Internet y un .exe para pasárselo.

**Decisión.**
- Banda sonora (`GameAudio` + `data/music.json`): pistas con contextos (menu, explore, deep, party), bolsa barajada
  por contexto sin repetir la anterior, silencio entre pistas según Opciones > Audio (continua, con pausas, a ratos,
  desactivada), aviso discreto con el título. 8 pistas CC0 de OpenGameArt descargadas con permiso del usuario
  (SRG774, wipics, Yoiyami); `gain_db` igualado con una medición RMS (`--audio-smoke`): las de SRG774 están ~25 dB por
  debajo y se suben +12..+18 dB.
- Megafonía de la nave (`ShipMusic`, `GameSettings.ship_*`, panel M): volumen guardado, volumen propio en Opciones >
  Audio, nivel de los altavoces respecto al puente, intensidad del efecto de altavoz, graves y agudos (EQ6 en el bus),
  orden (lista, aleatorio sin repetir, repetir canción), bajar la música mientras hay diálogo o habla un compañero, y
  oírla fuera de la nave por la radio del traje (opcional).
- Paquete sin plantillas de exportación (no instaladas): `--export-pack` genera `WeAreAlone.pck` y el binario oficial
  de Godot 4.7.2 renombrado `WeAreAlone.exe` lo carga solo al estar al lado. `tools/build.ps1` crea `build/` y el .zip
  con `LEEME.txt` (instrucciones para amigos). `build/.gdignore` evita que el editor importe el paquete.
- Música de la nave compartida en línea (`MusicShare`, hijo de NetWorld): quien pone una canción de su biblioteca es
  el DJ; publica el estado (MD5, título, pausa, posición) al cambiar y cada 3 s; quien no la tiene se la pide y el DJ
  la envía en trozos de 16 KB por el canal ENet 3 (~600 KB/s), se guarda en `user://music/compartida/<md5>` y suena
  sincronizada (corrección si se desvía > 0,4 s). Los controles de los demás se piden al DJ (`ShipMusic.forward`);
  poner otra canción propia te hace DJ. Máximo 40 MB por canción. Si el DJ se va, la música para.
- Red: `PROTOCOL` 4 (antes 1 pese a los cambios de RPC) y `GAME_VERSION` visible en el menú y en el rechazo por versión;
  aviso a los 12 s si el anfitrión no responde (IP/puerto, Firewall de Windows, UPnP o redes virtuales) o si conecta
  pero no contesta (otra versión); botón «Copiar dirección» en la sala (IP pública si UPnP la consiguió); consejos de
  Firewall en Crear sala.

**Estado.** Aceptada. `--audio-smoke`, `tools/net_smoke.ps1`, y las pruebas ejecutadas también desde el paquete.

