#!/usr/bin/env python3
"""v7.12 sounds: hidden-room reveal (rumble + original sting), armor hit/break, and the Hive Reaper's
fire/reload. Original, synthesised with numpy (reuses the v7 helpers). Run: python3 tools/gen_audio_v12.py"""
import numpy as np, os
src = open(os.path.join(os.path.dirname(__file__), "gen_audio_v7.py")).read().split('save("ann_round_v7"')[0]
g = {"__file__": os.path.join(os.path.dirname(__file__), "gen_audio_v7.py")}; exec(src, g)
t, ex, noise, band, save, tone, at, SR = (g[k] for k in ("t", "ex", "noise", "band", "save", "tone", "at", "SR"))
# reveal: crumbling rumble, debris ticks, then a low eerie minor-second sting
D = 3.2; s = t(D)
rumble = band(noise(D), 25, 160) * np.minimum(1, s / 0.05) * np.exp(-s * 1.1) * 1.2
debris = sum(at(band(noise(0.06), 1500, 5000) * ex(0.06, 60) * 0.5, 0.1 + 0.13 * i + 0.05 * np.sin(i * 7), D) for i in range(9))
sting = at((tone(146.8, 2.2) + 0.7 * tone(155.6, 2.2) + 0.4 * tone(293.7, 2.2)) * np.minimum(1, t(2.2) / 0.3) * np.exp(-t(2.2) * 1.4), 0.7, D)
save("hidden_reveal_v12", rumble + debris + sting * 0.5, 0.9)
# armor hit: dull plate clank; break: ceramic shatter + down-sweep
D = 0.25; save("armor_hit_v12", (tone(420, D) * 0.6 + tone(1130, D) * 0.3) * ex(D, 26) + band(noise(D), 800, 3000) * ex(D, 50) * 0.5, 0.7)
D = 0.7; s = t(D)
sweep = np.sin(2 * np.pi * np.cumsum(900 * np.exp(-s * 4) + 120) / SR) * ex(D, 5) * 0.4
save("armor_break_v12", band(noise(D), 2000, 9000) * ex(D, 9) * 0.8 + sweep, 0.85)
# Hive Reaper shot: wet organic thump + bright energy zap
D = 0.16; s = t(D)
zap = np.sin(2 * np.pi * np.cumsum(1800 * np.exp(-s * 30) + 300) / SR) * ex(D, 28) * 0.5
save("shot_reaper_v12", tone(70, D) * ex(D, 35) * 0.9 + band(noise(D), 200, 1200) * ex(D, 40) * 0.5 + zap, 0.8)
# reload: wet chitin unlatch, rising whine as the drum regrows, heavy seat clunk
D = 2.4; s = t(D)
whine = np.sin(2 * np.pi * np.cumsum(180 + 520 * np.minimum(1, s / 2.0)) / SR) * np.minimum(1, s / 0.3) * np.where(s < 2.0, 1, np.exp(-(s - 2.0) * 20)) * 0.25
clicks = at(band(noise(0.1), 400, 2500) * ex(0.1, 40), 0.05, D) + at((tone(90, 0.3) + band(noise(0.3), 60, 600)) * ex(0.3, 18), 2.05, D)
save("reload_reaper_v12", whine + clicks, 0.85)
print("ok")
