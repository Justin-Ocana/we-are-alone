class_name ShipPilotInput
extends RefCounted
## Esquemas de control de pilotaje (separados del de caminar), ADR-012 y ADR-016.
##
## ARCADE (por defecto): el ratón apunta la nave (respuesta directa) · W acelerar · S frenar (y marcha
## atrás si ya está parada) · A/D girar · Q/E alabeo · Espacio/Ctrl subir/bajar · Shift turbo · X parar
## en seco · L motor lumínico (lejos de los planetas) · Z piloto automático · T volver al planeta.
## SIMULACIÓN: palanca virtual con retorno lento, A/D deslizamiento lateral, 1–5 regímenes, J asistencia.

const STICK_SENS := 0.0065
const STICK_RETURN := 3.0     ## 1/s (simulación)
const ARCADE_SENS := 0.011
const ARCADE_RETURN := 11.0   ## 1/s: casi directo — la nave sigue al ratón
const DEADZONE := 0.02

var stick := Vector2.ZERO
var arcade := true


func on_mouse(rel: Vector2) -> void:
	stick = (stick + rel * (ARCADE_SENS if arcade else STICK_SENS)).limit_length(1.0)


func fill(c: ShipControls, dt: float, pin: PlayerInput = null) -> void:
	if pin == null:
		pin = PlayerInput.for_slot(0)
	stick *= exp(-(ARCADE_RETURN if arcade else STICK_RETURN) * dt)
	# Mando: el stick derecho es una palanca absoluta (sin retorno simulado); se suma al ratón.
	var pad := pin.look_stick()
	if GameSettings.pad_invert_y:
		pad.y = -pad.y
	var s := (stick + pad).limit_length(1.0)
	s = s if s.length() > DEADZONE else Vector2.ZERO
	c.pitch = clampf(-s.y, -1.0, 1.0)
	var lateral := pin.axis(&"ship_strafe_left", &"ship_strafe_right")
	if arcade:
		c.yaw = clampf(-s.x - lateral, -1.0, 1.0)  # A/D (stick izquierdo) giran la nave
		c.strafe = Vector2(0.0, pin.axis(&"ship_down", &"ship_up"))
		c.boost = pin.pressed(&"ship_boost")
	else:
		c.yaw = clampf(-s.x, -1.0, 1.0)
		c.strafe = Vector2(lateral, pin.axis(&"ship_down", &"ship_up"))
		c.boost = false
	c.roll = pin.axis(&"ship_roll_right", &"ship_roll_left")
	c.throttle = pin.axis(&"ship_throttle_down", &"ship_throttle_up")


## Acciones discretas. Devuelve true si el evento se ha consumido.
func handle_event(ev: InputEvent, ship: Ship, astro: Astronaut) -> bool:
	var pin := astro.pin
	if not arcade:
		for i in 5:
			if pin.event_pressed(ev, StringName("ship_regime_%d" % (i + 1))):
				ship.cmd_set_regime(i)
				return true
	if pin.event_pressed(ev, &"ship_gravity"):
		ship.cmd_toggle_artificial_gravity()
	elif pin.event_pressed(ev, &"ship_light"):
		ship.cmd_toggle_light()
	elif pin.event_pressed(ev, &"ship_stop"):
		ship.cmd_stop()
	elif pin.event_pressed(ev, &"ship_autopilot"):
		ship.cmd_toggle_autopilot(ShipState.Autopilot.HOLD)
	elif pin.event_pressed(ev, &"ship_approach"):
		ship.cmd_toggle_autopilot(ShipState.Autopilot.APPROACH)
	elif pin.event_pressed(ev, &"ship_assist") and not arcade:
		ship.cmd_toggle_assist()
	elif pin.event_pressed(ev, &"ship_floodlights"):
		ship.cmd_toggle_floodlights()
	elif pin.event_pressed(ev, &"ship_gear"):
		ship.cmd_toggle_gear()
	elif pin.event_pressed(ev, &"speed_up") and not astro.seated_looking():
		ship.cmd_adjust_target(1.25)
	elif pin.event_pressed(ev, &"speed_down") and not astro.seated_looking():
		ship.cmd_adjust_target(0.8)
	else:
		return false
	return true
