import Foundation

/// Спуск или подъём, найденный в треке.
struct TrackSegment: Identifiable {
    enum Kind {
        case run
        case lift
    }

    let id: Int
    let kind: Kind
    let start: Date
    let end: Date
    /// Перепад высоты, м (всегда положительный).
    let vertical: Double
    /// Путь по земле, м.
    let distance: Double
    /// Наибольшая скорость, которую держал несколько секунд подряд, м/с.
    let topSpeed: Double

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Итоги дня по треку.
struct DayStats {
    /// Лучшая удержанная скорость на спусках, м/с.
    var topSpeed = 0.0
    /// Сумма перепадов на спусках, м.
    var vertical = 0.0
    var runs = 0
    /// Путь на спусках, м.
    var runDistance = 0.0
    /// Весь записанный путь, м, и время в движении.
    var totalDistance = 0.0
    var movingTime: TimeInterval = 0
    var pointCount = 0
    var segments: [TrackSegment] = []

    static let empty = DayStats()
}

/// Пороги разбора трека. Позже придут с сервера вместе с остальными правилами.
struct TrackRules {
    /// Сколько секунд надо держать скорость, чтобы она засчиталась (защита от скачков GPS).
    var holdSeconds = 3.0
    /// На сколько метров высота должна развернуться, чтобы закончился спуск или подъём.
    var reversal = 10.0
    /// Меньший перепад спуском или подъёмом не считается.
    var minVertical = 20.0
    /// Пауза в записи длиннее этой рвёт трек на части, с.
    var gap = 120.0
    /// Медленнее этого считаем, что человек стоит, м/с.
    var movingSpeed = 1.5

    static let standard = TrackRules()
}

/// Разбор трека на спуски и подъёмы.
///
/// Высота сглаживается, затем ищутся развороты: вершины и низины, от которых высота ушла
/// больше чем на `reversal`. Участок между соседними разворотами вниз = спуск, вверх = подъём.
/// Остановки посреди спуска его не рвут: высота при этом не разворачивается.
enum TrackAnalyzer {
    static func analyze(_ points: [TrackPoint], rules: TrackRules = .standard) -> DayStats {
        var stats = DayStats()
        let count = points.count
        stats.pointCount = count
        guard count >= 2 else { return stats }

        // Шаг от предыдущей точки, скорость, разрывы записи.
        var step = [Double](repeating: 0, count: count)
        var speed = [Double](repeating: 0, count: count)
        var breakBefore = [Bool](repeating: false, count: count)
        speed[0] = max(points[0].speed, 0)
        for index in 1..<count {
            let seconds = points[index].time.timeIntervalSince(points[index - 1].time)
            if seconds <= 0 || seconds > rules.gap {
                breakBefore[index] = true
                speed[index] = max(points[index].speed, 0)
                continue
            }
            let moved = points[index - 1].meters(to: points[index])
            step[index] = moved
            speed[index] = points[index].speed >= 0 ? points[index].speed : moved / seconds
            stats.totalDistance += moved
            if speed[index] >= rules.movingSpeed {
                stats.movingTime += seconds
            }
        }

        // Сглаженная высота: среднее по соседним точкам в пределах 10 секунд.
        var height = [Double](repeating: 0, count: count)
        for index in 0..<count {
            var sum = 0.0
            var used = 0.0
            for near in max(0, index - 4)...min(count - 1, index + 4) {
                if abs(points[near].time.timeIntervalSince(points[index].time)) <= 10 {
                    sum += points[near].altitude
                    used += 1
                }
            }
            height[index] = sum / max(used, 1)
        }

        // Развороты высоты. Каждый непрерывный кусок записи даёт свою цепочку.
        var chains: [[Int]] = []
        var chain: [Int] = [0]
        var direction = 0
        var extreme = 0
        for index in 1..<count {
            if breakBefore[index] {
                if chain.last != extreme { chain.append(extreme) }
                if chain.last != index - 1 { chain.append(index - 1) }
                chains.append(chain)
                chain = [index]
                direction = 0
                extreme = index
                continue
            }
            if direction == 0 {
                if height[index] >= height[extreme] + rules.reversal {
                    direction = 1
                    extreme = index
                } else if height[index] <= height[extreme] - rules.reversal {
                    direction = -1
                    extreme = index
                }
            } else if direction == 1 {
                if height[index] > height[extreme] {
                    extreme = index
                } else if height[index] <= height[extreme] - rules.reversal {
                    chain.append(extreme)
                    direction = -1
                    extreme = index
                }
            } else {
                if height[index] < height[extreme] {
                    extreme = index
                } else if height[index] >= height[extreme] + rules.reversal {
                    chain.append(extreme)
                    direction = 1
                    extreme = index
                }
            }
        }
        if chain.last != extreme { chain.append(extreme) }
        if chain.last != count - 1 { chain.append(count - 1) }
        chains.append(chain)

        // Участки между разворотами.
        var nextID = 0
        for pivots in chains {
            for position in 1..<max(pivots.count, 1) {
                let from = pivots[position - 1]
                let to = pivots[position]
                guard to > from else { continue }
                let change = height[to] - height[from]
                guard abs(change) >= rules.minVertical else { continue }

                // Стояние в начале и в конце участка в него не входит.
                var first = from
                var last = to
                while first < last && speed[first + 1] < rules.movingSpeed { first += 1 }
                while last > first && speed[last] < rules.movingSpeed { last -= 1 }
                guard last > first else { continue }

                var distance = 0.0
                for index in (first + 1)...last {
                    distance += step[index]
                }
                nextID += 1
                stats.segments.append(TrackSegment(
                    id: nextID,
                    kind: change < 0 ? .run : .lift,
                    start: points[first].time,
                    end: points[last].time,
                    vertical: abs(change),
                    distance: distance,
                    topSpeed: heldSpeed(speed, points, from: first, to: last, hold: rules.holdSeconds)
                ))
            }
        }

        for segment in stats.segments where segment.kind == .run {
            stats.runs += 1
            stats.vertical += segment.vertical
            stats.runDistance += segment.distance
            stats.topSpeed = max(stats.topSpeed, segment.topSpeed)
        }
        return stats
    }

    /// Наибольшая скорость, которая держалась не меньше `hold` секунд подряд.
    private static func heldSpeed(_ speed: [Double], _ points: [TrackPoint], from: Int, to: Int, hold: Double) -> Double {
        var best = 0.0
        var end = from
        for start in from...to {
            if end < start { end = start }
            while end < to && points[end].time.timeIntervalSince(points[start].time) < hold {
                end += 1
            }
            let span = points[end].time.timeIntervalSince(points[start].time)
            if span < hold { break }          // до конца участка осталось меньше hold секунд
            if span > hold + 3 { continue }   // дыра в записи, окно не считается
            var lowest = Double.infinity
            for index in start...end {
                lowest = min(lowest, speed[index])
            }
            best = max(best, lowest)
        }
        return best
    }
}
