#!/usr/bin/env python3
"""Prepara gli asset del gioco a partire dal modulo Tabletop Simulator di Village.

Uso: python3 tools/prepara_asset.py <cartella Mods del modulo TTS>
(la cartella che contiene Images/, Models/ e Workshop/). Scrive in assets/.
Le immagini restano © eggertspiele / Pegasus: servono solo per l'uso personale.
"""
import os, re, sys, shutil
from PIL import Image

SRC = sys.argv[1] if len(sys.argv) > 1 else "/mnt/user-data/uploads/Village/Mods"
DST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")
IMG = os.path.join(SRC, "Images")


def find(key):
    for f in os.listdir(IMG):
        if key in f:
            return os.path.join(IMG, f)
    raise SystemExit("manca l'immagine " + key)


def out(*p):
    path = os.path.join(DST, *p)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    return path


def save_jpg(im, path, q=86):
    im.convert("RGB").save(path, quality=q, optimize=True)


# ------------------------------------------------------------------ tabellone
board = Image.open(find("9yleWNA")).convert("RGBA")       # 2245 x 2245
BW = 32.2                                                  # larghezza in unità TTS (scala 16.1)
K = 4.45                                                   # lato maggiore di un token TTS a scala 1


def tts_px(x, z):
    return ((x + 16.1) / BW * board.width, (17.1 - z) / BW * board.height)


def overlay(base, key, x, z, scale):
    t = Image.open(find(key)).convert("RGBA")
    big = K * scale / BW * board.width
    s = big / max(t.size)
    t = t.resize((round(t.width * s), round(t.height * s)), Image.LANCZOS)
    cx, cy = tts_px(x, z)
    base.alpha_composite(t, (round(cx - t.width / 2), round(cy - t.height / 2)))
    return (cx - t.width / 2, cy - t.height / 2, t.width, t.height)


PORT = ("843715475926060993", 6.47, 10.29, 4.29)
INN = ("9iRvIMi", 8.03, -9.28, 2.94)
BREW = ("7y5KkTD", -12.02, -10.45, 1.63)
rects = {}
for name, layers in [("base", []), ("inn", [INN, BREW]), ("port", [PORT]), ("innport", [PORT, INN, BREW])]:
    b = board.copy()
    for (k, x, z, sc) in layers:
        rects[k] = overlay(b, k, x, z, sc)
    save_jpg(b.resize((2048, 2048), Image.LANCZOS), out("board", "board_%s.jpg" % name), 88)
print("rettangoli delle sovrapposizioni (pixel del tabellone 2245):", {k: tuple(round(v) for v in r) for k, r in rects.items()})

chron = Image.open(find("EDzmeFU")).convert("RGBA")
chron.thumbnail((1400, 1400), Image.LANCZOS)
save_jpg(chron, out("board", "chron5.jpg"), 86)
graves = Image.open(find("12eEaQq")).convert("RGBA")
graves.thumbnail((512, 512), Image.LANCZOS)
graves.save(out("board", "graves5.png"), optimize=True)

# ------------------------------------------------------------------ fattorie
for key, col in [("ayBs8xn", "yellow"), ("G5DxNMs", "blue"), ("U72KguZ", "gray"), ("xo2hySA", "red"), ("ElwSm3K", "white")]:
    im = Image.open(find(key)).convert("RGB").resize((1024, 1024), Image.LANCZOS)
    save_jpg(im, out("farms", col + ".jpg"), 85)


# ------------------------------------------------------------------ carte
def sheet(key, cols, rows, n, prefix, size=None, q=86):
    im = Image.open(find(key)).convert("RGB")
    cw, ch = im.width / cols, im.height / rows
    for i in range(n):
        r, c = divmod(i, cols)
        card = im.crop((round(c * cw), round(r * ch), round((c + 1) * cw), round((r + 1) * ch)))
        if size:
            card = card.resize(size, Image.LANCZOS)
        save_jpg(card, out("cards", "%s%d.jpg" % (prefix, i)), q)


sheet("qzodyVC", 7, 5, 34, "v", (300, 475))                 # abitanti (Locanda e Porto)
save_jpg(Image.open(find("YRrrP37")).resize((300, 475), Image.LANCZOS), out("cards", "v_back.jpg"))
sheet("s1JPT0y", 7, 5, 32, "c", (200, 200))                 # clienti
save_jpg(Image.open(find("httpiimgurcomQSbPhIi")).resize((200, 200), Image.LANCZOS), out("cards", "c_back.jpg"))
sheet("Y1YS3KW", 5, 2, 8, "gs", (300, 475))                  # obiettivi d'argento
sheet("fysWEgs", 5, 2, 9, "gg", (300, 475))                  # obiettivi d'oro
save_jpg(Image.open(find("cjTbhE4")).resize((300, 475), Image.LANCZOS), out("cards", "gs_back.jpg"))
save_jpg(Image.open(find("kfjmg6F")).resize((300, 475), Image.LANCZOS), out("cards", "gg_back.jpg"))
for k, key in enumerate(["gv7My5U", "MbrlltS", "SaVfZe4"]):  # capitani da 1, 2, 3 monete
    im = Image.open(find(key)).convert("RGB")
    cw, ch = im.width / 3, im.height / 2
    for i in range(5):
        r, c = divmod(i, 3)
        card = im.crop((round(c * cw), round(r * ch), round((c + 1) * cw), round((r + 1) * ch))).resize((300, 475), Image.LANCZOS)
        save_jpg(card, out("cards", "cap%d.jpg" % (k * 5 + i)))
for k, key in enumerate(["TDwim4u", "gFjK443", "oIqHLAM"]):
    save_jpg(Image.open(find(key)).resize((300, 475), Image.LANCZOS), out("cards", "cap_back%d.jpg" % k))

# ------------------------------------------------------------------ segnalini
TOK = {"coin": "9Rdfwb7", "grain": "HVqHyit", "horse": "q3dqykY", "plow": "di2UxXF", "ox": "SwImFrb", "wagon": "2s08gmI",
       "beer": "m64Sids", "scroll": "P2IL6cJ", "cocoa": "d5sVkja", "tea": "rMn11z1", "start": "N3S8SU4", "next": "uoAsRcT"}
for name, key in TOK.items():
    im = Image.open(find(key)).convert("RGBA")
    im.thumbnail((256, 256), Image.LANCZOS)
    im.save(out("tokens", name + ".png"), optimize=True)
ch = Image.open(find("kbdxj08")).convert("RGB")          # forziere (dalla texture del modello)
ch.crop((20, 0, 500, 470)).resize((240, 235), Image.LANCZOS).save(out("tokens", "chest.png"))
ship = Image.open(find("jpqZQb1")).convert("RGB")        # plancia della nave (stiva a 3 posti)
ship.crop((60, 40, 420, 1000)).rotate(90, expand=True).resize((600, 225), Image.LANCZOS).save(out("tokens", "shiptile.jpg"), quality=86)

# ------------------------------------------------------------------ ambiente e interfaccia
save_jpg(Image.open(find("7vj106j")).resize((1024, 640), Image.LANCZOS), out("env", "table.jpg"), 84)
sky = Image.open(find("2saxBM7")).convert("RGB").resize((2048, 1024), Image.LANCZOS)
save_jpg(sky, out("env", "sky.jpg"), 82)
logo = Image.open(find("rirYpL2")).convert("RGBA")
logo.thumbnail((900, 400), Image.LANCZOS)
logo.save(out("ui", "logo.png"), optimize=True)
cover = Image.open(os.path.join(SRC, "Workshop", "1105793633.png")).convert("RGB")
save_jpg(cover, out("ui", "cover.jpg"), 88)

# ------------------------------------------------------------------ modelli 3D
MOD = os.path.join(SRC, "Models")
for key, name in [("zLbtBw8q", "meeple"), ("WMac7LXR", "meeple_lay"), ("EH0XtEDr", "ship")]:
    src = [f for f in os.listdir(MOD) if key in f][0]
    shutil.copy(os.path.join(MOD, src), out("models", name + ".obj"))
for key, n in [("Z6GmYvz", 1), ("vZKkj7G", 2), ("fs3jTZq", 3), ("NA4ULxy", 4)]:
    im = Image.open(find(key)).convert("RGB").resize((512, 512), Image.LANCZOS)
    save_jpg(im, out("models", "gen%d.jpg" % n), 88)
print("fatto")
