# Limitaciones conocidas (estado tras el Hito 1)

## Simulación y física
- En superficie se usa el marco fijo al cuerpo (rotante) **sin fuerzas ficticias** (Coriolis/centrífuga;
  ≤ 0,034 m/s² en la Tierra). La rotación sólo se ve en el movimiento del Sol.
- El Sol no tiene declinación estacional: se fija a la mitad de la oblicuidad del cuerpo.
- Control aéreo mínimo (0,6 m/s²) aunque no haya atmósfera: concesión de jugabilidad.
- El modo **vuelo** (tecla F) es una herramienta de depuración: sin colisión, sin física, velocidad arbitraria.
  No es la nave (Hito 2).
- No hay aerodinámica; la atmósfera de Prototipo-A es sólo visual (cielo + bruma).
- Las rocas no se apoyan sobre la malla sino sobre la altura analítica (se hunden un 30 % para ocultarlo).
  Sólo las rocas ≥ 0,7 m tienen colisión (esférica, aproximada).

## Cuerpo y cámara
- El modelo es de primitivas (sin malla esculpida ni texturas de tela); no hay dedos articulados.
- La animación es procedural: no hay animaciones de agacharse, caerse o recoger objetos; la parte inferior del
  cuerpo gira junto con la vista (al girar en el sitio se dan pasitos, pero sin pies fijos en el mundo).
- Con un traje real apenas se ven los pies; aquí se exagera ligeramente la inclinación del torso y el
  adelanto de la cabeza al mirar abajo para que se vean (decisión de jugabilidad).
- Sin sombras en calidad media: el propio cuerpo no proyecta sombra en el suelo (activable en calidad alta).
- La respiración del traje se eliminó a petición del usuario; quedan pisadas y zumbido del soporte vital.
- El brillo del Sol sólo se oculta por relieve con colisión (≤ 120 m del jugador) o por el horizonte geométrico;
  montañas lejanas sin colisión no lo tapan todavía.
- El oscurecimiento del visor es un velo de color (no hay HDR ni exposición automática en Compatibility).
- Asomarse no desplaza la cápsula de colisión: sólo inclina el cuerpo visual y la cámara.

## Nave (Hito 2)
- A bordo se siente la gravedad aparente, pero la "compensación inercial" (ficticia) limita a 6 m/s² lo que se
  nota de las maniobras; la gravedad artificial (G) es ficticia. Caminar mientras la nave gira con fuerza puede
  tirar al astronauta contra las paredes (realista, pedido); con G se camina como antes.
- El frenado de emergencia (X) detiene la nave en ≈1,5 s desde cualquier velocidad: ficticio, por jugabilidad.
- Música: sólo archivos MP3/OGG locales o enlaces directos; Spotify/YouTube no son posibles (DRM/condiciones de
  uso). Sin ecualizador ni lista aleatoria; la música no se replica todavía (no hay red).
- La ventana del suelo es transitable pero no se puede romper ni abrir.
- Flotando no hay animación específica de traje (se usa la postura en el aire) ni colisión de extremidades.
- La llamada a la nave (B) aterriza en terreno sin comprobar pendientes ni rocas del punto elegido.
- Los regímenes Crucero, Alta velocidad y Lumínico usan aceleraciones ficticias. El modo lumínico es abstracto,
  no relativista (sin dilatación temporal ni efectos ópticos) y no hay destinos todavía (Hito 3-4).
- La nave no tiene sistema de daños propio: un impacto fuerte frena la nave, avisa y sacude/daña a los pasajeros.
- La esclusa no simula presión ni aire (transición sencilla con interbloqueo y ciclo de 2,5 s).
- Colisión nave-terreno analítica (por la altura procedural) con margen por inclinación; no usa la malla fina
  ni las rocas, así que el tren puede quedar unos centímetros por encima o por debajo del suelo visible.
- El parabrisas y las ventanas no tienen cristal (huecos con montantes; la colisión sí está cerrada).
- Casco liso generado por secciones (ADR-021) pero sin texturas pintadas; el interior sigue siendo de primitivas.
- En calidad "alta" (sombras) el HD 630 baja a 45–64 FPS con la nave; se recomienda "media".
- La rampa siempre está desplegada con la nave posada (no se anima).
- Sólo hay una nave y un astronauta; la red no está implementada (ver ADR-015).
- Despegar exige Espacio (impulso vertical); con la nave posada se ignora la velocidad objetivo.
- Arcade usa aceleraciones y una velocidad máxima dependiente de la altitud deliberadamente ficticias
  (diversión antes que realismo); el modo Simulación conserva el modelo con regímenes.
- Las naves a más de 6 km de una cámara situada a gran altitud no se dibujan (fuera del alcance de la
  superposición de plano cercano); a esa distancia ocupan menos de un píxel.

## Sistema Solar (Hito 3)
- Efemérides keplerianas (sin perturbaciones): error de minutos de arco en los planetas en 1800-2050; las lunas
  menores usan elementos medios (pueden desviarse grados con los años). Plutón deriva fuera de ±50 años de J2000.
- Gravedad sólo del cuerpo dominante (sin el Sol a la vez ni efectos de marea); el marco rotante ignora Coriolis.
- Al cambiar de cuerpo dominante NO se suman las velocidades orbitales (compensación ficticia).
- Salto por encima de c hasta 1000 c: FICTICIO (a escala real, a la velocidad de la luz Neptuno está a ~4 h).
  El mapa usa escala logarítmica de distancias en la vista del sistema (a escala lineal no caben todos).
- 414 lunas sin radio publicado por el JPL usan un radio típico (`estimated`) y una forma genérica.
- Los fragmentos de la Tierra no tienen colisión ni se puede aterrizar en ellos; el núcleo es sólo visual.
- Los gigantes gaseosos y el Sol no tienen malla: se ven en el cielo analítico; el interior se representa con
  niebla y color según la capa (sin nubes volumétricas). Sin colisión con los anillos de Saturno.
- Casco y traje indestructibles salvo por el calor del Sol (FICTICIO, ADR-031): a escala real ninguna nave
  sobreviviría a cientos de bar en Júpiter. El rescate de emergencia queda sólo para el Sol.
- La iluminación usa (1/d²)^0,4 en lugar de 1/d² (sin exposición automática en Compatibility).
- El relieve de todos los cuerpos es procedural; los contornos continentales de la Tierra son aproximados.

## Terreno
- Las grietas entre niveles de LOD se tapan con faldones: posibles discontinuidades sutiles de color
  en la frontera entre niveles. Hay "popping" leve al cambiar de nivel (sin geomorfing).
- El LOD sólo usa la distancia (sin culling por horizonte ni error en pantalla).
- `FastNoiseLite` trabaja en 32 bits: la longitud de onda mínima del ruido se limita a ≥ 30 m. El relieve más
  fino lo aportan la textura de detalle y las rocas.
- Las UV de detalle son continuas dentro de cada cara del cubo, pero no a través de las aristas del cubo.
- Sin océanos, ríos, vegetación ni biomas complejos (sólo color por altura/pendiente/latitud).
- No hay persistencia de cambios en el terreno (todavía no existen cambios que guardar).
- El terreno de la Luna es procedural: **no** representa la topografía real (LOLA/LRO).

## Render
- Compatibility usa profundidad de 24 bits sin Z inversa; se mitiga con near/far dinámicos. No se han observado
  artefactos en las capturas, pero escenas con objetos cercanos y terreno lejano superpuestos (nave) deben vigilarse.
- Sombras desactivadas en calidad baja/media. Iluminación lambertiana sin especular.
- El cielo es un shader aproximado (no dispersión atmosférica física).
- El disco solar tiene el tamaño angular visto desde 1 UA para todos los cuerpos (se parametrizará en el Hito 3).

- El temblor de cámara tras pilotar que describió el jugador no se ha podido reproducir con la sonda
  (`--shake-probe`); se eliminaron todas las fuentes conocidas de movimiento en reposo. Si persiste, hace falta
  una descripción más concreta (¿sentado/de pie?, ¿nave posada?, ¿1ª/3ª persona?).
- Carga del terreno: el descenso especulativo apenas acorta la espera en las pruebas (el cuello de botella es el
  número total de parches); la mejora medida es ≈10 %.

## Interfaz y otros
- Menús mínimos. La reasignación de controles aún no tiene interfaz (las acciones se registran en `GameInput`).
- La calidad gráfica elegida en el menú se aplica al entrar en un mundo (no en caliente).
- No hay guardado de partida (posición, descubrimientos): previsto para hitos posteriores.
- La exportación necesita incluir `data/*` en el filtro de archivos no-recurso del preset.
- La entrada interactiva con ratón (mirar, menú de pausa) se ha revisado en código pero las pruebas
  automáticas la ejercitan mediante acciones simuladas, no con un ratón real.

## Cooperativo local, menús y audio (ronda 7)
- Cooperativo: un único origen flotante y un único cuerpo dominante. A pie, máximo 20 km entre jugadores; al
  despegar la nave, quien esté fuera sube a bordo. El jugador 2 necesita un mando.
- El mapa, el diario y el reproductor ocupan toda la pantalla aunque los abra un solo jugador.
- La pantalla dividida dibuja la escena dos veces: en gráficos integrados conviene la calidad baja o media.
- Parte del audio es grabado (Kenney, CC0) y el resto sintetizado. Los sonidos ambientales se oyen desde el
  jugador anfitrión.
- La mineralogía de las muestras es procedural (plausible, no medida). Una sola partida guardada.
- Los fragmentos de la Tierra siguen sin suelo propio: no se puede aterrizar en ellos.

## Imagen (ronda 8)
- Los materiales de la nave son procedurales (sin texturas pintadas): de muy cerca se nota su origen matemático.
- El resplandor de la Tierra rota sobre la Luna es ficticio (como la destrucción de la Tierra) y exagerado para que
  se vea; la luz cenicienta real sería mucho más débil.
- El visor dorado tiñe la vista al mirar hacia el Sol (efecto del casco, se puede desactivar en Opciones).
- Los efectos de imagen cuestan ~5 FPS en calidad alta en gráficos integrados; se pueden desactivar.

## Rendimiento y movimiento (rondas 9-10, ADR-041/042)
- Frente a la Tierra rota el cielo sigue costando ~8 ms en la HD 630 (46 FPS en calidad alta, antes 21).
- La interpolación de física se reinicia en cada recentrado del origen flotante (cada ~1 km recorrido): a gran
  velocidad ese fotograma se dibuja sin interpolar (un tirón mínimo cada segundo a 1000 m/s).
- El cuerpo propio en 1ª persona se interpola con un paso de retraso en el giro del ratón (la cámara no).

## Base LF-01 y prólogo (ADR-043)
- La explanada bajo la base es un aplanado EXPLÍCITO del terreno procedural (radio 135 m); el resto de la Luna no cambia.
- Los audios 16 y 24-32 no existen todavía: sus eventos funcionan pero no suena nada. Los audios 20 y 21 que nos
  pasaron son el mismo archivo. Los audios 1-23 no tienen transcripción: se muestra un indicador de voz en lugar
  de subtítulos (basta con rellenar «text» en `data/dialogue/prologue.json`).
- Los subtítulos del discurso de Magnus se corrigieron a mano desde una transcripción automática con errores; alguna
  frase poco audible es una reconstrucción plausible.
- Salas cerradas en el prólogo (dormitorios, cocina, despacho, sector C, talleres, almacén) existen pero casi vacías.
- Una sola planta: los suelos de la base están al nivel de la explanada.

## En línea (ADR-044)
- Sin servidor intermedio: si el router del anfitrión no admite UPnP (o el operador usa CGNAT), hay que abrir el
  puerto UDP a mano o usar una red virtual gratuita (ZeroTier, Tailscale, Radmin VPN).
- En línea sólo hay un jugador local por equipo (no se combina con la pantalla dividida).
- Sólo guarda el anfitrión. Los clientes que entran a mitad aparecen junto al anfitrión (o en las cápsulas si el
  prólogo acaba de empezar). Las muestras, el diario y las fotos de cada cliente son locales.
- Los asientos no se reservan entre equipos salvo el de piloto (manda quien pilota); dos jugadores pueden coincidir
  en otro asiento.
- Probado con tres procesos en el mismo PC (127.0.0.1); falta probar con latencia real por Internet.

## Ronda 11 (ADR-045)
- (Resuelto en la ronda 11, con las capturas del usuario) La cabina desaparecía en 1ª persona con el motor lumínico:
  los ocupantes de los asientos se recolocaban después de reiniciar la interpolación y la cámara quedaba lejos de la nave.
- (Resuelto en la ronda 13) Las instalaciones del NEXUS fuera de la Luna eran puestos sencillos: ahora son bases
  procedurales (ADR-048).
- Las balizas son de cada jugador (no se comparten en línea).
- La gravedad artificial de la base es FICTICIA, como la de la nave.

## Voz y sala de espera (ADR-046/047)
- Sin Opus: códec μ-law a 12 kHz, ~12 KB/s por cada jugador que habla (el anfitrión reenvía a los demás). Calidad de
  teléfono, suficiente para el estilo de radio; con 6 jugadores hablando a la vez el anfitrión sube ~60 KB/s.
- La voz es sólo para el jugador local principal (no para el segundo jugador de la pantalla dividida).
- Las pruebas automáticas usan tonos sintéticos; la captura con micrófono real sólo se puede comprobar a mano
  (medidor y prueba de micrófono de la pestaña «Voz»), y falta probar la voz entre dos PC.
- El mando sólo tiene la radio en Compartir/Captura; el resto de teclas de voz se reasignan con teclado o ratón.
- Oclusión con un único rayo (la voz no rodea esquinas); reverberación por sala del OYENTE, no de quien habla.
- No hay migración de anfitrión: si el anfitrión se va, la sala se cierra.
- Quien no termina de cargar en 90 s entra «sin cargar» cuando acabe; la partida no le espera.
- Si dos jugadores están en el mismo sitio, sus etiquetas de nombre se solapan.

## Ronda 13 (ADR-048)
- Las bases del NEXUS no aplanan el terreno: van sobre pilotes; con mucho desnivel la rampa de entrada es larga.
- La ubicación «de día» vale al llegar: en Marte (día de 24,6 h) puede anochecer si te quedas muchas horas; en Mercurio,
  Venus, Europa y Titán dura días.
- Las bases son abandonadas y despresurizadas: no hay esclusa, gravedad artificial ni aire dentro (se va con el casco).
- Los audios del NEXUS no tienen subtítulos (no hay transcripción) y están repartidos al azar.
- Las capturas de FPS de las bases varían mucho con otros programas abiertos; falta medirlas con el PC libre.

## Ronda 14 (ADR-049)
- El .exe es el binario del EDITOR de Godot renombrado (180 MB, icono de Godot, sin firmar: SmartScreen avisa). Con las
  plantillas de exportación oficiales (descarga aparte) saldría un .exe más pequeño, más rápido y con icono propio.
- La prueba de unidades no encuentra los scripts dentro del paquete (van compilados) y la de la megafonía no puede leer
  los MP3 originales: dentro del paquete sólo valen `--smoke-test`, `--nexus-smoke`, `--net-smoke`… (el juego, bien).
- Música compartida: la primera vez que suena una canción tarda en llegar a los demás (≈ tamaño / 600 KB/s; un MP3
  de 5 MB, unos 9 s) y la sincronía es aproximada (±0,4 s, sin compensar la latencia de cada uno).
- La igualación de volumen de la banda sonora es aproximada (RMS en tres tramos de 4 s).

