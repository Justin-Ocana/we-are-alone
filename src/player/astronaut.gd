class_name Astronaut
extends CharacterBody3D
## Astronauta de 1,85 m sobre un cuerpo esférico (ADR-006, ADR-009).
##
## - El origen del nodo está en los pies. `up_direction` = dirección radial, actualizada cada paso.
## - Gravedad g = GM/r² calculada en doble precisión desde la posición BF.
## - Cuerpo completo animado (AstronautRig) visible en 1ª y 3ª persona; cámara en los ojos con
##   estabilización de cabeza (BodyCamera); interior del casco (HelmetOverlay); sonido del traje.
## - Velocidad máxima limitada por la gravedad (Gait.max_speed_factor) y marcha según Froude.
## - Alt mantenido = mirada libre (la cabeza gira sin cambiar la dirección de la marcha).
## - Modo de vuelo de depuración (tecla N): sin colisión, velocidad ajustable con la rueda.
## - Naves (ADR-011, ADR-018): dentro de una nave rige la gravedad APARENTE (planeta menos la aceleración
##   de la nave, o la artificial si está activada): si la nave se inclina o acelera, el astronauta lo nota
##   y su postura se reorienta suavemente. La nave lo traslada (carry) y al entrar/salir se conserva la
##   velocidad absoluta. Sentado en el puesto de pilotaje, el control pasa a ShipPilotInput; en los demás
##   asientos se mira libremente.
## - Ingravidez y caída libre (ADR-018): en ingravidez o cayendo desde lo alto, el cuerpo flota con
##   orientación libre y conserva su giro (sale dando vueltas de una nave en marcha). Propulsores del
##   traje (WASD/Espacio/Ctrl, Q/E alabeo, X estabilizar) con combustible limitado. El giro marea
##   (efectos de vista), sin pérdida de conocimiento (retirada a petición del jugador).
## - Salud: los golpes (caídas, impactos de la nave) hacen daño y se regenera con el tiempo.

signal mode_changed
signal landed(impact_speed: float)
signal damaged(amount: float)
signal action_requested(action: String)   ## escanear / diario / foto: los atiende el mundo (ExplorationLog)

const WALK_SPEED := 1.6          ## m/s (paso cómodo con traje)
const RUN_SPEED := 5.0           ## m/s en 1 g; se escala con la gravedad
const JUMP_TAKEOFF_SPEED := 3.0  ## m/s (velocidad de despegue humana; la altura depende de g)
const AIR_CONTROL_ACCEL := 0.6   ## m/s² (concesión de jugabilidad: no hay aire)
const GROUND_CLAMP_TOLERANCE := 1.0
const FLY_SPEED_MIN := 1.0
const FLY_SPEED_MAX := 200000.0
const FREELOOK_MAX_YAW := deg_to_rad(110.0)
const SEATED_LOOK_YAW := deg_to_rad(160.0)  ## sentado: girar la cabeza (y el torso) para ver detrás
const PITCH_LIMIT := deg_to_rad(85.0)
const ZERO_G := 0.25             ## m/s²: por debajo se flota
const FREEFALL_ALT := 12.0       ## m: caer desde más alto pasa a caída libre (orientación libre)
const POSTURE_RATE := 2.2        ## rad/s: reorientación del cuerpo cuando cambia la gravedad
const JET_ACCEL := 1.2           ## m/s² de los propulsores del traje
const JET_ROLL_ACCEL := 1.5      ## rad/s² de alabeo / estabilización
const JET_FUEL_TIME := 90.0      ## s de empuje continuo con el depósito lleno
const SAFE_IMPACT := 5.5         ## m/s: por encima, los golpes hacen daño
const IMPACT_DAMAGE := 14.0      ## puntos de salud por m/s por encima de SAFE_IMPACT
const REGEN_DELAY := 6.0
const REGEN_RATE := 3.0          ## salud/s

var terrain: PlanetTerrain
var body_def: BodyDef
var first_person := true
var flying := false
var fly_speed := 50.0
var frozen := true
var gravity_mps2 := 0.0
var altitude_m := 0.0
var ground_clamps := 0
var look_pitch := 0.0            ## rad, negativo = abajo
var head_yaw := 0.0              ## rad, mirada libre respecto al cuerpo
var exertion := 0.1              ## 0..1 (respiración, cámara)
var turn_rate := 0.0             ## rad/s del cuerpo (suavizado)
var running := false

var rig: AstronautRig
var cam: BodyCamera
var helmet: HelmetOverlay
var hud: HelmetHud
var screen_fx: ScreenFx
var audio: SuitAudio
var _collision: CollisionShape3D
var _yaw_accum := 0.0
var look_rate := Vector2.ZERO     ## velocidad angular de la vista (yaw, pitch), rad/s
var _prev_pitch := 0.0
var _prev_head_yaw := 0.0
var sun_light := 1.0              ## iluminación solar aproximada (la fija el mundo)
var sun_dir := Vector3.UP         ## dirección hacia el Sol en el marco del motor (la fija el mundo)
var focusing := false             ## clic derecho mantenido (enfoque)
var lean_amount := 0.0            ## -1 (izquierda) .. 1 (derecha), suavizado
var _lean_limit := Vector2(1.0, 1.0)  ## límite por colisión (izquierda, derecha)
var _sun_blocked := false
var _was_on_floor := true
var _pre_move_vertical := 0.0
var gravity_vec := Vector3.ZERO   ## gravedad sentida (marco del motor)

# --- Ingravidez / caída libre, salud
var floating := false             ## orientación libre (ingravidez o caída libre)
var ang_vel := Vector3.ZERO       ## velocidad angular del cuerpo al flotar (marco del motor, rad/s)
var jet_fuel := 1.0               ## 0..1
var jet_active := 0.0             ## 0..1 empuje actual (sonido/cámara)
var dizziness := 0.0              ## 0..1 (al llegar a 1, desmayo)
var health := 100.0
var atmo: AtmosphereModel = null   ## atmósfera del cuerpo dominante (la fija el mundo)
const SUIT_PRESSURE_MAX := 5.0e5   ## Pa: el traje aguanta hasta 5 bar (FICTICIO)
const SUIT_TEMP_MAX := 600.0       ## K
var input_blocked := false        ## un panel (música) tiene el teclado: no se camina ni se pilota
var move_locked := false          ## secuencia del prólogo (cápsula): se mira pero no se camina (ADR-043)
var cinematic := false            ## mensaje obligatorio: sólo se puede mirar (se omite con Espacio)
var in_habitat := false           ## dentro de la base presurizada: iluminación interior, sin visor
var suit_on := true               ## traje EVA puesto (el prólogo empieza sin él: visor e interfaz ocultos)
var _since_damage := 99.0
var _air_time := 0.0
var _exit_spin := Vector3.ZERO
var _exit_spin_t := 0.0
var close_focus := false          ## mirando algo cercano (< 1,2 m): enfoque de instrumentos

# --- Naves
var ships: Array = []             ## naves del mundo (las fija el mundo; sin referencias globales)
var aboard: Ship = null           ## nave en cuyo interior está (gravedad artificial)
var seated := false               ## sentado en un asiento de `aboard`
var seat_id := ""                 ## asiento ocupado ("piloto", "copiloto"...)
var pilot_input := ShipPilotInput.new()
var pin := PlayerInput.for_slot(0)   ## controles de ESTE jugador (ADR-032)
var drives_origin := true          ## sólo el jugador anfitrión mueve el origen flotante (cooperativo)
var view: Node = null              ## su ViewManager (lo fija el mundo)
var world: Node = null             ## SurfaceWorld (lo fija el mundo; en el cooperativo no es el padre)
var exploration_hud: ExplorationHud = null   ## avisos, escáner y menú rápido de este jugador
var interaction_hint := ""        ## acción disponible con la tecla de interactuar (F / X), sin la tecla
var helmet_enabled := true        ## interior del casco visible en 1ª persona (se puede ocultar para capturas)


func _init() -> void:
	add_to_group(FloatingOriginService.GROUP)
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.4
	floor_constant_speed = true
	floor_stop_on_slope = true
	collision_layer = Layers.bit(Layers.PHYS_ASTRONAUT)
	collision_mask = Layers.solid_mask()
	# El traslado sobre naves es explícito (Ship → carry). Se desactiva la herencia de velocidad de
	# plataformas de CharacterBody3D, que sumaría la velocidad de la nave por segunda vez.
	platform_floor_layers = 0
	platform_wall_layers = 0
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
	var shape := CapsuleShape3D.new()
	shape.radius = Units.ASTRONAUT_RADIUS_M
	shape.height = Units.ASTRONAUT_HEIGHT_M
	_collision = CollisionShape3D.new()
	_collision.shape = shape
	_collision.position = Vector3(0, Units.ASTRONAUT_HEIGHT_M * 0.5, 0)
	add_child(_collision)

	rig = AstronautRig.new()
	rig.name = "Body"
	rig.astro = self
	add_child(rig)
	cam = BodyCamera.new()
	cam.name = "Cameras"
	add_child(cam)
	helmet = HelmetOverlay.new()
	add_child(helmet)
	hud = HelmetHud.new()
	hud.astro = self
	add_child(hud)
	screen_fx = ScreenFx.new()
	screen_fx.astro = self
	add_child(screen_fx)
	audio = SuitAudio.new()
	add_child(audio)


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON  # se mueve en pasos de física (ADR-042)
	cam.setup(self, rig)
	rig.footstep.connect(audio.footstep)
	landed.connect(rig.on_landed)
	landed.connect(cam.on_landed)
	landed.connect(_on_landed)
	_apply_camera()


## Asigna el jugador (0 = anfitrión con teclado y ratón, 1 = segundo jugador con mando).
func set_player_slot(slot: int, uses_mouse: bool = true) -> void:
	pin = PlayerInput.for_slot(slot)
	pin.uses_mouse = uses_mouse
	drives_origin = slot == 0
	rig.head_slot = slot
	rig.set_interior(aboard != null or in_habitat)
	rig.apply_profile(GameSettings.profile(slot))


# --- Emotes (ADR-035) ------------------------------------------------------------------------

const EMOTES := ["wave", "dance", "dance2", "cheer", "point"]
const EMOTE_NAMES := {"wave": "Saludar", "dance": "Bailar", "dance2": "Baile robot", "cheer": "Celebrar", "point": "Señalar"}
const EMOTE_TIME := {"wave": 3.0, "cheer": 3.5, "point": 2.5}   ## los bailes duran hasta que te mueves
var emote := ""
var _emote_t := 0.0
var _emote_restore_fp := false


func play_emote(e: String) -> void:
	if seated or flying or floating or not EMOTES.has(e):
		return
	if emote == e:
		stop_emote()
		return
	emote = e
	_emote_t = 0.0
	if first_person:
		_emote_restore_fp = true
		first_person = false
		_apply_camera()
	GameAudio.play("emote", -6.0)


func stop_emote() -> void:
	if emote == "":
		return
	emote = ""
	if _emote_restore_fp:
		_emote_restore_fp = false
		first_person = true
		_apply_camera()


func _update_emote(delta: float) -> void:
	if emote == "":
		return
	_emote_t += delta
	var moving := not input_blocked and (_input_dir().length() > 0.2 or pin.pressed(&"jump"))
	if moving or seated or floating or flying or _emote_t > float(EMOTE_TIME.get(emote, 1.0e9)):
		stop_emote()


func setup(p_terrain: PlanetTerrain, p_body: BodyDef) -> void:
	terrain = p_terrain
	body_def = p_body
	audio.has_atmosphere = body_def.has_atmosphere()


func active_camera() -> Camera3D:
	return cam.current_camera()


func position_bf() -> DVec3:
	return FloatingOrigin.to_global(global_position)


func set_look_pitch(p: float) -> void:
	look_pitch = clampf(p, -PITCH_LIMIT, PITCH_LIMIT)


func _apply_camera() -> void:
	cam.motion_intensity = GameSettings.camera_motion
	cam.apply(first_person, GameSettings.fov)
	mode_changed.emit()


func set_flying(on: bool) -> void:
	flying = on
	_collision.disabled = on
	velocity = Vector3.ZERO
	if not on:
		_clamp_to_ground(0.2)
	mode_changed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if exploration_hud != null and exploration_hud.menu_open():
		exploration_hud.menu_input(event)
		return
	if input_blocked or not pin.owns(event):
		return
	if cinematic:
		var rel0 := pin.mouse_motion(event)
		if rel0 != Vector2.ZERO:
			_look(rel0)
		return
	if pin.event_pressed(event, &"interact"):
		_interact()
		return
	var rel := pin.mouse_motion(event)
	if rel != Vector2.ZERO:
		_look(rel)
		return
	if seated:
		_seated_input(event)
		return
	if pin.event_pressed(event, &"recall_ship"):
		_recall_ship()
	elif pin.event_pressed(event, &"party_mode") and aboard != null:
		aboard.cmd_toggle_party()
	elif pin.event_pressed(event, &"toggle_camera"):
		first_person = not first_person
		_apply_camera()
	elif pin.event_pressed(event, &"toggle_fly"):
		set_flying(not flying)
	elif pin.event_pressed(event, &"speed_up"):
		if flying:
			fly_speed = clampf(fly_speed * 2.0, FLY_SPEED_MIN, FLY_SPEED_MAX)
		elif not first_person:
			cam.zoom(0.85)
	elif pin.event_pressed(event, &"speed_down"):
		if flying:
			fly_speed = clampf(fly_speed * 0.5, FLY_SPEED_MIN, FLY_SPEED_MAX)
		elif not first_person:
			cam.zoom(1.18)
	elif _event_action(event) != "":
		action_requested.emit(_event_action(event))
	else:
		for i in 4:
			if pin.event_pressed(event, StringName("emote_%d" % (i + 1))):
				play_emote(["wave", "dance", "dance2", "cheer"][i])
				break


## Mirada con el ratón o con el stick (en píxeles de ratón equivalentes; PlayerInput.look_pixels).
func _look(rel: Vector2, from_pad: bool = false) -> void:
	if GameSettings.mouse_invert_y and not from_pad:
		rel.y = -rel.y
	if seated:
		# Sentado: clic derecho (o Alt / R3) gira la cabeza sin mover la nave; si no, el ratón apunta la nave.
		if not is_piloting() or seated_looking():
			var sens0 := GameSettings.mouse_sensitivity
			head_yaw = clampf(head_yaw - rel.x * sens0, -SEATED_LOOK_YAW, SEATED_LOOK_YAW)
			set_look_pitch(look_pitch - rel.y * sens0)
		elif not from_pad:
			pilot_input.on_mouse(rel)
		return
	if floating:
		# Flotando no hay "arriba": la vista gira todo el cuerpo (guiñada y cabeceo propios).
		var fs: float = GameSettings.mouse_sensitivity
		var b := global_transform.basis.orthonormalized()
		global_transform.basis = (Basis(b.y, -rel.x * fs) * Basis(b.x, -rel.y * fs) * b).orthonormalized()
		_yaw_accum += -rel.x * fs
		return
	# Al enfocar baja la sensibilidad en proporción al FOV (misma sensación angular).
	var sens: float = GameSettings.mouse_sensitivity * (cam.fp_camera.fov / maxf(cam.base_fov, 1.0) if first_person else 1.0)
	var dx: float = -rel.x * sens
	if pin.pressed(&"freelook"):
		head_yaw = clampf(head_yaw + dx, -FREELOOK_MAX_YAW, FREELOOK_MAX_YAW)
	else:
		rotate(global_transform.basis.y.normalized(), dx)
		_yaw_accum += dx
	set_look_pitch(look_pitch - rel.y * sens)


## Nombre de la acción de exploración que dispara el evento ("scan", "journal", "photo", "quick_menu").
func _event_action(event: InputEvent) -> String:
	for a in ["scan", "journal", "photo", "quick_menu", "beacon"]:
		if pin.event_pressed(event, StringName(a)):
			return a
	return ""


func _physics_process(delta: float) -> void:
	if terrain == null or body_def == null:
		return
	var p_bf := position_bf()
	var r := p_bf.length()
	altitude_m = r - terrain.ground_radius_at(p_bf)
	_update_health(delta)
	if seated:
		_seated_physics(delta)
		_update_exertion(delta)
		_sun_blocked = _is_sun_blocked(global_transform.basis.y)
		if drives_origin:
			FloatingOrigin.update_focus(global_position)
		return
	_update_aboard()
	var planet_up := p_bf.normalized().to_vector3()
	if aboard != null:
		# Gravedad aparente dentro de la nave: sustituye (no se suma) a la planetaria.
		gravity_vec = aboard.apparent_gravity(global_position + global_transform.basis.y * 0.9)
		gravity_mps2 = gravity_vec.length()
	elif in_habitat and world != null and world.base != null and world.base.artificial_gravity:
		# Base LF-01 con energía: gravedad artificial de 1 g en todo el interior (FICTICIO, como la de la nave; ronda 11).
		gravity_mps2 = 9.80665
		gravity_vec = -planet_up * gravity_mps2
	else:
		gravity_mps2 = body_def.gravity_at_distance(r)  # escalar en doble precisión
		gravity_vec = -planet_up * gravity_mps2
	var up := -gravity_vec / gravity_mps2 if gravity_mps2 > 1e-4 else planet_up
	_exit_spin_t = maxf(0.0, _exit_spin_t - delta)
	_air_time = 0.0 if is_on_floor() else _air_time + delta

	if floating:
		if flying or frozen or (aboard != null and gravity_mps2 >= ZERO_G):
			_set_floating(false)
	elif not flying and not frozen and (gravity_mps2 < ZERO_G \
			or (aboard == null and _air_time > 0.6 and altitude_m > FREEFALL_ALT)):
		_set_floating(true)

	if floating:
		_float(delta, planet_up)
	else:
		_align_to_up(up, delta)
		up_direction = up
		if frozen:
			velocity = Vector3.ZERO
		elif flying:
			_fly(delta, up)
		else:
			_walk(delta, up)
			if aboard == null:
				_clamp_to_ground(0.05)
			var on_floor := is_on_floor()
			if on_floor and not _was_on_floor and _pre_move_vertical < -0.5:
				landed.emit(-_pre_move_vertical)
			_was_on_floor = on_floor
	if aboard != null:
		jet_fuel = minf(1.0, jet_fuel + 0.2 * delta)  # recarga a bordo
	audio.surface = "deck" if aboard != null else ("air" if audio.has_atmosphere else "vacuum")
	_update_dizziness(delta)
	_update_close_focus()
	_update_exertion(delta)
	_update_lean_limits()
	_sun_blocked = _is_sun_blocked(up)
	_update_interaction_hint()
	if drives_origin:
		FloatingOrigin.update_focus(global_position)


# --- Naves ---------------------------------------------------------------------------------

## Determina si el astronauta está dentro de alguna nave y gestiona la transición de marco.
func _update_aboard() -> void:
	var found: Ship = null
	var probe := global_position + global_transform.basis.y * 0.9
	for s in ships:
		if is_instance_valid(s) and ShipLayout.is_aboard(s.to_local(probe)):
			found = s
			break
	if found == aboard:
		return
	if aboard != null:
		# Sale: recupera la velocidad absoluta (relativa + la del punto de la nave).
		velocity += aboard.point_velocity(global_position)
		aboard.remove_passenger(self)
		if not aboard.state.landed:
			# Al soltarse de una nave en vuelo se hereda su giro, más el empujón descontrolado de la salida.
			var kick := clampf(0.5 + aboard.state.speed() / 80.0, 0.5, 1.3)
			_exit_spin = aboard.state.basis * aboard.state.ang_vel \
				+ Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * kick
			_exit_spin_t = 8.0
	aboard = found
	if aboard != null:
		velocity -= aboard.point_velocity(global_position)
		aboard.add_passenger(self)
	rig.set_interior(aboard != null or in_habitat)


## Sube a bordo de `s` en este mismo paso (teletransporte a la nave): misma transición que _update_aboard.
func board(s: Ship) -> void:
	if aboard == s:
		return
	if aboard != null:
		aboard.remove_passenger(self)
	aboard = s
	velocity = Vector3.ZERO
	s.add_passenger(self)
	rig.set_interior(true)
	if floating:
		_set_floating(false)


## La nave aplica su variación de transform a sus pasajeros antes de que se muevan (Ship._physics_process).
## Traslado preciso: pose relativa a la nave conservada (ADR-031).
func carry_relative(ship_xf: Transform3D, rel: Transform3D, rot: Basis) -> void:
	var xf := ship_xf * rel
	xf.basis = xf.basis.orthonormalized()
	global_transform = xf
	velocity = rot * velocity


func carry(delta_xf: Transform3D) -> void:
	var xf := delta_xf * global_transform
	xf.basis = xf.basis.orthonormalized()  # evita acumular error de redondeo paso a paso
	global_transform = xf
	velocity = delta_xf.basis.orthonormalized() * velocity


func _interact() -> void:
	if seated:
		_stand_up()
		return
	var sid := _near_seat()
	if sid != "":
		_sit_down(sid)
		return
	var st := _near_station()
	if st != "":
		action_requested.emit("station:" + str(ShipLayout.STATIONS[st][2]))
		return
	var it := _near_world_interaction()
	if not it.is_empty():
		it["provider"].interact(self, it["id"], it["kind"])


## Interactivo del mundo al alcance (terminales y puertas de la base LF-01; ADR-043) o {}.
func _near_world_interaction() -> Dictionary:
	if world == null or aboard != null:
		return {}
	for p in world.interact_providers:
		if not is_instance_valid(p):
			continue
		var it: Dictionary = p.nearest_interaction(self)
		if not it.is_empty():
			it["provider"] = p
			return it
	return {}


## Puesto interactivo al alcance (camas, camillas, laboratorio…) o "".
func _near_station() -> String:
	if aboard == null:
		return ""
	return aboard.nearest_station(aboard.to_local(global_position))


## Asiento libre al alcance (o "").
func _near_seat() -> String:
	if aboard == null:
		return ""
	return aboard.nearest_free_seat(aboard.to_local(global_position))


func is_piloting() -> bool:
	return seated and aboard != null and Ship.is_pilot_seat(seat_id)


func _update_interaction_hint() -> void:
	interaction_hint = ""
	var sid := _near_seat()
	if sid != "":
		interaction_hint = "Sentarse a pilotar" if Ship.is_pilot_seat(sid) else "Sentarse (%s)" % sid
		return
	var st := _near_station()
	if st != "":
		interaction_hint = str(ShipLayout.STATIONS[st][1])
		return
	if cinematic:
		return
	var it := _near_world_interaction()
	if not it.is_empty():
		interaction_hint = str(it["label"])


func _sit_down(sid: String = "piloto") -> void:
	if aboard == null or not aboard.sit(self, sid):
		return
	seat_id = sid
	seated = true
	flying = false
	if floating:
		_set_floating(false)
	_collision.disabled = true
	velocity = Vector3.ZERO
	look_pitch = -0.12
	head_yaw = 0.0
	pilot_input.stick = Vector2.ZERO
	if is_piloting():
		pilot_input.arcade = GameSettings.flight_mode == "arcade"
		aboard.set_arcade(pilot_input.arcade)
	global_transform = aboard.seat_transform(seat_id)
	interaction_hint = "Levantarse"
	GameAudio.play("sit", -6.0)
	mode_changed.emit()


func _stand_up() -> void:
	var ship := aboard
	var seat_xf := ship.seat_transform(seat_id)
	seated = false
	ship.stand(self)
	seat_id = ""
	# Detrás del asiento (los asientos miran a su −Z).
	global_transform = Transform3D(seat_xf.basis, seat_xf * Vector3(0, 0.05, 1.3))
	velocity = Vector3.ZERO
	head_yaw = 0.0
	_collision.disabled = false
	ship.add_passenger(self)
	interaction_hint = ""
	GameAudio.play("stand", -8.0)
	mode_changed.emit()


func _seated_physics(delta: float) -> void:
	if aboard == null:
		seated = false
		seat_id = ""
		_collision.disabled = false
		return
	gravity_vec = aboard.apparent_gravity(global_position + global_transform.basis.y * 0.9)
	gravity_mps2 = gravity_vec.length()
	up_direction = aboard.local_up()
	global_transform = aboard.seat_transform(seat_id)
	velocity = Vector3.ZERO
	if is_piloting():
		if input_blocked:
			aboard.controls.clear()
		else:
			pilot_input.fill(aboard.controls, delta, pin)
	interaction_hint = "Levantarse"


## Sentado: acciones discretas (la mirada la gestiona _look).
func _seated_input(event: InputEvent) -> void:
	if pin.event_pressed(event, &"party_mode"):
		aboard.cmd_toggle_party()
	elif _event_action(event) != "":
		action_requested.emit(_event_action(event))
	elif is_piloting():
		pilot_input.handle_event(event, aboard, self)
	elif pin.event_pressed(event, &"toggle_camera"):
		first_person = not first_person
		_apply_camera()


## ¿Mira alrededor sentado? Clic derecho o Alt (ratón) o R3 (mando). El gatillo izquierdo del mando NO cuenta:
## pilotando con mando es el freno.
func seated_looking() -> bool:
	return pin.pressed(&"freelook") or (pin.uses_mouse and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))


## Tecla B: llama a la nave más cercana (vuela hasta aquí y se posa cerca).
func _recall_ship() -> void:
	var best: Ship = null
	var best_d := INF
	for s in ships:
		if is_instance_valid(s):
			var d := global_position.distance_to(s.global_position)
			if d < best_d:
				best_d = d
				best = s
	if best == null:
		return
	if best == aboard:
		best.state.post_event("Ya estás a bordo")
		return
	if Net.is_client() and world != null and world.net != null and not world.net.is_ship_authority():
		var p := position_bf()
		Net.rpc_id(1, "request", "recall", [p.x, p.y, p.z])   # la nave la lleva el anfitrión (ADR-044)
		return
	best.cmd_recall(position_bf())


# --- Ingravidez y caída libre -------------------------------------------------------------

func _set_floating(on: bool) -> void:
	if on == floating:
		return
	floating = on
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING if on else CharacterBody3D.MOTION_MODE_GROUNDED
	if on:
		# La mirada pasa al cuerpo: sin "arriba", todo el cuerpo gira.
		var b := global_transform.basis.orthonormalized()
		global_transform.basis = (b * Basis(Vector3.UP, head_yaw) * Basis(Vector3.RIGHT, look_pitch)).orthonormalized()
		look_pitch = 0.0
		head_yaw = 0.0
		if _exit_spin_t > 0.0:
			ang_vel = _exit_spin
		elif aboard == null:
			ang_vel = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * 0.12
		_exit_spin_t = 0.0
	else:
		ang_vel = Vector3.ZERO
		jet_active = 0.0
		_was_on_floor = true
	mode_changed.emit()


func _float(delta: float, planet_up: Vector3) -> void:
	var b := global_transform.basis.orthonormalized()
	var fuel_use := 0.0
	var can_act := not input_blocked
	var inside := aboard != null  # dentro de la nave: asideros, sin gastar combustible
	# --- Rotación: se conserva el giro; Q/E alabean, X estabiliza (propulsores de actitud).
	if can_act and (inside or jet_fuel > 0.0):
		var roll := pin.axis(&"lean_right", &"lean_left")
		if absf(roll) > 0.0:
			ang_vel += b.z * roll * JET_ROLL_ACCEL * delta
			fuel_use += 0.5
		if pin.pressed(&"stabilize") and ang_vel.length() > 0.0:
			ang_vel = ang_vel.move_toward(Vector3.ZERO, JET_ROLL_ACCEL * 1.6 * delta)
			fuel_use += 0.6
	var w := ang_vel.length()
	if w > 1e-5:
		b = (Basis(ang_vel / w, w * delta) * b).orthonormalized()
		global_transform.basis = b
	_yaw_accum += ang_vel.dot(b.y) * delta
	# --- Traslación: gravedad (caída libre) + propulsores en ejes del cuerpo.
	var thrust := Vector3.ZERO
	if can_act and (inside or jet_fuel > 0.0):
		var input := _input_dir()
		thrust = b.x * input.x - b.z * input.y
		if pin.pressed(&"jump"):
			thrust += b.y
		if pin.pressed(&"crouch_down"):
			thrust -= b.y
		if thrust.length_squared() > 1.0:
			thrust = thrust.normalized()
		fuel_use += thrust.length()
	jet_active = lerpf(jet_active, clampf(fuel_use, 0.0, 1.0), 1.0 - exp(-10.0 * delta))
	if not inside:
		jet_fuel = maxf(0.0, jet_fuel - clampf(fuel_use, 0.0, 1.5) * delta / JET_FUEL_TIME)
	var pre := velocity + gravity_vec * delta + thrust * JET_ACCEL * (1.5 if inside else 1.0) * delta
	if inside:
		pre *= exp(-0.3 * delta)  # rozamiento con asideros/paredes
	velocity = pre
	move_and_slide()
	# --- Contactos: golpes y aterrizaje.
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		var v_in := -pre.dot(n)
		if v_in > 1.0:
			cam.add_trauma(clampf(v_in / 12.0, 0.1, 0.8))
			ang_vel += n.cross(pre).normalized() * minf(v_in * 0.08, 1.0) if n.cross(pre).length_squared() > 1e-6 else Vector3.ZERO
		if not inside and gravity_mps2 >= ZERO_G and n.dot(planet_up) > 0.5:
			_set_floating(false)
			if v_in > 0.5:
				landed.emit(v_in)
			return
	var r_before := position_bf().length()
	_clamp_to_ground(0.3)
	if position_bf().length() > r_before + 0.01:
		# Atravesó el suelo en un paso (caída muy rápida): impacto con la velocidad radial.
		var v_r := -pre.dot(planet_up)
		_set_floating(false)
		landed.emit(maxf(v_r, 0.0))


func _update_dizziness(delta: float) -> void:
	var w := ang_vel.length() if floating else 0.0
	if floating and w > 0.6:
		dizziness += (w - 0.6) * 0.1 * delta
	elif floating and aboard == null:
		dizziness += 0.004 * delta  # desorientación de la caída libre
	else:
		dizziness -= 0.12 * delta
	dizziness = clampf(dizziness, 0.0, 1.0)


# --- Salud --------------------------------------------------------------------------------

func apply_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	_since_damage = 0.0
	cam.add_trauma(clampf(amount / 40.0, 0.25, 1.0))
	damaged.emit(amount)


## Salud a 0: el traje falla; reaparición a bordo de la nave más cercana (FICTICIO, por jugabilidad).
func _respawn_in_ship() -> void:
	var best: Ship = null
	for s in ships:
		if is_instance_valid(s):
			best = s
			break
	health = 60.0
	_since_damage = 0.0
	if best == null:
		return
	if floating:
		_set_floating(false)
	global_transform = best.global_transform * Transform3D(Basis(), ShipLayout.SEAT_EXIT)
	velocity = Vector3.ZERO
	best.state.post_event("Traje dañado: rescatado a bordo de la nave")


func _on_landed(impact_speed: float) -> void:
	if impact_speed > SAFE_IMPACT:
		apply_damage((impact_speed - SAFE_IMPACT) * IMPACT_DAMAGE)


## Golpe de la nave (aterrizaje duro, choque): sacude y, si no vas sentado, puede hacer daño.
func on_ship_impact(strength: float) -> void:
	cam.add_trauma(clampf(strength * (0.25 if seated else 0.45), 0.05, 1.0))
	if not seated and strength > 1.0:
		apply_damage((strength - 1.0) * 22.0)


func _update_health(delta: float) -> void:
	_since_damage += delta
	# Traje: fuera de la nave, la presión o la temperatura extremas lo dañan (Venus, profundidades de los gigantes).
	# (FICTICIO: el traje aguanta cualquier atmósfera planetaria para poder explorarlas; ADR-031.)
	if health <= 0.0:
		_respawn_in_ship()
	if _since_damage > REGEN_DELAY:
		health = minf(100.0, health + REGEN_RATE * delta)


## Rayo corto hacia donde se mira: si hay algo a menos de 1,2 m (instrumentos), el enfoque se adapta.
func _update_close_focus() -> void:
	close_focus = false
	if not focusing:
		return
	var c := active_camera()
	var from := c.global_position
	var to := from - c.global_transform.basis.z * 1.2
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, Layers.solid_mask(), [get_rid()]))
	close_focus = not hit.is_empty()


func _process(delta: float) -> void:
	_pad_look(delta)
	# Velocidad de giro del cuerpo y de la vista (para alabeo de cámara, pasos al girar e inercia del casco).
	var yaw_rate := _yaw_accum / maxf(delta, 1e-4)
	_yaw_accum = 0.0
	turn_rate = lerpf(turn_rate, yaw_rate, 1.0 - exp(-10.0 * delta))
	var looking := pin.pressed(&"freelook") or (seated and seated_looking())
	if seated and not is_piloting():
		looking = true  # pasajero: la vista se queda donde la dejes
	if not looking:
		head_yaw = lerpf(head_yaw, 0.0, 1.0 - exp(-7.0 * delta))  # vuelve al centro al soltar
		if seated:
			look_pitch = lerpf(look_pitch, -0.12, 1.0 - exp(-4.0 * delta))
	running = not flying and is_on_floor() and velocity.length() > WALK_SPEED * 1.3
	focusing = pin.pressed(&"focus") and not seated and not input_blocked
	var lean_in := 0.0
	if not flying and not frozen and not floating and not input_blocked:
		lean_in = pin.axis(&"lean_left", &"lean_right")
	lean_in = clampf(lean_in, -_lean_limit.x, _lean_limit.y)
	lean_amount = lerpf(lean_amount, lean_in, 1.0 - exp(-7.0 * delta))
	if seated:
		global_transform = aboard.seat_transform(seat_id)
		lean_amount = 0.0
		rig.animate_seated(delta, look_pitch, head_yaw, pilot_input.stick, exertion)
	else:
		rig.animate(delta, look_pitch, head_yaw, turn_rate, is_on_floor() and not frozen and not floating,
			flying or floating, gravity_mps2, exertion, lean_amount)
		_update_emote(delta)
		rig.apply_emote(emote, _emote_t)
	cam.follow()
	cam.update(delta, look_pitch, head_yaw, turn_rate, running, exertion)
	var rate := Vector2(turn_rate + (head_yaw - _prev_head_yaw) / maxf(delta, 1e-4),
		(look_pitch - _prev_pitch) / maxf(delta, 1e-4))
	look_rate = look_rate.lerp(rate, 1.0 - exp(-12.0 * delta))
	_prev_pitch = look_pitch
	_prev_head_yaw = head_yaw
	# Visor bajado sólo fuera de la nave: a bordo (presurizada) se levanta y desaparece su interfaz.
	# Bajo una atmósfera densa (Venus, Titán) el Sol es un resplandor difuso: el visor no se oscurece ni deja imagen
	# remanente (ronda 11: en 1ª persona el terreno de Venus se veía negro; en 3ª, sin visor, no).
	var glare := sun_light
	if atmo != null and atmo.present():
		glare *= clampf((atmo.light_fraction(altitude_m) - 0.35) / 0.5, 0.0, 1.0)
	helmet.update_view(delta, look_rate, glare, first_person and helmet_enabled and suit_on and aboard == null and not seated,
		active_camera(), sun_dir, cam.focus_zoom, _sun_blocked)
	audio.jet = jet_active
	audio.update(delta, exertion)


## Stick derecho: misma mirada que el ratón. Pilotando (sin mirar alrededor) el stick apunta la nave
## (lo lee ShipPilotInput.fill).
func _pad_look(delta: float) -> void:
	if input_blocked or frozen:
		return
	var px := pin.look_pixels(delta)
	if px == Vector2.ZERO:
		return
	if is_piloting() and not seated_looking():
		return
	_look(px, true)


## Limita el asomado si hay algo a los lados a la altura de la cabeza (rocas, paredes).
func _update_lean_limits() -> void:
	var space := get_world_3d().direct_space_state
	var b := global_transform
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var from := b * Vector3(0, 1.55, 0)
		var to := b * Vector3(side * 0.6, 1.55, 0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, Layers.solid_mask(), [get_rid()]))
		var limit := 1.0
		if not hit.is_empty():
			limit = clampf((from.distance_to(hit["position"]) - 0.25) / 0.35, 0.0, 1.0)
		_lean_limit[i] = limit


## El Sol está tapado si está bajo el horizonte geométrico o un relieve cercano con colisión lo oculta.
func _is_sun_blocked(up: Vector3) -> bool:
	if sun_dir.dot(up) < -0.01:
		return true
	var eye := active_camera().global_position
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + sun_dir * 3000.0, Layers.solid_mask(), [get_rid()]))
	return not hit.is_empty()


func _update_exertion(delta: float) -> void:
	var target := 0.1
	if floating:
		target = 0.25 + jet_active * 0.2 + dizziness * 0.4
	elif not flying and not frozen:
		var v := velocity.length()
		target = clampf(0.1 + v / (RUN_SPEED * Gait.max_speed_factor(gravity_mps2)) * 0.75, 0.1, 0.9)
	var rate := 0.12 if target > exertion else 0.05
	exertion = move_toward(exertion, target, rate * delta)


## Reorienta el cuerpo hacia `up` girando lo mínimo. Con `delta` > 0 lo hace a ritmo limitado (cambio
## de postura al inclinarse la gravedad o al recuperar el equilibrio tras flotar).
func _align_to_up(up: Vector3, delta: float = 0.0) -> void:
	var b := global_transform.basis.orthonormalized()
	var cur := b.y
	var d := cur.dot(up)
	if d > 0.9999999:
		return
	var q: Quaternion
	if d < -0.9999:
		q = Quaternion(b.x.normalized(), PI)  # de cabeza: media vuelta alrededor del eje lateral del cuerpo
	else:
		q = Quaternion(cur, up)
	if delta > 0.0:
		var angle := acos(clampf(d, -1.0, 1.0))
		var max_step := POSTURE_RATE * delta * (1.0 + angle * 1.5)
		if angle > max_step:
			q = Quaternion.IDENTITY.slerp(q, max_step / angle)
	global_transform.basis = (Basis(q) * b).orthonormalized()


func _input_dir() -> Vector2:
	if move_locked or cinematic:
		return Vector2.ZERO
	return pin.vector(&"move_left", &"move_right", &"move_back", &"move_forward")


## Dentro o fuera de la base (LunarBase lo llama al cambiar de sala): capas de luz interiores y visor.
func set_habitat(on: bool) -> void:
	in_habitat = on
	rig.set_interior(on or aboard != null)


func _walk(delta: float, up: Vector3) -> void:
	var input := _input_dir() if not input_blocked else Vector2.ZERO
	var b := global_transform.basis
	var wish := b.x * input.x - b.z * input.y
	wish -= up * wish.dot(up)
	if wish.length_squared() > 1e-6:
		wish = wish.normalized()
	var v_vert := up * velocity.dot(up)
	var v_hor := velocity - v_vert
	if is_on_floor():
		var factor := Gait.max_speed_factor(gravity_mps2)
		var speed := (RUN_SPEED * factor) if pin.pressed(&"sprint") else WALK_SPEED
		if input.y < -0.1:
			speed *= 0.6  # hacia atrás se camina más despacio

		# Tracción limitada por la gravedad: en cuerpos de baja gravedad se acelera más despacio.
		var accel := clampf(1.6 * gravity_mps2, 2.5, 14.0)
		v_hor = v_hor.move_toward(wish * speed * minf(input.length(), 1.0), accel * delta)
		v_vert = Vector3.ZERO
		if pin.just_pressed(&"jump") and not input_blocked and not move_locked and not cinematic:
			v_vert = up * JUMP_TAKEOFF_SPEED
			exertion = minf(1.0, exertion + 0.08)
	else:
		v_hor += wish * AIR_CONTROL_ACCEL * delta
	v_vert -= up * gravity_mps2 * delta
	velocity = v_hor + v_vert
	_pre_move_vertical = velocity.dot(up)
	move_and_slide()


func _fly(delta: float, up: Vector3) -> void:
	var input := _input_dir()
	var cam_basis := active_camera().global_transform.basis
	var dir := cam_basis.x * input.x - cam_basis.z * input.y
	if pin.pressed(&"jump"):
		dir += up
	if pin.pressed(&"crouch_down"):
		dir -= up
	if dir.length_squared() > 1e-6:
		dir = dir.normalized()
	var speed := fly_speed * (4.0 if pin.pressed(&"sprint") else 1.0)
	velocity = dir * speed
	global_position += velocity * delta
	_clamp_to_ground(0.5)


## Salvaguarda: nunca más de GROUND_CLAMP_TOLERANCE bajo el terreno analítico.
func _clamp_to_ground(lift: float) -> void:
	var p_bf := position_bf()
	var ground_r := terrain.ground_radius_at(p_bf)
	var r := p_bf.length()
	var tolerance := 0.0 if flying else GROUND_CLAMP_TOLERANCE
	if r < ground_r - tolerance:
		var target := p_bf.normalized().mul(ground_r + lift)
		global_position = FloatingOrigin.to_local(target)
		var up := p_bf.normalized().to_vector3()
		var vu := velocity.dot(up)
		if vu < 0.0:
			velocity -= up * vu
		if not flying:
			ground_clamps += 1


## Coloca al astronauta de pie sobre el terreno en la dirección dada (marco BF).
func place_on_surface(dir: DVec3, lift: float = 0.3) -> void:
	var d := dir.normalized()
	var ground_r := terrain.radius + terrain.height_at_dir(d)
	var p := d.mul(ground_r + lift)
	if drives_origin:
		FloatingOrigin.reset(p)
		global_position = Vector3.ZERO
	else:
		global_position = FloatingOrigin.to_local(p)   # jugador 2: el origen es del anfitrión
	velocity = Vector3.ZERO
	var up := d.to_vector3()
	var fwd := -global_transform.basis.z
	fwd -= up * fwd.dot(up)
	if fwd.length_squared() < 1e-6:
		fwd = Vector3.UP - up * up.dot(Vector3.UP)  # mirar al norte local
		if fwd.length_squared() < 1e-6:
			fwd = Vector3.FORWARD - up * up.dot(Vector3.FORWARD)
	fwd = fwd.normalized()
	global_transform.basis = Basis(up.cross(-fwd).normalized(), up, -fwd).orthonormalized()
	_was_on_floor = true
	reset_physics_interpolation()  # teletransporte: sin estela interpolada (ADR-042)


## Rumbo (grados, 0 = norte, 90 = este) de la dirección de la vista sobre el plano tangente.
func heading_deg() -> float:
	var up := global_transform.basis.y
	var fwd := (-global_transform.basis.z).rotated(up, head_yaw)
	var north := Vector3.UP - up * up.dot(Vector3.UP)
	if north.length_squared() < 1e-8:
		return 0.0
	north = north.normalized()
	var east := north.cross(up)
	return fposmod(rad_to_deg(atan2(fwd.dot(east), fwd.dot(north))), 360.0)
