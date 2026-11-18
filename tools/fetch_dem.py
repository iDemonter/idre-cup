#!/usr/bin/env python3
"""Скачивает высоты района курорта из модели Copernicus DEM GLO-30.

Запускается в GitHub Actions: workflow «Данные высот» (Idre) и «3D-модель курорта» (остальные).
Курорт — первый аргумент, по умолчанию idre (см. tools/models.json). Результат кладётся в
data/dem-<курорт>.json: сетка высот в метрах с шагом около 30 м.

Данные: Copernicus DEM GLO-30. © DLR e.V. 2010-2014 и © Airbus Defence and Space GmbH
2014-2018, предоставлены по программе COPERNICUS Европейским союзом и ESA.
"""

import json
import pathlib
import sys

import rasterio
from rasterio.windows import from_bounds

ROOT = pathlib.Path(__file__).resolve().parent.parent
MODEL_ID = sys.argv[1] if len(sys.argv) > 1 else "idre"
MODEL = json.loads((ROOT / "tools" / "models.json").read_text(encoding="utf-8"))[MODEL_ID]

# Рамка вокруг курорта: запад, юг, восток, север.
WEST, SOUTH, EAST, NORTH = MODEL["demBox"]

# Плитки Copernicus по одному градусу: «N61_00_E012_00». Если курорт на стыке плиток — список.
TILES = MODEL["demTile"] if isinstance(MODEL["demTile"], list) else [MODEL["demTile"]]


def url(tile: str) -> str:
    return f"https://copernicus-dem-30m.s3.amazonaws.com/Copernicus_DSM_COG_10_{tile}_DEM/Copernicus_DSM_COG_10_{tile}_DEM.tif"


OUT = ROOT / "data" / f"dem-{MODEL_ID}.json"


def main() -> None:
    if len(TILES) == 1:
        with rasterio.open(url(TILES[0])) as source:
            window = from_bounds(WEST, SOUTH, EAST, NORTH, source.transform).round_offsets().round_lengths()
            heights = source.read(1, window=window)
            transform = source.window_transform(window)
    else:
        from rasterio.merge import merge
        sources = [rasterio.open(url(tile)) for tile in TILES]
        mosaic, transform = merge(sources, bounds=(WEST, SOUTH, EAST, NORTH))
        heights = mosaic[0]
        for source in sources:
            source.close()

    rows, cols = heights.shape
    result = {
        "source": "Copernicus DEM GLO-30",
        # Центр левого верхнего узла сетки и шаг в градусах.
        "west": round(transform.c + transform.a / 2, 7),
        "north": round(transform.f + transform.e / 2, 7),
        "dlon": round(transform.a, 9),
        "dlat": round(-transform.e, 9),
        "cols": cols,
        "rows": rows,
        # Строки с севера на юг, в строке с запада на восток. Высота в метрах.
        "heights": [round(float(value), 1) for value in heights.flatten()],
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, separators=(",", ":")), encoding="utf-8")
    print(f"Сохранено {cols}×{rows} узлов, высоты от {heights.min():.0f} до {heights.max():.0f} м → {OUT}")


if __name__ == "__main__":
    main()
