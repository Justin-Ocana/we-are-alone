class_name ShipState
extends RefCounted
## Estado replicable de una nave (ADR-012): todo lo que habría que sincronizar en red.
## No contiene nodos ni referencias a jugadores concretos, sólo identificadores.

enum Autopilot { OFF, HOLD, APPROACH, RECALL, TRAVEL }

# --- Física (marco BF del cuerpo dominante, doble precisión en la posición)
var pos_bf := DVec3.new()
var basis := Basis()                 ## orientación en el marco BF
var velocity := Vector3.ZERO         ## m/s, marco BF
var ang_vel := Vector3.ZERO          ## rad/s en ejes de la nave (pitch X, yaw Y, roll Z)
var landed := false
var gear_deployed := true

# --- Pilotaje
var regime := 0
var target_speed := 0.0              ## m/s a lo largo de -Z de la nave (negativo = marcha atrás)
var flight_assist := true
var arcade := true                   ## modo de vuelo sencillo (por defecto); false = simulación
var speed_cap := 60.0                ## velocidad máxima disponible ahora (arcade: crece con la altitud)
var braking := false                 ## frenado de emergencia en curso (X)
var engine_output := 0.0             ## 0..1 (indicadores de la sala de máquinas)
var light_spool := 0.0               ## s acumulados cargando el motor lumínico
var light_active := false
var autopilot := Autopilot.OFF
var autopilot_heading := Vector3.FORWARD  ## dirección BF a mantener
var autopilot_speed := 0.0
var pilot_id := -1                   ## instance_id del astronauta en el asiento (-1 = vacío)
var autopilot_up := Vector3.UP      ## "arriba" de la nave al activar HOLD (conserva la inclinación)
var autopilot_target := DVec3.new()  ## destino BF del modo RECALL (llamada a la nave)
var brake_accel := 0.0              ## m/s² del frenado de emergencia en curso (fijado al pulsar X)
var warp := 1.0                     ## multiplicador del motor lumínico (salto FICTICIO, ADR-028)
var travel_target := ""              ## cuerpo de destino del piloto automático de viaje
var travel_dir := Vector3.FORWARD    ## dirección de viaje (marco del motor), la calcula Ship
var travel_remaining := 0.0          ## m hasta el punto de llegada
var floodlights := false             ## focos exteriores (K)
var gear_hold := false               ## tren desplegado a mano (U); si no, automático
var travel_free := false             ## viaje en un cuerpo sin suelo (gigante): sin tope Arcade por altitud
var travel_climb := false            ## ascenso vertical inicial (junto al suelo)
# Entorno y casco (ADR-029)
var hull_integrity := 100.0          ## %
var hull_temperature := 290.0        ## K (temperatura de la piel del casco)
var ext_pressure := 0.0              ## Pa
var ext_temperature := 0.0           ## K
var dyn_pressure := 0.0              ## Pa (½ρv² respecto al aire)
var heat_flux := 0.0                 ## W/m² (calentamiento convectivo + radiación solar absorbida)
var wind_speed := 0.0                ## m/s (viento zonal en la posición de la nave)
var plasma := 0.0                    ## 0..1 (plasma de entrada visible)
var atmo_speed_limit := INF          ## m/s: limitador atmosférico (Arcade)
var altitude := 0.0                  ## m sobre el radio de referencia (lo fija el modelo de vuelo)
var takeoff_t := 999.0               ## s desde el último despegue (rampa de aceleración, ronda 11)
var party := false                   ## modo fiesta: luces de discoteca
var music_title := ""                ## pista que suena por la megafonía (ADR-022)
var music_playing := false
var artificial_gravity := false      ## false = realista: gravedad del planeta + inercia de la nave
var seats := {}                      ## id de asiento -> instance_id del ocupante

# --- Esclusa y puertas: nombre -> fracción abierta (0..1)
var doors := {}
var airlock_phase := "sellada"

# --- Mensajes para la interfaz (último evento)
var event_text := ""
var event_time := 0.0


func forward() -> Vector3:
	return -basis.z


func speed() -> float:
	return velocity.length()


## Velocidad con signo a lo largo del morro.
func forward_speed() -> float:
	return velocity.dot(forward())


func post_event(text: String) -> void:
	event_text = text
	event_time = 4.0


func to_dict() -> Dictionary:
	return {
		"pos": pos_bf.to_array(), "basis": [basis.x, basis.y, basis.z], "vel": velocity,
		"ang_vel": ang_vel, "landed": landed, "regime": regime, "target": target_speed,
		"assist": flight_assist, "autopilot": autopilot, "ap_heading": autopilot_heading,
		"ap_speed": autopilot_speed, "pilot": pilot_id, "doors": doors.duplicate(),
		"airlock": airlock_phase, "light": light_active,
	}
