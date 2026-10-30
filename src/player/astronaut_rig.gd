class_name AstronautRig
extends Node3D
## Cuerpo del astronauta (1,85 m) construido con primitivas articuladas y animado de forma procedural
## (ADR-009). Es el MISMO cuerpo en 1ª y 3ª persona ("true first person"): al mirar abajo se ven el
## pecho, los brazos, las piernas y las botas.
##
## - Piernas: IK analítica de dos huesos hacia objetivos de pie apoyados en el suelo (rayos físicos).
##   Durante el apoyo el pie retrocede exactamente lo que avanza el cuerpo → sin deslizamiento.
## - Marcha: Gait (Froude): caminar / correr / "loping" en baja gravedad, zancada y bote balísticos.
## - Brazos en contrabalanceo, torso inclinado al correr y al mirar abajo, compresión al aterrizar.
## - El origen del rig está en los pies; -Z es delante.

signal footstep(intensity: float)

const HEAD_LAYER := Layers.HEAD   ## capa de render de cabeza y casco (oculta para la cámara en 1ª persona)

# Antropometría (m) para 1,85 m de estatura.
const HIP_HEIGHT := 0.96
const THIGH := 0.45
const SHIN := 0.44
const ANKLE_HEIGHT := 0.07
const HIP_HALF_WIDTH := 0.105
const STANCE_HALF_WIDTH := 0.15  ## pies algo más separados que las caderas (postura con traje)
const SPINE_OFFSET := 0.10
const ABDOMEN := 0.20
const CHEST := 0.28
const SHOULDER_HALF_WIDTH := 0.23
const UPPER_ARM := 0.30
const FOREARM := 0.27
const NECK := 0.06
const EYE_UP := 0.12
const EYE_FORWARD := 0.09
const STAND_BEND := 0.008  ## la pelvis queda 8 mm por debajo de la pierna estirada

var astro: CharacterBody3D
var head_slot := 0                ## jugador dueño de este cuerpo (capas de cabeza propias; ADR-032)

var pelvis: Node3D
var abdomen: Node3D
var chest: Node3D
var neck: Node3D
var head: Node3D
var eye_marker: Node3D
var hips: Array[Node3D] = []
var knees: Array[Node3D] = []
var ankles: Array[Node3D] = []
var shoulders: Array[Node3D] = []
var elbows: Array[Node3D] = []

## Desplazamiento de la pelvis debido a la locomoción (bote, balanceo, compresión), espacio del rig.
## La cámara lo contrarresta parcialmente (estabilización de cabeza).
var pelvis_motion := Vector3.ZERO
var phase := 0.0
var gait_kind: int = Gait.Kind.IDLE
var foot_targets: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]  ## último objetivo de tobillo (rig)

var _speed := 0.0
var _move_dir := Vector2(0, 1)
var _stride := 0.0
var _duty := 1.0
var _offset := 0.5
var _lift := 0.0
var _bob := 0.0
var _arm_amp := 0.0
var _lean := 0.0
var _air := 0.0
var _comp := 0.0
var _comp_vel := 0.0
var _breath := 0.0
var _prev_q: Array[float] = [0.0, 0.5]

var _parts: Array[MeshInstance3D] = []
var _mat_suit: StandardMaterial3D
var _mat_joint: StandardMaterial3D
var _mat_glove: StandardMaterial3D
var _mat_visor: StandardMaterial3D
var _mat_dark: StandardMaterial3D
var _mat_red: StandardMaterial3D
var _mat_panel: StandardMaterial3D
var _stripes_right: Array[MeshInstance3D] = []   ## franjas del lado derecho (patrón "franjas dobles")
var _stripes_left: Array[MeshInstance3D] = []
var _tanks: Array[MeshInstance3D] = []           ## mochila de tanques dobles (estilo 1)
var _pack_std: Array[MeshInstance3D] = []


func _init() -> void:
	_make_materials()
	_build()


# --- Construcción -----------------------------------------------------------------

func _make_materials() -> void:
	_mat_suit = _mat(Color(0.92, 0.91, 0.87), 0.85)
	_mat_joint = _mat(Color(0.55, 0.56, 0.58), 0.45, 0.5)
	_mat_glove = _mat(Color(0.78, 0.80, 0.84), 0.7)
	_mat_dark = _mat(Color(0.16, 0.16, 0.17), 0.9)
	_mat_red = _mat(Color(0.72, 0.09, 0.08), 0.7)
	_mat_panel = _mat(Color(0.82, 0.82, 0.80), 0.6)
	_mat_visor = _mat(Color(0.85, 0.62, 0.22), 0.12, 0.35)
	_mat_visor.metallic_specular = 1.0


static func _mat(c: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _joint(parent: Node3D, pos: Vector3, node_name: String) -> Node3D:
	var j := Node3D.new()
	j.name = node_name
	j.position = pos
	parent.add_child(j)
	return j


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot := Vector3.ZERO,
		scl := Vector3.ONE, head_part := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	var hl := Layers.head_layers(head_slot)
	mi.layers = Layers.bit(hl.x if head_part else Layers.BODY)
	mi.set_meta("head", head_part)
	parent.add_child(mi)
	_parts.append(mi)
	return mi


## Dentro de una nave el cuerpo pasa a capas interiores (sin luz solar a través del casco).
func set_interior(on: bool) -> void:
	for mi in _parts:
		var head: bool = mi.get_meta("head", false)
		var hl := Layers.head_layers(head_slot)
		var layer := (hl.y if head else Layers.BODY_INT) if on else (hl.x if head else Layers.BODY)
		mi.layers = Layers.bit(layer)


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.0)
	c.radial_segments = 16
	c.rings = 6
	return c


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 16
	return c


static func _ring(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 16
	t.ring_segments = 8
	return t


static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 20
	s.rings = 10
	return s


func _build() -> void:
	pelvis = _joint(self, Vector3(0, HIP_HEIGHT - STAND_BEND, 0), "Pelvis")
	_part(pelvis, _capsule(0.15, 0.40), Vector3(0, -0.02, 0), _mat_suit, Vector3(0, 0, PI / 2), Vector3(1, 1, 0.82))
	_part(pelvis, _ring(0.15, 0.185), Vector3(0, 0.08, 0), _mat_joint, Vector3.ZERO, Vector3(1.08, 1, 0.8))

	abdomen = _joint(pelvis, Vector3(0, SPINE_OFFSET, 0), "Abdomen")
	_part(abdomen, _cyl(0.175, 0.16, 0.24), Vector3(0, 0.10, 0), _mat_suit, Vector3.ZERO, Vector3(1.05, 1, 0.78))

	chest = _joint(abdomen, Vector3(0, ABDOMEN, 0), "Chest")
	_part(chest, _capsule(0.20, 0.50), Vector3(0, 0.13, 0.02), _mat_suit, Vector3.ZERO, Vector3(1.18, 0.62, 0.72))
	# Módulo de control en el pecho (lo que un astronauta ve al mirar abajo).
	_part(chest, _box(Vector3(0.18, 0.08, 0.05)), Vector3(0, -0.03, -0.15), _mat_panel, Vector3(-0.35, 0, 0))
	for k in 3:
		_part(chest, _cyl(0.011, 0.011, 0.02), Vector3(-0.045 + k * 0.045, -0.018, -0.18), _mat_red if k == 1 else _mat_dark, Vector3(PI / 2 - 0.35, 0, 0))
	# Mochila de soporte vital (PLSS).
	_pack_std.append(_part(chest, _box(Vector3(0.46, 0.62, 0.22)), Vector3(0, 0.12, 0.27), _mat_suit))
	_pack_std.append(_part(chest, _box(Vector3(0.40, 0.14, 0.18)), Vector3(0, 0.47, 0.25), _mat_panel))
	_part(chest, _box(Vector3(0.36, 0.05, 0.02)), Vector3(0, 0.0, 0.385), _mat_dark)
	# Variante: dos tanques cilíndricos con franja de color (personalización, ADR-035).
	for tx: float in [-0.12, 0.12]:
		_tanks.append(_part(chest, _capsule(0.11, 0.66), Vector3(tx, 0.14, 0.29), _mat_panel))
		_tanks.append(_part(chest, _cyl(0.113, 0.113, 0.06), Vector3(tx, 0.3, 0.29), _mat_red))

	neck = _joint(chest, Vector3(0, CHEST, 0), "Neck")
	_part(neck, _ring(0.12, 0.16), Vector3(0, 0.0, 0), _mat_joint, Vector3.ZERO, Vector3.ONE, true)
	head = _joint(neck, Vector3(0, NECK, 0), "Head")
	_part(head, _sphere(0.165), Vector3(0, 0.05, 0.01), _mat_suit, Vector3.ZERO, Vector3.ONE, true)
	_part(head, _sphere(0.152), Vector3(0, 0.065, -0.035), _mat_visor, Vector3.ZERO, Vector3(1.0, 0.78, 0.92), true)
	_part(head, _box(Vector3(0.05, 0.03, 0.05)), Vector3(0.15, 0.10, 0.0), _mat_dark, Vector3.ZERO, Vector3.ONE, true)
	eye_marker = _joint(head, Vector3(0, EYE_UP, -EYE_FORWARD), "Eyes")

	for s in 2:
		var side := -1.0 if s == 0 else 1.0
		# Brazo
		var sh := _joint(chest, Vector3(side * SHOULDER_HALF_WIDTH, CHEST - 0.04, 0), "Shoulder%d" % s)
		_part(sh, _sphere(0.10), Vector3.ZERO, _mat_suit)
		_part(sh, _capsule(0.075, UPPER_ARM + 0.06), Vector3(0, -UPPER_ARM * 0.5, 0), _mat_suit)
		# Franja de color de comandante (como en el Apolo); la del lado derecho sólo con "franjas dobles".
		var arm_stripe := _part(sh, _cyl(0.079, 0.079, 0.035), Vector3(0, -UPPER_ARM * 0.55, 0), _mat_red)
		(_stripes_left if s == 0 else _stripes_right).append(arm_stripe)
		var el := _joint(sh, Vector3(0, -UPPER_ARM, 0), "Elbow%d" % s)
		_part(el, _ring(0.05, 0.08), Vector3.ZERO, _mat_joint)
		_part(el, _capsule(0.066, FOREARM + 0.04), Vector3(0, -FOREARM * 0.5, 0), _mat_suit)
		var wr := _joint(el, Vector3(0, -FOREARM, 0), "Wrist%d" % s)
		_part(wr, _cyl(0.062, 0.062, 0.04), Vector3(0, 0.01, 0), _mat_joint)
		_part(wr, _capsule(0.048, 0.17), Vector3(0, -0.085, -0.005), _mat_glove, Vector3.ZERO, Vector3(1.25, 1, 0.75))
		_part(wr, _capsule(0.02, 0.08), Vector3(-side * 0.045, -0.06, -0.03), _mat_glove, Vector3(0.4, 0, -side * 0.5))
		shoulders.append(sh)
		elbows.append(el)
		# Pierna
		var hp := _joint(pelvis, Vector3(side * HIP_HALF_WIDTH, -0.05, 0), "Hip%d" % s)
		_part(hp, _capsule(0.10, THIGH + 0.08), Vector3(0, -THIGH * 0.5, 0), _mat_suit)
		var leg_stripe := _part(hp, _cyl(0.104, 0.104, 0.04), Vector3(0, -THIGH * 0.35, 0), _mat_red)
		(_stripes_left if s == 0 else _stripes_right).append(leg_stripe)
		var kn := _joint(hp, Vector3(0, -THIGH, 0), "Knee%d" % s)
		_part(kn, _ring(0.07, 0.092), Vector3.ZERO, _mat_joint)
		_part(kn, _capsule(0.085, SHIN + 0.05), Vector3(0, -SHIN * 0.5, 0), _mat_suit)
		var an := _joint(kn, Vector3(0, -SHIN, 0), "Ankle%d" % s)
		_part(an, _box(Vector3(0.13, 0.11, 0.30)), Vector3(0, -0.015, -0.07), _mat_suit)
		_part(an, _box(Vector3(0.11, 0.07, 0.07)), Vector3(0, -0.035, -0.20), _mat_panel)
		_part(an, _box(Vector3(0.14, 0.03, 0.32)), Vector3(0, -ANKLE_HEIGHT + 0.015, -0.07), _mat_dark)
		_part(an, _cyl(0.09, 0.095, 0.08), Vector3(0, 0.05, 0), _mat_suit)
		hips.append(hp)
		knees.append(kn)
		ankles.append(an)


## Personalización (ADR-035): colores del traje, de las franjas y del visor; patrón y mochila.
## patrón: 0 = franjas de comandante (izquierda), 1 = franjas dobles, 2 = liso.
func apply_profile(prof: Dictionary) -> void:
	var suit: Color = prof.get("suit", Color(0.92, 0.91, 0.87))
	_mat_suit.albedo_color = suit
	_mat_panel.albedo_color = suit.lerp(Color(0.8, 0.8, 0.8), 0.35).darkened(0.08)
	_mat_red.albedo_color = prof.get("accent", Color(0.72, 0.09, 0.08))
	_mat_visor.albedo_color = prof.get("visor", Color(0.85, 0.62, 0.22))
	var pattern := int(prof.get("pattern", 0))
	for m in _stripes_left:
		m.visible = pattern != 2
	for m in _stripes_right:
		m.visible = pattern == 1
	var tanks := int(prof.get("backpack", 0)) == 1
	for m in _tanks:
		m.visible = tanks
	for m in _pack_std:
		m.visible = not tanks


## Postura de pie neutra (vista previa de la personalización, sin física ni animación de marcha).
func reset_pose() -> void:
	pelvis.position = Vector3(0, HIP_HEIGHT - STAND_BEND, 0)
	pelvis.rotation = Vector3.ZERO
	abdomen.rotation = Vector3.ZERO
	chest.rotation = Vector3.ZERO
	head.rotation = Vector3.ZERO
	for s in 2:
		var side := -1.0 if s == 0 else 1.0
		shoulders[s].rotation = Vector3(0.22, 0.0, side * 0.16)
		elbows[s].rotation = Vector3(0.95, 0.0, 0.0)
		hips[s].rotation = Vector3.ZERO
		knees[s].rotation = Vector3.ZERO
		ankles[s].rotation = Vector3.ZERO


## Emotes (ADR-035): poses procedurales sobre la animación normal (se aplican después de animate()).
## "wave" saludar, "dance" baile, "dance2" robot, "cheer" celebrar, "point" señalar.
func apply_emote(emote: String, t: float) -> void:
	if emote == "":
		return
	var beat := t * TAU * 124.0 / 60.0   # al ritmo de la pieza "fiesta"
	match emote:
		"wave":
			shoulders[1].rotation = Vector3(0.25, 0.0, 2.55 + 0.25 * sin(t * 9.0))
			elbows[1].rotation = Vector3(0.55 + 0.25 * sin(t * 9.0 + 1.0), 0.0, 0.0)
			head.rotation.z += 0.08 * sin(t * 4.5)
		"point":
			shoulders[1].rotation = Vector3(1.45, 0.0, 0.12)
			elbows[1].rotation = Vector3(0.05, 0.0, 0.0)
			shoulders[0].rotation = Vector3(0.1, 0.0, -0.25)
		"cheer":
			for s in 2:
				var side := -1.0 if s == 0 else 1.0
				shoulders[s].rotation = Vector3(0.2, 0.0, side * (2.75 + 0.15 * sin(t * 10.0 + s)))
				elbows[s].rotation = Vector3(0.35 + 0.35 * maxf(sin(t * 10.0 + s), 0.0), 0.0, 0.0)
			pelvis.position.y += 0.05 * maxf(sin(t * 10.0), 0.0)
		"dance":
			for s in 2:
				var side := -1.0 if s == 0 else 1.0
				shoulders[s].rotation = Vector3(0.7 + 0.6 * sin(beat + s * PI), 0.0, side * (0.9 + 0.5 * sin(beat * 0.5 + s)))
				elbows[s].rotation = Vector3(1.2 + 0.4 * sin(beat + s), 0.0, 0.0)
			pelvis.position.y -= 0.04 * absf(sin(beat * 0.5))
			pelvis.rotation.y += 0.25 * sin(beat * 0.5)
			chest.rotation.z += 0.12 * sin(beat * 0.5)
			head.rotation.x += 0.12 * sin(beat)
		"dance2":
			# Robot: poses fijas que cambian a cada medio tiempo.
			var step := int(floor(beat / PI)) % 4
			var poses := [[Vector3(1.57, 0, -0.2), Vector3(1.4, 0, 0), Vector3(0.1, 0, 0.3), Vector3(1.57, 0, 0)],
				[Vector3(0.1, 0, -0.3), Vector3(1.57, 0, 0), Vector3(1.57, 0, 0.2), Vector3(1.4, 0, 0)],
				[Vector3(0.0, 0, -1.57), Vector3(1.57, 0, 0), Vector3(0.0, 0, 1.57), Vector3(-1.57, 0, 0)],
				[Vector3(3.0, 0, -0.1), Vector3(0.1, 0, 0), Vector3(3.0, 0, 0.1), Vector3(0.1, 0, 0)]]
			var ps: Array = poses[step]
			shoulders[0].rotation = ps[0]
			elbows[0].rotation = ps[1]
			shoulders[1].rotation = ps[2]
			elbows[1].rotation = ps[3]
			head.rotation.y += (0.35 if step % 2 == 0 else -0.35)
			pelvis.rotation.y += (0.15 if step < 2 else -0.15)


# --- Animación ----------------------------------------------------------------------

func on_landed(impact_speed: float) -> void:
	_comp_vel -= minf(impact_speed, 7.0) * 0.22
	footstep.emit(clampf(impact_speed / 4.0, 0.4, 1.5))


## Avanza la animación. `look_pitch` (rad, negativo = abajo), `head_yaw` (rad, mirada libre),
## `turn_rate` (rad/s del cuerpo), `grounded`, `flying`.
func animate(delta: float, look_pitch: float, head_yaw: float, turn_rate: float, grounded: bool,
		flying: bool, gravity: float, exertion: float, lean: float = 0.0) -> void:
	if astro == null or delta <= 0.0:
		return
	var b := astro.global_transform.basis.orthonormalized()
	var v_local := b.transposed() * astro.velocity
	var v_h := Vector2(v_local.x, -v_local.z)
	var on_ground := grounded and not flying
	var speed := v_h.length() if on_ground else 0.0
	var shuffle := on_ground and speed < Gait.IDLE_SPEED and absf(turn_rate) > 0.8
	var eff_speed := speed if not shuffle else 0.35
	gait_kind = Gait.select(eff_speed, gravity) if on_ground else Gait.Kind.IDLE

	var stride_t := 0.0
	var lift_t := 0.0
	var bob_t := 0.0
	var arm_t := 0.0
	var lean_t := 0.0
	if gait_kind != Gait.Kind.IDLE:
		stride_t = 0.3 if shuffle else Gait.stride_length(eff_speed, gravity)
		bob_t = Gait.flight_height(gait_kind, eff_speed, gravity)
		match gait_kind:
			Gait.Kind.WALK:
				lift_t = 0.07; bob_t += 0.025; arm_t = 0.35; lean_t = 0.03
			Gait.Kind.RUN:
				lift_t = 0.17; bob_t += 0.045; arm_t = 0.75; lean_t = 0.17
			Gait.Kind.LOPE:
				lift_t = 0.13; bob_t += 0.02; arm_t = 0.22; lean_t = 0.10
		if shuffle:
			lift_t = 0.05; bob_t = 0.005; arm_t = 0.05; lean_t = 0.0
	var k := 1.0 - exp(-7.0 * delta)
	_stride = lerpf(_stride, stride_t, k)
	_duty = lerpf(_duty, Gait.duty_factor(gait_kind), k)
	_offset = lerpf(_offset, Gait.leg_phase_offset(gait_kind), k)
	_lift = lerpf(_lift, lift_t, k)
	_bob = lerpf(_bob, bob_t, k)
	_arm_amp = lerpf(_arm_amp, arm_t, k)
	_lean = lerpf(_lean, lean_t, k)
	_air = lerpf(_air, 0.0 if on_ground else 1.0, 1.0 - exp(-6.0 * delta))
	if speed > 0.1:
		_move_dir = _move_dir.slerp(v_h.normalized(), 1.0 - exp(-10.0 * delta))
	elif not shuffle:
		_move_dir = _move_dir.slerp(Vector2(0, 1), k)
	if gait_kind != Gait.Kind.IDLE and _stride > 0.01:
		phase = fposmod(phase + eff_speed / maxf(_stride, 0.2) * delta, 1.0)

	# Compresión de aterrizaje (muelle amortiguado).
	_comp_vel += (-140.0 * _comp - 15.0 * _comp_vel) * delta
	_comp = clampf(_comp + _comp_vel * delta, -0.32, 0.08)
	_breath += delta * TAU * lerpf(0.25, 0.7, exertion)

	# Pelvis: bote (dos por ciclo al caminar/correr, uno al "lopear"), balanceo lateral.
	var tp := TAU * phase
	var wave := maxf(0.0, sin(tp)) * 2.0 - 0.6 if gait_kind == Gait.Kind.LOPE else cos(2.0 * tp)
	var sway := 0.022 * sin(tp) * clampf(_arm_amp * 3.0, 0.0, 1.0) * (1.0 - _air)
	pelvis_motion = Vector3(sway, _bob * wave * (1.0 - _air) + _comp, 0.0)

	# Objetivos de los pies.
	var fwd3 := Vector3(_move_dir.x, 0.0, -_move_dir.y)
	var pelvis_base_y := HIP_HEIGHT - STAND_BEND
	var targets: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var alongs: Array[float] = []
	for s in 2:
		var side := -1.0 if s == 0 else 1.0
		var q := fposmod(phase + (0.0 if s == 0 else _offset), 1.0)
		var along := 0.0
		var lift := 0.0
		if q < _duty:
			along = (0.5 - q / _duty) * _stride * _duty
		else:
			var t := (q - _duty) / maxf(1.0 - _duty, 0.01)
			along = (-0.5 + smoothstep(0.0, 1.0, t)) * _stride * _duty
			lift = _lift * sin(PI * t)
		if on_ground and _prev_q[s] > q and _stride > 0.05:  # contacto del talón
			footstep.emit(clampf(0.4 + eff_speed * 0.15, 0.3, 1.2))
		_prev_q[s] = q
		var base := Vector3(side * STANCE_HALF_WIDTH, 0.0, 0.0) + fwd3 * along
		var gy := 0.0
		var gn := Vector3.UP
		if on_ground or _air < 0.95:
			var g := _ground_at(base)
			gy = g[0]
			gn = g[1]
		var target := Vector3(base.x, gy + ANKLE_HEIGHT + lift, base.z)
		var air_target := Vector3(side * 0.13, pelvis_base_y - 0.66, 0.06 if s == 0 else -0.12)
		target = target.lerp(air_target, _air)
		targets.append(target)
		normals.append(gn.lerp(Vector3.UP, _air).normalized())
		alongs.append(along)

	# Si un pie no alcanza (pendiente, escalón), se baja la pelvis (postura, no bote).
	var drop := 0.0
	for s in 2:
		var side := -1.0 if s == 0 else 1.0
		var hip_y := pelvis_base_y + pelvis_motion.y - 0.05
		var dx := targets[s].x - side * HIP_HALF_WIDTH
		var dz := targets[s].z
		var reach := THIGH + SHIN - 0.005
		var horiz2 := dx * dx + dz * dz
		if horiz2 < reach * reach:
			var need_y := targets[s].y + sqrt(reach * reach - horiz2)
			drop = maxf(drop, hip_y - need_y)
	drop = clampf(drop, 0.0, 0.45) * (1.0 - _air)

	pelvis.position = Vector3(pelvis_motion.x, pelvis_base_y + pelvis_motion.y - drop, 0.0)
	var twist := 0.10 * sin(tp) * _arm_amp
	pelvis.rotation = Vector3(-_lean * 0.25, twist, -sway * 1.5)
	# Al mirar abajo el torso se inclina poco: los ojos quedan sobre las punteras y se ven los pies.
	# Asomarse (Q/E): el torso se inclina de lado desde la cintura; la cabeza y los ojos lo siguen.
	abdomen.rotation = Vector3(-_lean * 0.35 + minf(look_pitch, 0.0) * 0.12, -twist * 0.6 + head_yaw * 0.1, -lean * 0.20)
	var breath := sin(_breath) * 0.012 * (0.5 + exertion)
	chest.rotation = Vector3(-_lean * 0.4 + minf(look_pitch, 0.0) * 0.10 + maxf(look_pitch, 0.0) * 0.12 + breath,
		-twist * 0.6 + head_yaw * 0.15, -lean * 0.24)
	# Al mirar abajo se adelanta la cabeza (como al mirarse los pies), así la vista libra el pecho.
	neck.position = Vector3(0, CHEST, minf(look_pitch, 0.0) * 0.16)
	var torso_pitch := pelvis.rotation.x + abdomen.rotation.x + chest.rotation.x
	head.rotation = Vector3(look_pitch - torso_pitch, head_yaw * 0.75, lean * 0.30)

	for s in 2:
		var side := -1.0 if s == 0 else 1.0
		var hip_local := Vector3(side * HIP_HALF_WIDTH, -0.05, 0.0)
		_solve_leg(s, hip_local, targets[s], normals[s], side)
		foot_targets[s] = targets[s]

	# Brazos: contrabalanceo con la pierna opuesta; el traje presurizado los mantiene algo separados.
	for s in 2:
		var side := -1.0 if s == 0 else 1.0
		var opp: float = alongs[1 - s]
		var swing := _arm_amp * clampf(opp / maxf(0.15, _stride * _duty * 0.5), -1.2, 1.2) * 0.55
		var abduct := lerpf(0.16, 0.55, _air) + (0.12 if gait_kind == Gait.Kind.LOPE else 0.0)
		shoulders[s].rotation = Vector3(swing + 0.22 + _air * 0.3, 0.0, side * abduct)
		var flex := lerpf(0.95, 1.35, clampf(_arm_amp / 0.75, 0.0, 1.0)) + maxf(swing, 0.0) * 0.3 + _air * 0.2
		elbows[s].rotation = Vector3(flex, 0.0, 0.0)


## Postura sentada en el puesto de pilotaje: muslos horizontales, pies delante, manos en los mandos
## (la mano derecha sigue a la palanca virtual).
func animate_seated(delta: float, look_pitch: float, head_yaw: float, stick: Vector2, exertion: float) -> void:
	var k := 1.0 - exp(-8.0 * delta)
	_air = lerpf(_air, 0.0, k)
	_stride = 0.0
	_lift = 0.0
	_breath += delta * TAU * lerpf(0.25, 0.7, exertion)
	pelvis_motion = Vector3.ZERO
	var seat_y := ShipLayout.SEAT_HEIGHT + 0.1
	pelvis.position = Vector3(0, seat_y, 0.05)
	pelvis.rotation = Vector3(0.05, 0, 0)
	abdomen.rotation = Vector3(0.04 + minf(look_pitch, 0.0) * 0.1, head_yaw * 0.1, 0)
	chest.rotation = Vector3(0.06 + minf(look_pitch, 0.0) * 0.15 + sin(_breath) * 0.01, head_yaw * 0.15, 0)
	neck.position = Vector3(0, CHEST, minf(look_pitch, 0.0) * 0.1)
	var torso_pitch := pelvis.rotation.x + abdomen.rotation.x + chest.rotation.x
	head.rotation = Vector3(look_pitch - torso_pitch, head_yaw * 0.75, 0.0)
	for s in 2:
		var side := -1.0 if s == 0 else 1.0
		var target := Vector3(side * 0.16, ANKLE_HEIGHT, -0.48)
		_solve_leg(s, Vector3(side * HIP_HALF_WIDTH, -0.05, 0.0), target, Vector3.UP, side)
		foot_targets[s] = target
	# Brazos: izquierda en el acelerador, derecha en la palanca (se desvía con la palanca virtual).
	shoulders[0].rotation = Vector3(0.55, 0.0, -0.22)
	elbows[0].rotation = Vector3(1.05, 0.0, 0.0)
	shoulders[1].rotation = Vector3(0.55 - stick.y * 0.15, 0.0, 0.22 - stick.x * 0.12)
	elbows[1].rotation = Vector3(1.05 + stick.y * 0.1, 0.0, 0.0)


func _ground_at(local_pos: Vector3) -> Array:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return [0.0, Vector3.UP]
	var from := global_transform * Vector3(local_pos.x, 0.65, local_pos.z)
	var to := global_transform * Vector3(local_pos.x, -0.75, local_pos.z)
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.solid_mask(), [astro.get_rid()])
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return [0.0, Vector3.UP]
	var lp := to_local(hit["position"])
	var ln: Vector3 = (global_transform.basis.orthonormalized().transposed() * (hit["normal"] as Vector3)).normalized()
	if ln.y < 0.5:
		ln = Vector3.UP
	return [clampf(lp.y, -0.6, 0.6), ln]


## IK analítica de dos huesos (cadera-rodilla-tobillo) en el espacio del rig.
func _solve_leg(s: int, hip_local: Vector3, target: Vector3, ground_n: Vector3, side: float) -> void:
	var hip_pos := pelvis.transform * hip_local
	var to := target - hip_pos
	var d := clampf(to.length(), 0.05, THIGH + SHIN - 0.001)
	var dir := to.normalized() if to.length_squared() > 1e-8 else Vector3.DOWN
	var cos_a := (THIGH * THIGH + d * d - SHIN * SHIN) / (2.0 * THIGH * d)
	var alpha := acos(clampf(cos_a, -1.0, 1.0))
	var cos_k := (THIGH * THIGH + SHIN * SHIN - d * d) / (2.0 * THIGH * SHIN)
	var flex := PI - acos(clampf(cos_k, -1.0, 1.0))
	var pole := Vector3(side * 0.12, 0.0, -1.0).normalized()
	var n := dir.cross(pole)
	if n.length_squared() < 1e-8:
		n = Vector3.RIGHT
	n = n.normalized()
	var thigh_dir := dir.rotated(n, alpha)
	var y := -thigh_dir
	var z := n.cross(y).normalized()
	var x := y.cross(z).normalized()
	var hip_basis_rig := Basis(x, y, z)
	hips[s].transform = Transform3D(pelvis.transform.basis.inverse() * hip_basis_rig, hip_local)
	var knee_basis := Basis(Vector3.RIGHT, -flex)
	knees[s].transform = Transform3D(knee_basis, Vector3(0, -THIGH, 0))
	# Pie apoyado según la normal del suelo, mirando hacia delante del cuerpo (ligera apertura).
	var foot_fwd := Vector3(side * 0.12, 0.0, -1.0).normalized()
	var fy := ground_n
	var fz := -(foot_fwd - fy * foot_fwd.dot(fy)).normalized()
	var fx := fy.cross(fz).normalized()
	var foot_rig := Basis(fx, fy, fz)
	ankles[s].transform = Transform3D((hip_basis_rig * knee_basis).inverse() * foot_rig, Vector3(0, -SHIN, 0))
