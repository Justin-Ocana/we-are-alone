extends Node
## Capturas del aspecto del juego (ronda 8, ADR-039/040): cielo con la Vía Láctea, la Tierra rota con sus grietas,
## su resplandor sobre el regolito, la nave por fuera y la cabina. Uso: --look-shots. Salida: user://bench/look_*.png.

var main: Node
var world: SurfaceWorld
var _t := 0.0
var _step := 0


func _ready() -> void:
	world = main.start_world("moon", main.SPAWN_LAT, main.SPAWN_LON, false, true)


func _process(delta: float) -> void:
	if world == null or not world.surface_ready:
		return
	_t += delta
	if _t < 2.5:
		return
	_t = 0.0
	var pl := world.player
	match _step:
		0:
			_look_at_earth(pl, 0.0)
			pl.set_look_pitch(0.25)
		1:
			_shot("look_tierra")
			_look_at_earth(pl, PI)
			pl.set_look_pitch(0.55)
		2:
			_shot("look_cielo")
			_look_at_earth(pl, 0.9)
			pl.set_look_pitch(-0.05)
		3:
			_shot("look_nave")
			world._bring_aboard(pl, world.ship)
			pl._sit_down("piloto") if pl.aboard != null else null
		4:
			if pl.aboard != null and not pl.seated:
				pl._sit_down("piloto")
			_shot("look_pasillo")
		5:
			_shot("look_cabina")
			pl._stand_up() if pl.seated else null
			world._place_beside_host(pl, 0.0) if false else null
			# Medio día lunar después: de día.
			world.system.time_s += 14.77 * 86400.0
			pl.global_transform = Transform3D(pl.global_transform.basis, world.ship.global_transform * Vector3(30.0, 0.5, -10.0))
			pl.place_on_surface(pl.position_bf(), 0.3)
		6:
			_look_at_earth(pl, 1.4)
			pl.set_look_pitch(0.0)
		7:
			_shot("look_dia_nave")
			var sd := world.env.sun_direction_bf()
			var up := pl.global_transform.basis.y
			var flat := (sd - up * sd.dot(up)).normalized()
			pl.global_transform.basis = Basis(up.cross(-flat).normalized(), up, -flat).orthonormalized()
			pl.set_look_pitch(asin(clampf(sd.dot(up), -1.0, 1.0)) * 0.8)
		8:
			_shot("look_dia_sol")
			print("LOOK fps=%d" % Engine.get_frames_per_second())
			get_tree().quit(0)
	_step += 1


## Gira al astronauta hacia la Tierra (más `yaw` radianes).
func _look_at_earth(pl: Astronaut, yaw: float) -> void:
	var sys := world.system
	var rel := sys.position_in_frame("earth", world.body.id).sub(pl.position_bf())
	var up := pl.global_transform.basis.y
	var dir := rel.normalized().to_vector3()
	var flat := (dir - up * dir.dot(up)).normalized()
	flat = flat.rotated(up, yaw)
	pl.global_transform.basis = Basis(up.cross(-flat).normalized(), up, -flat).orthonormalized()


func _shot(name: String) -> void:
	var dir := ProjectSettings.globalize_path("user://bench")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("CAPTURA ", name, " fps=", Engine.get_frames_per_second())
