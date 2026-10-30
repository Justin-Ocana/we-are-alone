class_name TerrainPatchJob
extends RefCounted
## Trabajo de generación de un parche del quadtree. Se ejecuta en WorkerThreadPool:
## sólo lee sus campos de entrada y escribe sus campos de salida (sin estado compartido).

# --- Entrada ---
var face: int
var level: int
var ix: int
var iy: int
var segments: int = 16
var radius: float
var seed_value: int
var profile_id: String
var profile: Dictionary = {}     ## perfil ya ajustado al cuerpo (sólo lectura en el hilo)
var tile_m: float = 2.0         ## tamaño de la tesela de la textura de detalle (m)
var build_collision: bool = true
var rock_count: int = 0         ## rocas a dispersar (sólo en el nivel de dispersión)

# --- Salida ---
var center: DVec3               ## centro del parche en el marco BF (m, doble)
var bound_radius: float = 0.0   ## radio de la esfera envolvente alrededor de `center`
var min_height: float = 0.0
var max_height: float = 0.0
var vertices := PackedVector3Array()   ## relativos a `center` (32 bits, pequeños)
var normals := PackedVector3Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
var indices := PackedInt32Array()
var collision_faces := PackedVector3Array()
var rock_transforms: Array[Transform3D] = []  ## relativas a `center`
var cached_mesh: Mesh = null       ## malla ya construida (parche recuperado de la caché; hilo principal)
var elapsed_usec: int = 0
var done: bool = false


func key() -> String:
	return "%d/%d/%d/%d" % [face, level, ix, iy]


func run() -> void:
	var t0 := Time.get_ticks_usec()
	TerrainPatchBuilder.build(self)
	elapsed_usec = Time.get_ticks_usec() - t0
	done = true
