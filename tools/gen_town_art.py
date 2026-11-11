#!/usr/bin/env python3
"""Victorious Framework - generates the ORIGINAL town art for VICTOR ZOMBIES into assets/town/.

Everything here is drawn procedurally (numpy + Pillow); the only inputs are the CC0 ambientCG
albedo maps already in assets/textures (used as the wall base under the painted windows) and the
DejaVu Sans Bold font for sign lettering. Deterministic: re-running reproduces the same files.

  python3 tools/gen_town_art.py
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "town")
TEX = os.path.join(ROOT, "assets", "textures")
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
rng = np.random.default_rng(1993)


def noise(w, h, scale, seed):
    """Smooth value noise in 0..1 (bilinear-upsampled random grid, 3 octaves)."""
    r = np.random.default_rng(seed)
    acc = np.zeros((h, w), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(3):
        s = max(2, int(scale / (2 ** o)))
        g = Image.fromarray((r.random((h // s + 2, w // s + 2)) * 255).astype(np.uint8))
        acc += amp * np.asarray(g.resize((w, h), Image.BICUBIC), np.float32) / 255.0
        tot += amp
        amp *= 0.5
    return acc / tot


def font(px):
    return ImageFont.truetype(FONT, px)


def weather(img, seed, amount=0.5):
    """Grime, streaks and chipped paint over an RGB(A) sign."""
    w, h = img.size
    a = np.asarray(img.convert("RGBA"), np.float32)
    n = noise(w, h, 48, seed)
    streak = noise(w, h, 6, seed + 1)[:, :1].repeat(w, 1) if False else np.asarray(
        Image.fromarray((noise(w, 8, 10, seed + 2) * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC), np.float32) / 255.0
    dirt = np.clip((n * 0.7 + streak * 0.5) - (1.0 - amount), 0, 1)[..., None]
    a[..., :3] = a[..., :3] * (1 - dirt * 0.75) + np.array([38, 30, 22], np.float32) * dirt * 0.75
    chips = (noise(w, h, 5, seed + 3) > 0.78 - amount * 0.1)[..., None]
    a[..., :3] = np.where(chips, a[..., :3] * 0.55 + 40, a[..., :3])
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def tile(name, size):
    t = Image.open(os.path.join(TEX, name + "_albedo.jpg")).convert("RGB").resize((size // 2, size // 2), Image.LANCZOS)
    out = Image.new("RGB", (size, size))
    for y in range(2):
        for x in range(2):
            out.paste(t, (x * size // 2, y * size // 2))
    return out


# ---------------------------------------------------------------- upper-storey facades
def facade(name, base, tint, cols, rows, lit, seed, win=(0.44, 0.56), arched=False):
    """One tile = cols x rows windows. Returns albedo + emission (lit panes only)."""
    S = 512
    r = np.random.default_rng(seed)
    img = tile(base, S)
    img = Image.fromarray(np.clip(np.asarray(img, np.float32) * np.array(tint), 0, 255).astype(np.uint8))
    em = Image.new("RGB", (S, S), (0, 0, 0))
    d, de = ImageDraw.Draw(img), ImageDraw.Draw(em)
    cw, ch = S / cols, S / rows
    for j in range(rows):
        # string course under each storey
        d.rectangle([0, (j + 1) * ch - 10, S, (j + 1) * ch - 2], fill=(52, 50, 48))
        for i in range(cols):
            ww, wh = cw * win[0], ch * win[1]
            x0, y0 = i * cw + (cw - ww) / 2, j * ch + (ch - wh) / 2 - 6
            x1, y1 = x0 + ww, y0 + wh
            d.rectangle([x0 - 7, y0 - 9, x1 + 7, y0 - 1], fill=(70, 68, 64))          # lintel
            d.rectangle([x0 - 9, y1, x1 + 9, y1 + 8], fill=(86, 84, 80))               # sill
            d.rectangle([x0 - 4, y0 - 2, x1 + 4, y1], fill=(36, 34, 32))               # frame
            state = "lit" if (i, j) in lit else r.choice(["dark", "dark", "dark", "broken", "board", "curtain"])
            pane = {"dark": (12, 15, 20), "broken": (5, 6, 8), "board": (74, 55, 36), "curtain": (30, 30, 34), "lit": (96, 66, 34)}[state]
            d.rectangle([x0, y0, x1, y1], fill=pane)
            if state == "dark":   # dusk sky reflection
                for k in range(int(wh)):
                    c = int(16 * (1 - k / wh))
                    d.line([x0, y0 + k, x1, y0 + k], fill=(12 + c, 15 + c, 20 + int(c * 1.3)))
            if state == "broken":
                pts = [(x0 + r.random() * ww, y0 + r.random() * wh) for _ in range(7)]
                d.polygon(pts, fill=(20, 26, 36))
            if state == "board":
                for k in range(4):
                    yy = y0 + (k + 0.5) * wh / 4
                    d.line([x0 - 3, yy - 6 + r.integers(-5, 5), x1 + 3, yy + 6 + r.integers(-5, 5)], fill=(52, 38, 24), width=3)
            if state == "lit":
                de.rectangle([x0, y0, x1, y1], fill=(210, 138, 70))
                de.rectangle([x0, y0, x1, y0 + wh * 0.4], fill=(110, 70, 34))        # blind half down
            if state != "board":
                d.line([(x0 + x1) / 2, y0, (x0 + x1) / 2, y1], fill=(36, 34, 32), width=3)
                d.line([x0, y0 + wh * 0.45, x1, y0 + wh * 0.45], fill=(36, 34, 32), width=3)
                de.line([(x0 + x1) / 2, y0, (x0 + x1) / 2, y1], fill=(0, 0, 0), width=3)
            # soot / water stain under the sill
            for k in range(26):
                d.line([x0 + r.random() * ww, y1 + 8, x0 + r.random() * ww, y1 + 8 + r.random() * 46], fill=(30, 27, 25), width=1)
    img = weather(img, seed, 0.38).convert("RGB")
    img.save(os.path.join(OUT, name + ".png"), optimize=True)
    em.filter(ImageFilter.GaussianBlur(1.2)).save(os.path.join(OUT, name + "_emit.png"), optimize=True)


# ---------------------------------------------------------------- skyline ring
def skyline():
    W, H = 2048, 256
    r = np.random.default_rng(77)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for layer, (col, base, hmin, hmax) in enumerate([((52, 62, 80), 70, 40, 150), ((24, 29, 39), 40, 30, 120)]):
        x = 0
        while x < W:
            w = int(r.integers(26, 90)); h = int(r.integers(hmin, hmax))
            top = H - base - h
            d.rectangle([x, top, x + w, H], fill=col + (255,))
            # ruined tops: bites out of the roofline, leaning girders
            if r.random() < 0.45:
                bx = x + int(r.integers(0, max(1, w - 14)))
                d.polygon([(bx, top - 1), (bx + int(r.integers(10, 26)), top - 1), (bx + int(r.integers(4, 18)), top + int(r.integers(10, 40)))], fill=(0, 0, 0, 0))
            if r.random() < 0.3:
                d.line([x + w * 0.3, top, x + w * 0.3 + r.integers(-10, 10), top - r.integers(8, 26)], fill=col + (255,), width=2)
            if r.random() < 0.2:   # water tower / antenna
                d.rectangle([x + w * 0.6, top - 14, x + w * 0.6 + 12, top], fill=col + (255,))
            # sparse windows: mostly dead, a few survivors' lights
            for wy in range(top + 8, H - 6, 9):
                for wx in range(x + 5, x + w - 5, 8):
                    q = r.random()
                    if q < 0.012: d.rectangle([wx, wy, wx + 3, wy + 4], fill=(255, 190, 110, 255))
                    elif q < 0.16: d.rectangle([wx, wy, wx + 3, wy + 4], fill=tuple(int(c * 0.72) for c in col) + (255,))
            x += w + int(r.integers(-4, 16))
    a = np.asarray(img, np.float32)
    # fires: orange glow rising behind the near layer, and smoke columns
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    for fx in (260, 905, 1490, 1830):
        g = np.exp(-(((xx - fx) / 70.0) ** 2 + ((yy - (H - 55)) / 46.0) ** 2))
        back = a[..., 3] < 10
        a[..., 0] = np.where(back, np.maximum(a[..., 0], 255 * g), a[..., 0] + 60 * g)
        a[..., 1] = np.where(back, np.maximum(a[..., 1], 120 * g), a[..., 1] + 22 * g)
        a[..., 2] = np.where(back, np.maximum(a[..., 2], 40 * g), a[..., 2])
        a[..., 3] = np.where(back, np.maximum(a[..., 3], 230 * g), a[..., 3])
        sm = noise(W, H, 40, int(fx))
        col_w = 26 + (H - yy) * 0.42
        plume = np.exp(-(((xx - fx - (H - yy) * 0.35) / col_w) ** 2)) * np.clip((H - 40 - yy) / 60.0, 0, 1) * (0.35 + 0.65 * sm)
        plume *= np.clip(yy / 60.0, 0, 1)
        back = a[..., 3] < 40
        for c, v in enumerate((30, 31, 36)):
            a[..., c] = np.where(back, a[..., c] * (1 - plume) + v * plume, a[..., c])
        a[..., 3] = np.where(back, np.maximum(a[..., 3], 190 * plume), a[..., 3])
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "skyline.png"), optimize=True)


# ---------------------------------------------------------------- signs atlas
# 2 columns x 6 rows of 512x128 banners, then one row of four 256x256 posters. Keep in sync with
# TownKit.SIGNS (scripts/game/town_kit.gd).
BANNERS = [
    ("VICTORY DINER", (150, 24, 20), (244, 226, 190), True),
    ("OPEN 24 HRS", (20, 28, 34), (255, 120, 90), True),
    ("HOLLIS AUTO REPAIR", (28, 46, 70), (236, 214, 120), False),
    ("MERCER'S GENERAL STORE", (40, 62, 44), (232, 224, 200), False),
    ("QUARANTINE ZONE - NO ENTRY", (196, 160, 24), (18, 18, 18), False),
    ("EVACUATION POINT B  >>>", (188, 96, 22), (250, 244, 230), False),
    ("PHARMACY", (226, 226, 220), (22, 110, 70), False),
    ("HOTEL ARDEN", (60, 22, 26), (226, 196, 120), False),
    ("BARBER SHOP", (228, 224, 214), (150, 26, 30), False),
    ("ROAD CLOSED", (226, 222, 210), (190, 30, 24), False),
    ("MAIN ST", (22, 78, 48), (238, 238, 232), False),
    ("CURFEW IN EFFECT 18:00", (226, 222, 210), (20, 20, 20), False),
]
POSTERS = [
    ("EVACUATION\nNOTICE", ["ALL RESIDENTS MUST", "REPORT TO POINT B", "BRING ID + WATER", "ONE BAG PER PERSON", "DO NOT RETURN HOME"], (232, 224, 200), (150, 20, 16)),
    ("MISSING", ["LAST SEEN MAIN ST", "PLEASE CALL", "IF YOU SEE HER", "WE LOVE YOU"], (236, 232, 222), (20, 20, 20)),
    ("INFECTION\nSIGNS", ["FEVER  -  TREMORS", "GREY SKIN", "AGGRESSION", "REPORT AT ONCE", "DO NOT APPROACH"], (222, 204, 90), (20, 20, 20)),
    ("TODAY'S\nSPECIAL", ["MEATLOAF  4.95", "PIE + COFFEE  2.50", "ASK FOR ROSA"], (26, 34, 30), (236, 232, 214)),
]


def signs():
    atlas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    emit = Image.new("RGB", (1024, 1024), (0, 0, 0))
    for i, (text, bg, fg, neon) in enumerate(BANNERS):
        cell = Image.new("RGBA", (512, 128), bg + (255,))
        d = ImageDraw.Draw(cell)
        d.rectangle([5, 5, 506, 122], outline=fg + (255,), width=4)
        px = 78
        while px > 20 and d.textlength(text, font=font(px)) > 468:
            px -= 2
        f = font(px)
        tw = d.textlength(text, font=f)
        d.text(((512 - tw) / 2, (128 - px) / 2 - px * 0.12), text, font=f, fill=fg + (255,))
        if "QUARANTINE" in text or "CLOSED" in text:
            for k in range(-128, 512, 48):   # hazard chevrons along the bottom edge
                d.polygon([(k, 122), (k + 24, 122), (k + 48, 104), (k + 24, 104)], fill=(18, 18, 18, 255))
        w = weather(cell, 100 + i, 0.3 if neon else 0.55)
        x, y = (i % 2) * 512, (i // 2) * 128
        atlas.paste(w, (x, y))
        if neon:
            e = Image.new("RGB", (512, 128), (0, 0, 0))
            de = ImageDraw.Draw(e)
            de.text(((512 - tw) / 2, (128 - px) / 2 - px * 0.12), text, font=f, fill=fg)
            de.rectangle([5, 5, 506, 122], outline=fg, width=4)
            if text.startswith("VICTORY"):   # two dead letters: the sign has seen better days
                de.rectangle([(512 - tw) / 2 + tw * 0.27, 10, (512 - tw) / 2 + tw * 0.36, 118], fill=(0, 0, 0))
            emit.paste(e, (x, y))
    for i, (title, lines, bg, fg) in enumerate(POSTERS):
        cell = Image.new("RGBA", (256, 256), bg + (255,))
        d = ImageDraw.Draw(cell)
        d.rectangle([6, 6, 249, 249], outline=fg + (255,), width=3)
        yy = 16
        for t in title.split("\n"):
            f = font(36); d.text(((256 - d.textlength(t, font=f)) / 2, yy), t, font=f, fill=fg + (255,)); yy += 40
        if title == "MISSING":   # a child's-drawing style portrait box, deliberately featureless
            d.rectangle([88, yy + 2, 168, yy + 78], outline=fg + (255,), width=3)
            d.ellipse([112, yy + 14, 144, yy + 46], outline=fg + (255,), width=3)
            d.arc([100, yy + 46, 156, yy + 110], 180, 360, fill=fg + (255,), width=3)
            yy += 84
        for t in lines:
            f = font(17); d.text(((256 - d.textlength(t, font=f)) / 2, yy + 6), t, font=f, fill=fg + (255,)); yy += 25
        atlas.paste(weather(cell, 300 + i, 0.5), (i * 256, 768))
    atlas.save(os.path.join(OUT, "signs.png"), optimize=True)
    emit.filter(ImageFilter.GaussianBlur(1.0)).save(os.path.join(OUT, "signs_emit.png"), optimize=True)


# ---------------------------------------------------------------- broken glass, road paint, corrugated steel
def glass():
    S = 512
    r = np.random.default_rng(5)
    img = Image.new("RGBA", (S, S), (150, 180, 200, 46))
    d = ImageDraw.Draw(img)
    for cx, cy, rad in ((180, 300, 150), (400, 120, 80)):
        pts = []
        for k in range(14):
            ang = k / 14 * 2 * np.pi
            rr = rad * (0.55 + 0.6 * r.random())
            pts.append((cx + np.cos(ang) * rr, cy + np.sin(ang) * rr))
        d.polygon(pts, fill=(0, 0, 0, 0))
        for p in pts:   # radial cracks running out of each point of the hole
            ang = np.arctan2(p[1] - cy, p[0] - cx) + r.normal(0, 0.15)
            ln = r.integers(40, 170)
            d.line([p, (p[0] + np.cos(ang) * ln, p[1] + np.sin(ang) * ln)], fill=(225, 235, 240, 170), width=2)
        d.line(pts + [pts[0]], fill=(235, 242, 246, 200), width=3)
    a = np.asarray(img, np.float32)
    dirt = noise(S, S, 60, 9)
    a[..., 3] = np.where(a[..., 3] > 0, np.clip(a[..., 3] + dirt * 70, 0, 255), 0)
    Image.fromarray(a.astype(np.uint8), "RGBA").save(os.path.join(OUT, "glass_broken.png"), optimize=True)


def road_paint():
    S = 256
    n = noise(S, S, 14, 21) * 0.6 + noise(S, S, 4, 22) * 0.4
    a = np.zeros((S, S, 4), np.uint8)
    a[..., :3] = (206, 202, 186)
    a[..., 3] = (np.clip((n - 0.34) * 4.0, 0, 1) * 215).astype(np.uint8)
    Image.fromarray(a, "RGBA").save(os.path.join(OUT, "road_paint.png"), optimize=True)


def corrugated():
    S = 512
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    ribs = 0.5 + 0.5 * np.sin(xx / S * 2 * np.pi * 16)
    rust = np.clip((noise(S, S, 70, 31) - 0.45) * 3.2, 0, 1) * np.clip(0.35 + yy / S, 0, 1)
    scr = noise(S, S, 6, 32)
    base = np.stack([92 + ribs * 34, 104 + ribs * 34, 112 + ribs * 32], -1)
    rcol = np.stack([116 + scr * 40, 62 + scr * 22, 30 + scr * 10], -1)
    alb = base * (1 - rust[..., None]) + rcol * rust[..., None]
    alb *= (0.82 + 0.18 * scr)[..., None]
    Image.fromarray(np.clip(alb, 0, 255).astype(np.uint8), "RGB").save(os.path.join(OUT, "corrugated_albedo.png"), optimize=True)
    h = ribs * 1.0 + rust * 0.12
    dx = np.gradient(h, axis=1) * 9.0
    dy = np.gradient(h, axis=0) * 9.0
    nz = np.ones_like(dx)
    ln = np.sqrt(dx * dx + dy * dy + nz * nz)
    nrm = np.stack([(-dx / ln) * 0.5 + 0.5, (dy / ln) * 0.5 + 0.5, (nz / ln) * 0.5 + 0.5], -1)   # OpenGL (Y+) convention
    Image.fromarray((nrm * 255).astype(np.uint8), "RGB").save(os.path.join(OUT, "corrugated_normal.png"), optimize=True)


def vinyl():
    """Tufted diner-booth vinyl + a chrome-edged formica top share one small sheet (left/right halves)."""
    S = 256
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    rib = 0.5 + 0.5 * np.cos(xx / S * 2 * np.pi * 8)
    n = noise(S, S, 30, 41)
    red = np.stack([120 + rib * 46 - n * 30, 22 + rib * 10, 22 + rib * 8], -1)
    wear = (noise(S, S, 5, 42) > 0.8)[..., None]
    red = np.where(wear, red * 0.6 + 30, red)
    Image.fromarray(np.clip(red, 0, 255).astype(np.uint8), "RGB").save(os.path.join(OUT, "vinyl_red.png"), optimize=True)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    facade("facade_brick", "bricks090", (0.62, 0.56, 0.54), 4, 2, {(1, 0), (3, 1)}, 11)
    facade("facade_plaster", "paintedplaster016", (0.6, 0.6, 0.58), 4, 2, {(2, 1)}, 12, win=(0.38, 0.62))
    facade("facade_concrete", "concrete044c", (0.74, 0.76, 0.8), 6, 4, {(4, 2)}, 13, win=(0.56, 0.5))
    skyline(); signs(); glass(); road_paint(); corrugated(); vinyl()
    for f in sorted(os.listdir(OUT)):
        if f.endswith(".png"): print(f, os.path.getsize(os.path.join(OUT, f)) // 1024, "KB")
