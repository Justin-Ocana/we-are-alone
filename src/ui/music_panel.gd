class_name MusicPanel
extends CanvasLayer
## Panel de música de la nave (ADR-022): se abre con M sentado en cualquier asiento de la nave (los puestos
## de ingeniería y comunicaciones tienen además la pantalla con la pista actual). Mientras está abierto el
## ratón queda libre y el teclado no mueve al astronauta ni pilota la nave. M o Esc lo cierran.

var astronaut: Astronaut
var _panel: PanelContainer
var _now: Label
var _time: Label
var _seek: HSlider
var _play: Button
var _vol: HSlider
var _url: LineEdit
var _status: Label
var _list: ItemList
var _music: ShipMusic
var _seeking := false
var _open := false


func _ready() -> void:
	layer = 15
	visible = false
	_panel = PanelContainer.new()
	_panel.theme = UiTheme.build()
	_panel.custom_minimum_size = Vector2(640, 0)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)
	var title := Label.new()
	title.text = "MÚSICA DE LA NAVE"
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	_now = Label.new()
	_now.text = "—"
	_now.add_theme_font_size_override("font_size", 18)
	_now.clip_text = true
	box.add_child(_now)
	var row := HBoxContainer.new()
	_seek = HSlider.new()
	_seek.max_value = 1.0
	_seek.step = 0.001
	_seek.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seek.drag_started.connect(func(): _seeking = true)
	_seek.drag_ended.connect(func(_c: bool):
		_seeking = false
		if _music != null:
			_music.seek_fraction(_seek.value))
	row.add_child(_seek)
	_time = Label.new()
	_time.custom_minimum_size = Vector2(110, 0)
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_time)
	box.add_child(row)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	for spec in [["⏮", func(): _music.previous()], ["▶", func(): _music.toggle_pause()], ["⏭", func(): _music.next()],
			["⏹", func(): _music.stop()]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(54, 40)
		b.focus_mode = Control.FOCUS_NONE
		var cb: Callable = spec[1]
		b.pressed.connect(func():
			if _music != null:
				cb.call())
		controls.add_child(b)
		if spec[0] == "▶":
			_play = b
	var vl := Label.new()
	vl.text = "   Volumen"
	controls.add_child(vl)
	_vol = HSlider.new()
	_vol.min_value = -30.0
	_vol.max_value = 6.0
	_vol.step = 0.5
	_vol.value = -6.0
	_vol.custom_minimum_size = Vector2(150, 0)
	_vol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_vol.value_changed.connect(func(v: float):
		if _music != null:
			_music.set_volume(v))
	_vol.drag_ended.connect(func(_c: bool): GameSettings.save_settings())
	controls.add_child(_vol)
	box.add_child(controls)
	_sound_settings(box)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 150)
	_list.item_activated.connect(func(i: int):
		if _music != null:
			_music.play_index(i))
	box.add_child(_list)
	var url_row := HBoxContainer.new()
	_url = LineEdit.new()
	_url.placeholder_text = "Pega un enlace directo a un archivo .mp3 / .ogg"
	_url.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_url.text_submitted.connect(func(t: String): _play_url(t))
	url_row.add_child(_url)
	var go := Button.new()
	go.text = "Reproducir enlace"
	go.pressed.connect(func(): _play_url(_url.text))
	url_row.add_child(go)
	box.add_child(url_row)
	var folder_row := HBoxContainer.new()
	var open_dir := Button.new()
	open_dir.text = "Abrir carpeta de música"
	open_dir.pressed.connect(func(): OS.shell_open(ProjectSettings.globalize_path("user://music")))
	folder_row.add_child(open_dir)
	var refresh := Button.new()
	refresh.text = "Actualizar lista"
	refresh.pressed.connect(func():
		if _music != null:
			_music.rescan())
	folder_row.add_child(refresh)
	box.add_child(folder_row)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(600, 0)
	_status.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_status.add_theme_font_size_override("font_size", 14)
	_status.text = "Suena limpio en el puente y por los altavoces en el resto de la nave. En línea, lo que pongas lo oyen todos (se les envía la canción). M o Esc para cerrar."
	box.add_child(_status)


func _play_url(t: String) -> void:
	if _music != null and t.strip_edges() != "":
		_music.play_url(t)


func is_open() -> bool:
	return _open


## Abre el reproductor para un jugador concreto (menú rápido; en el cooperativo, también el jugador 2).
func open_for(a: Astronaut) -> void:
	if _home == null:
		_home = astronaut
	if a.seated and a.aboard != null:
		astronaut = a
		open()


var _home: Astronaut = null


func _input(event: InputEvent) -> void:
	if astronaut == null:
		return
	var key_m := event.is_action_pressed(&"music_panel") and not _url.has_focus()
	var cancel := event.is_action_pressed(&"ui_cancel") and not _url.has_focus()
	if _open and (key_m or cancel or event.is_action_pressed(&"pause")):
		close()
		get_viewport().set_input_as_handled()
	elif not _open and key_m and astronaut.seated and astronaut.aboard != null:
		open()
		get_viewport().set_input_as_handled()


func open() -> void:
	_bind(astronaut.aboard.music)
	_open = true
	visible = true
	astronaut.input_blocked = true
	GameSettings.ui_modal = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_list()


func close() -> void:
	_open = false
	visible = false
	_url.release_focus()
	if astronaut != null:
		astronaut.input_blocked = false
	if _home != null:
		astronaut = _home
	GameSettings.ui_modal = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Ajustes de sonido de la megafonía (ronda 14). Se guardan al soltar cada control.
func _sound_settings(box: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	var db := func(x: float) -> String: return "%+d dB" % int(round(x))
	_knob(grid, "Altavoces", -20.0, 6.0, 0.5, GameSettings.ship_speaker_db, func(x: float): GameSettings.ship_speaker_db = x, db,
		"Volumen en el resto de la nave respecto al puente (allí suena limpio).")
	_knob(grid, "Efecto altavoz", 0.0, 1.0, 0.05, GameSettings.ship_speaker_fx, func(x: float): GameSettings.ship_speaker_fx = x,
		func(x: float) -> String: return "%d %%" % int(round(x * 100.0)), "0 % = limpio en toda la nave; 100 % = megafonía metálica.")
	_knob(grid, "Graves", -12.0, 12.0, 0.5, GameSettings.ship_bass_db, func(x: float): GameSettings.ship_bass_db = x, db, "")
	_knob(grid, "Agudos", -12.0, 12.0, 0.5, GameSettings.ship_treble_db, func(x: float): GameSettings.ship_treble_db = x, db, "")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var order := OptionButton.new()
	var orders := ["lista", "aleatorio", "repetir"]
	for o in ["En orden", "Aleatorio", "Repetir canción"]:
		order.add_item(o)
	order.select(maxi(0, orders.find(GameSettings.ship_music_order)))
	order.focus_mode = Control.FOCUS_NONE
	order.item_selected.connect(func(i: int):
		GameSettings.ship_music_order = orders[i]
		GameSettings.save_settings())
	row.add_child(order)
	for spec in [["Bajar al hablar", GameSettings.ship_music_duck, func(on: bool): GameSettings.ship_music_duck = on,
			"Baja la música mientras suena un diálogo o habla un compañero."],
			["Oír fuera (radio del traje)", GameSettings.ship_music_outside, func(on: bool): GameSettings.ship_music_outside = on,
			"Fuera de la nave no hay aire: sólo se oye si la retransmite tu traje, bajito y con sonido de radio."]]:
		var c := CheckBox.new()
		c.text = spec[0]
		c.button_pressed = spec[1]
		c.tooltip_text = spec[3]
		c.focus_mode = Control.FOCUS_NONE
		var cb: Callable = spec[2]
		c.toggled.connect(func(on: bool):
			cb.call(on)
			GameSettings.save_settings())
		row.add_child(c)
	box.add_child(row)


func _knob(grid: GridContainer, label: String, lo: float, hi: float, step: float, value: float, cb: Callable, fmt: Callable,
		tip: String) -> void:
	var l := Label.new()
	l.text = label
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(l)
	var box := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(120, 0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	s.tooltip_text = tip
	var v := Label.new()
	v.text = fmt.call(value)
	v.custom_minimum_size = Vector2(56, 0)
	v.add_theme_color_override("font_color", UiTheme.ACCENT)
	s.value_changed.connect(func(x: float):
		cb.call(x)
		v.text = fmt.call(x))
	s.drag_ended.connect(func(_c: bool): GameSettings.save_settings())
	box.add_child(s)
	box.add_child(v)
	grid.add_child(box)


func _bind(m: ShipMusic) -> void:
	if m == _music:
		return
	if _music != null:
		_music.changed.disconnect(_refresh_list)
		_music.status.disconnect(_on_status)
	_music = m
	_music.changed.connect(_refresh_list)
	_music.status.connect(_on_status)
	_vol.value = _music.volume_db


func _on_status(text: String) -> void:
	_status.text = text


func _refresh_list() -> void:
	if _music == null:
		return
	_list.clear()
	for t in _music.tracks:
		_list.add_item(t["title"])
	if _music.current >= 0 and _music.current < _list.item_count:
		_list.select(_music.current)
	if _music.tracks.is_empty():
		_status.text = "No hay canciones. Copia archivos MP3/OGG en tu carpeta Música o en la carpeta de música del juego " \
			+ "(botón «Abrir carpeta de música») y pulsa «Actualizar lista»."


func _process(_delta: float) -> void:
	if not _open or _music == null:
		return
	if astronaut == null or not astronaut.seated:
		close()
		return
	var t := _music.title()
	_now.text = (("♪ " + t) + ("   · la pone %s" % _music.remote_dj if _music.remote else "")) if t != "" else "— sin reproducir —"
	_play.text = "⏸" if _music.is_playing() else "▶"
	var length := _music.length()
	if not _seeking:
		_seek.value = _music.position() / length if length > 0.0 else 0.0
	_time.text = "%s / %s" % [_fmt(_music.position()), _fmt(length)]
	var vp := get_viewport().get_visible_rect().size
	_panel.position = Vector2(vp.x - _panel.size.x - 30.0, (vp.y - _panel.size.y) * 0.5)


static func _fmt(s: float) -> String:
	var i := int(s)
	return "%d:%02d" % [i / 60, i % 60]
