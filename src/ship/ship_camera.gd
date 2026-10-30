class_name ShipCamera
extends Camera3D
## Cámara exterior de la nave (ADR-014): persecución por detrás y por encima, con órbita libre
## manteniendo clic derecho (o Alt) y distancia ajustable (clic derecho + rueda). Muestra el MISMO objeto físico que la vista
## interior: su posición se calcula cada fotograma a partir del transform real de la nave, con el
## suavizado hecho en el espacio local de la nave (sin quedarse atrás a ninguna velocidad).

const DEFAULT_YAW := 0.0
const DEFAULT_PITCH := -0.28
const MIN_DIST := 30.0
const MAX_DIST := 600.0

var ship: Ship
var distance := 75.0
var orbit_yaw := DEFAULT_YAW
var orbit_pitch := DEFAULT_PITCH
var _smooth_offset := Vector3.ZERO
var _initialized := false


func _ready() -> void:
	top_level = true
	near = 0.1
	far = 1.0e6


func orbit(rel: Vector2, sens: float) -> void:
	orbit_yaw -= rel.x * sens
	orbit_pitch = clampf(orbit_pitch - rel.y * sens, -1.4, 1.4)


func zoom(factor: float) -> void:
	distance = clampf(distance * factor, MIN_DIST, MAX_DIST)


func update_view(delta: float, orbiting: bool) -> void:
	if ship == null:
		return
	if not orbiting:
		# Vuelve suavemente a la posición de persecución.
		orbit_yaw = lerp_angle(orbit_yaw, DEFAULT_YAW, 1.0 - exp(-1.5 * delta))
		orbit_pitch = lerpf(orbit_pitch, DEFAULT_PITCH, 1.0 - exp(-1.5 * delta))
	var dir := Basis(Vector3.UP, orbit_yaw) * Basis(Vector3.RIGHT, orbit_pitch) * Vector3(0, 0, 1)
	var target_offset := dir * distance + Vector3(0, 5.0, 0)
	if not _initialized:
		_smooth_offset = target_offset
		_initialized = true
	_smooth_offset = _smooth_offset.lerp(target_offset, 1.0 - exp(-6.0 * delta))
	var xf := ship.get_global_transform_interpolated() if ship.is_physics_interpolated_and_enabled() else ship.global_transform
	global_position = xf * _smooth_offset
	var focus := xf * Vector3(0, 1.5, -2.0)
	look_at(focus, xf.basis.y)
