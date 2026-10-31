#!/usr/bin/env python3
"""v7.13 sounds: upgrade paks (activate / extend tick / warn / expire) and backpack gadgets (pickup,
turret deploy + shot, shield up/hit/down, EMP burst, bag full). Original, synthesised with numpy
(reuses the v7 helpers). Run: python3 tools/gen_audio_v13.py"""
import numpy as np, os
src = open(os.path.join(os.path.dirname(__file__), "gen_audio_v7.py")).read().split('save("ann_round_v7"')[0]
g = {"__file__": os.path.join(os.path.dirname(__file__), "gen_audio_v7.py")}; exec(src, g)
t, ex, noise, band, save, tone, at, SR = (g[k] for k in ("t", "ex", "noise", "band", "save", "tone", "at", "SR"))
def sweep(D, f0, f1, k=3.0):
    s = t(D); f = f0 + (f1 - f0) * (1 - np.exp(-s * k)) / (1 - np.exp(-D * k))
    return np.sin(2 * np.pi * np.cumsum(f) / SR)
# pak activate: rising power chord whoosh
D = 0.9; s = t(D)
save("pak_on_v13", sweep(D, 220, 880) * ex(D, 3) * 0.4 + (tone(440, D) + 0.6 * tone(659.3, D)) * np.minimum(1, s / 0.25) * ex(D, 4) * 0.3 + band(noise(D), 1500, 6000) * np.minimum(1, s / 0.4) * ex(D, 6) * 0.3, 0.85)
D = 0.12; save("pak_extend_v13", (tone(1320, D) + 0.5 * tone(1980, D)) * ex(D, 35), 0.5)
D = 0.18; save("pak_warn_v13", tone(880, D) * np.sign(np.sin(2 * np.pi * 14 * t(D))).clip(0) * ex(D, 8), 0.5)
D = 0.8; save("pak_off_v13", sweep(D, 700, 120) * ex(D, 4) * 0.5 + band(noise(D), 300, 2000) * ex(D, 7) * 0.25, 0.8)
# backpack
D = 0.3; save("gadget_pickup_v13", at(tone(660, 0.12) * ex(0.12, 25), 0, D) + at(tone(990, 0.15) * ex(0.15, 20), 0.09, D) + band(noise(D), 3000, 8000) * ex(D, 30) * 0.2, 0.6)
D = 0.35; save("bag_full_v13", (tone(180, D) + 0.5 * tone(190, D)) * ex(D, 9), 0.6)
D = 1.0; s = t(D)
save("turret_deploy_v13", at(band(noise(0.15), 200, 1500) * ex(0.15, 30), 0, D) + at(sweep(0.7, 120, 900, 2) * 0.3 * ex(0.7, 3), 0.2, D) + at((tone(1500, 0.08) + band(noise(0.08), 2000, 6000)) * ex(0.08, 40), 0.85, D), 0.75)
D = 0.1; save("turret_shot_v13", tone(240, D) * ex(D, 45) * 0.6 + band(noise(D), 1500, 7000) * ex(D, 50) * 0.6, 0.6)
D = 0.5; save("turret_off_v13", sweep(D, 600, 90) * ex(D, 5) * 0.5, 0.6)
D = 0.8; s = t(D)
save("shield_up_v13", (tone(300, D) + 0.5 * tone(450, D) + 0.3 * tone(600, D)) * np.minimum(1, s / 0.2) * ex(D, 3) * 0.5 * (1 + 0.3 * np.sin(2 * np.pi * 9 * s)), 0.75)
D = 0.2; save("shield_hit_v13", (tone(820, D) + band(noise(D), 2000, 6000) * 0.5) * ex(D, 22), 0.6)
D = 0.6; save("shield_down_v13", sweep(D, 600, 150) * ex(D, 5) * 0.4 + band(noise(D), 4000, 9000) * ex(D, 9) * 0.4, 0.65)
D = 1.1; s = t(D)
crack = sum(at(band(noise(0.04), 3000, 10000) * ex(0.04, 80), 0.05 + 0.07 * i + 0.03 * np.sin(i * 5), D) for i in range(12))
save("emp_burst_v13", tone(55, D) * ex(D, 4) * 0.8 + sweep(D, 2400, 200, 5) * ex(D, 3) * 0.35 + crack * 0.6, 0.9)
print("ok")
