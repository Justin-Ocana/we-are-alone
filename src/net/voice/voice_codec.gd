class_name VoiceCodec
extends RefCounted
## Códec de voz (ADR-046): mono a 12 kHz, μ-law de 8 bits (G.711; Godot no trae Opus). Tramas de 40 ms (480 muestras,
## 480 bytes): ≈12 KB/s por persona hablando. Remuestreo lineal desde la frecuencia de mezcla del micrófono.

const RATE := 12000
const FRAME := 480                   ## muestras por trama (40 ms)
const BIAS := 0x84
const CLIP := 32635

static var _dec: PackedFloat32Array


static func encode(samples: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(samples.size())
	for i in samples.size():
		var s := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		var sign := 0
		if s < 0:
			s = -s
			sign = 0x80
		s = mini(s, CLIP) + BIAS
		var exponent := 7
		var mask := 0x4000
		while exponent > 0 and (s & mask) == 0:
			exponent -= 1
			mask >>= 1
		var mantissa := (s >> (exponent + 3)) & 0x0F
		out[i] = ~(sign | (exponent << 4) | mantissa) & 0xFF
	return out


static func decode(data: PackedByteArray) -> PackedFloat32Array:
	if _dec.is_empty():
		_dec.resize(256)
		for b in 256:
			var u := ~b & 0xFF
			var sign := u & 0x80
			var exponent := (u >> 4) & 0x07
			var mantissa := u & 0x0F
			var s := (((mantissa << 3) + BIAS) << exponent) - BIAS
			_dec[b] = float(-s if sign != 0 else s) / 32768.0
	var out := PackedFloat32Array()
	out.resize(data.size())
	for i in data.size():
		out[i] = _dec[data[i]]
	return out


## Remuestreador lineal con estado (para que las tramas encajen sin saltos).
class Resampler:
	extends RefCounted
	var ratio := 1.0           ## entrada / salida
	var _pos := 0.0
	var _last := 0.0

	func _init(in_rate: float, out_rate: float) -> void:
		ratio = in_rate / out_rate

	func process(mono: PackedFloat32Array) -> PackedFloat32Array:
		var out := PackedFloat32Array()
		var n := mono.size()
		while _pos < n:
			var i := int(_pos)
			var f := _pos - i
			var a := _last if i == 0 else mono[i - 1]
			var b := mono[i] if i < n else a
			out.append(lerpf(a, b, f))
			_pos += ratio
		_pos -= n
		if n > 0:
			_last = mono[n - 1]
		return out


static func rms(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return 0.0
	var acc := 0.0
	for s in samples:
		acc += s * s
	return sqrt(acc / samples.size())
