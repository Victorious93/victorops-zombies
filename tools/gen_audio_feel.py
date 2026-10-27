#!/usr/bin/env python3
"""Gameplay-feel pass sounds, synthesised from scratch with numpy (original work, no samples).
Run: python3 tools/gen_audio_feel.py -> writes extra audio/*.wav"""
import numpy as np, wave, os
SR = 22050
rng = np.random.default_rng(31)
OUT = os.path.join(os.path.dirname(__file__), "..", "audio")
def t(d): return np.arange(int(SR * d)) / SR
def ex(d, k): return np.exp(-t(d) * k)
def noise(d): return rng.uniform(-1, 1, int(SR * d))
def flp(x, hz):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1/SR); X[f > hz] *= 0.02; return np.fft.irfft(X, len(x))
def fhp(x, hz):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1/SR); X[f < hz] *= 0.02; return np.fft.irfft(X, len(x))
def save(name, x, gain=0.9):
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
def tone(f, d, k=4.0, h=(1, 0.4, 0.2)):
    s = t(d); return sum(a * np.sin(2*np.pi*f*(i+1)*s) for i, a in enumerate(h)) * ex(d, k)
def seq(parts):
    return np.concatenate(parts)
def vox(f0, d, vowel):
    """Wordless formant 'announcer' swell (buzzy source through vowel-ish resonances)."""
    s = t(d); src = np.sign(np.sin(2*np.pi*f0*s)) * 0.6 + np.sin(2*np.pi*f0*s)
    X = np.fft.rfft(src); f = np.fft.rfftfreq(len(src), 1/SR); g = np.zeros_like(f)
    for fc, bw in vowel: g += np.exp(-((f - fc) / bw) ** 2)
    y = np.fft.irfft(X * g, len(src)); a = np.minimum(1, s / 0.05) * np.minimum(1, (d - s) / 0.15)
    return y * a
AH = [(730, 90), (1090, 110), (2440, 160)]
OH = [(570, 80), (840, 100), (2410, 160)]
EE = [(270, 60), (2290, 150), (3010, 200)]

save("thwack", flp(noise(0.09), 1800) * ex(0.09, 45) + 0.8 * np.sin(2*np.pi*140*t(0.09)) * ex(0.09, 40))
save("headshot_pop", fhp(noise(0.12), 2500) * ex(0.12, 50) * 0.7 + np.sin(2*np.pi*(900 - 500 * t(0.12) / 0.12) * t(0.12)) * ex(0.12, 30))
save("kill_confirm", seq([tone(1320, 0.05, 40), tone(1760, 0.09, 30)]), 0.6)
save("slide", flp(noise(0.55), 1200) * np.sin(np.pi * t(0.55) / 0.55) ** 0.5)
save("tink", tone(2100, 0.1, 35, (1, 0.5)), 0.5)
save("crate_ready", seq([tone(523, 0.12, 10), tone(659, 0.12, 10), tone(1046, 0.4, 5)]), 0.7)
save("forge_done", seq([flp(noise(0.2), 900) * ex(0.2, 15), tone(196, 0.1, 8), tone(392, 0.9, 3, (1, 0.6, 0.4, 0.2))]))
save("downed", seq([tone(220, 0.25, 6), tone(185, 0.25, 6), tone(147, 1.2, 2, (1, 0.5, 0.3))]) + 0, 0.9)
save("pu_spawn", np.sin(2*np.pi*(400 + 900 * t(0.5)) * t(0.5)) * ex(0.5, 5), 0.6)
save("pu_end", seq([tone(880, 0.1, 15), tone(660, 0.1, 15), tone(440, 0.25, 8)]), 0.6)
# laughing Phantom: pitched-down 'ha' pulses with breath
ha = []
for i, f in enumerate([210, 200, 190, 175, 160, 150]):
    ha.append(vox(f, 0.16, AH) * ex(0.16, 12) + flp(noise(0.16), 3000) * 0.15 * ex(0.16, 20)); ha.append(np.zeros(int(SR * 0.05)))
save("phantom_laugh", seq(ha))
# power-up stings: a deep wordless 'announcer' swell + a signature motif each
def sting(name, f0, vowel, motif):
    v = vox(f0, 0.9, vowel)
    m = seq([tone(f, 0.16, 7) for f in motif]); m = np.pad(m, (0, max(0, len(v) - len(m))))
    v = np.pad(v, (0, max(0, len(m) - len(v))))
    save(name, v * 0.8 + m * 0.6)
sting("pu_restock", 98, AH, [392, 523, 659, 784])
sting("pu_onetouch", 82, OH, [659, 659, 988])
sting("pu_doublepay", 110, EE, [523, 1046, 523, 1046])
sting("pu_blackout", 73, OH, [196, 147, 98])
sting("pu_handyman", 104, AH, [440, 554, 440, 659])
print("ok")
