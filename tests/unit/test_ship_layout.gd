extends TestCase
## Plano de la nave, escala humana, esclusa y traslado de pasajeros (ADR-011, ADR-013).


func test_eight_required_areas_exist() -> void:
	var letters := {}
	for id in ShipLayout.ROOMS:
		letters[ShipLayout.ROOMS[id][1]] = id
	for l in ["A", "B", "C", "D", "E", "F", "G", "H"]:
		assert_true(letters.has(l), "existe el área %s" % l)


func test_all_rooms_reachable_from_airlock() -> void:
	var g := ShipLayout.adjacency()
	var seen := {"exterior": true}
	var queue := ["exterior"]
	while not queue.is_empty():
		var r: String = queue.pop_front()
		for n in g.get(r, []):
			if not seen.has(n):
				seen[n] = true
				queue.append(n)
	for id in ShipLayout.ROOMS:
		assert_true(seen.has(id), "'%s' accesible desde el exterior por la esclusa" % id)


func test_human_scale() -> void:
	assert_true(ShipLayout.DECK_HEIGHT >= Units.ASTRONAUT_HEIGHT_M + 0.5, "techo de %.2f m para 1,85 m" % ShipLayout.DECK_HEIGHT)
	assert_true(ShipLayout.DOOR_HEIGHT >= 2.0, "puertas de %.2f m de alto" % ShipLayout.DOOR_HEIGHT)
	assert_true(ShipLayout.DOOR_WIDTH >= 0.9, "puertas de %.2f m de ancho" % ShipLayout.DOOR_WIDTH)
	assert_true(ShipLayout.CORRIDOR_HALF * 2.0 >= 1.2, "pasillo de %.2f m" % (ShipLayout.CORRIDOR_HALF * 2.0))
	for id in ShipLayout.ROOMS:
		var r: Array = ShipLayout.ROOMS[id]
		var size: Vector2 = (r[3] as Vector2) - (r[2] as Vector2)
		assert_true(minf(size.x, size.y) >= 1.6, "'%s' de %.1f × %.1f m" % [id, size.x, size.y])


func test_rooms_do_not_overlap() -> void:
	var ids := ShipLayout.ROOMS.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: Array = ShipLayout.ROOMS[ids[i]]
			var b: Array = ShipLayout.ROOMS[ids[j]]
			var ra := Rect2(a[2], (a[3] as Vector2) - (a[2] as Vector2))
			var rb := Rect2(b[2], (b[3] as Vector2) - (b[2] as Vector2))
			var inter := ra.intersection(rb)
			assert_true(inter.get_area() < 1e-3, "'%s' y '%s' no se solapan" % [ids[i], ids[j]])


func test_aboard_volume() -> void:
	assert_true(ShipLayout.is_aboard(Vector3(0, 0.9, 0)), "pasillo a bordo")
	assert_true(ShipLayout.is_aboard(Vector3(0, 0.9, -22)), "puente a bordo")
	assert_true(not ShipLayout.is_aboard(Vector3(11, 0.9, -3)), "rampa fuera")
	assert_true(not ShipLayout.is_aboard(Vector3(0, 4.0, 0)), "techo exterior fuera")


func _airlock() -> ShipAirlock:
	var a := ShipAirlock.new()
	a.inner = ShipDoor.new()
	a.inner.center = Vector3(1.2, 0, -3)
	a.inner.automatic = false
	a.outer = ShipDoor.new()
	a.outer.center = Vector3(9.0, 0, -3)
	a.outer.automatic = false
	return a


func _step(a: ShipAirlock, people: Array, seconds: float) -> bool:
	var both := false
	for i in int(seconds * 60.0):
		a.update(1.0 / 60.0, people)
		var pts := []
		for p in people:
			pts.append(p["p"])
		a.inner.update(1.0 / 60.0, pts)
		a.outer.update(1.0 / 60.0, pts)
		if a.inner.open > 0.0 and a.outer.open > 0.0:
			both = true
	return both


func test_airlock_cycle_from_outside() -> void:
	var a := _airlock()
	var person := {"id": 1, "p": Vector3(11.0, 0.9, -3)}
	var both := _step(a, [person], 6.0)
	assert_true(a.outer.is_open(), "se abre la exterior para quien llega por la rampa")
	person["p"] = Vector3(8.0, 0.9, -3)   # entra
	both = _step(a, [person], 1.0) or both
	person["p"] = Vector3(3.0, 0.9, -3)
	both = _step(a, [person], 8.0) or both
	assert_true(a.inner.is_open() and a.outer.is_closed(), "tras el ciclo se abre la interior")
	assert_true(not both, "nunca ambas puertas abiertas a la vez")


func test_door_never_closes_on_someone() -> void:
	var a := _airlock()
	a.phase = ShipAirlock.Phase.OUTER_OPEN
	a.outer.open = 1.0
	a.outer.target = 1.0
	var in_doorway := {"id": 2, "p": Vector3(9.0, 0.9, -3)}
	a.outer.target = 0.0
	a.outer.update(0.5, [in_doorway["p"]])
	assert_near(a.outer.open, 1.0, 1e-6, "la puerta no se cierra con alguien en el umbral")


func test_carry_preserves_relative_pose() -> void:
	# La variación de transform de la nave aplicada al pasajero conserva su posición relativa.
	var old_ship := Transform3D(Basis(Vector3.UP, 0.3), Vector3(100, 5, -20))
	var new_ship := Transform3D(Basis(Vector3.UP, 0.42) * Basis(Vector3.RIGHT, 0.05), Vector3(103.7, 5.2, -24.1))
	var passenger := old_ship * Transform3D(Basis(Vector3.UP, 1.0), Vector3(0.5, 0, -8.0))
	var delta := new_ship * old_ship.affine_inverse()
	var moved := delta * passenger
	var rel_before := old_ship.affine_inverse() * passenger
	var rel_after := new_ship.affine_inverse() * moved
	assert_true(rel_before.origin.is_equal_approx(rel_after.origin), "posición relativa conservada")
	assert_true(rel_before.basis.is_equal_approx(rel_after.basis), "orientación relativa conservada")


func test_hull_encloses_interior() -> void:
	# El casco liso debe contener todo el volumen presurizado (esquinas de suelo y techo, con margen).
	for z: float in [-26.0, -24.0, -21.0, -18.0, -10.0, 0.0, 10.0, 20.0, 22.25]:
		var hw := ShipLayout.COCKPIT_HALF if z < ShipLayout.FRONT_Z else ShipLayout.HALF_WIDTH
		for y: float in [-0.4, ShipLayout.DECK_HEIGHT + 0.3]:
			var sx := ShipHull.shell_x(z, y)
			assert_true(sx > hw + 0.25, "casco en z=%.1f, y=%.1f: |x| %.2f > %.2f" % [z, y, sx, hw + 0.25])


func test_gear_drop_matches_params() -> void:
	var p := ShipParams.load_file("res://data/ships/explorer.json")
	assert_near(p.gear_drop, ShipLayout.GEAR_DROP, 1e-6, "altura del tren coherente entre el plano y los datos")


func test_seats_inside_rooms() -> void:
	for id in ShipLayout.SEATS:
		var p: Vector3 = ShipLayout.SEATS[id][0]
		assert_true(ShipLayout.room_at(p + Vector3(0, 1, 0)) != "", "asiento '%s' dentro de una sala" % id)
