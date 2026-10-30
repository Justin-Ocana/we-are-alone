class_name VoiceFx
extends RefCounted
## Procesado de una voz recibida según el dispositivo por el que llega (ADR-046). Cada fuente y cada vía tienen su
## propio VoiceFx (los filtros guardan estado entre tramas). A 12 kHz:
## - "casco": micrófono de casco: banda 250-3400 Hz, resonancia interna corta (eco de 2,5 ms) y compresión suave.
## - "radio": radio de traje / walkie: banda 450-2700 Hz, saturación, compresión, ruido de fondo y, con poca señal,
##   chasquidos y cortes.
## - "megafonia": altavoz de la nave: banda 200-4500 Hz y saturación leve (la sala la pone el bus con reverberación).
## - "aire": sin procesar (la distancia, la oclusión y la sala las aplica el reproductor 3D y su bus).

const SR := 12000.0

var kind := "aire"
var quality := 1.0                   ## 0..1 calidad de señal (radio)
var damaged := false                 ## casco dañado: interferencias
var _hp := Biquad.new()
var _lp := Biquad.new()
var _comb := PackedFloat32Array()
var _comb_i := 0
var _env := 0.0
var _rng := RandomNumberGenerator.new()
var _cut := 0                        ## muestras restantes de un corte de señal


func _init(p_kind: String = "aire") -> void:
	set_kind(p_kind)


func set_kind(p_kind: String) -> void:
	if p_kind == kind and _comb.size() > 0:
		return
	kind = p_kind
	match kind:
		"casco":
			_hp.highpass(250.0, 0.7)
			_lp.lowpass(3400.0, 0.9)
		"radio":
			_hp.highpass(450.0, 0.8)
			_lp.lowpass(2700.0, 1.1)
		"megafonia":
			_hp.highpass(200.0, 0.7)
			_lp.lowpass(4500.0, 0.8)
		_:
			_hp.highpass(60.0, 0.7)
			_lp.lowpass(5800.0, 0.7)
	_comb.resize(30)
	_comb.fill(0.0)


func process(x: PackedFloat32Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(x.size())
	var noise := 0.0
	if kind == "radio":
		noise = 0.012 + (1.0 - quality) * 0.09
	if damaged:
		noise += 0.05
	for i in x.size():
		var s := x[i]
		if kind != "aire":
			s = _lp.step(_hp.step(s))
		match kind:
			"casco":
				var d := _comb[_comb_i]
				var y := s + d * 0.28
				_comb[_comb_i] = y
				_comb_i = (_comb_i + 1) % _comb.size()
				s = _compress(y * 1.25)
			"radio":
				s = tanh(s * 3.2) * 0.55
				s = _compress(s)
				s += (_rng.randf() * 2.0 - 1.0) * noise
				if quality < 0.6 or damaged:
					if _cut > 0:
						_cut -= 1
						s *= 0.05
					elif _rng.randf() < (0.6 - quality) * 0.0012 + (0.0008 if damaged else 0.0):
						_cut = _rng.randi_range(200, 1400)
			"megafonia":
				s = tanh(s * 1.8) * 0.7
		if damaged and kind != "radio":
			s += (_rng.randf() * 2.0 - 1.0) * noise * (1.0 if _rng.randf() < 0.3 else 0.2)
		out[i] = Vector2(s, s)
	return out


## Compresor de envolvente sencillo (ataque rápido, caída lenta).
func _compress(s: float) -> float:
	var a := absf(s)
	_env = lerpf(_env, a, 0.02 if a > _env else 0.0008)
	var g := 1.0 / maxf(1.0, _env * 3.0)
	return s * g * 1.4


## Pitido de entrada y estática de salida de la radio (se empujan por el mismo reproductor).
static func squelch(start: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	if start:
		for i in int(SR * 0.07):
			var t := i / SR
			var s := sin(TAU * 1450.0 * t) * 0.18 * minf(1.0, (0.07 - t) * 60.0)
			out.append(Vector2(s, s))
	else:
		for i in int(SR * 0.16):
			var t := i / SR
			var s := (rng.randf() * 2.0 - 1.0) * 0.12 * (1.0 - t / 0.16)
			out.append(Vector2(s, s))
	return out


## Filtro biquad (RBJ) con estado.
class Biquad:
	extends RefCounted
	var b0 := 1.0
	var b1 := 0.0
	var b2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var z1 := 0.0
	var z2 := 0.0

	func lowpass(f: float, q: float) -> void:
		var w := TAU * f / SR
		var al := sin(w) / (2.0 * q)
		var c := cos(w)
		var a0 := 1.0 + al
		b0 = (1.0 - c) * 0.5 / a0
		b1 = (1.0 - c) / a0
		b2 = b0
		a1 = -2.0 * c / a0
		a2 = (1.0 - al) / a0

	func highpass(f: float, q: float) -> void:
		var w := TAU * f / SR
		var al := sin(w) / (2.0 * q)
		var c := cos(w)
		var a0 := 1.0 + al
		b0 = (1.0 + c) * 0.5 / a0
		b1 = -(1.0 + c) / a0
		b2 = b0
		a1 = -2.0 * c / a0
		a2 = (1.0 - al) / a0

	func step(x: float) -> float:
		var y := b0 * x + z1
		z1 = b1 * x - a1 * y + z2
		z2 = b2 * x - a2 * y
		return y
