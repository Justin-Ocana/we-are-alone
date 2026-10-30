class_name OnlinePanel
extends VBoxContainer
## Menú «En línea» (ADR-044): crear una sala alojada en este PC o unirse a una (red local o por IP). Nombre del
## jugador editable (es el mismo del perfil del astronauta), nombre de la sala, máximo de jugadores (2-6), puerto,
## apertura automática del puerto (UPnP) y partida nueva o continuar la guardada.

signal closed
signal start_requested(mode: String, opts: Dictionary)

var _tabs: TabContainer
var _status: Label
var _rooms_box: VBoxContainer
var _name: LineEdit
var _room: LineEdit
var _max: SpinBox
var _port: SpinBox
var _upnp: CheckButton
var _addr: LineEdit
var _join_btn: Button
var _busy := false


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var head := HBoxContainer.new()
	var t := Label.new()
	t.text = "EN LÍNEA"
	t.add_theme_font_override("font", UiTheme.title_font())
	t.add_theme_font_size_override("font_size", 26)
	t.add_theme_color_override("font_color", UiTheme.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var back := Button.new()
	back.text = "Volver"
	back.pressed.connect(func():
		Net.stop_browsing()
		if Net.is_client() and not _busy:
			Net.leave()
		closed.emit())
	head.add_child(back)
	add_child(head)
	_name = LineEdit.new()
	_name.text = Net.player_name()
	_name.max_length = 24
	_name.placeholder_text = "Tu nombre"
	_name.text_changed.connect(func(s: String):
		GameSettings.profiles[0]["name"] = s.strip_edges() if s.strip_edges() != "" else "Jugador"
		GameSettings.save_settings())
	_row(self, "Tu nombre", _name)
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(0, 330)
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_tabs)
	_build_host()
	_build_join()
	_tabs.tab_changed.connect(func(i: int):
		if i == 1:
			Net.start_browsing()
		else:
			Net.stop_browsing())
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", UiTheme.DATA)
	add_child(_status)
	Net.status_changed.connect(_on_status)
	Net.lan_rooms_changed.connect(_refresh_rooms)
	Net.join_failed.connect(func(r: String):
		_busy = false
		_join_btn.disabled = false
		_on_status(r))
	Net.joined.connect(func(w: Dictionary):
		_busy = true
		Net.stop_browsing()
		start_requested.emit("net_join", {"welcome": w}))
	# Cliente: el anfitrión nos ha admitido en la sala de espera.
	Net.lobby_changed.connect(func():
		if Net.is_client() and Net.lobby_state != "en_partida" and not _busy and Net.peers.has(Net.my_id()):
			_busy = true
			Net.stop_browsing()
			start_requested.emit("net_lobby", {}))


func focus_first() -> void:
	_name.grab_focus()


func _row(parent: Control, label: String, ctrl: Control, hint := "") -> void:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(190, 0)
	r.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(ctrl)
	parent.add_child(r)
	if hint != "":
		var h := Label.new()
		h.text = hint
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.add_theme_font_size_override("font_size", 13)
		h.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		parent.add_child(h)


func _page(title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	sc.add_child(v)
	return v


func _build_host() -> void:
	var v := _page("Crear sala")
	_room = LineEdit.new()
	_room.placeholder_text = "Sala de %s" % Net.player_name()
	_room.max_length = 32
	_row(v, "Nombre de la sala", _room)
	_max = SpinBox.new()
	_max.min_value = 2
	_max.max_value = NetSession.MAX_PLAYERS
	_max.value = NetSession.MAX_PLAYERS
	_row(v, "Jugadores (máx.)", _max)
	_port = SpinBox.new()
	_port.min_value = 1024
	_port.max_value = 65535
	_port.value = NetSession.DEFAULT_PORT
	_row(v, "Puerto (UDP)", _port)
	_upnp = CheckButton.new()
	_upnp.text = "Abrir el puerto automáticamente (UPnP)"
	_upnp.button_pressed = true
	_row(v, "Router", _upnp, "Si tu router no lo admite, en tu red local funciona igual. Por Internet: abre a mano el puerto UDP en el router, o usad una red virtual gratuita (ZeroTier, Tailscale o Radmin VPN) y uníos con la IP que os dé.")
	var go := Button.new()
	go.text = "CREAR SALA"
	go.custom_minimum_size = Vector2(0, 46)
	go.pressed.connect(_on_host)
	v.add_child(go)
	var ips := Label.new()
	ips.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ips.add_theme_font_size_override("font_size", 13)
	ips.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	ips.text = ("Tu IP en la red local: %s. Con UPnP, la IP pública aparece en la sala («Copiar dirección»).
" % (", ".join(Net.lan_ips) if not Net.lan_ips.is_empty() else "desconocida")) 		+ "La primera vez Windows preguntará por el Firewall: permite el acceso en redes privadas Y públicas, o tus amigos no podrán entrar. " 		+ "Todos deben tener el mismo .exe (v%s)." % NetSession.GAME_VERSION
	v.add_child(ips)


func _build_join() -> void:
	var v := _page("Unirse")
	var t := Label.new()
	t.text = "Salas en tu red local"
	t.add_theme_color_override("font_color", UiTheme.ACCENT)
	v.add_child(t)
	_rooms_box = VBoxContainer.new()
	_rooms_box.add_theme_constant_override("separation", 6)
	v.add_child(_rooms_box)
	_refresh_rooms()
	var sep := HSeparator.new()
	v.add_child(sep)
	_addr = LineEdit.new()
	_addr.placeholder_text = "IP del anfitrión (por ejemplo 192.168.1.20 o 25.x.x.x)"
	_row(v, "Dirección", _addr)
	_join_btn = Button.new()
	_join_btn.text = "UNIRSE"
	_join_btn.custom_minimum_size = Vector2(0, 42)
	_join_btn.pressed.connect(func(): _join(_addr.text, int(_port.value)))
	v.add_child(_join_btn)


func _refresh_rooms() -> void:
	if _rooms_box == null:
		return
	for c in _rooms_box.get_children():
		c.queue_free()
	if Net.lan_rooms.is_empty():
		var l := Label.new()
		l.text = "Buscando salas… (el anfitrión debe estar en la misma red)"
		l.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		_rooms_box.add_child(l)
		return
	for k in Net.lan_rooms:
		var r: Dictionary = Net.lan_rooms[k]
		var b := Button.new()
		b.text = "%s  ·  %s  ·  %d/%d jugadores" % [r.get("name", "Sala"), r.get("host", ""), int(r.get("players", 1)), int(r.get("max", 6))]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = int(r.get("players", 1)) >= int(r.get("max", 6))
		b.pressed.connect(_join.bind(str(r["ip"]), int(r.get("port", NetSession.DEFAULT_PORT))))
		_rooms_box.add_child(b)


func _join(address: String, p: int) -> void:
	if address.strip_edges() == "":
		_on_status("Escribe la IP del anfitrión o elige una sala de la lista.")
		return
	var a := address.strip_edges()
	if ":" in a:
		var parts := a.split(":")
		a = parts[0]
		p = int(parts[1])
	var err := Net.join(a, p)
	if err != "":
		_on_status(err)
	else:
		_join_btn.disabled = true


func _on_host() -> void:
	var err := Net.host(_room.text, int(_port.value), int(_max.value), _upnp.button_pressed)
	if err != "":
		_on_status(err)
		return
	Net.stop_browsing()
	_busy = true
	start_requested.emit("net_lobby", {})


func _on_status(t: String) -> void:
	if is_instance_valid(_status):
		_status.text = t
