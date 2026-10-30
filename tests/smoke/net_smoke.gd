extends Node
## Prueba de red con TRES procesos (ADR-044/046/047): anfitrión (--net-smoke=host) y dos invitados (join, join2) por
## 127.0.0.1. Comprueba la sala de espera (no arranca sola, «Listo» de todos, cancelar y volver a marcar, inicio
## rechazado si falta alguien, inicio doble ignorado, carga en paralelo y salida simultánea), la historia reflejada, y la
## voz real por la red con una voz sintética: proximidad (cerca), radio personal semidúplex (canal ocupado para el
## segundo emisor, vía de radio a distancia) y canal de la nave por los altavoces a bordo. Uso: tools/net_smoke.ps1.

const PORT := 7791

var main: Node
var role := "host"
var failures := 0
var checks := 0
var _t := 0.0
var _go_t := -1.0
var _step := 0
var _denied := false
var _flags := {}


func _ready() -> void:
	# Tiempo real (sin --fixed-fps, que impedía al anfitrión aceptar conexiones estando en la sala) y como mucho
	# 120 FPS, para que tres procesos sin ventana no se coman los cuatro núcleos.
	Engine.max_fps = 120
	Net.go.connect(func(): _go_t = 0.0)
	Voice.radio_denied.connect(func(_ch: int, _o: int): _denied = true)
	if role == "host":
		GameSettings.profiles[0]["name"] = "Anfitrión"
		var err := Net.host("Sala de prueba", PORT, 6, false)
		check(err == "", "el anfitrión crea la sala (%s)" % err)
	else:
		GameSettings.profiles[0]["name"] = "Invitada" if role == "join" else "Invitado2"
		Net.join_failed.connect(func(r: String):
			check(false, "conexión: " + r)
			_finish())
		var err := Net.join("127.0.0.1", PORT)
		check(err == "", "se inicia la conexión")


func check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
	print(("  PASA   " if cond else "  FALLA  ") + "[%s] " % role + what)


func _finish() -> void:
	print("NET-SMOKE %s RESULTADO: %d comprobaciones, %d fallidas" % [role, checks, failures])
	Voice.test_tone = 0
	Net.leave()
	get_tree().quit(failures)


func _world() -> SurfaceWorld:
	return main._world


func _process(delta: float) -> void:
	_t += delta
	if _go_t >= 0.0:
		_go_t += delta
	if _t > 240.0:
		check(false, "tiempo agotado (paso %d)" % _step)
		_finish()
		return
	if role == "host":
		_host()
	else:
		_client()
	_music()


## Música de la nave compartida: el anfitrión pone una canción de su biblioteca a los 1 s de la salida; los invitados
## la reciben (se les envía el archivo) y la oyen; el segundo invitado la pausa desde su equipo a los 13 s.
func _music() -> void:
	var w := _world()
	if w == null or w.ship == null or _go_t < 0.0:
		return
	var m := w.ship.music
	if role == "host" and _go_t > 1.0 and not _flags.has("m_play"):
		_flags["m_play"] = true
		var dst := ProjectSettings.globalize_path("user://pruebas_musica")
		DirAccess.make_dir_recursive_absolute(dst)
		var f := FileAccess.open(dst.path_join("prueba.mp3"), FileAccess.WRITE)
		f.store_buffer(FileAccess.get_file_as_bytes("res://assets/audio/music/srg774_airy.mp3"))
		f.close()
		m.tracks = [{"title": "Prueba", "path": dst.path_join("prueba.mp3")}]
		m.play_index(0)
	if role == "host" and _go_t > 16.0 and not _flags.has("m_check"):
		_flags["m_check"] = true
		check(m.player.stream_paused, "música compartida: un invitado la pausó desde su equipo")
	if role != "host" and _go_t > 11.0 and not _flags.has("m_got"):
		_flags["m_got"] = true
		check(m.remote and m.title() == "Prueba" and m.player.playing, "música compartida: recibe la canción del anfitrión y suena (%s, %.1f s)" % [m.title(), m.position()])
	if role == "join2" and _go_t > 13.0 and not _flags.has("m_pause"):
		_flags["m_pause"] = true
		m.toggle_pause()


func _ids_by_name() -> Dictionary:
	var out := {}
	for id in Net.peers:
		out[str(Net.peers[id]["name"])] = int(id)
	return out


func _host() -> void:
	var w := _world()
	match _step:
		0:
			if Net.peers.size() == 3:
				check(Net.lobby_state == "esperando" and w == null, "con los dos invitados dentro, la partida NO ha empezado sola")
				check(Net.start_match({"new": true}) != "", "no se puede iniciar si nadie ha pulsado «Listo»")
				Net.set_ready(true)
				_step = 1
		1:
			if Net.peers.size() == 3:
				var rdy := 0
				for id in Net.peers:
					rdy += 1 if Net.peers[id]["ready"] else 0
				if rdy < int(_flags.get("max_rdy", 0)):
					_flags["unready_seen"] = true
				_flags["max_rdy"] = maxi(int(_flags.get("max_rdy", 0)), rdy)
			# Se espera a ver la cancelación de «Listo» del segundo invitado antes de iniciar.
			if Net.all_ready() and Net.peers.size() == 3 and _flags.has("unready_seen"):
				check(true, "un invitado canceló su «Listo» y la sala volvió a esperarle")
				var cfg := {"new": true, "body": "moon", "lat": BaseLayout.SITE_LAT, "lon": BaseLayout.SITE_LON}
				check(Net.start_match(cfg) == "", "todos listos: el anfitrión inicia la partida")
				check(Net.start_match(cfg) != "", "una segunda petición de inicio se ignora (sin doble inicio)")
				_step = 2
			elif _t > 60.0:
				check(false, "no se vio la cancelación de «Listo»")
				_finish()
		2:
			if w != null and w.surface_ready and w.net_hold:
				_flags["held"] = true
			if _go_t >= 0.0 and w != null:
				# Si todos cargan a la vez, la salida puede llegar en el mismo fotograma en que el anfitrión termina de
				# cargar (sin fotograma de espera visible): basta con que su carga constara antes de la salida.
				check(_flags.has("held") or Net._loaded.has(1), "el anfitrión cargó y esperó a los demás antes de empezar")
				check(not w.net_hold and not w.player.frozen, "salida: el anfitrión ya puede moverse")
				var all_in := true
				for id in Net.peers:
					all_in = all_in and str(Net.peers[id]["status"]) == "en partida"
				check(all_in, "todos los jugadores empezaron la partida a la vez")
				_step = 3
		3:
			if _go_t > 4.0:
				var ids := _ids_by_name()
				var a: int = ids.get("Invitada", 0)
				check(int(Voice.stats.get("prox", 0)) > 10, "voz de proximidad de la invitada recibida en persona (%d tramas)" % int(Voice.stats.get("prox", 0)))
				check(Voice.is_speaking(a) == "prox" or int(Voice.stats.get("prox", 0)) > 10, "su voz llega por la vía de proximidad")
				# Alejarse al hangar (más de 150 m): la proximidad ya no llega; la radio sí.
				w.player.place_on_surface(w.base.point_bf(Vector3(0, 0, 40.0)).normalized(), 0.05)
				_flags["prox_before"] = int(Voice.stats.get("prox", 0))
				_step = 4
		4:
			if _go_t > 10.0:
				var ids := _ids_by_name()
				check(int(Voice.stats.get("radio", 0)) > 10, "la radio de la invitada llega a distancia (%d tramas por radio)" % int(Voice.stats.get("radio", 0)))
				check(int(Voice.stats.get("culled", 0)) > 0, "el anfitrión no reenvía la voz de proximidad a quien está lejos (%d recortadas)" % int(Voice.stats.get("culled", 0)))
				# A bordo de la nave: el canal de la nave suena por los altavoces.
				w._bring_aboard(w.player, w.ship)
				_step = 5
		5:
			if _go_t > 13.5 and not _flags.has("shot") and DisplayServer.get_name() != "headless":
				# Con ventana: captura del indicador de voz mientras el segundo invitado habla por la nave.
				_flags["shot"] = true
				var dir := ProjectSettings.globalize_path("user://bench")
				DirAccess.make_dir_recursive_absolute(dir)
				get_viewport().get_texture().get_image().save_png(dir.path_join("red_voz_hud.png"))
			if _go_t > 16.0:
				check(int(Voice.stats.get("speaker", 0)) > 5, "el canal de la nave suena por los altavoces a bordo (%d tramas)" % int(Voice.stats.get("speaker", 0)))
				_step = 6
		6:
			if Net.peers.size() <= 1:
				check(true, "los invitados se desconectan limpiamente")
				_finish()


func _client() -> void:
	var w := _world()
	match _step:
		0:
			if Net.lobby_state == "esperando" and Net.peers.has(Net.my_id()):
				check(w == null, "en la sala de espera: todavía no hay partida cargada")
				_step = 1
				_t = 0.0
		1:
			if _t > 1.0:
				Net.set_ready(true)
				_step = 2 if role == "join" else 10
				_t = 0.0
		10:
			# El segundo invitado cancela su «Listo» y lo vuelve a marcar.
			if _t > 1.5:
				Net.set_ready(false)
				_step = 11
				_t = 0.0
		11:
			if _t > 1.5:
				Net.set_ready(true)
				_step = 2
		2:
			if w != null and w.surface_ready:
				if _go_t < 0.0:
					_flags["held"] = w.net_hold and w.player.frozen
				else:
					check(_flags.get("held", false), "cargado y quieto hasta la salida del anfitrión")
					check(not w.player.frozen, "salida simultánea: ya se puede mover")
					check(w.base.room_of(w.player) == "crio", "despierta en su cápsula (%s)" % w.base.room_of(w.player))
					_step = 3
		3:
			if role == "join":
				# Voz de proximidad 0-4 s; radio 4-10 s (mantener la tecla); después, silencio.
				if _go_t < 4.0:
					Voice.test_tone = VoiceChat.FLAG_PROX
				elif _go_t < 10.0:
					Voice.test_key_radio = true
					if _go_t > 6.0:
						_flags["owned"] = int(Voice.radio_owners.get(Voice.radio_channel, 0)) == Net.my_id()
				else:
					check(_flags.get("owned", false), "la radio concedió el canal C1 a la invitada")
					Voice.test_key_radio = false
					Voice.test_tone = 0
					_step = 4
			else:
				if _go_t > 6.0 and _go_t < 8.0:
					Voice.test_key_radio = true
					Voice.test_tone = VoiceChat.FLAG_PROX
				elif _go_t >= 8.0 and _step == 3:
					check(_denied, "canal ocupado: el segundo emisor recibe el aviso y no transmite")
					Voice.test_key_radio = false
					Voice.test_tone = 0
					_step = 4
		4:
			if role == "join2" and _go_t > 11.0 and _go_t < 16.0:
				Voice.test_key_ship = true
				Voice.test_tone = VoiceChat.FLAG_PROX
			elif _go_t >= 16.5:
				Voice.test_key_ship = false
				Voice.test_tone = 0
				check(int(Voice.stats.get("tx", 0)) > 20, "tramas de voz enviadas (%d)" % int(Voice.stats.get("tx", 0)))
				_finish()
