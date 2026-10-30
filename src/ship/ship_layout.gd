class_name ShipLayout
extends RefCounted
## Plano interior de la nave clase Kestrel, como datos (ADR-013). Lo usan ShipBuilder (geometría y
## colisión), Ship (zonas a bordo, esclusa, asiento) y las pruebas (conectividad y escala humana).
##
## Ejes locales de la nave: −Z = proa, +X = estribor (derecha), +Y = arriba. Suelo de la cubierta en y = 0.

## Rediseño (ADR-021): nave más grande y espaciosa — 57 m de eslora, 20 m de manga de casco, cubierta
## de 3 m, pasillo de 2,4 m, puente con cinco puestos y sala común con sofás frente a un ventanal.

const DECK_HEIGHT := 3.0
const DOOR_WIDTH := 1.4
const DOOR_HEIGHT := 2.3
const WALL_T := 0.12
const HULL_T := 0.25
const HALF_WIDTH := 9.0       ## semiancho interior del casco
const FRONT_Z := -18.0        ## mamparo delantero de los camarotes
const AFT_Z := 22.0           ## mamparo de popa
const COCKPIT_HALF := 5.0
const COCKPIT_FRONT_Z := -26.0
const CORRIDOR_HALF := 1.2
const ARCH_WIDTH := 2.4       ## arco entre el pasillo y el puente
const HALF_LENGTH := 28.6     ## semieslora exterior (morro a toberas)

## Habitaciones: id → [nombre, área del hito, mín (x, z), máx (x, z)]
const ROOMS := {
	"cabina": ["Puente de mando", "A", Vector2(-5, -26), Vector2(5, -18)],
	"pasillo": ["Pasillo central", "-", Vector2(-1.2, -18), Vector2(1.2, 10)],
	"comedor": ["Comedor y cocina", "B", Vector2(-9, -18), Vector2(-1.2, -8)],
	"dormitorios": ["Dormitorios", "C", Vector2(-9, -8), Vector2(-1.2, 2)],
	"almacen": ["Almacén", "F", Vector2(-9, 2), Vector2(-1.2, 10)],
	"enfermeria": ["Enfermería", "G", Vector2(1.2, -18), Vector2(9, -10)],
	"bano": ["Baño", "D", Vector2(1.2, -10), Vector2(9, -6)],
	"esclusa": ["Esclusa", "H", Vector2(1.2, -6), Vector2(9, 0)],
	"vestuario": ["Vestuario EVA", "-", Vector2(1.2, 0), Vector2(9, 4)],
	"salon": ["Sala común", "-", Vector2(1.2, 4), Vector2(9, 10)],
	"maquinas": ["Sala de máquinas", "E", Vector2(-9, 10), Vector2(9, 22)],
}

## Puertas: id → [habitación A, habitación B, centro (x, z) sobre el plano de la pared, normal "x"/"z", tipo]
## tipo: "arco" (sin hoja), "auto" (corredera automática), "esclusa_int", "esclusa_ext".
const DOORS := {
	"cabina": ["pasillo", "cabina", Vector2(0, -18), "z", "auto"],
	"comedor": ["pasillo", "comedor", Vector2(-1.2, -11.0), "x", "auto"],
	"dormitorios": ["pasillo", "dormitorios", Vector2(-1.2, -3.0), "x", "auto"],
	"almacen": ["pasillo", "almacen", Vector2(-1.2, 6.0), "x", "auto"],
	"enfermeria": ["pasillo", "enfermeria", Vector2(1.2, -14.0), "x", "auto"],
	"bano": ["pasillo", "bano", Vector2(1.2, -8.0), "x", "auto"],
	"esclusa_int": ["pasillo", "esclusa", Vector2(1.2, -3.0), "x", "esclusa_int"],
	"vestuario": ["pasillo", "vestuario", Vector2(1.2, 2.0), "x", "auto"],
	"salon": ["pasillo", "salon", Vector2(1.2, 7.0), "x", "auto"],
	"maquinas": ["pasillo", "maquinas", Vector2(0, 10), "z", "auto"],
	"esclusa_ext": ["esclusa", "exterior", Vector2(9.0, -3.0), "x", "esclusa_ext"],
}

## Puertas de tamaño especial (ancho, alto); las demás miden DOOR_WIDTH × DOOR_HEIGHT.
const DOOR_SIZES := {"cabina": Vector2(ARCH_WIDTH, 2.6)}
## Ventana en el suelo del pasillo central (se ve el terreno bajo la nave): x, z, ancho, largo.
const FLOOR_WINDOW := Rect2(-0.85, -16.0, 1.7, 24.0)

## Puesto de pilotaje: base del asiento (suelo) y orientación (mirando a −Z).
const PILOT_SEAT := Vector3(0, 0, -23.2)
## Asientos: id → [posición de la base (suelo), guiñada (rad, 0 = mirando a −Z), ¿mandos?]
const SEATS := {
	"piloto": [Vector3(0, 0, -23.2), 0.0, true],
	"copiloto": [Vector3(2.4, 0, -22.8), 0.0, false],
	"navegante": [Vector3(-2.4, 0, -22.8), 0.0, false],
	"ingeniero": [Vector3(-3.5, 0, -19.9), PI / 2.0, false],
	"comunicaciones": [Vector3(3.5, 0, -19.9), -PI / 2.0, false],
	"sofá 1": [Vector3(4.2, 0, 5.4), -PI / 2.0, false],
	"sofá 2": [Vector3(4.2, 0, 6.6), -PI / 2.0, false],
	"sofá 3": [Vector3(4.2, 0, 7.8), -PI / 2.0, false],
}
const SEAT_HEIGHT := 0.55
## Puestos interactivos (ADR-034): id → [punto de uso (espacio de la nave), texto de la acción, acción].
## Se usan con la tecla de interactuar a menos de STATION_REACH del punto.
const STATIONS := {
	"litera_1": [Vector3(-8.0, 0.5, -6.8), "Dormir 8 horas", "sleep"],
	"litera_2": [Vector3(-8.0, 0.5, 0.8), "Dormir 8 horas", "sleep"],
	"camilla_1": [Vector3(3.9, 0.8, -16.8), "Tratamiento médico (curarse)", "heal"],
	"camilla_2": [Vector3(6.4, 0.8, -16.8), "Tratamiento médico (curarse)", "heal"],
	"cafetera": [Vector3(-4.3, 1.1, -17.4), "Preparar un café", "coffee"],
	"trajes": [Vector3(5.0, 1.15, 3.2), "Recargar los propulsores del traje", "refuel"],
	"laboratorio": [Vector3(-4.0, 1.0, 3.1), "Laboratorio: analizar muestras", "lab"],
	"ingenieria": [Vector3(4.5, 1.0, 10.5), "Diagnóstico y reparación del casco", "repair"],
	"escritorio": [Vector3(-8.3, 1.0, -3.0), "Diario de exploración", "journal"],
}
const STATION_REACH := 1.7
## Punto de salida del astronauta al levantarse del puesto de pilotaje (detrás del asiento).
const SEAT_EXIT := Vector3(0, 0.05, -21.9)
const GEAR_DROP := 2.0        ## m de la cubierta al pie de las patas (debe coincidir con explorer.json)
## Patas del tren de aterrizaje (espacio de la nave, a nivel de la cubierta).
const GEAR_POINTS := [Vector3(0, 0, -22.0), Vector3(-6.5, 0, 14.0), Vector3(6.5, 0, 14.0)]
## Ventanas del casco por lado: [centro z, ancho, y0, y1]. Las puertas (y0 = 0) dejan paso.
const HULL_OPENINGS_LEFT := [[-13.0, 4.0, 1.0, 2.3], [-9.2, 1.6, 1.2, 2.2], [-4.4, 1.4, 1.2, 2.2], [-3.0, 0.9, 1.2, 2.2],
	[11.8, 2.6, 1.1, 2.4], [18.9, 2.6, 1.1, 2.4]]
const HULL_OPENINGS_RIGHT := [[-14.0, 3.0, 1.0, 2.3], [-11.2, 1.4, 1.2, 2.2], [-8.0, 1.0, 1.7, 2.2],
	[-3.0, DOOR_WIDTH, 0.0, DOOR_HEIGHT], [-0.8, 1.0, 1.3, 2.2], [7.0, 4.6, 0.75, 2.6], [11.8, 2.6, 1.1, 2.4], [18.9, 2.6, 1.1, 2.4]]
const COCKPIT_SIDE_WINDOW := [-23.2, 3.6, 1.0, 2.35]
const WINDSHIELD := Rect2(-4.4, 0.95, 8.8, 1.85)   ## hueco frontal del puente: x, y, ancho, alto


static func room_center(id: String) -> Vector3:
	var r: Array = ROOMS[id]
	var a: Vector2 = r[2]
	var b: Vector2 = r[3]
	return Vector3((a.x + b.x) * 0.5, 0.0, (a.y + b.y) * 0.5)


static func room_contains(id: String, p: Vector3, margin: float = 0.0) -> bool:
	var r: Array = ROOMS[id]
	var a: Vector2 = r[2]
	var b: Vector2 = r[3]
	return p.x >= a.x - margin and p.x <= b.x + margin and p.z >= a.y - margin and p.z <= b.y + margin \
		and p.y >= -0.3 and p.y <= DECK_HEIGHT + 0.2


## Habitación que contiene el punto (espacio local de la nave) o "" si está fuera.
static func room_at(p: Vector3) -> String:
	for id in ROOMS:
		if room_contains(id, p):
			return id
	return ""


## ¿Está el punto dentro del volumen presurizado (a bordo)?
static func is_aboard(p: Vector3) -> bool:
	if p.y < -0.3 or p.y > DECK_HEIGHT + 0.2:
		return false
	if p.x >= -HALF_WIDTH and p.x <= HALF_WIDTH and p.z >= FRONT_Z and p.z <= AFT_Z:
		return true
	return p.x >= -COCKPIT_HALF and p.x <= COCKPIT_HALF and p.z >= COCKPIT_FRONT_Z - 0.2 and p.z <= FRONT_Z


## Grafo de habitaciones conectadas por puertas.
static func adjacency() -> Dictionary:
	var g := {}
	for id in DOORS:
		var d: Array = DOORS[id]
		g[d[0]] = g.get(d[0], []) + [d[1]]
		g[d[1]] = g.get(d[1], []) + [d[0]]
	return g


## Punto a 0,9 m a un lado de la puerta (para recorridos de prueba). side = ±1.
static func door_approach(id: String, side: float) -> Vector3:
	var d: Array = DOORS[id]
	var c: Vector2 = d[2]
	if d[3] == "x":
		return Vector3(c.x + side * 0.9, 0.0, c.y)
	return Vector3(c.x, 0.0, c.y + side * 0.9)
