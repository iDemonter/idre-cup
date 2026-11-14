import CoreLocation
import Foundation

/// Запрашивает доступ к геопозиции, чтобы на карте появилась своя точка.
/// Запись треков добавится на следующем шаге.
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var status: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        status = manager.authorizationStatus
    }

    func requestAccess() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        DispatchQueue.main.async {
            self.status = newStatus
        }
    }
}
