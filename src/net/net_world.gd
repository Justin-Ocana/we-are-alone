class_name NetWorld
extends Node
## Sincronización de un mundo en línea (ADR-044). Vive dentro de SurfaceWorld cuando hay sesión (Net.is_online()).
##
## Autoridad:
## - Cada jugador manda en SU astronauta: envía su estado 20 veces por segundo (posición BF de 64 bits con el cuerpo
##   dominante, orientación, mirada, animación; a bordo, la pose RELATIVA a la nave). Los demás lo ven como un
##   RemoteAstronaut suavizado.
## - La nave: manda quien va a los mandos (asiento de piloto); si nadie pilota, el anfitrión. El resto la sigue
##   (Ship.net_puppet) y puede ir a bordo sin tirones.
## - El anfitrión manda en la historia: prólogo, puertas, energía, diálogos, hora del Sistema Solar y guardado.
##   Los clientes le PIDEN las interacciones (terminales, puertas, omitir el mensaje) y él responde.
## Cada equipo tiene su propio origen flotante y su propio cuerpo dominante: las posiciones viajan en el marco del
## cuerpo del emisor y se convierten con SolarSystem.convert_point si el receptor está anclado a otro cuerpo.

const SEND_HZ := 20.0
const WORLD_HZ := 5.0

var world: SurfaceWorld
var music_share: MusicShare = null     ## música de la nave compartida (ronda 14)
var puppets := {}                  ## id → RemoteAstronaut
var ship_owner := 1
var _send_t := 0.0
var _world_t := 0.0
var _last_world_hash := 0
var _last_full_t := 0.0
var _peer_seat := {}               ## id → asiento que dice ocupar (para decidir quién pilota)
var _pending_welcome := {}
var _welcome_applied := false
var ack_after_welcome := false     ## inicio coordinado: avisar al anfitrión al aplicar el estado inicial
var _loaded_reported := false


func setup(p_world: SurfaceWorld) -> void:
	world = p_world
	Net.world_sync = self
	if world.dialogue != null and Net.is_host():
		world.dialogue.line_started.connect(func(id: String, _sp: String, _sk: bool): Net.rpc("event", "line", [id]))
		world.dialogue.line_finished.connect(func(_id: String, skipped: bool):
			if skipped:
				Net.rpc("event", "line_stop", []))
	if world.prologue != null and Net.is_client():
		world.prologue.mirror = true
	music_share = MusicShare.new()
	music_share.name = "MusicaCompartida"
	add_child(music_share)
	music_share.setup.call_deferred(world)   # la nave crea su ShipMusic en su _ready


func is_ship_authority() -> bool:
	return ship_owner == Net.my_id()


## Todos los astronautas presentes (locales y remotos).
func people() -> Array:
	return world.players + puppets.values()


func _process(delta: float) -> void:
	if world == null or not Net.is_online():
		return
	if not _pending_welcome.is_empty() and world.surface_ready:
		_apply_welcome(_pending_welcome)
		_pending_welcome = {}
		if ack_after_welcome:
			ack_after_welcome = false
			Net.report_synced()
	# Inicio coordinado (ADR-047): cada equipo avisa al terminar de cargar; el anfitrión da la salida a la vez.
	if world.net_hold and world.surface_ready and not _loaded_reported:
		_loaded_reported = true
		Net.report_loaded()
	_send_t -= delta
	if _send_t <= 0.0 and world.surface_ready:
		_send_t = 1.0 / SEND_HZ
		_send_player()
		if world.ship != null and is_ship_authority():
			_send_ship()
	if Net.is_host():
		_update_owner()
		_world_t -= delta
		_last_full_t += delta
		if _world_t <= 0.0:
			_world_t = 1.0 / WORLD_HZ
			var ws := _world_snapshot()
			var h := hash(ws)
			if h != _last_world_hash or _last_full_t > 2.0:
				_last_world_hash = h
				_last_full_t = 0.0
				ws["t"] = world.system.time_s if world.system != null else 0.0
				ws["ts"] = world.env.time_scale
				Net.rpc("world_state", ws)
	if world.ship != null:
		world.ship.net_puppet = not is_ship_authority()
		world.ship.crew_sources = people()


# --- Jugador local → los demás -------------------------------------------------------------------

func _send_player() -> void:
	var a := world.player
	var p := a.position_bf()
	var q := a.global_transform.basis.get_rotation_quaternion()
	var d := {"a": world.body.id, "p": [p.x, p.y, p.z], "q": [q.x, q.y, q.z, q.w], "v": _arr(a.velocity),
		"pi": snappedf(a.look_pitch, 0.001), "hy": snappedf(a.head_yaw, 0.001), "ex": snappedf(a.exertion, 0.01),
		"seat": a.seat_id if a.seated else "", "ab": a.aboard != null and a.aboard == world.ship, "fly": a.flying,
		"gr": a.is_on_floor(), "em": a.emote, "suit": a.suit_on}
	if d["ab"]:
		var rel: Transform3D = world.ship.global_transform.affine_inverse() * a.global_transform
		var rq := rel.basis.get_rotation_quaternion()
		d["rp"] = _arr(rel.origin)
		d["rq"] = [rq.x, rq.y, rq.z, rq.w]
	Net.rpc("player_state", d)


func on_player_state(id: int, d: Dictionary) -> void:
	if world == null or not world.surface_ready:
		return
	var pup: RemoteAstronaut = puppets.get(id)
	if pup == null:
		pup = RemoteAstronaut.new()
		pup.peer_id = id
		var info: Dictionary = Net.peers.get(id, {})
		pup.display_name = str(info.get("name", "Jugador"))
		pup.profile = info.get("profile", {})
		pup.profile["name"] = pup.display_name
		pup.world = world
		pup.name = "Remoto_%d" % id
		world.add_child(pup)
		puppets[id] = pup
		_refresh_hud_others()
	_peer_seat[id] = str(d.get("seat", ""))
	var conv := _convert(d)
	pup.apply_state(d, conv[0], conv[1], conv[2], world.ship)


## [posición local del motor, orientación, velocidad] del estado recibido, en el marco local.
func _convert(d: Dictionary) -> Array:
	var p: Array = d["p"]
	var pos := DVec3.new(p[0], p[1], p[2])
	var q: Array = d["q"]
	var basis := Basis(Quaternion(q[0], q[1], q[2], q[3]))
	var vel := _v3(d.get("v", [0, 0, 0]))
	var a := str(d.get("a", world.body.id))
	if a != world.body.id and world.system != null and world.system.has_body(a):
		var r := world.system.frame_rotation(a, world.body.id)
		pos = world.system.convert_point(pos, a, world.body.id)
		basis = r * basis
		vel = r * vel
	return [FloatingOrigin.to_local(pos), basis, vel]


func on_peer_left(id: int) -> void:
	if music_share != null:
		music_share.on_peer_left(id)
	if puppets.has(id):
		puppets[id].queue_free()
		puppets.erase(id)
	_peer_seat.erase(id)
	_refresh_hud_others()


func _refresh_hud_others() -> void:
	for a in world.players:
		if a.exploration_hud != null:
			var others: Array = world.players.filter(func(o): return o != a)
			a.exploration_hud.others = others + puppets.values()


# --- Nave ---------------------------------------------------------------------------------------

func _update_owner() -> void:
	var owner := 1
	if world.player.seated and Ship.is_pilot_seat(world.player.seat_id):
		owner = 1
	else:
		for id in _peer_seat:
			if Ship.is_pilot_seat(str(_peer_seat[id])) and puppets.has(id) and puppets[id].aboard != null:
				owner = id
				break
	if owner != ship_owner:
		ship_owner = owner
		_last_world_hash = 0   # avisar ya


func _send_ship() -> void:
	var st := world.ship.state
	var q := st.basis.get_rotation_quaternion()
	Net.rpc("ship_state", {"a": world.body.id, "p": [st.pos_bf.x, st.pos_bf.y, st.pos_bf.z], "q": [q.x, q.y, q.z, q.w],
		"v": _arr(st.velocity), "w": _arr(st.ang_vel), "landed": st.landed, "gear": st.gear_hold,
		"fl": st.floodlights, "eo": snappedf(st.engine_output, 0.01)})


func on_ship_state(id: int, d: Dictionary) -> void:
	if world.ship == null or id != ship_owner or is_ship_authority():
		return
	var conv := _convert(d)
	var s := world.ship
	s.net_receive(FloatingOrigin.to_global(conv[0]), conv[1], conv[2], _v3(d.get("w", [0, 0, 0])), bool(d.get("landed", true)))
	s.state.gear_hold = bool(d.get("gear", false))
	s.state.engine_output = float(d.get("eo", 0.0))
	if bool(d.get("fl", false)) != s.state.floodlights:
		s.cmd_toggle_floodlights()


# --- Historia y mundo (anfitrión → clientes) ----------------------------------------------------

func _world_snapshot() -> Dictionary:
	var ws := {"owner": ship_owner}
	if world.base != null:
		ws["base"] = world.base.capture()
	if world.prologue != null:
		ws["pro"] = {"step": world.prologue.step, "active": world.prologue.active}
		var a := world.player
		ws["pf"] = {"suit": a.suit_on, "lock": a.move_locked, "cin": a.cinematic}
	if world.ship != null:
		ws["immob"] = world.ship.immobilized
	if world.dialogue != null:
		ws["heard"] = world.dialogue.heard.keys()
	if world.nexus != null:
		ws["nx"] = world.nexus.log.nexus
		ws["nxs"] = world.nexus.log.nexus_sites
	return ws


func on_world_state(d: Dictionary) -> void:
	if world == null:
		return
	var owner := int(d.get("owner", 1))
	ship_owner = owner
	if world.system != null and d.has("t"):
		var t := float(d["t"])
		if absf(world.system.time_s - t) > 5.0:
			world.system.time_s = t
		else:
			world.system.time_s = lerpf(world.system.time_s, t, 0.2)
		world.env.time_scale = float(d.get("ts", 1.0))
	if world.base != null and d.has("base"):
		world.base.apply_net(d["base"])
	if world.prologue != null and d.has("pro"):
		world.prologue.apply_mirror(d["pro"])
	if d.has("pf"):
		var pf: Dictionary = d["pf"]
		for a in world.players:
			a.suit_on = bool(pf.get("suit", true))
			a.move_locked = bool(pf.get("lock", false))
			a.cinematic = bool(pf.get("cin", false))
	if world.ship != null and d.has("immob"):
		world.ship.immobilized = bool(d["immob"])
	if world.dialogue != null and d.has("heard"):
		for id in d["heard"]:
			world.dialogue.heard[str(id)] = true
	if world.nexus != null and d.has("nx"):
		world.nexus.apply_net(d["nx"], d.get("nxs", {}))


## Petición de un cliente (en el anfitrión).
func on_request(id: int, kind: String, args: Array) -> void:
	var pup: RemoteAstronaut = puppets.get(id)
	match kind:
		"interact":
			if pup != null and world.base != null:
				world.base.interact(pup, str(args[0]), str(args[1]))
		"skip":
			if world.dialogue != null:
				world.dialogue.skip()
		"nexus":
			if world.nexus != null:
				world.nexus.collect(pup)
		"recall":
			if world.ship != null and args.size() >= 3:
				world.ship.cmd_recall(DVec3.new(args[0], args[1], args[2]))


## Aviso del anfitrión (en los clientes).
func on_event(kind: String, args: Array) -> void:
	var hud: ExplorationHud = world.player.exploration_hud
	match kind:
		"card":
			if hud != null:
				hud.show_card(str(args[0]), PackedStringArray(args[1]), 11.0)
		"note":
			if hud != null:
				hud.notify(str(args[0]), UiTheme.DANGER)
		"line":
			if world.dialogue != null:
				world.dialogue.play_remote(str(args[0]))
		"line_stop":
			if world.dialogue != null:
				world.dialogue.stop_all()


## Ficha o aviso para un jugador concreto (local o remoto).
func send_card(a: Node, title: String, lines: Array) -> void:
	if a is RemoteAstronaut:
		Net.rpc_id(a.peer_id, "event", "card", [title, lines])


func send_note(a: Node, text: String) -> void:
	if a is RemoteAstronaut:
		Net.rpc_id(a.peer_id, "event", "note", [text])


# --- Entrada en la partida ----------------------------------------------------------------------

## Estado inicial para un cliente que entra (lo calcula el anfitrión).
func welcome_for(id: int) -> Dictionary:
	var a := world.player
	var w := {"body": world.body.id, "t": world.system.time_s if world.system != null else 0.0, "ts": world.env.time_scale}
	w.merge(_world_snapshot())
	var spawn := a.position_bf()
	var in_capsules := world.prologue != null and world.prologue.active \
		and world.prologue.idx(world.prologue.step) <= world.prologue.idx("salir_capsula")
	if in_capsules and world.base != null:
		var k: int = int(Net.pod_of.get(id, world.base.next_free_pod()))
		world.base.assign_pod(k)
		w["pod"] = k
		w["base"] = world.base.capture()
		spawn = world.base.point_bf(BaseLayout.CAPSULE_SPOTS[k])
	elif a.aboard != null and world.ship != null:
		w["aboard"] = true
	else:
		var side := a.global_transform.basis.x * 1.6 * float(Net.peers.size() - 1)
		spawn = FloatingOrigin.to_global(a.global_position + side)
	w["spawn"] = [spawn.x, spawn.y, spawn.z]
	if world.ship != null:
		var st := world.ship.state
		var q := st.basis.get_rotation_quaternion()
		w["ship"] = {"p": [st.pos_bf.x, st.pos_bf.y, st.pos_bf.z], "q": [q.x, q.y, q.z, q.w], "landed": st.landed}
	return w


## El cliente aplica el estado inicial cuando su terreno está listo.
func receive_welcome(w: Dictionary) -> void:
	_pending_welcome = w


func _apply_welcome(w: Dictionary) -> void:
	if world.system != null:
		world.system.time_s = float(w.get("t", world.system.time_s))
	on_world_state(w)
	if world.ship != null and w.has("ship"):
		var sd: Dictionary = w["ship"]
		var p: Array = sd["p"]
		var q: Array = sd["q"]
		world.ship.state.pos_bf = DVec3.new(p[0], p[1], p[2])
		world.ship.state.basis = Basis(Quaternion(q[0], q[1], q[2], q[3]))
		world.ship.state.landed = bool(sd.get("landed", true))
		world.ship._sync_node()
	var a := world.player
	if bool(w.get("aboard", false)) and world.ship != null:
		world._bring_aboard(a, world.ship)
	elif w.has("pod") and world.base != null:
		world.place_in_pod(a, int(w["pod"]))
	elif w.has("spawn"):
		var s: Array = w["spawn"]
		a.place_on_surface(DVec3.new(s[0], s[1], s[2]), 0.05)
	_welcome_applied = true


static func _arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


static func _v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])
