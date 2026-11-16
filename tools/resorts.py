#!/usr/bin/env python3
"""Каталог курортов для зачёта сезона: трассы и подъёмники из OpenStreetMap.

  python3 tools/resorts.py --fetch   скачать районы из tools/resort_regions.json в data/osm-resorts/<id>.json
                                     (Overpass; запускается в GitHub Actions, workflow «Курорты»)
  python3 tools/resorts.py           собрать server/config/resorts.json из скачанного

Курорт = группа трасс и подъёмников, которые лежат рядом друг с другом (не дальше 400 м).
Имя берётся у ближайшей области landuse=winter_sports с именем.
Данные © участники OpenStreetMap, лицензия ODbL.
"""

import json
import math
import pathlib
import re
import sys
import time
import unicodedata
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
REGIONS = ROOT / "tools" / "resort_regions.json"
RAW = ROOT / "data" / "osm-resorts"
OUT = ROOT / "server" / "config" / "resorts.json"

SERVERS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
]

JOIN_M = 400          # трассы и подъёмники ближе этого — один курорт
MIN_TRAIL_M = 150     # короче — не трасса для короны
MARGIN_M = 300        # запас территории вокруг крайних трасс
STEP_M = 15           # точки трассы не чаще этого
LIFT_KINDS = {"gondola", "cable_car", "chair_lift", "mixed_lift", "drag_lift", "t-bar", "j-bar", "platter", "rope_tow", "magic_carpet"}
DIFFICULTY = {"novice": "green", "easy": "green", "intermediate": "blue", "advanced": "red", "expert": "black", "freeride": "black", "extreme": "black"}


def query(bbox):
    box = ",".join(str(x) for x in bbox)
    return f"""
[out:json][timeout:120];
(
  way["piste:type"="downhill"]({box});
  way["aerialway"]({box});
  way["landuse"="winter_sports"]["name"]({box});
  relation["landuse"="winter_sports"]["name"]({box});
);
out tags geom;
"""


def fetch(text):
    body = urllib.parse.urlencode({"data": text}).encode()
    last = None
    for attempt in range(3):
        for server in SERVERS:
            try:
                request = urllib.request.Request(server, data=body, headers={"User-Agent": "idre-cup/0.1 (github.com/iDemonter/idre-cup)"})
                with urllib.request.urlopen(request, timeout=180) as response:
                    return json.load(response)
            except Exception as error:  # noqa: BLE001 - пробуем следующий сервер
                last = error
                print(f"{server}: {error}", file=sys.stderr)
        time.sleep(15 * (attempt + 1))
    raise SystemExit(f"Overpass недоступен: {last}")


def download():
    RAW.mkdir(parents=True, exist_ok=True)
    for region in json.loads(REGIONS.read_text(encoding="utf-8"))["regions"]:
        elements = fetch(query(region["bbox"])).get("elements", [])
        if not elements:
            raise SystemExit(f"{region['name']}: пустой ответ")
        path = RAW / f"{region['id']}.json"
        path.write_text(json.dumps({"source": "OpenStreetMap, ODbL", "bbox": region["bbox"], "elements": elements}, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        print(f"{region['name']}: {len(elements)} объектов → {path}")
        time.sleep(5)


def dist(a, b):
    dy = (a[0] - b[0]) * 111_320
    dx = (a[1] - b[1]) * 111_320 * math.cos(math.radians((a[0] + b[0]) / 2))
    return math.hypot(dx, dy)


def length(points):
    return sum(dist(points[i - 1], points[i]) for i in range(1, len(points)))


def thin(points):
    """Точки не чаще STEP_M, концы сохраняются."""
    kept = [points[0]]
    for point in points[1:-1]:
        if dist(kept[-1], point) >= STEP_M:
            kept.append(point)
    kept.append(points[-1])
    return [[round(p[0], 5), round(p[1], 5)] for p in kept]


def sample(points, every=100):
    out = [points[0]]
    for point in points[1:]:
        if dist(out[-1], point) >= every:
            out.append(point)
    out.append(points[-1])
    return out


def slug(text):
    text = unicodedata.normalize("NFKD", text.lower())
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    return re.sub(r"[^a-z0-9]+", "-", text).strip("-")


def geometry(element):
    if element.get("geometry"):
        return [(p["lat"], p["lon"]) for p in element["geometry"]]
    points = []
    for member in element.get("members", []):
        points += [(p["lat"], p["lon"]) for p in member.get("geometry", [])]
    return points


def build_region(region, elements):
    items, areas = [], []
    for element in elements:
        tags = element.get("tags", {})
        points = geometry(element)
        if len(points) < 2:
            continue
        if tags.get("landuse") == "winter_sports":
            areas.append({"name": tags["name"], "points": points})
        elif tags.get("piste:type") == "downhill" and tags.get("area") != "yes":
            items.append({"kind": "piste", "id": element["id"], "tags": tags, "points": points})
        elif tags.get("aerialway") in LIFT_KINDS:
            items.append({"kind": "lift", "id": element["id"], "tags": tags, "points": points})

    # Группы: объединение по близости точек.
    parent = list(range(len(items)))

    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    samples = [sample(item["points"]) for item in items]
    boxes = [(min(p[0] for p in s), min(p[1] for p in s), max(p[0] for p in s), max(p[1] for p in s)) for s in samples]
    pad = JOIN_M / 111_320 * 2.2
    for i in range(len(items)):
        for j in range(i + 1, len(items)):
            a, b = boxes[i], boxes[j]
            if a[0] - pad > b[2] or b[0] - pad > a[2] or a[1] - pad * 2 > b[3] or b[1] - pad * 2 > a[3]:
                continue
            if root(i) != root(j) and any(dist(p, q) <= JOIN_M for p in samples[i] for q in samples[j]):
                parent[root(i)] = root(j)

    groups = {}
    for index, item in enumerate(items):
        groups.setdefault(root(index), []).append(item)

    resorts = []
    for members in groups.values():
        pistes = [m for m in members if m["kind"] == "piste"]
        if not pistes or sum(length(p["points"]) for p in pistes) < 300:
            continue
        everything = [p for m in members for p in m["points"]]
        lat0 = (min(p[0] for p in everything) + max(p[0] for p in everything)) / 2
        lon0 = (min(p[1] for p in everything) + max(p[1] for p in everything)) / 2
        center = (lat0, lon0)
        radius = max(dist(center, p) for p in everything) + MARGIN_M

        # Имя: область winter_sports, ближайшая к середине (по ближайшей точке её границы).
        name = None
        best = 3000.0
        for area in areas:
            gap = min(dist(center, p) for p in sample(area["points"], 50))
            inside = (min(p[0] for p in area["points"]) <= lat0 <= max(p[0] for p in area["points"])
                      and min(p[1] for p in area["points"]) <= lon0 <= max(p[1] for p in area["points"]))
            if inside:
                gap = 0
            if gap < best:
                best, name = gap, area["name"]
        if name is None:
            named = sorted((length(p["points"]), p["tags"].get("name")) for p in pistes if p["tags"].get("name"))
            name = f"{region['name']} · {named[-1][1]}" if named else region["name"]

        # Трассы: по имени или номеру самая длинная линия.
        trails = {}
        for piste in pistes:
            tags = piste["tags"]
            ref = (tags.get("piste:ref") or tags.get("ref") or "").strip()
            title = (tags.get("piste:name") or tags.get("name") or "").strip()
            if not ref and not title:
                continue
            key = ref or slug(title)
            meters = length(piste["points"])
            if meters < MIN_TRAIL_M:
                continue
            if key in trails and trails[key]["length"] >= meters:
                continue
            trails[key] = {
                "key": key,
                "ref": ref or None,
                "name": title or None,
                "difficulty": DIFFICULTY.get(tags.get("piste:difficulty", ""), "unknown"),
                "length": round(meters),
                "coords": thin(piste["points"]),
            }
        lifts = [
            {"name": m["tags"].get("name"), "kind": m["tags"]["aerialway"], "coords": thin(m["points"])}
            for m in members if m["kind"] == "lift"
        ]
        resorts.append({
            "name": name,
            "region": region["name"],
            "center": [round(lat0, 5), round(lon0, 5)],
            "radiusKm": round(radius / 1000, 2),
            "trails": sorted(trails.values(), key=lambda t: (t["ref"] is None, int(t["ref"]) if (t["ref"] or "").isdigit() else 0, t["ref"] or "", t["name"] or "")),
            "lifts": lifts,
        })

    # Одинаковые имена у соседних групп: склеиваем в одно имя с номером.
    seen = {}
    for resort in sorted(resorts, key=lambda r: -len(r["trails"])):
        count = seen.get(resort["name"], 0)
        seen[resort["name"]] = count + 1
        base = slug(resort["name"]) or region["id"]
        resort["id"] = base if count == 0 else f"{base}-{count + 1}"
        for trail in resort["trails"]:
            trail["id"] = f"{resort['id']}:{trail.pop('key')}"
    return resorts


def build():
    regions = json.loads(REGIONS.read_text(encoding="utf-8"))["regions"]
    result = []
    for region in regions:
        path = RAW / f"{region['id']}.json"
        if not path.exists():
            print(f"{region['name']}: нет {path}, пропускаю (сначала --fetch)")
            continue
        found = build_region(region, json.loads(path.read_text(encoding="utf-8"))["elements"])
        for resort in sorted(found, key=lambda r: -len(r["trails"])):
            print(f"{region['name']}: {resort['id']} «{resort['name']}» трасс {len(resort['trails'])}, подъёмников {len(resort['lifts'])}, радиус {resort['radiusKm']} км")
        result += found
    ids = [r["id"] for r in result]
    dup = {i for i in ids if ids.count(i) > 1}
    for resort in result:
        if resort["id"] in dup:
            resort["id"] = f"{resort['id']}-{slug(resort['region'])}"
            for trail in resort["trails"]:
                trail["id"] = resort["id"] + ":" + trail["id"].split(":", 1)[1]
    OUT.write_text(json.dumps({"source": "OpenStreetMap, ODbL", "resorts": result}, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"Курортов: {len(result)}, {OUT.stat().st_size // 1024} КБ → {OUT}")


if __name__ == "__main__":
    if "--fetch" in sys.argv:
        download()
    build()
