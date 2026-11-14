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

# Рамка вокруг курорта: юг, запад, север, восток.
BBOX = "61.85,12.76,61.93,12.95"

QUERY = f"""
[out:json][timeout:60];
(
  way["piste:type"="downhill"]({BBOX});
  relation["piste:type"="downhill"]({BBOX});
  way["aerialway"]({BBOX});
  node["natural"="peak"]({BBOX});
);
out tags geom;
"""

SERVERS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
]

OUT = pathlib.Path(__file__).resolve().parent.parent / "data" / "osm-idre.json"


def fetch() -> dict:
    body = urllib.parse.urlencode({"data": QUERY}).encode()
    last_error = None
    for attempt in range(3):
        for server in SERVERS:
            try:
                request = urllib.request.Request(
                    server, data=body, headers={"User-Agent": "idre-cup/0.1 (github.com/iDemonter/idre-cup)"}
                )
                with urllib.request.urlopen(request, timeout=90) as response:
                    return json.load(response)
            except Exception as error:  # noqa: BLE001 - пробуем следующий сервер
                last_error = error
                print(f"{server}: {error}", file=sys.stderr)
        time.sleep(10 * (attempt + 1))
    raise SystemExit(f"Overpass недоступен: {last_error}")


def main() -> None:
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


if __name__ == "__main__":
    main()
