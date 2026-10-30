# Créditos del audio

## Sintetizado (propio, CC0)
Todo lo que hay en `sfx/`, `amb/` y `music/` lo genera `tools/gen_audio.py` (numpy, determinista). Dominio público.
Banda sonora: «Despertar» (menú), «Órbita» (exploración), «Profundidades» (atmósferas densas), «Fiesta» (modo fiesta y bailes).

## Grabado — Kenney (www.kenney.nl), licencia CC0 (dominio público)
Carpeta `kenney/` (56 archivos OGG elegidos de tres paquetes; ver `kenney/LICENCIA_KENNEY_CC0.txt`):
- **Sci-Fi Sounds** (`scifi_*`): puertas, ruidos de consola, motores, propulsores, impactos metálicos.
- **UI Audio** (`ui_*`): pasar por encima, clics e interruptores de la interfaz.
- **Impact Sounds** (`impact_*`): pisadas (hormigón y nieve), cubierta metálica, minería, golpes suaves.

Descargados el 2026-10-11 con permiso del usuario desde kenney.nl/assets (sci-fi-sounds, ui-audio, impact-sounds).
`GameAudio.VARIANTS` decide qué sonido grabado sustituye a cada sintetizado; los que no tienen versión grabada
(avisos, escáner, salto lumínico, truenos, esclusa, foto, emotes y la música) siguen siendo sintetizados.

## Registros del NEXUS (del usuario)
Carpeta `nexus/`: cinco audios proporcionados por el usuario (generados con ElevenLabs), copiados el 2026-10-16 desde
`Desktop/Space/auidos`. Reparto al azar (se cambia en `data/dialogue/prologue.json`, líneas `nexus_*`):
- `mercury.mp3` ← «Karolina - Warm, Calm and Deep»
- `venus.mp3` ← «Daniela - Warm, Clear and Positive»
- `mars.mp3` ← «Martin Osborne - Deep and Passionate»
- `europa.mp3` ← «Arconte - Evocative, Deep and Elegant»
- `titan.mp3` ← «Edoardo - Dark, Measured, Natural»

## Banda sonora CC0 de OpenGameArt (descargada con permiso del usuario el 2026-10-16)
Todas con licencia CC0 (dominio público). Volumen igualado en `data/music.json` (`gain_db`).
- `music/srg774_*.mp3` (sector, airy, pulse, urgent, transmission, title): «Dark Sci-Fi Audio Pack», SRG774 —
  https://opengameart.org/node/188336
- `music/wipics_outer_space.mp3`: «Outer Space Loop», wipics — https://opengameart.org/content/outer-space-loop
- `music/yoiyami_starfield_romance.wav`: «Starfield Romance», Yoiyami — https://opengameart.org/node/182246

