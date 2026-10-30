class_name SurfaceWorld
extends Node3D
## Escena de exploración de superficie: terreno + astronauta + nave + cielo + HUD + pausa.
## Todo se ejecuta en el marco BF del cuerpo con origen flotante (ADR-003).
## Las naves y los astronautas se guardan en listas (no hay un "jugador" global; ADR-015).

signal exit_to_menu

const READY_TIMEOUT_MS := 60000  ## tiempo real máximo de espera del terreno inicial
const SHIP_SPAWN_DISTANCE := 48.0  ## m al este del punto de aparición (la punta del ala queda a ~28 m)
const SHIP_PARAMS := "res://data/ships/explorer.json"

var body: BodyDef
var catalog: BodyCatalog
var system: SolarSystem = null    ## Sistema Solar (null en mundos ficticios); ADR-024
var spawn_lat := 12.0
var spawn_lon := 31.0
var interactive := true  ## false en pruebas automáticas (sin ratón capturado ni menús)
var coop := false        ## cooperativo local a pantalla dividida (ADR-032)
const COOP_DEPART_ALT := 600.0     ## m: por encima, la nave "se va" y sube a bordo quien esté fuera
const COOP_MAX_APART_M := 20000.0  ## a pie: separación máxima (precisión de 32 bits con un solo origen flotante)

var terrain: PlanetTerrain
var player: Astronaut
var env: SkyEnvironment
var hud: DebugHud
var pause_menu: PauseMenu
var view: ViewManager
var pilot_hud: PilotHud
var music_panel: MusicPanel
var map_panel: MapPanel
var nav_target := ""              ## destino marcado en el mapa (también sin pilotar)
var atmo: AtmosphereModel         ## atmósfera del cuerpo dominante (ADR-029)
var ships: Array = []
var astronauts: Array = []
var players: Array = []          ## astronautas controlados por jugadores locales (0 = anfitrión)
var views: Array = []            ## ViewManager de cada jugador
var pilot_huds: Array = []
var coop_views: Array = []       ## CoopViewport de cada jugador (vacío en solitario)
var exploration := ExplorationLog.new()   ## diario (ADR-034); se guarda con la partida
var exploration_ctl: ExplorationController
var journal: JournalPanel
var clouds: CloudField
var prof := {}                    ## tiempos por sistema del último fotograma (sonda de rendimiento)
var _split: CanvasLayer
var ship: Ship
var spawn_ship := true
var wait_started_ms := 0
var _anchor_timer := 0.0
signal anchor_changed(body_id: String)
var surface_ready := false
var new_game := false             ## partida nueva: empieza el prólogo en la base LF-01 (ADR-043)
var base: LunarBase = null        ## base lunar de MacSpaces (sólo en la Luna)
var prologue: PrologueDirector = null
var dialogue: DialogueDirector = null
var story_hud: StoryHud = null
var interact_providers: Array = []   ## objetos con nearest_interaction/interact (la base)
var net: NetWorld = null          ## sincronización en línea (ADR-044)
var nexus: NexusQuest = null      ## componentes del NEXUS (ronda 11)
var net_hold := false             ## inicio coordinado en línea: todos quietos hasta que el anfitrión da la salida (ADR-047)
var beacons: BeaconManager = null ## balizas de exploración (ronda 11)


func setup(p_body: BodyDef, lat: float, lon: float, p_coop: bool = false) -> void:
	body = p_body
	spawn_lat = lat
	spawn_lon = lon
	coop = p_coop


func _ready() -> void:
	var preset := GameSettings.coop_preset() if coop else GameSettings.preset()
	terrain = PlanetTerrain.new()
	terrain.name = "PlanetTerrain"
	terrain.setup(body, int(preset["terrain_segments"]), float(preset["split_factor"]), int(preset["max_jobs"]))
	add_child(terrain)

	if catalog != null and body.in_system():
		system = SolarSystem.from_catalog(catalog)
	atmo = AtmosphereModel.for_body(body)
	env = SkyEnvironment.new()
	env.name = "Sky"
	add_child(env)
	env.setup(body, bool(preset["shadows"]), system)
	if body.id == "moon":
		base = LunarBase.new()
		base.setup(self)
		add_child(base)
		interact_providers.append(base)

	var parents: Array = [self]
	if coop:
		parents = _build_split()
	for i in parents.size():
		var a := Astronaut.new()
		a.name = "Astronaut" if i == 0 else "Astronaut%d" % (i + 1)
		parents[i].add_child(a)
		a.set_player_slot(i, i == 0)
		a.world = self
		a.setup(terrain, body)
		a.atmo = AtmosphereModel.for_body(body)
		players.append(a)
		astronauts.append(a)
	player = players[0]
	if new_game and base != null:
		_place_in_capsules()
		if spawn_ship:
			_spawn_ship_in_hangar()
	else:
		player.place_on_surface(CubeSphere.latlon_to_dir(spawn_lat, spawn_lon))
		if spawn_ship:
			_spawn_ship_near_player()
		for i in range(1, players.size()):
			_place_beside_host(players[i], 2.5 * i)
	for a in players:
		a.ships = ships
	wait_for_surface()

	for i in players.size():
		var v := ViewManager.new()
		v.name = "View" if i == 0 else "View%d" % (i + 1)
		v.world = self
		v.astronaut = players[i]
		parents[i].add_child(v)
		v.set_world_environment(env.world_env.environment)
		players[i].view = v
		views.append(v)
		var ph := PilotHud.new()
		ph.astronaut = players[i]
		parents[i].add_child(ph)
		pilot_huds.append(ph)
	view = views[0]
	pilot_hud = pilot_huds[0]
	music_panel = MusicPanel.new()
	music_panel.astronaut = player
	add_child(music_panel)
	if system != null:
		map_panel = MapPanel.new()
		map_panel.world = self
		add_child(map_panel)
	for s in ships:
		s.music.listener = player
	exploration_ctl = ExplorationController.new()
	exploration_ctl.name = "Exploracion"
	add_child(exploration_ctl)
	exploration_ctl.setup(self, exploration)
	# Siempre (no sólo con la base): también suenan los registros del NEXUS en otros mundos (ronda 12).
	dialogue = DialogueDirector.new()
	dialogue.name = "Dialogos"
	add_child(dialogue)
	story_hud = StoryHud.new()
	story_hud.world = self
	story_hud.dialogue = dialogue
	add_child(story_hud)
	if base != null:
		prologue = PrologueDirector.new()
		prologue.name = "Prologo"
		add_child(prologue)
		prologue.setup(self, base, dialogue, story_hud)
		if new_game:
			prologue.start_new()
		else:
			prologue.start_skipped()
	beacons = BeaconManager.new()
	beacons.name = "Balizas"
	add_child(beacons)
	beacons.setup(self, exploration)
	if system != null:
		nexus = NexusQuest.new()
		nexus.name = "Nexus"
		add_child(nexus)
		nexus.setup(self, exploration)
	if Net.is_online():
		net = NetWorld.new()
		net.name = "Red"
		add_child(net)
		net.setup(self)
	var amb := AmbientAudio.new()
	amb.name = "Ambiente"
	amb.world = self
	add_child(amb)
	journal = JournalPanel.new()
	journal.log = exploration
	journal.world = self
	add_child(journal)

	hud = DebugHud.new()
	hud.world = self
	add_child(hud)
	if interactive:
		var ls := LoadingScreen.new()
		ls.world = self
		add_child(ls)

	if interactive:
		pause_menu = PauseMenu.new()
		add_child(pause_menu)
		pause_menu.resume_requested.connect(_resume)
		pause_menu.save_requested.connect(func():
			if Net.is_client():
				pause_menu.show_status("En línea sólo guarda el anfitrión")
			else:
				pause_menu.show_status("Partida guardada" if SaveGame.save(self) else "No se pudo guardar"))
		pause_menu.journal_requested.connect(func():
			_resume()
			open_journal(player))
		pause_menu.main_menu_requested.connect(func():
			get_tree().paused = false
			exit_to_menu.emit())
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Pantalla dividida: dos medias pantallas (lado a lado o arriba/abajo, según los ajustes) en una capa por
## debajo de los menús. Devuelve el SubViewport de cada jugador.
func _build_split() -> Array:
	_split = CanvasLayer.new()
	_split.name = "PantallaDividida"
	_split.layer = -1
	add_child(_split)
	var box: BoxContainer = HBoxContainer.new() if GameSettings.split_mode == "vertical" else VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.05, 0.08)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_split.add_child(bg)
	_split.add_child(box)
	var out := []
	for i in 2:
		var cv := CoopViewport.new(i)
		box.add_child(cv)
		coop_views.append(cv)
		out.append(cv.viewport)
	return out


## Coloca a un jugador junto al anfitrión (a su izquierda), en el suelo o dentro de la nave si el anfitrión
## va a bordo.
func _place_beside_host(a: Astronaut, offset: float) -> void:
	var host := player
	if host.aboard != null:
		_bring_aboard(a, host.aboard)
		return
	var b := host.global_transform.basis.orthonormalized()
	var p := FloatingOrigin.to_global(host.global_position - b.x * offset)
	a.global_transform.basis = b
	a.place_on_surface(p.normalized(), 0.3)
	a.velocity = Vector3.ZERO


## Teletransporta a un jugador al pasillo de la nave y lo registra como pasajero EN EL MISMO PASO (si no, una
## nave en marcha se alejaría antes de que el astronauta detectara que está dentro).
func _bring_aboard(a: Astronaut, s: Ship) -> void:
	if a.seated:
		a._stand_up()
	if a.flying:
		a.set_flying(false)
	var spot := ShipLayout.room_center("pasillo") + Vector3(0, 0.05, -2.0 + 1.2 * a.pin.slot)
	a.global_transform = Transform3D(s.global_transform.basis, s.global_transform * spot)
	a.velocity = Vector3.ZERO
	a.ang_vel = Vector3.ZERO
	a.board(s)
	if a.drives_origin:
		FloatingOrigin.update_focus(a.global_position)


## Cooperativo (ADR-032): nadie se queda atrás. A pie podéis separaros libremente; cuando la nave se va (sube
## de COOP_DEPART_ALT, viaja o enciende el motor lumínico), quien esté fuera sube a bordo automáticamente.
## Sólo si dos jugadores a pie se alejan más de COOP_MAX_APART_M (límite de precisión de un único origen
## flotante), el jugador 2 vuelve junto al anfitrión.
func _update_coop_group() -> void:
	if players.size() < 2:
		return
	var a: Astronaut = players[0]
	var b: Astronaut = players[1]
	terrain.set_secondary_focus(b.position_bf())
	var s := ship
	if s != null:
		var st := s.state
		var departing := not st.landed and (s.radar_altitude > COOP_DEPART_ALT or st.autopilot == ShipState.Autopilot.TRAVEL
			or st.light_active)
		var someone_aboard := a.aboard == s or b.aboard == s
		if departing and someone_aboard:
			for p in players:
				if p.aboard != s:
					_bring_aboard(p, s)
					st.post_event("Jugador %d a bordo: la nave despega" % (p.pin.slot + 1))
			return
	if a.aboard == null and b.aboard == null and a.global_position.distance_to(b.global_position) > COOP_MAX_APART_M:
		_place_beside_host(b, 2.5)
		if s != null:
			s.state.post_event("Jugador 2: demasiado lejos, vuelve junto al jugador 1")


## Congela a los astronautas sobre el suelo bajo su posición actual hasta que el terreno de
## alrededor esté generado con colisión (aparición, aterrizaje forzado, teletransporte).
func wait_for_surface() -> void:
	surface_ready = false
	wait_started_ms = 0
	for a in players:
		a.frozen = true
		if a.flying:
			a.set_flying(false)
		if a.aboard == null:
			a.place_on_surface(a.position_bf(), 0.3)
	terrain.set_focus(player.position_bf())
	pass


## Texto de la sala para el menú de pausa: jugadores y cómo invitar.
func _online_info() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("SALA «%s» · %s · %d/%d jugadores" % [Net.room_name, "anfitrión" if Net.is_host() else "invitado", Net.peers.size(), Net.max_players])
	var names := PackedStringArray()
	for id in Net.peers:
		names.append(str(Net.peers[id]["name"]) + (" (anfitrión)" if int(id) == 1 else ""))
	out.append("Jugadores: " + ", ".join(names))
	if Net.is_host():
		out.append("Red local: %s:%d" % [", ".join(Net.lan_ips), Net.port])
		if Net.public_ip != "":
			out.append("Por Internet: %s:%d (puerto abierto con UPnP)" % [Net.public_ip, Net.port])
		elif Net.upnp_state.begins_with("fallo"):
			out.append("UPnP no disponible: abre el puerto UDP %d o usad ZeroTier / Tailscale / Radmin VPN" % Net.port)
	return out


## Salida del inicio coordinado: todos los jugadores empiezan a la vez.
func release_hold() -> void:
	net_hold = false
	if surface_ready:
		for a in players:
			a.frozen = false


## Todos los astronautas presentes: los de este equipo y los remotos (en línea).
func all_people() -> Array:
	return astronauts + net.puppets.values() if net != null else astronauts


## Ficha de terminal para un jugador (local o remoto, ADR-044).
func show_card(a: Node, title: String, lines: Array) -> void:
	if a is Astronaut and a.exploration_hud != null:
		a.exploration_hud.show_card(title, PackedStringArray(lines), 11.0)
	elif net != null:
		net.send_card(a, title, lines)


func show_note(a: Node, text: String) -> void:
	if a is Astronaut and a.exploration_hud != null:
		a.exploration_hud.notify(text, UiTheme.DANGER)
	elif net != null:
		net.send_note(a, text)


## Ficha para todos los jugadores (también los remotos).
func show_card_all(title: String, lines: Array) -> void:
	for a in players:
		show_card(a, title, lines)
	if net != null and Net.is_host():
		Net.rpc("event", "card", [title, lines])


## Partida nueva (ADR-043): cada jugador despierta en una cápsula de la cámara criogénica, mirando al sur.
func _place_in_capsules() -> void:
	for i in players.size():
		place_in_pod(players[i], mini(i, BaseLayout.PODS.size() - 1))


## Coloca al astronauta dentro de la cápsula `i`, mirando hacia su puerta, y la reserva.
func place_in_pod(a: Astronaut, i: int) -> void:
	base.assign_pod(i)
	a.place_on_surface(base.point_bf(BaseLayout.CAPSULE_SPOTS[i]).normalized(), 0.05)
	var up := a.global_transform.basis.y
	var f := base.basis_bf * BaseLayout.pod_forward(i)
	var fwd := (f - up * f.dot(up)).normalized()
	a.global_transform.basis = Basis(up.cross(-fwd).normalized(), up, -fwd).orthonormalized()
	a.reset_physics_interpolation()


## La «Esperanza» descansa inmovilizada en el hangar de la base, morro al norte.
func _spawn_ship_in_hangar() -> void:
	var params := ShipParams.load_file(SHIP_PARAMS)
	for e in params.errors:
		push_error(e)
	ship = Ship.new()
	ship.name = "Kestrel"
	ship.setup(params, terrain, body)
	add_child(ship)
	ship.place_landed(base.point_bf(BaseLayout.SHIP_POINT).normalized(), -base.basis_bf.z)
	ship.takeoff_guard = base.takeoff_block_reason
	ship.crew_sources = astronauts
	ship.system = system
	ship.atmo = atmo
	ships.append(ship)


## Nave posada a SHIP_SPAWN_DISTANCE al este, con la esclusa (estribor) mirando al astronauta.
func _spawn_ship_near_player() -> void:
	var params := ShipParams.load_file(SHIP_PARAMS)
	for e in params.errors:
		push_error(e)
	ship = Ship.new()
	ship.name = "Kestrel"
	ship.setup(params, terrain, body)
	add_child(ship)
	var p := player.position_bf().normalized()
	var up := p.to_vector3()
	var north := (Vector3.UP - up * up.dot(Vector3.UP)).normalized()
	var east := north.cross(up).normalized()
	var dir := p.add(DVec3.from_vector3(east).mul(SHIP_SPAWN_DISTANCE / terrain.radius)).normalized()
	ship.place_landed(dir, -north)  # morro al sur → estribor (esclusa) hacia el oeste, hacia el jugador
	if base != null:
		ship.takeoff_guard = base.takeoff_block_reason
	ship.crew_sources = astronauts
	ship.system = system
	ship.atmo = atmo
	ships.append(ship)
	player.global_transform.basis = Basis(up.cross(-east).normalized(), up, -east).orthonormalized()


func _unhandled_input(event: InputEvent) -> void:
	if coop:
		_route_coop_input(event)
	if not interactive or GameSettings.ui_modal:
		return
	for a in players:
		if a.exploration_hud != null and a.exploration_hud.menu_open():
			return
	if event.is_action_pressed(&"pause") or (coop and event.is_action_pressed(&"p2_pause")):
		if get_tree().paused or pause_menu.visible:
			_resume()
		else:
			# En línea el mundo no se detiene (los demás siguen jugando): sólo se bloquean tus controles (ADR-044).
			if Net.is_online():
				player.input_blocked = true
				pause_menu.set_online_info(_online_info())
			else:
				get_tree().paused = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			pause_menu.open()
	elif event.is_action_pressed(&"toggle_all_ui"):
		GameSettings.ui_hidden = not GameSettings.ui_hidden
	elif event.is_action_pressed(&"time_faster"):
		env.time_scale = minf(env.time_scale * 10.0, 1.0e5)
	elif event.is_action_pressed(&"time_slower"):
		env.time_scale = maxf(env.time_scale / 10.0, 1.0)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Nubes 3D al atravesar una capa (CloudField): viento zonal del modelo y destellos de rayos.
func _update_clouds(cam: Camera3D, cam_bf: DVec3, delta: float) -> void:
	if clouds == null:
		clouds = CloudField.new()
		clouds.name = "Nubes"
		add_child(clouds)
	var alt := cam_bf.length() - terrain.radius
	var wind := Vector3.ZERO
	var light := 1.0
	if atmo != null and atmo.present():
		var up := cam_bf.normalized().to_vector3()
		var east := Vector3.UP.cross(up)
		east = east.normalized() if east.length_squared() > 1e-6 else Vector3.RIGHT
		wind = east * atmo.zonal_wind(asin(clampf(up.y, -1.0, 1.0)), alt)
		light = atmo.light_fraction(alt)
	clouds.update_field(cam, atmo, alt, light, wind, delta, env.flash_amount())


## Deja de dibujar el mundo 3D mientras un panel opaco (mapa, diario) cubre la pantalla: el rendimiento
## del panel no compite con el terreno y el cielo (la simulación sigue).
func set_render_paused(on: bool) -> void:
	get_tree().root.disable_3d = on and not coop
	for cv in coop_views:
		cv.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED if on else SubViewport.UPDATE_ALWAYS
	for v in views:
		v.render_paused = on


func open_journal(a: Astronaut) -> void:
	if journal != null and not journal.is_open():
		journal.open_for(a)


## Al cargar una partida: vuelve a sentar a quien estaba sentado (cuando ya consta a bordo).
func _resume_seats() -> void:
	for a in players:
		if not a.has_meta("resume_seat"):
			continue
		var seat := str(a.get_meta("resume_seat"))
		if seat == "":
			a.remove_meta("resume_seat")
		elif a.aboard != null:
			a.remove_meta("resume_seat")
			a._sit_down(seat)


## En el cooperativo los nodos de cada jugador viven en su SubViewport, que no recibe entrada (CoopViewport):
## se les entrega aquí. Cada uno filtra por su dispositivo (PlayerInput.owns / acciones con prefijo).
func _route_coop_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	for i in players.size():
		players[i]._unhandled_input(event)
		views[i]._unhandled_input(event)
		pilot_huds[i]._unhandled_input(event)


func _resume() -> void:
	pause_menu.close()
	get_tree().paused = false
	player.input_blocked = false
	player._apply_camera()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	var cam := view.active_camera() if view != null else player.active_camera()
	var cam_bf := FloatingOrigin.to_global(cam.global_position)
	terrain.set_focus(cam_bf)

	if not surface_ready:
		if wait_started_ms == 0:
			wait_started_ms = Time.get_ticks_msec()
		if terrain.is_ready_at_focus() or Time.get_ticks_msec() - wait_started_ms > READY_TIMEOUT_MS:
			surface_ready = true
			for a in players:
				if a.aboard == null:
					a.place_on_surface(a.position_bf(), 0.3)
				a.frozen = net_hold
			hud.set_status("")
	if coop and surface_ready:
		_update_coop_group()
	if surface_ready:
		_resume_seats()

	if system != null:
		_check_anchor(delta)
		cam_bf = FloatingOrigin.to_global(cam.global_position)
	var up := cam_bf.normalized().to_vector3()
	if system != null:
		system.time_scale = env.time_scale
		system.advance(delta)
	var px := deg_to_rad(cam.fov) / maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var t0 := Time.get_ticks_usec()
	env.update_for_observer(up, cam_bf.length() - terrain.radius, delta, cam_bf, px)
	var t1 := Time.get_ticks_usec()
	env.update_atmosphere(atmo, cam_bf.length() - terrain.radius, delta)
	_update_clouds(cam, cam_bf, delta)
	_update_helmet(delta, up)
	var t2 := Time.get_ticks_usec()
	prof["cielo_ms"] = (t1 - t0) / 1000.0
	prof["atmosfera_nubes_ms"] = (t2 - t1) / 1000.0
	prof["terreno_ms"] = terrain.last_process_usec / 1000.0


# --- Cambio de cuerpo dominante (ADR-027) ----------------------------------------------------

## Cuatro veces por segundo: si el sujeto (la nave si vas a bordo; si no, el astronauta) ha entrado en la esfera
## de influencia de otro cuerpo, todo el mundo pasa a su marco fijo.
func _check_anchor(delta: float) -> void:
	_anchor_timer -= delta
	if _anchor_timer > 0.0:
		return
	_anchor_timer = 0.25
	var subject_bf: DVec3 = ship.state.pos_bf if ship != null and player.aboard == ship else player.position_bf()
	var dom := system.dominant_body(system.to_system(subject_bf, body.id), body.id)
	if dom != body.id:
		set_anchor(dom)


## Cambia el marco de trabajo al cuerpo `new_id`: convierte naves y astronautas (posición en doble precisión,
## orientación y velocidad girada; las velocidades orbitales de los cuerpos NO se suman: compensación ficticia
## que evita saltos de decenas de km/s), recoloca el origen flotante y reconstruye terreno y cielo.
func set_anchor(new_id: String) -> void:
	var old_id := body.id
	var nb: BodyDef = system.body(new_id)
	if nb == null or new_id == old_id:
		return
	var rot := system.frame_rotation(old_id, new_id)
	# Astronautas (posición absoluta antes de mover el origen).
	var astro_bf := {}
	for a in astronauts:
		astro_bf[a] = system.convert_point(a.position_bf(), old_id, new_id)
	for s in ships:
		var st: ShipState = s.state
		st.pos_bf = system.convert_point(st.pos_bf, old_id, new_id)
		st.velocity = rot * st.velocity
		st.basis = (rot * st.basis).orthonormalized()
		st.autopilot_heading = rot * st.autopilot_heading
		st.autopilot_up = rot * st.autopilot_up
		st.autopilot_target = system.convert_point(st.autopilot_target, old_id, new_id)
		st.landed = false
	# Nuevo origen flotante en el sujeto.
	var focus_bf: DVec3 = ship.state.pos_bf if ship != null and player.aboard == ship else astro_bf[player]
	FloatingOrigin.reset(focus_bf)
	for a in astronauts:
		var xf: Transform3D = a.global_transform
		a.global_transform = Transform3D((rot * xf.basis).orthonormalized(), FloatingOrigin.to_local(astro_bf[a]))
		a.velocity = rot * a.velocity
	# Terreno y cielo del nuevo cuerpo.
	body = nb
	var preset := GameSettings.coop_preset() if coop else GameSettings.preset()
	terrain.queue_free()
	terrain = PlanetTerrain.new()
	terrain.name = "PlanetTerrain"
	terrain.setup(body, int(preset["terrain_segments"]), float(preset["split_factor"]), int(preset["max_jobs"]))
	add_child(terrain)
	var time_scale := env.time_scale
	env.queue_free()
	env = SkyEnvironment.new()
	env.name = "Sky"
	add_child(env)
	env.setup(body, bool(preset["shadows"]), system)
	env.time_scale = time_scale
	for v in views:
		v.set_world_environment(env.world_env.environment)
	atmo = AtmosphereModel.for_body(body)
	for a in astronauts:
		a.setup(terrain, body)
		a.atmo = atmo
	for s in ships:
		s.terrain = terrain
		s.body_def = body
		s.atmo = atmo
		s._sync_node()
	terrain.set_focus(focus_bf)
	if ship != null:
		ship.state.post_event("Ahora dominante: %s" % body.display_name)
	anchor_changed.emit(new_id)


const GAIT_NAMES := {Gait.Kind.IDLE: "quieto", Gait.Kind.WALK: "caminar", Gait.Kind.RUN: "correr", Gait.Kind.LOPE: "saltitos (lunar)"}


func _update_helmet(_delta: float, up: Vector3) -> void:
	var sun_elev := rad_to_deg(asin(clampf(env.sun_direction_bf().dot(up), -1.0, 1.0)))
	for a in players:
		a.sun_light = clampf(sun_elev / 20.0 + 0.3, 0.05, 1.0)
		a.sun_dir = env.sun_direction_bf()
		a.hud.sun_elevation_deg = sun_elev


func debug_text() -> String:
	var p_bf := player.position_bf()
	var ll := CubeSphere.dir_to_latlon(p_bf)
	var r := p_bf.length()
	var cam := player.active_camera()
	var lines := PackedStringArray()
	lines.append("FPS %d (%.1f ms) · llamadas de dibujo %d · primitivas %d" % [
		Engine.get_frames_per_second(), 1000.0 / maxf(1.0, Engine.get_frames_per_second()),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	lines.append("%s%s · R = %s · masa %s kg · g sup. = %.3f m/s²" % [
		body.display_name, " [FICTICIO]" if body.is_fictional() else " [datos reales, terreno procedural]",
		Units.format_distance(terrain.radius), String.num_scientific(body.mass_kg()), body.surface_gravity()])
	lines.append("Lat %.5f° · Lon %.5f° · altitud sobre terreno %s · sobre radio medio %s" % [
		ll.x, ll.y, Units.format_distance(player.altitude_m), Units.format_distance(r - terrain.radius)])
	lines.append("Modo: %s · cámara %s · velocidad %s · en suelo: %s · g local %.4f m/s²" % [
		("VUELO (%s)" % Units.format_speed(player.fly_speed)) if player.flying else ("flotando" if player.floating else "a pie"),
		"1ª persona" if player.first_person else "3ª persona",
		Units.format_speed(player.velocity.length()), "—" if player.flying else ("sí" if player.is_on_floor() else "no"),
		player.gravity_mps2])
	lines.append("Terreno: nodos %d · dibujados %d · nivel %d/%d · pendientes %d · colisiones %d · gen. %.1f ms/parche" % [
		terrain.stat_nodes, terrain.stat_drawn, terrain.stat_deepest, terrain.max_level,
		terrain.pending_count(), terrain.stat_colliders, terrain.stat_job_usec_avg / 1000.0])
	lines.append("Origen flotante: |offset| %s · recentrados %d · pos. local %s · near %.2f m far %s" % [
		Units.format_distance(FloatingOrigin.offset.length()), FloatingOrigin.shift_count,
		str(player.global_position.snapped(Vector3.ONE * 0.01)), cam.near, Units.format_distance(cam.far)])
	if ship != null:
		var st := ship.state
		lines.append("Nave: %s · %s · objetivo %s · %s · alt. radar %s · a bordo: %s · pasajeros %d" % [
			ship.regime_name(), ShipParams.format_speed(st.speed()), ShipParams.format_speed(st.target_speed),
			"posada" if st.landed else "en vuelo", Units.format_distance(ship.radar_altitude),
			"sí (asiento)" if player.seated else ("sí" if player.aboard != null else "no"), ship.passengers.size()])
	lines.append("Memoria: estática %.0f MB · vídeo %.0f MB · tiempo ×%.0f · salvaguardas de suelo %d" % [
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		env.time_scale, player.ground_clamps])
	lines.append("Astronauta: salud %.0f · combustible %.0f %% · mareo %.2f · giro %.2f rad/s" % [
		player.health, player.jet_fuel * 100.0, player.dizziness, player.ang_vel.length()])
	if Net.is_online():
		# Depuración de red y voz (ADR-046/047): estado de la sala, transmisiones, canales y distancias de voz.
		lines.append("Red: %s · sala «%s» · estado %s · %d jugadores · alcance de voz %.0f m" % [
			"anfitrión" if Net.is_host() else "invitado", Net.room_name, Net.lobby_state, Net.peers.size(), Voice.prox_range()])
		lines.append(Voice.debug_text())
		if net != null:
			for id in net.puppets:
				var pup: RemoteAstronaut = net.puppets[id]
				lines.append("  %s · %.1f m · voz: %s" % [pup.display_name, player.global_position.distance_to(pup.global_position),
					Voice.is_speaking(int(id)) if Voice.is_speaking(int(id)) != "" else "—"])
	return "\n".join(lines)
