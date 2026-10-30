#!/usr/bin/env python3
"""v7.11 sounds: power-up announcer call-outs (formant-synthesised syllables reusing the v7 voice,
no recorded voices), a power-up grab stinger and a last-zombie heartbeat cue. Original, numpy only.
Run: python3 tools/gen_audio_v11.py"""
import numpy as np, os
src = open(os.path.join(os.path.dirname(__file__), "gen_audio_v7.py")).read().split('save("ann_round_v7"')[0]
g = {"__file__": os.path.join(os.path.dirname(__file__), "gen_audio_v7.py")}; exec(src, g)
t, ex, noise, band, save, phrase, tone, at, SR = (g[k] for k in ("t", "ex", "noise", "band", "save", "phrase", "tone", "at", "SR"))
# call-outs: short syllable shapes per drop (deep hall voice)
save("ann_pu_restock_v11",   phrase([("a", 0.24, 80, "k"), ("o", 0.22, 86, "s"), ("a", 0.5, 74, None, -0.18)]), 0.95)
save("ann_pu_onetouch_v11",  phrase([("u", 0.26, 72), ("a", 0.22, 78, "d"), ("i", 0.45, 70, "k", -0.15)]), 0.95)
save("ann_pu_doublepay_v11", phrase([("a", 0.22, 84, "d"), ("u", 0.2, 80), ("e", 0.5, 76, None, -0.15)]), 0.95)
save("ann_pu_blackout_v11",  phrase([("a", 0.28, 66, "k"), ("o", 0.6, 58, None, -0.25)], verb=0.5), 0.95)
save("ann_pu_handyman_v11",  phrase([("a", 0.22, 82), ("i", 0.2, 88, "d"), ("a", 0.48, 76, None, -0.12)]), 0.95)
# grab stinger: bright rising arpeggio + shimmer
D = 0.9; s = t(D)
arp = sum(at(tone(f, 0.5) * ex(0.5, 7), i * 0.07, D) for i, f in enumerate([392, 523.3, 659.3, 784, 1046.5]))
save("pu_grab_v11", arp * 0.6 + band(noise(D), 5000, 11000) * ex(D, 6) * 0.25, 0.8)
# last zombie: two muffled heartbeat thumps over a low drone
D = 2.4; s = t(D)
beat = lambda: tone(52, 0.25) * ex(0.25, 18) + band(noise(0.25), 30, 200) * ex(0.25, 30) * 0.6
hb = at(beat(), 0.05, D) + at(beat() * 0.7, 0.33, D) + at(beat(), 1.25, D) + at(beat() * 0.7, 1.53, D)
drone = (tone(36.7, D) + 0.4 * tone(55, D)) * np.minimum(1, s / 0.6) * np.minimum(1, (D - s) / 0.8) * 0.35
save("last_zombie_v11", hb + drone, 0.9)
print("ok")
