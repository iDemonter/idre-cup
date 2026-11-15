import ActivityKit
import Foundation

/// Данные Live Activity «запись идёт»: экран блокировки, Dynamic Island и Apple Watch.
/// Общий код приложения и расширения IdreCupLive.
struct RideAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Лучшая скорость дня на спусках, м/с.
        var topSpeed: Double
        /// Перепад на спусках за день, м.
        var vertical: Double
        var runs: Int
        /// Место и очки за сегодня. nil, пока сервер их не прислал.
        var place: Int?
        var points: Int?
        /// Идущая дуэль: соперник и когда она кончится.
        var duelWith: String?
        var duelEnds: Date?
        /// Идущее событие дня: название и когда оно кончится.
        var eventTitle: String?
        var eventEnds: Date?
    }

    var cupName: String
    /// Когда включили запись: от него идёт таймер.
    var startedAt: Date
}
