extends Node
## Capturas del cooperativo local (ADR-032): pantalla dividida en la Luna, el jugador 2 a bordo y ambos en la
## nave. Uso: --coop-shots [--split=horizontal]. Salida: user://bench/coop_*.png.

var main: Node
var world: SurfaceWorld
var _t := 0.0
var _step := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--split=horizontal"):
		GameSettings.split_mode = "horizontal"
	GameInput.configure_players(0)
	world = main.start_world("moon", main.SPAWN_LAT, main.SPAWN_LON, false, true, true)


func _process(delta: float) -> void:
	if world == null or not world.surface_ready:
		return
	_t += delta
	if _t < 2.0:
		return
	_t = 0.0
	var p1: Astronaut = world.players[0]
	var p2: Astronaut = world.players[1]
	match _step:
		0:
			# El jugador 2 mira al jugador 1 (se ve su cuerpo; cada uno oculta sólo su propia cabeza).
			var to := p1.global_position - p2.global_position
			p2.look_at(p2.global_position - to, p2.global_transform.basis.y)
			p2.rotate_object_local(Vector3.UP, PI)
			_shot("coop_superficie")
			world._bring_aboard(p2, world.ship)
		1:
			_shot("coop_p2_a_bordo")
			world._bring_aboard(p1, world.ship)
			p1._sit_down("piloto")
			p2._sit_down("copiloto")
		2:
			_shot("coop_cabina")
			print("COOP p1 aboard=%s seated=%s · p2 aboard=%s seated=%s · fps=%d" % [p1.aboard != null, p1.seated,
				p2.aboard != null, p2.seated, Engine.get_frames_per_second()])
			get_tree().quit(0)
	_step += 1


func _shot(name: String) -> void:
	var dir := ProjectSettings.globalize_path("user://bench")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("CAPTURA ", name, " fps=", Engine.get_frames_per_second())
