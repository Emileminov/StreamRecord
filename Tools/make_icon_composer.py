#!/usr/bin/env python3
"""Иконки Apple Liquid Glass через Icon Composer (ictool): настоящее системное стекло.
Рисуем слои (подложка + белые формы), стекло/преломление/блики добавляет ictool.
Использование: python3 Tools/make_icon_composer.py <папка> [номера вариантов]
Результат: <папка>/vN.icon (документ для Icon Composer/actool) и vN.png (рендер 1024)."""
import json, os, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ICTOOL = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
S = 1024
SS = 3  # суперсэмплинг для гладких форм

def canvas(): return Image.new("RGBA", (S * SS, S * SS), (0, 0, 0, 0))
def fin(im): return im.resize((S, S), Image.LANCZOS)
def sc(v): return int(v * SS)

def backdrop(blobs, base=(14, 14, 22)):
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    img = np.zeros((S, S, 3), np.float32) + np.array(base, np.float32)
    for (x, y, r, col, a) in blobs:
        d = np.hypot(xx - x * S, yy - y * S) / (r * S)
        w = np.clip(1 - d, 0, 1) ** 1.6 * a
        img = img * (1 - w[..., None]) + np.array(col, np.float32) * w[..., None]
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).convert("RGBA")

def ring(cx, cy, R, W):
    im = canvas(); d = ImageDraw.Draw(im)
    d.ellipse([sc(cx - R), sc(cy - R), sc(cx + R), sc(cy + R)], fill=(255, 255, 255, 255))
    d.ellipse([sc(cx - R + W), sc(cy - R + W), sc(cx + R - W), sc(cy + R - W)], fill=(0, 0, 0, 0))
    return fin(im)
def disc(cx, cy, r, col=(255, 255, 255, 255)):
    im = canvas(); ImageDraw.Draw(im).ellipse([sc(cx - r), sc(cy - r), sc(cx + r), sc(cy + r)], fill=col); return fin(im)
def rrect(x0, y0, x1, y1, r, col=(255, 255, 255, 255), rot=0):
    im = canvas(); ImageDraw.Draw(im).rounded_rectangle([sc(x0), sc(y0), sc(x1), sc(y1)], radius=sc(r), fill=col)
    if rot: im = im.rotate(rot, center=(sc((x0 + x1) / 2 - (x1 - x0) / 2), sc(y0)), resample=Image.BICUBIC)
    return fin(im)
def poly(pts, col=(255, 255, 255, 255)):
    im = canvas(); ImageDraw.Draw(im).polygon([(sc(x), sc(y)) for x, y in pts], fill=col); return fin(im)

RED = (255, 59, 64, 255)

def layers(v):
    """-> (backdrop Image, [(имя, Image, свойства слоя), ...]) для варианта v"""
    if v == 1:
        bd = backdrop([(0.22, 0.2, 0.75, (40, 100, 255), 0.95), (0.85, 0.85, 0.8, (255, 50, 150), 0.9), (0.85, 0.15, 0.4, (140, 70, 255), 0.6)])
        return bd, [("ring", ring(512, 512, 290, 78), {}), ("dot", disc(512, 512, 78, RED), {})]
    if v == 2:
        bd = backdrop([(0.25, 0.25, 0.8, (20, 200, 200), 0.9), (0.85, 0.8, 0.8, (30, 80, 255), 0.95), (0.15, 0.9, 0.4, (90, 230, 140), 0.6)], base=(6, 20, 28))
        return bd, [("orb", disc(512, 512, 290), {})]
    if v == 3:
        bd = backdrop([(0.2, 0.2, 0.8, (255, 140, 20), 0.95), (0.85, 0.75, 0.8, (255, 40, 110), 0.9), (0.6, 0.95, 0.4, (160, 50, 255), 0.6)], base=(26, 10, 14))
        board = rrect(250, 470, 774, 800, 46)
        stick = rrect(250, 335, 774, 440, 34, rot=7)
        return bd, [("board", board, {}), ("stick", stick, {})]
    if v == 4:
        bd = backdrop([(0.2, 0.2, 0.8, (130, 70, 255), 0.95), (0.85, 0.8, 0.8, (40, 120, 255), 0.9), (0.15, 0.9, 0.4, (255, 90, 190), 0.6)], base=(16, 10, 30))
        cam = rrect(190, 360, 600, 690, 80)
        lens = poly([(640, 525), (830, 400), (830, 650)])
        return bd, [("cam", cam, {}), ("lens", lens, {})]
    if v == 5:
        bd = backdrop([(0.2, 0.2, 0.8, (255, 60, 70), 0.95), (0.85, 0.85, 0.8, (255, 140, 40), 0.85), (0.8, 0.15, 0.4, (200, 40, 140), 0.6)], base=(26, 8, 12))
        return bd, [("ring", ring(512, 512, 320, 56), {}), ("orb", disc(512, 512, 190, RED), {})]
    # 6: графит, сдержанно
    bd = backdrop([(0.2, 0.15, 0.8, (110, 120, 150), 0.7), (0.85, 0.9, 0.7, (80, 60, 130), 0.6)], base=(12, 12, 16))
    return bd, [("ring", ring(512, 512, 290, 78), {}), ("dot", disc(512, 512, 78, RED), {})]

def build(v, out):
    d = os.path.join(out, f"v{v}.icon"); a = os.path.join(d, "Assets")
    os.makedirs(a, exist_ok=True)
    bd, ls = layers(v)
    bd.save(os.path.join(a, "bg.png"))
    groups = []
    for name, im, props in ls:
        im.save(os.path.join(a, f"{name}.png"))
        groups.append({"layers": [{"image-name": f"{name}.png", "name": name, "glass": True}],
                       "shadow": {"kind": "neutral", "opacity": 0.5},
                       "translucency": {"enabled": True, "value": float(os.environ.get("TR", "0.35"))}, "specular": True})
    groups.append({"layers": [{"image-name": "bg.png", "name": "bg"}]})   # подложка — нижним слоем
    groups = groups[-1:] + groups[:-1]
    doc = {"fill": {"solid": "srgb:0.05,0.05,0.08,1"}, "groups": groups, "supported-platforms": {"squares": "shared"}}
    json.dump(doc, open(os.path.join(d, "icon.json"), "w"), indent=2)
    subprocess.run([ICTOOL, d, "--export-image", "--output-file", os.path.join(out, f"v{v}.png"), "--platform", "macOS",
                    "--rendition", "Default", "--width", "1024", "--height", "1024", "--scale", "1"], check=True, capture_output=True)

if __name__ == "__main__":
    out = sys.argv[1]; os.makedirs(out, exist_ok=True)
    vs = [int(x) for x in sys.argv[2:]] or list(range(1, 7))
    for v in vs: build(v, out)
    sheet = Image.new("RGBA", (1560, 1040), (100, 104, 114, 255))
    for v in range(1, 7):
        p = os.path.join(out, f"v{v}.png")
        if os.path.exists(p):
            im = Image.open(p).convert("RGBA").resize((500, 500), Image.LANCZOS)
            sheet.alpha_composite(im, (20 + ((v - 1) % 3) * 520, 20 + ((v - 1) // 3) * 520))
    sheet.save(os.path.join(out, "sheet.png"))
