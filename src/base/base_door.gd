class_name BaseDoor
extends Node3D
## Puerta de la base LF-01 (ADR-043): dos hojas que se deslizan hacia los lados, marco con luz de estado
## (verde = libre, ámbar = sin energía, rojo = restringida u obstruida) y colisión mientras está cerrada.
## Las "open" se abren solas con alguien cerca; el resto sólo se abre si el prólogo o la energía la desbloquean.
## La geometría vive en el marco LOCAL de la base (este nodo es hijo de LunarBase).

signal moved(open: bool)

const OPEN_SPEED := 1.6        ## fracción por segundo
const SENSE_RADIUS := 2.6      ## m
const LOCKED_STATES := ["locked_power", "locked_auth", "blocked", "locked_script"]

var id := ""
var state := "open"
var width := 1.6
var height := 2.4
var axis := "z"
var open := 0.0                ## 0 cerrada · 1 abierta
var force_open := false        ## la escotilla exterior y los guiones la abren aunque no haya nadie
var force_closed := false      ## la esclusa cierra la interior durante el ciclo
var _target := 0.0
var _leaves: Array[MeshInstance3D] = []
var _shape: CollisionShape3D
var _lamp_mat: StandardMaterial3D
var _was_open := false


func setup(p_id: String, def: Array, panel_mat: Material, frame_mat: Material, body: StaticBody3D) -> void:
	id = p_id
	axis = def[3]
	width = def[4]
	height = def[5]
	state = def[6]
	var c: Vector2 = def[2]
	position = Vector3(c.x, 0.0, c.y)
	# En el plano x = cte la puerta abarca el eje z: se gira 90° y la geometría se describe siempre en "x".
	rotation.y = PI * 0.5 if axis == "x" else 0.0
	var depth := BaseLayout.WALL_T * 2.0 + 0.1
	for side in [-1.0, 1.0]:
		var leaf := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(width * 0.5, height, 0.12)
		leaf.mesh = bm
		leaf.material_override = panel_mat
		leaf.layers = Layers.bit(Layers.SHIP_INT)
		leaf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		leaf.position = Vector3(side * width * 0.25, height * 0.5, 0.0)
		add_child(leaf)
		_leaves.append(leaf)
	# Marco (dintel y jambas) y piloto de estado sobre el dintel, a los dos lados.
	for side in [-1.0, 1.0]:
		var jamb := MeshInstance3D.new()
		var jm := BoxMesh.new()
		jm.size = Vector3(0.16, height + 0.2, depth)
		jamb.mesh = jm
		jamb.material_override = frame_mat
		jamb.layers = Layers.bit(Layers.SHIP_INT)
		jamb.position = Vector3(side * (width * 0.5 + 0.08), (height + 0.2) * 0.5, 0.0)
		add_child(jamb)
	var lintel := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(width + 0.32, 0.2, depth)
	lintel.mesh = lm
	lintel.material_override = frame_mat
	lintel.layers = Layers.bit(Layers.SHIP_INT)
	lintel.position = Vector3(0.0, height + 0.1, 0.0)
	add_child(lintel)
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for side in [-1.0, 1.0]:
		var lamp := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.5, 0.06, 0.02)
		lamp.mesh = pm
		lamp.material_override = _lamp_mat
		lamp.layers = Layers.bit(Layers.SHIP_INT)
		lamp.position = Vector3(0.0, height + 0.1, side * (depth * 0.5 + 0.012))
		add_child(lamp)
	# Colisión de la puerta cerrada (en el cuerpo estático de la base, con la transformación de la puerta).
	_shape = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(width, height, 0.3)
	_shape.shape = bs
	body.add_child(_shape)
	_shape.transform = transform * Transform3D(Basis(), Vector3(0.0, height * 0.5, 0.0))
	_update_lamp()


func is_locked() -> bool:
	return state in LOCKED_STATES


func set_state(s: String) -> void:
	state = s
	_update_lamp()


## Distancia (m) de un punto local de la base al centro del vano.
func distance_to_local(p: Vector3) -> float:
	return Vector2(p.x - position.x, p.z - position.z).length()


func update(dt: float, people_local: Array) -> void:
	var want := false
	if force_open:
		want = true
	elif not force_closed and state == "open":
		for p in people_local:
			if distance_to_local(p) < SENSE_RADIUS and absf(p.y) < height + 1.0:
				want = true
				break
	_target = 1.0 if want else 0.0
	if not is_equal_approx(open, _target):
		open = move_toward(open, _target, OPEN_SPEED * dt)
		for i in _leaves.size():
			var side := -1.0 if i == 0 else 1.0
			_leaves[i].position.x = side * width * (0.25 + 0.5 * open)
			_leaves[i].scale.x = 1.0 - 0.6 * open   # la hoja se recoge dentro del tabique
	var is_open := open > 0.85
	_shape.disabled = is_open
	if is_open != _was_open:
		_was_open = is_open
		moved.emit(is_open)


func _update_lamp() -> void:
	if _lamp_mat == null:
		return
	var c := Color(0.25, 1.0, 0.45)
	match state:
		"locked_power":
			c = Color(1.0, 0.55, 0.1) * 0.6
		"locked_auth", "blocked":
			c = Color(1.0, 0.12, 0.08)
		"locked_script", "cycle":
			c = Color(1.0, 0.55, 0.1)
	_lamp_mat.albedo_color = c * 1.6
