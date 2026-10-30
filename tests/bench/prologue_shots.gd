extends Node
## Capturas del prólogo con audio real (ADR-043): despertar borroso en la cápsula, cápsula abierta, terminal médico y
## mensaje de Magnus con subtítulos. Uso: --prologue-shots. Salida: user://bench/prologo_*.png.

var main: Node
var world: SurfaceWorld
var _t := 0.0
var _step := 0


func _ready() -> void:
	world = main.start_world("moon", BaseLayout.SITE_LAT, BaseLayout.SITE_LON, false, true, false, true)


func _process(delta: float) -> void:
	if world == null or not world.surface_ready:
		return
	_t += delta
	var pr := world.prologue
	var pl := world.player
	match _step:
		0:
			if _t > 4.0:
				_shot("prologo_despertar")
				print("PROLOGO audio p01 sonando: %s (cola %s)" % [world.dialogue.current, str(world.dialogue._queue)])
				_step = 1
		1:
			if pr.step == "salir_capsula" and _t > 8.0:
				_shot("prologo_capsula_abierta")
				world.base.interact(pl, "capsula", "capsule")
				_step = 2
				_t = 0.0
			elif _t > 60.0:
				print("PROLOGO la cápsula no se abrió")
				get_tree().quit(1)
		2:
			if _t > 2.0:
				world.dialogue.stop_all()
				var b := world.base
				pl.place_on_surface(b.point_bf(Vector3(-2.0, 0, -56.0)).normalized(), 0.05)
				var up := pl.global_transform.basis.y
				var dir := b.to_engine(Vector3(6.6, 2.0, -56.0)) - pl.global_position
				var flat := (dir - up * dir.dot(up)).normalized()
				pl.global_transform.basis = Basis(up.cross(-flat).normalized(), up, -flat).orthonormalized()
				pl.set_look_pitch(0.05)
				pr.advance("pantalla")
				pr.flags["medico"] = true
				for id in ["p03", "p04", "p05", "p09", "p10", "p11", "p12"]:
					world.dialogue.heard[id] = true
				_step = 3
				_t = 0.0
		3:
			if world.dialogue.current == "magnus" and _t > 1.0:
				# Salta a mitad del discurso para ver un subtítulo largo.
				world.dialogue._player.seek(57.0)
				_step = 4
				_t = 0.0
			elif _t > 30.0:
				print("PROLOGO Magnus no empezó: paso %s actual %s" % [pr.step, world.dialogue.current])
				get_tree().quit(1)
		4:
			if _t > 3.0:
				_shot("prologo_magnus")
				print("PROLOGO subtítulo visible; cinemática=%s" % pl.cinematic)
				world.dialogue.skip()
				_step = 5
				_t = 0.0
		5:
			if _t > 2.5:
				_shot("prologo_objetivos")
				get_tree().quit(0)


func _shot(name: String) -> void:
	var dir := ProjectSettings.globalize_path("user://bench")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
