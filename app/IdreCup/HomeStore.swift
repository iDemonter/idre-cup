import CoreLocation
import Foundation

/// Жильё на карте: одна точка, которую человек ставит сам. Хранится на телефоне.
/// Позже её можно будет задать один раз на весь кубок: все живут в одном домике.
final class HomeStore: ObservableObject {
    @Published private(set) var home: CLLocationCoordinate2D?

    private let latitudeKey = "homeLat"
    private let longitudeKey = "homeLon"

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: latitudeKey) != nil, defaults.object(forKey: longitudeKey) != nil {
            let place = CLLocationCoordinate2D(latitude: defaults.double(forKey: latitudeKey), longitude: defaults.double(forKey: longitudeKey))
            if CLLocationCoordinate2DIsValid(place) {
                home = place
            }
        }
    }

    func set(_ place: CLLocationCoordinate2D) {
        guard CLLocationCoordinate2DIsValid(place) else { return }
        home = place
        UserDefaults.standard.set(place.latitude, forKey: latitudeKey)
        UserDefaults.standard.set(place.longitude, forKey: longitudeKey)
    }

    func clear() {
        home = nil
        UserDefaults.standard.removeObject(forKey: latitudeKey)
        UserDefaults.standard.removeObject(forKey: longitudeKey)
    }
}
