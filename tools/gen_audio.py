#!/usr/bin/env python3
"""Synthesises every VictorOps Zombies sound effect from scratch (numpy only).
All output is original work released with the game (no samples, no third-party audio).
Run: python3 tools/gen_audio.py  -> writes audio/*.wav"""
import numpy as np, wave, os
SR = 22050
rng = np.random.default_rng(7)
OUT = os.path.join(os.path.dirname(__file__), "..", "audio")
os.makedirs(OUT, exist_ok=True)

def t(d): return np.arange(int(SR * d)) / SR
def env(n, a=0.005, r=None):
    e = np.ones(n); ai = max(1, int(a * SR)); e[:ai] = np.linspace(0, 1, ai)
    if r: e *= np.exp(-np.arange(n) / (r * SR))
    return e
def lp(x, k):  # crude one-pole low-pass
    y = np.zeros_like(x); a = k
    for i in range(1, len(x)): y[i] = y[i-1] + a * (x[i] - y[i-1])
    return y
def save(name, x, gain=0.9):
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    d = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(d.tobytes())
def noise(d): return rng.uniform(-1, 1, int(SR * d))

def shot(d, cut, boom, name):
    n = noise(d) * env(int(SR*d), 0.001, d/5)
    body = np.sin(2*np.pi*boom*t(d) * np.exp(-t(d)*8)) * env(int(SR*d), 0.001, d/4)
    save(name, lp(n, cut) * 1.2 + body * 0.8)
shot(0.35, 0.35, 90, "shot_light")
shot(0.5, 0.2, 60, "shot_heavy")
shot(0.22, 0.5, 120, "shot_auto")
# energy weapon
x = t(0.6); save("shot_energy", np.sin(2*np.pi*(900*np.exp(-x*6)+80)*x) * env(len(x), 0.002, 0.15) + lp(noise(0.6), 0.1)*env(len(x),0.001,0.1))
# reload: two metallic clicks
def click(f): x=t(0.08); return np.sin(2*np.pi*f*x)*env(len(x),0.0005,0.01) + noise(0.08)*env(len(x),0.0005,0.006)*0.5
save("reload", np.concatenate([click(2400), np.zeros(int(SR*0.25)), click(1800), np.zeros(int(SR*0.1)), click(2600)]))
x = t(0.06); save("hitmarker", np.sin(2*np.pi*3200*x)*env(len(x),0.0005,0.015), 0.6)
# zombie groans: formant-ish detuned saws with vibrato
def groan(f0, d, name):
    x = t(d); f = f0 * (1 + 0.15*np.sin(2*np.pi*3.3*x) + 0.3*np.sin(2*np.pi*0.5*x))
    ph = np.cumsum(2*np.pi*f/SR); s = ((ph/np.pi) % 2 - 1) + 0.6*np.sin(ph*2.01)
    s = lp(s + 0.4*noise(d), 0.08) * np.sin(np.pi*x/d)**0.6
    save(name, s, 0.8)
groan(70, 1.6, "groan1"); groan(55, 2.0, "groan2"); groan(95, 1.1, "groan3")
x = t(0.5); save("zombie_attack", lp(noise(0.5), 0.25)*env(len(x),0.01,0.12) + np.sin(2*np.pi*140*x*np.exp(-x*3))*env(len(x),0.005,0.1))
x = t(0.45); save("plank_rip", lp(noise(0.45), 0.4)*env(len(x),0.002,0.08) + 0.6*np.sin(2*np.pi*180*x)*np.sign(np.sin(2*np.pi*23*x))*env(len(x),0.002,0.1))
x = t(0.3); save("plank_place", lp(noise(0.3), 0.6)*env(len(x),0.0005,0.03) + np.sin(2*np.pi*110*x)*env(len(x),0.001,0.06))
def notes(seq, dur, wave_fn, decay=0.25):
    out = []
    for f in seq:
        x = t(dur); out.append(wave_fn(f, x) * env(len(x), 0.004, decay))
    return np.concatenate(out)
sine = lambda f, x: np.sin(2*np.pi*f*x) + 0.3*np.sin(4*np.pi*f*x)
save("buy", notes([880, 1320], 0.12, sine, 0.08))
save("deny", notes([200, 150], 0.14, lambda f,x: np.sign(np.sin(2*np.pi*f*x))*0.5, 0.1), 0.5)
# music-box crate jingle (original melody)
save("crate", notes([659, 784, 988, 784, 659, 523, 587, 659, 784, 1046, 988, 784], 0.22, lambda f,x: np.sin(2*np.pi*f*x)+0.4*np.sin(2*np.pi*3*f*x), 0.3))
# round stings: low detuned minor chord swell + bell
def chord(fs, d, name, bell=None):
    x = t(d); s = sum(np.sin(2*np.pi*f*x) + 0.5*np.sin(2*np.pi*f*1.005*x) for f in fs)
    s *= np.sin(np.pi*x/d)**0.5
    if bell: s += 1.5*np.sin(2*np.pi*bell*x)*np.exp(-x*1.5)
    save(name, s)
chord([55, 65.4, 82.4, 110], 3.5, "round_start", bell=220)
chord([73.4, 92.5, 110, 146.8], 3.0, "round_end", bell=293.7)
x = t(2.5); save("power_on", lp(noise(2.5), 0.05)*np.exp(-x*4)*3 + np.sin(2*np.pi*(40+40*x)*x)*np.minimum(x,1))
x = t(1.2); save("perk", notes([392, 494, 587, 784], 0.2, sine, 0.2))
x = t(1.0); save("forge", np.sin(2*np.pi*(200+600*x)*x)*np.sin(np.pi*x) + lp(noise(1.0),0.3)*0.3*np.sin(np.pi*x))
x = t(0.7); save("door", lp(noise(0.7), 0.1)*env(len(x),0.01,0.3) + np.sin(2*np.pi*50*x)*env(len(x),0.01,0.3))
x = t(0.5); save("hurt", lp(noise(0.5), 0.15)*env(len(x),0.002,0.08) + np.sin(2*np.pi*90*x)*env(len(x),0.002,0.1))
x = t(0.9); save("bass_drop", np.sin(2*np.pi*(120*np.exp(-x*3)+30)*x)*env(len(x),0.002,0.4))
# ambient: 20 s seamless drone loop (integer cycles) with wind
d = 20.0; x = t(d)
amb = 0.6*np.sin(2*np.pi*41*x) + 0.4*np.sin(2*np.pi*61.5*x)*(0.5+0.5*np.sin(2*np.pi*0.1*x)) + 0.25*np.sin(2*np.pi*123*x)*(0.5+0.5*np.sin(2*np.pi*0.05*x))
wind = lp(noise(d), 0.02); fade = int(SR*1.0); wind[:fade] *= np.linspace(0,1,fade); wind[-fade:] *= np.linspace(1,0,fade)
save("ambient", amb + 3*wind*(0.6+0.4*np.sin(2*np.pi*0.15*x)), 0.6)
print("ok", sorted(os.listdir(OUT)))
