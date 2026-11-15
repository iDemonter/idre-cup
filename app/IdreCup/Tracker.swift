import CoreLocation
import Foundation

/// Запись трека: получает точки GPS, в том числе в фоне, хранит трек дня на телефоне
/// и считает по нему итоги. Очки и рейтинг считает сервер, здесь только свой день.
final class Tracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    /// Один трекер на приложение: его включают и экраны, и часы (в том числе когда телефон в кармане).
    static let shared = Tracker()

    /// Запись на паузе: точки не пишутся, но день не закончен (Live Activity и часы показывают «Пауза»).
    @Published private(set) var isPaused = false
    @Published private(set) var status: CLAuthorizationStatus = .notDetermined
    @Published private(set) var isRecording = false
    @Published private(set) var stats = DayStats.empty
    /// Линия трека для карты, прореженная: точки не ближе 8 м друг к другу.
    @Published private(set) var path: [CLLocationCoordinate2D] = []
    /// Меняется вместе с path: по нему карта понимает, что линию пора перерисовать.
    @Published private(set) var pathVersion = 0
    /// Показан демо-день вместо настоящей записи.
    @Published private(set) var isDemo = false
    /// Где телефон сейчас, если это известно. Обновляется и без записи трека.
    @Published private(set) var here: CLLocationCoordinate2D?

    /// Вызывается, когда меняются запись или итоги: по нему обновляется Live Activity.
    /// Работает и в фоне, в отличие от обновления экранов.
    var onChange: (@MainActor () -> Void)?

    private let manager = CLLocationManager()
    private let store = TrackStore()
    private var points: [TrackPoint] = []
    private var savedPoints: [TrackPoint] = []
    private var day = TrackStore.dayName(Date())
    private var sinceStats = 0
    private let recordingKey = "recording"
    private let pausedKey = "paused"
    /// Последнее место, где телефон двигался: если час стоит на месте, запись выключается сама.
    private var anchor: TrackPoint?
    static let idleLimit: TimeInterval = 60 * 60
    /// Почему запись остановилась сама (показывается в «Моём дне»), или nil.
    @Published private(set) var autoStopNote: String?

    var isDenied: Bool { status == .denied || status == .restricted }

    override init() {
        super.init()
        manager.delegate = self
        status = manager.authorizationStatus
        points = store.load(day: Date())
        isPaused = UserDefaults.standard.bool(forKey: pausedKey)
        rebuild()
        // Запись шла, когда приложение закрыли: продолжаем.
        if UserDefaults.standard.bool(forKey: recordingKey), isAllowed {
            begin()
        }
    }

    private var isAllowed: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }

    // MARK: - Управление

    func requestAccess() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Разрешение «Всегда»: без него телефон в кармане не может начать запись по кнопке на часах.
    var isAlways: Bool { status == .authorizedAlways }

    func requestAlways() {
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        } else if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Узнать своё место один раз, не включая запись.
    func locateOnce() {
        if isAllowed, !isRecording {
            manager.requestLocation()
        }
    }

    func start() {
        guard !isDemo else { return }
        if manager.authorizationStatus == .notDetermined {
            // Запись начнётся сама, как только человек разрешит геопозицию.
            UserDefaults.standard.set(true, forKey: recordingKey)
            manager.requestWhenInUseAuthorization()
            return
        }
        guard isAllowed else { return }
        UserDefaults.standard.set(true, forKey: recordingKey)
        setPaused(false)
        autoStopNote = nil
        anchor = nil
        begin()
    }

    func stop() {
        UserDefaults.standard.set(false, forKey: recordingKey)
        manager.stopUpdatingLocation()
        isRecording = false
        setPaused(false)
        refreshStats()
    }

    /// Пауза: точки не пишутся (обед, перерыв), продолжить можно кнопкой «Старт».
    func pause() {
        guard isRecording, !isDemo else { return }
        UserDefaults.standard.set(false, forKey: recordingKey)
        manager.stopUpdatingLocation()
        isRecording = false
        setPaused(true)
        refreshStats()
    }

    private func setPaused(_ value: Bool) {
        isPaused = value
        UserDefaults.standard.set(value, forKey: pausedKey)
    }

    private func begin() {
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        isRecording = true
        notify()
    }

    /// Запись и итоги меняются только на главном потоке: и нажатия, и точки GPS приходят туда.
    private func notify() {
        MainActor.assumeIsolated {
            onChange?()
        }
        PhoneLink.shared.trackerChanged()
    }

    /// Настоящие точки позже заданного времени (секунды с 1970): их Session отправляет на сервер.
    func points(after time: Double, limit: Int) -> [TrackPoint] {
        let source = isDemo ? savedPoints : points
        // Точки идут по возрастанию времени: ищем с конца, где кончается уже отправленное.
        var first = source.count
        while first > 0 && source[first - 1].time.timeIntervalSince1970 > time {
            first -= 1
        }
        return Array(source[first..<min(first + limit, source.count)])
    }

    // MARK: - Демо-день

    /// Показывает готовый трек вместо настоящего. Настоящая запись при этом не теряется.
    func showDemo(_ demo: [TrackPoint]) {
        guard !demo.isEmpty else { return }
        if isRecording { stop() }
        if !isDemo { savedPoints = points }
        isDemo = true
        points = demo
        rebuild()
    }

    func leaveDemo() {
        guard isDemo else { return }
        isDemo = false
        points = savedPoints
        savedPoints = []
        rebuild()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
        PhoneLink.shared.trackerChanged(force: true)
        if isAllowed, UserDefaults.standard.bool(forKey: recordingKey), !isRecording, !isDemo {
            begin()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let latest = locations.last, latest.horizontalAccuracy >= 0, latest.horizontalAccuracy <= 100 {
            here = latest.coordinate
        }
        guard isRecording, !isDemo else { return }
        for location in locations {
            // Грубые и старые точки отбрасываем.
            guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50 else { continue }
            guard abs(location.timestamp.timeIntervalSinceNow) < 30 else { continue }
            let point = TrackPoint(location)
            if let last = points.last, point.time <= last.time { continue }

            // Наступил новый день: начинаем трек заново.
            let today = TrackStore.dayName(point.time)
            if today != day {
                day = today
                points = []
                path = []
            }

            points.append(point)
            store.append(point)
            extendPath(with: point)
            sinceStats += 1

            // Час без движения (обед, вечер в домике): запись выключается, чтобы не сажать батарею.
            if let still = anchor, still.meters(to: point) < 60 {
                if point.time.timeIntervalSince(still.time) > Self.idleLimit {
                    stopIdle(since: still.time)
                    return
                }
            } else {
                anchor = point
            }
        }
        if sinceStats >= 5 {
            refreshStats()
        }
    }

    private func stopIdle(since: Date) {
        stop()
        anchor = nil
        let note = "Запись выключилась сама в \(Format.clock(Date())): час без движения с \(Format.clock(since))."
        autoStopNote = note
        Notifier.postRecordPrompt(id: "idle-\(Int(Date().timeIntervalSince1970))", title: "Запись трека выключена", body: "Час без движения. Снова на склоне? Нажми, чтобы включить.")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Временная потеря сигнала: запись продолжится сама.
    }

    // MARK: - Итоги и линия

    private func rebuild() {
        var line: [CLLocationCoordinate2D] = []
        var last: TrackPoint?
        for point in points {
            if let previous = last, previous.meters(to: point) < 8 { continue }
            line.append(point.coordinate)
            last = point
        }
        path = line
        pathVersion += 1
        refreshStats()
    }

    private func extendPath(with point: TrackPoint) {
        if let last = path.last {
            let previous = TrackPoint(time: point.time, latitude: last.latitude, longitude: last.longitude, altitude: 0, speed: 0, accuracy: 0)
            if previous.meters(to: point) < 8 { return }
        }
        path.append(point.coordinate)
        pathVersion += 1
    }

    private func refreshStats() {
        sinceStats = 0
        stats = TrackAnalyzer.analyze(points)
        notify()
    }
}
