class_name VoiceChat
extends Node
## Comunicaciones por voz (autoload «Voice», ADR-046). Tres canales SEPARADOS:
## - Proximidad: la voz en persona, LIMPIA (sin casco, eco ni muros: petición del usuario). Audio 3D desde la cabeza de
##   quien habla: sólo dirección real y volumen por distancia (hasta el alcance de las reglas de la sala).
## - Radio personal (walkie del traje): pulsar para transmitir, canales 1-4, SEMIDÚPLEX (un emisor por canal, lo
##   arbitra el anfitrión), pitido de entrada y estática de salida, compresión, ruido y cortes según la cobertura.
## - Canal de la nave: abierto para toda la tripulación vinculada; dentro de la nave se oye por sus altavoces (audio 3D
##   desde el altavoz más cercano, ecualización de megafonía y sala), fuera por la radio del traje.
## Cada trama llega a cada oyente por UNA sola vía (proximidad si se le oye en persona; si no, radio o altavoces): sin
## duplicados. Las tramas van al anfitrión, que valida (radio: sólo el dueño del canal; proximidad: sólo a quien está
## cerca) y reenvía. Códec: VoiceCodec (μ-law 12 kHz, tramas de 40 ms).

signal state_changed
signal radio_denied(channel: int, owner: int)

const FLAG_PROX := 1
const FLAG_RADIO := 2
const FLAG_SHIP := 4
const FLAG_SUIT := 8          ## quien habla lleva el casco puesto
const FLAG_DAMAGED := 16      ## casco dañado (salud baja): interferencias
const FLAG_HABITAT := 32      ## quien habla está en un recinto presurizado (nave o base)
const CHANNELS := 4
const SPEAK_HOLD_MS := 300
const VAD_HANG_S := 0.35
const RADIO_CLEAR_M := 5.0e7        ## hasta 50.000 km la radio llega limpia
const RADIO_MAX_M := 2.0e9          ## más allá, sin señal (FICTICIO: red de repetidores de MacSpaces)

var radio_channel := 1
var radio_owners := {}              ## canal → id del emisor (lo mantiene el anfitrión y lo replica)
var tx_prox := false
var tx_radio := false
var tx_ship := false
var radio_wanted := false
var radio_busy_until := 0           ## ms: aviso «canal ocupado»
var mic_level := 0.0
var mic_ok := false
var mic_test := false
var test_tone := 0                  ## pruebas: banderas de una voz sintética (sin micrófono)
var test_key_radio := false
var test_key_ship := false
var muted := {}                     ## nombre → true (se guarda en los ajustes)
var player_volume := {}             ## nombre → 0..2
var stats := {"tx": 0, "rx": 0, "prox": 0, "radio": 0, "speaker": 0, "lobby": 0, "dropped": 0, "fwd": 0, "culled": 0}
var no_signal_until := 0

var _mic_player: AudioStreamPlayer
var _capture: AudioEffectCapture
var _resampler: VoiceCodec.Resampler
var _acc := PackedFloat32Array()
var _vad_t := 0.0
var _tone_t := 0.0
var _tone_acc := 0.0
var _sources := {}                  ## id → VoiceSource
var _fx_player: AudioStreamPlayer   ## pitidos propios (radio concedida / ocupada)
var _fx_pb: AudioStreamGeneratorPlayback
var _test_player: AudioStreamPlayer
var _test_pb: AudioStreamGeneratorPlayback
var _test_fx := VoiceFx.new("aire")
var _src_t := 0.0
var _hud: VoiceHud


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_buses()
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = "Microfono"
	add_child(_mic_player)
	_fx_player = _gen_player(AudioStreamPlayer.new(), "VozRadio")
	add_child(_fx_player)
	_test_player = _gen_player(AudioStreamPlayer.new(), "VozProx")
	add_child(_test_player)
	_hud = VoiceHud.new()
	_hud.voice = self
	add_child(_hud)
	apply_settings()


func _make_buses() -> void:
	var defs := [["Microfono", ""], ["VozProx", "Voces"], ["VozRadio", "Voces"], ["VozNave", "Voces"]]
	for d in defs:
		if AudioServer.get_bus_index(d[0]) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, d[0])
			if d[1] != "" and AudioServer.get_bus_index(d[1]) >= 0:
				AudioServer.set_bus_send(i, d[1])
	var mic := AudioServer.get_bus_index("Microfono")
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 0.5
	AudioServer.add_bus_effect(mic, _capture)
	AudioServer.set_bus_volume_db(mic, -80.0)    # se captura, no se oye
	var radio := AudioServer.get_bus_index("VozRadio")
	var comp := AudioEffectCompressor.new()
	comp.threshold = -18.0
	comp.ratio = 6.0
	AudioServer.add_bus_effect(radio, comp)
	var nave := AudioServer.get_bus_index("VozNave")
	var eq := AudioEffectEQ6.new()
	eq.set_band_gain_db(0, -12.0)
	eq.set_band_gain_db(1, -4.0)
	eq.set_band_gain_db(3, 3.0)
	eq.set_band_gain_db(5, -10.0)
	AudioServer.add_bus_effect(nave, eq)
	var rv2 := AudioEffectReverb.new()
	rv2.room_size = 0.45
	rv2.damping = 0.6
	rv2.wet = 0.22
	rv2.dry = 0.85
	AudioServer.add_bus_effect(nave, rv2)


static func _gen_player(p: Node, bus: String) -> Node:
	var g := AudioStreamGenerator.new()
	g.mix_rate = VoiceCodec.RATE
	g.buffer_length = 0.6
	p.set("stream", g)
	p.set("bus", bus)
	return p


## Volúmenes, dispositivos y teclas desde GameSettings.
func apply_settings() -> void:
	var vols := {"VozProx": GameSettings.voice_vol_prox, "VozRadio": GameSettings.voice_vol_radio, "VozNave": GameSettings.voice_vol_ship}
	for b in vols:
		var i := AudioServer.get_bus_index(b)
		if i >= 0:
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(float(vols[b]), 0.0001)))
	if GameSettings.voice_input_device != "" and GameSettings.voice_input_device in AudioServer.get_input_device_list():
		AudioServer.input_device = GameSettings.voice_input_device
	if GameSettings.voice_output_device != "" and GameSettings.voice_output_device in AudioServer.get_output_device_list():
		AudioServer.output_device = GameSettings.voice_output_device
	muted = GameSettings.voice_mutes.duplicate()
	player_volume = GameSettings.voice_player_volume.duplicate()


## Alcance de proximidad efectivo: el del jugador, sin pasar del máximo de las reglas de la sala.
func prox_range() -> float:
	return minf(GameSettings.voice_range, float(Net.rules.get("prox_range", 35.0)))


func active() -> bool:
	return (Net.is_online() and GameSettings.voice_enabled) or mic_test


# --- Captura y envío --------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_update_mic(delta)
	_src_t -= delta
	if _src_t <= 0.0:
		_src_t = 0.25
		_update_sources()


func _world() -> SurfaceWorld:
	var ws: Node = Net.world_sync
	if ws != null and is_instance_valid(ws) and ws.get("world") != null:
		return ws.world
	return null


func _update_mic(delta: float) -> void:
	var want := active()
	if want and not _mic_player.playing and test_tone == 0:
		_mic_player.play()
		_resampler = VoiceCodec.Resampler.new(AudioServer.get_mix_rate(), VoiceCodec.RATE)
	elif not want and _mic_player.playing:
		_mic_player.stop()
		_acc.clear()
	if not want:
		_set_tx(false, false, false)
		return
	if test_tone != 0:
		# Voz sintética (pruebas automáticas sin micrófono): un tono que sube y baja.
		_tone_acc += delta * VoiceCodec.RATE
		while _tone_acc >= 1.0:
			_tone_acc -= 1.0
			_tone_t += 1.0 / VoiceCodec.RATE
			_acc.append(sin(TAU * 220.0 * _tone_t) * 0.3 * (0.6 + 0.4 * sin(_tone_t * 3.0)))
		mic_ok = true
	elif _capture.can_get_buffer(1):
		var n := _capture.get_frames_available()
		var buf := _capture.get_buffer(n)
		var mono := PackedFloat32Array()
		mono.resize(buf.size())
		for i in buf.size():
			mono[i] = (buf[i].x + buf[i].y) * 0.5
		_acc.append_array(_resampler.process(mono))
		mic_ok = true
	_update_keys()
	while _acc.size() >= VoiceCodec.FRAME:
		var frame := _acc.slice(0, VoiceCodec.FRAME)
		_acc = _acc.slice(VoiceCodec.FRAME)
		_on_frame(frame)


func _key(action: StringName) -> bool:
	if not InputMap.has_action(action):
		return false
	var w := _world()
	if w != null and w.player != null and (w.player.input_blocked or get_tree().paused):
		return false
	return Input.is_action_pressed(action)


func _update_keys() -> void:
	var radio := _key(&"voice_radio") or test_key_radio
	if radio != radio_wanted:
		radio_wanted = radio
		if Net.is_online():
			request_radio(radio)
	if Input.is_action_just_pressed(&"voice_channel"):
		set_channel(radio_channel % CHANNELS + 1)


func _on_frame(frame: PackedFloat32Array) -> void:
	var level := VoiceCodec.rms(frame)
	mic_level = lerpf(mic_level, level, 0.5)
	var threshold := lerpf(0.004, 0.08, GameSettings.voice_vad_threshold)
	if level > threshold or test_tone != 0:
		_vad_t = VAD_HANG_S
	else:
		_vad_t = maxf(0.0, _vad_t - VoiceCodec.FRAME / float(VoiceCodec.RATE))
	var radio: bool = radio_wanted and radio_owners.get(radio_channel, 0) == Net.my_id()
	var ship := (_key(&"voice_ship") or test_key_ship) and GameSettings.voice_ship_linked
	var prox: bool
	if GameSettings.voice_mode == "ptt":
		prox = _key(&"voice_prox") or (test_tone & FLAG_PROX) != 0
	else:
		prox = _vad_t > 0.0
	if test_tone != 0:
		prox = (test_tone & FLAG_PROX) != 0
	# Quien habla por la radio o la nave también habla en voz alta: los de al lado le oyen en persona.
	prox = prox or radio or ship
	_set_tx(prox, radio, ship)
	if mic_test:
		_loopback(frame)
	if not (prox or radio or ship) or not Net.is_online():
		return
	var flags := (FLAG_PROX if prox else 0) | (FLAG_RADIO if radio else 0) | (FLAG_SHIP if ship else 0) | _context_flags()
	var data := VoiceCodec.encode(frame)
	stats["tx"] += 1
	if Net.is_host():
		host_route(1, flags, radio_channel, data)
	else:
		Net.rpc_id(1, "voice_frame", flags, radio_channel, data)


func _context_flags() -> int:
	var w := _world()
	if w == null or w.player == null:
		return 0
	var a := w.player
	var f := 0
	if a.suit_on and a.aboard == null and not a.in_habitat:
		f |= FLAG_SUIT
	if a.health < 35.0:
		f |= FLAG_DAMAGED
	if a.aboard != null or a.in_habitat:
		f |= FLAG_HABITAT
	return f


func _set_tx(p: bool, r: bool, s: bool) -> void:
	if p != tx_prox or r != tx_radio or s != tx_ship:
		tx_prox = p
		tx_radio = r
		tx_ship = s
		state_changed.emit()


func _loopback(frame: PackedFloat32Array) -> void:
	if _test_pb == null:
		_test_player.play()
		_test_pb = _test_player.get_stream_playback()
	if _test_pb.can_push_buffer(frame.size()):
		_test_fx.set_kind("radio" if tx_radio else ("megafonia" if tx_ship else "aire"))
		_test_pb.push_buffer(_test_fx.process(frame))


func set_mic_test(on: bool) -> void:
	mic_test = on
	if not on and _test_player.playing:
		_test_player.stop()
		_test_pb = null


# --- Radio: semidúplex arbitrado por el anfitrión -------------------------------------------------

func set_channel(ch: int) -> void:
	if radio_wanted:
		request_radio(false)
	radio_channel = clampi(ch, 1, CHANNELS)
	GameSettings.voice_channel = radio_channel
	if radio_wanted:
		request_radio(true)
	state_changed.emit()


func request_radio(on: bool) -> void:
	if Net.is_host():
		host_radio_request(1, radio_channel, on)
	else:
		Net.rpc_id(1, "voice_radio_req", radio_channel, on)


## Anfitrión: concede el canal si está libre; si no, avisa al que lo pide de que está ocupado.
func host_radio_request(peer: int, ch: int, on: bool) -> void:
	if ch < 1 or ch > CHANNELS:
		return
	var owner := int(radio_owners.get(ch, 0))
	if on:
		if owner == 0:
			radio_owners[ch] = peer
		elif owner != peer:
			if peer == 1:
				on_radio_denied(ch, owner)
			else:
				Net.rpc_id(peer, "voice_radio_denied", ch, owner)
			return
	else:
		if owner == peer:
			radio_owners.erase(ch)
	Net.rpc("voice_radio_state", radio_owners)
	on_radio_state(radio_owners)


func on_radio_state(owners: Dictionary) -> void:
	var before: int = radio_owners.get(radio_channel, 0)
	radio_owners = {}
	for k in owners:
		radio_owners[int(k)] = int(owners[k])
	var now: int = radio_owners.get(radio_channel, 0)
	if before != now:
		# Pitido de entrada (o estática de salida) en NUESTRO canal, como una radio de verdad.
		if now != 0:
			_push_fx(VoiceFx.squelch(true))
		elif before != 0:
			_push_fx(VoiceFx.squelch(false))
	state_changed.emit()


func on_radio_denied(ch: int, owner: int) -> void:
	radio_busy_until = Time.get_ticks_msec() + 1500
	var tone := PackedVector2Array()
	for i in 1800:
		var s := sin(TAU * 480.0 * i / VoiceCodec.RATE) * 0.15 * (1.0 if (i / 300) % 2 == 0 else 0.0)
		tone.append(Vector2(s, s))
	_push_fx(tone)
	radio_denied.emit(ch, owner)
	state_changed.emit()


func _push_fx(buf: PackedVector2Array) -> void:
	if not _fx_player.playing:
		_fx_player.play()
		_fx_pb = _fx_player.get_stream_playback()
	if _fx_pb != null and _fx_pb.can_push_buffer(buf.size()):
		_fx_pb.push_buffer(buf)


func on_peer_left(peer: int) -> void:
	if _sources.has(peer):
		_sources[peer].free_players()
		_sources.erase(peer)
	if Net.is_host():
		var changed := false
		for ch in radio_owners.keys():
			if radio_owners[ch] == peer:
				radio_owners.erase(ch)
				changed = true
		if changed:
			Net.rpc("voice_radio_state", radio_owners)
			on_radio_state(radio_owners)


# --- Anfitrión: validación y reenvío ---------------------------------------------------------------

func host_route(sender: int, flags: int, ch: int, data: PackedByteArray) -> void:
	if flags & FLAG_RADIO and int(radio_owners.get(ch, 0)) != sender:
		flags &= ~FLAG_RADIO       # nadie transmite por un canal que no tiene concedido
	if flags & (FLAG_PROX | FLAG_RADIO | FLAG_SHIP) == 0:
		return
	var w := _world()
	var spos = _peer_position(w, sender)
	for peer in Net.peers:
		var id := int(peer)
		if id == sender:
			continue
		if flags & (FLAG_RADIO | FLAG_SHIP) == 0 and spos != null and w != null:
			var ppos = _peer_position(w, id)
			if ppos != null and (ppos as Vector3).distance_to(spos) > float(Net.rules.get("prox_range", 35.0)) * 1.6:
				stats["culled"] += 1
				continue    # sólo proximidad y demasiado lejos: ni se reenvía ni se reproduce
		if id == 1:
			receive(sender, flags, ch, data)    # el propio anfitrión también escucha
		else:
			Net.rpc_id(id, "voice_deliver", sender, flags, ch, data)
			stats["fwd"] += 1


func _peer_position(w: SurfaceWorld, id: int):
	if w == null:
		return null
	if id == Net.my_id():
		return w.player.global_position
	if w.net != null and w.net.puppets.has(id):
		return w.net.puppets[id].global_position
	return null


# --- Recepción y reproducción ---------------------------------------------------------------------

func receive(sender: int, flags: int, ch: int, data: PackedByteArray) -> void:
	stats["rx"] += 1
	var name := str(Net.peers.get(sender, {}).get("name", "?"))
	if muted.get(name, false):
		stats["dropped"] += 1
		return
	var src: VoiceSource = _sources.get(sender)
	if src == null:
		src = VoiceSource.new(sender, self)
		_sources[sender] = src
	var w := _world()
	var path := "lobby"
	var quality := 1.0
	if w != null:
		path = ""
		var pup: RemoteAstronaut = w.net.puppets.get(sender) if w.net != null else null
		var me := w.player
		if flags & FLAG_PROX and pup != null and pup.visible and me.global_position.distance_to(pup.global_position) <= prox_range():
			path = "prox"     # cerca: voz limpia, también en el vacío (enlace de corto alcance entre trajes, sin efecto)
		elif flags & FLAG_RADIO and ch == radio_channel and GameSettings.voice_listen_radio:
			path = "radio"
			quality = _radio_quality(w, pup)
		elif flags & FLAG_SHIP and GameSettings.voice_listen_ship:
			if w.ship != null and me.aboard == w.ship and GameSettings.voice_ship_speakers:
				path = "speaker"
			else:
				path = "radio"
				quality = _radio_quality(w, pup)
		if path == "radio" and quality <= 0.0:
			no_signal_until = Time.get_ticks_msec() + 1500
			path = ""
	if path == "":
		stats["dropped"] += 1
		return
	stats[path] = stats.get(path, 0) + 1
	src.play(path, quality, flags, ch, VoiceCodec.decode(data), w)


func _radio_quality(w: SurfaceWorld, pup: RemoteAstronaut) -> float:
	if pup == null:
		return 0.85
	var d := w.player.position_bf().sub(pup.position_bf()).length()
	if d <= RADIO_CLEAR_M:
		return 1.0
	if d >= RADIO_MAX_M:
		return 0.0
	return clampf(1.0 - log(d / RADIO_CLEAR_M) / log(RADIO_MAX_M / RADIO_CLEAR_M), 0.05, 1.0)


func is_speaking(peer: int) -> String:
	var s: VoiceSource = _sources.get(peer)
	return s.speaking_path() if s != null else ""


## ¿Se está oyendo a algún compañero ahora mismo (por cualquier vía)?
func anyone_speaking() -> bool:
	for id in _sources:
		if _sources[id].speaking_path() != "":
			return true
	return false


func sources() -> Dictionary:
	return _sources


func _update_sources() -> void:
	var w := _world()
	for id in _sources:
		_sources[id].update_spatial(w)


func debug_text() -> String:
	var owners := []
	for ch in radio_owners:
		owners.append("C%d:%s" % [ch, Net.peers.get(radio_owners[ch], {}).get("name", "?")])
	return "Voz: tx %d · rx %d (prox %d, radio %d, altavoz %d, sala %d, descartadas %d) · reenviadas %d (recortadas por distancia %d)\n" % [
		stats["tx"], stats["rx"], stats.get("prox", 0), stats.get("radio", 0), stats.get("speaker", 0), stats.get("lobby", 0),
		stats["dropped"], stats["fwd"], stats["culled"]] \
		+ "Canal C%d · %s · micro %.3f %s · alcance %.0f m" % [radio_channel, ", ".join(owners) if not owners.is_empty() else "canales libres",
		mic_level, "OK" if mic_ok else "sin micro", prox_range()]
