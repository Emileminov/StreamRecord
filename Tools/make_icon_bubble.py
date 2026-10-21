#!/usr/bin/env python3
"""Иконка StreamRecord в стиле Duo Cam: тёмный фон, стеклянные пузыри с радужной кромкой, цветной значок внутри.
Использование: python3 Tools/make_icon_bubble.py <папка> [варианты 1-3]   -> vN.png (+ sheet.png)"""
import os, sys
import numpy as np
from PIL import Image, ImageFilter

S = 1024
yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
def dist(cx, cy): return np.hypot(xx - cx, yy - cy)
def blur(a, s):
    if a.ndim == 3: return np.stack([blur(a[..., k], s) for k in range(3)], -1)
    return np.asarray(Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(s)), np.float32) / 255
def over(base, rgb, alpha):
    a = np.clip(alpha, 0, 1)[..., None]; return base * (1 - a) + np.asarray(rgb, np.float32) * a
def cov(sdf): return np.clip(0.5 - sdf, 0, 1)

def sd_rrect(cx, cy, hw, hh, r, rot=0.0):
    a = np.radians(rot); c, s = np.cos(a), np.sin(a)
    x = (xx - cx) * c + (yy - cy) * s; y = -(xx - cx) * s + (yy - cy) * c
    qx = np.abs(x) - (hw - r); qy = np.abs(y) - (hh - r)
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r
def sd_poly(pts, rnd=0):
    d = np.full((S, S), 1e9, np.float32); sgn = np.ones((S, S), np.float32); n = len(pts)
    for i in range(n):
        a = np.array(pts[i], np.float32); b = np.array(pts[(i + 1) % n], np.float32); e = b - a
        px = xx - a[0]; py = yy - a[1]
        t = np.clip((px * e[0] + py * e[1]) / (e @ e), 0, 1)
        d = np.minimum(d, np.hypot(px - e[0] * t, py - e[1] * t))
        c1 = yy >= pts[i][1]; c2 = yy < pts[(i + 1) % n][1]; c3 = e[0] * py > e[1] * px
        sgn = np.where((c1 & c2 & c3) | (~c1 & ~c2 & ~c3), -sgn, sgn)
    return d * sgn - rnd

STOPS = [(0, (255, 150, 0)), (0.25, (255, 85, 110)), (0.5, (165, 95, 255)), (0.75, (70, 150, 255)), (1, (255, 150, 0))]
def rainbow(cx, cy):
    u = (np.arctan2(yy - cy, xx - cx) + np.pi) / (2 * np.pi)
    return np.stack([np.interp(u, [s[0] for s in STOPS], [s[1][k] for s in STOPS]) for k in range(3)], -1)

def glyph(img, sdf, cx, cy):
    """Цветной значок с радужной заливкой и мягким свечением."""
    col = rainbow(cx, cy); m = cov(sdf)
    img = over(img, col, blur(m, 28) * 0.45)
    img = over(img, col, m)
    top = np.clip(1 - (yy - (cy - 220)) / 440, 0, 1)
    return over(img, (255, 255, 255), m * top * 0.10)

def bubble(img, cx, cy, R, spec=1.0):
    """Стеклянный пузырь: прозрачная середина, радужная кромка (френель), блики."""
    d = dist(cx, cy); m = cov(d - R)
    rn = np.clip(d / R, 0, 1)
    ang = np.degrees(np.arctan2(yy - cy, xx - cx))
    def wrapw(a0, w, p=1.0): return np.clip(1 - np.abs((ang - a0 + 180) % 360 - 180) / w, 0, 1) ** p
    # тень под пузырём
    sh = blur(np.roll(cov(d - R), int(R * 0.08), axis=0), R * 0.09)
    img = img * (1 - 0.45 * sh[..., None] * (1 - m[..., None]))
    # лёгкое осветление «воздуха» внутри + затемнение к краю
    img = over(img, (120, 120, 150), m * 0.06)
    # радужная кромка: цвет зависит от угла
    pal = [(-180, (120, 200, 190)), (-135, (150, 205, 235)), (-60, (150, 170, 230)), (20, (190, 150, 225)), (80, (140, 200, 170)), (125, (235, 175, 140)), (180, (120, 200, 190))]
    rim = np.stack([np.interp(ang, [p[0] for p in pal], [p[1][k] for p in pal]) for k in range(3)], -1)
    fres = np.clip((rn - 0.80) / 0.20, 0, 1) ** 1.7
    img = over(img, rim, m * fres * 0.78 * spec)
    # тонкая яркая внешняя линия
    edge = np.clip(1 - np.abs(d - (R - 2.5)) / 3.0, 0, 1)
    img = over(img, (255, 255, 255), m * edge * (0.35 + 0.5 * wrapw(-135, 110)) * spec)
    # широкий белый блик сверху-слева (внутри кромки)
    band = np.clip(1 - np.abs(d - R * 0.86) / (R * 0.09), 0, 1)
    img = over(img, (255, 255, 255), blur(m * band * wrapw(-138, 55, 1.4), 3) * 0.85 * spec)
    # нижний тёплый отсвет
    band2 = np.clip(1 - np.abs(d - R * 0.90) / (R * 0.07), 0, 1)
    img = over(img, (255, 205, 170), m * band2 * wrapw(110, 60, 1.2) * 0.55 * spec)
    # маленький овальный блик
    hx, hy = cx - R * 0.62, cy - R * 0.62
    ov = np.clip(1 - np.hypot((xx - hx) / (R * 0.15), (yy - hy) / (R * 0.065)), 0, 1) ** 0.8
    img = over(img, (255, 255, 255), m * ov * 0.9 * spec)
    return img

def background():
    t = np.clip(dist(S * 0.35, S * 0.12) / (S * 1.2), 0, 1)[..., None]
    return np.array([54, 54, 62], np.float32) * (1 - t) + np.array([12, 12, 16], np.float32) * t

def red_dot(img, cx, cy, r):
    m = cov(dist(cx, cy) - r)
    img = over(img, (255, 60, 70), blur(m, r * 0.5) * 0.5)
    return over(img, (255, 72, 82), m)

def render(v):
    img = background(); c0 = S / 2
    if v == 1:    # play-треугольник
        img = glyph(img, sd_poly([(c0 - 90, c0 - 150), (c0 - 90, c0 + 150), (c0 + 170, c0)], rnd=34), c0, c0)
    elif v == 2:  # хлопушка
        img = glyph(img, sd_rrect(c0, c0 + 70, 170, 110, 26), c0, c0)
        img = glyph(img, sd_rrect(c0 + 4, c0 - 100, 170, 34, 18, rot=-9), c0, c0)
    else:         # объектив-диафрагма: кольцо + точка
        d = dist(c0, c0)
        img = glyph(img, np.abs(d - 150) - 38, c0, c0)
        img = glyph(img, d - 52, c0, c0)
    img = bubble(img, c0, c0, 385)
    if v != 3:
        sx, sy, sr = 782, 782, 168
        img = red_dot(img, sx, sy, 36)
        img = bubble(img, sx, sy, sr)
    else:
        img = red_dot(img, 782, 782, 36)
        img = bubble(img, 782, 782, 168)
    out = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).convert("RGBA")
    # форма macOS: сжимаем в 0.89 и скругляем
    r = 0.2237 * S
    mask = (cov(sd_rrect(S / 2, S / 2, S / 2, S / 2, r)) * 255).astype(np.uint8)
    out.putalpha(Image.fromarray(mask))
    body = out.resize((912, 912), Image.LANCZOS)
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0)); shadow.paste((0, 0, 0, 120), (56, 70), body.split()[3])
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14)))
    canvas.alpha_composite(body, (56, 56))
    return canvas

if __name__ == "__main__":
    out = sys.argv[1]; os.makedirs(out, exist_ok=True)
    vs = [int(x) for x in sys.argv[2:]] or [1, 2, 3]
    for v in vs: render(v).save(os.path.join(out, f"v{v}.png"))
    sheet = Image.new("RGBA", (1560, 540), (96, 100, 110, 255))
    for i, v in enumerate(vs):
        sheet.alpha_composite(Image.open(os.path.join(out, f"v{v}.png")).resize((500, 500), Image.LANCZOS), (20 + i * 520, 20))
    sheet.save(os.path.join(out, "sheet.png"))
