class_name TestCase
extends RefCounted
## Clase base de las pruebas. Los métodos `test_*` se ejecutan automáticamente.

var failures: PackedStringArray = []
var current_test := ""


func fail(msg: String) -> void:
	failures.append("%s: %s" % [current_test, msg])


func assert_true(cond: bool, msg: String = "se esperaba true") -> void:
	if not cond:
		fail(msg)


func assert_eq(a: Variant, b: Variant, msg: String = "") -> void:
	if a != b:
		fail("%s (obtenido %s, esperado %s)" % [msg, str(a), str(b)])


func assert_near(a: float, b: float, tol: float, msg: String = "") -> void:
	if absf(a - b) > tol:
		fail("%s (obtenido %s, esperado %s ± %s)" % [msg, str(a), str(b), str(tol)])
