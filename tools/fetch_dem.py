#!/usr/bin/env python3
"""Скачивает высоты района Idre Fjäll из модели Copernicus DEM GLO-30.

Запускается в GitHub Actions: workflow «Данные высот». Результат кладётся в
data/dem-idre.json: сетка высот в метрах с шагом около 30 м.

Данные: Copernicus DEM GLO-30. © DLR e.V. 2010-2014 и © Airbus Defence and Space GmbH
2014-2018, предоставлены по программе COPERNICUS Европейским союзом и ESA.
"""

import json
import pathlib

import rasterio
from rasterio.windows import from_bounds

# Рамка вокруг Idre Fjäll, Idre Himmelfjäll и вершины Städjan: запад, юг, восток, север.
WEST, SOUTH, EAST, NORTH = 12.715, 61.855, 12.945, 61.945

URL = (
    "https://copernicus-dem-30m.s3.amazonaws.com/"
    "Copernicus_DSM_COG_10_N61_00_E012_00_DEM/Copernicus_DSM_COG_10_N61_00_E012_00_DEM.tif"
)

OUT = pathlib.Path(__file__).resolve().parent.parent / "data" / "dem-idre.json"


def main() -> None:
    with rasterio.open(URL) as source:
        window = from_bounds(WEST, SOUTH, EAST, NORTH, source.transform).round_offsets().round_lengths()
        heights = source.read(1, window=window)
        transform = source.window_transform(window)

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
