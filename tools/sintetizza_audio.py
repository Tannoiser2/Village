#!/usr/bin/env python3
"""Sintetizza la musica (una danza medievale con liuto, flauto dolce, bordone e tamburello) e gli
effetti sonori di Village.

Tutto è generato qui, senza campioni esterni: nessun problema di licenza.
Uso: python3 tools/sintetizza_audio.py   (serve ffmpeg con libvorbis per la musica)
Scrive assets/audio/musica.ogg e assets/audio/*.wav
"""
import os
import subprocess
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
rng = np.random.default_rng(2012)


def note_hz(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def lute(freq, dur, vel=1.0, bright=0.5):
    """Corda pizzicata (Karplus-Strong) con un po' di cassa armonica."""
    n = int(dur * SR)
    period = max(2, int(SR / freq))
    buf = rng.uniform(-1, 1, period)
    # attacco più morbido: filtra il rumore iniziale
    buf = np.convolve(buf, [0.5, 0.5], mode="same")
    out = np.zeros(n)
    decay = 0.996 - (1 - bright) * 0.004
    for i in range(n):
        j = i % period
        nxt = buf[(i + 1) % period]
        out[i] = buf[j]
        buf[j] = decay * 0.5 * (buf[j] + nxt)
    t = np.arange(n) / SR
    body = 0.15 * np.sin(2 * np.pi * freq * 2 * t) * np.exp(-t / 0.25)
    return (out + body) * vel * np.clip(t / 0.002, 0, 1)


def recorder(freq, dur, vel=1.0):
    """Flauto dolce: fondamentale, poche armoniche dispari, soffio e un vibrato leggero."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.2 * t) * np.clip((t - 0.15) / 0.2, 0, 1)
    ph = 2 * np.pi * np.cumsum(freq * vib) / SR
    s = np.sin(ph) + 0.18 * np.sin(3 * ph) + 0.06 * np.sin(5 * ph)
    breath = np.convolve(rng.standard_normal(n), np.ones(8) / 8, mode="same") * 0.05
    a = np.clip(t / 0.04, 0, 1)
    r = np.clip((dur - t) / 0.06, 0, 1)
    return (s + breath) * a * r * vel


def drone(freq, dur, vel=1.0):
    """Bordone (ghironda): dente di sega addolcito."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = np.zeros(n)
    for k in range(1, 9):
        s += np.sin(2 * np.pi * freq * k * t * (1 + 0.0007 * k)) / k * (0.85 ** k)
    a = np.clip(t / 0.3, 0, 1) * np.clip((dur - t) / 0.3, 0, 1)
    return s * a * vel


def tabor(dur, vel=1.0, pitch=150):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = pitch * (1 + 0.8 * np.exp(-t / 0.015))
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.09)
    snare = np.convolve(rng.standard_normal(n), [1, -1], mode="same") * np.exp(-t / 0.05) * 0.35
    return (body + snare) * vel


def add(buf, sig, start):
    i = int(start * SR)
    j = min(len(buf), i + len(sig))
    if i < len(buf):
        buf[i:j] += sig[: j - i]


def reverb(x, mix=0.25):
    out = x.copy()
    for d, g in [(0.031, 0.5), (0.041, 0.46), (0.053, 0.42), (0.067, 0.36), (0.089, 0.3), (0.13, 0.22)]:
        k = int(d * SR)
        y = np.zeros_like(x)
        y[k:] = x[:-k]
        for _ in range(3):
            y2 = np.zeros_like(y)
            y2[k:] = y[:-k] * g
            y = y + y2
        out += y * mix * g
    return out


def music():
    # danza in 6/8 in Re dorico: due frasi ripetute (A A B B) e una ripresa
    bpm = 132          # crome per battuta: 6, la semiminima puntata vale 3 crome
    eighth = 60 / bpm / 2 * 1.0
    bar = 6 * eighth
    D = 62
    dorian = [0, 2, 3, 5, 7, 9, 10]
    # melodie (gradi della scala, durata in crome); -1 = pausa
    A = [[(0, 2), (2, 1), (4, 2), (3, 1)], [(2, 2), (1, 1), (0, 3)], [(4, 2), (5, 1), (6, 2), (5, 1)], [(4, 3), (3, 3)],
         [(2, 2), (3, 1), (4, 2), (2, 1)], [(1, 2), (0, 1), (1, 3)], [(2, 2), (1, 1), (0, 2), (-3, 1)], [(0, 6)]]
    B = [[(7, 2), (6, 1), (7, 2), (4, 1)], [(5, 2), (4, 1), (3, 3)], [(4, 2), (5, 1), (6, 2), (4, 1)], [(5, 3), (4, 3)],
         [(7, 2), (8, 1), (7, 2), (5, 1)], [(4, 2), (3, 1), (2, 3)], [(3, 2), (2, 1), (1, 2), (-1, 1)], [(0, 6)]]
    roots = {"A": [0, 0, 3, 4, 0, -2, 0, 0], "B": [3, 3, 4, 0, 3, 0, -2, 0]}
    form = [("A", A), ("A", A), ("B", B), ("B", B)]
    total = sum(len(m) for _, m in form) * bar
    L = np.zeros(int((total + 4) * SR))
    R = np.zeros_like(L)

    def deg(d):
        o, k = divmod(d, 7)
        return D + 12 * o + dorian[k]

    bi = 0
    for name, phrase in form:
        for mi, meas in enumerate(phrase):
            t0 = bi * bar
            root = deg(roots[name][mi]) - 24
            # bordone su Re e La per tutta la battuta
            add(L, drone(note_hz(D - 24), bar + 0.05, 0.05), t0)
            add(R, drone(note_hz(D - 17), bar + 0.05, 0.04), t0)
            # liuto: arpeggio in crome sull'accordo della battuta
            chord = [root + 12, root + 19, root + 24, root + 19, root + 15 if roots[name][mi] in (0, 3) else root + 16, root + 19]
            for k, nt in enumerate(chord):
                sig = lute(note_hz(nt), eighth * 2.5, 0.22 if k % 3 == 0 else 0.15, 0.6)
                add(L if k % 2 == 0 else R, sig, t0 + k * eighth)
                add(R if k % 2 == 0 else L, sig * 0.5, t0 + k * eighth + 0.01)
            # tamburello: 1 e 4 forti, qualche colpo leggero
            for pos, v in [(0, 0.5), (2, 0.18), (3, 0.38), (5, 0.18)]:
                sig = tabor(0.25, v * 0.35, 140 if pos in (0, 3) else 190)
                add(L, sig * 0.8, t0 + pos * eighth)
                add(R, sig, t0 + pos * eighth)
            # flauto (la prima volta di ogni frase lo raddoppia il liuto all'ottava)
            pos = 0
            for d, ln in meas:
                if d > -9:
                    f = note_hz(deg(d) + 12)
                    add(L, recorder(f, ln * eighth * 0.95, 0.26), t0 + pos * eighth)
                    add(R, recorder(f, ln * eighth * 0.95, 0.2), t0 + pos * eighth + 0.008)
                    if name == "B":
                        add(R, lute(f / 2, ln * eighth + 0.3, 0.12, 0.8), t0 + pos * eighth)
                pos += ln
            bi += 1
    n = int(total * SR)
    for ch in (L, R):
        tail = ch[n:].copy()
        ch[: len(tail)] += tail
    L, R = L[:n], R[:n]
    L, R = reverb(L), reverb(R)
    st = np.stack([L, R], 1)
    st /= np.max(np.abs(st)) / 0.8
    st = np.tanh(st * 1.1) * 0.85
    wav = os.path.join(OUT, "_musica.wav")
    write_wav(wav, st, 2)
    ogg = os.path.join(OUT, "musica.ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "4", ogg], check=True)
    os.remove(wav)
    print("musica", round(total, 1), "s")


def write_wav(path, data, ch=1, sr=SR):
    d = np.clip(data, -1, 1)
    pcm = (d * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


def norm(x, peak=0.8):
    m = np.max(np.abs(x))
    return x / m * peak if m > 0 else x


def bell(f0, dur, partials=((1, 1, 1.2), (2.0, 0.5, 0.8), (2.4, 0.35, 0.6), (3.0, 0.25, 0.4), (4.2, 0.12, 0.25), (0.5, 0.4, 1.8))):
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = sum(a * np.sin(2 * np.pi * f0 * m * t) * np.exp(-t / tau) for m, a, tau in partials)
    return s * np.clip(t / 0.003, 0, 1)


def sfx():
    out = {}
    # clic di legno (pulsanti)
    n = int(0.06 * SR)
    t = np.arange(n) / SR
    out["click"] = norm(np.sin(2 * np.pi * 1500 * t) * np.exp(-t / 0.009) + 0.3 * rng.standard_normal(n) * np.exp(-t / 0.004), 0.5)
    # pedina di legno sul tabellone
    n = int(0.18 * SR)
    t = np.arange(n) / SR
    f = 480 * (1 + 0.5 * np.exp(-t / 0.01))
    tock = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.045) + 0.4 * np.sin(2 * np.pi * 1200 * t) * np.exp(-t / 0.015)
    out["pawn"] = norm(tock, 0.7)
    # cubetto preso (legno piccolo)
    n = int(0.1 * SR)
    t = np.arange(n) / SR
    out["cube"] = norm(np.sin(2 * np.pi * 2100 * t) * np.exp(-t / 0.012) + 0.5 * np.sin(2 * np.pi * 3400 * t) * np.exp(-t / 0.006), 0.45)
    # monete
    x = np.zeros(int(0.7 * SR))
    for k, st in enumerate([0.0, 0.09, 0.16]):
        n = int(0.5 * SR)
        t = np.arange(n) / SR
        base = rng.uniform(2300, 2700)
        s = sum(a * np.sin(2 * np.pi * base * m * t) * np.exp(-t / tau) for m, a, tau in [(1, 1, 0.18), (1.51, 0.6, 0.12), (2.37, 0.4, 0.08), (3.1, 0.2, 0.05)])
        add(x, s * (0.9 - k * 0.2), st)
    out["coin"] = norm(x, 0.55)
    # campana della chiesa (messa)
    out["bell"] = norm(reverb(bell(392, 3.0), 0.2), 0.6)
    # rintocco funebre
    out["toll"] = norm(reverb(bell(147, 3.5), 0.3), 0.55)
    # carta / pergamena
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    rust = np.convolve(rng.standard_normal(n), [1, -0.9], mode="same") * (np.sin(np.pi * t / 0.35) ** 2) * (0.6 + 0.4 * rng.random(n))
    out["card"] = norm(rust, 0.35)
    # onde (nave)
    n = int(1.0 * SR)
    t = np.arange(n) / SR
    noise = np.convolve(rng.standard_normal(n), np.ones(60) / 60, mode="same")
    out["splash"] = norm(noise * np.sin(np.pi * t) ** 1.5 * (1 + 0.4 * np.sin(2 * np.pi * 6 * t)), 0.5)
    # liuto e flauto: brevi frasi
    def phrase(notes, step, inst="lute", dur_each=0.9, vel=0.6):
        x = np.zeros(int((step * len(notes) + dur_each + 0.3) * SR))
        for i, nt in enumerate(notes):
            sig = lute(note_hz(nt), dur_each, vel) if inst == "lute" else recorder(note_hz(nt), dur_each, vel)
            add(x, sig, i * step)
        return norm(reverb(x, 0.18), 0.6)
    out["market"] = phrase([62, 66, 69, 74], 0.08, "lute", 0.8)
    out["turn"] = phrase([74, 81], 0.12, "flute", 0.25, 0.5)
    out["harvest"] = phrase([69, 67, 65, 62], 0.07, "lute", 0.6)
    out["win"] = phrase([62, 66, 69, 74, 72, 74, 78, 81], 0.13, "flute", 0.5)
    for name, data in out.items():
        write_wav(os.path.join(OUT, name + ".wav"), data, 1)
    print("effetti:", ", ".join(out))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    sfx()
    music()
