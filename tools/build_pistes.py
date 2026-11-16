#!/usr/bin/env python3
"""Собирает компактный файл трасс для приложения.

Вход:  data/osm-idre.json (геометрия из OpenStreetMap, см. fetch_osm.py)
Выход: app/IdreCup/Resources/pistes.json

Номера, зоны и сложность берутся из официальной карты трасс Idre Fjäll 2026/27,
геометрия из OpenStreetMap. Соседний курорт Idre Himmelfjäll отсекается по расстоянию.

Чего в OpenStreetMap нет, дополняется здесь же:
  UNNAMED  - линии, которые в OpenStreetMap есть, но без названия: им назначен номер;
  DRAWN    - трассы, которых в OpenStreetMap нет совсем: нарисованы от руки по официальной
             карте и соседним подъёмникам. В данных у них "approx": true, на карте они
             пунктирные. Точность примерно 30-50 м, для засечки времени не годятся.
"""

import json
import math
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "data" / "osm-idre.json"
OUT = ROOT / "app" / "IdreCup" / "Resources" / "pistes.json"
TERRAIN = ROOT / "app" / "IdreCup" / "Resources" / "terrain.json"
OUT_TRAILS = ROOT / "server" / "config" / "trails.json"

# Соединительные и детские трассы: в коронах и автогонках не участвуют.
NO_CROWN = {2, 3, 4, 9, 12, 36}

SUMMIT = (61.8881353, 12.8587081)  # Gränjåsvålen, 891 м
RADIUS_KM = 2.6                    # всё дальше относится к Idre Himmelfjäll

# Соседний курорт Idre Himmelfjäll: его пронумерованные трассы тоже зачётные (решено 16.11.2026).
HIMMEL = (61.8990, 12.7700)        # середина его трасс
HIMMEL_SUMMIT = (61.9087842, 12.7803565)   # Hemmeråsen, 869 м
HIMMEL_RADIUS_KM = 3.2
HIMMEL_ZONE = "Himmelfjäll"
# Номера трасс у курортов свои и совпадают. В файле у Himmelfjäll номер = 100 + номер с его карты,
# а на значке показывается настоящий (поле display).
HIMMEL_OFFSET = 100
DEM = ROOT / "data" / "dem-idre.json"

# Вершины, которые подписываются на карте. Имя из OpenStreetMap → подпись.
PEAK_NAMES = {
    "Gränjåsvålen": "Idre Fjäll",
    "Hemmeråsen": "Himmelfjäll",
}
MIN_UNNAMED_M = 150                # короткие безымянные обрезки не показываем

# Значки на карте. Экран телефона вмещает примерно 1/24 высоты камеры на один значок
# (замер по скриншоту: 0,19-0,28 pt на метр при камере на 4200 м). Значок появляется,
# когда до соседних уже видимых значков есть место.
BADGE_ROOM = 24
ALWAYS = 30000                     # высота камеры, с которой виден самый важный значок
LIFT_BADGE_MAX = 5000              # буквы подъёмников только вблизи

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
    # Сноупарк в OpenStreetMap записан двумя линиями по старой схеме. Линия с юго-восточной
    # стороны парковых подъёмников = Snowpark (8), с северо-западной = Äventyret (7):
    # так они стоят на официальной карте 2026/27.
    "snowpark grön/blå": "snowpark",
    "snowpark röd": "äventyret",
}

OSM_DIFFICULTY = {
    "novice": "green",
    "easy": "blue",
    "intermediate": "red",
    "advanced": "black",
    "expert": "black",
    "freeride": "black",
}

# Безымянные линии OpenStreetMap, сопоставленные с официальной картой по положению.
# id линии: (номер трассы, запасная ветка). Запасная ветка идёт параллельно основной
# и не входит в длину трассы.
UNNAMED = {
    29350373: (39, False),    # от вершины к верху северных трасс = Glidaren
    1244763833: (40, False),  # слева от гондолы, если смотреть снизу = Gondolsvängen
    1244763831: (41, False),  # справа от гондолы: низ Pernillabacken до нижней станции
    29504048: (9, True),      # вторая ветка Askestigen, верх
    29504049: (9, True),      # вторая ветка Askestigen, низ до Väst 6:an
}

# Трассы, нарисованные от руки. Координаты: метры на восток и на север от вершины.
# (свой id, номер, сложность, запасная ветка, точки сверху вниз)
DRAWN = [
    # Familjeparken: между зелёным участком Västbacken и подъёмником Familjeliften.
    (-2, 2, "green", False, [(-1147, 274), (-1200, 290), (-1270, 293), (-1340, 286), (-1400, 272)]),
    # Askes skidområde: вдоль Askeliften, между ним и детскими лентами.
    (-3, 3, "green", False, [(-1575, 372), (-1632, 322), (-1690, 270)]),
]

# Подъёмники, которые в OpenStreetMap названы иначе, чем на официальной карте.
LIFT_ALIASES = {
    "askeliften 1": "Parkliften 1",        # пара бугелей у сноупарка
    "askeliften 2": "Parkliften 2",
    "skicenter syd": "Rävens rullband",    # единственная лента в Skicenter Syd
    "skicenter syd 2": "Knatteknappen",    # короткий бугель; пара с Sydknappen по длине
    "skicenter syd 1": "Sydknappen",
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


def point_at(points, fraction):
    """Точка на линии на заданной доле длины от начала."""
    target = length_m(points) * fraction
    walked = 0.0
    for i in range(len(points) - 1):
        step = km(points[i], points[i + 1]) * 1000
        if step > 0 and walked + step >= target:
            t = (target - walked) / step
            return (
                points[i][0] + (points[i + 1][0] - points[i][0]) * t,
                points[i][1] + (points[i + 1][1] - points[i][1]) * t,
            )
        walked += step
    return points[-1]


def place_badges(items):
    """Расставляет значки вдоль линий так, чтобы они не слипались.

    items: словари с ключами points, importance, limit. Функция добавляет pos (где стоит
    значок) и show (с какой высоты камеры он виден). Порядок важности: importance по убыванию.
    """
    fractions = [f / 20 for f in range(4, 17)]  # от 20 до 80 % длины
    for item in items:
        item["length"] = length_m(item["points"])
        item["options"] = [(f, point_at(item["points"], f)) for f in fractions]
        item["pos"] = point_at(item["points"], 0.5)

    # Несколько проходов: каждый значок сдвигается туда, где до соседей дальше всего.
    for _ in range(8):
        for item in items:
            others = [o["pos"] for o in items if o is not item]

            def score(option):
                fraction, pos = option
                room = min(km(pos, o) * 1000 for o in others) if others else 1000
                return min(room, 450) - abs(fraction - 0.5) * item["length"] * 0.12

            item["pos"] = max(item["options"], key=score)[1]

    # Чем важнее значок, тем с большей высоты он виден. Менее важный появляется,
    # когда перестаёт задевать уже видимые.
    placed = []
    for item in sorted(items, key=lambda i: -i["importance"]):
        show = item["limit"]
        for other in placed:
            fits_from = km(item["pos"], other["pos"]) * 1000 * BADGE_ROOM
            if fits_from < other["show"]:
                show = min(show, fits_from)
        item["show"] = round(show)
        placed.append(item)


def bearing(a, b):
    """Курс из точки a в точку b, градусы от севера по часовой стрелке."""
    dy = b[0] - a[0]
    dx = (b[1] - a[1]) * math.cos(math.radians(a[0]))
    return (math.degrees(math.atan2(dx, dy)) + 360) % 360


def from_local(point):
    """Метры на восток и на север от вершины в широту и долготу."""
    east, north = point
    return (
        SUMMIT[0] + north / 111320,
        SUMMIT[1] + east / (111320 * math.cos(math.radians(SUMMIT[0]))),
    )


def rounded(points):
    return [[round(p[0], 5), round(p[1], 5)] for p in points]


def write_trails(longest):
    """Зачётные участки трасс для сервера: по ним считаются короны и автогонки.

    Участок = самый длинный основной отрезок трассы, точки идут сверху вниз.
    """
    terrain = json.loads(TERRAIN.read_text(encoding="utf-8"))
    lon_m = 111320 * math.cos(math.radians(SUMMIT[0]))

    def height(point):
        column = min(max(((point[1] - SUMMIT[1]) * lon_m - terrain["west"]) / terrain["step"], 0), terrain["cols"] - 1)
        row = min(max((terrain["north"] - (point[0] - SUMMIT[0]) * 111320) / terrain["step"], 0), terrain["rows"] - 1)
        return terrain["heights"][int(round(row)) * terrain["cols"] + int(round(column))]

    trails = []
    for number, piste in sorted(longest.items()):
        if number in NO_CROWN:
            continue
        coords = piste["coords"]
        if height(coords[0]) < height(coords[-1]):
            coords = coords[::-1]
        trails.append({"number": number, "name": piste["name"], "length": piste["length"], "coords": coords})
    OUT_TRAILS.write_text(json.dumps({"trails": trails}, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"Зачётных трасс для сервера: {len(trails)} → {OUT_TRAILS}")


def main():
    data = json.loads(SOURCE.read_text(encoding="utf-8"))
    official_by_name = {name.lower(): (number, name, zone, difficulty, lit) for number, name, zone, difficulty, lit in OFFICIAL}
    official_by_number = {entry[0]: entry for entry in official_by_name.values()}

    pistes, lifts = [], []
    seen_lifts = set()
    for element in data["elements"]:
        tags = element.get("tags", {})
        geometry = element.get("geometry")
        if not geometry:
            continue
        points = [(p["lat"], p["lon"]) for p in geometry]
        center = (sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points))
        if km(center, SUMMIT) <= RADIUS_KM:
            resort = "idre"
        elif km(center, HIMMEL) <= HIMMEL_RADIUS_KM:
            resort = "himmel"
        else:
            continue
        meters = length_m(points)

        if resort == "himmel":
            # Соседний курорт: номер, название и сложность берём из OpenStreetMap как есть.
            ref = (tags.get("ref") or tags.get("piste:ref") or "").strip()
            name = (tags.get("name") or "").strip() or None
            if tags.get("piste:type") in ("downhill", "snow_park"):
                number = HIMMEL_OFFSET + int(ref) if ref.isdigit() else None
                if number is None and (name is None or meters < MIN_UNNAMED_M):
                    continue
                mid = midpoint(points)
                pistes.append({
                    "id": element["id"],
                    "number": number,
                    "display": ref if number else None,
                    "resort": resort,
                    "name": name,
                    "zone": HIMMEL_ZONE,
                    "difficulty": OSM_DIFFICULTY.get(tags.get("piste:difficulty", ""), "unknown"),
                    "extreme": False,
                    "lit": tags.get("piste:lit") == "yes" or tags.get("lit") == "yes",
                    "length": round(meters),
                    "label": False,
                    "alt": False,
                    "approx": False,
                    "mid": [round(mid[0], 5), round(mid[1], 5)],
                    "coords": rounded(points),
                })
            elif "aerialway" in tags:
                key = "himmel:" + (name or str(element["id"])).lower()
                if key in seen_lifts:
                    continue
                seen_lifts.add(key)
                lifts.append({
                    "id": element["id"],
                    "code": f"H{ref}" if ref else f"H{len(lifts)}",
                    "resort": resort,
                    "name": name,
                    "kind": tags["aerialway"],
                    "length": round(meters),
                    "coords": rounded(points),
                })
            continue

        if tags.get("piste:type") in ("downhill", "snow_park"):
            raw_name = (tags.get("name") or "").strip()
            key = ALIASES.get(raw_name.lower(), raw_name.lower())
            official = official_by_name.get(key)
            alt = False
            if not official and element["id"] in UNNAMED:
                number, alt = UNNAMED[element["id"]]
                official = official_by_number[number]
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
                "alt": alt,
                "approx": False,
                "mid": [round(mid[0], 5), round(mid[1], 5)],
                "coords": rounded(points),
            })
        elif "aerialway" in tags:
            name = (tags.get("name") or "").strip() or None
            name = LIFT_ALIASES.get((name or "").lower(), name)
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

    for own_id, number, difficulty, alt, local in DRAWN:
        _, name, zone, _, lit = official_by_number[number]
        points = [from_local(p) for p in local]
        mid = midpoint(points)
        pistes.append({
            "id": own_id,
            "number": number,
            "name": name,
            "zone": zone,
            "difficulty": difficulty,
            "extreme": False,
            "lit": lit,
            "length": round(length_m(points)),
            "label": False,
            "alt": alt,
            "approx": True,
            "mid": [round(mid[0], 5), round(mid[1], 5)],
            "coords": rounded(points),
        })

    # Значок с номером ставим на самый длинный основной участок каждой трассы.
    longest, total = {}, {}
    for piste in pistes:
        if piste["number"] is None or piste["alt"]:
            continue
        total[piste["number"]] = total.get(piste["number"], 0) + piste["length"]
        best = longest.get(piste["number"])
        if best is None or piste["length"] > best["length"]:
            longest[piste["number"]] = piste
    for piste in longest.values():
        piste["label"] = True

    # Значки трасс важнее букв подъёмников, длинные трассы важнее коротких.
    badges = [
        {"target": piste, "points": piste["coords"], "importance": 100000 + total[number], "limit": ALWAYS}
        for number, piste in longest.items()
    ] + [
        {"target": lift, "points": lift["coords"], "importance": lift["length"], "limit": LIFT_BADGE_MAX}
        for lift in lifts if lift["code"]
    ]
    place_badges(badges)
    for badge in badges:
        badge["target"]["mid"] = [round(badge["pos"][0], 5), round(badge["pos"][1], 5)]
        badge["target"]["show"] = badge["show"]

    # Зоны: центр по трассам и курс камеры снизу вверх, на вершину.
    zones = []
    for zone in ["Väst", "Nord", "Ost", "Syd", HIMMEL_ZONE]:
        points = [tuple(c) for p in pistes if p["zone"] == zone for c in p["coords"]]
        if not points:
            continue
        center = (sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points))
        zones.append({
            "name": zone,
            "center": [round(center[0], 5), round(center[1], 5)],
            "heading": round(bearing(center, HIMMEL_SUMMIT if zone == HIMMEL_ZONE else SUMMIT)),
        })

    # Вершины с высотой: имя и высота из OpenStreetMap, без высоты там берём её из модели высот.
    dem = json.loads(DEM.read_text(encoding="utf-8"))

    def dem_height(lat, lon):
        row = min(max(int(round((dem["north"] - lat) / dem["dlat"])), 0), dem["rows"] - 1)
        column = min(max(int(round((lon - dem["west"]) / dem["dlon"])), 0), dem["cols"] - 1)
        return dem["heights"][row * dem["cols"] + column]

    peaks = []
    for element in data["elements"]:
        tags = element.get("tags", {})
        if element.get("type") != "node" or tags.get("natural") != "peak" or not tags.get("name"):
            continue
        try:
            height = float(tags["ele"].replace(",", "."))
        except (KeyError, ValueError):
            height = dem_height(element["lat"], element["lon"])
        peaks.append({
            "name": PEAK_NAMES.get(tags["name"], tags["name"]),
            "height": round(height),
            "at": [round(element["lat"], 5), round(element["lon"], 5)],
        })
    peaks.sort(key=lambda peak: -peak["height"])

    pistes.sort(key=lambda p: (p["number"] is None, p["number"] or 0, -p["length"]))
    lifts.sort(key=lambda l: (l["code"] is None, l["code"] or "", l["name"] or ""))
    result = {
        "source": "Геометрия: © участники OpenStreetMap (ODbL). Номера и сложность: карта трасс Idre Fjäll 2026/27. Трассы с approx нарисованы от руки.",
        "summit": [round(SUMMIT[0], 5), round(SUMMIT[1], 5)],
        "zones": zones,
        "peaks": peaks,
        "pistes": pistes,
        "lifts": lifts,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")

    write_trails(longest)

    found = sorted({p["number"] for p in pistes if p["number"] is not None and p["number"] < HIMMEL_OFFSET})
    himmel = sorted({p["display"] for p in pistes if p.get("resort") == "himmel" and p["number"]}, key=int)
    print("Himmelfjäll, трассы:", himmel, "подъёмники:", [(l["code"], l["name"], l["kind"]) for l in lifts if l.get("resort") == "himmel"])
    print("Вершины:", [(p["name"], p["height"]) for p in peaks])
    missing = [f"{n} {name}" for n, name, *_ in OFFICIAL if n not in found]
    print(f"Трасс с номером: {len(found)} из {len(OFFICIAL)}; участков всего: {len(pistes)}; подъёмников: {len(lifts)}")
    print("Не хватает:", ", ".join(missing) or "нет")
    print("Нарисованы от руки:", sorted({p["number"] for p in pistes if p["approx"]}))
    print("Без номера:", [(p["name"], p["length"]) for p in pistes if p["number"] is None])
    print("Подъёмники:", [(l["code"], l["name"]) for l in lifts])
    print("Значки трасс, высота камеры:", sorted(((p["show"], p["number"]) for p in longest.values()), reverse=True))
    print("Значки подъёмников:", sorted(((l["show"], l["code"]) for l in lifts if l["code"]), reverse=True))
    print("Зоны:", zones)
    print("Размер файла:", OUT.stat().st_size, "байт")


if __name__ == "__main__":
    main()
