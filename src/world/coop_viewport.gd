class_name CoopViewport
extends SubViewportContainer
## Media pantalla de un jugador en el cooperativo local (ADR-032).
## El SubViewport comparte el World3D de la ventana (física, luces y entorno son los mismos); dentro viven el
## astronauta de ese jugador, su ViewManager y sus interfaces, así que sus cámaras y CanvasLayers se dibujan
## sólo en su mitad sin código especial.
## La entrada NO se propaga por el contenedor: SurfaceWorld la reparte a cada jugador según su dispositivo
## (con el ratón capturado, la posición del cursor no sirve para saber de quién es un evento).

var viewport: SubViewport
var slot := 0


func _init(p_slot: int) -> void:
	slot = p_slot
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport = SubViewport.new()
	viewport.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # los viewports no heredan: sólo naves y astronautas interpolan (ADR-042)
	viewport.name = "Jugador%d" % (p_slot + 1)
	viewport.handle_input_locally = false
	viewport.audio_listener_enable_3d = true
	viewport.scaling_3d_scale = float(GameSettings.coop_preset()["render_scale"])
	add_child(viewport)


func _propagate_input_event(_event: InputEvent) -> bool:
	return false
