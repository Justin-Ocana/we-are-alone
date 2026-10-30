class_name DVec3
extends RefCounted
## Vector 3D de doble precisión.
##
## En las compilaciones oficiales de Godot, Vector3 es de 32 bits (ulp ≈ 0,5 m a 6.000 km).
## El tipo `float` de GDScript es de 64 bits, así que DVec3 almacena tres floats y se usa
## para toda posición en marcos astronómicos o planetarios (ver ADR-003).
## Las operaciones devuelven instancias nuevas (semántica de valor).

var x: float
var y: float
var z: float


func _init(px: float = 0.0, py: float = 0.0, pz: float = 0.0) -> void:
	x = px
	y = py
	z = pz


static func from_vector3(v: Vector3) -> DVec3:
	return DVec3.new(v.x, v.y, v.z)


func to_vector3() -> Vector3:
	return Vector3(x, y, z)


func copy() -> DVec3:
	return DVec3.new(x, y, z)


func add(o: DVec3) -> DVec3:
	return DVec3.new(x + o.x, y + o.y, z + o.z)


func sub(o: DVec3) -> DVec3:
	return DVec3.new(x - o.x, y - o.y, z - o.z)


func add_vector3(v: Vector3) -> DVec3:
	return DVec3.new(x + v.x, y + v.y, z + v.z)


func mul(s: float) -> DVec3:
	return DVec3.new(x * s, y * s, z * s)


func dot(o: DVec3) -> float:
	return x * o.x + y * o.y + z * o.z


func cross(o: DVec3) -> DVec3:
	return DVec3.new(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)


func length_squared() -> float:
	return x * x + y * y + z * z


func length() -> float:
	return sqrt(x * x + y * y + z * z)


func normalized() -> DVec3:
	var l := length()
	if l == 0.0:
		return DVec3.new()
	return DVec3.new(x / l, y / l, z / l)


func distance_to(o: DVec3) -> float:
	var dx := x - o.x
	var dy := y - o.y
	var dz := z - o.z
	return sqrt(dx * dx + dy * dy + dz * dz)


func is_equal_approx_tol(o: DVec3, tol: float) -> bool:
	return absf(x - o.x) <= tol and absf(y - o.y) <= tol and absf(z - o.z) <= tol


func to_array() -> Array:
	return [x, y, z]


static func from_array(a: Array) -> DVec3:
	if a.size() != 3:
		return DVec3.new()
	return DVec3.new(float(a[0]), float(a[1]), float(a[2]))


func _to_string() -> String:
	return "(%.3f, %.3f, %.3f)" % [x, y, z]
