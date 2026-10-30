class_name MeshBatcher
extends RefCounted
## Agrupa geometría estática en pocas mallas (una por lote y material) para reducir llamadas de
## dibujo (ADR-013). Los lotes se separan por zona para respetar el límite de 8 luces omnidireccionales
## por malla del renderizador Compatibility.

class Batch:
	extends RefCounted
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var batch := ""
	var mat := ""


var _batches := {}  # "lote|material" -> Batch
var meshes_by_batch := {}   ## lote -> [MeshInstance3D] (para ocultar salas no visibles; ronda 9)


func _batch(batch: String, mat: String) -> Batch:
	var k := batch + "|" + mat
	if not _batches.has(k):
		var b := Batch.new()
		b.batch = batch
		b.mat = mat
		_batches[k] = b
	return _batches[k]


## Caja de tamaño `size` centrada en el origen de `xf`.
func box(batch: String, mat: String, xf: Transform3D, size: Vector3) -> void:
	var b := _batch(batch, mat)
	var h := size * 0.5
	var faces := [
		[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
		[Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
	]
	var nb := xf.basis.inverse().transposed()
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c := n * h
		var hu := u * h
		var hv := v * h
		var base := b.verts.size()
		var corners := [c - hu - hv, c + hu - hv, c + hu + hv, c - hu + hv]
		var wn := (nb * n).normalized()
		for p in corners:
			b.verts.append(xf * p)
			b.normals.append(wn)
		# Orientación horaria vista desde fuera (Godot): comprobada con la normal.
		var p0: Vector3 = corners[0]
		var p1: Vector3 = corners[1]
		var p2: Vector3 = corners[2]
		if (p2 - p0).cross(p1 - p0).dot(n) > 0.0:
			b.indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
		else:
			b.indices.append_array([base, base + 2, base + 1, base, base + 3, base + 2])


## Cualquier PrimitiveMesh (cilindros, esferas, toros…) transformado.
func primitive(batch: String, mat: String, mesh: PrimitiveMesh, xf: Transform3D) -> void:
	var b := _batch(batch, mat)
	var arrays := mesh.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var base := b.verts.size()
	var nb := xf.basis.inverse().transposed()
	for i in verts.size():
		b.verts.append(xf * verts[i])
		b.normals.append((nb * norms[i]).normalized())
	for i in idx:
		b.indices.append(base + i)


## Triángulos ya calculados (casco liso): vértices, normales e índices en el espacio de la nave.
func triangles(batch: String, mat: String, verts: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array) -> void:
	var b := _batch(batch, mat)
	var base := b.verts.size()
	b.verts.append_array(verts)
	b.normals.append_array(normals)
	for i in indices:
		b.indices.append(base + i)


## Crea los MeshInstance3D. `materials`: nombre → Material; `layer_for`: Callable(lote) → capa de render.
func build(parent: Node3D, materials: Dictionary, layer_for: Callable) -> int:
	var count := 0
	for k in _batches:
		var b: Batch = _batches[k]
		if b.verts.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = b.verts
		arrays[Mesh.ARRAY_NORMAL] = b.normals
		arrays[Mesh.ARRAY_INDEX] = b.indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.name = k.replace("|", "_")
		mi.mesh = mesh
		mi.material_override = materials.get(b.mat)
		mi.layers = Layers.bit(layer_for.call(b.batch))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if b.batch.begins_with("int:"):
			mi.visibility_range_end = 150.0   # ronda 9: el interior no cuenta lejos de la nave
		parent.add_child(mi)
		if not meshes_by_batch.has(b.batch):
			meshes_by_batch[b.batch] = []
		meshes_by_batch[b.batch].append(mi)
		count += 1
	return count
