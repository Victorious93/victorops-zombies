#!/usr/bin/env python3
"""v5 sounds (special zombies, juice jingles), synthesised from scratch with numpy (original work, no samples).
Run: python3 tools/gen_audio_v5.py -> writes extra audio/*.wav"""
import numpy as np, os, importlib.util
spec = importlib.util.spec_from_file_location("v4", os.path.join(os.path.dirname(__file__), "gen_audio_v4.py"))
# reuse helpers without re-running v4's writes
src = open(spec.origin).read().split("# two more zombie voices")[0]
g = {"__file__": spec.origin}; exec(src, g)
t, ex, noise, band, save, growl = g["t"], g["ex"], g["noise"], g["band"], g["save"], g["growl"]
rng = np.random.default_rng(505); SR = g["SR"]
# Sprinter: thin, fast panting shriek-chatter
pant = np.concatenate([band(noise(0.12), 900, 5000) * np.sin(np.pi * t(0.12) / 0.12) for _ in range(5)])
save("sprinter_call", pant * 0.7 + np.pad(growl(180, 0.6, [(900, 160), (2800, 400)], 14.0, 0.9), (0, len(pant) - int(SR * 0.6))) if len(pant) > SR * 0.6 else pant)
# Brute: deep roar + chain-rattle tell, heavy footstep
save("brute_roar", growl(42, 2.0, [(300, 90), (650, 120), (1500, 250)], 2.2, 0.9) + band(noise(2.0), 40, 200) * ex(2.0, 1.2) * 0.4)
rattle = sum(band(noise(0.05), 2500, 8000) * ex(0.05, 60) for _ in range(1))
save("brute_rattle", np.concatenate([np.pad(rattle, (0, int(SR * rng.uniform(0.03, 0.09)))) for _ in range(8)]), 0.6)
save("brute_step", np.sin(2*np.pi*38*t(0.35)) * ex(0.35, 10) + band(noise(0.35), 30, 250) * ex(0.35, 16) * 0.8)
# Bloater: wet gurgle tell, then a squelchy pop and a gas hiss
s = t(1.4); bub = np.zeros_like(s)
for k in range(18):
    c = rng.uniform(0, 1.3); f = rng.uniform(120, 420)
    bub += np.sin(2*np.pi*f*(s - c) * (1 + 2*(s - c))) * np.exp(-np.abs(s - c) * 30) * (s > c)
save("bloater_gurgle", bub + growl(70, 1.4, [(400, 100), (800, 140)], 4.0, 0.5) * 0.4)
save("bloater_pop", band(noise(0.7), 60, 3000) * ex(0.7, 7) + np.sin(2*np.pi*(70 - 30*t(0.7))*t(0.7)) * ex(0.7, 9))
save("gas_hiss", band(noise(2.5), 2500, 9000) * np.minimum(1, t(2.5) / 0.1) * ex(2.5, 1.2), 0.45)
# juice: crate jingle (music-box arpeggio), forge jingle (rising metallic chord), points tick
def bell(f, d, k=5.0): return (np.sin(2*np.pi*f*t(d)) + 0.4*np.sin(2*np.pi*f*2.76*t(d)) * ex(d, k*2)) * ex(d, k)
notes = [659, 784, 988, 1175, 988, 1319]
save("crate_jingle", np.concatenate([np.pad(bell(f, 0.32), (0, 0)) for f in notes]) , 0.6)
fj = sum(bell(f, 1.6, 2.2) * np.minimum(1, t(1.6) / (0.05 + i*0.12)) for i, f in enumerate([220, 277, 330, 440, 554]))
save("forge_jingle", fj, 0.7)
save("tick", np.sin(2*np.pi*2400*t(0.03)) * ex(0.03, 150), 0.35)
# round-start rumble + slow-mo whoosh
save("rumble", band(noise(1.6), 20, 140) * np.sin(np.pi * t(1.6) / 1.6) + np.sin(2*np.pi*32*t(1.6)) * np.sin(np.pi * t(1.6) / 1.6) * 0.6)
save("slowmo", band(noise(1.0), 100, 900) * np.sin(np.pi * t(1.0) / 1.0) + np.sin(2*np.pi*(160 - 110*t(1.0))*t(1.0)) * ex(1.0, 2) * 0.5, 0.7)
save("gib_burst", band(noise(0.5), 80, 2500) * ex(0.5, 9) + np.sin(2*np.pi*60*t(0.5)) * ex(0.5, 12) * 0.7)
print("ok")
