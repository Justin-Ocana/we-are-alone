class_name PrologueDirector
extends Node
## Prólogo de «WE ARE ALONE?» en la base lunar LF-01 (ADR-043). Máquina de estados por pasos con objetivos y
## marcador, audios disparados por EVENTOS (nunca por tiempo), puertas que se abren según avanza la historia y
## textos de los terminales. Sigue vivo tras completarse para los terminales opcionales.
##
## Recorrido: despertar en la cápsula → terminal médico → pasillo de recuperación → sala de orientación → mensaje
## de Magnus Blackwell (obligatorio; Espacio lo omite) → centro de operaciones → energía auxiliar → hangar →
## diagnóstico de la nave → traje EVA y oxígeno → ciclo de la esclusa → superficie lunar (fin del prólogo).

signal completed

const STEPS := ["despertar", "salir_capsula", "terminal_medico", "orientacion", "pantalla", "mensaje", "operaciones",
	"consola", "energia", "restableciendo", "hangar", "diagnostico", "traje", "oxigeno", "esclusa", "despresurizando",
	"salir", "completado"]

## paso → [texto del objetivo, punto (BaseLayout.POINTS o TERMINALS)]
const OBJECTIVES := {
	"despertar": ["Reanimación en curso. Mantén la calma.", ""],
	"salir_capsula": ["Sal de la cápsula criogénica", "capsula"],
	"terminal_medico": ["Consulta el terminal médico junto a tu cápsula", "terminal_medico"],
	"orientacion": ["Sigue la señalización hasta la sala de orientación", "orientacion"],
	"pantalla": ["Acércate a la pantalla de la sala de orientación", "pantalla"],
	"mensaje": ["Escucha el mensaje", ""],
	"operaciones": ["Dirígete al centro de operaciones", "operaciones"],
	"consola": ["Usa la consola central del centro de operaciones", "consola_ops"],
	"energia": ["Activa la energía auxiliar en la sala de energía", "energia_aux"],
	"restableciendo": ["Restableciendo la energía auxiliar…", ""],
	"hangar": ["Ve al hangar principal por el eje central", "hangar"],
	"diagnostico": ["Haz el diagnóstico de la nave en el panel del hangar", "diagnostico"],
	"traje": ["Equípate un traje EVA en la esclusa", "traje"],
	"oxigeno": ["Comprueba el oxígeno y la conexión del traje", "traje"],
	"esclusa": ["Inicia el ciclo de la esclusa", "panel_esclusa"],
	"despresurizando": ["Espera a que termine la despresurización", ""],
	"salir": ["Sal a la superficie lunar", "exterior"],
	"completado": ["Explora. Cuando quieras despegar, la «Esperanza» te espera en el hangar (techo abierto).", "nave"],
}

## Terminal opcional → [audio, título, líneas]
const OPTIONAL := {
	"generador": ["p23", "GENERADOR PRINCIPAL G-1", [
		"Estado: FUERA DE SERVICIO · núcleo en parada fría.",
		"Último arranque registrado: [FECHA CORRUPTA].",
		"Daños en la carcasa compatibles con una sobrecarga deliberada.",
		"Recomendación del sistema: usar la red auxiliar."]],
	"enfermeria": ["p24", "ENFERMERÍA · REGISTRO", [
		"Pacientes atendidos en la última semana: 14. Altas: 3.",
		"Nota de la Dra. E. Varga: «Ya no quedan sedantes. Preparad las cápsulas».",
		"Evacuación médica: INICIADA · no se registró su final.",
		"Dos camillas siguen ocupadas en el inventario. Están vacías."]],
	"cultivos": ["p25", "SISTEMA DE CULTIVOS", [
		"Bandejas viables: 11 %. Riego automático: activo (reservas al 4 %).",
		"Las lámparas de crecimiento siguen encendidas por un error de programación.",
		"Especies supervivientes: patata, soja, musgo de control.",
		"Alguien dejó escrito en una bandeja: «NO REGAR LA 7»."]],
	"consola_com": ["p26", "COMUNICACIONES", [
		"Enlace Tierra: SIN PORTADORA. Repetidores: 0 de 6.",
		"Última transmisión recibida: ruido. Duración: 41 min.",
		"Baliza de socorro de LF-01: emitiendo en bucle desde hace [DESBORDAMIENTO].",
		"Nadie ha contestado."]],
	"telescopio": ["p27", "OBSERVATORIO", [
		"Objetivo actual: la Tierra.",
		"El telescopio sigue apuntando a ella desde hace años.",
		"Las anotaciones del operador terminan a mitad de una frase."]],
	"lab_exp": ["p28", "LABORATORIO EXPERIMENTAL", [
		"Contenedor C-3: integridad comprometida.",
		"Proyecto: HORIZONS · fase 2 · acceso de nivel ejecutivo.",
		"Contenido: [CLASIFICADO]. Temperatura interior: −40 °C y bajando.",
		"Registro de seguridad: desactivado manualmente."]],
	"archivo": ["p29", "ARCHIVO DIGITAL", [
		"Registros íntegros: 23 %. Sectores dañados: 4.112.",
		"«Plantilla de LF-01: 38 personas. Criopreservados: 12. Resto: [SIN DATOS]».",
		"«Orden de evacuación al transbordador ATLAS: CANCELADA».",
		"Hay un expediente a tu nombre. Está vacío."]],
	"capsulas_resto": ["p30", "CÁPSULAS CRIOGÉNICAS", [
		"Cápsula 02: ocupada · constantes estables · reanimación NO autorizada.",
		"Cápsula 04: vacía. Cápsula 06: FALLO · sin constantes.",
		"Cápsula 07: ocupada · etiqueta ilegible bajo la escarcha.",
		"El sistema sólo tenía orden de despertar a una persona."]],
	"terminal_nexus": ["p32", "NEXUS · CARTOGRAFÍA UNIVERSAL", [
		"Componentes localizados: 0 de 6.",
		"Ubicaciones asignadas: Luna, Mercurio, Venus, Marte, Europa, Titán.",
		"Componente lunar: «sección de mantenimiento, sector restringido».",
		"Mapa estelar: incompleto. Rutas calculables: ninguna."]],
}

var world: SurfaceWorld
var base: LunarBase
var dialogue: DialogueDirector
var hud: StoryHud
var step := "despertar"
var flags := {}
var active := true                 ## false: partida antigua o prólogo superado al empezar (sin objetivos)
var mirror := false                ## cliente en línea: sólo refleja lo que manda el anfitrión (ADR-044)
var _seq: Array = []               ## líneas encadenadas pendientes
var _seq_done := Callable()
var _timer := 0.0
var _task := ""                    ## tarea con barra de progreso ("energia", "diagnostico", "oxigeno")
var _task_t := 0.0
var _screen_wait := 0.0


func setup(p_world: SurfaceWorld, p_base: LunarBase, p_dialogue: DialogueDirector, p_hud: StoryHud) -> void:
	world = p_world
	base = p_base
	dialogue = p_dialogue
	hud = p_hud
	base.interacted.connect(_on_interact)
	base.room_entered.connect(_on_room)
	base.door_denied.connect(_on_door_denied)
	dialogue.line_finished.connect(_on_line_finished)


func idx(s: String) -> int:
	return STEPS.find(s)


func at_least(s: String) -> bool:
	return idx(step) >= idx(s)


## Avanza (nunca retrocede) y actualiza el objetivo.
func advance(s: String) -> void:
	if idx(s) < idx(step):
		return
	step = s
	_refresh_objective()


func _refresh_objective() -> void:
	if hud == null:
		return
	if not active:
		hud.set_objective("")
		return
	var o: Array = OBJECTIVES.get(step, ["", ""])
	hud.set_objective(o[0], o[1])


# --- Arranque ------------------------------------------------------------------------------------

## Partida nueva: todos despiertan dentro de una cápsula, sin traje.
func start_new() -> void:
	active = true
	step = "despertar"
	for a in world.players:
		a.suit_on = false
		a.move_locked = true
	base.set_capsule_label("")   # hasta que se abran
	if world.ship != null:
		world.ship.immobilized = true
	hud.wake = 1.0
	_refresh_objective()
	_timer = 0.0
	_set_morning()


## La partida empieza poco después del amanecer lunar en la base: al salir a la superficie al final del prólogo hay
## luz rasante, sombras largas y la Tierra rota en el cielo (dentro de la base no se nota). Busca, en el mes lunar
## siguiente, la primera hora con el Sol entre 15° y 30° sobre el horizonte y subiendo.
func _set_morning() -> void:
	var sys := world.system
	if sys == null:
		return
	var up := base.pos_bf.normalized().to_vector3()
	var t0 := sys.time_s
	var prev := -1.0
	for i in 800:
		sys.time_s = t0 + i * 3600.0
		var sun := sys.position_in_frame("sun", world.body.id).sub(base.pos_bf).normalized().to_vector3()
		var el := rad_to_deg(asin(clampf(sun.dot(up), -1.0, 1.0)))
		if el > 15.0 and el < 30.0 and el > prev and i > 0:
			return
		prev = el
	sys.time_s = t0


## Partida sin prólogo (antigua o de pruebas): base en su estado de abandono, sin objetivos.
func start_skipped() -> void:
	active = false
	step = "completado"
	base.set_roof(true)
	base.doors["d_taller"].set_state("open")
	_refresh_objective()


func _process(delta: float) -> void:
	if world == null or not world.surface_ready or world.net_hold:
		return
	_timer += delta
	if mirror:
		_mirror_visuals(delta)
		return
	match step:
		"despertar":
			# Despertar lento: el desenfoque y los parpadeos ceden mientras suena la reanimación (audio 1).
			if not flags.has("p01_asked"):
				flags["p01_asked"] = true
				if not dialogue.say("p01"):
					_capsule_ready()
			hud.wake = maxf(0.45, hud.wake - delta * 0.04)
			hud.blink = clampf(sin(_timer * 1.7) * 2.0 - 1.2, 0.0, 1.0) * clampf(1.0 - _timer / 25.0, 0.0, 1.0)
		"salir_capsula", "terminal_medico":
			hud.wake = maxf(0.0, hud.wake - delta * 0.12)
			hud.blink = 0.0
		"orientacion", "pantalla":
			hud.wake = 0.0
			_check_corridor()
			if step == "pantalla":
				_check_screen(delta)
		"despresurizando":
			if base.airlock_phase == "abierta":
				dialogue.say("p22")
				advance("salir")
		"salir":
			for a in world.all_people():
				if base.room_of(a) == "":
					_complete()
					break
		"completado":
			if active and world.player.aboard != null and not flags.has("cleared"):
				flags["cleared"] = true
				hud.set_objective("")
	if _task != "":
		_update_task(delta)


## Cliente: el efecto de despertar sigue el paso que manda el anfitrión.
func _mirror_visuals(delta: float) -> void:
	match step:
		"despertar":
			hud.wake = maxf(0.45, hud.wake - delta * 0.04)
			hud.blink = clampf(sin(_timer * 1.7) * 2.0 - 1.2, 0.0, 1.0) * clampf(1.0 - _timer / 25.0, 0.0, 1.0)
		"salir_capsula", "terminal_medico":
			hud.wake = maxf(0.0, hud.wake - delta * 0.12)
			hud.blink = 0.0
		_:
			hud.wake = 0.0
			hud.blink = 0.0


func apply_mirror(d: Dictionary) -> void:
	var s := str(d.get("step", step))
	var act := bool(d.get("active", active))
	if s != step or act != active:
		step = s
		active = act
		_refresh_objective()


## Pasillo señalizado: la mitad sur del pasillo de recuperación (audio 9).
func _check_corridor() -> void:
	if flags.has("p09"):
		return
	for a in world.all_people():
		var lp := base.to_base(a.global_position)
		if BaseLayout.room_at(lp + Vector3(0, 0.5, 0)) == "recuperacion" and lp.z > -74.0:
			flags["p09"] = true
			dialogue.say("p09")
			break


## La pantalla detecta presencia: el jugador cerca y sin nadie hablando durante un momento.
func _check_screen(delta: float) -> void:
	if flags.has("pantalla_on"):
		return
	var near := false
	for a in world.all_people():
		var lp := base.to_base(a.global_position)
		if Vector2(lp.x - 6.5, lp.z + 56.0).length() < 10.0 and BaseLayout.room_at(lp + Vector3(0, 0.5, 0)) == "orientacion":
			near = true
	_screen_wait = _screen_wait + delta if near and not dialogue.is_busy() else 0.0
	if _screen_wait > 1.2:
		_activate_screen()


func _activate_screen() -> void:
	flags["pantalla_on"] = true
	base.set_screen("pantalla", "PRESENCIA DETECTADA\nGRABACIÓN CORPORATIVA PENDIENTE")
	GameAudio.play("scan", -4.0)
	_play_seq(["p11", "p12"], _start_magnus)


func _start_magnus() -> void:
	advance("mensaje")
	base.set_screen("pantalla", "MAGNUS BLACKWELL\nFUNDADOR Y CEO · MACSPACES")
	for a in world.players:
		a.cinematic = true
	if not dialogue.say("magnus"):
		_after_magnus(false)


func _after_magnus(_skipped: bool) -> void:
	for a in world.players:
		a.cinematic = false
	base.set_screen("pantalla", "OBJETIVOS\n1 · CENTRO DE OPERACIONES\n2 · ENERGÍA AUXILIAR\n3 · HANGAR PRINCIPAL")
	base.doors["d_eje"].set_state("open")
	advance("operaciones")
	dialogue.say("p13")


func _capsule_ready() -> void:
	if flags.has("capsula_abierta"):
		return
	flags["capsula_abierta"] = true
	base.set_capsule_label(null)
	base.open_capsule()
	dialogue.say("p02")
	advance("salir_capsula")


# --- Encadenado de líneas ---------------------------------------------------------------------------

## Reproduce las líneas en orden (las ya oídas o sin audio se saltan) y después llama a `done`.
func _play_seq(ids: Array, done: Callable) -> void:
	_seq = ids.duplicate()
	_seq_done = done
	_seq_next()


func _seq_next() -> void:
	while not _seq.is_empty():
		var id: String = _seq.pop_front()
		if dialogue.say(id):
			flags["seq_wait"] = id
			return
	flags.erase("seq_wait")
	if _seq_done.is_valid():
		var cb := _seq_done
		_seq_done = Callable()
		cb.call()


func _on_line_finished(id: String, skipped: bool) -> void:
	if id == "p01":
		_capsule_ready()
	elif id == "magnus":
		_after_magnus(skipped)
	if flags.get("seq_wait", "") == id:
		_seq_next()


# --- Salas y puertas -------------------------------------------------------------------------------

func _on_room(_a: Node, room: String) -> void:
	if mirror:
		return
	match room:
		"recuperacion":
			if at_least("salir_capsula") and not step == "salir_capsula":
				dialogue.say("p05")
				if idx(step) < idx("orientacion") and flags.has("medico"):
					advance("orientacion")
		"orientacion":
			dialogue.say("p10")
			if idx(step) < idx("pantalla"):
				advance("pantalla")
		"operaciones":
			if step == "operaciones":
				advance("consola")
		"hangar":
			if at_least("hangar"):
				dialogue.say("p18")
				if step == "hangar":
					advance("diagnostico")


func _on_door_denied(a: Node, did: String, state: String) -> void:
	var hud_a := a
	match state:
		"locked_power":
			if did == "d_sector_c" and not dialogue.heard.has("p31") and dialogue.has_audio("p31"):
				dialogue.say("p31")
			else:
				dialogue.say("p06")
			_note(hud_a, "Sin energía. " + ("Restablece la energía auxiliar." if did in BaseLayout.AUX_UNLOCKS else "Este sector no tiene suministro."))
		"locked_auth":
			dialogue.say("p07")
			_note(hud_a, "Acceso restringido: se requiere autorización ejecutiva.")
		"blocked":
			_note(hud_a, "La puerta está obstruida: hay escombros al otro lado.")
		"locked_script":
			_note(hud_a, "Bloqueada. Completa la orientación primero.")
		"cycle":
			_note(hud_a, "Escotilla exterior: usa el panel del ciclo de la esclusa.")


func _note(a: Node, text: String) -> void:
	world.show_note(a, text)


func _card(a: Node, title: String, lines: Array) -> void:
	world.show_card(a, title, lines)


# --- Interacciones -------------------------------------------------------------------------------

func _on_interact(a: Node, id: String, _kind: String) -> void:
	if mirror:
		return
	if OPTIONAL.has(id):
		var o: Array = OPTIONAL[id]
		_card(a, o[1], o[2])
		dialogue.say(o[0])
		return
	match id:
		"capsula", "capsula_2", "capsula_3", "capsula_4", "capsula_5", "capsula_6":
			if step == "salir_capsula" or flags.has("capsula_abierta"):
				for p in world.players:
					p.move_locked = false
				base.set_capsule_label("")
				advance("terminal_medico")
		"terminal_medico":
			flags["medico"] = true
			_card(a, "MACSPACES · PROGRAMA CAJAFUERTE", [
				"Reanimación completada. Tiempo en criopreservación: [ERROR DE DESBORDAMIENTO].",
				"Constantes: estables. Desorientación y visión borrosa transitorias: normales.",
				"Personal médico de guardia: Dra. E. Varga — [SIN RESPUESTA]. Técnico R. Osei — [BAJA].",
				"Plantilla de la base: [DATOS INCOMPLETOS]. Diríjase a la sala de orientación."])
			dialogue.say("p03")
			dialogue.say("p04")
			if idx(step) <= idx("terminal_medico"):
				advance("orientacion")
		"terminal_danado":
			_card(a, "TERMINAL · ERROR", ["ERR 0x4F — SECTOR DE MEMORIA ILEGIBLE", "█▓▒░ R̷E̷G̷I̷S̷T̷R̷O̷ ░▒▓█ … evacuac… … no abr… …"])
			dialogue.say("p08")
		"pantalla":
			if step == "pantalla" and not flags.has("pantalla_on") and not dialogue.is_busy():
				_activate_screen()
		"consola_ops":
			_card(a, "CENTRO DE OPERACIONES", [
				"Sistemas principales: FUERA DE LÍNEA. Red auxiliar: DESCONECTADA.",
				"Soporte vital: reserva de emergencia (sectores norte).",
				"NEXUS: componente local NO PRESENTE · mapa estelar incompleto.",
				"Acción requerida: conectar la energía auxiliar en la sala de energía."])
			dialogue.say("p14")
			flags["consola"] = true
			if idx(step) < idx("energia"):
				advance("energia")
		"energia_aux":
			if not flags.has("consola"):
				_note(a, "Sin autorización: inicia los sistemas desde el centro de operaciones.")
				GameAudio.play("error", -6.0)
			elif not base.lever_on and _task == "":
				base.pull_lever()
				dialogue.say("p15")
				advance("restableciendo")
				_begin_task("energia", "Conectando la red auxiliar…")
		"diagnostico":
			if not at_least("diagnostico"):
				return
			if _task == "" and not flags.has("diagnostico"):
				_begin_task("diagnostico", "Diagnóstico de EXP-01 «Esperanza»…")
			elif flags.has("diagnostico"):
				_diag_card(a)
		"traje":
			if step == "oxigeno":
				if _task == "":
					_begin_task("oxigeno", "Comprobando oxígeno y conexión del traje…")
			elif not at_least("traje"):
				_note(a, "Primero comprueba el estado de la nave en el hangar.")
			elif not world.player.suit_on:
				_equip_suit(a)
		"panel_esclusa":
			if at_least("salir"):
				base.cycle_airlock()   # tras el prólogo: salir y volver a entrar
				return
			if not at_least("esclusa"):
				_note(a, "Necesitas un traje EVA conectado antes de salir.")
				GameAudio.play("error", -6.0)
			elif base.airlock_phase == "":
				for p in world.all_people():
					if base.room_of(p) != "esclusa":
						_note(a, "Esperad todos dentro de la esclusa.")
						return
				base.start_airlock_cycle()
				dialogue.say("p21")
				advance("despresurizando")


func _equip_suit(a: Node) -> void:
	var h: ExplorationHud = a.exploration_hud if a is Astronaut else null
	if h != null:
		h.fade_out("Equipando el traje EVA…")
	GameAudio.play("airlock_cycle", -8.0)
	await get_tree().create_timer(1.4).timeout
	for p in world.players:
		p.suit_on = true
	if h != null:
		h.fade_in()
	base.label_override["traje"] = "Comprobar oxígeno y conexión"
	advance("oxigeno")


## Resultado del diagnóstico (a quien lo pide; `null` = a todos, al terminar).
func _diag_card(a: Node) -> void:
	var lines := [
		"Casco: íntegro. Soporte vital: operativo.",
		"Propulsión principal: BLOQUEADA · reparación pendiente (orden de mantenimiento 7731).",
		"Motor lumínico: calibración incompleta. Navegación: sin cartografía NEXUS.",
		"Las compuertas del hangar se abrirán cuando haya alguien fuera para supervisar el despegue."]
	if a == null:
		world.show_card_all("DIAGNÓSTICO · EXP-01 «ESPERANZA»", lines)
	else:
		_card(a, "DIAGNÓSTICO · EXP-01 «ESPERANZA»", lines)


# --- Tareas con barra de progreso ------------------------------------------------------------------

func _begin_task(t: String, text: String) -> void:
	_task = t
	_task_t = 0.0
	hud.progress = 0.0
	hud.progress_text = text


func _update_task(delta: float) -> void:
	var dur := {"energia": 6.0, "diagnostico": 5.0, "oxigeno": 2.5}.get(_task, 3.0) as float
	_task_t += delta
	hud.progress = clampf(_task_t / dur, 0.0, 1.0)
	if _task == "energia":
		# Las luces del eje parpadean mientras arranca la red.
		if randf() < delta * 6.0:
			base.flicker_lights(randf() < 0.5)
	if _task_t < dur:
		return
	var t := _task
	_task = ""
	hud.progress = -1.0
	match t:
		"energia":
			base.set_power_aux(true)
			base.set_screen("panel_aux", "ENERGÍA AUXILIAR\nCONECTADA")
			GameAudio.play("scan", -4.0)
			world.show_card_all("RED AUXILIAR CONECTADA", ["Iluminación del eje central y del hangar: restablecida.",
				"Gravedad artificial de la base: ACTIVADA (1 g).", "Compuertas del sector sur y del hangar: desbloqueadas."])
			advance("hangar")
			_play_seq(["p16", "p17"], Callable())
		"diagnostico":
			flags["diagnostico"] = true
			_diag_card(null)
			dialogue.say("p19")
			advance("traje")
		"oxigeno":
			world.show_card_all("TRAJE EVA · MACSPACES MK-IV", ["Oxígeno: 100 % (8 h 00 min).", "Presión interna: 30 kPa · estanqueidad correcta.",
				"Conexión con la red del traje: correcta.", "Propulsores: carga completa."])
			base.label_override["traje"] = "Trajes EVA"
			dialogue.say("p20")
			advance("esclusa")


# --- Final ----------------------------------------------------------------------------------------

func _complete() -> void:
	advance("completado")
	base.open_roof()
	base.doors["d_taller"].set_state("open")   # el componente lunar del NEXUS está en los talleres
	if world.ship != null:
		world.ship.immobilized = false
	world.show_card_all("PRÓLOGO COMPLETADO", [
		"Base lunar LF-01 · MacSpaces.", "Las compuertas del hangar se abren. La «Esperanza» puede despegar.",
		"Encuentra los componentes del NEXUS: Luna, Mercurio, Venus, Marte, Europa y Titán."])
	GameAudio.set_music("explore")
	completed.emit()
	SaveGame.save(world)


# --- Guardado ------------------------------------------------------------------------------------

func capture() -> Dictionary:
	return {"step": step, "flags": flags.duplicate(), "active": active}


func apply(d: Dictionary) -> void:
	active = bool(d.get("active", true))
	step = str(d.get("step", "completado"))
	flags = (d.get("flags", {}) as Dictionary).duplicate()
	flags.erase("seq_wait")
	# Pasos transitorios: se reanudan desde un punto estable.
	match step:
		"despertar":
			flags.erase("p01_asked")
		"mensaje":
			step = "pantalla"
			flags.erase("pantalla_on")
		"restableciendo":
			step = "hangar"
			base.set_power_aux(true)
			base.lever_on = true
		"despresurizando":
			step = "esclusa"
	var started := idx(step) > idx("salir_capsula")
	var suit := idx(step) >= idx("oxigeno")
	for a in world.players:
		a.move_locked = not started
		a.cinematic = false
		a.suit_on = suit or not active
	if step == "salir_capsula" or started:
		base.capsule_target = 1.0
		flags["capsula_abierta"] = true
		if not started:
			base.set_capsule_label(null)
	if at_least("oxigeno"):
		base.label_override["traje"] = "Comprobar oxígeno y conexión" if step == "oxigeno" else "Trajes EVA"
	if started:
		base.set_capsule_label("")
	if world.ship != null:
		world.ship.immobilized = active and step != "completado"
	hud.wake = 0.0 if started else 0.6
	_refresh_objective()
