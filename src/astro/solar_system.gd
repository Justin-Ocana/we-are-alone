class_name SolarSystem
extends RefCounted
## Estado del Sistema Solar en el tiempo de juego (ADR-024): posiciones heliocéntricas (eclíptica J2000, m),
## orientación de cada cuerpo, jerarquía padre/hijos y esferas de influencia.
##
## El juego no simula en el marco heliocéntrico: trabaja en el marco fijo (rotante) del cuerpo "ancla"
## (el dominante donde está la nave; ADR-024) y usa este servicio para situar todo lo demás.

const SOI_MIN_RADII := 4.0      ## una luna pequeña es dominante al menos hasta 4 radios de su centro

var bodies := {}                ## id -> BodyDef (sólo los del sistema)
var children := {}              ## id del padre -> [ids]
var time_s := 0.0               ## segundos desde J2000
var time_scale := 1.0
var _pos := {}                  ## caché por instante: id -> DVec3
var _axes := {}                 ## caché: id -> [X, Y, Z] (DVec3 en eclíptica)
var _poles := {}                ## caché por instante: id del padre -> polo ecuatorial (DVec3)
var _cache_t := INF


static func from_catalog(cat: BodyCatalog) -> SolarSystem:
	var s := SolarSystem.new()
	for id in cat.bodies:
		var b: BodyDef = cat.bodies[id]
		if b.in_system():
			s.bodies[id] = b
	for id in s.bodies:
		var p: String = s.bodies[id].parent_id
		if p != "" and s.bodies.has(p):
			if not s.children.has(p):
				s.children[p] = []
			s.children[p].append(id)
	s.time_s = Ephemeris.now_seconds()
	return s


func has_body(id: String) -> bool:
	return bodies.has(id)


func body(id: String) -> BodyDef:
	return bodies.get(id)


func advance(dt: float) -> void:
	time_s += dt * time_scale


func set_time(t: float) -> void:
	time_s = t


func _check_cache() -> void:
	if time_s != _cache_t:
		_cache_t = time_s
		_pos.clear()
		_axes.clear()
		_poles.clear()


## Posición heliocéntrica (eclíptica J2000, m).
func position(id: String) -> DVec3:
	_check_cache()
	if _pos.has(id):
		return _pos[id]
	var p := _position_at(id, time_s)
	_pos[id] = p
	return p


func _position_at(id: String, t: float) -> DVec3:
	var b: BodyDef = bodies.get(id)
	if b == null:
		return DVec3.new()
	var o := b.orbit()
	match str(o.get("model", "fixed")):
		"planet":
			var p := Ephemeris.planet_position(o, t)
			if id == "earth" and bodies.has("moon"):
				# La tabla da el baricentro Tierra-Luna: la Tierra está desplazada frente a la Luna.
				var moon: BodyDef = bodies["moon"]
				var mu := moon.mass_kg() / (moon.mass_kg() + b.mass_kg())
				p = p.sub(_satellite_offset("moon", t).mul(mu))
			return p
		"satellite":
			var parent := b.parent_id
			var parent_pos: DVec3
			if parent == "":
				parent_pos = DVec3.new()
			elif t == time_s:
				parent_pos = position(parent)   # caché: cientos de lunas comparten padre
			else:
				parent_pos = _position_at(parent, t)
			return parent_pos.add(_satellite_offset(id, t))
	return DVec3.new()


func _satellite_offset(id: String, t: float) -> DVec3:
	var b: BodyDef = bodies[id]
	var parent: BodyDef = bodies.get(b.parent_id)
	var pole := DVec3.new(0, 0, 1)
	if parent != null and parent.rotation().get("model", "") == "iau":
		if t == time_s:
			_check_cache()
			if not _poles.has(b.parent_id):
				_poles[b.parent_id] = Ephemeris.pole_equatorial(parent.rotation(), t)
			pole = _poles[b.parent_id]
		else:
			pole = Ephemeris.pole_equatorial(parent.rotation(), t)
	return Ephemeris.satellite_position(b.orbit(), t, pole)


## Velocidad heliocéntrica (m/s), por diferencias centradas.
func velocity(id: String) -> DVec3:
	var h := 30.0
	return _position_at(id, time_s + h).sub(_position_at(id, time_s - h)).mul(0.5 / h)


## Ejes del marco fijo al cuerpo (convención del motor) en la eclíptica.
func axes(id: String) -> Array:
	_check_cache()
	if _axes.has(id):
		return _axes[id]
	var b: BodyDef = bodies.get(id)
	var ax: Array
	if b == null:
		ax = [DVec3.new(1, 0, 0), DVec3.new(0, 0, 1), DVec3.new(0, -1, 0)]
	elif str(b.rotation().get("model", "")) == "iau":
		ax = Ephemeris.iau_axes(b.rotation(), time_s)
	else:
		var rel := position(id).sub(position(b.parent_id)) if b.parent_id != "" else DVec3.new(1, 0, 0)
		var h := 30.0
		var vel := _satellite_offset(id, time_s + h).sub(_satellite_offset(id, time_s - h)).mul(0.5 / h) \
			if b.parent_id != "" and bodies.has(b.parent_id) else DVec3.new(0, 1, 0)
		ax = Ephemeris.synchronous_axes(rel, vel)
	_axes[id] = ax
	return ax


## Posición de `target` en el marco fijo de `anchor` (m, DVec3, convención del motor).
func position_in_frame(target: String, anchor: String) -> DVec3:
	return Ephemeris.to_frame(axes(anchor), position(target).sub(position(anchor)))


## Punto del marco de `a` → marco de `b` (doble precisión).
func convert_point(p: DVec3, a: String, b: String) -> DVec3:
	var p_sys := position(a).add(Ephemeris.from_frame(axes(a), p))
	return Ephemeris.to_frame(axes(b), p_sys.sub(position(b)))


## Rotación que lleva vectores del marco de `a` al de `b` (no incluye traslación ni velocidades orbitales).
func frame_rotation(a: String, b: String) -> Basis:
	var cols: Array[Vector3] = []
	for e: DVec3 in [DVec3.new(1, 0, 0), DVec3.new(0, 1, 0), DVec3.new(0, 0, 1)]:
		cols.append(Ephemeris.to_frame(axes(b), Ephemeris.from_frame(axes(a), e)).to_vector3())
	return Basis(cols[0], cols[1], cols[2]).orthonormalized()


## Posición heliocéntrica de un punto del marco de `anchor`.
func to_system(p: DVec3, anchor: String) -> DVec3:
	return position(anchor).add(Ephemeris.from_frame(axes(anchor), p))


## Dirección y distancia al Sol desde un punto del marco de `anchor`.
func sun_in_frame(anchor: String) -> DVec3:
	return position_in_frame("sun", anchor)


## Radio de la esfera de influencia (Laplace: a·(m/M)^(2/5)), con un mínimo de SOI_MIN_RADII radios.
func soi_radius(id: String) -> float:
	var b: BodyDef = bodies.get(id)
	if b == null or b.parent_id == "" or not bodies.has(b.parent_id):
		return INF
	var parent: BodyDef = bodies[b.parent_id]
	var a := position(id).distance_to(position(b.parent_id))
	var r := a * pow(b.mass_kg() / parent.mass_kg(), 0.4)
	return maxf(r, b.radius_m() * SOI_MIN_RADII)


## Cuerpo dominante para un punto heliocéntrico: el más profundo de la jerarquía cuya esfera lo contiene.
## `current` se usa para la histéresis (hay que salir un 5 % más allá para cambiar).
func dominant_body(p_sys: DVec3, current: String = "") -> String:
	var best := "sun"
	var level: Array = children.get("sun", [])
	while true:
		var found := ""
		var best_ratio := INF
		for id in level:
			var r := soi_radius(id) * (1.05 if id == current else 1.0)
			var d := p_sys.distance_to(position(id))
			if d < r and d / r < best_ratio:
				best_ratio = d / r
				found = id
		if found == "":
			break
		best = found
		level = children.get(found, [])
	return best


## Planeta "local" de un cuerpo (él mismo si es planeta; su padre si es una luna).
func system_planet(id: String) -> String:
	var b: BodyDef = bodies.get(id)
	if b == null or id == "sun":
		return "sun"
	if b.parent_id == "sun" or b.parent_id == "":
		return id
	return b.parent_id
