class_name TerrainQuadNode
extends RefCounted
## Nodo del quadtree de una cara del cubo. Cada nodo tiene su propia malla (las mallas de los
## ancestros se conservan para poder fusionar sin esperar); sólo se dibujan las hojas efectivas.

enum State { EMPTY, PENDING, READY }

var face: int
var level: int
var ix: int
var iy: int
var edge_m: float
var state: int = State.EMPTY
var children: Array = []  # 0 o 4 TerrainQuadNode

## Centro aproximado (antes de generar) o exacto (tras generar), marco BF.
var center: DVec3
var bound_radius: float

var job: TerrainPatchJob
var task_id: int = -1
var mesh_instance: MeshInstance3D
var collider: StaticBody3D
var collision_faces := PackedVector3Array()
var drawn: bool = false
var draw_epoch: int = -1
var rock_transforms: Array[Transform3D] = []
var scatter: Node3D             ## rocas instanciadas (sólo en el nivel de dispersión)
var released: bool = false  ## eliminado del árbol; sus tareas pendientes se descartan
## Centro en 32 bits (resolución ≈0,1–0,5 m a escala planetaria): sólo para decisiones de LOD y
## prioridad, que así usan operaciones nativas en lugar de DVec3 (mucho más rápido en GDScript).
var cf: Vector3
var priority := 0.0


func _init(p_face: int, p_level: int, p_ix: int, p_iy: int, radius: float) -> void:
	face = p_face
	level = p_level
	ix = p_ix
	iy = p_iy
	edge_m = CubeSphere.patch_edge_length(radius, level)
	var size := 2.0 / float(1 << level)
	var u := -1.0 + (float(ix) + 0.5) * size
	var v := -1.0 + (float(iy) + 0.5) * size
	center = CubeSphere.face_uv_to_dir(face, u, v).mul(radius)
	cf = center.to_vector3()
	bound_radius = edge_m * 0.75


func is_leaf() -> bool:
	return children.is_empty()


func distance_to(p: DVec3) -> float:
	return maxf(0.0, center.distance_to(p) - bound_radius)
