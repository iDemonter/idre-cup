#!/usr/bin/env python3
"""Каталог курортов для зачёта сезона: трассы и подъёмники из OpenStreetMap.

  python3 tools/resorts.py --fetch   скачать районы из tools/resort_regions.json в data/osm-resorts/<id>.json
                                     (Overpass; запускается в GitHub Actions, workflow «Курорты»)
  python3 tools/resorts.py           собрать server/config/resorts.json из скачанного

Курорт = группа трасс и подъёмников, которые лежат рядом друг с другом (не дальше 400 м).
Имя берётся у ближайшей области landuse=winter_sports с именем.
Данные © участники OpenStreetMap, лицензия ODbL.
"""

import difflib
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
OFFICIAL = ROOT / "tools" / "official" / "trails.json"
REPORT = ROOT / "tools" / "official" / "report.md"
LEVEL = {"g": "green", "b": "blue", "r": "red", "s": "black", "o": "park"}

SERVERS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
]

JOIN_M = 400          # трассы и подъёмники ближе этого — один курорт
MIN_TRAIL_M = 80      # короче — не трасса для короны (на горках Стокгольма трассы по 100–150 м)
MARGIN_M = 300        # запас территории вокруг крайних трасс
STEP_M = 15           # точки трассы не чаще этого
LIFT_KINDS = {"gondola", "cable_car", "chair_lift", "mixed_lift", "drag_lift", "t-bar", "j-bar", "platter", "rope_tow", "magic_carpet"}
# Как в Швеции и Европе: grön = mycket lätt (novice), blå = lätt (easy), röd = medelsvår (intermediate), svart = svår.
DIFFICULTY = {"novice": "green", "easy": "blue", "intermediate": "red", "advanced": "black", "expert": "black", "freeride": "black", "extreme": "black"}


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
        # Своё имя из tools/resort_regions.json: точка, которая лежит внутри этого курорта.
        own = [(dist(center, item["at"]), item["name"]) for item in region.get("names", []) if dist(center, item["at"]) <= radius]
        if own:
            name = min(own)[1]
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


def norm(text):
    text = unicodedata.normalize("NFKD", (text or "").lower())
    return re.sub(r"[^a-z0-9]", "", "".join(ch for ch in text if not unicodedata.combining(ch)))


def apply_official(resorts):
    """Номера, названия и цвета с сайта курорта (tools/official/trails.json). Линии остаются из OpenStreetMap."""
    official = json.loads(OFFICIAL.read_text(encoding="utf-8"))["resorts"] if OFFICIAL.exists() else {}
    lines = ["# Сверка трасс с официальными списками", "", "Собирает tools/resorts.py. Линии трасс из OpenStreetMap, номера, названия и цвета с сайтов курортов.", ""]
    for resort in resorts:
        entry = official.get(resort["id"])
        if not entry:
            lines.append(f"## {resort['name']}: официального списка нет, всё из OpenStreetMap ({len(resort['trails'])} трасс)\n")
            continue
        wanted = entry["trails"]
        by_ref = {w["ref"]: w for w in wanted if w["ref"]}
        by_name = {norm(w["name"]): w for w in wanted}
        found, extra = {}, []
        for trail in resort["trails"]:
            match = None
            if trail["ref"] and trail["ref"] in by_ref:
                # Номер совпал: название могло быть с опечаткой или сокращено («Tusenmetern»).
                match = by_ref[trail["ref"]]
            if not match and trail["name"]:
                key = norm(trail["name"])
                match = by_name.get(key)
                if not match:
                    near = [w for n, w in by_name.items() if len(n) >= 5 and (n in key or key in n)]
                    if len(near) == 1:
                        match = near[0]
                if not match:
                    # Опечатки: «Vildmarsstigen» → «Vildmarksstigen», «Vargbacken» → «Vargenbacken».
                    scored = sorted((difflib.SequenceMatcher(None, key, n).ratio(), n) for n in by_name)
                    if scored and scored[-1][0] >= 0.88:
                        match = by_name[scored[-1][1]]
            if not match and trail["ref"] and trail["ref"] in by_ref and not trail["name"]:
                match = by_ref[trail["ref"]]
            if not match:
                extra.append(trail)
                continue
            mkey = match["ref"] or norm(match["name"])
            if mkey in found and found[mkey]["length"] >= trail["length"]:
                continue
            trail["ref"], trail["name"] = match["ref"], match["name"]
            if LEVEL[match["level"]] != "park":
                trail["difficulty"] = LEVEL[match["level"]]
            trail["official"] = True
            trail["id"] = f"{resort['id']}:{match['ref'] or slug(match['name'])}"
            found[mkey] = trail
        missing = [w for w in wanted if (w["ref"] or norm(w["name"])) not in found]
        # Оставляем официальные трассы и те из OpenStreetMap, которых нет в списке (их помечаем).
        resort["trails"] = sorted(found.values(), key=lambda t: (int(t["ref"]) if (t["ref"] or "").isdigit() else 9999, t["name"] or "")) + extra
        lines.append(f"## {resort['name']}: совпало {len(found)} из {len(wanted)}")
        lines.append(f"Источник: {entry['source']}, проверено {entry['checked']}.")
        if missing:
            lines.append("- Нет линии в OpenStreetMap (в зачёт и на карту не попадут): " + ", ".join(f"{w['ref'] or ''} {w['name']}".strip() for w in missing))
        if extra:
            lines.append("- Есть в OpenStreetMap, нет в официальном списке (оставлены как есть): " + ", ".join(f"{t['ref'] or ''} {t['name'] or ''}".strip() for t in extra))
        lines.append("")
    return "\n".join(lines)


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
    report = apply_official(result)
    REPORT.write_text(report, encoding="utf-8")
    print(report)
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
