import CoreLocation
import Foundation

/// Одна точка трека: то, что приходит от GPS раз в секунду.
struct TrackPoint: Equatable {
    let time: Date
    let latitude: Double
    let longitude: Double
    /// Высота над уровнем моря, м.
    let altitude: Double
    /// Скорость по GPS, м/с. Меньше нуля: телефон её не знает.
    let speed: Double
    /// Точность по горизонтали, м.
    let accuracy: Double

    init(time: Date, latitude: Double, longitude: Double, altitude: Double, speed: Double, accuracy: Double) {
        self.time = time
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.speed = speed
        self.accuracy = accuracy
    }

    init(_ location: CLLocation) {
        time = location.timestamp
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        altitude = location.altitude
        speed = location.speed
        accuracy = location.horizontalAccuracy
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Расстояние по земле до другой точки, м.
    func meters(to other: TrackPoint) -> Double {
        let north = (other.latitude - latitude) * 111_320
        let east = (other.longitude - longitude) * 111_320 * cos(latitude * .pi / 180)
        return (north * north + east * east).squareRoot()
    }

    // MARK: - Строка файла

    /// Время (секунды с 1970), широта, долгота, высота, скорость, точность.
    var line: String {
        String(format: "%.3f,%.6f,%.6f,%.1f,%.2f,%.1f", time.timeIntervalSince1970, latitude, longitude, altitude, speed, accuracy)
    }

    init?(line: Substring) {
        let parts = line.split(separator: ",")
        guard
            parts.count == 6,
            let seconds = Double(parts[0]),
            let latitude = Double(parts[1]),
            let longitude = Double(parts[2]),
            let altitude = Double(parts[3]),
            let speed = Double(parts[4]),
            let accuracy = Double(parts[5])
        else {
            return nil
        }
        self.init(time: Date(timeIntervalSince1970: seconds), latitude: latitude, longitude: longitude, altitude: altitude, speed: speed, accuracy: accuracy)
    }
}

/// Треки на телефоне: один файл на день, точки дописываются в конец.
/// Так ничего не теряется, если приложение закрыли или связь пропала.
final class TrackStore {
    private let folder: URL
    private var handle: FileHandle?
    private var openDay: String?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = base.appendingPathComponent("tracks", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Имя дня по местному времени: 2027-01-03.
    static func dayName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func load(day: Date) -> [TrackPoint] {
        let url = folder.appendingPathComponent(Self.dayName(day) + ".csv")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { TrackPoint(line: $0) }
    }

    func append(_ point: TrackPoint) {
        let day = Self.dayName(point.time)
        if day != openDay {
            try? handle?.close()
            handle = nil
            let url = folder.appendingPathComponent(day + ".csv")
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            handle = try? FileHandle(forWritingTo: url)
            _ = try? handle?.seekToEnd()
            openDay = day
        }
        if let data = (point.line + "\n").data(using: .utf8) {
            try? handle?.write(contentsOf: data)
        }
    }
}
