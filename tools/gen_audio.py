"""Genera TODO el audio del juego por síntesis (ADR-038): efectos de interfaz, efectos de la nave y del traje,
ambientes en bucle y cuatro piezas de banda sonora. Sin muestras externas: dominio público (CC0), propio.

Uso:  python tools/gen_audio.py          (escribe assets/audio/{sfx,amb,music}/*.wav)

Requiere numpy. Todo es determinista (semillas fijas): volver a ejecutarlo produce los mismos archivos.
"""
import os
import wave
import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")
SR_FX = 44100
SR_MUS = 22050
rng = np.random.default_rng(7)


# --- utilidades -------------------------------------------------------------------------------

def write(path, data, sr, stereo=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = np.asarray(data, dtype=np.float64)
    peak = np.max(np.abs(data)) if data.size else 1.0
    if peak > 0.98:
        data = data * (0.98 / peak)
    pcm = (np.clip(data, -1.0, 1.0) * 32767.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2 if stereo else 1)
        w.setsampwidth(2)
        w.setframerate(sr)
        if stereo:
            w.writeframes(pcm.T.reshape(-1).tobytes() if pcm.ndim == 2 and pcm.shape[0] == 2 else pcm.tobytes())
        else:
            w.writeframes(pcm.tobytes())
    print("  %-40s %6.2f s  %5d kB" % (os.path.relpath(path, ROOT), data.shape[-1] / sr, os.path.getsize(path) // 1024))


def t_axis(sec, sr):
    return np.arange(int(sec * sr)) / sr


def env_adsr(n, sr, a=0.01, d=0.1, s=0.6, r=0.2):
    e = np.zeros(n)
    ai, di, ri = int(a * sr), int(d * sr), int(r * sr)
    if ai + di + ri > n:  # notas cortas: las fases se encogen en proporción
        k = n / float(ai + di + ri)
        ai, di, ri = int(ai * k), int(di * k), int(ri * k)
    si = max(n - ai - di - ri, 0)
    e[:ai] = np.linspace(0, 1, ai, endpoint=False) if ai else e[:ai]
    e[ai:ai + di] = np.linspace(1, s, di, endpoint=False) if di else e[ai:ai + di]
    e[ai + di:ai + di + si] = s
    e[ai + di + si:ai + di + si + ri] = np.linspace(s, 0, ri) if ri else e[ai + di + si:ai + di + si + ri]
    return e[:n]


def exp_decay(n, sr, tau):
    return np.exp(-np.arange(n) / sr / tau)


def fft_filter(x, sr, lo=None, hi=None, order=2):
    """Filtro de magnitud en el dominio de la frecuencia (paso bajo `hi`, paso alto `lo`)."""
    n = len(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1.0 / sr)
    g = np.ones_like(f)
    if hi is not None:
        g *= 1.0 / np.sqrt(1.0 + (f / hi) ** (2 * order))
    if lo is not None:
        g *= 1.0 / np.sqrt(1.0 + (lo / np.maximum(f, 1e-3)) ** (2 * order))
    return np.fft.irfft(X * g, n)


def noise(n):
    return rng.standard_normal(n)


def pink(n):
    X = np.fft.rfft(noise(n))
    f = np.fft.rfftfreq(n)
    f[0] = f[1]
    y = np.fft.irfft(X / np.sqrt(f), n)
    return y / (np.std(y) + 1e-9)


def brown(n):
    y = np.cumsum(noise(n))
    y = fft_filter(y, 1000, lo=0.5)
    return y / (np.std(y) + 1e-9)


def reverb(x, sr, tau=1.6, mix=0.35, seed=0, predelay=0.02):
    r = np.random.default_rng(100 + seed)
    m = int(tau * 4 * sr)
    ir = r.standard_normal(m) * np.exp(-np.arange(m) / sr / tau)
    ir = fft_filter(ir, sr, hi=6000)
    ir[: int(predelay * sr)] = 0
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    n = len(x) + m
    size = 1 << int(np.ceil(np.log2(n)))
    y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[: len(x)]
    return x * (1 - mix) + y * mix * 1.2


def loop_crossfade(x, sr, fade=3.0):
    """Hace el sonido cíclico: el final se funde con el principio (x[...,] se acorta en `fade`)."""
    k = int(fade * sr)
    out = x[..., : x.shape[-1] - k].copy()
    w = np.linspace(0, 1, k)
    out[..., :k] = out[..., :k] * w + x[..., x.shape[-1] - k:] * (1 - w)
    return out


def note_hz(n):
    """n en semitonos respecto a La4 (440 Hz)."""
    return 440.0 * 2 ** (n / 12.0)


NOTE = {"C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4, "F#": -3, "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2}


def nn(name, octave):
    return NOTE[name] + 12 * (octave - 4)


# --- instrumentos -----------------------------------------------------------------------------

def pad(freqs, sec, sr, bright=1800.0, detune=0.004, seed=0):
    t = t_axis(sec, sr)
    r = np.random.default_rng(seed)
    y = np.zeros_like(t)
    for f in freqs:
        for d in (-detune, 0.0, detune):
            ph = r.random() * 2 * np.pi
            ff = f * (1 + d)
            # Diente de sierra suave (6 armónicos).
            for h in range(1, 7):
                y += np.sin(2 * np.pi * ff * h * t + ph * h) / (h ** 1.3)
    y = fft_filter(y, sr, hi=bright, order=2)
    lfo = 0.85 + 0.15 * np.sin(2 * np.pi * 0.11 * t + seed)
    return y * lfo * env_adsr(len(t), sr, a=sec * 0.35, d=0.1, s=1.0, r=sec * 0.35) / (len(freqs) * 3.0)


def pluck(f, sec, sr, decay=1.2, bright=1.0):
    t = t_axis(sec, sr)
    y = np.zeros_like(t)
    for h, a in ((1, 1.0), (2, 0.45 * bright), (3, 0.22 * bright), (4, 0.12 * bright), (5, 0.06 * bright)):
        y += a * np.sin(2 * np.pi * f * h * t) * np.exp(-t * h / decay)
    att = np.minimum(1.0, t / 0.004)
    return y * att * 0.5


def bell(f, sec, sr, decay=2.5):
    t = t_axis(sec, sr)
    mod = np.sin(2 * np.pi * f * 3.5 * t) * 2.0 * np.exp(-t / 0.6)
    y = np.sin(2 * np.pi * f * t + mod) * np.exp(-t / decay)
    return y * np.minimum(1.0, t / 0.003) * 0.4


def place(buf, x, at, sr, gain=1.0):
    i = int(at * sr)
    j = min(len(buf), i + len(x))
    if i < len(buf):
        buf[i:j] += x[: j - i] * gain


def stereo(mono, pan=0.0):
    l = np.cos((pan + 1) * np.pi / 4)
    r = np.sin((pan + 1) * np.pi / 4)
    return np.vstack([mono * l, mono * r])


# --- efectos (SFX) ----------------------------------------------------------------------------

def soft_tone(f, sec, attack, decay, glide=1.0, sr=SR_FX):
    """Tono suave: seno con un poco de 2.º armónico, ataque `attack` s, caída exponencial `decay` s y un ligero
    deslizamiento de tono hasta f·glide. Filtrado por arriba para que nunca suene a pitido."""
    t = t_axis(sec, sr)
    ff = f * (1.0 + (glide - 1.0) * (1.0 - np.exp(-t / max(sec * 0.4, 1e-3))))
    ph = 2 * np.pi * np.cumsum(ff) / sr
    y = np.sin(ph) + 0.15 * np.sin(2 * ph)
    env = np.minimum(1.0, t / max(attack, 1e-4)) * np.exp(-np.maximum(t - attack, 0.0) / decay)
    return fft_filter(y * env, sr, hi=2600)


def mix(*parts):
    """Suma señales de distinta longitud (rellena con ceros)."""
    n = max(len(x) for x in parts)
    out = np.zeros(n)
    for x in parts:
        out[: len(x)] += x
    return out


def air_puff(sec, sr, lo, hi, rise=False):
    n = int(sec * sr)
    env = env_adsr(n, sr, sec * (0.7 if rise else 0.08), 0.02, 0.6, sec * (0.25 if rise else 0.8))
    return fft_filter(noise(n), sr, lo=lo, hi=hi) * env


def sfx():
    sr = SR_FX
    d = os.path.join(ROOT, "sfx")
    # Interfaz (ronda 8): sonidos cálidos y graves, de ataque suave, sin pitidos agudos ni tonos de "teléfono".
    # Base: tono suave (seno + un poco de 2.º armónico, filtrado) y soplos de aire filtrado.
    write(os.path.join(d, "ui_hover.wav"), mix(soft_tone(880, 0.06, 0.004, 0.018) * 0.12, air_puff(0.05, sr, 2500, 6000) * 0.05), sr)
    write(os.path.join(d, "ui_click.wav"), mix(soft_tone(520, 0.12, 0.003, 0.035, glide=0.85) * 0.35, air_puff(0.04, sr, 900, 3000) * 0.08), sr)
    write(os.path.join(d, "ui_toggle.wav"), mix(soft_tone(440, 0.14, 0.004, 0.045, glide=1.12) * 0.32, air_puff(0.05, sr, 700, 2500) * 0.06), sr)
    up = mix(air_puff(0.32, sr, 300, 2200, rise=True) * 0.22, soft_tone(330, 0.32, 0.06, 0.12, glide=1.5) * 0.18)
    write(os.path.join(d, "ui_open.wav"), reverb(up, sr, 0.5, 0.3), sr)
    down = mix(air_puff(0.25, sr, 300, 1800) * 0.18, soft_tone(420, 0.25, 0.01, 0.08, glide=0.7) * 0.18)
    write(os.path.join(d, "ui_back.wav"), reverb(down, sr, 0.4, 0.25), sr)
    # Aviso: acorde grave que florece (La3 + Mi4 + La4 muy suave), sin campanas.
    buf = np.zeros(int(1.1 * sr))
    for f, g, at in ((220.0, 0.30, 0.0), (329.6, 0.22, 0.04), (440.0, 0.10, 0.08)):
        place(buf, soft_tone(f, 0.9, 0.03, 0.32), at, sr, g)
    write(os.path.join(d, "notify.wav"), reverb(fft_filter(buf, sr, hi=2200), sr, 0.9, 0.35, 5), sr)
    # Error: dos golpes graves y apagados (nada de ondas cuadradas).
    buf = np.zeros(int(0.5 * sr))
    for k in range(2):
        place(buf, soft_tone(160, 0.18, 0.004, 0.06, glide=0.85), k * 0.16, sr, 0.45)
    write(os.path.join(d, "error.wav"), buf, sr)
    # Escáner: barrido suave tipo sónar (seno grave que sube despacio) con un eco.
    t = t_axis(1.1, sr)
    f = 260 + 260 * (t / t[-1]) ** 1.3
    sweep = np.sin(2 * np.pi * np.cumsum(f) / sr) * env_adsr(len(t), sr, 0.12, 0.2, 0.6, 0.5) * 0.25
    sweep = fft_filter(sweep, sr, hi=1800)
    write(os.path.join(d, "scan.wav"), reverb(sweep, sr, 1.2, 0.4, 2), sr)
    # Muestra: roca raspada + pitido de confirmación.
    n = int(0.6 * sr)
    scrape = fft_filter(noise(n), sr, lo=600, hi=3500) * exp_decay(n, sr, 0.12) * 0.5
    place(scrape, soft_tone(440, 0.3, 0.01, 0.1), 0.25, sr, 0.25)
    write(os.path.join(d, "sample.wav"), scrape, sr)
    # Foto: obturador mecánico (dos golpes de ruido filtrado).
    buf = np.zeros(int(0.35 * sr))
    for at, g in ((0.0, 1.0), (0.09, 0.7)):
        k = int(0.04 * sr)
        place(buf, fft_filter(noise(k), sr, lo=1500, hi=8000) * exp_decay(k, sr, 0.008), at, sr, g * 0.6)
    write(os.path.join(d, "photo.wav"), buf, sr)
    # Puertas: siseo neumático (ruido con barrido) + golpe final.
    n = int(0.8 * sr)
    hiss = noise(n)
    hiss = fft_filter(hiss, sr, lo=800, hi=5000) * env_adsr(n, sr, 0.03, 0.15, 0.5, 0.45) * 0.35
    k = int(0.15 * sr)
    place(hiss, np.sin(2 * np.pi * 80 * t_axis(0.15, sr)) * exp_decay(k, sr, 0.04) * 0.5, 0.6, sr)
    write(os.path.join(d, "door_open.wav"), hiss, sr)
    write(os.path.join(d, "door_close.wav"), hiss[::-1] * np.linspace(0.6, 1.0, n), sr)
    # Esclusa: despresurización larga.
    n = int(2.6 * sr)
    air = fft_filter(pink(n), sr, lo=300, hi=6000) * env_adsr(n, sr, 0.2, 0.3, 0.8, 1.2) * 0.35
    write(os.path.join(d, "airlock_cycle.wav"), air, sr)
    # Sentarse / levantarse: golpe sordo con crujido de cuero sintético.
    n = int(0.3 * sr)
    thump = np.sin(2 * np.pi * 70 * t_axis(0.3, sr)) * exp_decay(n, sr, 0.05) * 0.7
    thump += fft_filter(noise(n), sr, lo=200, hi=1200) * exp_decay(n, sr, 0.06) * 0.25
    write(os.path.join(d, "sit.wav"), thump, sr)
    write(os.path.join(d, "stand.wav"), thump * np.linspace(0.6, 0.9, n), sr)
    # Confirmación de la nave (acciones: gravedad, focos, fiesta…): un "toc" grave y corto, casi imperceptible.
    tok = mix(soft_tone(300, 0.16, 0.004, 0.05, glide=1.18) * 0.3, air_puff(0.06, sr, 500, 2000) * 0.05)
    write(os.path.join(d, "beep.wav"), reverb(tok, sr, 0.3, 0.2), sr)
    # Salto lumínico: barrido grave a agudo con ruido.
    n = int(3.0 * sr)
    t = t_axis(3.0, sr)
    f = 50 * (40 ** (t / 3.0))
    warp = np.sin(2 * np.pi * np.cumsum(f) / sr) * 0.4 + fft_filter(noise(n), sr, lo=200, hi=4000) * (t / 3.0) * 0.4
    write(os.path.join(d, "warp.wav"), reverb(warp * env_adsr(n, sr, 0.6, 0.5, 0.8, 1.0), sr, 1.5, 0.35, 3), sr)
    # Aterrizaje: golpe grave.
    n = int(1.2 * sr)
    t = t_axis(1.2, sr)
    write(os.path.join(d, "landing.wav"), (np.sin(2 * np.pi * (45 + 20 * np.exp(-t * 8)) * t) * exp_decay(n, sr, 0.25) * 0.8
          + fft_filter(noise(n), sr, hi=500) * exp_decay(n, sr, 0.15) * 0.4), sr)
    # Trueno lejano (rayos en los gigantes gaseosos).
    n = int(4.0 * sr)
    th = fft_filter(brown(n), sr, hi=400) * env_adsr(n, sr, 0.05, 0.6, 0.5, 2.5)
    th *= 0.6 + 0.4 * np.abs(fft_filter(noise(n), sr, hi=6))
    write(os.path.join(d, "thunder.wav"), reverb(th * 0.6, sr, 2.0, 0.4, 4), sr)
    # Emote: pop alegre.
    write(os.path.join(d, "emote.wav"), soft_tone(392, 0.22, 0.006, 0.07, glide=1.25) * 0.3, sr)


# --- ambientes en bucle -----------------------------------------------------------------------

def ambience():
    sr = SR_MUS
    d = os.path.join(ROOT, "amb")
    # Zumbido de la nave: 50 Hz + armónicos, ventilación (ruido rosa filtrado) y un latido muy lento.
    sec = 24.0
    t = t_axis(sec + 3, sr)
    n = len(t)
    hum = (np.sin(2 * np.pi * 50 * t) * 0.35 + np.sin(2 * np.pi * 100 * t) * 0.18 + np.sin(2 * np.pi * 150.4 * t) * 0.07)
    vent = fft_filter(pink(n), sr, lo=120, hi=1400) * 0.22
    beat = 1.0 + 0.08 * np.sin(2 * np.pi * 0.25 * t)
    write(os.path.join(d, "ship_hum.wav"), loop_crossfade((hum + vent) * beat * 0.6, sr), sr)
    # Viento: ruido rosa con ráfagas y silbidos.
    sec = 20.0
    n = int((sec + 3) * sr)
    gust = 0.5 + 0.5 * fft_filter(noise(n), sr, hi=0.35)
    gust = (gust - gust.min()) / (gust.max() - gust.min() + 1e-9)
    wind = fft_filter(pink(n), sr, lo=80, hi=900) * (0.35 + 0.65 * gust)
    whistle = fft_filter(noise(n), sr, lo=900, hi=1300, order=4) * gust ** 2 * 0.4
    write(os.path.join(d, "wind.wav"), loop_crossfade((wind + whistle) * 0.7, sr), sr)
    # Motores: rumor grave pulsante.
    sec = 8.0
    t = t_axis(sec + 2, sr)
    n = len(t)
    rumble = fft_filter(brown(n), sr, hi=180) * 0.7 + np.sin(2 * np.pi * 38 * t) * 0.3 + np.sin(2 * np.pi * 57 * t) * 0.12
    roar = fft_filter(pink(n), sr, lo=300, hi=2500) * 0.18
    write(os.path.join(d, "engine.wav"), loop_crossfade(rumble + roar, sr, 2.0), sr)
    # Profundidades de un gigante: rumor tectónico + crujidos.
    sec = 24.0
    n = int((sec + 3) * sr)
    deep = fft_filter(brown(n), sr, hi=90) * 0.8
    for k in range(10):
        at = rng.random() * sec
        m = int(1.5 * sr)
        place(deep, fft_filter(noise(m), sr, lo=40, hi=300) * exp_decay(m, sr, 0.4) * 0.5, at, sr)
    write(os.path.join(d, "deep.wav"), loop_crossfade(deep, sr), sr)
    # Fiesta sin música: no se genera aparte (usa la pieza "fiesta").


# --- banda sonora -----------------------------------------------------------------------------

def song_despertar():
    """Menú: melancólica y espaciosa. La menor, 60 ppm, Am–Fmaj7–C–G con pad, piano suave y campanas lejanas."""
    sr = SR_MUS
    bpm = 60.0
    beat = 60.0 / bpm
    chords = [["A", "C", "E"], ["F", "A", "C", "E"], ["C", "E", "G"], ["G", "B", "D"]]
    roots = ["A", "F", "C", "G"]
    bars = 24
    total = bars * 4 * beat + 6
    L = np.zeros(int(total * sr))
    R = np.zeros_like(L)
    melody = [("E", 5), ("C", 5), ("D", 5), ("B", 4), ("A", 4), ("C", 5), ("G", 4), ("B", 4)]
    for b in range(bars):
        ch = chords[b % 4]
        start = b * 4 * beat
        p = pad([note_hz(nn(c, 3 if c in ("A", "B") else 4) ) for c in ch], 4 * beat + 2.0, sr, bright=1200, seed=b)
        place(L, p, start, sr, 0.55)
        place(R, p, start + 0.013, sr, 0.55)
        bass = pluck(note_hz(nn(roots[b % 4], 2)), 4 * beat, sr, decay=2.0, bright=0.3)
        place(L, bass, start, sr, 0.5)
        place(R, bass, start, sr, 0.5)
        if b >= 4:
            for k in range(2):
                name, octv = melody[(b * 2 + k) % len(melody)]
                pl = pluck(note_hz(nn(name, octv)), 3.0, sr, decay=1.4)
                pan = -0.3 if k == 0 else 0.3
                s = stereo(pl, pan)
                place(L, s[0], start + k * 2 * beat + 0.5, sr, 0.35)
                place(R, s[1], start + k * 2 * beat + 0.5, sr, 0.35)
        if b % 4 == 3:
            bl = bell(note_hz(nn("E", 6)), 4.0, sr, 3.0)
            place(L, bl, start + 3 * beat, sr, 0.12)
            place(R, bl, start + 3 * beat + 0.03, sr, 0.12)
    drone = np.sin(2 * np.pi * note_hz(nn("A", 1)) * t_axis(total, sr)) * 0.12
    L += drone
    R += drone
    L = reverb(L, sr, 2.6, 0.45, 10)
    R = reverb(R, sr, 2.6, 0.45, 11)
    st = np.vstack([L, R])
    return loop_crossfade(st, sr, 6.0)


def song_orbita():
    """Exploración: luminosa y tranquila. Re mayor, 72 ppm, arpegios de campana sobre pads Dmaj7–Bm9–Gmaj7–A6sus."""
    sr = SR_MUS
    bpm = 72.0
    beat = 60.0 / bpm
    chords = [[("D", 4), ("F#", 4), ("A", 4), ("C#", 5)], [("B", 3), ("D", 4), ("F#", 4), ("C#", 5)],
              [("G", 3), ("B", 3), ("D", 4), ("F#", 4)], [("A", 3), ("D", 4), ("E", 4), ("F#", 4)]]
    bars = 32
    total = bars * 4 * beat + 6
    L = np.zeros(int(total * sr))
    R = np.zeros_like(L)
    for b in range(bars):
        ch = chords[b % 4]
        start = b * 4 * beat
        p = pad([note_hz(nn(c, o)) for c, o in ch], 4 * beat + 2.0, sr, bright=2200, seed=20 + b)
        place(L, p, start, sr, 0.45)
        place(R, p, start + 0.017, sr, 0.45)
        place(L, pluck(note_hz(nn(ch[0][0], 2)), 4 * beat, sr, 2.5, 0.4), start, sr, 0.4)
        place(R, pluck(note_hz(nn(ch[0][0], 2)), 4 * beat, sr, 2.5, 0.4), start, sr, 0.4)
        if b >= 2:
            seq = [0, 2, 1, 3, 2, 1, 3, 0]
            for k in range(8):
                c, o = ch[seq[k]]
                f = note_hz(nn(c, o + 1))
                bl = bell(f, 1.8, sr, 1.0)
                pan = np.sin(k * 0.8) * 0.6
                s = stereo(bl, pan)
                place(L, s[0], start + k * beat * 0.5, sr, 0.16)
                place(R, s[1], start + k * beat * 0.5, sr, 0.16)
    L = reverb(L, sr, 2.2, 0.4, 20)
    R = reverb(R, sr, 2.2, 0.4, 21)
    return loop_crossfade(np.vstack([L, R]), sr, 6.0)


def song_profundidades():
    """Atmósferas densas: oscura. Drones graves, clusters disonantes que crecen y rumor lejano."""
    sr = SR_MUS
    total = 96.0
    t = t_axis(total, sr)
    L = np.sin(2 * np.pi * 41.2 * t) * 0.25 + np.sin(2 * np.pi * 61.7 * t + 1.0) * 0.12
    R = np.sin(2 * np.pi * 41.25 * t + 0.4) * 0.25 + np.sin(2 * np.pi * 61.8 * t) * 0.12
    for k in range(9):
        at = k * 10.5 + rng.random() * 2
        base = nn("C", 3) + rng.integers(-3, 4)
        cl = pad([note_hz(base), note_hz(base + 1), note_hz(base + 6), note_hz(base + 13)], 9.0, sr, bright=700, seed=40 + k)
        place(L, cl, at, sr, 0.5)
        place(R, cl, at + 0.02, sr, 0.5)
    rum = fft_filter(brown(len(t)), sr, hi=120) * 0.25
    L += rum
    R += rum[::-1]
    L = reverb(L, sr, 3.5, 0.5, 40)
    R = reverb(R, sr, 3.5, 0.5, 41)
    return loop_crossfade(np.vstack([L, R]), sr, 6.0)


def song_fiesta():
    """Modo fiesta y emotes de baile: 124 ppm, bombo a negras, palmas, charles, bajo y acordes sincopados."""
    sr = SR_MUS
    bpm = 124.0
    beat = 60.0 / bpm
    bars = 32
    total = bars * 4 * beat + 2
    L = np.zeros(int(total * sr))
    R = np.zeros_like(L)
    kt = t_axis(0.35, sr)
    kick = np.sin(2 * np.pi * (50 + 120 * np.exp(-kt * 30)) * kt) * np.exp(-kt / 0.12)
    ht = int(0.05 * sr)
    hat = fft_filter(noise(ht), sr, lo=7000) * exp_decay(ht, sr, 0.012) * 0.35
    ct = int(0.18 * sr)
    clap = fft_filter(noise(ct), sr, lo=900, hi=4000) * exp_decay(ct, sr, 0.04) * 0.5
    prog = [("A", ["A", "C", "E"]), ("F", ["F", "A", "C"]), ("C", ["C", "E", "G"]), ("G", ["G", "B", "D"])]
    for b in range(bars):
        start = b * 4 * beat
        root, ch = prog[(b // 2) % 4]
        for q in range(4):
            place(L, kick, start + q * beat, sr, 0.9)
            place(R, kick, start + q * beat, sr, 0.9)
            place(L, hat, start + q * beat + beat / 2, sr, 0.8)
            place(R, hat, start + q * beat + beat / 2 + 0.004, sr, 0.8)
            if q in (1, 3) and b >= 2:
                place(L, clap, start + q * beat, sr, 0.8)
                place(R, clap, start + q * beat + 0.006, sr, 0.8)
        for e in range(8):
            if e % 2 == 1 or e == 0:
                f = note_hz(nn(root, 2) + (12 if e in (3, 7) else 0))
                tt = t_axis(beat * 0.45, sr)
                saw = sum(np.sin(2 * np.pi * f * h * tt) / h for h in range(1, 9))
                bs = fft_filter(saw, sr, hi=700) * env_adsr(len(tt), sr, 0.005, 0.08, 0.6, 0.05) * 0.35
                place(L, bs, start + e * beat / 2, sr)
                place(R, bs, start + e * beat / 2, sr)
        if b >= 4:
            for e in (1.5, 2.5, 3.75):
                st = pad([note_hz(nn(c, 4)) for c in ch], beat * 0.4, sr, bright=3500, seed=60 + b)
                st *= env_adsr(len(st), sr, 0.005, 0.05, 0.7, 0.1)
                place(L, st, start + e * beat, sr, 1.4)
                place(R, st, start + e * beat + 0.01, sr, 1.4)
    L = reverb(L, sr, 0.9, 0.2, 60)
    R = reverb(R, sr, 0.9, 0.2, 61)
    return np.vstack([L, R])[:, : int(bars * 4 * beat * sr)]


def music():
    d = os.path.join(ROOT, "music")
    for name, fn in (("despertar", song_despertar), ("orbita", song_orbita), ("profundidades", song_profundidades),
                     ("fiesta", song_fiesta)):
        st = fn()
        write(os.path.join(d, name + ".wav"), st, SR_MUS, stereo=True)


if __name__ == "__main__":
    print("Efectos:")
    sfx()
    print("Ambientes:")
    ambience()
    print("Música:")
    music()
