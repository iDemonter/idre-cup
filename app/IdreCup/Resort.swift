import MapKit
import SwiftUI

/// Курорт Idre Fjäll (гора Gränjåsvålen, вершина около 890 м).
enum Resort {
    static let name = "Idre Fjäll"
}

/// Вид карты под трассами.
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

    /// Снимок приглушается, чтобы цветные линии трасс читались на пёстром фоне.
    var dimmed: Bool {
        switch self {
        case .satellite, .hybrid:
            return true
        case .scheme:
            return false
        }
    }
}

/// Прямоугольник затемнения вокруг курорта.
struct DimArea: Identifiable {
    let id = "dim"
    let coordinates: [CLLocationCoordinate2D]

    init(center: CLLocationCoordinate2D) {
        let dLat = 0.16
        let dLon = 0.34
        coordinates = [
            CLLocationCoordinate2D(latitude: center.latitude - dLat, longitude: center.longitude - dLon),
            CLLocationCoordinate2D(latitude: center.latitude - dLat, longitude: center.longitude + dLon),
            CLLocationCoordinate2D(latitude: center.latitude + dLat, longitude: center.longitude + dLon),
            CLLocationCoordinate2D(latitude: center.latitude + dLat, longitude: center.longitude - dLon),
        ]
    }
}
