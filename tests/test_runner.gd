extends RefCounted
## Ejecutor de pruebas sin dependencias: carga tests/unit/test_*.gd y ejecuta sus métodos test_*.

const UNIT_DIR := "res://tests/unit"


func run_all() -> int:
	var total := 0
	var failed := 0
	var dir := DirAccess.open(UNIT_DIR)
	var files := dir.get_files() if dir != null else PackedStringArray()
	files.sort()
	var t0 := Time.get_ticks_msec()
	for file in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		var script: GDScript = load(UNIT_DIR.path_join(file))
		var tc: TestCase = script.new()
		for m in tc.get_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			total += 1
			tc.current_test = "%s::%s" % [file.get_basename(), name]
			var before := tc.failures.size()
			tc.call(name)
			if tc.failures.size() > before:
				failed += 1
				for i in range(before, tc.failures.size()):
					print("  FALLO  ", tc.failures[i])
			else:
				print("  ok     ", tc.current_test)
	print("RESULTADO: %d pruebas, %d fallidas (%d ms)" % [total, failed, Time.get_ticks_msec() - t0])
	return failed
