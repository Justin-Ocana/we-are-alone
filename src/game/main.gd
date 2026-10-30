extends Node
## Punto de entrada. Argumentos de usuario (tras `--`):
##   --run-tests            ejecuta las pruebas unitarias y sale (código = nº de fallos)
##   --smoke-test           prueba de integración headless del Hito 1
##   --benchmark            recorrido automático con medición de FPS y capturas
##   --ship-smoke           prueba de integración headless de la nave (Hito 2)
##   --ship-tour            recorrido visual de la nave con capturas y medición de FPS
##   --world=<id>           entra directamente en un mundo (p. ej. --world=moon)
##   --lat=<g> --lon=<g>    punto de aparición
##   --quality=<low|medium|high>  fuerza un preset sólo para esta ejecución (pruebas)
##   --coop                 cooperativo local a pantalla dividida (jugador 2 con el primer mando)
##   --coop-shots           capturas de la pantalla dividida
##   --continue             carga la partida guardada
##   --menu-shots           capturas de los menús
##   --audio-smoke          prueba de la banda sonora y la megafonía de la nave
##   --nexus-smoke          prueba de las bases procedurales del NEXUS (5 mundos)
##   --nexus-shots          capturas de las bases del NEXUS [--only=mars]
##   --exploration-smoke    prueba de integración de escáner, muestras, puestos de la nave y guardado

## Aparición en la cara visible de la Luna, con la Tierra destruida a ~40° sobre el horizonte (Hito 3).
const SPAWN_LAT := 12.0
const SPAWN_LON := -48.0

var catalog: BodyCatalog
var _world: SurfaceWorld
var _menu: MainMenu


func _ready() -> void:
	Net.session_ended.connect(_on_session_ended)
	Net.begin_requested.connect(_on_net_begin)
	Net.go.connect(func():
		if _world != null:
			_world.release_hold())
	# Pruebas y bancos automáticos: otra partida guardada (nunca la del jugador).
	for k in _parse_args():
		if not k in ["world", "coop", "continue", "lat", "lon", "quality", "novsync"]:
			SaveGame.path = SaveGame.TEST_PATH
			break
	catalog = BodyCatalog.load_dir()
	for e in catalog.errors:
		push_error(e)
	var args := _parse_args()
	if args.has("quality") and GameSettings.QUALITY_PRESETS.has(str(args["quality"])):
		GameSettings.quality = str(args["quality"])  # sólo para esta ejecución (no se guarda)
		GameSettings.apply_runtime()
	if args.has("run-tests"):
		var failures: int = load("res://tests/test_runner.gd").new().run_all()
		get_tree().quit(failures)
		return
	if args.has("smoke-test"):
		var smoke: Node = load("res://tests/smoke/surface_smoke.gd").new()
		smoke.main = self
		add_child(smoke)
		return
	if args.has("ship-smoke"):
		var ship_smoke: Node = load("res://tests/smoke/ship_smoke.gd").new()
		ship_smoke.main = self
		add_child(ship_smoke)
		return
	if args.has("ship-tour"):
		var tour: Node = load("res://tests/bench/ship_tour.gd").new()
		tour.main = self
		tour.no_vsync = args.has("novsync")
		add_child(tour)
		return
	if args.has("shake-probe"):
		var probe: Node = load("res://tests/bench/shake_probe.gd").new()
		probe.main = self
		probe.hover = args.has("hover")
		probe.third = args.has("third")
		probe.fast = args.has("fast")
		add_child(probe)
		return
	if args.has("render-probe"):
		var rp: Node = load("res://tests/bench/render_probe.gd").new()
		rp.main = self
		rp.only = str(args.get("only", ""))
		add_child(rp)
		return
	if args.has("net-smoke"):
		var ns: Node = load("res://tests/smoke/net_smoke.gd").new()
		ns.main = self
		ns.role = str(args["net-smoke"])
		add_child(ns)
		return
	if args.has("prologue-smoke"):
		var ps: Node = load("res://tests/smoke/prologue_smoke.gd").new()
		ps.main = self
		add_child(ps)
		return
	if args.has("audio-smoke"):
		var aus: Node = load("res://tests/smoke/audio_smoke.gd").new()
		aus.main = self
		add_child(aus)
		return
	if args.has("nexus-smoke"):
		var nxs: Node = load("res://tests/smoke/nexus_smoke.gd").new()
		nxs.main = self
		add_child(nxs)
		return
	if args.has("nexus-shots"):
		var nxb: Node = load("res://tests/bench/nexus_shots.gd").new()
		nxb.main = self
		nxb.only = str(args.get("only", ""))
		add_child(nxb)
		return
	if args.has("prologue-shots"):
		var pss: Node = load("res://tests/bench/prologue_shots.gd").new()
		pss.main = self
		add_child(pss)
		return
	if args.has("base-shots"):
		var bs: Node = load("res://tests/bench/base_shots.gd").new()
		bs.main = self
		add_child(bs)
		return
	if args.has("judder-probe"):
		var jp: Node = load("res://tests/bench/judder_probe.gd").new()
		jp.main = self
		jp.smooth = not args.has("nosmooth")
		jp.fps = int(args.get("fps", 45))
		add_child(jp)
		return
	if args.has("descent-tour"):
		var dt: Node = load("res://tests/bench/descent_tour.gd").new()
		dt.main = self
		add_child(dt)
		return
	if args.has("surface-tour"):
		var sft: Node = load("res://tests/bench/surface_tour.gd").new()
		sft.main = self
		sft.only = str(args.get("only", ""))
		add_child(sft)
		return
	if args.has("travel-smoke"):
		var ts: Node = load("res://tests/smoke/travel_smoke.gd").new()
		ts.main = self
		add_child(ts)
		return
	if args.has("system-tour"):
		var st: Node = load("res://tests/bench/system_tour.gd").new()
		st.main = self
		st.only = str(args.get("only", ""))
		add_child(st)
		return
	if args.has("map-shots"):
		var ms: Node = load("res://tests/bench/map_shots.gd").new()
		ms.main = self
		add_child(ms)
		return
	if args.has("coop-shots"):
		var cs: Node = load("res://tests/bench/coop_shots.gd").new()
		cs.main = self
		add_child(cs)
		return
	if args.has("perf-tour"):
		var pt: Node = load("res://tests/bench/perf_tour.gd").new()
		pt.main = self
		add_child(pt)
		return
	if args.has("look-shots"):
		var lk: Node = load("res://tests/bench/look_shots.gd").new()
		lk.main = self
		add_child(lk)
		return
	if args.has("perf-probe"):
		var pp: Node = load("res://tests/bench/perf_probe.gd").new()
		pp.main = self
		add_child(pp)
		return
	if args.has("exploration-smoke"):
		var es: Node = load("res://tests/smoke/exploration_smoke.gd").new()
		es.main = self
		add_child(es)
		return
	if args.has("menu-shots"):
		var mshot: Node = load("res://tests/bench/menu_shots.gd").new()
		mshot.main = self
		add_child(mshot)
		return
	if args.has("continue"):
		continue_game(args.has("coop"))
		return
	if args.has("light-probe"):
		var lp: Node = load("res://tests/bench/light_probe.gd").new()
		lp.main = self
		add_child(lp)
		return
	if args.has("ui-shots"):
		var ui: Node = load("res://tests/bench/ui_shots.gd").new()
		ui.main = self
		ui.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(ui)
		return
	if args.has("benchmark"):
		var bench: Node = load("res://tests/bench/benchmark.gd").new()
		bench.main = self
		bench.world_id = str(args.get("world", "proto_a"))
		add_child(bench)
		return
	if args.has("world"):
		var w := str(args["world"])
		if args.has("coop"):
			GameInput.configure_players(0)
		start_world(w, float(args.get("lat", SPAWN_LAT if w == "moon" else 12.0)), float(args.get("lon", SPAWN_LON if w == "moon" else 31.0)),
			true, true, args.has("coop"))
		return
	show_menu()


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			continue
		var kv := a.substr(2).split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out


func show_menu() -> void:
	_clear_world()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameInput.configure_players(-1)
	GameAudio.set_suppressed(false)
	GameAudio.set_music("menu")
	_menu = MainMenu.new()
	_menu.catalog = catalog
	_menu.start_requested.connect(_on_menu_start)
	add_child(_menu)


func _on_menu_start(mode: String, opts: Dictionary) -> void:
	match mode:
		"new":
			start_world("moon", BaseLayout.SITE_LAT, BaseLayout.SITE_LON, true, true, false, true)
		"coop":
			start_world("moon", BaseLayout.SITE_LAT, BaseLayout.SITE_LON, true, true, true, true)
		"test":
			start_world("proto_a", 12.0, 31.0)
		"continue":
			continue_game(bool(opts.get("coop", false)))
		"net_host":
			pass   # ya no arranca la partida: se abre la sala de espera (LobbyPanel)
		"net_join":
			_join_world(opts.get("welcome", {}))


## Cliente en línea: crea el mundo del anfitrión (mismo cuerpo, junto a donde le toca aparecer) y le aplica su estado.
func _join_world(w: Dictionary) -> void:
	var body := str(w.get("body", "moon"))
	var s: Array = w.get("spawn", [])
	var ll := Vector2(BaseLayout.SITE_LAT, BaseLayout.SITE_LON)
	if s.size() == 3:
		ll = CubeSphere.dir_to_latlon(DVec3.new(s[0], s[1], s[2]))
	var world := start_world(body, ll.x, ll.y, true, true, false, false)
	if world != null and world.net != null:
		world.net.receive_welcome(w)


## Inicio coordinado (ADR-047): todos cargan el mismo mundo a la vez y esperan la salida del anfitrión.
func _on_net_begin(cfg: Dictionary) -> void:
	var w: SurfaceWorld = null
	if Net.is_host() and not bool(cfg.get("new", true)):
		continue_game(false)
		w = _world
	else:
		w = start_world(str(cfg.get("body", "moon")), float(cfg.get("lat", BaseLayout.SITE_LAT)),
			float(cfg.get("lon", BaseLayout.SITE_LON)), true, true, false, bool(cfg.get("new", true)))
	if w != null:
		w.net_hold = true


func _on_session_ended(reason: String) -> void:
	show_menu()
	if _menu != null:
		_menu.show_notice.call_deferred(reason)


## Carga la partida guardada: crea el mundo en el cuerpo guardado y le aplica el estado (SaveGame).
func continue_game(coop: bool = false) -> void:
	var d := SaveGame.load_data()
	if d.is_empty() or catalog.get_body(str(d.get("anchor", ""))) == null:
		start_world("moon", SPAWN_LAT, SPAWN_LON)
		return
	var ll := SaveGame.spawn_latlon(d)
	var w := start_world(str(d["anchor"]), ll.x, ll.y, true, true, coop)
	if w != null:
		SaveGame.apply(w, d)


func start_world(body_id: String, lat: float, lon: float, interactive: bool = true, with_ship: bool = true,
		coop: bool = false, new_game: bool = false) -> SurfaceWorld:
	var b := catalog.get_body(body_id)
	if b == null:
		push_error("Mundo desconocido: %s" % body_id)
		show_menu()
		return null
	if _menu != null:
		_menu.queue_free()
		_menu = null
	_clear_world()
	_world = SurfaceWorld.new()
	_world.interactive = interactive
	_world.spawn_ship = with_ship
	_world.new_game = new_game
	_world.catalog = catalog
	_world.setup(b, lat, lon, coop)
	_world.exit_to_menu.connect(func():
		if not Net.is_client():
			SaveGame.save(_world)
		Net.leave()
		show_menu())
	add_child(_world)
	return _world


func _clear_world() -> void:
	if _world != null:
		_world.queue_free()
		_world = null
