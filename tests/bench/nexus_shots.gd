extends Node
## Capturas de las bases procedurales del NEXUS (ronda 12, ADR-048): en cada mundo, vista lejana, la entrada, el
## núcleo con el componente y un módulo. Uso: --nexus-shots [--only=mars]. Salida: user://bench/nexus_*.png.

const BODIES := ["mars", "mercury", "venus", "europa", "titan"]

var main: Node
var world: SurfaceWorld
var only := ""
var _i := -1
var _t := 0.0
var _step := 0
var _frames := 0
var _time := 0.0
var _views: Array = []


func _ready() -> void:
	_next_body()


func _next_body() -> void:
	_i += 1
	while _i < BODIES.size() and only != "" and BODIES[_i] != only:
		_i += 1
	if _i >= BODIES.size():
		get_tree().quit(0)
		return
	world = main.start_world(BODIES[_i], 12.0, 31.0, false, false)
	_step = -1
	_t = 0.0


func _process(delta: float) -> void:
	if world == null or not world.surface_ready or world.nexus == null or world.nexus.outpost == null:
		return
	_t += delta
	if _step >= 0 and _t > 2.0:
		_frames += 1
		_time += delta
	if _t < (6.0 if _step < 0 else 3.5):
		return
	var id: String = BODIES[_i]
	if _step < 0:
		_views = _make_views()
	elif _step < _views.size():
		var v: Array = _views[_step]
		print("NEXUS %-8s %-10s %5.1f FPS  llamadas %d" % [id, v[0], _frames / maxf(_time, 0.001),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
		_shot("nexus_%s_%s" % [id, v[0]])
	_step += 1
	if _step >= _views.size():
		_next_body()
		return
	var v2: Array = _views[_step]
	_place(v2[1], v2[2], bool(v2[3]))
	_t = 0.0
	_frames = 0
	_time = 0.0


func _make_views() -> Array:
	var o := world.nexus.outpost
	var out: Vector2 = o.entry["out"]
	var foot: Vector2 = o.entry["foot"]
	var edge: Vector2 = o.entry["edge"]
	var across := Vector2(-out.y, out.x)
	var far := foot + out * 30.0 + across * 22.0
	var near := foot + out * 3.0 + across * 3.0
	var hub: Vector3 = o.core_local
	var m: Dictionary = o.modules[1]
	var mp: Vector2 = m["pos"]
	return [
		["lejos", Vector3(far.x, 0, far.y), Vector3(edge.x, o.floor_y + 2.0, edge.y), false],
		["entrada", Vector3(near.x, 0, near.y), Vector3(edge.x, o.floor_y + 1.5, edge.y), false],
		["nucleo", hub + Vector3(0.6, 0, 5.4), hub + Vector3(0, 1.2, 0), true],
		["modulo", Vector3(mp.x + m["w"] * 0.3, o.floor_y, mp.y + m["d"] * 0.3), Vector3(mp.x - m["w"] * 0.5, o.floor_y + 1.2, mp.y - m["d"] * 0.5), true],
	]


## Coloca al jugador en un punto del marco de la base mirando a `look`. `inside`: sobre el suelo interior.
func _place(p: Vector3, look: Vector3, inside: bool) -> void:
	var nx := world.nexus
	var pl := world.player
	var target := nx._local_to_bf(Vector3(p.x, p.y + 0.1, p.z))
	var dir := target.normalized()
	var lift := target.length() - (world.terrain.radius + world.terrain.height_at_dir(dir)) if inside else 0.05
	pl.place_on_surface(dir, lift)
	var up := pl.global_transform.basis.y
	var la := FloatingOrigin.to_local(nx._local_to_bf(look))
	var d := (la - (pl.global_position + up * 1.7)).normalized()
	var flat := (d - up * d.dot(up)).normalized()
	pl.global_transform.basis = Basis(up.cross(-flat).normalized(), up, -flat).orthonormalized()
	pl.set_look_pitch(asin(clampf(d.dot(up), -1.0, 1.0)))


func _shot(name: String) -> void:
	var dir := ProjectSettings.globalize_path("user://bench")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
