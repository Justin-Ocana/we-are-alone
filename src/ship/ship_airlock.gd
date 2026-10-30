class_name ShipAirlock
extends RefCounted
## Esclusa con interbloqueo (ADR-013): las puertas interior y exterior nunca están abiertas a la vez.
## Ciclo automático de `CYCLE_S` segundos al pasar de un lado a otro, con indicadores de estado.
##
## IMPORTANTE: es una transición sencilla y fiable; NO simula presión, aire ni despresurización real.
## El estado se expresa con identificadores de astronauta (instance_id), apto para varios jugadores.

enum Phase { SEALED, INNER_OPEN, OUTER_OPEN, CYCLING_TO_INNER, CYCLING_TO_OUTER }

const CYCLE_S := 2.5
const OUTER_SENSE := 3.2     ## m: distancia a la puerta exterior que la solicita desde fuera
const INNER_SENSE := 1.7

var inner: ShipDoor
var outer: ShipDoor
var phase := Phase.SEALED
var cycle_t := 0.0
var _entered_from := {}      ## instance_id -> "dentro" / "fuera"
var _last_zone := {}         ## instance_id -> "dentro" / "esclusa" / "fuera"


func phase_name() -> String:
	match phase:
		Phase.SEALED:
			return "sellada"
		Phase.INNER_OPEN:
			return "puerta interior abierta"
		Phase.OUTER_OPEN:
			return "puerta exterior abierta"
		Phase.CYCLING_TO_INNER:
			return "ciclando hacia el interior"
		Phase.CYCLING_TO_OUTER:
			return "ciclando hacia el exterior"
	return ""


## `people` = [{id: int, p: Vector3 (espacio de la nave)}]
func update(dt: float, people: Array) -> void:
	var in_lock := []
	var want_inner := false
	var want_outer := false
	for person in people:
		var id: int = person["id"]
		var p: Vector3 = person["p"]
		var zone := _zone(p)
		var last: String = _last_zone.get(id, zone)
		if zone == "esclusa" and last != "esclusa":
			_entered_from[id] = last
		_last_zone[id] = zone
		if zone == "esclusa":
			in_lock.append(id)
			if _entered_from.get(id, "dentro") == "fuera":
				want_inner = true
			else:
				want_outer = true
		elif zone == "dentro" and Vector2(p.x - inner.center.x, p.z - inner.center.z).length() < INNER_SENSE:
			want_inner = true
		elif zone == "fuera" and Vector2(p.x - outer.center.x, p.z - outer.center.z).length() < OUTER_SENSE:
			want_outer = true
	# Si dentro de la esclusa ya se ha llegado al lado deseado, se deja la puerta abierta.
	var target := ""
	if want_outer and not want_inner:
		target = "outer"
	elif want_inner and not want_outer:
		target = "inner"
	elif want_inner and want_outer:
		target = "inner" if phase == Phase.INNER_OPEN else ("outer" if phase == Phase.OUTER_OPEN else "inner")

	match phase:
		Phase.SEALED:
			if target == "inner":
				_start_cycle(Phase.CYCLING_TO_INNER)
			elif target == "outer":
				_start_cycle(Phase.CYCLING_TO_OUTER)
		Phase.INNER_OPEN:
			inner.target = 1.0
			outer.target = 0.0
			if target == "outer" or (target == "" and in_lock.is_empty()):
				inner.target = 0.0
				if inner.is_closed():
					if target == "outer":
						_start_cycle(Phase.CYCLING_TO_OUTER)
					else:
						phase = Phase.SEALED
		Phase.OUTER_OPEN:
			outer.target = 1.0
			inner.target = 0.0
			if target == "inner" or (target == "" and in_lock.is_empty()):
				outer.target = 0.0
				if outer.is_closed():
					if target == "inner":
						_start_cycle(Phase.CYCLING_TO_INNER)
					else:
						phase = Phase.SEALED
		Phase.CYCLING_TO_INNER, Phase.CYCLING_TO_OUTER:
			inner.target = 0.0
			outer.target = 0.0
			if inner.is_closed() and outer.is_closed():
				cycle_t += dt
				if cycle_t >= CYCLE_S:
					phase = Phase.INNER_OPEN if phase == Phase.CYCLING_TO_INNER else Phase.OUTER_OPEN


func _start_cycle(p: Phase) -> void:
	phase = p
	cycle_t = 0.0
	if inner != null and inner.mesh != null and inner.mesh.get_parent() is Node3D:
		GameAudio.play_at("airlock_cycle", inner.mesh.get_parent(), Vector3(5.0, 1.2, -3.0), -2.0, 30.0)


func _zone(p: Vector3) -> String:
	if ShipLayout.room_contains("esclusa", p, -0.05):
		return "esclusa"
	# El umbral de la puerta exterior (dentro del grosor del casco) cuenta como "fuera":
	# quien llega por la rampa entra en la esclusa desde el exterior.
	if p.x > outer.center.x - 0.06 and absf(p.z - outer.center.z) < 1.5:
		return "fuera"
	if ShipLayout.is_aboard(p):
		return "dentro"
	return "fuera"


## Color de los indicadores: verde = abierta hacia ese lado, ámbar = ciclando, rojo = cerrada.
func indicator_color(side: String) -> Color:
	if phase == Phase.CYCLING_TO_INNER or phase == Phase.CYCLING_TO_OUTER:
		return Color(1.0, 0.6, 0.1)
	if (side == "inner" and phase == Phase.INNER_OPEN) or (side == "outer" and phase == Phase.OUTER_OPEN):
		return Color(0.2, 1.0, 0.4)
	return Color(1.0, 0.15, 0.1)
