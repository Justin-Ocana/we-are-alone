class_name JournalPanel
extends CanvasLayer
## Diario de exploración (ADR-034): resumen, cuerpos visitados, escaneos y muestras con sus informes de
## laboratorio. Pantalla completa y modal; se maneja con ratón, teclado o mando (LB/RB cambian de pestaña).

var log: ExplorationLog
var world: SurfaceWorld
var _who: Astronaut
var _open := false
var _tabs: TabContainer
var _nexus_page: RichTextLabel
var _summary: RichTextLabel
var _visited: RichTextLabel
var _scans: RichTextLabel
var _samples: RichTextLabel


func _ready() -> void:
	layer = 15
	visible = false
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.build()
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.013, 0.013, 0.015, 0.94)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.06
	panel.anchor_right = 0.94
	panel.anchor_top = 0.06
	panel.anchor_bottom = 0.94
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var head := HBoxContainer.new()
	var t := Label.new()
	t.text = "DIARIO DE EXPLORACIÓN"
	t.add_theme_font_override("font", UiTheme.title_font())
	t.add_theme_font_size_override("font_size", 26)
	t.add_theme_color_override("font_color", UiTheme.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close_b := Button.new()
	close_b.text = "Cerrar"
	close_b.pressed.connect(close)
	head.add_child(close_b)
	box.add_child(head)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tabs)
	_summary = _page("Resumen")
	_visited = _page("Visitados")
	_scans = _page("Escaneos")
	_samples = _page("Muestras")
	_nexus_page = _page("NEXUS")
	var hint := Label.new()
	hint.text = "Esc / B / I cerrar · LB/RB o clic en las pestañas para cambiar · el diario se guarda con la partida"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	box.add_child(hint)


func _page(title: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.name = title
	r.bbcode_enabled = true
	r.focus_mode = Control.FOCUS_ALL
	r.add_theme_font_size_override("normal_font_size", 15)
	r.add_theme_font_size_override("bold_font_size", 17)
	_tabs.add_child(r)
	return r


func is_open() -> bool:
	return _open


func open_for(a: Astronaut) -> void:
	_who = a
	world.set_render_paused(true)
	_open = true
	visible = true
	a.input_blocked = true
	GameSettings.ui_modal = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()
	_tabs.get_tab_bar().grab_focus()


func close() -> void:
	world.set_render_paused(false)
	_open = false
	visible = false
	if _who != null:
		_who.input_blocked = false
	_who = null
	GameSettings.ui_modal = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"journal") or event.is_action_pressed(&"pause") \
			or event.is_action_pressed(&"p2_journal") or event.is_action_pressed(&"p2_pause"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			_tabs.current_tab = posmod(_tabs.current_tab - 1, _tabs.get_tab_count())
		elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			_tabs.current_tab = posmod(_tabs.current_tab + 1, _tabs.get_tab_count())


static func _date(unix: float) -> String:
	return Time.get_datetime_string_from_unix_time(int(unix), true).substr(0, 16)


func _refresh() -> void:
	var L := PackedStringArray()
	L.append("[b][color=#ff8c38]Resumen[/color][/b]")
	L.append("Cuerpo actual: [b]%s[/b]" % world.body.display_name)
	L.append("Cuerpos visitados: %d · escaneados: %d · muestras: %d (%d sin analizar)" % [log.visited.size(), log.scans.size(),
		log.samples.size(), log.pending_samples()])
	L.append("Distancia recorrida con la nave: %s" % Units.format_distance(log.ship_distance_m))
	L.append("Fotos: %d · tiempo de juego: %s" % [log.photos, MapPanel._duration(log.play_time_s)])
	if world.system != null:
		var total := 0
		for id in world.system.bodies:
			if world.system.body(id).kind in ["planet", "moon", "dwarf_planet"]:
				total += 1
		L.append("Planetas, lunas principales y planetas enanos del catálogo: %d" % total)
	L.append("")
	L.append("[color=#a2a4a8]Consejos: escanea con %s mirando a un planeta o luna; fuera de la nave, %s mirando al suelo recoge una muestra. " % [
		PlayerInput.glyph_for(&"scan", false), PlayerInput.glyph_for(&"scan", false)]
		+ "Las muestras se analizan en el laboratorio del almacén de la nave (F junto a la consola).[/color]")
	_summary.text = "\n".join(L)
	var V := PackedStringArray()
	if log.visited.is_empty():
		V.append("[color=#a2a4a8]Todavía no has pisado ningún cuerpo. Sal de la nave por la esclusa y camina.[/color]")
	for id in log.visited:
		var e: Dictionary = log.visited[id]
		V.append("[b]%s[/b] — primera visita %s%s" % [e.get("name", id), _date(float(e.get("first", 0))), " · aterrizaje" if e.get("landed", false) else ""])
	_visited.text = "\n".join(V)
	var S := PackedStringArray()
	if log.scans.is_empty():
		S.append("[color=#a2a4a8]Sin escaneos. Apunta a un cuerpo y pulsa %s (o ▶ en el mando).[/color]" % PlayerInput.glyph_for(&"scan", false))
	for id in log.scans:
		var e: Dictionary = log.scans[id]
		S.append("[b][color=#ffd485]%s[/color][/b]  [color=#a2a4a8]%s[/color]" % [e.get("name", id), _date(float(e.get("when", 0)))])
		for line in e.get("lines", []):
			S.append("    " + str(line))
		S.append("")
	_scans.text = "\n".join(S)
	var M := PackedStringArray()
	if log.samples.is_empty():
		M.append("[color=#a2a4a8]Sin muestras. Fuera de la nave, mira al suelo y pulsa %s.[/color]" % PlayerInput.glyph_for(&"scan", false))
	var i := 1
	for s in log.samples:
		M.append("[b]#%d %s[/b] (%.3f°, %.3f°) · %s · %s" % [i, s["name"], s["lat"], s["lon"], _date(float(s["when"])),
			"[color=#5f9]analizada[/color]" if s["analyzed"] else "[color=#fb4]pendiente de análisis[/color]"])
		if s["analyzed"]:
			for line in str(s["report"]).split("\n"):
				M.append("    " + line)
		M.append("")
		i += 1
	_samples.text = "\n".join(M)
	var N := PackedStringArray()
	N.append("[b][color=#ff8c38]NEXUS · cartografía universal de MacSpaces[/color][/b]")
	N.append("Componentes recuperados: [b]%d de 6[/b]" % log.nexus.size())
	N.append("")
	for id in NexusQuest.ORDER:
		var e: Array = NexusQuest.SITES[id]
		var bd: BodyDef = world.system.body(id) if world.system != null else null
		var nm: String = bd.display_name if bd != null else id
		var where := "dentro de la base lunar LF-01" if id == "moon" else "%.1f°, %.1f°" % [float(e[1]), float(e[2])]
		N.append("%s  [b]%s[/b] — %s (%s)" % ["[color=#5f9]✔[/color]" if id in log.nexus else "[color=#fb4]○[/color]", nm, e[0], where])
	N.append("")
	N.append("[color=#a2a4a8]En el mundo de cada componente, el objetivo marca la dirección y la distancia de su instalación. Las balizas (%s) ayudan a no perderse.[/color]" % PlayerInput.glyph_for(&"beacon", false))
	_nexus_page.text = "\n".join(N)
