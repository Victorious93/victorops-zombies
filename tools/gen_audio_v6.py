#!/usr/bin/env python3
"""v6 sounds (gunfeel impacts/reloads, barricade, doors, atmospheric round stings), synthesised
from scratch with numpy (original work, no samples). Run: python3 tools/gen_audio_v6.py"""
import numpy as np, os, importlib.util
spec = importlib.util.spec_from_file_location("v4", os.path.join(os.path.dirname(__file__), "gen_audio_v4.py"))
src = open(spec.origin).read().split("# two more zombie voices")[0]
g = {"__file__": spec.origin}; exec(src, g)
t, ex, noise, band, save = g["t"], g["ex"], g["noise"], g["band"], g["save"]
rng = np.random.default_rng(606); SR = g["SR"]
def tone(f, d): return np.sin(2*np.pi*f*t(d))
def at(x, off, total):
    out = np.zeros(int(SR*total)); i = int(SR*off); n = min(len(x), len(out)-i); out[i:i+n] += x[:n]; return out
# --- gunfeel ---
save("impact_flesh", band(noise(0.18), 120, 1800) * ex(0.18, 26) + tone(85, 0.18) * ex(0.18, 30) * 0.8, 0.8)
save("impact_metal", tone(1850, 0.4)*ex(0.4, 9)*0.5 + tone(2630, 0.4)*ex(0.4, 12)*0.35 + band(noise(0.4), 2000, 9000)*ex(0.4, 40), 0.7)
save("impact_wall", band(noise(0.22), 300, 5000) * ex(0.22, 30) + band(noise(0.22), 60, 300) * ex(0.22, 18) * 0.6, 0.6)
d = 0.55; s = t(d)
save("ricochet", np.sin(2*np.pi*np.cumsum(3800 - 2600*s/d)/SR) * ex(d, 5) * 0.6 + band(noise(d), 3000, 9000)*ex(d, 50)*0.5, 0.5)
click = lambda f, k: band(noise(0.06), f, f*4) * ex(0.06, k)
save("mag_out_v6", at(click(1200, 70), 0, 0.35) + at(band(noise(0.25), 400, 2500)*ex(0.25, 14)*0.5, 0.04, 0.35), 0.8)
save("mag_in_v6", at(click(900, 60)*0.6, 0, 0.3) + at(click(1500, 90) + tone(160, 0.06)*ex(0.06, 40), 0.12, 0.3), 0.9)
save("bolt_v6", at(click(2000, 80), 0, 0.4) + at(band(noise(0.1), 600, 3500)*ex(0.1, 30), 0.08, 0.4) + at(click(1300, 90)*1.2 + tone(120, 0.06)*ex(0.06, 30), 0.22, 0.4), 0.9)
save("hit_tick_v6", tone(3200, 0.04)*ex(0.04, 120) + tone(1600, 0.04)*ex(0.04, 90)*0.5, 0.4)
# --- barricade / climb / door ---
creak = np.sin(2*np.pi*np.cumsum(180 + 120*np.sin(2*np.pi*7*t(0.5)))/SR) * band(noise(0.5), 150, 1200) * 2
save("plank_pull_v6", at(creak*ex(0.5, 3)*0.6, 0, 0.8) + at(band(noise(0.3), 200, 4000)*ex(0.3, 12), 0.45, 0.8), 0.8)
save("climb_v6", at(band(noise(0.3), 100, 900)*ex(0.3, 10), 0, 0.7) + at(tone(55, 0.3)*ex(0.3, 14) + band(noise(0.3), 60, 500)*ex(0.3, 20), 0.4, 0.7), 0.8)
dr = 2.2; s = t(dr)
rumble = band(noise(dr), 25, 180) * np.sin(np.pi*s/dr) + tone(40, dr)*np.sin(np.pi*s/dr)*0.5
chain = sum(at(band(noise(0.04), 2500, 7000)*ex(0.04, 70), o, dr) for o in np.arange(0.1, 1.6, 0.09) + rng.uniform(0, 0.03, 17))
save("door_open_v6", rumble + chain*0.35 + at(tone(50, 0.6)*ex(0.6, 8) + band(noise(0.6), 40, 400)*ex(0.6, 10), 1.6, dr), 0.85)
# --- atmospheric stings: low drone + tolling bell + breathy pad (round start); falling pad + bell (round end) ---
def bell(f, d, k=1.6):
    s = t(d); return sum(a*np.sin(2*np.pi*f*m*s)*np.exp(-s*k*(1+m*0.4)) for m, a in [(1, 1), (2.0, .5), (2.76, .35), (5.4, .2), (0.5, .4)])
def pad(fs, d, breath=0.25):
    s = t(d); v = sum(np.sin(2*np.pi*f*s + 0.3*np.sin(2*np.pi*5.1*s)) + 0.4*np.sin(2*np.pi*f*2.003*s) for f in fs)
    return v / len(fs) + band(noise(d), 300, 2500) * breath
D = 6.0; s = t(D); env = np.minimum(1, s/1.2) * np.minimum(1, (D - s)/1.8)
drone = (tone(55, D) + 0.6*tone(55*1.498, D) + 0.3*tone(27.5, D)) * env * 0.5
toll = at(bell(110, 3.5), 0.3, D) + at(bell(110, 3.5), 2.1, D) * 0.8 + at(bell(103.8, 3.0), 3.9, D) * 0.7
choir = pad([220, 261.6, 329.6], D) * env * 0.35
save("round_start_v6", drone + toll*0.7 + choir, 0.9)
D = 5.0; s = t(D); env = np.minimum(1, s/0.6) * np.exp(-s*0.5)
fall = sum(np.sin(2*np.pi*np.cumsum(f*(1 - 0.06*s/D))/SR) for f in [196, 233, 293.7]) / 3 * env * 0.6
save("round_end_v6", fall + at(bell(146.8, 4.0, 1.2), 0.05, D)*0.6 + band(noise(D), 200, 1500)*env*0.15 + tone(49, D)*env*0.4, 0.85)
print("ok")
