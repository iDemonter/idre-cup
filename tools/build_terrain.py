#!/usr/bin/env python3
"""Собирает 3D-модель горы для вида «Модель».

Курорт — первый аргумент, по умолчанию idre; настройки в tools/models.json.
Для Idre файлы без суффикса, для остальных с суффиксом «-<курорт>» (например terrain-are.json).

Вход:  data/dem-<курорт>.json  - высоты Copernicus DEM (fetch_dem.py)
       data/osm-land.json (Idre) или data/osm-land-<курорт>.json - вода, дома, дороги, места (fetch_osm.py)
       app/IdreCup/Resources/pistes[-<курорт>].json - трассы и подъёмники
Выход: app/IdreCup/Resources/terrain[-<курорт>].json - сетка высот
       app/IdreCup/Resources/terrain[-<курорт>].jpg  - раскраска горы: высота, тени, горизонтали, лес, дороги, вода
       app/IdreCup/Resources/scenery[-<курорт>].json - деревья, дома, полезные места и названия районов

Координаты модели: метры на восток (x) и на север (y) от вершины.
Нужны numpy, scipy и Pillow: python3 -m pip install numpy scipy pillow
"""

import json
import math
import pathlib
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

ROOT = pathlib.Path(__file__).resolve().parent.parent
MODEL_ID = sys.argv[1] if len(sys.argv) > 1 else "idre"
MODEL = json.loads((ROOT / "tools" / "models.json").read_text(encoding="utf-8"))[MODEL_ID]
SUFFIX = "" if MODEL_ID == "idre" else f"-{MODEL_ID}"
RESOURCES = ROOT / "app" / "IdreCup" / "Resources"

DEM = ROOT / "data" / f"dem-{MODEL_ID}.json"
LAND = ROOT / "data" / ("osm-land.json" if MODEL_ID == "idre" else f"osm-land-{MODEL_ID}.json")
PISTES = RESOURCES / f"pistes{SUFFIX}.json"
OUT_GRID = RESOURCES / f"terrain{SUFFIX}.json"
OUT_TEXTURE = RESOURCES / f"terrain{SUFFIX}.jpg"
OUT_SCENERY = RESOURCES / f"scenery{SUFFIX}.json"

SUMMIT = tuple(MODEL["summit"])
LON_M = 111320 * math.cos(math.radians(SUMMIT[0]))
# Границы модели, метры от вершины. У Idre на западе в неё входит соседний Idre Himmelfjäll,
# на севере вершина Städjan: рельеф общий, без шва.
WEST, EAST, SOUTH, NORTH = MODEL["bounds"]
GRID_STEP = 25                     # шаг сетки высот в приложении, м
PIXEL = 2.5                        # размер точки раскраски, м
EXAGGERATION = MODEL["exaggeration"]   # во сколько раз вытянута высота: пологая гора вытянута сильнее

# Лес. В OpenStreetMap он отмечен только местами, поэтому граница леса берётся по высоте:
# ниже TREES_FULL лес сплошной, выше TREES_NONE его нет, между ними редеет.
TREES_FULL, TREES_NONE = MODEL["trees"]
TREE_STEP = 24                     # среднее расстояние между деревьями модели, м
GLADE = {"piste": 30, "lift": 16, "road": 9, "building": 10}   # сколько метров от линии без деревьев

BACKGROUND = (0x0B, 0x10, 0x26)    # фон сцены, Theme.base
LOW = (0x6F, 0x82, 0xAE)           # долина
MID = (0x9F, 0xAF, 0xD2)
HIGH = (0xD9, 0xE2, 0xF4)          # голая вершина
CONTOUR = (0x3A, 0x49, 0x7C)
SNOW = (0xFF, 0xFF, 0xFF)          # просека под трассой
FOREST = (0x4C, 0x5F, 0x92)        # земля под лесом
ROAD = (0x46, 0x54, 0x80)
WATER = (0x86, 0xB4, 0xEE)
SHADOW = (0x20, 0x2A, 0x58)        # тень под домом


def load_dem():
    data = json.loads(DEM.read_text(encoding="utf-8"))
    heights = np.array(data["heights"], dtype=float).reshape(data["rows"], data["cols"])
    return data, heights


def sample(data, heights, east, north):
    """Высота в точках (east, north), метры от вершины. Гладкая интерполяция."""
    lat = SUMMIT[0] + north / 111320
    lon = SUMMIT[1] + east / LON_M
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


def paint(color, layer, strength, tint):
    """Накладывает цвет tint по маске layer (0..1) с силой strength."""
    amount = (np.clip(layer, 0, 1) * strength)[..., None]
    return color * (1 - amount) + np.array(tint, dtype=float) * amount


def local(lat, lon):
    return ((lon - SUMMIT[1]) * LON_M, (lat - SUMMIT[0]) * 111320)


def to_pixel(place):
    return ((place[0] - WEST) / PIXEL, (NORTH - place[1]) / PIXEL)


def inside(place, margin=0):
    return WEST + margin <= place[0] <= EAST - margin and SOUTH + margin <= place[1] <= NORTH - margin


def rings(element):
    """Контуры объекта OpenStreetMap в метрах: [(роль, [(east, north), ...])]."""
    if element["type"] == "way" and "geometry" in element:
        return [("outer", [local(p["lat"], p["lon"]) for p in element["geometry"]])]
    if element["type"] == "relation":
        return [
            (member.get("role") or "outer", [local(p["lat"], p["lon"]) for p in member["geometry"]])
            for member in element.get("members", [])
            if member.get("geometry")
        ]
    return []


def center(element):
    if element["type"] == "node":
        return local(element["lat"], element["lon"])
    points = [p for _, ring in rings(element) for p in ring]
    if not points:
        return None
    return (sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points))


class Canvas:
    """Маски в размере раскраски: рисуем линии и многоугольники в метрах, получаем массивы 0..1."""

    def __init__(self, width, height):
        self.size = (width, height)

    def lines(self, paths, width_m):
        image = Image.new("L", self.size, 0)
        draw = ImageDraw.Draw(image)
        for path in paths:
            if len(path) >= 2:
                draw.line([to_pixel(p) for p in path], fill=255, width=max(1, round(width_m / PIXEL)), joint="curve")
        return image

    def areas(self, shapes):
        image = Image.new("L", self.size, 0)
        draw = ImageDraw.Draw(image)
        for role, ring in shapes:
            if len(ring) >= 3:
                draw.polygon([to_pixel(p) for p in ring], fill=0 if role == "inner" else 255)
        return image

    @staticmethod
    def array(image, blur=0.0):
        if blur > 0:
            image = image.filter(ImageFilter.GaussianBlur(blur / PIXEL))
        return np.asarray(image, dtype=float) / 255


# Полезные места: тег OpenStreetMap → вид значка в приложении. Порядок задаёт важность.
PLACE_KINDS = [
    ("center", lambda t: t.get("building") and t.get("name", "").startswith("Skicenter")),
    ("food", lambda t: t.get("amenity") in ("restaurant", "cafe", "bar", "pub", "fast_food")),
    ("shop", lambda t: t.get("shop") in ("supermarket", "convenience")),
    ("rental", lambda t: t.get("amenity") in ("ski_rental", "bicycle_rental")),
    ("hotel", lambda t: t.get("tourism") == "hotel" or t.get("leisure") == "resort"),
    ("tickets", lambda t: t.get("shop") == "ticket"),
    ("fun", lambda t: t.get("leisure") in ("miniature_golf", "playground", "sports_centre", "swimming_pool")
        or t.get("tourism") in ("zoo", "attraction")),
    ("shelter", lambda t: t.get("amenity") == "shelter" and t.get("name")),
    ("fuel", lambda t: t.get("amenity") == "fuel"),
    ("parking", lambda t: t.get("amenity") == "parking"),
]


def build_scenery(land, forest):
    """Деревья, дома, полезные места и названия районов для приложения."""
    rng = random.Random(2027)

    # Деревья: по одной попытке на клетку TREE_STEP × TREE_STEP, вероятность берётся из карты леса.
    trees = []
    rows, cols = forest.shape
    y = NORTH - TREE_STEP / 2
    while y > SOUTH:
        x = WEST + TREE_STEP / 2
        while x < EAST:
            east = x + rng.uniform(-0.45, 0.45) * TREE_STEP
            north = y + rng.uniform(-0.45, 0.45) * TREE_STEP
            column = min(max(int((east - WEST) / PIXEL), 0), cols - 1)
            row = min(max(int((NORTH - north) / PIXEL), 0), rows - 1)
            if rng.random() < forest[row, column]:
                trees += [round(east), round(north), rng.randint(0, 9)]   # третье число: размер от 0 до 9
            x += TREE_STEP
        y -= TREE_STEP

    # Дома: прямоугольник по контуру (главная ось по самому длинному ребру).
    buildings = []
    for element in land:
        tags = element.get("tags", {})
        if "building" not in tags or tags["building"] in ("roof", "shed", "terrace"):
            continue
        for _, ring in rings(element)[:1]:
            if len(ring) < 4:
                continue
            edges = [(math.hypot(b[0] - a[0], b[1] - a[1]), a, b) for a, b in zip(ring, ring[1:])]
            _, a, b = max(edges)
            angle = math.atan2(b[1] - a[1], b[0] - a[0])
            cos, sin = math.cos(-angle), math.sin(-angle)
            turned = [(p[0] * cos - p[1] * sin, p[0] * sin + p[1] * cos) for p in ring]
            min_u, max_u = min(p[0] for p in turned), max(p[0] for p in turned)
            min_v, max_v = min(p[1] for p in turned), max(p[1] for p in turned)
            length, width = max_u - min_u, max_v - min_v
            if length * width < 20:
                continue
            mid_u, mid_v = (min_u + max_u) / 2, (min_v + max_v) / 2
            cos, sin = math.cos(angle), math.sin(angle)
            middle = (mid_u * cos - mid_v * sin, mid_u * sin + mid_v * cos)
            if inside(middle, 150):
                buildings.append([round(middle[0], 1), round(middle[1], 1), round(length, 1), round(width, 1), round(math.degrees(angle))])

    # Полезные места.
    places = []
    for element in land:
        tags = element.get("tags", {})
        kind = next((kind for kind, test in PLACE_KINDS if test(tags)), None)
        middle = center(element)
        if not kind or not middle or not inside(middle, 200):
            continue
        if not tags.get("name") and kind != "parking":
            continue   # место без названия на карте ничего не скажет
        # Одно и то же место бывает отмечено дважды, а значки рядом сливаются: оставляем первое.
        near = 150 if kind == "parking" else 25
        if any(p["kind"] == kind and math.hypot(p["east"] - middle[0], p["north"] - middle[1]) < near for p in places):
            continue
        places.append({"kind": kind, "name": tags.get("name"), "east": round(middle[0]), "north": round(middle[1])})
    order = [kind for kind, _ in PLACE_KINDS]
    places.sort(key=lambda p: (order.index(p["kind"]), p["name"] or ""))

    # Названия районов посёлка: по ним проще найти свой домик.
    areas = []
    for element in land:
        tags = element.get("tags", {})
        if element["type"] == "node" and tags.get("place") in MODEL["areaPlaces"] and tags.get("name"):
            middle = center(element)
            if inside(middle, 200) and tags["name"] != "Skills area":
                areas.append({"name": tags["name"], "east": round(middle[0]), "north": round(middle[1])})

    scenery = {
        "source": "Дома, дороги, вода и полезные места: © участники OpenStreetMap (ODbL). Лес расставлен по высоте.",
        "trees": trees,
        "buildings": buildings,
        "places": places,
        "areas": areas,
    }
    OUT_SCENERY.write_text(json.dumps(scenery, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    return scenery


def main():
    data, raw = load_dem()
    # Модель высот включает кроны деревьев: сглаживаем, чтобы лес не выглядел рябью.
    dem = ndimage.gaussian_filter(raw, 0.8)
    soft = ndimage.gaussian_filter(raw, 1.3)      # для теней, ещё мягче
    land = json.loads(LAND.read_text(encoding="utf-8"))["elements"]
    pistes = json.loads(PISTES.read_text(encoding="utf-8"))

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
    canvas = Canvas(width_px, height_px)

    # Линии и площади из данных.
    piste_lines = [[local(lat, lon) for lat, lon in piste["coords"]] for piste in pistes["pistes"]]
    lift_lines = [[local(lat, lon) for lat, lon in lift["coords"]] for lift in pistes["lifts"]]
    road_lines = [ring for e in land if "highway" in e.get("tags", {}) for _, ring in rings(e)]
    building_shapes = [shape for e in land if "building" in e.get("tags", {}) for shape in rings(e)]
    water_shapes = [shape for e in land if e.get("tags", {}).get("natural") == "water" for shape in rings(e)]
    open_shapes = [shape for e in land if e.get("tags", {}).get("natural") in ("fell", "bare_rock", "wetland") for shape in rings(e)]

    yy, xx = np.mgrid[0:height_px, 0:width_px]
    u = np.abs(xx / (width_px - 1) * 2 - 1)
    v = np.abs(yy / (height_px - 1) * 2 - 1)
    fade = smooth((1 - (u ** 4 + v ** 4) ** 0.25) / 0.14)   # к краям модель растворяется в фоне

    # Карта леса: 1 = сплошной лес, 0 = деревьев нет.
    forest = smooth((TREES_NONE - h) / (TREES_NONE - TREES_FULL))
    forest *= 1 - canvas.array(canvas.lines(piste_lines, GLADE["piste"] * 2), blur=4)
    forest *= 1 - canvas.array(canvas.lines(lift_lines, GLADE["lift"] * 2), blur=3)
    forest *= 1 - canvas.array(canvas.lines(road_lines, GLADE["road"] * 2), blur=2)
    houses = canvas.areas(building_shapes)
    forest *= 1 - canvas.array(houses.filter(ImageFilter.MaxFilter(2 * round(GLADE["building"] / PIXEL) + 1)))
    # В посёлке лес редкий.
    forest *= 1 - 0.7 * canvas.array(houses.filter(ImageFilter.MaxFilter(2 * round(40 / PIXEL) + 1)), blur=12)
    forest *= 1 - canvas.array(canvas.areas(water_shapes), blur=3)
    forest *= 1 - canvas.array(canvas.areas(open_shapes), blur=6)
    forest *= fade > 0.75
    # Лес неровный: где-то гуще, где-то реже.
    patches = ndimage.gaussian_filter(np.random.default_rng(2027).standard_normal(h.shape), 55 / PIXEL)
    forest *= np.clip(0.97 + 0.8 * patches / patches.std(), 0.2, 1)
    forest = np.clip(forest, 0, 1)
    scenery = build_scenery(land, forest)

    # Цвет по высоте: внизу холодный серо-синий, вверху белая вершина.
    # Цвета по высоте: из настроек или от самой низкой до самой высокой точки модели.
    low, high = (float(v) for v in MODEL.get("colors") or (np.percentile(h, 2), np.percentile(h, 99.5)))
    t = (h - low) / (high - low)
    color = np.where((t < 0.55)[..., None], blend(LOW, MID, t / 0.55), blend(MID, HIGH, (t - 0.55) / 0.45))

    # Земля под лесом темнее, просеки трасс светлые.
    color = paint(color, ndimage.gaussian_filter(forest, 6 / PIXEL), 0.45, FOREST)
    color = paint(color, canvas.array(canvas.lines(piste_lines, 40), blur=4), 0.6, SNOW)

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
    for interval, width, strength in ((20, 0.5, 0.26), (100, 1.0, 0.5)):
        to_line = np.abs((h + interval / 2) % interval - interval / 2) / slope / PIXEL   # в точках
        line = np.clip(width + 0.5 - to_line, 0, 1) * strength
        color = color * (1 - line[..., None]) + np.array(CONTOUR, dtype=float) * line[..., None]

    # Деревья на раскраске: тёмное пятнышко тени и светлая макушка. Издалека лес читается как фактура,
    # а вблизи приложение ставит на эти же места объёмные ели.
    shadows = Image.new("L", (width_px, height_px), 0)
    crowns = Image.new("L", (width_px, height_px), 0)
    draw_shadow, draw_crown = ImageDraw.Draw(shadows), ImageDraw.Draw(crowns)
    trees = scenery["trees"]
    for index in range(0, len(trees), 3):
        x, y = to_pixel((trees[index], trees[index + 1]))
        size = (5.5 + trees[index + 2] * 0.35) / PIXEL
        draw_shadow.ellipse([x - size + 1.2, y - size + 1.2, x + size + 1.2, y + size + 1.2], fill=255)
        draw_crown.ellipse([x - size * 0.55 - 0.6, y - size * 0.55 - 0.6, x + size * 0.55 - 0.6, y + size * 0.55 - 0.6], fill=255)
    color = paint(color, canvas.array(shadows, blur=1.5), 0.5, (0x2F, 0x3D, 0x73))
    color = paint(color, canvas.array(crowns, blur=1.0), 0.55, (0xB7, 0xC5, 0xEA))

    # Вода, дороги, тени домов.
    color = paint(color, canvas.array(canvas.areas(water_shapes), blur=1.5), 0.9, WATER)
    color = paint(color, canvas.array(canvas.lines(road_lines, 6), blur=1.5), 0.55, ROAD)
    color = paint(color, canvas.array(houses.filter(ImageFilter.MaxFilter(3)), blur=3), 0.45, SHADOW)

    color = np.array(BACKGROUND, dtype=float) * (1 - fade[..., None]) + color * fade[..., None]
    Image.fromarray(np.clip(color, 0, 255).astype(np.uint8), "RGB").save(OUT_TEXTURE, quality=86, optimize=True)

    print(f"Сетка {terrain['cols']}×{terrain['rows']}, высоты {gh.min():.0f}-{gh.max():.0f} м, base {base:.0f}")
    print(f"Раскраска {width_px}×{height_px}: {OUT_TEXTURE.stat().st_size // 1024} КБ; сетка: {OUT_GRID.stat().st_size // 1024} КБ")
    print(f"Окружение: деревьев {len(scenery['trees']) // 3}, домов {len(scenery['buildings'])}, "
          f"мест {len(scenery['places'])}, районов {len(scenery['areas'])}; {OUT_SCENERY.stat().st_size // 1024} КБ")
    print("Места:", [(p["kind"], p["name"]) for p in scenery["places"]])
    print("Районы:", [a["name"] for a in scenery["areas"]])


if __name__ == "__main__":
    main()
