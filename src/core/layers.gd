class_name Layers
extends RefCounted
## Capas de render y de física centralizadas (ADR-011).
##
## Render (VisualInstance3D.layers / Camera3D.cull_mask / Light3D.light_cull_mask):
## - El Sol sólo ilumina WORLD, HEAD, BODY y SHIP_EXT (el interior de la nave no recibe luz solar
##   a través del casco porque no hay sombras en Compatibility).
## - Las luces interiores sólo iluminan SHIP_INT, BODY_INT y HEAD_INT.
## - Un astronauta a bordo cambia su cuerpo a BODY_INT/HEAD_INT.

# --- Render (número de capa, 1..20) ---
const WORLD := 1
const HEAD := 2
const BODY := 3
const SHIP_EXT := 4
const SHIP_INT := 5
const BODY_INT := 6
const HEAD_INT := 7
const HEAD_P2 := 8       ## cabeza del jugador 2 (cooperativo: cada cámara oculta sólo SU cabeza; ADR-032)
const HEAD_INT_P2 := 9

# --- Física (número de capa) ---
const PHYS_TERRAIN := 1   ## terreno y rocas
const PHYS_ASTRONAUT := 2
const PHYS_SHIP := 4      ## casco, paredes y mobiliario de las naves


static func bit(layer: int) -> int:
	return 1 << (layer - 1)


static func bits(list: Array) -> int:
	var m := 0
	for l in list:
		m |= bit(l)
	return m


## Máscara de colisión de "suelo" para personajes, rayos de pies y cámaras.
static func solid_mask() -> int:
	return bit(PHYS_TERRAIN) | bit(PHYS_SHIP)


static func sun_mask() -> int:
	return bits([WORLD, HEAD, BODY, SHIP_EXT, HEAD_P2])


static func interior_light_mask() -> int:
	return bits([SHIP_INT, BODY_INT, HEAD_INT, HEAD_INT_P2])


## Capas de cabeza (exterior, interior) del jugador `slot`.
static func head_layers(slot: int) -> Vector2i:
	return Vector2i(HEAD_P2, HEAD_INT_P2) if slot == 1 else Vector2i(HEAD, HEAD_INT)


## Todas las capas que dibuja una cámara de jugador (sin quitar todavía su propia cabeza).
static func all_view_layers() -> int:
	return bits([WORLD, HEAD, BODY, SHIP_EXT, SHIP_INT, BODY_INT, HEAD_INT, HEAD_P2, HEAD_INT_P2])
