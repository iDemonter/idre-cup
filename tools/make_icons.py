#!/usr/bin/env python3
"""Иконка приложения в трёх видах (предложение 8, Figma AppIcon 46:1540 / 46:1551 / 46:1562).

Рисует светлую и tinted-иконку теми же формами, что и тёмная icon-1024.png: гора с трассой,
снежная шапка, горы позади, земля. Рисует в 4096 и уменьшает до 1024 (сглаживание).
  python3 tools/make_icons.py
"""
import pathlib
from PIL import Image, ImageDraw

OUT = pathlib.Path(__file__).resolve().parent.parent / "app" / "IdreCup" / "Assets.xcassets" / "AppIcon.appiconset"
S = 4  # рисуем в 4 раза крупнее

def pts(points):
    return [(x * S, y * S) for x, y in points]

def draw(path, sky_top, sky_bottom, back, ground, mountain, shade, snow, trail):
    size = 1024 * S
    image = Image.new("RGB", (size, size))
    paint = ImageDraw.Draw(image)
    for y in range(size):
        t = y / size
        color = tuple(int(sky_top[i] + (sky_bottom[i] - sky_top[i]) * t) for i in range(3))
        paint.line([(0, y), (size, y)], fill=color)
    paint.polygon(pts([(0, 760), (250, 520), (420, 640), (300, 860), (0, 860)]), fill=back)
    paint.polygon(pts([(760, 680), (1024, 820), (1024, 860), (700, 860)]), fill=back)
    paint.polygon(pts([(120, 860), (512, 250), (904, 860)]), fill=mountain)
    paint.polygon(pts([(538, 418), (610, 402), (904, 860), (600, 860)]), fill=shade)
    paint.polygon(pts([(512, 250), (610, 402), (560, 440), (512, 398), (463, 445), (415, 403)]), fill=snow)
    paint.rectangle(pts([(0, 860), (1024, 1024)]), fill=ground)
    line = pts([(512, 300), (463, 468), (543, 600), (447, 740), (483, 860)])
    paint.line(line, fill=trail, width=18 * S, joint="curve")
    for x, y in line:
        r = 9 * S
        paint.ellipse([x - r, y - r, x + r, y + r], fill=trail)
    image.resize((1024, 1024), Image.LANCZOS).save(path)
    print("→", path)

def hexc(value):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))

# Светлая: небо и земля светлые, гора и трасса как в тёмной.
draw(OUT / "icon-1024-light.png", hexc("BFE5FF"), hexc("EAF6FF"), hexc("D2ECFB"), hexc("F4F9FF"),
     hexc("4FD8FF"), hexc("31A0CC"), hexc("FFFFFF"), hexc("0E1229"))
# Tinted: оттенки серого на тёмном фоне, система сама окрашивает.
draw(OUT / "icon-1024-tinted.png", hexc("1C1C1C"), hexc("262626"), hexc("3A3A3A"), hexc("0D0D0D"),
     hexc("C8C8C8"), hexc("8E8E8E"), hexc("FFFFFF"), hexc("0D0D0D"))
