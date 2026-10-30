extends TestCase
## Música de la nave (ADR-022): enlaces admitidos y rechazados.


func test_blocked_services_are_explained() -> void:
	for u in ["https://open.spotify.com/track/abc", "https://www.youtube.com/watch?v=x", "https://youtu.be/x",
			"https://music.youtube.com/watch?v=x", "https://soundcloud.com/a/b"]:
		assert_true(ShipMusic.url_problem(u).contains("DRM"), "se explica por qué no: %s" % u)


func test_direct_links_are_allowed() -> void:
	assert_true(ShipMusic.url_problem("https://example.com/cancion.mp3") == "", "enlace directo .mp3 admitido")
	assert_true(ShipMusic.url_problem("http://example.com/a.ogg?x=1") == "", "enlace directo .ogg admitido")
	assert_true(ShipMusic.url_problem("ftp://example.com/a.mp3") != "", "sólo http(s)")
