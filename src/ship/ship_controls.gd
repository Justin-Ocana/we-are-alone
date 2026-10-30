class_name ShipControls
extends RefCounted
## Entradas instantáneas de pilotaje (de un jugador, del piloto automático o, en el futuro, de la red).

var pitch := 0.0      ## +1 morro arriba
var yaw := 0.0        ## +1 morro a la izquierda
var roll := 0.0       ## +1 alabeo a la izquierda
var strafe := Vector2.ZERO  ## x: lateral (+derecha), y: vertical (+arriba), -1..1
var throttle := 0.0   ## -1..1: cambia la velocidad objetivo (o empuje directo sin asistencia)
var boost := false    ## turbo (arcade)


func manual_magnitude() -> float:
	return maxf(maxf(absf(pitch), absf(yaw)), maxf(absf(roll), strafe.length()))


func clear() -> void:
	pitch = 0.0
	yaw = 0.0
	roll = 0.0
	strafe = Vector2.ZERO
	throttle = 0.0
	boost = false
