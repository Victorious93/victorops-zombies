#!/usr/bin/env python3
"""v7 sounds: voice-like announcer stings (formant-synthesised syllables, no recorded voices),
alternate-ammo effects, wonder-weapon/pact/boss cues. Original work, numpy only.
Run: python3 tools/gen_audio_v7.py"""
import numpy as np, os, importlib.util
spec = importlib.util.spec_from_file_location("v4", os.path.join(os.path.dirname(__file__), "gen_audio_v4.py"))
src = open(spec.origin).read().split("# two more zombie voices")[0]
g = {"__file__": spec.origin}; exec(src, g)
t, ex, noise, band, save = g["t"], g["ex"], g["noise"], g["band"], g["save"]
rng = np.random.default_rng(707); SR = g["SR"]
def tone(f, d): return np.sin(2*np.pi*f*t(d))
def at(x, off, total):
    out = np.zeros(int(SR*total)); i = int(SR*off); n = min(len(x), len(out)-i); out[i:i+n] += x[:n]; return out
# vowel formants (Hz) for a deep, gravelly announcer
V = {"a": (730, 1090, 2440), "o": (570, 840, 2410), "u": (300, 870, 2240), "e": (530, 1840, 2480), "i": (390, 1990, 2550)}
def syl(v, d, f0=78, cons=None, glide=0.0):
    s = t(d); f = f0 * (1 + 0.03*np.sin(2*np.pi*5.5*s)) * (1 + glide*s/d)
    ph = np.cumsum(f)/SR; src_ = 2*(ph % 1.0) - 1 + band(noise(d), 80, 4000)*0.15   # buzzy glottal + breath
    out = sum(band(src_, fm*0.85, fm*1.15) * w for fm, w in zip(V[v], (1.0, 0.6, 0.25)))
    env = np.minimum(1, s/0.03) * np.minimum(1, (d - s)/0.08)
    out = out * env
    if cons == "k": out = at(band(noise(0.05), 1500, 5000)*ex(0.05, 60)*0.8, 0, d) + at(out, 0.04, d)
    if cons == "s": out = at(band(noise(0.12), 4000, 9000)*0.5, 0, d) + at(out, 0.1, d)
    if cons == "d": out = at(tone(110, 0.04)*ex(0.04, 50), 0, d) + at(out, 0.02, d)
    return out
def phrase(parts, gap=0.04, verb=0.35):
    xs = [syl(*p) for p in parts]; total = sum(len(x) for x in xs)/SR + gap*len(xs) + 0.9
    out = np.zeros(int(SR*total)); i = 0
    for x in xs: out[i:i+len(x)] += x; i += len(x) + int(SR*gap)
    for dl, a in ((0.11, verb), (0.23, verb*0.6), (0.37, verb*0.35)):   # hall echo
        k = int(SR*dl); out[k:] += out[:-k]*a
    sub = tone(41, total)*np.exp(-t(total)*2.5)*0.4
    return out + sub
save("ann_round_v7",   phrase([("o", 0.32, 82, "d"), ("a", 0.5, 74, None, -0.15)]), 0.9)
save("ann_boss_v7",    phrase([("a", 0.28, 70, "k"), ("u", 0.35, 64), ("o", 0.7, 55, None, -0.25)], verb=0.45), 0.95)
save("ann_part_v7",    phrase([("i", 0.22, 96, "k"), ("a", 0.35, 88, None, 0.1)]), 0.8)
save("ann_built_v7",   phrase([("e", 0.25, 84, "d"), ("o", 0.25, 90), ("a", 0.55, 98, None, 0.12)]), 0.9)
save("ann_pact_v7",    phrase([("u", 0.3, 66, "s"), ("o", 0.6, 60, None, -0.2)], verb=0.5), 0.85)
save("ann_sealed_v7",  phrase([("a", 0.25, 72, "s"), ("e", 0.25, 80, "d"), ("o", 0.8, 68, None, -0.1)], verb=0.5), 0.95)
save("ann_gameover_v7", phrase([("o", 0.4, 70, "d"), ("a", 0.4, 62), ("u", 0.9, 50, None, -0.3)], verb=0.55), 0.95)
save("ann_highscore_v7", phrase([("i", 0.22, 100, "s"), ("a", 0.25, 110), ("o", 0.6, 120, None, 0.15)]), 0.85)
save("ann_laststand_v7", phrase([("a", 0.3, 76, "s"), ("a", 0.6, 66, "d", -0.2)]), 0.85)
save("ann_forge_v7",   phrase([("o", 0.3, 80, "k"), ("e", 0.55, 92, None, 0.1)]), 0.85)
# alt ammo
d = 0.6; save("alt_fire_v7", band(noise(d), 200, 3000)*ex(d, 4)*(1+0.5*np.sin(2*np.pi*13*t(d))) + tone(70, d)*ex(d, 8)*0.5, 0.7)
d = 0.45; zap = np.sign(np.sin(2*np.pi*np.cumsum(900+700*rng.uniform(-1, 1, int(SR*d)))/SR)) * ex(d, 7)
save("alt_shock_v7", band(zap, 400, 7000) + band(noise(d), 3000, 9000)*ex(d, 25)*0.5, 0.6)
d = 0.7; save("alt_freeze_v7", sum(tone(f, d)*ex(d, k)*a for f, k, a in ((2400, 6, 0.4), (3150, 8, 0.3), (4700, 10, 0.2))) + band(noise(d), 5000, 10000)*ex(d, 9)*0.4, 0.6)
d = 0.35; save("shatter_v7", band(noise(d), 2500, 10000)*ex(d, 14) + sum(tone(f, d)*ex(d, 20)*0.2 for f in (3300, 4100, 5200)), 0.7)
# quest / pact / boss
d = 1.4; save("part_pickup_v7", sum(at(tone(f, 0.5)*ex(0.5, 6)*0.5, o, d) for f, o in ((523, 0), (659, 0.12), (784, 0.24), (1046, 0.36))), 0.7)
d = 2.2; s = t(d); save("wonder_build_v7", band(noise(d), 80, 1500)*np.sin(np.pi*s/d)*0.6 + np.sin(2*np.pi*np.cumsum(110+330*s/d)/SR)*np.sin(np.pi*s/d)*0.6, 0.8)
d = 0.5; save("gloam_fire_v7", np.sin(2*np.pi*np.cumsum(1400*np.exp(-s[:int(SR*d)]*6)+200)/SR)*ex(d, 6) + band(noise(d), 300, 3000)*ex(d, 15)*0.4, 0.75)
d = 1.8; s = t(d); save("pact_step_v7", tone(55, d)*np.sin(np.pi*s/d) + band(noise(d), 40, 400)*np.sin(np.pi*s/d)*0.8 + tone(220, d)*ex(d, 2)*0.2, 0.85)
d = 2.5; save("boss_roar_v7", g["growl"](48, d, [(300, 1.0), (700, 0.6), (1600, 0.3)], wobble=4.0, rough=0.8), 1.0)
