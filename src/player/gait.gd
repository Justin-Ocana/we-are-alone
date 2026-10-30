class_name Gait
extends RefCounted
## Modelo de marcha humana dependiente de la gravedad (ADR-009).
##
## - Número de Froude Fr = v²/(g·L), con L = altura de cadera.
## - Transición caminar→correr en Fr ≈ 0,5 (Carr & McGee 2009, sin traje, ~1 g).
## - Con traje y gravedad < 0,4 g los astronautas del Apolo pasaban a "loping" (salto sin cambio
##   de pie) a partir de Fr ≈ 0,36 (Carr & McGee 2009; Rader, Newman & Carr 2007).
## - Longitud de zancada relativa λ/L ≈ 2,3·Fr^0,3 (Alexander 1976, similitud dinámica).
## - Velocidades máximas en gravedad lunar ≈ 60 % de las terrestres (Hewes, Spady & Harris 1966).

enum Kind { IDLE, WALK, RUN, LOPE }

const G_EARTH := 9.80665
const LEG_LENGTH_M := 0.92        ## altura de cadera de un astronauta de 1,85 m
const FR_WALK_RUN := 0.5
const FR_LOPE_SUITED := 0.36
const LOW_G_RATIO := 0.4
const IDLE_SPEED := 0.12          ## m/s


static func froude(speed: float, g: float) -> float:
	return speed * speed / (maxf(g, 1e-3) * LEG_LENGTH_M)


static func select(speed: float, g: float) -> Kind:
	if speed < IDLE_SPEED:
		return Kind.IDLE
	var fr := froude(speed, g)
	if g < LOW_G_RATIO * G_EARTH:
		return Kind.LOPE if fr > FR_LOPE_SUITED else Kind.WALK
	return Kind.RUN if fr > FR_WALK_RUN else Kind.WALK


## Longitud de un ciclo completo (dos pasos) en metros.
static func stride_length(speed: float, g: float) -> float:
	var fr := maxf(froude(speed, g), 1e-4)
	return clampf(LEG_LENGTH_M * 2.3 * pow(fr, 0.3), 0.25, 3.4)


## Fracción del ciclo en que cada pie está apoyado.
static func duty_factor(kind: Kind) -> float:
	match kind:
		Kind.WALK:
			return 0.62
		Kind.RUN:
			return 0.36
		Kind.LOPE:
			return 0.34
	return 1.0


## Desfase entre piernas (fracción de ciclo): alterno al caminar/correr, casi en fase al "lopear".
static func leg_phase_offset(kind: Kind) -> float:
	return 0.14 if kind == Kind.LOPE else 0.5


## Factor de velocidad máxima según la gravedad (0,6 en la Luna, 1 en la Tierra).
static func max_speed_factor(g: float) -> float:
	var x := clampf((g / G_EARTH - 1.0 / 6.0) / (1.0 - 1.0 / 6.0), 0.0, 1.0)
	return lerpf(0.6, 1.0, x)


## Elevación (m) del cuerpo durante la fase aérea, por balística: h = g·t²/8.
static func flight_height(kind: Kind, speed: float, g: float) -> float:
	if kind == Kind.IDLE or kind == Kind.WALK or speed < IDLE_SPEED:
		return 0.0
	var period := stride_length(speed, g) / speed
	var duty := duty_factor(kind)
	var flight := 0.0
	if kind == Kind.RUN:
		flight = maxf(0.0, (1.0 - 2.0 * duty) * 0.5) * period  # dos fases aéreas por ciclo
	else:
		flight = maxf(0.0, 1.0 - duty - leg_phase_offset(kind)) * period  # una por ciclo
	return clampf(g * flight * flight / 8.0, 0.0, 0.35)
