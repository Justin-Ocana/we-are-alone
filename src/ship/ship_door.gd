class_name ShipDoor
extends RefCounted
## Puerta corredera de la nave (ADR-013). La hoja es una malla dinámica y una forma de colisión dentro del
## cuerpo físico de la nave; se desliza dentro de la pared. Su estado (`open`, 0..1) forma parte del
## estado replicable de la nave (ShipState.doors).
##
## - Modo automático: se abre cuando algún astronauta está a menos de `sense_radius`.
## - Modo controlado (esclusa): `target` lo fija ShipAirlock; nunca se cierra sobre alguien en el umbral.

const SPEED := 1.6           ## fracción por segundo (≈0,6 s para abrir)
const PANEL_T := 0.08

var id := ""
var center := Vector3.ZERO   ## centro del vano a nivel del suelo (espacio de la nave)
var normal_axis := "x"       ## la pared es perpendicular a este eje
var width := ShipLayout.DOOR_WIDTH
var height := ShipLayout.DOOR_HEIGHT
var automatic := true
var sense_radius := 1.7
var open := 0.0
var target := 0.0
var mesh: MeshInstance3D
var _moving := 0
var shape: CollisionShape3D


## Desplazamiento de la hoja al abrir: a lo largo de la pared.
func slide_dir() -> Vector3:
	return Vector3(0, 0, 1) if normal_axis == "x" else Vector3(1, 0, 0)


func panel_size() -> Vector3:
	return Vector3(PANEL_T, height, width) if normal_axis == "x" else Vector3(width, height, PANEL_T)


func closed_position() -> Vector3:
	return center + Vector3(0, height * 0.5, 0)


## ¿Hay alguien dentro del vano (no se puede cerrar)?
func is_blocked(local_points: Array) -> bool:
	for p: Vector3 in local_points:
		var d := p - center
		var across := absf(d.x) if normal_axis == "x" else absf(d.z)
		var along := absf(d.z) if normal_axis == "x" else absf(d.x)
		if across < 0.45 and along < width * 0.5 + 0.2 and d.y > -0.5 and d.y < height:
			return true
	return false


## `local_points` = posiciones (espacio de la nave) de los astronautas cercanos.
func update(dt: float, local_points: Array) -> void:
	if automatic:
		target = 0.0
		for p: Vector3 in local_points:
			if Vector2(p.x - center.x, p.z - center.z).length() < sense_radius and absf(p.y - center.y) < 2.5:
				target = 1.0
				break
	if target < open and is_blocked(local_points):
		target = open  # seguridad: no cerrar sobre un astronauta
	# Sonido neumático al empezar a abrirse o a cerrarse (ADR-038).
	var moving_to := 1 if target > open + 0.001 else (-1 if target < open - 0.001 else 0)
	if moving_to != 0 and moving_to != _moving and mesh != null and mesh.get_parent() is Node3D:
		GameAudio.play_at("door_open" if moving_to > 0 else "door_close", mesh.get_parent(), center + Vector3(0, 1.2, 0), -6.0, 25.0)
	_moving = moving_to
	open = move_toward(open, target, SPEED * dt)
	var pos := closed_position() + slide_dir() * open * (width + 0.05)
	if mesh != null:
		mesh.position = pos
		mesh.visible = open < 0.999
	if shape != null:
		shape.position = pos
		shape.disabled = open > 0.85


func is_closed() -> bool:
	return open <= 0.001


func is_open() -> bool:
	return open >= 0.999
