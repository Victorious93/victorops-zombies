#!/usr/bin/env python3
"""v7.10 round-change sting, synthesised from scratch with numpy (original work, no samples):
a timpani-like hit, a detuned low-brass minor stab (D minor add b6) and a rising reverse-swell.
Run: python3 tools/gen_audio_v10.py"""
import numpy as np, wave, os
SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "audio")
rng = np.random.default_rng(710)
def t(d): return np.arange(int(SR * d)) / SR
def at(x, off, total):
    out = np.zeros(int(SR * total)); i = int(SR * off); n = min(len(x), len(out) - i); out[i:i + n] += x[:n]; return out
def lowpass(x, a): 
    y = np.zeros_like(x); acc = 0.0
    for i, v in enumerate(x): acc += a * (v - acc); y[i] = acc
    return y
def brass(f, d):
    s = t(d); ph = 2 * np.pi * f * s
    saw = sum(np.sin(ph * k * (1 + 0.0015 * rng.uniform(-1, 1))) / k for k in range(1, 14))
    env = np.minimum(1, s / 0.03) * np.exp(-s * 0.9)
    return saw * env
D = 3.2; total = D + 0.6
s = t(0.9)
timp = (np.sin(2 * np.pi * np.cumsum(70 - 22 * np.minimum(s, 0.3)) / SR) * np.exp(-s * 3.2)
        + lowpass(rng.standard_normal(len(s)), 0.08) * np.exp(-s * 18) * 0.8)
swell_s = t(0.6)
swell = lowpass(rng.standard_normal(len(swell_s)), 0.05) * (swell_s / 0.6) ** 3 * 0.9
chord = sum(brass(f, D) for f in [73.4, 146.8, 174.6, 220.0, 233.1]) / 5
sting = at(swell, 0, total) + at(timp * 1.1, 0.6, total) + at(chord * 1.4, 0.6, total)
sting += at(timp * 0.6, 1.25, total)   # second, softer hit
sting = lowpass(sting, 0.35)
sting = sting / np.max(np.abs(sting)) * 0.9
with wave.open(os.path.join(OUT, "round_sting_v10.wav"), "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((sting * 32767).astype(np.int16).tobytes())
print("ok")
