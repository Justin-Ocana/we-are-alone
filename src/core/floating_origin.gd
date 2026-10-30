class_name FloatingOriginService
extends Node
## Origen flotante (autoload `FloatingOrigin`). Ver ADR-003.
##
## El punto (0,0,0) del motor corresponde a `offset` en el marco del cuerpo (BF, doble
## precisión). Cuando el foco se aleja más de `threshold_m`, se recentra: el offset absorbe
## la posición del foco y los nodos del grupo `floating_origin` se desplazan en sentido opuesto.
## Los sistemas que guardan posiciones en DVec3 (terreno) escuchan `origin_shifted` y
## recalculan sus posiciones locales desde cero.

signal origin_shifted(delta: Vector3)

const GROUP := &"floating_origin"
const DEFAULT_THRESHOLD_M := 1024.0

var offset: DVec3 = DVec3.new()
var threshold_m: float = DEFAULT_THRESHOLD_M
var shift_count: int = 0


## Fija el origen en una posición BF (teletransporte). Los nodos del grupo no se mueven; los
## sistemas con posiciones DVec3 se recolocan al recibir `origin_shifted(Vector3.ZERO)`.
func reset(new_offset: DVec3) -> void:
	offset = new_offset.copy()
	shift_count = 0
	origin_shifted.emit(Vector3.ZERO)
	teleported()


## Marco BF (doble) → marco local del motor (32 bits). Sólo es preciso cerca del origen.
func to_local(p: DVec3) -> Vector3:
	return Vector3(p.x - offset.x, p.y - offset.y, p.z - offset.z)


## Marco local del motor → marco BF (doble).
func to_global(v: Vector3) -> DVec3:
	return DVec3.new(offset.x + v.x, offset.y + v.y, offset.z + v.z)


## Recentra si `focus` (posición local) supera el umbral. Devuelve true si hubo recentrado.
func update_focus(focus: Vector3) -> bool:
	if focus.length() < threshold_m:
		return false
	shift(focus)
	return true


func shift(delta: Vector3) -> void:
	offset = DVec3.new(offset.x + delta.x, offset.y + delta.y, offset.z + delta.z)
	shift_count += 1
	if is_inside_tree():
		for n in get_tree().get_nodes_in_group(GROUP):
			var n3 := n as Node3D
			if n3 != null and n3.is_inside_tree():
				n3.global_position -= delta
	origin_shifted.emit(delta)
	teleported()


## Interpolación de física (ronda 10, ADR-042): naves y astronautas se dibujan interpolados entre pasos de física.
## Tras un salto de todo el mundo (recentrado, teletransporte, cambio de cuerpo) se reinicia en todo el árbol: si no,
## cruzarían en un fotograma el kilómetro desplazado. Ese fotograma se dibuja sin interpolar (como antes).
func teleported() -> void:
	if is_inside_tree():
		get_tree().root.reset_physics_interpolation()


func _ready() -> void:
	# Sólo se interpola lo que se mueve en pasos de física (naves y astronautas lo activan); el resto del árbol
	# (terreno, cielo, nubes, interfaz) se coloca cada fotograma y no debe interpolarse.
	get_tree().root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
