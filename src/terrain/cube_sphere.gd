class_name CubeSphere
extends RefCounted
## Proyección cubo → esfera ("cubo esferizado"). Ver ADR-004.
##
## Cada cara f tiene normal n, eje u (a) y eje v (b) con a × b = n, de modo que la cuadrícula
## (u hacia a, v hacia b) vista desde fuera está orientada de forma estándar.
## (u, v) ∈ [-1, 1]². Las aristas de caras vecinas producen exactamente los mismos puntos.

const FACE_COUNT := 6

const NORMALS: Array[Vector3] = [
	Vector3(1, 0, 0), Vector3(-1, 0, 0),
	Vector3(0, 1, 0), Vector3(0, -1, 0),
	Vector3(0, 0, 1), Vector3(0, 0, -1),
]
const AXIS_U: Array[Vector3] = [
	Vector3(0, 0, -1), Vector3(0, 0, 1),
	Vector3(1, 0, 0), Vector3(1, 0, 0),
	Vector3(1, 0, 0), Vector3(-1, 0, 0),
]
const AXIS_V: Array[Vector3] = [
	Vector3(0, 1, 0), Vector3(0, 1, 0),
	Vector3(0, 0, -1), Vector3(0, 0, 1),
	Vector3(0, 1, 0), Vector3(0, 1, 0),
]


## Punto unitario de la esfera para la cara `face` y coordenadas (u, v). Doble precisión.
static func face_uv_to_dir(face: int, u: float, v: float) -> DVec3:
	var n := NORMALS[face]
	var a := AXIS_U[face]
	var b := AXIS_V[face]
	# Los ejes son exactos (0/±1): estas sumas no pierden precisión.
	var cx: float = n.x + u * a.x + v * b.x
	var cy: float = n.y + u * a.y + v * b.y
	var cz: float = n.z + u * a.z + v * b.z
	return cube_to_sphere(cx, cy, cz)


static func cube_to_sphere(x: float, y: float, z: float) -> DVec3:
	var x2 := x * x
	var y2 := y * y
	var z2 := z * z
	var sx := x * sqrt(maxf(0.0, 1.0 - y2 * 0.5 - z2 * 0.5 + y2 * z2 / 3.0))
	var sy := y * sqrt(maxf(0.0, 1.0 - z2 * 0.5 - x2 * 0.5 + z2 * x2 / 3.0))
	var sz := z * sqrt(maxf(0.0, 1.0 - x2 * 0.5 - y2 * 0.5 + x2 * y2 / 3.0))
	return DVec3.new(sx, sy, sz)


## Longitud aproximada (m) de la arista de una cara del cubo proyectada sobre la esfera.
static func face_edge_length(radius_m: float) -> float:
	return radius_m * PI * 0.5


## Nivel máximo del quadtree para que la arista del parche más fino sea ≤ target_edge_m.
static func max_level_for(radius_m: float, target_edge_m: float) -> int:
	return maxi(0, ceili(log(face_edge_length(radius_m) / target_edge_m) / log(2.0)))


## Arista aproximada (m) de un parche del nivel dado.
static func patch_edge_length(radius_m: float, level: int) -> float:
	return face_edge_length(radius_m) / float(1 << level)


## Latitud/longitud (grados) → dirección unitaria BF (+Y norte, lon 0 en +Z, lon 90 en +X).
static func latlon_to_dir(lat_deg: float, lon_deg: float) -> DVec3:
	var lat := deg_to_rad(lat_deg)
	var lon := deg_to_rad(lon_deg)
	return DVec3.new(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))


static func dir_to_latlon(d: DVec3) -> Vector2:
	var n := d.normalized()
	return Vector2(rad_to_deg(asin(clampf(n.y, -1.0, 1.0))), rad_to_deg(atan2(n.x, n.z)))
