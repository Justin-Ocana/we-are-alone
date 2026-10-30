class_name PlayerInput
extends RefCounted
## Entrada de UN jugador (ADR-032). Cada astronauta lee sus controles a través de su PlayerInput, nunca de
## `Input` directamente, para que en el cooperativo local cada jugador tenga los suyos:
## - Jugador 1: acciones sin prefijo (teclado y ratón + los mandos que no use el jugador 2).
## - Jugador 2: acciones con prefijo "p2_" (sólo su mando; las registra GameInput.configure_players).
## La mirada con mando (stick derecho) se convierte en "píxeles de ratón equivalentes" para reutilizar
## exactamente el mismo código que el ratón.

var slot := 0
var prefix := ""
var uses_mouse := true


static func for_slot(p_slot: int) -> PlayerInput:
	var pin := PlayerInput.new()
	pin.slot = p_slot
	pin.prefix = "" if p_slot == 0 else "p%d_" % (p_slot + 1)
	pin.uses_mouse = p_slot == 0
	return pin


func act(a: StringName) -> StringName:
	return a if prefix == "" else StringName(prefix + String(a))


func pressed(a: StringName) -> bool:
	return Input.is_action_pressed(act(a))


func just_pressed(a: StringName) -> bool:
	return Input.is_action_just_pressed(act(a))


func axis(neg: StringName, pos: StringName) -> float:
	return Input.get_axis(act(neg), act(pos))


func vector(left: StringName, right: StringName, back: StringName, fwd: StringName) -> Vector2:
	return Input.get_vector(act(left), act(right), act(back), act(fwd))


## ¿Este evento es una pulsación de la acción `a` de ESTE jugador?
func event_pressed(ev: InputEvent, a: StringName) -> bool:
	if not owns(ev):
		return false
	return ev.is_action_pressed(act(a))


## Eventos de ratón y teclado sólo pertenecen al jugador con ratón; los de mando, a quien tenga la acción.
func owns(ev: InputEvent) -> bool:
	if ev is InputEventMouse or ev is InputEventKey:
		return uses_mouse
	return true


## Movimiento del ratón de este jugador (cero si no es suyo).
func mouse_motion(ev: InputEvent) -> Vector2:
	if uses_mouse and ev is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		return ev.relative
	return Vector2.ZERO


## Stick derecho (−1..1), con zona muerta radial y respuesta cuadrática para apuntar con precisión.
func look_stick() -> Vector2:
	var v := Input.get_vector(act(&"look_left"), act(&"look_right"), act(&"look_up"), act(&"look_down"), 0.15)
	var l := v.length()
	if l < 1e-4:
		return Vector2.ZERO
	return v / l * l * l


## Mirada del stick en "píxeles de ratón" para este fotograma (misma escala que la sensibilidad del ratón).
func look_pixels(delta: float) -> Vector2:
	var s := look_stick()
	if s == Vector2.ZERO:
		return Vector2.ZERO
	var rate: float = GameSettings.pad_look_speed  # rad/s a fondo
	var px := s * rate * delta / maxf(GameSettings.mouse_sensitivity, 1e-5)
	if GameSettings.pad_invert_y:
		px.y = -px.y
	return px


const PAD_BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_START: "Start", JOY_BUTTON_BACK: "Select",
	JOY_BUTTON_DPAD_UP: "▲", JOY_BUTTON_DPAD_DOWN: "▼", JOY_BUTTON_DPAD_LEFT: "◀", JOY_BUTTON_DPAD_RIGHT: "▶",
}
const PAD_AXIS_NAMES := {
	JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT",
	JOY_AXIS_LEFT_X: "Stick izq.", JOY_AXIS_LEFT_Y: "Stick izq.",
	JOY_AXIS_RIGHT_X: "Stick der.", JOY_AXIS_RIGHT_Y: "Stick der.",
}
const KEY_NAMES := {KEY_SPACE: "Espacio", KEY_SHIFT: "Shift", KEY_CTRL: "Ctrl", KEY_ESCAPE: "Esc", KEY_TAB: "Tab",
	KEY_PERIOD: ".", KEY_COMMA: ",", KEY_ALT: "Alt", KEY_CAPSLOCK: "Bloq Mayús", KEY_QUOTELEFT: "º"}


## Nombre de la tecla o botón de la acción para este jugador ("F", "X", "LB"…), para las ayudas en pantalla.
func glyph(a: StringName) -> String:
	return glyph_for(a, not uses_mouse)


static func glyph_for(a: StringName, pad: bool) -> String:
	if pad:
		var specs: Array = GameInput.JOY_BINDINGS.get(a, [])
		if specs.is_empty():
			return "—"
		var sp: Array = specs[0]
		if sp.size() == 1:
			return PAD_BUTTON_NAMES.get(sp[0], "?")
		return PAD_AXIS_NAMES.get(sp[0], "?")
	var vb = GameSettings.voice_bindings.get(String(a))
	if vb is Array and (vb as Array).size() == 2:
		return GameInput.binding_name(vb)
	var keys: Array = GameInput.KEY_BINDINGS.get(a, [])
	if not keys.is_empty():
		return KEY_NAMES.get(keys[0], OS.get_keycode_string(keys[0]))
	var mb: Array = GameInput.MOUSE_BINDINGS.get(a, [])
	if not mb.is_empty():
		return {MOUSE_BUTTON_RIGHT: "Clic der.", MOUSE_BUTTON_WHEEL_UP: "Rueda", MOUSE_BUTTON_WHEEL_DOWN: "Rueda"}.get(mb[0], "Ratón")
	return "—"
