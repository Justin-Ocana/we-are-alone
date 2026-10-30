class_name LandMask
extends RefCounted
## Máscara de tierras emergidas de la Tierra (equirrectangular, 512×256) a partir de data/earth_land.json
## (contornos aproximados). Se rellena por líneas de barrido (rápido en GDScript) y se suaviza. La usan los
## fragmentos de la Tierra destruida para que se reconozcan los continentes (ADR-026).

const PATH := "res://data/earth_land.json"
const W := 512
const H := 256

static var _tex: ImageTexture


static func texture() -> ImageTexture:
	if _tex == null:
		_tex = ImageTexture.create_from_image(build_image())
	return _tex


static func build_image() -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_L8)
	img.fill(Color(0, 0, 0))
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary:
		push_warning("LandMask: no se pudo leer %s" % PATH)
		return img
	var polys: Dictionary = data["polygons"]
	for key in polys:
		_fill(img, polys[key])
	# Suavizado: costas sin escalones de píxel.
	img.resize(W / 2, H / 2, Image.INTERPOLATE_BILINEAR)
	img.resize(W, H, Image.INTERPOLATE_BILINEAR)
	return img


static func _fill(img: Image, poly: Array) -> void:
	var n := poly.size()
	for row in H:
		var lat := 90.0 - (float(row) + 0.5) * 180.0 / H
		var xs: Array[float] = []
		for k in n:
			var a: Array = poly[k]
			var b: Array = poly[(k + 1) % n]
			var la := float(a[1])
			var lb := float(b[1])
			if (la <= lat and lb > lat) or (lb <= lat and la > lat):
				var t := (lat - la) / (lb - la)
				xs.append(float(a[0]) + t * (float(b[0]) - float(a[0])))
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			var x0 := int(floor((xs[k] + 180.0) / 360.0 * W))
			var x1 := int(ceil((xs[k + 1] + 180.0) / 360.0 * W))
			for x in range(maxi(x0, 0), mini(x1, W)):
				img.set_pixel(x, row, Color(1, 1, 1))


## ¿Es tierra en (lat, lon) grados? (para pruebas)
static func is_land(lat: float, lon: float) -> bool:
	var img := texture().get_image()
	var x := clampi(int((lon + 180.0) / 360.0 * W), 0, W - 1)
	var y := clampi(int((90.0 - lat) / 180.0 * H), 0, H - 1)
	return img.get_pixel(x, y).r > 0.5
