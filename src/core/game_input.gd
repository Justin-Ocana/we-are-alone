extends Node
## Autoload `GameInput`: registra las acciones de entrada por código para que el proyecto
## no dependa de editar el mapa de entrada en el editor, y para permitir reasignaciones
## guardadas en GameSettings más adelante.
## Mando (disposición Xbox; ADR-032): cada acción tiene también botones/ejes de mando. En el cooperativo local,
## `configure_players` reparte los mandos: el jugador 2 recibe copias "p2_*" de todas las acciones ligadas
## SÓLO a su mando, y el jugador 1 conserva teclado, ratón y el resto de mandos.

const KEY_BINDINGS := {
	&"move_forward": [KEY_W, KEY_UP],
	&"move_back": [KEY_S, KEY_DOWN],
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"jump": [KEY_SPACE],
	&"sprint": [KEY_SHIFT],
	&"crouch_down": [KEY_CTRL, KEY_C],
	&"toggle_camera": [KEY_V],
	&"freelook": [KEY_ALT],
	&"interact": [KEY_F],
	&"toggle_fly": [KEY_N],
	&"lean_left": [KEY_Q],
	&"lean_right": [KEY_E],
	&"pause": [KEY_ESCAPE],
	&"toggle_hud": [KEY_F3],
	&"toggle_help": [KEY_F1],
	&"time_faster": [KEY_PERIOD],
	&"time_slower": [KEY_COMMA],
	# Pilotaje (sólo se leen sentado en el puesto de pilotaje).
	&"ship_throttle_up": [KEY_W],
	&"ship_throttle_down": [KEY_S],
	&"ship_strafe_left": [KEY_A],
	&"ship_strafe_right": [KEY_D],
	&"ship_up": [KEY_SPACE],
	&"ship_down": [KEY_CTRL, KEY_C],
	&"ship_roll_left": [KEY_Q],
	&"ship_roll_right": [KEY_E],
	&"ship_stop": [KEY_X],
	&"ship_boost": [KEY_SHIFT],
	&"ship_gravity": [KEY_G],
	&"recall_ship": [KEY_B],
	&"stabilize": [KEY_X],
	&"toggle_all_ui": [KEY_F2],
	&"music_panel": [KEY_M],
	&"toggle_map": [KEY_TAB],
	&"party_mode": [KEY_P],
	&"ship_light": [KEY_L],
	&"toggle_controls_help": [KEY_H],
	&"ship_autopilot": [KEY_Z],
	&"ship_approach": [KEY_T],
	&"ship_assist": [KEY_J],
	&"ship_regime_1": [KEY_1],
	&"ship_regime_2": [KEY_2],
	&"ship_regime_3": [KEY_3],
	&"ship_regime_4": [KEY_4],
	&"ship_regime_5": [KEY_5],
	&"scan": [KEY_R],
	&"journal": [KEY_I],
	&"photo": [KEY_F12],
	&"beacon": [KEY_O],
	# Voz en línea (ADR-046); reasignables en Opciones > Voz.
	&"voice_prox": [KEY_6],
	&"voice_radio": [KEY_CAPSLOCK],
	&"voice_ship": [KEY_QUOTELEFT],
	&"voice_channel": [KEY_7],
	&"ship_floodlights": [KEY_K],
	&"ship_gear": [KEY_U],
	&"quick_menu": [KEY_Y],
	&"emote_1": [KEY_1],
	&"emote_2": [KEY_2],
	&"emote_3": [KEY_3],
	&"emote_4": [KEY_4],
	&"look_left": [],
	&"look_right": [],
	&"look_up": [],
	&"look_down": [],
}

## Mando: acción → lista de [botón] o [eje, signo]. Botones = JoyButton, ejes = JoyAxis.
const JOY_BINDINGS := {
	&"move_forward": [[JOY_AXIS_LEFT_Y, -1.0]],
	&"move_back": [[JOY_AXIS_LEFT_Y, 1.0]],
	&"move_left": [[JOY_AXIS_LEFT_X, -1.0]],
	&"move_right": [[JOY_AXIS_LEFT_X, 1.0]],
	&"look_left": [[JOY_AXIS_RIGHT_X, -1.0]],
	&"look_right": [[JOY_AXIS_RIGHT_X, 1.0]],
	&"look_up": [[JOY_AXIS_RIGHT_Y, -1.0]],
	&"look_down": [[JOY_AXIS_RIGHT_Y, 1.0]],
	&"jump": [[JOY_BUTTON_A]],
	&"crouch_down": [[JOY_BUTTON_B]],
	&"interact": [[JOY_BUTTON_X]],
	&"toggle_camera": [[JOY_BUTTON_Y]],
	&"sprint": [[JOY_BUTTON_LEFT_STICK]],
	&"freelook": [[JOY_BUTTON_RIGHT_STICK]],
	&"focus": [[JOY_AXIS_TRIGGER_LEFT, 1.0]],
	&"lean_left": [[JOY_BUTTON_LEFT_SHOULDER]],
	&"lean_right": [[JOY_BUTTON_RIGHT_SHOULDER]],
	&"stabilize": [[JOY_BUTTON_DPAD_DOWN]],
	&"recall_ship": [[JOY_BUTTON_DPAD_UP]],
	&"scan": [[JOY_BUTTON_DPAD_RIGHT]],
	&"journal": [[JOY_BUTTON_DPAD_LEFT]],
	&"pause": [[JOY_BUTTON_START]],
	&"quick_menu": [[JOY_BUTTON_BACK]],
	&"voice_radio": [[JOY_BUTTON_MISC1]],
	&"ship_throttle_up": [[JOY_AXIS_TRIGGER_RIGHT, 1.0]],
	&"ship_throttle_down": [[JOY_AXIS_TRIGGER_LEFT, 1.0]],
	&"ship_strafe_left": [[JOY_AXIS_LEFT_X, -1.0]],
	&"ship_strafe_right": [[JOY_AXIS_LEFT_X, 1.0]],
	&"ship_up": [[JOY_BUTTON_A]],
	&"ship_down": [[JOY_BUTTON_B]],
	&"ship_roll_left": [[JOY_BUTTON_LEFT_SHOULDER]],
	&"ship_roll_right": [[JOY_BUTTON_RIGHT_SHOULDER]],
	&"ship_boost": [[JOY_BUTTON_LEFT_STICK]],
	&"ship_stop": [[JOY_BUTTON_DPAD_DOWN]],
	&"ship_autopilot": [[JOY_BUTTON_DPAD_LEFT]],
	&"ship_light": [[JOY_BUTTON_DPAD_UP]],
}
const MAX_PADS := 8
const DEADZONE := 0.2

## Mando asignado al jugador 2 (−1 = ninguno: partida de un jugador).
var p2_device := -1

const MOUSE_BINDINGS := {
	&"focus": [MOUSE_BUTTON_RIGHT],
	&"speed_up": [MOUSE_BUTTON_WHEEL_UP],
	&"speed_down": [MOUSE_BUTTON_WHEEL_DOWN],
	&"voice_radio": [MOUSE_BUTTON_XBUTTON1],
	&"voice_ship": [MOUSE_BUTTON_XBUTTON2],
}


func _enter_tree() -> void:
	register_actions()
	configure_players(-1)
	apply_voice_bindings()


const VOICE_ACTIONS := [&"voice_prox", &"voice_radio", &"voice_ship", &"voice_channel"]


## Teclas de voz reasignadas por el jugador (GameSettings.voice_bindings): sustituyen las de teclado y ratón por
## defecto; los botones de mando se conservan.
static func apply_voice_bindings() -> void:
	for action in VOICE_ACTIONS:
		var b = GameSettings.voice_bindings.get(String(action))
		if not b is Array or (b as Array).size() != 2:
			continue
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey or ev is InputEventMouseButton:
				InputMap.action_erase_event(action, ev)
		InputMap.action_add_event(action, binding_event(b))


static func binding_event(b: Array) -> InputEvent:
	if str(b[0]) == "mouse":
		var m := InputEventMouseButton.new()
		m.button_index = int(b[1])
		return m
	var k := InputEventKey.new()
	k.physical_keycode = int(b[1])
	return k


## Nombre legible de una asignación guardada.
static func binding_name(b: Array) -> String:
	if str(b[0]) == "mouse":
		return {MOUSE_BUTTON_LEFT: "Clic izq.", MOUSE_BUTTON_RIGHT: "Clic der.", MOUSE_BUTTON_MIDDLE: "Clic central",
			MOUSE_BUTTON_XBUTTON1: "Ratón 4", MOUSE_BUTTON_XBUTTON2: "Ratón 5"}.get(int(b[1]), "Ratón %d" % int(b[1]))
	return PlayerInput.KEY_NAMES.get(int(b[1]), OS.get_keycode_string(int(b[1])))


static func register_actions() -> void:
	for action in KEY_BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, DEADZONE)
			for key in KEY_BINDINGS[action]:
				var ev := InputEventKey.new()
				ev.physical_keycode = key
				InputMap.action_add_event(action, ev)
	for action in MOUSE_BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, DEADZONE)
			for button in MOUSE_BINDINGS[action]:
				var ev := InputEventMouseButton.new()
				ev.button_index = button
				InputMap.action_add_event(action, ev)
	for action in JOY_BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, DEADZONE)


static func _joy_event(spec: Array, device: int) -> InputEvent:
	if spec.size() == 1:
		var b := InputEventJoypadButton.new()
		b.button_index = spec[0]
		b.device = device
		return b
	var m := InputEventJoypadMotion.new()
	m.axis = spec[0]
	m.axis_value = spec[1]
	m.device = device
	return m


## Reparte los mandos. `p2` = id del mando del jugador 2, o −1 para una partida de un jugador (todos los mandos
## controlan al jugador 1). Se puede llamar varias veces (vuelve a crear los eventos de mando).
func configure_players(p2: int) -> void:
	p2_device = p2
	for action in JOY_BINDINGS:
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				InputMap.action_erase_event(action, ev)
		var p2a := StringName("p2_" + String(action))
		if InputMap.has_action(p2a):
			InputMap.erase_action(p2a)
		for spec in JOY_BINDINGS[action]:
			if p2 < 0:
				InputMap.action_add_event(action, _joy_event(spec, -1))
			else:
				for d in MAX_PADS:
					if d != p2:
						InputMap.action_add_event(action, _joy_event(spec, d))
	if p2 < 0:
		return
	# Jugador 2: copia de TODAS las acciones (también las que sólo tienen teclado, para que existan) con
	# los eventos de su mando únicamente.
	for action in InputMap.get_actions():
		var name := String(action)
		if name.begins_with("ui_") or name.begins_with("p2_"):
			continue
		var p2a := StringName("p2_" + name)
		if not InputMap.has_action(p2a):
			InputMap.add_action(p2a, DEADZONE)
		for spec in JOY_BINDINGS.get(action, []):
			InputMap.action_add_event(p2a, _joy_event(spec, p2))


## Nombre legible del mando (o "—").
static func pad_name(device: int) -> String:
	if device < 0 or not Input.get_connected_joypads().has(device):
		return "—"
	return Input.get_joy_name(device)
