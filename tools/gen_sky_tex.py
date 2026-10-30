"""Genera la textura de la Vía Láctea (ADR-040, rendimiento ronda 9) en proyección equirectangular y coordenadas
ECLÍPTICAS J2000 (x hacia el punto Aries, z al polo norte de la eclíptica): banda a lo largo del plano galáctico
con estructura, carriles de polvo, el bulbo cálido hacia el centro galáctico (Sagitario) y nebulosas tenues.
El cielo (sky.gdshader) la lee con una sola muestra en lugar de calcular ruido por píxel.

Uso: python tools/gen_sky_tex.py   → assets/sky/milky_way.png (2048×1024)
"""
import os
import struct
import zlib
import numpy as np

W, H = 2048, 1024
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sky", "milky_way.png")
GAL_POLE = np.array([-0.8676, -0.0003, 0.4971])
GAL_CENTER = np.array([-0.0548, -0.9939, -0.0965])


def hash3(ix, iy, iz, seed):
    h = (ix * 73856093) ^ (iy * 19349663) ^ (iz * 83492791) ^ (seed * 2654435761)
    h = (h ^ (h >> 13)) * 1274126177
    h = h ^ (h >> 16)
    return (h & 0xFFFFFF).astype(np.float64) / float(0xFFFFFF)


def vnoise(p, seed=0):
    i = np.floor(p).astype(np.int64)
    f = p - i
    f = f * f * (3.0 - 2.0 * f)
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[..., 0] if dx else 1 - f[..., 0]) * (f[..., 1] if dy else 1 - f[..., 1]) * (f[..., 2] if dz else 1 - f[..., 2])
                out = out + w * hash3(i[..., 0] + dx, i[..., 1] + dy, i[..., 2] + dz, seed)
    return out


def fbm(p, octaves=5, seed=0):
    s = 0.0
    a = 0.5
    for o in range(octaves):
        s = s + a * vnoise(p, seed + o * 17)
        p = p * 2.03 + 3.7
        a *= 0.5
    return s / (1.0 - 0.5 ** octaves)


def write_png(path, rgb):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    h, w, _ = rgb.shape
    raw = b"".join(b"\x00" + rgb[y].tobytes() for y in range(h))

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(png)


def main():
    u = (np.arange(W) + 0.5) / W
    v = (np.arange(H) + 0.5) / H
    lon = (u - 0.5) * 2 * np.pi
    colat = v * np.pi
    LON, COL = np.meshgrid(lon, colat)
    e = np.stack([np.sin(COL) * np.cos(LON), np.sin(COL) * np.sin(LON), np.cos(COL)], axis=-1)
    b = e @ GAL_POLE
    band = np.exp(-b * b / (2 * 0.12 ** 2))
    gc = np.arccos(np.clip(e @ GAL_CENTER, -1, 1))
    bulge = np.exp(-gc * gc / (2 * 0.5 ** 2))
    n1 = fbm(e * 4.0, 5, 1)
    n2 = fbm(e * 12.0, 4, 2)
    core = np.exp(-b * b / (2 * 0.035 ** 2))
    dust = np.clip((fbm(e * 7.0, 5, 3) - 0.42) / 0.3, 0, 1) * core
    lum = band * (0.3 + 0.7 * n1) * (0.55 + 0.45 * n2) * (1.0 + bulge * 1.6)
    lum *= 1.0 - dust * 0.85
    warm = np.clip(bulge * 1.4, 0, 1)[..., None]
    c = np.array([0.55, 0.62, 0.85]) * (1 - warm) + np.array([1.0, 0.82, 0.6]) * warm
    neb = np.clip((fbm(e * 2.4, 4, 4) - 0.58) / 0.24, 0, 1) * band
    t = vnoise(e * 1.8, 5)[..., None]
    nc = np.array([0.62, 0.16, 0.34]) * (1 - t) + np.array([0.12, 0.46, 0.56]) * t
    col = c * lum[..., None] * 0.075 + nc * neb[..., None] * 0.05
    # Se guarda escalado ×4 (el shader divide): más precisión en 8 bits para un brillo tan bajo.
    rgb = np.clip(col * 4.0 * 255.0, 0, 255).astype(np.uint8)
    write_png(OUT, rgb)
    print("escrito", OUT, os.path.getsize(OUT) // 1024, "kB")


if __name__ == "__main__":
    main()
