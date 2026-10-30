class_name LobbyPanel
extends VBoxContainer
## Sala de espera en línea (ADR-047). Crear una sala NO inicia la partida: aquí se reúnen los jugadores, cada uno pulsa
## «Listo» y el anfitrión inicia cuando todos lo están; entonces todos cargan a la vez y empiezan juntos.
## Lista de jugadores con estado (conectado, preparándose, listo, cargando…), ping y marca de «Listo»; el anfitrión
## elige la partida (nueva o continuar), el alcance de la voz de proximidad (regla de la sala) y puede expulsar.
## Se puede hablar ya en la sala (voz directa) para probar los micrófonos.

signal closed

var _title: Label
var _state: Label
var _list: VBoxContainer
var _ready_btn: Button
var _start_btn: Button
var _mode: OptionButton
var _range: HSlider
var _range_lbl: Label
var _msg: Label
var _host_box: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var head := HBoxContainer.new()
	_title = Label.new()
	_title.add_theme_font_override("font", UiTheme.title_font())
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", UiTheme.ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	if Net.is_host():
		# Copiar la dirección para pasársela al amigo (la pública si el router abrió el puerto).
		var copy := Button.new()
		copy.text = "Copiar dirección"
		copy.tooltip_text = "Copia IP:puerto al portapapeles para enviársela a tus amigos."
		copy.pressed.connect(func():
			DisplayServer.clipboard_set(Net.invite_address())
			copy.text = "Copiada: " + Net.invite_address())
		head.add_child(copy)
	var leave := Button.new()
	leave.text = "Salir de la sala"
	leave.pressed.connect(func():
		Net.leave()
		closed.emit())
	head.add_child(leave)
	add_child(head)
	_state = Label.new()
	_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_state.add_theme_color_override("font_color", UiTheme.DATA)
	add_child(_state)
	var cols := HBoxContainer.new()
	for c in [["JUGADOR", 190], ["ESTADO", 130], ["PING", 60], ["LISTO", 60], ["", 90]]:
		var l := Label.new()
		l.text = c[0]
		l.custom_minimum_size = Vector2(c[1], 0)
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		cols.add_child(l)
	add_child(cols)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.custom_minimum_size = Vector2(0, 170)
	add_child(_list)
	_ready_btn = Button.new()
	_ready_btn.custom_minimum_size = Vector2(0, 44)
	_ready_btn.pressed.connect(func(): Net.set_ready(not _my_ready()))
	add_child(_ready_btn)
	_host_box = VBoxContainer.new()
	_host_box.add_theme_constant_override("separation", 6)
	add_child(_host_box)
	_mode = OptionButton.new()
	_mode.add_item("Partida nueva (prólogo en la base LF-01)", 0)
	_mode.add_item("Continuar mi partida guardada", 1)
	if SaveGame.summary().is_empty():
		_mode.set_item_disabled(1, true)
	_host_box.add_child(_row("Partida", _mode))
	var rr := HBoxContainer.new()
	_range = HSlider.new()
	_range.min_value = 10.0
	_range.max_value = 60.0
	_range.step = 5.0
	_range.value = float(Net.rules.get("prox_range", 35.0))
	_range.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_range_lbl = Label.new()
	_range_lbl.custom_minimum_size = Vector2(60, 0)
	_range.value_changed.connect(func(v: float):
		Net.rules["prox_range"] = v
		_range_lbl.text = "%d m" % int(v)
		Net._broadcast_lobby())
	_range_lbl.text = "%d m" % int(_range.value)
	rr.add_child(_range)
	rr.add_child(_range_lbl)
	_host_box.add_child(_row("Alcance de la voz (regla de la sala)", rr))
	_start_btn = Button.new()
	_start_btn.text = "INICIAR PARTIDA"
	_start_btn.custom_minimum_size = Vector2(0, 48)
	_start_btn.pressed.connect(_on_start)
	_host_box.add_child(_start_btn)
	_msg = Label.new()
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.add_theme_font_size_override("font_size", 13)
	_msg.add_theme_color_override("font_color", UiTheme.DANGER)
	add_child(_msg)
	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	hint.text = "Ya podéis hablar para probar los micrófonos (indicador abajo a la izquierda). Ajustes de voz: Opciones > Voz."
	add_child(hint)
	Net.lobby_changed.connect(_refresh)
	Net.peers_changed.connect(_refresh)
	Net.status_changed.connect(func(t: String): _msg.text = t if Net.is_host() else _msg.text)
	_refresh()


func focus_first() -> void:
	_ready_btn.grab_focus()


func _row(label: String, ctrl: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(250, 0)
	r.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(ctrl)
	return r


func _my_ready() -> bool:
	return bool(Net.peers.get(Net.my_id(), {}).get("ready", false))


const STATE_TEXT := {"esperando": "Esperando jugadores", "iniciando": "Iniciando partida…", "cargando": "Cargando…",
	"en_partida": "En partida"}


func _refresh() -> void:
	if not is_inside_tree():
		return
	_title.text = "SALA · " + Net.room_name.to_upper()
	var n_ready := 0
	for id in Net.peers:
		if bool(Net.peers[id].get("ready", false)):
			n_ready += 1
	var st := "%s · %d/%d jugadores · %d listos" % [STATE_TEXT.get(Net.lobby_state, Net.lobby_state), Net.peers.size(),
		Net.max_players, n_ready]
	if Net.is_host():
		st += "\nTu IP en la red local: %s:%d" % [", ".join(Net.lan_ips), Net.port]
		if Net.public_ip != "":
			st += " · por Internet: %s:%d" % [Net.public_ip, Net.port]
	else:
		st += "\nAnfitrión: %s" % Net.peers.get(1, {}).get("name", "?")
	_state.text = st
	for c in _list.get_children():
		c.queue_free()
	var ids: Array = Net.peers.keys()
	ids.sort()
	for id in ids:
		var e: Dictionary = Net.peers[id]
		var row := HBoxContainer.new()
		var nm := Label.new()
		nm.text = str(e.get("name", "?")) + ("  · tú" if int(id) == Net.my_id() else "")
		nm.custom_minimum_size = Vector2(190, 0)
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.clip_text = true
		var prof: Dictionary = NetSession.profile_from_dict(e.get("profile", {}))
		nm.add_theme_color_override("font_color", prof.get("accent", UiTheme.TEXT))
		row.add_child(nm)
		var sl := Label.new()
		sl.text = str(e.get("status", ""))
		sl.custom_minimum_size = Vector2(130, 0)
		row.add_child(sl)
		var pl := Label.new()
		pl.text = "—" if int(id) == 1 else "%d ms" % int(e.get("ping", 0))
		pl.custom_minimum_size = Vector2(60, 0)
		row.add_child(pl)
		var rl := Label.new()
		var rd := bool(e.get("ready", false))
		rl.text = "✔" if rd else "✗"
		rl.add_theme_color_override("font_color", UiTheme.OK if rd else UiTheme.DANGER)
		rl.custom_minimum_size = Vector2(60, 0)
		row.add_child(rl)
		if Net.is_host() and int(id) != 1 and Net.lobby_state == "esperando":
			var kick := Button.new()
			kick.text = "Expulsar"
			kick.pressed.connect(Net.kick.bind(int(id)))
			row.add_child(kick)
		_list.add_child(row)
	var waiting := Net.lobby_state == "esperando"
	_ready_btn.disabled = not waiting
	_ready_btn.text = ("NO ESTOY LISTO" if _my_ready() else "LISTO") if waiting else STATE_TEXT.get(Net.lobby_state, "")
	_host_box.visible = Net.is_host()
	_mode.disabled = not waiting
	_range.editable = waiting and Net.is_host()
	_start_btn.disabled = not (waiting and Net.all_ready())
	_start_btn.text = "INICIAR PARTIDA" if Net.all_ready() else "INICIAR PARTIDA (faltan jugadores por pulsar «Listo»)"


func _on_start() -> void:
	var cfg := {"new": _mode.selected == 0, "body": "moon", "lat": BaseLayout.SITE_LAT, "lon": BaseLayout.SITE_LON}
	if _mode.selected == 1:
		var d := SaveGame.load_data()
		if not d.is_empty():
			var ll := SaveGame.spawn_latlon(d)
			cfg = {"new": false, "body": str(d.get("anchor", "moon")), "lat": ll.x, "lon": ll.y}
	var err := Net.start_match(cfg)
	if err != "":
		_msg.text = err
