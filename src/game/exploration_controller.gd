class_name ExplorationController
extends Node
## Acciones de exploración y de la nave (ADR-034). Atiende las peticiones de cada jugador
## (Astronaut.action_requested) y muestra el resultado en SU ExplorationHud:
## - Escáner (R / ▶): datos reales del cuerpo apuntado (o del que tienes debajo) → diario.
## - Muestras (R mirando al suelo, fuera de la nave): roca del lugar → se analiza en el laboratorio.
## - Foto (F12): captura de la vista de ese jugador en Imágenes/We Are Alone.
## - Menú rápido (Y / Select) y puestos de la nave: dormir, curarse, café, recargar el traje, laboratorio,
##   reparar el casco, diario.
## - Registro automático de visitas, distancia recorrida, tiempo de juego y guardado automático.

const AUTOSAVE_S := 180.0
const SLEEP_HOURS := 8.0
const SCAN_MIN_ANGLE := deg_to_rad(3.0)

var world: SurfaceWorld
var log: ExplorationLog
var huds := {}                    ## Astronaut -> ExplorationHud
var _autosave_t := 0.0
var _visit_t := 0.0
var _sample_cd := {}
var _busy := {}                   ## Astronaut -> true mientras duerme


func setup(p_world: SurfaceWorld, p_log: ExplorationLog) -> void:
	world = p_world
	log = p_log
	for a in world.players:
		var h := ExplorationHud.new()
		h.name = "ExplorationHud%d" % (a.pin.slot + 1)
		h.astro = a
		a.get_parent().add_child(h)
		a.exploration_hud = h
		huds[a] = h
		a.action_requested.connect(_on_action.bind(a))
	for a in world.players:
		huds[a].others = world.players.filter(func(o): return o != a)


func _process(delta: float) -> void:
	if world == null or not world.surface_ready or get_tree().paused:
		return
	log.play_time_s += delta
	if world.ship != null and not world.ship.state.landed:
		log.ship_distance_m += world.ship.state.speed() * delta
	_visit_t -= delta
	if _visit_t <= 0.0:
		_visit_t = 1.0
		_check_visits()
	if world.interactive:
		_autosave_t += delta
		if _autosave_t >= AUTOSAVE_S:
			_autosave_t = 0.0
			if SaveGame.save(world):
				huds[world.player].notify("Partida guardada automáticamente", UiTheme.TEXT_DIM)


func _check_visits() -> void:
	var b := world.body
	if b == null or not world.terrain.solid:
		return
	var landed_ship := world.ship != null and world.ship.state.landed
	for a in world.players:
		var on_ground: bool = a.aboard == null and not a.flying and a.is_on_floor()
		if on_ground or (landed_ship and a.aboard == world.ship):
			if log.mark_visit(b, true):
				for h in huds.values():
					h.notify("Primera visita: %s — anotada en el diario" % b.display_name, UiTheme.OK)
			return


func _on_action(action: String, a: Astronaut) -> void:
	if _busy.get(a, false):
		return
	match action:
		"scan":
			_scan_or_sample(a)
		"journal":
			world.open_journal(a)
		"photo":
			_photo(a)
		"quick_menu":
			_quick_menu(a)
		"beacon":
			if world.beacons != null:
				world.beacons.place(a)
		"station:sleep":
			_sleep(a)
		"station:heal":
			a.health = 100.0
			huds[a].notify("Tratamiento completado: salud al 100 %", UiTheme.OK)
		"station:coffee":
			a.exertion = 0.0
			huds[a].notify("Café recién hecho. Sabe mejor con estas vistas.")
		"station:refuel":
			a.jet_fuel = 1.0
			huds[a].notify("Propulsores del traje recargados al 100 %", UiTheme.OK)
		"station:lab":
			_lab(a)
		"station:repair":
			_repair(a)
		"station:journal":
			world.open_journal(a)


# --- Escáner y muestras --------------------------------------------------------------------

func _scan_or_sample(a: Astronaut) -> void:
	if a.aboard == null and not a.seated and world.terrain.solid and _ground_in_view(a):
		_take_sample(a)
	else:
		_scan(a)


func _ground_in_view(a: Astronaut) -> bool:
	var cam := a.view.active_camera() as Camera3D
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * 4.0
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.bit(Layers.PHYS_TERRAIN), [a.get_rid()])
	return not a.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _take_sample(a: Astronaut) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_sample_cd.get(a, -10000)) < 1500:
		return
	_sample_cd[a] = now
	var ll := CubeSphere.dir_to_latlon(a.position_bf())
	log.add_sample(world.body, ll)
	GameAudio.play("sample", -2.0)
	huds[a].notify("Muestra de %s recogida · %d sin analizar (laboratorio del almacén)" % [world.body.display_name, log.pending_samples()], UiTheme.OK)


## Cuerpo hacia el que mira la cámara (el de menor desviación angular respecto a su tamaño aparente).
func _scan_target(a: Astronaut) -> String:
	var sys := world.system
	if sys == null:
		return world.body.id
	var cam := a.view.active_camera() as Camera3D
	var fwd := -cam.global_transform.basis.z
	var cam_bf := FloatingOrigin.to_global(cam.global_position)
	var best := ""
	var best_score := INF
	for id in sys.bodies:
		var b: BodyDef = sys.body(id)
		var rel: DVec3 = sys.position_in_frame(id, world.body.id).sub(cam_bf)
		var d := rel.length()
		if d < 1.0:
			continue
		var dir := rel.mul(1.0 / d).to_vector3()
		var ang := acos(clampf(dir.dot(fwd), -1.0, 1.0))
		var ar := asin(clampf(b.radius_m() / d, 0.0, 1.0))
		if ang > maxf(ar * 1.15, SCAN_MIN_ANGLE):
			continue
		var score := maxf(ang - ar, 0.0) + (0.0 if b.kind != "moon_minor" else 0.02)
		if score < best_score:
			best_score = score
			best = id
	if best == "" and world.terrain.solid:
		best = world.body.id
	return best


func _scan(a: Astronaut) -> void:
	var id := _scan_target(a)
	if id == "":
		huds[a].notify("Escáner: no hay ningún cuerpo en la mira", UiTheme.TEXT_DIM)
		return
	var sys := world.system
	var b: BodyDef = sys.body(id) if sys != null else world.body
	var lines := PackedStringArray()
	if sys != null:
		var cam_bf := FloatingOrigin.to_global((a.view.active_camera() as Camera3D).global_position)
		var d := sys.position_in_frame(id, world.body.id).sub(cam_bf).length() - b.radius_m()
		lines.append("Distancia: %s (luz: %s)" % [Units.format_distance(maxf(d, 0.0)), MapPanel._duration(maxf(d, 0.0) / ShipParams.C)])
	var g := b.surface_gravity()
	lines.append("Radio %s · gravedad %.2f m/s² (%.2f g)" % [Units.format_distance(b.radius_m()), g, g / 9.80665])
	var rot := absf(b.physical("sidereal_rotation_period", 0.0))
	if rot > 0.0:
		lines.append("Rotación: %s%s" % [MapPanel._duration(rot), " (retrógrada)" if b.physical("sidereal_rotation_period", 0.0) < 0.0 else ""])
	var m := AtmosphereModel.for_body(b)
	if m.present():
		if m.kind == "gas_giant":
			lines.append("Atmósfera: %.0f K a 1 bar, sin superficie sólida" % m.temperature(0.0))
		else:
			lines.append("Atmósfera: %s bar, %.0f K en la superficie" % [String.num(m.pressure(0.0) / 1.0e5, 4), m.temperature(0.0)])
		var comp := str(b.atmosphere().get("composition", ""))
		if comp != "":
			lines.append("  " + comp.substr(0, 64))
	elif b.kind != "star":
		lines.append("Sin atmósfera apreciable")
	if sys != null:
		var nm: int = sys.children.get(id, []).size()
		if nm > 0:
			lines.append("Lunas conocidas: %d" % nm)
	GameAudio.play("scan", -4.0)
	var is_new := log.add_scan(b, lines)
	huds[a].show_card(b.display_name, lines)
	if is_new:
		huds[a].notify("Nuevo escaneo en el diario: %s" % b.display_name, UiTheme.OK)


# --- Foto ----------------------------------------------------------------------------------

func _photo(a: Astronaut) -> void:
	var was_hidden := GameSettings.ui_hidden
	GameSettings.ui_hidden = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := a.get_viewport().get_texture().get_image()
	GameSettings.ui_hidden = was_hidden
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	dir = ProjectSettings.globalize_path("user://fotos") if dir == "" else dir.path_join("We Are Alone")
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := dir.path_join("%s_%s.png" % [world.body.display_name, stamp])
	var err := img.save_png(path)
	GameAudio.play("photo", -2.0)
	huds[a].flash()
	if err == OK:
		log.photos += 1
		huds[a].notify("Foto guardada en %s" % dir, UiTheme.OK)
	else:
		huds[a].notify("No se pudo guardar la foto (%d)" % err, UiTheme.DANGER)


# --- Menú rápido ---------------------------------------------------------------------------

func _quick_menu(a: Astronaut) -> void:
	var items: Array = []
	var ship := world.ship
	var aboard := a.aboard != null
	var piloting := a.is_piloting()
	if world.system != null and world.map_panel != null:
		items.append({"label": "Mapa del Sistema Solar", "cb": func(): world.map_panel.open_for(a), "hint": a.pin.glyph(&"toggle_map")})
	items.append({"label": "Diario de exploración", "cb": func(): world.open_journal(a), "hint": a.pin.glyph(&"journal")})
	items.append({"label": "Escanear lo que miro", "cb": func(): _scan(a), "hint": a.pin.glyph(&"scan")})
	if piloting and ship != null:
		var nav := world.nav_target
		items.append({"label": "Viajar al destino marcado" + ("" if nav == "" else " (%s)" % world.system.body(nav).display_name),
			"cb": func(): ship.cmd_travel(nav), "enabled": nav != "" and nav != "sun"})
		items.append({"label": "Gravedad artificial: %s" % ("ON" if ship.state.artificial_gravity else "OFF"),
			"cb": func(): ship.cmd_toggle_artificial_gravity(), "hint": a.pin.glyph(&"ship_gravity")})
		items.append({"label": "Focos exteriores: %s" % ("ON" if ship.state.floodlights else "OFF"),
			"cb": func(): ship.cmd_toggle_floodlights(), "hint": a.pin.glyph(&"ship_floodlights")})
		items.append({"label": "Tren de aterrizaje: %s" % ("desplegado" if ship.state.gear_hold else "automático"),
			"cb": func(): ship.cmd_toggle_gear(), "hint": a.pin.glyph(&"ship_gear")})
	if aboard:
		items.append({"label": "Música de la nave", "cb": func(): world.music_panel.open_for(a),
			"hint": a.pin.glyph(&"music_panel") if a.seated else "siéntate", "enabled": a.seated})
		items.append({"label": "Modo fiesta: %s" % ("ON" if a.aboard.state.party else "OFF"), "cb": func(): a.aboard.cmd_toggle_party(),
			"hint": a.pin.glyph(&"party_mode")})
	elif ship != null:
		items.append({"label": "Llamar a la nave", "cb": func(): a._recall_ship(), "hint": a.pin.glyph(&"recall_ship")})
	if not a.seated:
		items.append({"label": "Cámara: %s" % ("1ª persona" if a.first_person else "3ª persona"), "cb": func():
			a.first_person = not a.first_person
			a._apply_camera(), "hint": a.pin.glyph(&"toggle_camera")})
	items.append({"label": "Hacer una foto", "cb": func(): _photo(a), "hint": a.pin.glyph(&"photo")})
	if world.beacons != null and not aboard and not a.seated:
		items.append({"label": "Plantar una baliza", "cb": func(): world.beacons.place(a), "hint": a.pin.glyph(&"beacon")})
	if not a.seated and not a.floating:
		items.append({"label": "Emotes…", "cb": func(): _emote_menu(a), "hint": "1-4" if a.pin.uses_mouse else ""})
	if a == world.player and world.interactive:
		items.append({"label": "Guardar partida", "cb": func():
			huds[a].notify("Partida guardada" if SaveGame.save(world) else "No se pudo guardar", UiTheme.OK)})
	huds[a].open_menu(items)


func _emote_menu(a: Astronaut) -> void:
	var items: Array = []
	var keys := ["1", "2", "3", "4", ""]
	for i in Astronaut.EMOTES.size():
		var e: String = Astronaut.EMOTES[i]
		items.append({"label": Astronaut.EMOTE_NAMES[e], "cb": func(): a.play_emote(e), "hint": keys[i] if a.pin.uses_mouse else ""})
	huds[a].open_menu(items)


# --- Puestos de la nave --------------------------------------------------------------------

func _sleep(a: Astronaut) -> void:
	var ship := world.ship
	if ship != null and not ship.state.landed and ship.state.speed() > 5.0:
		huds[a].notify("No es buen momento para dormir: la nave está en movimiento", UiTheme.DANGER)
		return
	_busy[a] = true
	a.input_blocked = true
	var h: ExplorationHud = huds[a]
	h.fade_out("Durmiendo %d horas…" % int(SLEEP_HOURS))
	while not h.is_black():
		await get_tree().process_frame
	if world.system != null:
		world.system.time_s += SLEEP_HOURS * 3600.0
	world.env.time_s += SLEEP_HOURS * 3600.0
	a.health = 100.0
	a.exertion = 0.0
	await get_tree().create_timer(1.2).timeout
	h.fade_in()
	a.input_blocked = false
	_busy[a] = false
	var date := Time.get_datetime_string_from_unix_time(int(world.system.time_s + Ephemeris.J2000_UNIX), true) if world.system != null else ""
	h.notify("Has dormido %d horas%s" % [int(SLEEP_HOURS), (" · fecha: %s UTC" % date.substr(0, 16)) if date != "" else ""])


func _lab(a: Astronaut) -> void:
	var n := 0
	var last := ""
	for s in log.samples:
		if bool(s["analyzed"]):
			continue
		var b: BodyDef = world.catalog.get_body(str(s["body"])) if world.catalog != null else world.body
		if b == null:
			b = world.body
		s["report"] = ExplorationLog.analyze(b, s)
		s["analyzed"] = true
		last = s["report"]
		n += 1
	if n == 0:
		huds[a].notify("No hay muestras sin analizar. Sal a recogerlas (%s mirando al suelo)" % a.pin.glyph(&"scan"), UiTheme.TEXT_DIM)
		return
	log.changed.emit()
	huds[a].show_card("Laboratorio", last.split("\n"), 12.0)
	huds[a].notify("%d muestra%s analizada%s · informes en el diario" % [n, "" if n == 1 else "s", "" if n == 1 else "s"], UiTheme.OK)


func _repair(a: Astronaut) -> void:
	var ship := world.ship
	if ship == null:
		return
	var st := ship.state
	var before := st.hull_integrity
	st.hull_integrity = 100.0
	var lines := PackedStringArray([
		"Casco: %.0f %% → 100 %%%s" % [before, " (reparado)" if before < 99.9 else ""],
		"Reactor: nominal · empuje disponible %d %%" % int(100),
		"Temperatura de la piel: %.0f K" % st.hull_temperature,
		"Gravedad artificial: %s" % ("activa" if st.artificial_gravity else "desactivada"),
		"Tren de aterrizaje: %s" % ("desplegado" if st.gear_deployed else "recogido"),
		"Focos exteriores: %s · modo fiesta: %s" % ["ON" if st.floodlights else "OFF", "ON" if st.party else "OFF"],
		"Distancia recorrida: %s" % Units.format_distance(log.ship_distance_m),
	])
	huds[a].show_card("Ingeniería", lines, 10.0)
