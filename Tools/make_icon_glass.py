#!/usr/bin/env python3
"""Иконки StreamRecord из ПРОЗРАЧНОГО преломляющего стекла (SDF + нормали: преломление, дисперсия,
френель, блики, каустика). Техника та же, что в иконке «Кружок».
Использование: python3 Tools/make_icon_glass.py <папка> [номера вариантов]   -> vN.png, sheet.png"""
import os, sys
import numpy as np
from PIL import Image, ImageFilter

S = 1024
yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)

def dist(cx, cy): return np.hypot(xx - cx, yy - cy)
def blur(a, s):
    if a.ndim == 3: return np.stack([blur(a[..., k], s) for k in range(3)], -1)
    mx = a.max() > 1.5
    im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8) if mx else (np.clip(a, 0, 1) * 255).astype(np.uint8))
    r = np.asarray(im.filter(ImageFilter.GaussianBlur(s)), np.float32)
    return r if mx else r / 255
def over(base, rgb, alpha):
    a = np.clip(alpha, 0, 1)[..., None]; return base * (1 - a) + np.asarray(rgb, np.float32) * a

# ---------- SDF (отрицательный внутри)
def sd_circle(cx, cy, r): return dist(cx, cy) - r
def sd_ring(cx, cy, R, W): return np.abs(dist(cx, cy) - (R - W / 2)) - W / 2
def sd_rrect(cx, cy, hw, hh, r, rot=0.0):
    a = np.radians(rot); c, s = np.cos(a), np.sin(a)
    x = (xx - cx) * c + (yy - cy) * s; y = -(xx - cx) * s + (yy - cy) * c
    qx = np.abs(x) - (hw - r); qy = np.abs(y) - (hh - r)
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r
def sd_poly(pts, rnd=0):
    d = np.full((S, S), 1e9, np.float32); sgn = np.ones((S, S), np.float32)
    n = len(pts)
    for i in range(n):
        a = np.array(pts[i], np.float32); b = np.array(pts[(i + 1) % n], np.float32)
        e = b - a; px = xx - a[0]; py = yy - a[1]
        t = np.clip((px * e[0] + py * e[1]) / (e @ e), 0, 1)
        d = np.minimum(d, np.hypot(px - e[0] * t, py - e[1] * t))
        j = pts[(i + 1) % n]; k = pts[i]
        c1 = yy >= k[1]; c2 = yy < j[1]; c3 = e[0] * py > e[1] * px
        flip = (c1 & c2 & c3) | (~c1 & ~c2 & ~c3)
        sgn = np.where(flip, -sgn, sgn)
    return d * sgn - rnd

# ---------- подложка
def backdrop(base, top, blobs):
    t = np.clip(dist(S * 0.30, S * 0.12) / (S * 1.15), 0, 1)[..., None]
    bg = np.array(top, np.float32) * (1 - t) + np.array(base, np.float32) * t
    for (x, y, r, col, a) in blobs:
        bg = over(bg, col, blur(np.clip(r * 1.3 - dist(x * S, y * S) + 0.5, 0, 1) * 255 / 255, S * 0.07) * a)
    return bg

# ---------- стекло
def glass(img, sdf, k=1.0, L=115, blurpx=3, lift=14, tint=None, tint_a=0.0, rainbow=0.75, spec=1.0):
    m = np.clip(0.5 - sdf, 0, 1); d = np.clip(-sdf, 0, None)
    gy, gx = np.gradient(sdf); n = np.hypot(gx, gy) + 1e-6; nx, ny = gx / n, gy / n
    sh = blur(np.clip(0.5 - sdf, 0, 1) * 255, 28 * k + 6) / 255
    shy = np.roll(sh, int(26 * k + 4), axis=0)
    img = img * (1 - 0.55 * shy[..., None] * (1 - m[..., None]))
    L = L * k
    lens = np.clip(1 - d / L, 0, 1) ** 1.8
    frost = blur(img, blurpx)
    def samp(src, kk):
        sx = np.clip(xx + nx * lens * kk * k, 0, S - 1).astype(np.int32); sy = np.clip(yy + ny * lens * kk * k, 0, S - 1).astype(np.int32)
        return src[sy, sx]
    core = np.zeros_like(img)
    for ch, kk in enumerate([75, 88, 102]): core[..., ch] = samp(frost[..., ch], kk)
    tone = np.clip(1 - (yy - 80) / (S - 160), 0, 1)
    core = core * 0.96 + (lift * 0.5 + lift * 0.8 * tone)[..., None]
    if tint is not None: core = core * (1 - tint_a) + np.asarray(tint, np.float32) * tint_a
    img = img * (1 - m[..., None]) + core * m[..., None]
    ang = np.degrees(np.arctan2(ny, nx))
    def wrapw(a0, w, p=1.2): return np.clip(1 - np.abs((ang - a0 + 180) % 360 - 180) / w, 0, 1) ** p
    band = np.clip(1 - d / (75 * k), 0, 1) ** 2.6
    img = over(img, (240, 244, 252), m * band * 0.36 * spec)
    edge = np.clip(1 - np.abs(d - 3.5 * k) / (3.5 * k), 0, 1)
    img = over(img, (255, 255, 255), m * edge * (0.22 + 0.60 * wrapw(-130, 100)) * spec)
    d2 = np.clip(1 - np.abs(d - 17 * k) / (13 * k), 0, 1)
    img = over(img, (255, 255, 255), m * d2 * wrapw(-125, 70, 1.0) * 0.85 * spec)
    stops = [(0, (255, 170, 110)), (0.25, (255, 120, 190)), (0.5, (160, 130, 255)), (0.75, (90, 190, 255)), (1, (120, 240, 210))]
    u = np.clip((ang - 10) / 110, 0, 1)
    rb = np.stack([np.interp(u, [s_[0] for s_ in stops], [s_[1][c] for s_ in stops]) for c in range(3)], -1)
    cau = np.clip(1 - np.abs(d - 15 * k) / (10 * k), 0, 1) * wrapw(55, 70, 0.9)
    img = over(img, rb, m * cau * rainbow * spec)
    return img

def ball(img, cx, cy, r, col=(236, 48, 70)):
    """Глянцевый цветной шарик (красная точка REC)."""
    bm = np.clip(r - dist(cx, cy) + 0.5, 0, 1)
    sh = blur(np.roll(bm, int(r * 0.12), axis=0) * 255, r * 0.15) / 255
    img = img * (1 - 0.5 * sh[..., None] * (1 - bm[..., None]))
    t = np.clip(dist(cx - r * 0.25, cy - r * 0.35) / (r * 1.3), 0, 1)[..., None]
    body = np.array([min(255, col[0] + 40), min(255, col[1] + 60), min(255, col[2] + 60)], np.float32) * (1 - t) + np.array(col, np.float32) * 0.8 * t
    img = over(img, body, bm)
    hl = np.clip(1 - dist(cx - r * 0.2, cy - r * 0.45) / (r * 0.5), 0, 1) ** 1.5
    return over(img, (255, 255, 255), hl * bm * 0.7)

def squircle_mask():
    r = 0.2237 * S * 0.89
    return np.clip(0.5 - sd_rrect(S / 2, S / 2, S * 0.445, S * 0.445, r), 0, 1)

NEUTRAL = ([8, 8, 10], [70, 70, 78], [(0.06, 0.2, 130, (235, 238, 248), 0.40), (0.95, 0.75, 150, (235, 238, 248), 0.34), (0.5, 0.98, 120, (235, 238, 248), 0.32), (0.9, 0.08, 100, (235, 238, 248), 0.28)])
COLD = ([6, 8, 20], [20, 30, 70], [(0.15, 0.2, 170, (60, 120, 255), 0.75), (0.9, 0.8, 190, (255, 60, 160), 0.65), (0.55, 0.95, 120, (140, 90, 255), 0.5), (0.9, 0.1, 110, (60, 200, 255), 0.45)])
WARM = ([14, 6, 8], [60, 28, 26], [(0.12, 0.2, 170, (255, 140, 30), 0.75), (0.92, 0.75, 190, (255, 50, 110), 0.65), (0.5, 0.98, 120, (170, 60, 255), 0.5), (0.9, 0.1, 100, (255, 200, 80), 0.4)])

def render(v):
    cfg = {1: NEUTRAL, 2: COLD, 3: NEUTRAL, 4: COLD, 5: NEUTRAL, 6: WARM}[v]
    img = backdrop(*cfg)
    c0 = S / 2
    plate = sd_rrect(c0, c0, S * 0.425, S * 0.425, S * 0.245)
    img = glass(img, plate, k=1.0, L=115, blurpx=4)
    if v == 1:   # стеклянное кольцо + красная точка
        img = glass(img, sd_ring(c0, c0, 300, 78), k=0.55, L=115, blurpx=2)
        img = ball(img, c0, c0, 70)
    elif v == 2:  # большой стеклянный шар-линза
        img = glass(img, sd_circle(c0, c0, 285), k=1.0, L=260, blurpx=2)
    elif v == 3:  # стеклянная хлопушка
        img = glass(img, sd_rrect(c0, c0 + 105, 265, 165, 40), k=0.8, L=130, blurpx=2)
        img = glass(img, sd_rrect(c0 + 5, c0 - 150, 265, 50, 28, rot=-8), k=0.55, L=100, blurpx=2)
    elif v == 4:  # стеклянная видеокамера
        img = glass(img, sd_rrect(c0 - 70, c0, 215, 165, 70), k=0.85, L=130, blurpx=2)
        img = glass(img, sd_poly([(c0 + 170, c0), (c0 + 330, c0 - 120), (c0 + 330, c0 + 120)], rnd=22), k=0.7, L=100, blurpx=2)
        img = ball(img, c0 - 190, c0 - 95, 26)
    elif v == 5:  # кнопка записи: кольцо + красное стекло
        img = glass(img, sd_ring(c0, c0, 320, 50), k=0.45, L=100, blurpx=2)
        img = glass(img, sd_circle(c0, c0, 190), k=0.9, L=190, blurpx=2, tint=(235, 40, 60), tint_a=0.55, rainbow=0.4)
    else:         # тёплый: кольцо + красная точка на тёплой подложке
        img = glass(img, sd_ring(c0, c0, 300, 78), k=0.55, L=115, blurpx=2)
        img = ball(img, c0, c0, 70)
    out = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).convert("RGBA")
    a = (squircle_mask() * 255).astype(np.uint8)
    out.putalpha(Image.fromarray(a))
    return out

if __name__ == "__main__":
    out = sys.argv[1]; os.makedirs(out, exist_ok=True)
    vs = [int(x) for x in sys.argv[2:]] or list(range(1, 7))
    for v in vs: render(v).save(os.path.join(out, f"v{v}.png"))
    sheet = Image.new("RGBA", (1560, 1040), (96, 100, 110, 255))
    for v in range(1, 7):
        p = os.path.join(out, f"v{v}.png")
        if os.path.exists(p):
            sheet.alpha_composite(Image.open(p).resize((500, 500), Image.LANCZOS), (20 + ((v - 1) % 3) * 520, 20 + ((v - 1) // 3) * 520))
    sheet.save(os.path.join(out, "sheet.png"))
