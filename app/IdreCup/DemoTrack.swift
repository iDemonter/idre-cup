import Foundation

/// Демо-день: выдуманный трек по настоящим трассам и рельефу. Три круга на северном склоне:
/// подъём на Nord 6:an, спуск по Glidaren и одной из трасс Nord.
/// Нужен, чтобы проверить подсчёт и увидеть экраны, пока до горы далеко.
enum DemoTrack {
    static func make(data: PisteData, terrain: TerrainData) -> [TrackPoint] {
        let frame = LocalFrame(origin: data.summitCoordinate)

        func heightAbove(_ place: (east: Double, north: Double)) -> Double {
            terrain.base + terrain.height(east: place.east, north: place.north)
        }

        /// Линия в метрах от вершины, развёрнутая вниз или вверх по склону.
        func line(_ coords: [[Double]], downhill: Bool) -> [(east: Double, north: Double)] {
            let path = coords.map { frame.local($0) }
            guard let first = path.first, let last = path.last else { return [] }
            let startsHigher = heightAbove(first) > heightAbove(last)
            return startsHigher == downhill ? path : Array(path.reversed())
        }

        func piste(_ number: Int) -> [[Double]] {
            data.pistes.first { $0.number == number && $0.label }?.coords ?? []
        }

        guard let lift = data.lifts.first(where: { $0.code == "A" }) else { return [] }
        let up = line(lift.coords, downhill: false)
        let ridge = line(piste(39), downhill: true)
        guard up.count >= 2, ridge.count >= 2 else { return [] }

        var points: [TrackPoint] = []
        let calendar = Calendar.current
        var clock = calendar.startOfDay(for: Date()).addingTimeInterval(9.5 * 3600)

        func add(_ place: (east: Double, north: Double), speed: Double) {
            let seconds = clock.timeIntervalSinceReferenceDate
            let coordinate = frame.coordinate(east: place.east, north: place.north)
            points.append(TrackPoint(
                time: clock,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                altitude: heightAbove(place) + sin(seconds * 0.7) * 1.2,   // «шум» датчика
                speed: speed,
                accuracy: 5
            ))
            clock = clock.addingTimeInterval(1)
        }

        /// Едем вдоль линии, раз в секунду ставим точку. Скорость задаётся долей пройденного пути.
        func travel(_ path: [(east: Double, north: Double)], speed: (Double) -> Double) {
            guard path.count >= 2 else { return }
            var lengths: [Double] = []
            for index in 1..<path.count {
                lengths.append(hypot(path[index].east - path[index - 1].east, path[index].north - path[index - 1].north))
            }
            let total = lengths.reduce(0, +)
            guard total > 0 else { return }
            var walked = 0.0
            while walked < total {
                var rest = walked
                var part = 0
                while part < lengths.count - 1 && rest > lengths[part] {
                    rest -= lengths[part]
                    part += 1
                }
                let share = lengths[part] > 0 ? min(rest / lengths[part], 1) : 0
                let place = (
                    east: path[part].east + (path[part + 1].east - path[part].east) * share,
                    north: path[part].north + (path[part + 1].north - path[part].north) * share
                )
                let now = max(speed(walked / total), 1)
                add(place, speed: now)
                walked += now
            }
        }

        func wait(_ seconds: Int) {
            guard let last = points.last else { return }
            let place = frame.local(last.coordinate)
            for _ in 0..<seconds {
                add(place, speed: 0)
            }
        }

        // Номер трассы и скорость в середине спуска, м/с.
        let laps: [(piste: Int, peak: Double)] = [(28, 17.0), (31, 14.0), (26, 21.5)]
        for lap in laps {
            let slope = line(piste(lap.piste), downhill: true)
            guard slope.count >= 2 else { continue }
            travel(up) { _ in 5 }
            wait(20)
            travel(ridge) { share in 8 + 2 * sin(share * 9) }
            travel(slope) { share in 6 + (lap.peak - 6) * pow(sin(share * .pi), 0.6) + 0.8 * sin(share * 40) }
            wait(40)
        }
        return points
    }
}
