#!/usr/bin/env python3
"""Собирает 3D-модель горы для вида «Модель».

Вход:  data/dem-idre.json (высоты Copernicus DEM, см. fetch_dem.py)
       app/IdreCup/Resources/pistes.json (трассы: под ними рисуются светлые просеки)
Выход: app/IdreCup/Resources/terrain.json - сетка высот для приложения
       app/IdreCup/Resources/terrain.jpg  - раскраска горы: высота, тени, горизонтали

Координаты модели: метры на восток (x) и на север (y) от вершины.
Нужны numpy, scipy и Pillow: python3 -m pip install numpy scipy pillow
"""

import json
import math
import pathlib

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEM = ROOT / "data" / "dem-idre.json"
PISTES = ROOT / "app" / "IdreCup" / "Resources" / "pistes.json"
OUT_GRID = ROOT / "app" / "IdreCup" / "Resources" / "terrain.json"
OUT_TEXTURE = ROOT / "app" / "IdreCup" / "Resources" / "terrain.jpg"

SUMMIT = (61.8881353, 12.8587081)
WEST, EAST = -2800, 1500           # границы модели, метры от вершины
SOUTH, NORTH = -1800, 1700
GRID_STEP = 25                     # шаг сетки высот в приложении, м
PIXEL = 4                          # размер точки раскраски, м
EXAGGERATION = 3.0                 # во сколько раз вытянута высота: гора пологая

BACKGROUND = (0x0B, 0x10, 0x26)    # фон сцены, Theme.base
LOW = (0x6F, 0x82, 0xAE)           # долина и лес
MID = (0x9F, 0xAF, 0xD2)
HIGH = (0xD9, 0xE2, 0xF4)          # голая вершина
CONTOUR = (0x3A, 0x49, 0x7C)
GLADE = (0xFF, 0xFF, 0xFF)         # просека под трассой


def load_dem():
    data = json.loads(DEM.read_text(encoding="utf-8"))
    heights = np.array(data["heights"], dtype=float).reshape(data["rows"], data["cols"])
    return data, heights


def sample(data, heights, east, north):
    """Высота в точках (east, north), метры от вершины. Гладкая интерполяция."""
    lat = SUMMIT[0] + north / 111320
    lon = SUMMIT[1] + east / (111320 * math.cos(math.radians(SUMMIT[0])))
    rows = (data["north"] - lat) / data["dlat"]
    cols = (lon - data["west"]) / data["dlon"]
    return ndimage.map_coordinates(heights, [rows, cols], order=3, mode="nearest")


def grid(step):
    xs = np.arange(WEST, EAST + step / 2, step)
    ys = np.arange(NORTH, SOUTH - step / 2, -step)   # с севера на юг
    return np.meshgrid(xs, ys)


def blend(a, b, t):
    t = np.clip(t, 0, 1)[..., None]
    return np.array(a, dtype=float) * (1 - t) + np.array(b, dtype=float) * t


def smooth(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


def main():
    data, raw = load_dem()
    # Модель высот включает кроны деревьев: сглаживаем, чтобы лес не выглядел рябью.
    dem = ndimage.gaussian_filter(raw, 0.8)
    soft = ndimage.gaussian_filter(raw, 1.3)      # для теней, ещё мягче

    # Сетка высот для приложения.
    gx, gy = grid(GRID_STEP)
    gh = sample(data, dem, gx, gy)
    base = float(np.floor(gh.min()))
    terrain = {
        "west": WEST,
        "north": NORTH,
        "step": GRID_STEP,
        "cols": gh.shape[1],
        "rows": gh.shape[0],
        "base": base,
        "exaggeration": EXAGGERATION,
        # Строки с севера на юг. Высота над base в дециметрах.
        "heights": [int(round((h - base) * 10)) for h in gh.flatten()],
        "source": "Высоты: Copernicus DEM GLO-30, © DLR e.V. 2010-2014 и © Airbus Defence and Space GmbH 2014-2018, "
                  "предоставлены по программе COPERNICUS Европейским союзом и ESA.",
    }
    OUT_GRID.write_text(json.dumps(terrain, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")

    # Раскраска.
    px, py = grid(PIXEL)
    h = sample(data, dem, px, py)
    height_px, width_px = h.shape

    # Цвет по высоте: внизу холодный серо-синий «лес», вверху белая вершина.
    low, high = 580.0, 890.0
    t = (h - low) / (high - low)
    color = np.where((t < 0.55)[..., None], blend(LOW, MID, t / 0.55), blend(MID, HIGH, (t - 0.55) / 0.45))

    # Просеки под трассами: светлые полосы, как расчищенный склон.
    pistes = json.loads(PISTES.read_text(encoding="utf-8"))
    mask = Image.new("L", (width_px, height_px), 0)
    draw = ImageDraw.Draw(mask)
    lon_m = 111320 * math.cos(math.radians(SUMMIT[0]))
    for piste in pistes["pistes"]:
        line = [
            (((lon - SUMMIT[1]) * lon_m - WEST) / PIXEL, (NORTH - (lat - SUMMIT[0]) * 111320) / PIXEL)
            for lat, lon in piste["coords"]
        ]
        draw.line(line, fill=255, width=round(40 / PIXEL), joint="curve")
    glade = np.asarray(mask.filter(ImageFilter.GaussianBlur(1.5)), dtype=float) / 255
    color = color * (1 - 0.55 * glade[..., None]) + np.array(GLADE, dtype=float) * (0.55 * glade[..., None])

    # Тени: свет с северо-запада, высота вытянута так же, как в модели.
    dy, dx = np.gradient(sample(data, soft, px, py) * EXAGGERATION, PIXEL)
    dy = -dy                                        # строки идут на юг
    azimuth, altitude = math.radians(315), math.radians(42)
    light = np.array([math.sin(azimuth) * math.cos(altitude), math.cos(azimuth) * math.cos(altitude), math.sin(altitude)])
    normal = np.dstack([-dx, -dy, np.ones_like(h)])
    normal /= np.linalg.norm(normal, axis=2, keepdims=True)
    shade = np.clip(normal @ light, 0, 1)
    flat = math.sin(altitude)                       # освещённость ровной земли
    color = color * np.clip(1 + 1.1 * (shade - flat), 0.5, 1.22)[..., None]

    # Горизонтали: тонкие через 20 м, заметные через 100 м.
    hy, hx = np.gradient(h, PIXEL)
    slope = np.hypot(hx, hy) + 1e-3                 # метров высоты на метр
    for interval, width, strength in ((20, 0.5, 0.30), (100, 1.0, 0.55)):
        to_line = np.abs((h + interval / 2) % interval - interval / 2) / slope / PIXEL   # в точках
        line = np.clip(width + 0.5 - to_line, 0, 1) * strength
        color = color * (1 - line[..., None]) + np.array(CONTOUR, dtype=float) * line[..., None]

    # Края растворяются в фоне сцены.
    yy, xx = np.mgrid[0:height_px, 0:width_px]
    u = np.abs(xx / (width_px - 1) * 2 - 1)
    v = np.abs(yy / (height_px - 1) * 2 - 1)
    fade = smooth((1 - (u ** 4 + v ** 4) ** 0.25) / 0.14)   # скруглённый прямоугольник
    color = np.array(BACKGROUND, dtype=float) * (1 - fade[..., None]) + color * fade[..., None]

    image = Image.fromarray(np.clip(color, 0, 255).astype(np.uint8), "RGB")
    image.save(OUT_TEXTURE, quality=88, optimize=True)

    print(f"Сетка {terrain['cols']}×{terrain['rows']}, высоты {gh.min():.0f}-{gh.max():.0f} м, base {base:.0f}")
    print(f"Раскраска {width_px}×{height_px}: {OUT_TEXTURE.stat().st_size // 1024} КБ; сетка: {OUT_GRID.stat().st_size // 1024} КБ")


if __name__ == "__main__":
    main()
