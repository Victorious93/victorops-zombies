#!/usr/bin/env python3
"""v7.12 in-round music: three original hip-hop/trap instrumental loops, synthesised from scratch
(numpy oscillators + noise; no samples, no borrowed melodies). Each loop is a whole number of bars so it
repeats seamlessly. Writes audio/beat_*.ogg via ffmpeg (libvorbis, mono, 22.05 kHz).
Run: python3 tools/gen_beats_v12.py"""
import numpy as np, os, subprocess, wave, tempfile
SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "audio")
rng = np.random.default_rng(1212)

def env(n, a, d):
    i = np.arange(n) / SR
    return np.minimum(1, i / max(a, 1e-4)) * np.exp(-i * d)

def kick808(dur=0.7, f0=48):
    n = int(dur * SR); i = np.arange(n) / SR
    f = f0 + 90 * np.exp(-i * 30)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.tanh(1.6 * np.sin(ph) * np.exp(-i * 3.2))

def boomkick(dur=0.35):
    n = int(dur * SR); i = np.arange(n) / SR
    ph = 2 * np.pi * np.cumsum(55 + 110 * np.exp(-i * 40)) / SR
    return np.sin(ph) * np.exp(-i * 11) + rng.standard_normal(n) * np.exp(-i * 200) * 0.3

def snare(dur=0.3, tone=185):
    n = int(dur * SR); i = np.arange(n) / SR
    nz = rng.standard_normal(n); nz = np.convolve(nz, [1, -0.6], "same")
    return nz * np.exp(-i * 16) * 0.55 + np.sin(2 * np.pi * tone * i) * np.exp(-i * 28) * 0.5

def clap(dur=0.3):
    n = int(dur * SR); i = np.arange(n) / SR
    e = sum(np.where(i >= o, np.exp(-(i - o) * 60), 0) for o in (0, 0.011, 0.023)) + np.exp(-i * 14) * 0.5
    return np.convolve(rng.standard_normal(n), [1, -0.9], "same") * e * 0.5

def hat(dur=0.05, open_=False):
    n = int((0.22 if open_ else dur) * SR); i = np.arange(n) / SR
    nz = rng.standard_normal(n); nz = nz - np.convolve(nz, np.ones(4) / 4, "same")
    return nz * np.exp(-i * (14 if open_ else 70)) * 0.35

def sub(freq, dur, glide_to=None):
    n = int(dur * SR); i = np.arange(n) / SR
    f = np.full(n, freq) if glide_to is None else freq + (glide_to - freq) * np.minimum(1, i / 0.08)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.tanh(1.3 * np.sin(ph)) * env(n, 0.005, 1.2)

def keys(freq, dur, bright=0.3):
    n = int(dur * SR); i = np.arange(n) / SR
    s = sum(np.sin(2 * np.pi * freq * h * i) * (bright ** (h - 1)) / h for h in (1, 2, 3, 4))
    return s * env(n, 0.01, 2.5)

def pad(freq, dur):
    n = int(dur * SR); i = np.arange(n) / SR
    s = sum(((2 * ((freq * d * i) % 1) - 1)) for d in (0.996, 1.0, 1.004)) / 3
    s = np.convolve(s, np.ones(24) / 24, "same")
    return s * np.minimum(1, i / 0.3) * np.minimum(1, (dur - i) / 0.3)

def place(buf, x, t, g=1.0):
    s = int(t * SR) % len(buf); e = min(len(buf), s + len(x))
    buf[s:e] += x[:e - s] * g
    if e - s < len(x):   # wrap the tail to the loop start so the seam stays seamless
        buf[:len(x) - (e - s)] += x[e - s:] * g

def hz(semi, root=55.0): return root * 2 ** (semi / 12)

def make(name, bpm, bars, style, prog, mel):
    beat = 60 / bpm; step = beat / 4; L = int(round(bars * 4 * beat * SR))
    drums = np.zeros(L); bass = np.zeros(L); mus = np.zeros(L)
    for b in range(bars):
        t0 = b * 4 * beat
        root = prog[b % len(prog)]
        if style == "boom":
            for s in (0, 7, 10): place(drums, boomkick(), t0 + s * step, 0.9)
            for s in (4, 12): place(drums, snare(), t0 + s * step, 0.8)
            for s in range(0, 16, 2): place(drums, hat(), t0 + s * step + (0.012 if s % 4 else 0), 0.5 if s % 4 else 0.7)
            place(bass, sub(hz(root, 41.2), 2 * beat), t0, 0.55); place(bass, sub(hz(root + 3, 41.2), 2 * beat), t0 + 2 * beat, 0.5)
        else:
            ks = (0, 6, 10) if b % 2 == 0 else (0, 3, 8, 11)
            for s in ks:
                place(drums, kick808(), t0 + s * step, 0.8)
                place(bass, sub(hz(root, 41.2), 3 * step, hz(root - (5 if s == 11 else 0), 41.2)), t0 + s * step, 0.6)
            place(drums, clap(), t0 + 8 * step, 0.9); place(drums, snare(0.2, 210), t0 + 8 * step, 0.4)
            for s in range(16):
                roll = style == "trap" and b % 4 == 3 and s >= 12
                place(drums, hat(), t0 + s * step, 0.45 if s % 2 else 0.6)
                if roll: place(drums, hat(0.03), t0 + (s + 0.5) * step, 0.35)
            if b % 2 == 1: place(drums, hat(open_=True), t0 + 14 * step, 0.4)
        # dark minor chord pad (root, minor third, fifth) + a sparse keys figure
        for iv in (0, 3, 7): place(mus, pad(hz(root + iv + 12, 110), 4 * beat), t0, 0.12)
        for k, (s, semi) in enumerate(mel[b % len(mel)]):
            place(mus, keys(hz(root + semi + 12, 220), 2 * step), t0 + s * step, 0.22)
    mix = drums * 0.75 + bass + mus
    mix = np.tanh(mix * 1.2) / np.tanh(1.2)
    mix *= 0.5 / np.max(np.abs(mix))
    tmp = tempfile.mktemp(suffix=".wav")
    with wave.open(tmp, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((mix * 32767).astype(np.int16).tobytes())
    out = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "1", out], check=True)
    os.remove(tmp)
    print(name, bpm, "bpm", bars, "bars", round(L / SR, 2), "s", os.path.getsize(out) // 1024, "KB")

# (step, semitone-in-minor) figures; scale degrees of natural minor
make("beat_grave_shift", 88, 16, "boom", [0, 0, -4, -2], [[(0, 7), (6, 3), (10, 5)], [(2, 10), (8, 7)], [(0, 3), (4, 2), (12, 0)], [(6, 7), (14, 8)]])
make("beat_static_ward", 92, 16, "trap", [0, -2, -4, -5], [[(0, 12), (3, 10), (6, 7)], [(8, 3)], [(0, 7), (10, 8)], [(4, 5), (12, 3)]])
make("beat_low_tide", 86, 16, "trap", [0, 3, -4, -2], [[(0, 0), (8, 7)], [(4, 3), (12, 2)], [(0, 8), (6, 7)], [(10, 3)]])
