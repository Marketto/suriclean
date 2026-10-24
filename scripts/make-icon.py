#!/usr/bin/env python3
"""Draws the SuriClean icon (Suri's head on a mint background) for every platform.

    python3 scripts/make-icon.py      # from the repo root, needs Pillow
"""
import math
import os
from PIL import Image, ImageDraw

MINT_TOP, MINT_BOTTOM = (196, 245, 226), (79, 201, 160)
FUR, LIGHT, DARK = (230, 184, 128), (250, 230, 194), (115, 77, 54)
INK = (84, 56, 43)


def gradient(size, top, bottom):
    g = Image.new("RGBA", (size, size))
    d = ImageDraw.Draw(g)
    for y in range(size):
        t = y / size
        d.line([(0, y), (size, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))
    return g


def star(d, cx, cy, r, fill=(255, 255, 255, 230)):
    pts = []
    for i in range(8):
        rr = r if i % 2 == 0 else r * 0.28
        a = math.pi / 4 * i - math.pi / 2
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    d.polygon(pts, fill=fill)


def head(img, cx, cy, k):
    """Suri's head; (cx, cy) is the centre of the face, k pixels per unit (face is 120 units wide)."""
    ox, oy = cx - 110 * k, cy - 99 * k
    d = ImageDraw.Draw(img)

    def E(x, y, w, h, fill):
        d.ellipse([ox + (x - w / 2) * k, oy + (y - h / 2) * k, ox + (x + w / 2) * k, oy + (y + h / 2) * k], fill=fill)

    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([ox + 52 * k, oy + 46 * k, ox + 168 * k, oy + 150 * k], fill=(40, 90, 70, 60))
    img.alpha_composite(sh)
    d = ImageDraw.Draw(img)
    for x in (58, 162):
        E(x, 70, 28, 28, DARK); E(x, 70, 13, 13, (255, 170, 190))
    E(110, 92, 120, 100, FUR)
    E(110, 113, 56, 38, LIGHT)
    for ex, ang in ((82, -20), (138, 20)):
        patch = Image.new("RGBA", (int(60 * k), int(60 * k)), (0, 0, 0, 0))
        ImageDraw.Draw(patch).ellipse([(30 - 19) * k, (30 - 23) * k, (30 + 19) * k, (30 + 23) * k], fill=DARK)
        patch = patch.rotate(ang, resample=Image.BICUBIC)
        img.alpha_composite(patch, (int(ox + (ex - 30) * k), int(oy + (88 - 30) * k)))
    d = ImageDraw.Draw(img)
    for ex in (82, 138):
        E(ex, 89, 26, 30, (0, 0, 0)); E(ex - 5, 82, 11, 11, (255, 255, 255)); E(ex + 5, 96, 5, 5, (255, 255, 255))
    for ex in (64, 156):
        E(ex, 116, 22, 12, (255, 150, 175))
    d.polygon([(ox + 102 * k, oy + 100 * k), (ox + 118 * k, oy + 100 * k), (ox + 110 * k, oy + 110 * k)], fill=INK)
    w = max(1, int(2.3 * k))
    d.arc([ox + 101 * k, oy + 109 * k, ox + 110 * k, oy + 119 * k], 0, 180, fill=INK, width=w)
    d.arc([ox + 110 * k, oy + 109 * k, ox + 119 * k, oy + 119 * k], 0, 180, fill=INK, width=w)


def app_icon(S=1024):
    """Rounded square with margins (macOS style), also used for Windows, Linux and the site."""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([60, 60, S - 60, S - 60], radius=200, fill=255)
    img.paste(gradient(S, MINT_TOP, MINT_BOTTOM), (0, 0), mask)
    d = ImageDraw.Draw(img)
    star(d, 190, 190, 46); star(d, 850, 230, 30); star(d, 840, 840, 40); star(d, 175, 820, 26)
    head(img, 512, 547, 5.9)
    return img


def android_foreground(px):
    """Adaptive-icon foreground: 108dp canvas, Suri inside the 72dp visible circle."""
    S = 1024
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    star(d, 345, 330, 20); star(d, 690, 335, 14); star(d, 700, 680, 17)
    head(img, 512, 525, 4.2)
    return img.resize((px, px), Image.LANCZOS)


if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    icon = app_icon()
    icon.save(os.path.join(root, "Resources/AppIcon.png"))
    icon.save(os.path.join(root, "Resources/AppIcon.icns"),
              sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
    res = os.path.join(root, "android/app/src/main/res")
    for name, scale in (("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2), ("xxhdpi", 3), ("xxxhdpi", 4)):
        legacy = int(48 * scale)
        # legacy icon (Android 7 and older launchers): full-bleed squircle
        sq = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
        m = Image.new("L", (1024, 1024), 0)
        ImageDraw.Draw(m).rounded_rectangle([40, 40, 984, 984], radius=230, fill=255)
        sq.paste(gradient(1024, MINT_TOP, MINT_BOTTOM), (0, 0), m)
        head(sq, 512, 540, 6.2)
        sq.resize((legacy, legacy), Image.LANCZOS).save(os.path.join(res, f"mipmap-{name}/ic_launcher.png"))
        android_foreground(int(108 * scale)).save(os.path.join(res, f"mipmap-{name}/ic_launcher_foreground.png"))
    print("icons written")
