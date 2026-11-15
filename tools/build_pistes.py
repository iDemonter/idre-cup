#!/usr/bin/env python3
"""Собирает компактный файл трасс для приложения.

Вход:  data/osm-idre.json (геометрия из OpenStreetMap, см. fetch_osm.py)
Выход: app/IdreCup/Resources/pistes.json

Номера, зоны и сложность берутся из официальной карты трасс Idre Fjäll 2026/27,
геометрия из OpenStreetMap. Соседний курорт Idre Himmelfjäll отсекается по расстоянию.
"""

import json
import math
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "data" / "osm-idre.json"
OUT = ROOT / "app" / "IdreCup" / "Resources" / "pistes.json"

SUMMIT = (61.8881353, 12.8587081)  # Gränjåsvålen, 891 м
RADIUS_KM = 2.6                    # всё дальше относится к Idre Himmelfjäll
MIN_UNNAMED_M = 150                # короткие безымянные обрезки не показываем

# Официальная карта: номер, название, зона, сложность, освещение.
# Сложность: green, blue, red, black; mixed = участки разной сложности (берём из OSM).
OFFICIAL = [
    (1, "Västbacken", "Väst", "mixed", True),
    (2, "Familjeparken", "Väst", "green", True),
    (3, "Askes skidområde", "Väst", "green", True),
    (4, "Ostpassagen", "Väst", "green", False),
    (5, "Toppbacken", "Väst", "green", True),
    (6, "Tunnelbacken", "Väst", "blue", False),
    (7, "Äventyret", "Väst", "red", False),
    (8, "Snowpark", "Väst", "mixed", False),
    (9, "Askestigen", "Väst", "green", False),
    (35, "Blåbärsslingan", "Väst", "green", True),
    (36, "Fäbodsvängen", "Väst", "green", False),
    (37, "Ravinen", "Väst", "blue", False),
    (38, "Tallbacken", "Väst", "red", False),
    (10, "Stugbybacken", "Syd", "blue", False),
    (11, "Dalsbranten", "Syd", "black", False),
    (12, "Skicenter Syd", "Syd", "green", False),
    (13, "Dalarnas längsta", "Syd", "green", False),
    (14, "Dalen 1", "Syd", "green", False),
    (15, "Dalen 2", "Syd", "green", False),
    (40, "Gondolsvängen", "Syd", "green", True),
    (41, "Pernillabacken", "Syd", "mixed", True),
    (16, "Ostbacken", "Ost", "green", False),
    (17, "Ostkroken", "Ost", "green", False),
    (18, "Lämmeln", "Ost", "green", False),
    (19, "Solbacken", "Ost", "blue", False),
    (20, "Rödingen", "Ost", "red", False),
    (21, "Snobbrännan", "Ost", "black", False),
    (22, "Djärven", "Ost", "black", False),
    (23, "Tävlingsbacken", "Ost", "black", False),
    (24, "Chocken", "Ost", "black", False),
    (25, "Svarten 1", "Nord", "black", False),
    (26, "Svarten 2", "Nord", "black", False),
    (27, "Specialen", "Nord", "black", True),
    (28, "Carvingsvängen", "Nord", "red", True),
    (29, "Mellanbacken", "Nord", "red", False),
    (30, "Palmbacken", "Nord", "red", False),
    (31, "Turisten 1", "Nord", "blue", False),
    (32, "Turisten 2", "Nord", "blue", False),
    (33, "Gröngölingen 1", "Nord", "green", False),
    (34, "Gröngölingen 2", "Nord", "green", False),
    (39, "Glidaren", "Nord", "green", False),
]
EXTREME = {24}

# Как названия записаны в OpenStreetMap, если отличаются от официальных.
ALIASES = {
    "lymmeln": "lämmeln",
    "ravinen (skicross)": "ravinen",
    "västbacken self timer": "västbacken",
    "tunnelbacken (drömbacken)": "tunnelbacken",
}

OSM_DIFFICULTY = {
    "novice": "green",
    "easy": "blue",
    "intermediate": "red",
    "advanced": "black",
    "expert": "black",
    "freeride": "black",
}

LIFT_CODES = {
    "nord 6:an": "A", "nordknappen": "B", "askeliften": "C", "ugglans rullband": "D",
    "björnens rullband": "E", "parkliften 1": "F", "parkliften 2": "G", "väst 6:an": "H",
    "tunnelliften": "I", "västtransporten": "J", "familjeliften": "K", "talliften": "L",
    "sydgondolen": "M", "rävens rullband": "N", "knatteknappen": "O", "sydknappen": "P",
    "biejjieliften": "Q", "dalsliften": "R", "ostknappen": "S", "ost 6:an": "T",
    "ost 4:an": "U", "ost 4an": "U", "chockentransporten": "V", "toppliften": "X",
    "nordtransporten": "Y",
}


def km(a, b):
    dy = (a[0] - b[0]) * 111.32
    dx = (a[1] - b[1]) * 111.32 * math.cos(math.radians(SUMMIT[0]))
    return math.hypot(dx, dy)


def length_m(points):
    return sum(km(points[i], points[i + 1]) for i in range(len(points) - 1)) * 1000


def midpoint(points):
    """Точка на середине линии по длине."""
    half = length_m(points) / 2
    walked = 0.0
    for i in range(len(points) - 1):
        step = km(points[i], points[i + 1]) * 1000
        if step > 0 and walked + step >= half:
            t = (half - walked) / step
            return (
                points[i][0] + (points[i + 1][0] - points[i][0]) * t,
                points[i][1] + (points[i + 1][1] - points[i][1]) * t,
            )
        walked += step
    return points[len(points) // 2]


def bearing(a, b):
    """Курс из точки a в точку b, градусы от севера по часовой стрелке."""
    dy = b[0] - a[0]
    dx = (b[1] - a[1]) * math.cos(math.radians(a[0]))
    return (math.degrees(math.atan2(dx, dy)) + 360) % 360


def rounded(points):
    return [[round(p[0], 5), round(p[1], 5)] for p in points]


def main():
    data = json.loads(SOURCE.read_text(encoding="utf-8"))
    official_by_name = {name.lower(): (number, name, zone, difficulty, lit) for number, name, zone, difficulty, lit in OFFICIAL}

    pistes, lifts = [], []
    seen_lifts = set()
    for element in data["elements"]:
        tags = element.get("tags", {})
        geometry = element.get("geometry")
        if not geometry:
            continue
        points = [(p["lat"], p["lon"]) for p in geometry]
        center = (sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points))
        if km(center, SUMMIT) > RADIUS_KM:
            continue
        meters = length_m(points)

        if "piste:type" in tags:
            raw_name = (tags.get("name") or "").strip()
            key = ALIASES.get(raw_name.lower(), raw_name.lower())
            official = official_by_name.get(key)
            osm_difficulty = OSM_DIFFICULTY.get(tags.get("piste:difficulty", ""), "unknown")
            if official:
                number, name, zone, difficulty, lit = official
                if difficulty == "mixed":
                    difficulty = osm_difficulty
            else:
                if meters < MIN_UNNAMED_M:
                    continue
                number, name, zone, lit = None, (raw_name or None), None, False
                difficulty = osm_difficulty
            mid = midpoint(points)
            pistes.append({
                "id": element["id"],
                "number": number,
                "name": name,
                "zone": zone,
                "difficulty": difficulty,
                "extreme": number in EXTREME,
                "lit": lit,
                "length": round(meters),
                "label": False,
                "mid": [round(mid[0], 5), round(mid[1], 5)],
                "coords": rounded(points),
            })
        elif "aerialway" in tags:
            name = (tags.get("name") or "").strip() or None
            key = (name or "").lower()
            if name and key in seen_lifts:
                continue  # один подъёмник бывает записан дважды
            seen_lifts.add(key)
            lifts.append({
                "id": element["id"],
                "code": LIFT_CODES.get(key),
                "name": name,
                "kind": tags["aerialway"],
                "length": round(meters),
                "coords": rounded(points),
            })

    # Значок с номером ставим на самый длинный участок каждой трассы.
    longest = {}
    for piste in pistes:
        if piste["number"] is None:
            continue
        best = longest.get(piste["number"])
        if best is None or piste["length"] > best["length"]:
            longest[piste["number"]] = piste
    for piste in longest.values():
        piste["label"] = True

    # Зоны: центр по трассам и курс камеры снизу вверх, на вершину.
    zones = []
    for zone in ["Väst", "Nord", "Ost", "Syd"]:
        points = [tuple(c) for p in pistes if p["zone"] == zone for c in p["coords"]]
        if not points:
            continue
        center = (sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points))
        zones.append({
            "name": zone,
            "center": [round(center[0], 5), round(center[1], 5)],
            "heading": round(bearing(center, SUMMIT)),
        })

    pistes.sort(key=lambda p: (p["number"] is None, p["number"] or 0, -p["length"]))
    lifts.sort(key=lambda l: (l["code"] is None, l["code"] or "", l["name"] or ""))
    result = {
        "source": "Геометрия: © участники OpenStreetMap (ODbL). Номера и сложность: карта трасс Idre Fjäll 2026/27.",
        "summit": [round(SUMMIT[0], 5), round(SUMMIT[1], 5)],
        "zones": zones,
        "pistes": pistes,
        "lifts": lifts,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")

    found = sorted({p["number"] for p in pistes if p["number"] is not None})
    missing = [f"{n} {name}" for n, name, *_ in OFFICIAL if n not in found]
    print(f"Трасс с номером: {len(found)} из {len(OFFICIAL)}; участков всего: {len(pistes)}; подъёмников: {len(lifts)}")
    print("Нет в OpenStreetMap:", ", ".join(missing) or "нет")
    print("Без номера:", [(p["name"], p["length"]) for p in pistes if p["number"] is None])
    print("Подъёмники:", [(l["code"], l["name"]) for l in lifts])
    print("Зоны:", zones)
    print("Размер файла:", OUT.stat().st_size, "байт")


if __name__ == "__main__":
    main()
