#!/usr/bin/env python3
"""Icone 2D dei familiari ricavate dal modello 3D del gioco (assets/models/meeple.obj), viste di fronte,
con luce morbida e bordo scuro, una per colore. Scrive assets/ui/meeple_<colore>.png (256 x 256)."""
import os
import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
COLORS = {"red": "#c4161c", "yellow": "#f2b705", "blue": "#1565a6", "white": "#f1ead2", "gray": "#8d948d"}
S = 1024          # disegno in grande, poi si riduce (bordi morbidi)
OUT = 256

V, F = [], []
for line in open(os.path.join(ROOT, "assets", "models", "meeple.obj")):
    p = line.split()
    if not p:
        continue
    if p[0] == "v":
        V.append([float(x) for x in p[1:4]])
    elif p[0] == "f":
        idx = [int(t.split("/")[0]) - 1 for t in p[1:]]
        for k in range(1, len(idx) - 1):
            F.append((idx[0], idx[k], idx[k + 1]))
V = np.array(V)
lo, hi = V.min(0), V.max(0)
size = max(hi[0] - lo[0], hi[1] - lo[1]) * 1.08
cx, cy = (lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2
light = np.array([-0.45, 0.55, 0.70])
light /= np.linalg.norm(light)


def render(hexcol):
    base = np.array([int(hexcol[i:i + 2], 16) for i in (1, 3, 5)], float) / 255.0
    col = np.zeros((S, S, 3))
    alpha = np.zeros((S, S))
    depth = np.full((S, S), -1e9)
    P = np.stack([(V[:, 0] - cx) / size * S + S / 2, S / 2 - (V[:, 1] - cy) / size * S, V[:, 2]], 1)
    for a, b, c in F:
        n = np.cross(V[b] - V[a], V[c] - V[a])
        ln = np.linalg.norm(n)
        if ln == 0:
            continue
        n /= ln
        if n[2] < 0:
            n = -n
        shade = 0.42 + 0.58 * max(0.0, float(n @ light))
        tri = P[[a, b, c]]
        x0, y0 = np.floor(tri[:, :2].min(0)).astype(int)
        x1, y1 = np.ceil(tri[:, :2].max(0)).astype(int)
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, S - 1), min(y1, S - 1)
        if x1 < x0 or y1 < y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        (ax, ay, az), (bx, by, bz), (qx, qy, qz) = tri
        d = (by - qy) * (ax - qx) + (qx - bx) * (ay - qy)
        if abs(d) < 1e-9:
            continue
        w1 = ((by - qy) * (xs - qx) + (qx - bx) * (ys - qy)) / d
        w2 = ((qy - ay) * (xs - qx) + (ax - qx) * (ys - qy)) / d
        w3 = 1 - w1 - w2
        inside = (w1 >= 0) & (w2 >= 0) & (w3 >= 0)
        z = w1 * az + w2 * bz + w3 * qz
        sub = depth[y0:y1 + 1, x0:x1 + 1]
        upd = inside & (z > sub)
        sub[upd] = z[upd]
        col[y0:y1 + 1, x0:x1 + 1][upd] = base * shade
        alpha[y0:y1 + 1, x0:x1 + 1][upd] = 1.0
    # sfumatura del legno: più chiaro in alto a sinistra, più scuro in basso
    yy, xx = np.mgrid[0:S, 0:S] / S
    col *= (1.12 - 0.30 * yy - 0.12 * xx)[..., None]
    img = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8), "RGB")
    mask = Image.fromarray((alpha * 255).astype(np.uint8), "L")
    # bordo scuro come il legno visto di profilo
    edge = mask.filter(ImageFilter.MaxFilter(13))
    dark = Image.new("RGBA", (S, S), (40, 22, 10, 255))
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.paste(dark, (0, 0), edge)
    fg = img.convert("RGBA")
    fg.putalpha(mask)
    out.alpha_composite(fg)
    return out.resize((OUT, OUT), Image.LANCZOS)


for key, hx in COLORS.items():
    render(hx).save(os.path.join(ROOT, "assets", "ui", "meeple_%s.png" % key), optimize=True)
    print("meeple", key)
