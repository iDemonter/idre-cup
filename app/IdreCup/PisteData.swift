import CoreLocation
import SwiftUI

/// Трассы и подъёмники Idre Fjäll из файла Resources/pistes.json.
/// Геометрия: © участники OpenStreetMap (ODbL). Номера и сложность: карта трасс курорта 2026/27.
struct PisteData: Decodable {
    let source: String
    let summit: [Double]
    let zones: [Zone]
    let pistes: [Piste]
    let lifts: [Lift]

    /// Вершины с высотой: подписываются на карте.
    let peaks: [Peak]?

    static let empty = PisteData(source: "", summit: [61.88814, 12.85871], zones: [], pistes: [], lifts: [], peaks: nil)

    /// name: «pistes» у Idre, «pistes-are» у Åre (см. ResortModel).
    static func load(_ name: String = "pistes") -> PisteData {
        guard
            let url = Bundle.main.url(forResource: name, withExtension: "json"),
            let raw = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(PisteData.self, from: raw)
        else {
            return .empty
        }
        return decoded
    }

    var summitCoordinate: CLLocationCoordinate2D { Self.coordinate(summit) }

    /// Трассы, на которых стоит значок с номером: по одной на номер.
    var labelled: [Piste] { pistes.filter { $0.label } }

    /// Трассы со светлой обводкой: все, кроме нарисованных пунктиром.
    var outlinedPistes: [Piste] { pistes.filter { !$0.isApproximate } }

    /// Подъёмники с буквой из официальной карты.
    var codedLifts: [Lift] { lifts.filter { $0.code != nil } }

    static func coordinate(_ pair: [Double]) -> CLLocationCoordinate2D {
        guard pair.count == 2 else { return CLLocationCoordinate2D(latitude: 0, longitude: 0) }
        return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
    }
}

struct Zone: Decodable, Identifiable {
    let name: String
    let center: [Double]
    /// Курс камеры: от подножия зоны к вершине.
    let heading: Double

    var id: String { name }
    var coordinate: CLLocationCoordinate2D { PisteData.coordinate(center) }
}

/// Вершина: имя, высота над морем в метрах и место.
struct Peak: Decodable, Identifiable {
    let name: String
    let height: Int
    let at: [Double]

    var id: String { name }
    var coordinate: CLLocationCoordinate2D { PisteData.coordinate(at) }
    /// «Städjan · 1131 м».
    var title: String { "\(name) · \(height) м" }
}

struct Piste: Decodable, Identifiable {
    let id: Int
    /// Номер трассы. У соседнего Idre Himmelfjäll это 100 + номер с его карты: номера курортов совпадают.
    let number: Int?
    /// Что написано на значке, если это не number (трассы Himmelfjäll).
    let display: String?
    /// idre (или пусто) либо himmel.
    let resort: String?
    let name: String?
    let zone: String?
    /// green, blue, red, black или unknown.
    let difficulty: String
    let extreme: Bool
    let lit: Bool
    /// Длина участка в метрах.
    let length: Int
    let label: Bool
    /// Запасная ветка: идёт параллельно основной и в длину трассы не входит.
    let alt: Bool?
    /// Нарисована от руки по официальной карте, в OpenStreetMap её нет.
    let approx: Bool?
    /// Высота камеры в метрах, с которой значок виден: ближе значки не слипаются.
    let show: Double?
    let mid: [Double]
    let coords: [[Double]]

    var coordinates: [CLLocationCoordinate2D] { coords.map(PisteData.coordinate) }
    var midCoordinate: CLLocationCoordinate2D { PisteData.coordinate(mid) }
    var isAlternative: Bool { alt ?? false }
    var badgeText: String { display ?? number.map { String($0) } ?? "•" }
    var isApproximate: Bool { approx ?? false }

    /// Нарисованные от руки трассы показываем пунктиром.
    var stroke: StrokeStyle {
        StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: isApproximate ? [2, 7] : [])
    }

    /// Светлая обводка отделяет линию от леса на снимке. У чёрных трасс она шире.
    var outline: StrokeStyle {
        StrokeStyle(lineWidth: difficulty == "black" ? 7 : 6, lineCap: .round, lineJoin: .round)
    }

    var color: Color {
        switch difficulty {
        case "green": return Palette.pisteGreen
        case "blue": return Palette.pisteBlue
        case "red": return Palette.pisteRed
        case "black": return Palette.pisteBlack
        default: return Palette.textSecondary
        }
    }

    var difficultyName: String {
        if extreme { return "экстрим" }
        switch difficulty {
        case "green": return "очень лёгкая"
        case "blue": return "лёгкая"
        case "red": return "средняя"
        case "black": return "сложная"
        default: return "сложность не указана"
        }
    }
}

struct Lift: Decodable, Identifiable {
    let id: Int
    /// Буква подъёмника на официальной карте.
    let code: String?
    let name: String?
    let kind: String
    let length: Int
    /// Высота камеры в метрах, с которой буква видна.
    let show: Double?
    /// Где стоит буква. Нет в данных: берётся середина линии.
    let mid: [Double]?
    let coords: [[Double]]

    var coordinates: [CLLocationCoordinate2D] { coords.map(PisteData.coordinate) }

    /// Место значка на линии подъёмника.
    var midCoordinate: CLLocationCoordinate2D {
        if let mid { return PisteData.coordinate(mid) }
        guard let first = coords.first, let last = coords.last, first.count == 2, last.count == 2 else {
            return CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        if coords.count > 2 {
            return PisteData.coordinate(coords[coords.count / 2])
        }
        return CLLocationCoordinate2D(latitude: (first[0] + last[0]) / 2, longitude: (first[1] + last[1]) / 2)
    }
}
