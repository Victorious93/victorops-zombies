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

# ---------------------------------------------------------------- v2 overhaul (all original synthesis)
def flp(x, hz):  # FFT brick-ish low-pass (fast for long buffers)
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1/SR); X *= 1/(1+(f/hz)**4); return np.fft.irfft(X, len(x))
def fhp(x, hz):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1/SR); X *= 1-1/(1+(f/hz)**4); return np.fft.irfft(X, len(x))
def tail(x, d=0.35, decay=0.12):  # short concrete-room tail (sparse echoes)
    out = np.concatenate([x, np.zeros(int(SR*d))])
    for k, delay in enumerate([0.023, 0.041, 0.067, 0.089, 0.131, 0.177]):
        i = int(SR*delay); out[i:i+len(x)] += x * 0.45 * np.exp(-delay/decay) * (-1)**k
    return flp(out, 3500)
def layered(name, d, crack_hz, boom, thump, mech_f, gain=0.95):
    n = int(SR*d); x = t(d)
    crack = fhp(noise(d), crack_hz) * env(n, 0.0003, 0.012)          # supersonic-ish transient
    body = flp(noise(d), 1800) * env(n, 0.001, d/6)                   # powder body
    sub = np.sin(2*np.pi*boom*x*np.exp(-x*10)) * env(n, 0.001, d/5) * thump
    mech = np.zeros(n); m = t(0.03); mech[:len(m)] = np.sin(2*np.pi*mech_f*m)*env(len(m), 0.0003, 0.006)*0.4
    save(name, tail(crack*0.8 + body + sub + mech), gain)
layered("shot_pistol", 0.3, 2500, 110, 0.9, 3100)
layered("shot_smg", 0.2, 3000, 130, 0.6, 3600)
layered("shot_shotgun", 0.55, 1500, 55, 1.6, 1900)
layered("shot_rifle", 0.32, 2200, 85, 1.1, 2800)
layered("shot_lmg", 0.36, 1800, 70, 1.3, 2300)
layered("shot_launcher", 0.5, 900, 45, 1.8, 1200)
x = t(0.7); zap = np.sin(2*np.pi*np.cumsum(300+1400*np.exp(-x*9)+60*np.sin(2*np.pi*37*x))/SR) * env(len(x), 0.001, 0.18)
save("shot_nova", tail(zap + 0.5*np.sin(2*np.pi*55*x)*env(len(x),0.002,0.25) + 0.2*fhp(noise(0.7),4000)*env(len(x),0.001,0.05)))
def tink(f, d=0.12): x=t(d); return (np.sin(2*np.pi*f*x)+0.5*np.sin(2*np.pi*f*2.76*x))*env(len(x),0.0002,0.025)
save("shell1", np.concatenate([tink(4200), np.zeros(int(SR*0.06)), tink(3900)*0.5, np.zeros(int(SR*0.04)), tink(4100)*0.25]), 0.5)
save("shell2", np.concatenate([tink(3600), np.zeros(int(SR*0.08)), tink(3400)*0.4]), 0.5)
x = t(0.12); save("mag_out", tink(900, 0.06).tolist() and np.concatenate([tink(900, 0.06), flp(noise(0.06),2000)*env(int(SR*0.06),0.001,0.02)]), 0.7)
save("mag_in", np.concatenate([flp(noise(0.03),3000)*env(int(SR*0.03),0.001,0.01), tink(1400, 0.08), tink(2200, 0.05)]), 0.8)
save("bolt", np.concatenate([tink(1800, 0.05), np.zeros(int(SR*0.07)), tink(2600, 0.06), flp(noise(0.05),2500)*env(int(SR*0.05),0.001,0.015)]), 0.8)
x = t(0.25); save("knife_swing", fhp(noise(0.25), 1500) * np.sin(np.pi*x/0.25)**2 * 0.8, 0.6)
x = t(0.3); save("knife_hit", flp(noise(0.3), 600)*env(len(x),0.001,0.05) + np.sin(2*np.pi*95*x)*env(len(x),0.001,0.06), 0.85)
x = t(0.2); save("grenade_bounce", tink(700, 0.2)*0.8 + flp(noise(0.2),1200)*env(len(x),0.001,0.02), 0.6)
x = t(1.6); save("explosion", tail(flp(noise(1.6), 900)*env(len(x),0.002,0.35) + 1.5*np.sin(2*np.pi*38*x*np.exp(-x*2))*env(len(x),0.002,0.4) + fhp(noise(1.6),3000)*env(len(x),0.0005,0.02), 0.5, 0.2))
x = t(0.35); save("gore", flp(noise(0.35), 500)*env(len(x),0.002,0.06) + 0.5*np.sin(2*np.pi*70*x)*env(len(x),0.002,0.05), 0.8)
for i, (f, c) in enumerate([(85, 900), (70, 700), (100, 1100)]):
    x = t(0.18); save("step%d" % (i+1), flp(noise(0.18), c)*env(len(x),0.002,0.03) + 0.6*np.sin(2*np.pi*f*x)*env(len(x),0.002,0.03), 0.6)
x = t(0.22); save("drag", flp(noise(0.22), 500) * np.sin(np.pi*x/0.22), 0.5)
# round-change sting: original cluster swell + timpani-like hits + rising tone
d = 3.2; x = t(d)
sw = sum(np.sin(2*np.pi*f*x + 0.3*np.sin(2*np.pi*5*x)) for f in [49, 58.3, 73.4, 77.8]) * np.minimum(x/1.2, 1) * np.exp(-np.maximum(x-1.6, 0)*2)
hits = np.zeros(len(x))
for k, at in enumerate([0.0, 0.42, 0.84]):
    i = int(SR*at); h = t(0.6); hits[i:i+len(h)] += np.sin(2*np.pi*(65-k*4)*h*np.exp(-h*1.5))*env(len(h),0.001,0.18)
rise = np.sin(2*np.pi*np.cumsum(330+220*x/d)/SR)*0.25*np.sin(np.pi*x/d)**2
save("sting", tail(sw*0.5 + hits*1.4 + rise, 0.6, 0.3))
x = t(1.0); save("egg_fuse", sum(np.sin(2*np.pi*f*x)*np.exp(-x*3) for f in [523.3, 784, 1174.7]) + 0.3*np.sin(2*np.pi*55*x)*np.exp(-x*2), 0.7)
x = t(3.0); save("egg_complete", sum(np.sin(2*np.pi*f*x + 2*np.sin(2*np.pi*0.7*x))*np.exp(-x*0.9) for f in [110, 164.8, 220, 329.6, 440]) + flp(noise(3.0),300)*np.exp(-x*1.5), 0.8)
x = t(2.0); save("crate_move", np.sin(2*np.pi*np.cumsum(600*np.exp(-x*1.5)+40)/SR)*env(len(x),0.01,0.8) + flp(noise(2.0),800)*np.exp(-x*2)*0.6, 0.8)
x = t(1.6); save("forge_hum", (np.sin(2*np.pi*60*x) + 0.5*np.sin(2*np.pi*120.5*x) + 0.25*np.sin(2*np.pi*181*x)) * (0.7+0.3*np.sin(2*np.pi*1.25*x)), 0.5)
# ---------------------------------------------------------------- original music loop: "Annex Night"
# 90 bpm, 16 bars of 4/4 = 42.667 s; D minor-ish pulse, pad, sparse bell motif. Fully synthesised here.
bpm = 90; beat = 60/bpm; bars = 16; L = int(SR*beat*4*bars); x = np.arange(L)/SR
roots = [73.42, 73.42, 58.27, 58.27, 65.41, 65.41, 55.0, 61.74] * 2   # D, D, Bb, Bb, C, C, A, B
music = np.zeros(L)
pad = np.zeros(L)
for b, r in enumerate(roots):
    i0 = int(SR*beat*4*b); i1 = int(SR*beat*4*(b+1)); seg = x[i0:i1] - x[i0]
    ch = sum(np.sin(2*np.pi*f*seg) + 0.4*np.sin(2*np.pi*f*1.004*seg) for f in [r*2, r*3, r*2*1.19 if b % 8 != 6 else r*2*1.26])
    fade = np.minimum(1, np.minimum(seg/0.4, (seg[-1]-seg+1e-3)/0.4))
    pad[i0:i1] = ch * fade
    for e in range(8):  # eighth-note bass pulse
        j = i0 + int(SR*beat/2*e); n = int(SR*beat/2*0.9); s2 = np.arange(n)/SR
        music[j:j+n] += np.sin(2*np.pi*r*s2) * np.exp(-s2*7) * (1.0 if e % 2 == 0 else 0.6)
music = music*0.9 + flp(pad, 1200)*0.18
motif = [0, None, 3, None, 7, 5, None, 3, 2, None, None, 0, None, None, None, None]
for b in range(bars):
    if b % 4 not in (1, 3): continue
    for k, st in enumerate(motif):
        if st is None: continue
        j = int(SR*beat*4*b + SR*beat/4*k*2); n = int(SR*1.2); s2 = np.arange(n)/SR
        f = 587.33 * 2**(st/12)
        if j+n <= L: music[j:j+n] += 0.35*(np.sin(2*np.pi*f*s2)+0.3*np.sin(2*np.pi*f*2.01*s2))*np.exp(-s2*3)
for b in range(bars):  # soft kick on 1 and 3 from bar 4
    if b < 4: continue
    for q in (0, 2):
        j = int(SR*beat*(4*b+q)); n = int(SR*0.3); s2 = np.arange(n)/SR
        music[j:j+n] += 0.9*np.sin(2*np.pi*(50+80*np.exp(-s2*30))*s2)*np.exp(-s2*12)
music += flp(noise(L/SR), 400)*0.08
save("music", music, 0.7)

print("ok", sorted(os.listdir(OUT)))
