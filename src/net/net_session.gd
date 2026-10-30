class_name NetSession
extends Node
## Sesión online (autoload «Net», ADR-044). Sin servidor de pago: el ANFITRIÓN es el PC de un jugador.
## - Transporte: ENet (UDP) de Godot. El anfitrión escucha en el puerto 7777 (configurable); hasta 6 jugadores.
## - Apertura de puerto automática con UPnP (incluido en Godot; en un hilo para no congelar el juego). Si el router
##   no lo admite o el operador usa CGNAT, se puede jugar igual con una red virtual gratuita (ZeroTier, Tailscale,
##   Radmin VPN): el juego sólo necesita una IP alcanzable.
## - Red local: el anfitrión anuncia la sala por difusión UDP (puerto 7778) y la lista de «Unirse» la muestra sola.
## - Topología cliente-servidor con reenvío del anfitrión (SceneMultiplayer.server_relay): los clientes sólo hablan
##   con el anfitrión. El anfitrión manda en la historia (prólogo, base, tiempo); cada jugador manda en su astronauta
##   y quien pilota manda en la nave (NetWorld).
## Todas las RPC viven en este nodo (/root/Net existe igual en todos los equipos).

signal status_changed(text: String)
signal peers_changed
signal joined(welcome: Dictionary)          ## cliente: el anfitrión aceptó y mandó el estado inicial
signal join_failed(reason: String)
signal session_ended(reason: String)
signal lan_rooms_changed
signal lobby_changed                          ## estado de la sala o de algún jugador (ADR-047)
signal begin_requested(config: Dictionary)    ## todos: cargar el mundo de la partida (inicio coordinado)
signal go                                     ## todos han cargado: empieza la partida a la vez

const DEFAULT_PORT := 7777
const DISCOVERY_PORT := 7778
const MAX_PLAYERS := 6
const PROTOCOL := 4                ## sube con cada cambio de las RPC (ronda 14: sala, voz, NEXUS)
const GAME_VERSION := "0.8.1"        ## versión visible (menú y avisos de versión distinta)
const JOIN_TIMEOUT_MS := 12000     ## sin respuesta del anfitrión en este tiempo → aviso con las causas habituales
const BEACON_S := 1.0

var mode := "offline"                ## "offline" | "host" | "client"
var room_name := ""
var max_players := MAX_PLAYERS
var port := DEFAULT_PORT
var peers := {}                      ## id → {name, profile}
var lan_rooms := {}                  ## "ip:puerto" → {name, players, max, host, t}
var lan_ips: PackedStringArray = []
var public_ip := ""
var upnp_state := ""                 ## "", "buscando", "abierto", "fallo: …"
var world_sync: Node = null          ## NetWorld del mundo actual (recibe las RPC de juego)
var start_new_game := true           ## anfitrión: partida nueva o continuar la guardada
## Reglas de la sala (las fija el anfitrión y valen para todos; ADR-046/047).
var rules := {"prox_range": 35.0, "radio_channels": 4}
## Estado de la sala (ADR-047): "esperando" (acepta jugadores; cada uno pulsa «Listo»), "iniciando" (el anfitrión ha
## iniciado; ya no se puede cambiar), "cargando" (todos cargan el mundo en paralelo), "en_partida".
var lobby_state := "esperando"
var pod_of := {}                     ## id → cápsula asignada en el inicio coordinado
var _loaded := {}                    ## id → true (mundo cargado y sincronizado)
var _load_started_ms := 0
var _ping_t := 0.0
const LOAD_TIMEOUT_MS := 90000
var _join_addr := ""
var _join_started := 0
var _admitted := false             ## el anfitrión ya nos aceptó (sala o partida)

var _peer: ENetMultiplayerPeer
var _upnp: UPNP
var _upnp_thread: Thread
var _beacon: PacketPeerUDP
var _listen: PacketPeerUDP
var _beacon_t := 0.0
var _pending_name := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _fail("No se pudo conectar con el anfitrión."))
	multiplayer.server_disconnected.connect(func(): _end("El anfitrión cerró la sala."))
	lan_ips = _local_ips()


func is_online() -> bool:
	return mode != "offline"


func is_host() -> bool:
	return mode == "host"


func is_client() -> bool:
	return mode == "client"


func my_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


func player_name() -> String:
	return str(GameSettings.profile(0).get("name", "Jugador"))


# --- Crear / unirse / salir ----------------------------------------------------------------------

## Crea la sala en este PC. Devuelve "" si todo va bien o el motivo del error.
func host(p_room: String, p_port: int, p_max: int, use_upnp: bool) -> String:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(p_port, clampi(p_max, 2, MAX_PLAYERS) - 1)
	if err != OK:
		_peer = null
		return "No se pudo abrir el puerto %d (¿otra copia del juego abierta?)." % p_port
	multiplayer.multiplayer_peer = _peer
	mode = "host"
	room_name = p_room.strip_edges() if p_room.strip_edges() != "" else "Sala de %s" % player_name()
	port = p_port
	max_players = clampi(p_max, 2, MAX_PLAYERS)
	peers = {1: {"name": player_name(), "profile": _profile_dict(), "ready": false, "status": "anfitrión", "ping": 0}}
	lobby_state = "esperando"
	pod_of = {}
	_loaded = {}
	_start_beacon()
	if use_upnp:
		_start_upnp()
	_status("Sala «%s» abierta en el puerto %d" % [room_name, port])
	peers_changed.emit()
	return ""


func join(address: String, p_port: int) -> String:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address.strip_edges(), p_port)
	if err != OK:
		_peer = null
		return "Dirección no válida."
	multiplayer.multiplayer_peer = _peer
	mode = "client"
	port = p_port
	_join_addr = "%s:%d" % [address.strip_edges(), p_port]
	_join_started = Time.get_ticks_msec()
	_admitted = false
	_status("Conectando con %s…" % _join_addr)
	return ""


## Dirección para invitar: la pública si el router abrió el puerto (UPnP), si no la de la red local.
func invite_address() -> String:
	var ip := public_ip if public_ip != "" else (lan_ips[0] if not lan_ips.is_empty() else "127.0.0.1")
	return "%s:%d" % [ip, port]


func leave() -> void:
	if _peer != null:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	_stop_beacon()
	_stop_upnp()
	mode = "offline"
	peers = {}
	world_sync = null
	lobby_state = "esperando"
	_loaded = {}
	peers_changed.emit()
	lobby_changed.emit()


func _fail(reason: String) -> void:
	leave()
	join_failed.emit(reason)
	_status(reason)


func _end(reason: String) -> void:
	var was := mode
	leave()
	if was != "offline":
		session_ended.emit(reason)


func _status(t: String) -> void:
	status_changed.emit(t)


func _profile_dict() -> Dictionary:
	var p: Dictionary = GameSettings.profile(0)
	var out := {}
	for k in p:
		var v = p[k]
		out[k] = v.to_html() if v is Color else v
	return out


static func profile_from_dict(d: Dictionary) -> Dictionary:
	var out := d.duplicate()
	for k in ["suit", "accent", "visor"]:
		if out.has(k) and out[k] is String:
			out[k] = Color.html(out[k])
	return out


# --- Altas y bajas -------------------------------------------------------------------------------

func _on_connected() -> void:
	_status("Conectado. Esperando al anfitrión…")
	rpc_id(1, "hello", PROTOCOL, player_name(), _profile_dict())


func _on_peer_connected(id: int) -> void:
	if is_host() and peers.size() >= max_players:
		_peer.disconnect_peer(id)


func _on_peer_disconnected(id: int) -> void:
	_loaded.erase(id)
	if peers.has(id):
		var n := str(peers[id]["name"])
		peers.erase(id)
		if is_host():
			rpc("peer_list", peers)
			_broadcast_lobby()
			_check_go()       # si se iba el último que faltaba por cargar, empezar ya
		peers_changed.emit()
		_status("%s ha salido" % n)
	if world_sync != null:
		world_sync.on_peer_left(id)
	Voice.on_peer_left(id)


@rpc("any_peer", "reliable")
func hello(protocol: int, p_name: String, profile: Dictionary) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if protocol != PROTOCOL:
		rpc_id(id, "rejected", "Versión del juego distinta: el anfitrión tiene la v%s. Usad los dos el mismo .exe." % GAME_VERSION)
		return
	if peers.size() >= max_players:
		rpc_id(id, "rejected", "La sala está llena (%d jugadores)." % max_players)
		return
	var nm := p_name.strip_edges().left(24)
	if nm == "":
		nm = "Jugador %d" % (peers.size() + 1)
	var taken := []
	for p in peers.values():
		taken.append(str(p["name"]))
	var base_nm := nm
	var k := 2
	while nm in taken:
		nm = "%s (%d)" % [base_nm, k]
		k += 1
	peers[id] = {"name": nm, "profile": profile, "ready": false, "status": "conectado", "ping": 0}
	rpc("peer_list", peers)
	peers_changed.emit()
	_status("%s se ha unido" % nm)
	if lobby_state == "en_partida" and world_sync != null:
		# Partida ya empezada: entra directamente (aparece junto al anfitrión).
		peers[id]["status"] = "en partida"
		var welcome := {"room": room_name, "you": nm}
		welcome.merge(world_sync.welcome_for(id))
		rpc_id(id, "welcome", welcome)
	elif lobby_state != "esperando":
		rpc_id(id, "rejected", "La partida está empezando; vuelve a intentarlo en unos segundos.")
		return
	_broadcast_lobby()


@rpc("authority", "reliable")
func rejected(reason: String) -> void:
	_fail(reason)


@rpc("authority", "reliable")
func welcome(data: Dictionary) -> void:
	_admitted = true
	room_name = str(data.get("room", ""))
	_status("Dentro de «%s»" % room_name)
	joined.emit(data)


@rpc("authority", "reliable", "call_local")
func peer_list(list: Dictionary) -> void:
	if is_client():
		peers = list
		peers_changed.emit()


# --- Sala de espera (ADR-047) ---------------------------------------------------------------------

func _broadcast_lobby() -> void:
	if not is_host():
		return
	rpc("lobby_update", lobby_state, peers, rules, room_name)
	lobby_changed.emit()


@rpc("authority", "reliable")
func lobby_update(state: String, list: Dictionary, p_rules: Dictionary, p_room: String) -> void:
	_admitted = true
	lobby_state = state
	peers = list
	rules = p_rules
	room_name = p_room
	peers_changed.emit()
	lobby_changed.emit()


## «Listo» / «No listo» de este jugador (sólo mientras la sala espera).
func set_ready(on: bool) -> void:
	if is_host():
		_set_ready(1, on)
	elif is_client():
		rpc_id(1, "ready_req", on)


@rpc("any_peer", "reliable")
func ready_req(on: bool) -> void:
	if is_host():
		_set_ready(multiplayer.get_remote_sender_id(), on)


func _set_ready(id: int, on: bool) -> void:
	if lobby_state != "esperando" or not peers.has(id):
		return
	peers[id]["ready"] = on
	if id != 1:
		peers[id]["status"] = "listo" if on else "preparándose"
	_broadcast_lobby()


func all_ready() -> bool:
	if peers.is_empty():
		return false
	for id in peers:
		if not bool(peers[id].get("ready", false)):
			return false
	return true


## Anfitrión: inicia la partida para todos. Devuelve "" o el motivo por el que no se puede (y no hace nada: así una
## pulsación doble o una petición repetida nunca la inicia dos veces).
func start_match(config: Dictionary) -> String:
	if not is_host():
		return "Sólo el anfitrión inicia la partida."
	if lobby_state != "esperando":
		return "La partida ya se está iniciando."
	if not all_ready():
		return "Faltan jugadores por pulsar «Listo»."
	lobby_state = "iniciando"
	pod_of = {}
	var ids: Array = peers.keys()
	ids.sort()
	var k := 0
	for id in ids:
		pod_of[int(id)] = k
		k += 1
	var cfg := config.duplicate()
	cfg["pods"] = pod_of
	_loaded = {}
	_load_started_ms = Time.get_ticks_msec()
	for id in peers:
		peers[id]["status"] = "cargando"
	lobby_state = "cargando"
	_broadcast_lobby()
	rpc("begin", cfg)
	begin_requested.emit(cfg)
	return ""


@rpc("authority", "reliable")
func begin(config: Dictionary) -> void:
	lobby_state = "cargando"
	lobby_changed.emit()
	begin_requested.emit(config)


## El mundo de este equipo ha terminado de cargar (lo llama NetWorld).
func report_loaded() -> void:
	if is_host():
		_mark_loaded(1)
	else:
		rpc_id(1, "loaded_req")


@rpc("any_peer", "reliable")
func loaded_req() -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	# El cliente recibe su estado inicial (cápsula o posición, nave, historia) y responde «sincronizado».
	if world_sync != null:
		var w: Dictionary = world_sync.welcome_for(id)
		rpc_id(id, "start_sync", w)


@rpc("authority", "reliable")
func start_sync(data: Dictionary) -> void:
	if world_sync != null:
		world_sync.receive_welcome(data)
		world_sync.ack_after_welcome = true


func report_synced() -> void:
	rpc_id(1, "synced_req")


@rpc("any_peer", "reliable")
func synced_req() -> void:
	if is_host():
		_mark_loaded(multiplayer.get_remote_sender_id())


func _mark_loaded(id: int) -> void:
	if lobby_state != "cargando":
		return
	_loaded[id] = true
	if peers.has(id):
		peers[id]["status"] = "cargado"
	_broadcast_lobby()
	_check_go()


func _check_go() -> void:
	if lobby_state != "cargando" or not _loaded.has(1):
		return
	var timed_out := Time.get_ticks_msec() - _load_started_ms > LOAD_TIMEOUT_MS
	for id in peers:
		if not _loaded.has(id) and not timed_out:
			return
	lobby_state = "en_partida"
	for id in peers:
		peers[id]["status"] = "en partida" if _loaded.has(id) else "sin cargar"
	_broadcast_lobby()
	rpc("go_now")
	go.emit()


@rpc("authority", "reliable")
func go_now() -> void:
	lobby_state = "en_partida"
	lobby_changed.emit()
	go.emit()


## El anfitrión expulsa a un jugador.
func kick(id: int) -> void:
	if is_host() and id != 1 and _peer != null:
		rpc_id(id, "rejected", "El anfitrión te ha expulsado de la sala.")
		_peer.disconnect_peer(id, true)


# --- RPC de juego (las reenvía al NetWorld) ------------------------------------------------------

@rpc("any_peer", "unreliable_ordered")
func player_state(data: Dictionary) -> void:
	if world_sync != null:
		world_sync.on_player_state(multiplayer.get_remote_sender_id(), data)


@rpc("any_peer", "unreliable_ordered")
func ship_state(data: Dictionary) -> void:
	if world_sync != null:
		world_sync.on_ship_state(multiplayer.get_remote_sender_id(), data)


@rpc("authority", "reliable")
func world_state(data: Dictionary) -> void:
	if world_sync != null:
		world_sync.on_world_state(data)


@rpc("any_peer", "reliable")
func request(kind: String, args: Array) -> void:
	if is_host() and world_sync != null:
		world_sync.on_request(multiplayer.get_remote_sender_id(), kind, args)


@rpc("authority", "reliable")
func event(kind: String, args: Array) -> void:
	if world_sync != null:
		world_sync.on_event(kind, args)


# --- Voz (ADR-046): las tramas van SIEMPRE al anfitrión, que valida y reenvía ----------------------

# --- Música de la nave compartida (MusicShare, ronda 14): canal ENet 3, aparte de la voz ---------------

@rpc("any_peer", "reliable", "call_remote", 3)
func music_state(st: Dictionary) -> void:
	if world_sync != null and world_sync.music_share != null:
		world_sync.music_share.on_state(multiplayer.get_remote_sender_id(), st)


@rpc("any_peer", "reliable", "call_remote", 3)
func music_want(h: String) -> void:
	if world_sync != null and world_sync.music_share != null:
		world_sync.music_share.on_want(multiplayer.get_remote_sender_id(), h)


@rpc("any_peer", "reliable", "call_remote", 3)
func music_chunk(h: String, idx: int, total: int, data: PackedByteArray) -> void:
	if world_sync != null and world_sync.music_share != null:
		world_sync.music_share.on_chunk(multiplayer.get_remote_sender_id(), h, idx, total, data)


@rpc("any_peer", "reliable", "call_remote", 3)
func music_ctrl(action: String, arg: float) -> void:
	if world_sync != null and world_sync.music_share != null:
		world_sync.music_share.on_ctrl(multiplayer.get_remote_sender_id(), action, arg)


@rpc("any_peer", "unreliable_ordered", "call_remote", 1)
func voice_frame(flags: int, ch: int, data: PackedByteArray) -> void:
	if is_host():
		Voice.host_route(multiplayer.get_remote_sender_id(), flags, ch, data)


@rpc("authority", "unreliable_ordered", "call_remote", 1)
func voice_deliver(sender: int, flags: int, ch: int, data: PackedByteArray) -> void:
	Voice.receive(sender, flags, ch, data)


@rpc("any_peer", "reliable", "call_remote", 2)
func voice_radio_req(ch: int, on: bool) -> void:
	if is_host():
		Voice.host_radio_request(multiplayer.get_remote_sender_id(), ch, on)


@rpc("authority", "reliable", "call_remote", 2)
func voice_radio_state(owners: Dictionary) -> void:
	Voice.on_radio_state(owners)


@rpc("authority", "reliable", "call_remote", 2)
func voice_radio_denied(ch: int, owner: int) -> void:
	Voice.on_radio_denied(ch, owner)


# --- UPnP (en un hilo: el descubrimiento puede tardar varios segundos) ----------------------------

func _start_upnp() -> void:
	upnp_state = "buscando"
	_status("Abriendo el puerto %d en el router (UPnP)…" % port)
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_work.bind(port))


func _upnp_work(p: int) -> void:
	var u := UPNP.new()
	var err := u.discover(2000, 2, "InternetGatewayDevice")
	var result := {}
	if err != UPNP.UPNP_RESULT_SUCCESS or u.get_gateway() == null or not u.get_gateway().is_valid_gateway():
		result = {"ok": false, "why": "el router no responde a UPnP"}
	else:
		var m := u.add_port_mapping(p, p, "We Are Alone?", "UDP", 0)
		if m == UPNP.UPNP_RESULT_SUCCESS:
			result = {"ok": true, "ip": u.query_external_address()}
		else:
			result = {"ok": false, "why": "el router rechazó abrir el puerto (código %d)" % m}
	call_deferred("_upnp_done", u, result)


func _upnp_done(u: UPNP, r: Dictionary) -> void:
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if mode != "host":
		return
	if r.get("ok", false):
		_upnp = u
		public_ip = str(r.get("ip", ""))
		upnp_state = "abierto"
		_status("Puerto abierto. IP pública para tus amigos: %s:%d" % [public_ip, port])
	else:
		upnp_state = "fallo: " + str(r.get("why", ""))
		_status("UPnP no disponible (%s). En red local funciona; por Internet abre el puerto UDP %d a mano o usa ZeroTier/Tailscale/Radmin." % [r.get("why", ""), port])


func _stop_upnp() -> void:
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if _upnp != null:
		_upnp.delete_port_mapping(port, "UDP")
		_upnp = null
	public_ip = ""
	upnp_state = ""


# --- Descubrimiento en red local ------------------------------------------------------------------

func _start_beacon() -> void:
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	_beacon.set_dest_address("255.255.255.255", DISCOVERY_PORT)


func _stop_beacon() -> void:
	if _beacon != null:
		_beacon.close()
	_beacon = null


## La pantalla «Unirse» escucha anuncios de salas en la red local.
func start_browsing() -> void:
	stop_browsing()
	_listen = PacketPeerUDP.new()
	if _listen.bind(DISCOVERY_PORT) != OK:
		_listen = null
		_status("No se pueden buscar salas en la red local (puerto %d ocupado)." % DISCOVERY_PORT)


func stop_browsing() -> void:
	if _listen != null:
		_listen.close()
	_listen = null
	lan_rooms = {}


func _process(delta: float) -> void:
	# Cliente sin respuesta del anfitrión: aviso con las causas habituales en vez de esperar al tiempo de ENet.
	if mode == "client" and not _admitted and _join_started > 0 and Time.get_ticks_msec() - _join_started > JOIN_TIMEOUT_MS:
		_join_started = 0
		var connected := _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
		_fail(("Conectado, pero el anfitrión no contesta (¿otra versión del juego?). Usad los dos el mismo .exe (v%s)." % GAME_VERSION) \
			if connected else ("El anfitrión no responde en %s. Comprueba la IP y el puerto, que el anfitrión haya " % _join_addr \
			+ "permitido el juego en el Firewall de Windows y que su router tenga abierto el puerto UDP (o UPnP). " \
			+ "Si no hay manera, usad una red virtual gratuita (Radmin VPN, ZeroTier o Tailscale)."))
	if is_host():
		_ping_t -= delta
		if _ping_t <= 0.0:
			_ping_t = 1.0
			_update_pings()
		if lobby_state == "cargando":
			_check_go()
	if _beacon != null and mode == "host":
		_beacon_t -= delta
		if _beacon_t <= 0.0:
			_beacon_t = BEACON_S
			var msg := JSON.stringify({"game": "WeAreAlone", "v": PROTOCOL, "name": room_name, "port": port,
				"players": peers.size(), "max": max_players, "host": player_name(), "state": lobby_state})
			_beacon.put_packet(msg.to_utf8_buffer())
	if _listen != null:
		var changed := false
		while _listen.get_available_packet_count() > 0:
			var pkt := _listen.get_packet()
			var ip := _listen.get_packet_ip()
			var d = JSON.parse_string(pkt.get_string_from_utf8())
			if d is Dictionary and d.get("game", "") == "WeAreAlone":
				var key := "%s:%d" % [ip, int(d.get("port", DEFAULT_PORT))]
				d["ip"] = ip
				d["t"] = Time.get_ticks_msec()
				lan_rooms[key] = d
				changed = true
		var now := Time.get_ticks_msec()
		for k in lan_rooms.keys():
			if now - int(lan_rooms[k]["t"]) > 4000:
				lan_rooms.erase(k)
				changed = true
		if changed:
			lan_rooms_changed.emit()


func _update_pings() -> void:
	if _peer == null:
		return
	var changed := false
	for id in peers:
		if int(id) == 1:
			continue
		var pp := _peer.get_peer(int(id))
		if pp != null:
			var rtt := int(pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
			if rtt != int(peers[id].get("ping", 0)):
				peers[id]["ping"] = rtt
				changed = true
	if changed and lobby_state != "en_partida":
		_broadcast_lobby()


static func _local_ips() -> PackedStringArray:
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out


func _exit_tree() -> void:
	leave()
