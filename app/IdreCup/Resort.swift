import MapKit
import SwiftUI

/// Курорт Idre Fjäll (гора Gränjåsvålen, вершина около 890 м).
enum Resort {
    static let name = "Idre Fjäll"
}

/// Вид карты под трассами.
enum MapLook: String, CaseIterable, Identifiable {
    /// Своя 3D-модель горы с вытянутой высотой. Остальные виды рисует Apple Maps.
    case model = "Модель"
    case satellite = "Спутник"
    case hybrid = "Гибрид"
    case scheme = "Схема"

    var id: String { rawValue }

    var style: MapStyle {
        switch self {
        case .model, .satellite:
            return .imagery(elevation: .realistic)
        case .hybrid:
            return .hybrid(elevation: .realistic)
        case .scheme:
            return .standard(elevation: .realistic)
        }
    }
}
