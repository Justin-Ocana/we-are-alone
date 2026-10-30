class_name BaseLayout
extends RefCounted
## Plano de la base lunar LF-01 de MacSpaces (ADR-043). Todo en metros, en el marco LOCAL de la base:
## X = este, Y = arriba, Z = sur (−Z = norte); el suelo está en y = 0, sobre una explanada del terreno.
##
## La base está semienterrada: módulos rectangulares unidos por un eje central norte-sur que termina en el
## hangar (sur). Al norte, la cámara criogénica del programa CajaFuerte, donde empieza la partida.
## Las paredes son de cada sala (dos tabiques espalda con espalda entre salas vecinas): así se puede dejar de
## dibujar una sala sin abrir huecos en las demás (lección de la nave, ronda 10).

const SITE_LAT := 12.0          ## grados (Oceanus Procellarum, cara visible: la Tierra queda en el cielo)
const SITE_LON := -47.95         ## 1,5 km al este del punto de aparición clásico (12, −48): se ve en el horizonte
const PAD_RADIUS := 135.0       ## m de explanada perfectamente llana bajo la base
const PAD_BLEND := 90.0         ## m de transición con el relieve natural
const WALL_T := 0.2
const DOOR_H := 2.4

## id → [nombre, x0, z0, x1, z1, altura, estado inicial de la luz ("emergencia" | "apagada")]
const ROOMS := {
	"crio": ["Cámara criogénica CajaFuerte", -9.0, -100.0, 9.0, -84.0, 4.5, "emergencia"],
	"recuperacion": ["Pasillo de recuperación", -1.6, -84.0, 1.6, -62.0, 3.0, "emergencia"],
	"enfermeria": ["Enfermería", -13.0, -80.0, -1.6, -68.0, 3.2, "emergencia"],
	"orientacion": ["Sala de orientación", -7.0, -62.0, 7.0, -50.0, 4.0, "emergencia"],
	"observatorio": ["Observatorio", -19.0, -62.0, -7.0, -50.0, 6.0, "emergencia"],
	"pasillo_norte": ["Eje central (norte)", -1.8, -50.0, 1.8, -10.0, 3.2, "emergencia"],
	"operaciones": ["Centro de operaciones", 1.8, -50.0, 15.0, -36.0, 3.6, "emergencia"],
	"comunicaciones": ["Sala de comunicaciones", 15.0, -50.0, 25.0, -40.0, 3.2, "emergencia"],
	"archivo": ["Archivo digital", 1.8, -34.0, 13.0, -24.0, 3.2, "emergencia"],
	"lab_experimental": ["Laboratorio experimental", 1.8, -22.0, 14.0, -12.0, 3.4, "emergencia"],
	"laboratorio": ["Laboratorio científico", 14.0, -22.0, 24.0, -12.0, 3.2, "emergencia"],
	"energia": ["Sala de energía", -15.0, -50.0, -1.8, -36.0, 4.5, "emergencia"],
	"hidroponia": ["Hidroponía", -16.0, -34.0, -1.8, -12.0, 3.6, "emergencia"],
	"pasillo_sur": ["Eje central (sur)", -1.8, -10.0, 1.8, 30.0, 3.2, "apagada"],
	"dormitorios": ["Dormitorios", 1.8, -8.0, 14.0, 4.0, 3.0, "apagada"],
	"comedor": ["Cocina y comedor", -16.0, -8.0, -1.8, 4.0, 3.2, "apagada"],
	"despacho": ["Despacho ejecutivo", 1.8, 6.0, 12.0, 16.0, 3.2, "apagada"],
	"sector_c": ["Sector C", -16.0, 6.0, -1.8, 18.0, 3.2, "apagada"],
	"taller": ["Talleres de mantenimiento", 1.8, 18.0, 14.0, 30.0, 4.0, "apagada"],
	"almacen": ["Almacén", -16.0, 20.0, -1.8, 30.0, 3.6, "apagada"],
	"hangar": ["Hangar principal", -35.0, 30.0, 35.0, 100.0, 22.0, "emergencia"],
	"esclusa": ["Esclusa y equipos EVA", 35.0, 56.0, 45.0, 70.0, 3.4, "emergencia"],
}

## Salas cuya luz vuelve con la energía auxiliar (sólo el camino al hangar).
const AUX_LIT := ["pasillo_norte", "pasillo_sur", "hangar", "esclusa", "taller"]

## id → [sala A, sala B ("" = exterior), centro (x, z), eje del tabique ("x": plano x = cte; "z": plano z = cte),
##        ancho, alto, estado inicial]
## Estados: "open" (se abre sola al acercarse), "locked_power" (sin energía), "locked_auth" (acceso restringido),
## "blocked" (obstruida), "locked_script" (la abre el prólogo), "cycle" (escotilla exterior de la esclusa).
const DOORS := {
	"d_crio": ["crio", "recuperacion", Vector2(0.0, -84.0), "z", 1.6, DOOR_H, "open"],
	"d_enfermeria": ["recuperacion", "enfermeria", Vector2(-1.6, -74.0), "x", 1.6, DOOR_H, "open"],
	"d_orientacion": ["recuperacion", "orientacion", Vector2(0.0, -62.0), "z", 1.6, DOOR_H, "open"],
	"d_observatorio": ["orientacion", "observatorio", Vector2(-7.0, -56.0), "x", 1.6, DOOR_H, "open"],
	"d_eje": ["orientacion", "pasillo_norte", Vector2(0.0, -50.0), "z", 1.8, DOOR_H, "locked_script"],
	"d_operaciones": ["pasillo_norte", "operaciones", Vector2(1.8, -43.0), "x", 1.8, DOOR_H, "open"],
	"d_comunicaciones": ["operaciones", "comunicaciones", Vector2(15.0, -45.0), "x", 1.6, DOOR_H, "open"],
	"d_archivo": ["pasillo_norte", "archivo", Vector2(1.8, -29.0), "x", 1.6, DOOR_H, "open"],
	"d_lab_exp": ["pasillo_norte", "lab_experimental", Vector2(1.8, -17.0), "x", 1.6, DOOR_H, "open"],
	"d_laboratorio": ["lab_experimental", "laboratorio", Vector2(14.0, -17.0), "x", 1.6, DOOR_H, "open"],
	"d_energia": ["pasillo_norte", "energia", Vector2(-1.8, -43.0), "x", 1.8, DOOR_H, "open"],
	"d_hidroponia": ["pasillo_norte", "hidroponia", Vector2(-1.8, -23.0), "x", 1.6, DOOR_H, "open"],
	"d_sector": ["pasillo_norte", "pasillo_sur", Vector2(0.0, -10.0), "z", 3.0, 2.8, "locked_power"],
	"d_dormitorios": ["pasillo_sur", "dormitorios", Vector2(1.8, -2.0), "x", 1.6, DOOR_H, "blocked"],
	"d_comedor": ["pasillo_sur", "comedor", Vector2(-1.8, -2.0), "x", 1.6, DOOR_H, "blocked"],
	"d_despacho": ["pasillo_sur", "despacho", Vector2(1.8, 11.0), "x", 1.6, DOOR_H, "locked_auth"],
	"d_sector_c": ["pasillo_sur", "sector_c", Vector2(-1.8, 12.0), "x", 1.6, DOOR_H, "locked_power"],
	"d_taller": ["pasillo_sur", "taller", Vector2(1.8, 24.0), "x", 1.6, DOOR_H, "locked_power"],
	"d_almacen": ["pasillo_sur", "almacen", Vector2(-1.8, 25.0), "x", 1.6, DOOR_H, "locked_power"],
	"d_hangar": ["pasillo_sur", "hangar", Vector2(0.0, 30.0), "z", 3.0, 3.0, "locked_power"],
	"d_esclusa": ["hangar", "esclusa", Vector2(35.0, 63.0), "x", 1.8, DOOR_H, "open"],
	"d_exterior": ["esclusa", "", Vector2(45.0, 63.0), "x", 1.8, DOOR_H, "cycle"],
}

## Puertas que abre la energía auxiliar (ADR-043: sólo las necesarias para llegar al hangar).
const AUX_UNLOCKS := ["d_sector", "d_hangar"]

## Interactivos: id → [texto de la acción, sala, posición (m, marco de la base), tipo]
## El prólogo decide qué hace cada uno (Prologue.on_interact); los "opcionales" cuentan lo que pasó en la base.
const TERMINALS := {
	"capsula": ["Salir de la cápsula", "crio", Vector3(0.0, 0.0, -98.6), "capsule"],
	"capsula_2": ["Salir de la cápsula", "crio", Vector3(-7.6, 0.0, -95.0), "capsule"],
	"capsula_3": ["Salir de la cápsula", "crio", Vector3(7.6, 0.0, -95.0), "capsule"],
	"capsula_4": ["Salir de la cápsula", "crio", Vector3(-7.6, 0.0, -91.0), "capsule"],
	"capsula_5": ["Salir de la cápsula", "crio", Vector3(7.6, 0.0, -91.0), "capsule"],
	"capsula_6": ["Salir de la cápsula", "crio", Vector3(-7.6, 0.0, -87.5), "capsule"],
	"terminal_medico": ["Consultar el terminal médico", "crio", Vector3(2.2, 1.1, -97.4), "medical"],
	"capsulas_resto": ["Examinar las demás cápsulas", "crio", Vector3(-6.0, 1.2, -92.0), "optional"],
	"terminal_danado": ["Usar el terminal", "recuperacion", Vector3(1.35, 1.2, -70.0), "damaged"],
	"enfermeria": ["Revisar el registro de la enfermería", "enfermeria", Vector3(-11.5, 1.1, -70.0), "optional"],
	"pantalla": ["Pantalla de orientación", "orientacion", Vector3(6.6, 2.0, -56.0), "screen"],
	"telescopio": ["Mirar por el telescopio", "observatorio", Vector3(-13.0, 1.2, -56.0), "optional"],
	"consola_ops": ["Usar la consola de operaciones", "operaciones", Vector3(8.4, 1.1, -43.0), "ops"],
	"terminal_nexus": ["Terminal NEXUS", "operaciones", Vector3(13.6, 1.2, -37.6), "optional"],
	"consola_com": ["Usar la consola de comunicaciones", "comunicaciones", Vector3(23.6, 1.1, -45.0), "optional"],
	"archivo": ["Consultar el archivo digital", "archivo", Vector3(7.0, 1.1, -25.0), "optional"],
	"lab_exp": ["Examinar el experimento", "lab_experimental", Vector3(8.0, 1.2, -17.0), "optional"],
	"generador": ["Revisar el generador principal", "energia", Vector3(-11.0, 1.4, -46.0), "optional"],
	"energia_aux": ["Activar la energía auxiliar", "energia", Vector3(-14.4, 1.2, -39.0), "aux_power"],
	"cultivos": ["Revisar el sistema de cultivos", "hidroponia", Vector3(-9.0, 1.1, -14.0), "optional"],
	"panel_hangar": ["Abrir o cerrar las compuertas del techo", "hangar", Vector3(-5.0, 1.1, 31.4), "hangar_roof"],
	"diagnostico": ["Iniciar el diagnóstico de la nave", "hangar", Vector3(26.0, 1.1, 50.0), "ship_diag"],
	"traje": ["Equiparse el traje EVA", "esclusa", Vector3(44.4, 1.1, 59.0), "suit"],
	"panel_esclusa": ["Iniciar el ciclo de la esclusa", "esclusa", Vector3(44.4, 1.3, 66.6), "airlock"],
	"panel_exterior": ["Abrir la esclusa desde fuera", "", Vector3(45.75, 1.3, 61.2), "airlock_ext"],
}

## Puntos de interés con nombre para los objetivos (marco de la base).
const POINTS := {
	"capsula": Vector3(0.0, 1.4, -97.0),
	"orientacion": Vector3(0.0, 1.4, -56.0),
	"operaciones": Vector3(8.4, 1.4, -43.0),
	"energia_aux": Vector3(-14.0, 1.4, -39.0),
	"hangar": Vector3(0.0, 1.4, 34.0),
	"diagnostico": Vector3(26.0, 1.4, 50.0),
	"traje": Vector3(44.0, 1.4, 59.0),
	"panel_esclusa": Vector3(44.0, 1.4, 66.6),
	"exterior": Vector3(52.0, 1.4, 63.0),
	"nave": Vector3(0.0, 0.0, 66.0),
}

const SHIP_POINT := Vector3(0.0, 0.0, 66.0)   ## la nave descansa aquí, morro al norte
## Cápsulas con puerta en las que despiertan los jugadores (hasta 6): [centro, giro (rad; mira a su +Z girado)].
## La primera es la del protagonista; las otras cinco, las laterales (ronda 11: antes los jugadores 2-6 aparecían
## DELANTE de las laterales, fuera de ellas).
const PODS := [[Vector3(0.0, 0.0, -98.6), 0.0], [Vector3(-7.6, 0.0, -95.0), PI * 0.5], [Vector3(7.6, 0.0, -95.0), -PI * 0.5],
	[Vector3(-7.6, 0.0, -91.0), PI * 0.5], [Vector3(7.6, 0.0, -91.0), -PI * 0.5], [Vector3(-7.6, 0.0, -87.5), PI * 0.5]]
## Dónde se está de pie DENTRO de cada cápsula (en su centro, entre el respaldo y la puerta).
const CAPSULE_SPOTS := [Vector3(0.0, 0.0, -98.6), Vector3(-7.6, 0.0, -95.0), Vector3(7.6, 0.0, -95.0),
	Vector3(-7.6, 0.0, -91.0), Vector3(7.6, 0.0, -91.0), Vector3(-7.6, 0.0, -87.5)]


## Hacia dónde mira quien despierta en la cápsula `i` (marco de la base).
static func pod_forward(i: int) -> Vector3:
	var r: float = PODS[i][1]
	return Vector3(sin(r), 0.0, cos(r))


static func room_rect(id: String) -> Rect2:
	var r: Array = ROOMS[id]
	return Rect2(r[1], r[2], r[3] - r[1], r[4] - r[2])


static func room_height(id: String) -> float:
	return float(ROOMS[id][5])


## Sala que contiene el punto (marco de la base) o "".
static func room_at(p: Vector3) -> String:
	if p.y < -0.5:
		return ""
	for id in ROOMS:
		var r: Array = ROOMS[id]
		if p.x >= r[1] and p.x <= r[3] and p.z >= r[2] and p.z <= r[4] and p.y <= float(r[5]) + 0.5:
			return id
	return ""


## Salas vecinas a través de puertas (sin contar el exterior).
static func neighbors(id: String) -> Array:
	var out := []
	for d in DOORS:
		var e: Array = DOORS[d]
		if e[0] == id and e[1] != "":
			out.append([e[1], d])
		elif e[1] == id:
			out.append([e[0], d])
	return out


## Explanada del terreno bajo la base (TerrainGenerator la aplana; ADR-043).
static func terrain_pad() -> Dictionary:
	var d := CubeSphere.latlon_to_dir(SITE_LAT, SITE_LON)
	var center := Vector3(0.0, 0.0, 0.0)
	return {"dir": [d.x, d.y, d.z], "radius_m": PAD_RADIUS, "blend_m": PAD_BLEND, "center_local": center}
