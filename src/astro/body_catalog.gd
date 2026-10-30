class_name BodyCatalog
extends RefCounted
## Catálogo de cuerpos cargado desde data/bodies/*.json.
## NOTA de exportación: añadir "data/*" al filtro de recursos no-recurso en el preset de exportación.

const DEFAULT_DIR := "res://data/bodies"

var bodies: Dictionary = {}  # id -> BodyDef
var errors: PackedStringArray = []


static func load_dir(dir_path: String = DEFAULT_DIR) -> BodyCatalog:
	var cat := BodyCatalog.new()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		cat.errors.append("No se pudo abrir %s" % dir_path)
		return cat
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var path := dir_path.path_join(file)
		# Colecciones (p. ej. moons_saturn.json): {"bodies": [...]} con muchos cuerpos menores.
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and parsed.has("bodies"):
			for d in parsed["bodies"]:
				cat._add(BodyDef.from_dict(d), file)
			continue
		cat._add(BodyDef.load_file(path), file)
	return cat


func _add(b: BodyDef, file: String) -> void:
	if not b.is_valid():
		for e in b.errors:
			errors.append("%s: %s" % [file, e])
		return
	bodies[b.id] = b


func get_body(id: String) -> BodyDef:
	return bodies.get(id)


func ids() -> Array:
	var a := bodies.keys()
	a.sort()
	return a
