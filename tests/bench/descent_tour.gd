extends Node
## Capturas del descenso en atmósferas (Hito 3): Júpiter desde órbita hasta las profundidades, Saturno junto a los
## anillos y Titán. La nave se coloca a cada altitud con el piloto sentado y vista exterior o de cabina.
## Uso: --descent-tour. Salida: user://bench/descent_*.png.

var main: Node
var world: SurfaceWorld
var _i := -1
var _t := 0.0
var _out := ""

## [nombre, cuerpo, altitud sobre la referencia (m), vista exterior, cabeceo de la vista]
const SHOTS := [
	["jupiter_orbita", "jupiter", 300000.0, true, 0.0],
	["jupiter_sobre_nubes", "jupiter", 40000.0, false, -0.25],
	["jupiter_nubes_amoniaco", "jupiter", -8000.0, false, -0.05],
	["jupiter_nh4sh", "jupiter", -25000.0, false, 0.0],
	["jupiter_nubes_agua", "jupiter", -75000.0, true, 0.0],
	["jupiter_profundidad", "jupiter", -250000.0, false, 0.0],
	["saturno_anillos", "saturn", 25000000.0, true, 0.0],
	["titan_neblina", "titan", 60000.0, false, -0.2],
	["venus_nubes", "venus", 55000.0, false, 0.0],
	["venus_superficie", "venus", 300.0, false, -0.15],
]


func _ready() -> void:
	_out = ProjectSettings.globalize_path("user://bench")
	DirAccess.make_dir_recursive_absolute(_out)
	world = main.start_world("moon", main.SPAWN_LAT, main.SPAWN_LON, false, true)
	GameSettings.ui_hidden = false
	GameSettings.show_hud = false


func _physics_process(delta: float) -> void:
	if world == null or not world.surface_ready or world.ship == null:
		return
	var pl := world.player
	var ship := world.ship
	if _i == -1:
		pl.global_transform = ship.global_transform * Transform3D(Basis(), ShipLayout.SEAT_EXIT)
		_i = -2
		_t = 0.0
		return
	_t += delta
	if _i == -2:
		if _t > 1.0:
			pl._interact()
			_start(0)
		return
	# Mantener la altitud (la nave está suspendida por la asistencia; se recoloca por si deriva).
	if _t > 2.5:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_out.path_join("descent_%s.png" % SHOTS[_i][0]))
		var st := ship.state
		print("DESCENSO %s: %.3f bar, %.0f K, luz %.3f" % [SHOTS[_i][0], st.ext_pressure / 1e5, st.ext_temperature,
			world.atmo.light_fraction(st.pos_bf.length() - world.terrain.radius)])
		if _i + 1 >= SHOTS.size():
			get_tree().quit(0)
			return
		_start(_i + 1)


func _start(i: int) -> void:
	_i = i
	_t = 0.0
	var shot: Array = SHOTS[i]
	if world.body.id != shot[1]:
		world.set_anchor(shot[1])
	var ship := world.ship
	var alt: float = shot[2]
	var r := world.terrain.radius + alt
	if world.terrain.solid:
		r = world.terrain.ground_radius_at(ship.state.pos_bf) + alt
	# Lado iluminado: hacia el Sol, algo inclinado.
	var sun := DVec3.from_vector3(world.env.sun_direction_bf())
	var dir := sun.add(DVec3.new(0.3, 0.25, 0.1)).normalized()
	if shot[1] == "saturn":
		dir = sun.add(DVec3.new(0, 0.08, 0)).normalized()
	ship.state.pos_bf = dir.mul(r)
	ship.state.velocity = Vector3.ZERO
	ship.state.target_speed = 0.0
	ship.state.hull_integrity = 100.0
	var up := dir.to_vector3()
	var fwd := up.cross(Vector3(0, 1, 0)).normalized()
	if fwd.length_squared() < 0.5:
		fwd = up.cross(Vector3(1, 0, 0)).normalized()
	ship.state.basis = Basis(fwd.cross(up).normalized() * -1.0, up, -fwd)
	ship.state.basis = Basis(up.cross(-fwd).normalized(), up, -fwd).orthonormalized()
	ship.state.autopilot = ShipState.Autopilot.HOLD
	ship.state.autopilot_heading = -ship.state.basis.z
	ship.state.autopilot_up = up
	ship.state.autopilot_speed = 0.0
	ship.state.landed = false
	ship._sync_node()
	world.view.ship_exterior = shot[3]
	world.player.set_look_pitch(shot[4])
