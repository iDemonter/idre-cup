import CoreLocation
import Foundation

/// Сетка высот горы из файла Resources/terrain.json (собирает tools/build_terrain.py).
/// Высоты: Copernicus DEM GLO-30. Координаты: метры на восток и на север от вершины.
struct TerrainData: Decodable {
    /// Западный и северный край сетки, метры от вершины.
    let west: Double
    let north: Double
    /// Шаг сетки в метрах.
    let step: Double
    let cols: Int
    let rows: Int
    /// Высота над уровнем моря, от которой отсчитаны heights.
    let base: Double
    /// Во сколько раз в модели вытянута высота.
    let exaggeration: Double
    /// Высота над base в дециметрах. Строки с севера на юг, в строке с запада на восток.
    let heights: [Int]

    /// name: «terrain» у Idre, «terrain-are» у Åre (см. ResortModel).
    static func load(_ name: String = "terrain") -> TerrainData? {
        guard
            let url = Bundle.main.url(forResource: name, withExtension: "json"),
            let raw = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(TerrainData.self, from: raw),
            decoded.cols > 1, decoded.rows > 1, decoded.heights.count == decoded.cols * decoded.rows
        else {
            return nil
        }
        return decoded
    }

    /// Настоящая высота над base в метрах в точке модели.
    func height(east: Double, north northing: Double) -> Double {
        let column = min(max((east - west) / step, 0), Double(cols - 1))
        let row = min(max((north - northing) / step, 0), Double(rows - 1))
        let c0 = min(Int(column), cols - 2)
        let r0 = min(Int(row), rows - 2)
        let fc = column - Double(c0)
        let fr = row - Double(r0)
        let top = value(r0, c0) * (1 - fc) + value(r0, c0 + 1) * fc
        let bottom = value(r0 + 1, c0) * (1 - fc) + value(r0 + 1, c0 + 1) * fc
        return top * (1 - fr) + bottom * fr
    }

    private func value(_ row: Int, _ column: Int) -> Double {
        Double(heights[row * cols + column]) / 10
    }

    /// Попадает ли точка на модель.
    func contains(east: Double, north northing: Double) -> Bool {
        east >= west && east <= west + Double(cols - 1) * step && northing <= north && northing >= north - Double(rows - 1) * step
    }
}

/// Перевод широты и долготы в метры от вершины. Те же формулы, что в tools/build_pistes.py.
struct LocalFrame {
    let origin: CLLocationCoordinate2D

    func local(_ pair: [Double]) -> (east: Double, north: Double) {
        guard pair.count == 2 else { return (0, 0) }
        let north = (pair[0] - origin.latitude) * 111_320
        let east = (pair[1] - origin.longitude) * 111_320 * cos(origin.latitude * .pi / 180)
        return (east, north)
    }

    func local(_ coordinate: CLLocationCoordinate2D) -> (east: Double, north: Double) {
        local([coordinate.latitude, coordinate.longitude])
    }

    /// Обратно: метры от вершины в широту и долготу.
    func coordinate(east: Double, north: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: origin.latitude + north / 111_320,
            longitude: origin.longitude + east / (111_320 * cos(origin.latitude * .pi / 180))
        )
    }
}

/// Положение камеры над моделью.
struct ModelCamera: Equatable {
    /// Номер запроса: камера двигается, когда он меняется.
    var id: Int
    /// Куда смотрит камера, метры от вершины.
    var east: Double
    var north: Double
    /// Расстояние до точки в метрах.
    var distance: Double
    /// Курс взгляда, градусы от севера по часовой стрелке.
    var heading: Double
    /// Наклон: 0 = строго сверху, 90 = вдоль земли.
    var pitch: Double
}
