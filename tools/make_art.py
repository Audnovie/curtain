#!/usr/bin/env python3
"""Draws the app icon and the sample wallpaper used by the UI tests.

    python3 tools/make_art.py

Needs Pillow. The results are committed; run this again only to change the artwork.
"""
from PIL import Image, ImageDraw, ImageFilter
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "App", "Assets.xcassets")


def vertical_gradient(size, top, bottom):
    w, h = size
    img = Image.new("RGB", size)
    px = img.load()
    for y in range(h):
        t = y / (h - 1)
        c = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = c
    return img


def icon():
    # The app's signature: the row of hour blocks, the last one part empty.
    s = 1024
    img = vertical_gradient((s, s), (224, 52, 66), (150, 22, 38)).convert("RGBA")
    d = ImageDraw.Draw(img)
    blocks, bw, gap, bh = 5, 104, 44, 420
    total = blocks * bw + (blocks - 1) * gap
    x0 = (s - total) // 2
    y0 = (s - bh) // 2 + 20
    for i in range(blocks):
        x = x0 + i * (bw + gap)
        if i < blocks - 1:
            d.rounded_rectangle([x, y0, x + bw, y0 + bh], radius=34, fill=(255, 255, 255, 255))
        else:
            d.rounded_rectangle([x, y0, x + bw, y0 + bh], radius=34, fill=(255, 255, 255, 70))
            part = Image.new("RGBA", (s, s), (0, 0, 0, 0))
            pd = ImageDraw.Draw(part)
            pd.rounded_rectangle([x, y0, x + bw, y0 + bh], radius=34, fill=(255, 255, 255, 255))
            keep = Image.new("L", (s, s), 0)
            ImageDraw.Draw(keep).rectangle([x, y0 + int(bh * 0.62), x + bw, y0 + bh], fill=255)
            img.paste(part, (0, 0), keep)
    img.convert("RGB").save(os.path.join(ASSETS, "AppIcon.appiconset", "icon-1024.png"))


def wallpaper():
    # A stand-in Home Screen background for the "match my wallpaper" test: dark navy with a
    # periwinkle disc and a teal disc, softly blurred.
    w, h = 390, 844
    img = vertical_gradient((w, h), (6, 20, 80), (2, 6, 40)).convert("RGB")
    d = ImageDraw.Draw(img)
    d.ellipse([120, -60, 520, 440], fill=(88, 118, 200))
    d.ellipse([-240, 300, 330, 900], fill=(46, 120, 128))
    d.ellipse([230, 520, 560, 900], fill=(40, 70, 160))
    img = img.filter(ImageFilter.GaussianBlur(3))
    img.save(os.path.join(ASSETS, "TestWallpaper.imageset", "wallpaper.png"))


if __name__ == "__main__":
    icon()
    wallpaper()
    print("done")
