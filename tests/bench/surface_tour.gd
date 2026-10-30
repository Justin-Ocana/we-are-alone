extends Node
## Recorrido por las superficies del Sistema Solar (Hito 3): cambia el cuerpo dominante, coloca al astronauta
## con el Sol a ~40° y captura el paisaje. Uso: --surface-tour [--only=id]. Salida: user://bench/surface_*.png.

var main: Node
var world: SurfaceWorld
var cam: Camera3D
var only := ""
var _i := -1
var _t := 0.0
var _waiting := false
var _out := ""
const BODIES := ["mercury", "venus", "mars", "phobos", "io", "europa", "ganymede", "callisto", "titan", "enceladus",
	"iapetus", "miranda", "triton", "pluto", "charon", "moon"]


func _ready() -> void:
	_out = ProjectSettings.globalize_path("user://bench")
	DirAccess.make_dir_recursive_absolute(_out)
	world = main.start_world("moon", main.SPAWN_LAT, main.SPAWN_LON, false, false)
	GameSettings.ui_hidden = true
	GameSettings.show_hud = false
	cam = Camera3D.new()
	cam.top_level = true
	cam.fov = 70.0
	add_child(cam)


func _process(delta: float) -> void:
	if world == null or not world.surface_ready and _i < 0:
		return
	if _i < 0:
		_next()
		return
	if _waiting:
		if world.surface_ready:
			_waiting = false
			_t = 0.0
		return
	_t += delta
	_aim()
	if _t > 1.5:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_out.path_join("surface_%s.png" % BODIES[_i]))
		print("SUPERFICIE: %s (alt %.1f m, g %.2f)" % [BODIES[_i], world.player.altitude_m, world.player.gravity_mps2])
		_next()


func _next() -> void:
	_i += 1
	if only != "":
		while _i < BODIES.size() and BODIES[_i] != only:
			_i += 1
	if _i >= BODIES.size() or (only != "" and _i > 0 and BODIES[_i - 1] == only):
		get_tree().quit(0)
		return
	var id: String = BODIES[_i]
	if world.body.id != id:
		world.set_anchor(id)
	# Sol a ~40° sobre el horizonte.
	var sun := DVec3.from_vector3(world.env.sun_direction_bf())
	var side := sun.cross(DVec3.new(0, 1, 0))
	if side.length_squared() < 1e-6:
		side = DVec3.new(1, 0, 0)
	var dir := sun.mul(cos(deg_to_rad(50.0))).add(side.normalized().mul(sin(deg_to_rad(50.0)))).normalized()
	world.player.place_on_surface(dir)
	world.wait_for_surface()
	world.player.helmet_enabled = false
	world.player.helmet.visible = false
	world.view.override_camera = cam
	_waiting = true


func _aim() -> void:
	var pl := world.player
	var up := pl.global_transform.basis.y
	cam.global_position = pl.global_position + up * 1.8
	var sun := world.env.sun_direction_bf()
	var away := -(sun - up * sun.dot(up))
	if away.length_squared() < 1e-6:
		away = -pl.global_transform.basis.z
	away = away.normalized()
	cam.look_at(cam.global_position + away - up * 0.12, up)
