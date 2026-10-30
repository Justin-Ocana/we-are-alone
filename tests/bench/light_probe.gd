extends Node
## Diagnóstico de la iluminación interior: capturas del pasillo y del puente con luces normales, sin luces
## interiores y sin luz ambiente, para ver qué aporta cada una. Uso: --light-probe
## Salida: user://bench/light_*.png y el brillo medio de cada captura.

var main: Node
var world: SurfaceWorld
var _step := 0
var _t := 0.0
var _out := ""
var _applied := false
const VIEWS := [["pasillo", Vector3(0, 0, 8.5), 0.0, -0.1], ["puente", Vector3(0, 0, -19.0), 0.0, -0.1],
	["comedor", Vector3(-2.0, 0, -8.8), PI / 4 + 0.1, -0.2]]
const MODES := ["normal", "sin_luces", "sin_ambiente"]


func _ready() -> void:
	_out = ProjectSettings.globalize_path("user://bench")
	DirAccess.make_dir_recursive_absolute(_out)
	world = main.start_world("moon", -20.0, 140.0, false, true)
	GameSettings.ui_hidden = true
	GameSettings.show_hud = false


func _process(delta: float) -> void:
	if world == null or not world.surface_ready:
		return
	_t += delta
	var view: int = _step / MODES.size()
	var mode: int = _step % MODES.size()
	if view >= VIEWS.size():
		get_tree().quit(0)
		return
	if not _applied:
		_apply(VIEWS[view], MODES[mode])
		_applied = true
		_t = 0.0
	elif _t > 1.2:
		var img := get_viewport().get_texture().get_image()
		var name := "light_%s_%s" % [VIEWS[view][0], MODES[mode]]
		img.save_png(_out.path_join(name + ".png"))
		print("LUZ: %s brillo medio %.3f" % [name, _mean(img)])
		_step += 1
		_t = 0.0
		_applied = false


func _apply(v: Array, mode: String) -> void:
	var pl := world.player
	var ship := world.ship
	pl.global_transform = ship.global_transform * Transform3D(Basis(Vector3.UP, v[2]), v[1])
	pl.velocity = Vector3.ZERO
	pl.set_look_pitch(v[3])
	for c in ship.get_children():
		if c is OmniLight3D:
			c.visible = mode != "sin_luces"
	var env: Environment = world.view._env_interior
	env.ambient_light_energy = 0.0 if mode == "sin_ambiente" else ViewManager.INTERIOR_AMBIENT


static func _mean(img: Image) -> float:
	var sum := 0.0
	var n := 0
	for y in range(0, img.get_height(), 8):
		for x in range(0, img.get_width(), 8):
			sum += img.get_pixel(x, y).get_luminance()
			n += 1
	return sum / maxf(1.0, n)
