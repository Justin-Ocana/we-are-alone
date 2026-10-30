class_name MusicShare
extends Node
## Música de la nave compartida en línea (ronda 14, ADR-049). Quien pone una canción de SU biblioteca es el «DJ»:
## - Publica el estado (huella MD5, título, reproduciendo/pausa, posición) a todos al cambiar y cada 3 s.
## - Quien no tiene esa canción la pide al DJ, que se la envía en trozos de 16 KB por el canal ENet 3 (fiable, aparte
##   de la voz y del estado del mundo), a ~600 KB/s como mucho. Se guarda en user://music/compartida/<md5>.<ext> y no
##   se vuelve a enviar. Al completarla (MD5 comprobado) suena en el punto en que va el DJ.
## - Los demás siguen al DJ y corrigen la posición si se desvían más de 0,4 s. Pausar, seguir, avanzar o parar desde
##   otro equipo se pide al DJ; poner una canción propia convierte a ese jugador en el nuevo DJ.
## - Si el DJ se va, la música se para.

const CHUNK := 16384
const SEND_BYTES_PER_S := 600 * 1024
const MAX_BYTES := 40 * 1024 * 1024
const HEARTBEAT_S := 3.0
const DRIFT_S := 0.4
const CACHE_DIR := "user://music/compartida"

signal progress(text: String)

var world: SurfaceWorld
var music: ShipMusic
var dj := 0                         ## peer que manda en la música (0 = nadie)
var state := {}                     ## último estado publicado/recibido
var _state_at := 0                  ## ms en que se recibió `state`
var _beat := 0.0
var _file_bytes := {}               ## DJ: huella → bytes de la canción (para enviar)
var _send_queue: Array = []         ## DJ: [peer, huella, índice del siguiente trozo]
var _send_budget := 0.0
var _recv := {}                     ## huella → {total, parts: {i: bytes}, got}
var _applying := false              ## aplicando un estado remoto (no volver a publicarlo)


func setup(p_world: SurfaceWorld) -> void:
	world = p_world
	music = world.ship.music if world.ship != null else null
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	if music != null:
		music.local_action.connect(_on_local_action)
		music.forward = func(action: String, arg: float): Net.rpc_id(dj, "music_ctrl", action, arg)
		progress.connect(func(t: String): music.status.emit(t))


# --- DJ (quien tiene el archivo) ------------------------------------------------------------------

## El jugador local ha tocado los controles (panel M) o ha acabado una canción en su equipo.
func _on_local_action(action: String, arg: float) -> void:
	if _applying or music == null or music.remote:
		return
	dj = Net.my_id()
	music.remote = false
	_publish()


func _publish() -> void:
	var path := music.current_path()
	if path == "" or (not music.is_playing() and not music.player.stream_paused):
		state = {"h": "", "dj": Net.my_id()}
	else:
		var h := FileAccess.get_md5(path)
		if not _file_bytes.has(h):
			var bytes := FileAccess.get_file_as_bytes(path)
			if bytes.size() > MAX_BYTES:
				progress.emit("«%s» es demasiado grande para compartirla (más de 40 MB)." % music.title())
				return
			_file_bytes.clear()          # sólo la canción actual en memoria
			_file_bytes[h] = bytes
		state = {"h": h, "title": music.title(), "ext": path.get_extension().to_lower(), "size": int(_file_bytes[h].size()),
			"playing": music.is_playing(), "pos": music.position(), "dj": Net.my_id()}
	_state_at = Time.get_ticks_msec()
	_beat = HEARTBEAT_S
	Net.rpc("music_state", state)


## Petición de la canción por parte de otro jugador.
func on_want(sender: int, h: String) -> void:
	if not _file_bytes.has(h):
		return
	for q in _send_queue:
		if int(q[0]) == sender and str(q[1]) == h:
			return
	_send_queue.append([sender, h, 0])


## Pausar/seguir/parar/avanzar pedido desde otro equipo.
func on_ctrl(_sender: int, action: String, arg: float) -> void:
	if dj != Net.my_id() or music == null:
		return
	match action:
		"toggle":
			music.toggle_pause()
		"stop":
			music.stop()
		"next":
			music.next()
		"previous":
			music.previous()
		"seek":
			music.seek_fraction(arg)


# --- Oyentes --------------------------------------------------------------------------------------

func on_state(sender: int, st: Dictionary) -> void:
	if music == null or sender == Net.my_id():
		return
	dj = int(st.get("dj", sender))
	state = st
	_state_at = Time.get_ticks_msec()
	var h := str(st.get("h", ""))
	if h == "":
		if music.remote:
			_apply(func(): music.stop_local())
		return
	var cached := _cache_path(h, str(st.get("ext", "mp3")))
	if FileAccess.file_exists(cached):
		_follow(cached)
	elif not _recv.has(h):
		if int(st.get("size", 0)) > MAX_BYTES:
			return
		_recv[h] = {"total": int(ceil(float(st.get("size", 0)) / CHUNK)), "parts": {}, "got": 0}
		progress.emit("Recibiendo «%s» de %s…" % [str(st.get("title", "")), _name(dj)])
		Net.rpc_id(dj, "music_want", h)


func on_chunk(sender: int, h: String, idx: int, total: int, data: PackedByteArray) -> void:
	if not _recv.has(h) or sender != dj:
		return
	var r: Dictionary = _recv[h]
	if idx < 0 or idx >= total or r["parts"].has(idx):
		return
	r["parts"][idx] = data
	r["got"] = int(r["got"]) + data.size()
	r["total"] = total
	if r["parts"].size() % 32 == 0:
		progress.emit("Recibiendo «%s»: %d %%" % [str(state.get("title", "")), int(100.0 * r["parts"].size() / maxf(total, 1))])
	if r["parts"].size() < total:
		return
	var all := PackedByteArray()
	for i in total:
		all.append_array(r["parts"][i])
	_recv.erase(h)
	var ext := str(state.get("ext", "mp3")) if str(state.get("h", "")) == h else "mp3"
	var path := _cache_path(h, ext)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(all)
	f.close()
	if FileAccess.get_md5(path) != h:
		DirAccess.remove_absolute(path)
		progress.emit("La canción llegó dañada; se vuelve a pedir.")
		return
	progress.emit("«%s» recibida." % str(state.get("title", "")))
	if str(state.get("h", "")) == h:
		_follow(path)


## Sigue el estado del DJ con la canción ya en disco.
func _follow(path: String) -> void:
	var playing := bool(state.get("playing", false))
	var target := float(state.get("pos", 0.0)) + (float(Time.get_ticks_msec() - _state_at) / 1000.0 if playing else 0.0) + 0.08
	_apply(func():
		if music.current_path() != path or not music.remote:
			music.remote = true
			music.play_file(path, str(state.get("title", "")), target)
		elif absf(music.position() - target) > DRIFT_S:
			music.player.seek(target)
		if playing and music.player.stream_paused:
			music.player.stream_paused = false
		elif not playing and music.is_playing():
			music.player.stream_paused = true
		music.remote_dj = _name(dj))


func _apply(f: Callable) -> void:
	_applying = true
	f.call()
	_applying = false


func on_peer_left(id: int) -> void:
	for i in range(_send_queue.size() - 1, -1, -1):
		if int(_send_queue[i][0]) == id:
			_send_queue.remove_at(i)
	if id == dj and music != null and music.remote:
		_apply(func(): music.stop_local())
		dj = 0
		progress.emit("El DJ se ha ido: música parada.")


static func _cache_path(h: String, ext: String) -> String:
	return CACHE_DIR.path_join(h + "." + (ext if ext in ShipMusic.EXTENSIONS else "mp3"))


func _name(id: int) -> String:
	return str(Net.peers.get(id, {}).get("name", "?"))


func _process(delta: float) -> void:
	if music == null:
		return
	# DJ: latido del estado y envío de trozos con presupuesto de ancho de banda.
	if dj == Net.my_id() and not state.is_empty():
		_beat -= delta
		if _beat <= 0.0 and str(state.get("h", "")) != "":
			_publish()
	_send_budget = minf(_send_budget + SEND_BYTES_PER_S * delta, CHUNK * 8.0)
	while not _send_queue.is_empty() and _send_budget >= CHUNK:
		var q: Array = _send_queue[0]
		var bytes: PackedByteArray = _file_bytes.get(q[1], PackedByteArray())
		if bytes.is_empty() or not Net.peers.has(int(q[0])):
			_send_queue.pop_front()
			continue
		var total := int(ceil(float(bytes.size()) / CHUNK))
		var i := int(q[2])
		Net.rpc_id(int(q[0]), "music_chunk", str(q[1]), i, total, bytes.slice(i * CHUNK, mini((i + 1) * CHUNK, bytes.size())))
		_send_budget -= CHUNK
		q[2] = i + 1
		if i + 1 >= total:
			_send_queue.pop_front()
