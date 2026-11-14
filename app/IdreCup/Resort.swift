import CoreLocation
import MapKit
import SwiftUI

/// Курорт Idre Fjäll (гора Gränjåsvålen, вершина около 890 м).
/// Координаты вершины приблизительные: уточняем по первой сборке.
enum Resort {
    static let name = "Idre Fjäll"
    static let summit = CLLocationCoordinate2D(latitude: 61.8890, longitude: 12.8530)

    /// Готовые виды на гору. Курс камеры направлен на склон:
    /// чтобы увидеть северный склон, камера смотрит на юг, и так далее.
    enum ViewPreset: String, CaseIterable, Identifiable {
        case overview = "Обзор"
        case vast = "Väst"
        case nord = "Nord"
        case ost = "Ost"
        case syd = "Syd"

        var id: String { rawValue }

        var camera: MapCamera {
            switch self {
            case .overview:
                return MapCamera(centerCoordinate: Resort.summit, distance: 11_000, heading: 20, pitch: 55)
            case .vast:
                return MapCamera(centerCoordinate: Resort.summit, distance: 6_500, heading: 90, pitch: 62)
            case .nord:
                return MapCamera(centerCoordinate: Resort.summit, distance: 6_500, heading: 180, pitch: 62)
            case .ost:
                return MapCamera(centerCoordinate: Resort.summit, distance: 6_500, heading: 270, pitch: 62)
            case .syd:
                return MapCamera(centerCoordinate: Resort.summit, distance: 6_500, heading: 0, pitch: 62)
            }
        }
    }
}

/// Вид карты. В первой сборке можно переключать, чтобы выбрать лучший для Idre Fjäll.
enum MapLook: String, CaseIterable, Identifiable {
    case satellite = "Спутник"
    case hybrid = "Гибрид"
    case scheme = "Схема"

    var id: String { rawValue }

    var style: MapStyle {
        switch self {
        case .satellite:
            return .imagery(elevation: .realistic)
        case .hybrid:
            return .hybrid(elevation: .realistic)
        case .scheme:
            return .standard(elevation: .realistic)
        }
    }
}
