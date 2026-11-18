#!/usr/bin/env python3
"""Скачивает трассы и подъёмники Idre Fjäll из OpenStreetMap (Overpass API).

Запускается в GitHub Actions: workflow «Данные трасс». Результат кладётся в
data/osm-idre.json. Данные © участники OpenStreetMap, лицензия ODbL.
"""

import json
import pathlib
import sys
import time
import urllib.parse
import urllib.request

# Рамка вокруг Idre Fjäll, соседнего Idre Himmelfjäll и вершины Städjan: юг, запад, север, восток.
BBOX = "61.85,12.715,61.945,12.95"

QUERY = f"""
[out:json][timeout:60];
(
  way["piste:type"]["piste:type"!="nordic"]({BBOX});
  relation["piste:type"]["piste:type"!="nordic"]({BBOX});
  way["aerialway"]({BBOX});
  node["natural"="peak"]({BBOX});
);
out tags geom;
"""

# Окружение для 3D-модели: лес, вода, дома, дороги и полезные места в границах модели.
LAND_BBOX = "61.869,12.730,61.931,12.894"

def land_query(bbox: str, peaks: bool = False) -> str:
    extra = f'  node["natural"="peak"]({bbox});\n' if peaks else ""
    return f"""
[out:json][timeout:120];
(
  way["natural"~"^(wood|water|scrub|heath|fell|bare_rock|wetland|grassland)$"]({bbox});
  relation["natural"~"^(wood|water|scrub|heath|fell|bare_rock|wetland|grassland)$"]({bbox});
  way["landuse"~"^(forest|residential|commercial|retail|winter_sports|recreation_ground)$"]({bbox});
  relation["landuse"~"^(forest|residential|commercial|retail|winter_sports|recreation_ground)$"]({bbox});
  way["building"]({bbox});
  way["highway"~"^(primary|secondary|tertiary|unclassified|residential|service|living_street|pedestrian)$"]({bbox});
  nwr["amenity"]({bbox});
  nwr["shop"]({bbox});
  nwr["tourism"]({bbox});
  nwr["leisure"]({bbox});
  nwr["sport"]({bbox});
  node["place"]({bbox});
{extra});
out tags geom;
"""


LAND_QUERY = land_query(LAND_BBOX)

SERVERS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
]

OUT = pathlib.Path(__file__).resolve().parent.parent / "data" / "osm-idre.json"
OUT_LAND = OUT.with_name("osm-land.json")


def fetch(query: str = QUERY) -> dict:
    body = urllib.parse.urlencode({"data": query}).encode()
    last_error = None
    for attempt in range(3):
        for server in SERVERS:
            try:
                request = urllib.request.Request(
                    server, data=body, headers={"User-Agent": "idre-cup/0.1 (github.com/iDemonter/idre-cup)"}
                )
                with urllib.request.urlopen(request, timeout=150) as response:
                    return json.load(response)
            except Exception as error:  # noqa: BLE001 - пробуем следующий сервер
                last_error = error
                print(f"{server}: {error}", file=sys.stderr)
        time.sleep(10 * (attempt + 1))
    raise SystemExit(f"Overpass недоступен: {last_error}")


def other_model(model_id: str) -> None:
    """Только окружение (лес, вода, дома, места, вершины) для модели другого курорта:
    его трассы берутся из каталога курортов. Результат: data/osm-land-<курорт>.json."""
    models = json.loads((OUT.parent.parent / "tools" / "models.json").read_text(encoding="utf-8"))
    south, west, north, east = models[model_id]["landBox"]
    bbox = f"{south},{west},{north},{east}"
    land = fetch(land_query(bbox, peaks=True)).get("elements", [])
    if not land:
        raise SystemExit("Overpass вернул пустое окружение")
    out = OUT.with_name(f"osm-land-{model_id}.json")
    out.write_text(
        json.dumps({"source": "OpenStreetMap, ODbL", "bbox": bbox, "elements": land}, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    print(f"Окружение {model_id}: {len(land)} объектов → {out}")


def main() -> None:
    if len(sys.argv) > 1 and sys.argv[1] != "idre":
        other_model(sys.argv[1])
        return
    data = fetch()
    elements = data.get("elements", [])
    if not elements:
        raise SystemExit("Overpass вернул пустой ответ")
    # Служебные поля с временем запроса убираем, чтобы файл не менялся без причины.
    result = {"source": "OpenStreetMap, ODbL", "bbox": BBOX, "elements": elements}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    kinds = {}
    for element in elements:
        tags = element.get("tags", {})
        kind = "piste" if "piste:type" in tags else "lift" if "aerialway" in tags else "peak"
        kinds[kind] = kinds.get(kind, 0) + 1
    print(f"Сохранено {len(elements)} объектов: {kinds} → {OUT}")

    land = fetch(LAND_QUERY).get("elements", [])
    if not land:
        raise SystemExit("Overpass вернул пустое окружение")
    OUT_LAND.write_text(
        json.dumps({"source": "OpenStreetMap, ODbL", "bbox": LAND_BBOX, "elements": land}, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    print(f"Окружение: {len(land)} объектов → {OUT_LAND}")


if __name__ == "__main__":
    main()
