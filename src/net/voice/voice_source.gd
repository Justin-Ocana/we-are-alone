class_name VoiceSource
extends RefCounted
## Voz de UN jugador remoto (ADR-046): un reproductor por vía y su propio procesado (VoiceFx con estado).
## - "prox": AudioStreamPlayer3D en la cabeza de su marioneta (bus VozProx): voz LIMPIA, sólo dirección real y
##   volumen por distancia (petición del usuario: cerca, sin casco, eco ni muros; los efectos son de la radio).
## - "radio": AudioStreamPlayer (bus VozRadio): radio del traje (canal personal o canal de la nave fuera de ella).
## - "speaker": AudioStreamPlayer3D en el altavoz de la nave más cercano a quien escucha (bus VozNave).
## - "lobby": en la sala de espera, voz directa sin mundo.

var peer := 0
var voice: Node
var players := {}                    ## vía → AudioStreamPlayer/3D
var _pb := {}                        ## vía → AudioStreamGeneratorPlayback
var _fx := {}                        ## vía → VoiceFx
var _last := {}                      ## vía → ms de la última trama


func _init(p_peer: int, p_voice: Node) -> void:
	peer = p_peer
	voice = p_voice


func play(path: String, quality: float, flags: int, _ch: int, samples: PackedFloat32Array, w: SurfaceWorld) -> void:
	var p := _player(path, w)
	if p == null:
		return
	var fx: VoiceFx = _fx.get(path)
	if fx == null:
		fx = VoiceFx.new()
		_fx[path] = fx
	var kind := "aire"
	match path:
		"radio":
			kind = "radio" if GameSettings.voice_radio_fx else "aire"
		"speaker":
			kind = "megafonia" if GameSettings.voice_effects else "aire"
	fx.set_kind(kind)
	fx.quality = quality
	fx.damaged = (flags & VoiceChat.FLAG_DAMAGED) != 0
	var pb: AudioStreamGeneratorPlayback = _pb.get(path)
	if pb == null or not p.playing:
		p.play()
		pb = p.get_stream_playback()
		_pb[path] = pb
	var out := fx.process(samples)
	if pb.can_push_buffer(out.size()):
		pb.push_buffer(out)
	_last[path] = Time.get_ticks_msec()


func _player(path: String, w: SurfaceWorld) -> Node:
	var p: Node = players.get(path)
	if p != null and is_instance_valid(p):
		return p
	match path:
		"prox":
			if w == null or w.net == null or not w.net.puppets.has(peer):
				return null
			var p3 := AudioStreamPlayer3D.new()
			p3.unit_size = 3.0
			p3.max_distance = 120.0
			p3.attenuation_filter_db = 0.0     # sin el pasa-bajo de la distancia: sólo baja el volumen
			p3.panning_strength = 1.0
			p = VoiceChat._gen_player(p3, "VozProx")
			w.net.puppets[peer].add_child(p)
			(p as Node3D).position = Vector3(0, 1.62, 0)
		"speaker":
			if w == null or w.ship == null:
				return null
			var s3 := AudioStreamPlayer3D.new()
			s3.unit_size = 6.0
			s3.max_distance = 40.0
			p = VoiceChat._gen_player(s3, "VozNave")
			w.ship.add_child(p)
		"radio":
			p = VoiceChat._gen_player(AudioStreamPlayer.new(), "VozRadio")
			voice.add_child(p)
		_:
			p = VoiceChat._gen_player(AudioStreamPlayer.new(), "Voces")
			voice.add_child(p)
	players[path] = p
	_apply_volume()
	return p


func _apply_volume() -> void:
	var name := str(Net.peers.get(peer, {}).get("name", "?"))
	var v := float(voice.player_volume.get(name, 1.0))
	for k in players:
		var p: Node = players[k]
		if is_instance_valid(p):
			p.set("volume_db", linear_to_db(maxf(v, 0.0001)))


## Vía por la que se le oye ahora mismo (para los indicadores) o "".
func speaking_path() -> String:
	var now := Time.get_ticks_msec()
	var best := ""
	var best_t := -1
	for k in _last:
		if now - int(_last[k]) < VoiceChat.SPEAK_HOLD_MS and int(_last[k]) > best_t:
			best = k
			best_t = int(_last[k])
	return best


## Volumen por jugador y posición del altavoz de la nave (el más cercano a quien escucha).
func update_spatial(w: SurfaceWorld) -> void:
	_apply_volume()
	if w == null or w.player == null:
		return
	var spk: AudioStreamPlayer3D = players.get("speaker")
	if spk != null and is_instance_valid(spk) and w.ship != null:
		var local := w.ship.to_local(w.player.global_position)
		var best := Vector3(0, 2.7, 0)
		var best_d := INF
		for id in ["pasillo", "cabina", "salon", "comedor", "dormitorios", "maquinas", "almacen", "enfermeria", "esclusa"]:
			if not ShipLayout.ROOMS.has(id):
				continue
			var c: Vector3 = ShipLayout.room_center(id) + Vector3(0, 2.7, 0)
			var d := c.distance_to(local)
			if d < best_d:
				best_d = d
				best = c
		spk.position = best


func free_players() -> void:
	for k in players:
		if is_instance_valid(players[k]):
			players[k].queue_free()
	players.clear()
	_pb.clear()
