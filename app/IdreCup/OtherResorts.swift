import CoreLocation
import MapKit
import SwiftUI

/// Курорты сезона (Åre, Vemdalen, горки Стокгольма): список с сервера, трассы и подъёмники из OpenStreetMap.
struct ResortSummary: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let region: String
    let center: [Double]
    let radiusKm: Double
    let trails: Int

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: center[0], longitude: center[1]) }
    /// Idre Fjäll и Himmelfjäll и так нарисованы на карте своими данными.
    var isIdre: Bool { region == "Idre" }
}

struct ResortList: Decodable {
    let resorts: [ResortSummary]
}

struct ResortDetail: Decodable {
    struct Trail: Decodable, Identifiable {
        let id: String
        let label: String?
        let name: String?
        let difficulty: String?
        let length: Double
        let coords: [[Double]]

        var coordinates: [CLLocationCoordinate2D] { coords.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) } }
        var color: Color {
            switch difficulty {
            case "green": return Palette.pisteGreen
            case "blue": return Palette.pisteBlue
            case "red": return Palette.pisteRed
            case "black": return Palette.pisteBlack
            default: return Palette.textSecondary
            }
        }
        var title: String { [label, name].compactMap { $0 }.joined(separator: " ") }
        var mid: CLLocationCoordinate2D { coordinates[coordinates.count / 2] }
    }

    struct Lift: Decodable, Identifiable {
        let name: String?
        let kind: String
        let coords: [[Double]]
        var id: String { "\(coords.first?.description ?? "")\(kind)" }
        var coordinates: [CLLocationCoordinate2D] { coords.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) } }
    }

    let id: String
    let name: String
    let region: String
    let center: [Double]
    let radiusKm: Double
    let trails: [Trail]
    let lifts: [Lift]

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: center[0], longitude: center[1]) }

    /// Камера, в которую курорт входит целиком.
    var camera: MapCamera {
        MapCamera(centerCoordinate: coordinate, distance: max(2_500, radiusKm * 1000 * 3.2), heading: 0, pitch: 40)
    }
}
