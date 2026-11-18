#!/usr/bin/env python3
"""Трассы и подъёмники для 3D-модели другого курорта (не Idre).

Берёт трассы и подъёмники курорта из каталога сезона (server/config/resorts.json, собирает
tools/resorts.py из OpenStreetMap, номера и названия сверены с сайтом курорта), зоны и вершины —
из tools/models.json, вершины с высотой — ещё и из окружения data/osm-land-<курорт>.json.
Результат: app/IdreCup/Resources/pistes-<курорт>.json в том же виде, что pistes.json у Idre.

Запуск: python3 tools/build_resort_pistes.py are
"""

import json
import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MODEL_ID = sys.argv[1]
MODEL = json.loads((ROOT / "tools" / "models.json").read_text(encoding="utf-8"))[MODEL_ID]
CATALOG = ROOT / "server" / "config" / "resorts.json"
APPROX = ROOT / "tools" / "official" / "approx.json"
LAND = ROOT / "data" / f"osm-land-{MODEL_ID}.json"
OUT = ROOT / "app" / "IdreCup" / "Resources" / f"pistes-{MODEL_ID}.json"

SUMMIT = MODEL["summit"]
LON_M = 111320 * math.cos(math.radians(SUMMIT[0]))
WEST, EAST, SOUTH, NORTH = MODEL["bounds"]
MARGIN = 300   # трасса должна целиком лежать на модели с запасом от края, м


def local(point):
    return ((point[1] - SUMMIT[1]) * LON_M, (point[0] - SUMMIT[0]) * 111320)


def on_model(coords):
    return all(WEST + MARGIN <= x <= EAST - MARGIN and SOUTH + MARGIN <= y <= NORTH - MARGIN for x, y in map(local, coords))


def length(coords):
    points = [local(p) for p in coords]
    return round(sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(points, points[1:])))


def middle(coords):
    """Точка на середине пути по линии."""
    points = [local(p) for p in coords]
    total = sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(points, points[1:]))
    walked = 0.0
    for a, b, pa, pb in zip(points, points[1:], coords, coords[1:]):
        step = math.hypot(b[0] - a[0], b[1] - a[1])
        if walked + step >= total / 2 and step > 0:
            t = (total / 2 - walked) / step
            return [round(pa[0] + (pb[0] - pa[0]) * t, 6), round(pa[1] + (pb[1] - pa[1]) * t, 6)]
        walked += step
    return coords[len(coords) // 2]


def to_geo(east, north):
    return [round(SUMMIT[0] + north / 111320, 6), round(SUMMIT[1] + east / LON_M, 6)]


def along(coords, offset, trim=(0.0, 1.0)):
    """Линия вдоль подъёмника со сдвигом offset метров (плюс — влево по ходу), обрезанная по долям длины."""
    points = [local(p) for p in coords]
    total = sum(math.dist(a, b) for a, b in zip(points, points[1:]))
    start, end = trim[0] * total, trim[1] * total
    result, walked = [], 0.0
    steps = max(4, int(total / 60))
    for i in range(steps + 1):
        want = start + (end - start) * i / steps
        walked, here = 0.0, None
        for a, b in zip(points, points[1:]):
            step = math.dist(a, b)
            if walked + step >= want and step > 0:
                t = (want - walked) / step
                dx, dy = (b[0] - a[0]) / step, (b[1] - a[1]) / step
                here = (a[0] + dx * step * t - dy * offset, a[1] + dy * step * t + dx * offset)
                break
            walked += step
        if here is None:
            a, b = points[-2], points[-1]
            step = math.dist(a, b) or 1
            dx, dy = (b[0] - a[0]) / step, (b[1] - a[1]) / step
            here = (b[0] - dy * offset, b[1] + dx * offset)
        result.append(to_geo(*here))
    return result


def nearest_zone(point):
    zones = MODEL.get("zones", [])
    if not zones:
        return None
    here = local(point)
    return min(zones, key=lambda z: math.dist(here, local(z["center"])))["name"]


def main() -> None:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    resort = dict(next(r for r in catalog["resorts"] if r["id"] == MODEL["resort"]))
    # Соседние курорты каталога на той же модели (Vargliften у Vemdalsskalet).
    for extra in MODEL.get("extraResorts", []):
        other = next(r for r in catalog["resorts"] if r["id"] == extra)
        resort["trails"] = resort["trails"] + other["trails"]
        resort["lifts"] = resort["lifts"] + other["lifts"]

    pistes = []
    for trail in resort["trails"]:
        coords = trail["coords"]
        if len(coords) < 2 or not on_model(coords):
            continue
        ref = trail.get("ref")
        pistes.append({
            "id": len(pistes) + 1,
            "number": None,
            "display": ref,
            "resort": MODEL_ID,
            "name": trail.get("name"),
            "zone": nearest_zone(middle(coords)),
            "difficulty": trail.get("difficulty") or "unknown",
            "extreme": False,
            "lit": False,
            "length": trail.get("length") or length(coords),
            "label": False,
            "mid": middle(coords),
            "coords": coords,
        })
    # Трассы, которых нет в OpenStreetMap: нарисованы от руки по официальной карте (tools/official/approx.json).
    approx = json.loads(APPROX.read_text(encoding="utf-8")).get(MODEL_ID, []) if APPROX.exists() else []
    lifts_by_name = {lift.get("name"): lift["coords"] for lift in resort["lifts"]}
    for trail in approx:
        if "points" in trail:
            coords = trail["points"]
        else:
            spec = trail["along"]
            coords = along(lifts_by_name[spec["lift"]], spec["offset"], tuple(spec.get("trim", (0.0, 1.0))))
        pistes.append({
            "id": len(pistes) + 1,
            "number": None,
            "display": trail["ref"],
            "resort": MODEL_ID,
            "name": trail["name"],
            "zone": nearest_zone(middle(coords)),
            "difficulty": trail["difficulty"],
            "extreme": False,
            "lit": False,
            "length": length(coords),
            "label": False,
            "approx": True,
            "mid": middle(coords),
            "coords": coords,
        })

    # Значок с номером — один на трассу (по номеру или имени), на самом длинном участке.
    # Короткие трассы видны только вблизи, чтобы значки не слипались.
    groups = {}
    for piste in pistes:
        key = piste["display"] or piste["name"]
        if key:
            groups.setdefault(key, []).append(piste)
    for group in groups.values():
        main_piste = max(group, key=lambda p: p["length"])
        main_piste["label"] = True
        main_piste["show"] = 9_000 if main_piste["length"] > 1_500 else 5_500 if main_piste["length"] > 700 else 3_500
        for piste in group:
            if piste is not main_piste:
                piste["alt"] = True

    lifts = []
    for lift in resort["lifts"]:
        coords = lift["coords"]
        if len(coords) < 2 or not on_model(coords):
            continue
        name = lift.get("name") or ""
        code, _, rest = name.partition(" - ")
        if not rest:
            code, rest = None, name or None
        lifts.append({
            "id": len(lifts) + 1,
            "code": code,
            "name": rest,
            "kind": lift.get("kind") or "unknown",
            "length": length(coords),
            "show": 6_000 if length(coords) > 1_000 else 3_500,
            "mid": middle(coords),
            "coords": coords,
        })

    peaks = list(MODEL.get("peaks", []))
    if LAND.exists():
        for element in json.loads(LAND.read_text(encoding="utf-8"))["elements"]:
            tags = element.get("tags", {})
            if tags.get("natural") != "peak" or not tags.get("name") or element["type"] != "node":
                continue
            try:
                height = round(float(tags.get("ele", "").replace(",", ".")))
            except ValueError:
                continue
            at = [element["lat"], element["lon"]]
            if not on_model([at]) or any(p["name"] == tags["name"] for p in peaks):
                continue
            peaks.append({"name": tags["name"], "height": height, "at": at})
    peaks.sort(key=lambda p: -p["height"])
    peaks = peaks[:6]

    result = {
        "source": "Трассы и подъёмники: © участники OpenStreetMap (ODbL), номера и названия сверены с сайтом курорта.",
        "summit": SUMMIT,
        "zones": MODEL.get("zones", []),
        "pistes": pistes,
        "lifts": lifts,
        "peaks": peaks,
    }
    OUT.write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"{MODEL['name']}: трасс {len(pistes)}, из них примерных {len(approx)} (значков {sum(p['label'] for p in pistes)}), "
          f"подъёмников {len(lifts)}, вершин {len(peaks)} → {OUT}")


if __name__ == "__main__":
    main()
