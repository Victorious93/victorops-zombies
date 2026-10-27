#!/usr/bin/env python3
"""Single-player polish v4 sounds, synthesised from scratch with numpy (original work, no samples).
Run: python3 tools/gen_audio_v4.py -> writes extra audio/*.wav"""
import numpy as np, wave, os
SR = 22050
rng = np.random.default_rng(404)
OUT = os.path.join(os.path.dirname(__file__), "..", "audio")
def t(d): return np.arange(int(SR * d)) / SR
def ex(d, k): return np.exp(-t(d) * k)
def noise(d): return rng.uniform(-1, 1, int(SR * d))
def band(x, lo, hi):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1/SR); X[(f < lo) | (f > hi)] *= 0.02; return np.fft.irfft(X, len(x))
def save(name, x, gain=0.9):
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
def growl(f0, d, formants, wobble=6.0, rough=0.5):
    s = t(d)
    f = f0 * (1 + 0.08 * np.sin(2*np.pi*wobble*s) + 0.05 * rng.standard_normal(len(s)).cumsum() / np.sqrt(len(s)))
    ph = 2*np.pi*np.cumsum(f) / SR
    src = np.sign(np.sin(ph)) * 0.5 + np.sin(ph) + rough * rng.uniform(-1, 1, len(s))
    X = np.fft.rfft(src); fr = np.fft.rfftfreq(len(src), 1/SR); g = np.zeros_like(fr)
    for fc, bw in formants: g += np.exp(-((fr - fc) / bw) ** 2)
    y = np.fft.irfft(X * g, len(src))
    a = np.minimum(1, s / 0.12) * np.minimum(1, (d - s) / 0.3)
    return y * a
# two more zombie voices (the game now gives every zombie its own voice + pitch)
save("groan4", growl(62, 1.6, [(500, 120), (900, 150), (2300, 300)], 3.5, 0.7))
save("groan5", growl(95, 1.2, [(650, 100), (1100, 140), (2600, 250)], 9.0, 0.4))
# lunge screech: rising rough shriek
s = t(0.6); f = 300 + 500 * np.minimum(1, s / 0.25)
save("screech", band(np.sign(np.sin(2*np.pi*np.cumsum(f)/SR)) + 0.8 * noise(0.6), 600, 4200) * np.minimum(1, s / 0.04) * ex(0.6, 4), 0.8)
save("swipe_miss", band(noise(0.25), 400, 2500) * np.sin(np.pi * t(0.25) / 0.25) ** 2, 0.6)
save("dirt_rise", band(noise(1.0), 80, 1200) * (0.4 + 0.6 * np.abs(np.sin(2*np.pi*3*t(1.0)))) * ex(1.0, 2.5))
save("land_thud", band(noise(0.3), 30, 400) * ex(0.3, 18) + np.sin(2*np.pi*55*t(0.3)) * ex(0.3, 14))
# heartbeat (lub-dub) for low health
def thump(f, d, k): return np.sin(2*np.pi*f*t(d)) * ex(d, k)
hb = np.concatenate([thump(48, 0.14, 30), np.zeros(int(SR*0.08)), thump(40, 0.16, 26) * 0.7, np.zeros(int(SR*0.5))])
save("heartbeat", hb)
# layered reload: mag release click, cloth/handling rustle, rack
save("mag_release", band(noise(0.05), 2000, 7000) * ex(0.05, 90) + np.sin(2*np.pi*1800*t(0.05)) * ex(0.05, 70) * 0.5, 0.7)
save("reload_cloth", band(noise(0.3), 300, 2500) * np.sin(np.pi * t(0.3) / 0.3), 0.4)
save("rack", np.concatenate([band(noise(0.06), 1500, 6000) * ex(0.06, 60), np.zeros(int(SR*0.07)), band(noise(0.09), 900, 5000) * ex(0.09, 45) + np.sin(2*np.pi*700*t(0.09)) * ex(0.09, 50) * 0.6]))
# low thump layer under every first/heavy shot
save("shot_punch", np.sin(2*np.pi*(90 - 40*t(0.18)/0.18)*t(0.18)) * ex(0.18, 22) + band(noise(0.18), 40, 300) * ex(0.18, 30) * 0.6)
print("ok")
