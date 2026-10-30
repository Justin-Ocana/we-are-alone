extends Node
## Recorrido visual del Sistema Solar (Hito 3): capturas desde la Luna (Tierra destruida, Sol) y desde
## observadores virtuales junto a cada planeta. Uso: --system-tour. Salida: user://bench/system_*.png.

var main: Node
var world: SurfaceWorld
var cam: Camera3D
var _i := -1
var _t := 0.0
var _out := ""
var only := ""   ## --only=nombre: sólo esa captura

## [nombre, cuerpo objetivo, distancia en radios (0 = desde el jugador en la Luna), elevación (rad), fov]
const SHOTS := [
	["luna_tierra", "earth", 0.0, 0.0, 30.0],
	["luna_sol", "sun", 0.0, 0.0, 60.0],
	["tierra_destruida", "earth", 4.0, 0.25, 60.0],
	["jupiter", "jupiter", 3.2, 0.12, 60.0],
	["jupiter_mancha", "jupiter", 1.6, -0.35, 50.0],
	["saturno", "saturn", 5.5, 0.32, 60.0],
	["saturno_anillos_cerca", "saturn", 2.6, 0.08, 70.0],
	["urano", "uranus", 3.5, 0.2, 60.0],
	["neptuno", "neptune", 3.5, 0.15, 60.0],
	["marte", "mars", 3.0, 0.2, 60.0],
	["venus", "venus", 3.0, 0.1, 60.0],
	["mercurio", "mercury", 3.0, 0.1, 60.0],
	["io", "io", 3.0, 0.2, 60.0],
	["titan", "titan", 3.0, 0.1, 60.0],
	["pluton", "pluto", 3.0, 0.2, 60.0],
	["sol_cerca", "sun", 6.0, 0.0, 60.0],
]


func _ready() -> void:
	_out = ProjectSettings.globalize_path("user://bench")
	DirAccess.make_dir_recursive_absolute(_out)
	world = main.start_world("moon", main.SPAWN_LAT, main.SPAWN_LON, false, false)
	GameSettings.ui_hidden = true
	GameSettings.show_hud = false
	cam = Camera3D.new()
	cam.top_level = true
	cam.far = 1.0e6
	add_child(cam)


func _process(delta: float) -> void:
	if world == null or not world.surface_ready:
		return
	if _i < 0:
		_start(_first())
		return
	_t += delta
	if _t > 1.5:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_out.path_join("system_%s.png" % SHOTS[_i][0]))
		print("SISTEMA: captura %s" % SHOTS[_i][0])
		if _i + 1 >= SHOTS.size() or only != "":
			get_tree().quit(0)
			return
		_start(_i + 1)


func _first() -> int:
	for k in SHOTS.size():
		if SHOTS[k][0] == only:
			return k
	return 0


func _start(i: int) -> void:
	_i = i
	_t = 0.0
	var shot: Array = SHOTS[i]
	var sys := world.system
	var anchor := world.body.id
	var target: String = shot[1]
	var radii: float = shot[2]
	world.view.override_camera = cam
	world.player.helmet_enabled = false
	world.player.helmet.visible = false
	cam.fov = shot[4]
	var ax: Array = sys.axes(anchor)
	if radii <= 0.0:
		world.env.observer_sys_override = null
		world.terrain.visible = true
		var pl := world.player
		cam.global_position = pl.global_position + pl.global_transform.basis.y * 1.7
		var to := Ephemeris.to_frame(ax, sys.position(target).sub(sys.position(anchor))).to_vector3().normalized()
		cam.look_at(cam.global_position + to, pl.global_transform.basis.y)
		return
	# Observador virtual a `radii` radios del objetivo, del lado iluminado y algo elevado sobre su ecuador.
	var b: BodyDef = sys.body(target)
	var tpos := sys.position(target)
	var to_sun := sys.position("sun").sub(tpos).normalized()
	var pole: DVec3 = sys.axes(target)[1]
	if target == "sun":
		to_sun = sys.position(anchor).sub(tpos).normalized()
	var side := to_sun.cross(pole).normalized()
	var dir := to_sun.mul(cos(0.6)).add(side.mul(sin(0.6))).normalized()
	dir = dir.mul(cos(shot[3])).add(pole.mul(sin(shot[3]))).normalized()
	var r := b.radius_m() * (float(b.surface().get("expansion", 1.0)) if b.surface_type() == "shattered" else 1.0)
	var obs := tpos.add(dir.mul(r * radii))
	world.env.observer_sys_override = obs
	world.terrain.visible = false
	cam.global_position = world.player.global_position + Vector3(0, 2, 0)
	var look := Ephemeris.to_frame(ax, tpos.sub(obs)).to_vector3().normalized()
	var up_hint := Ephemeris.to_frame(ax, pole).to_vector3()
	if absf(look.dot(up_hint)) > 0.98:
		up_hint = Vector3.UP
	cam.look_at(cam.global_position + look, up_hint)
