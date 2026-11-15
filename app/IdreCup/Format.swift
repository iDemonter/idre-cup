import Foundation

/// Числа и даты так, как их пишут по-русски: «78,4», «4 260», «воскресенье · 15 ноября».
enum Format {
    static let russian = Locale(identifier: "ru_RU")

    /// Скорость в км/ч из м/с, один знак после запятой.
    static func kmh(_ metersPerSecond: Double) -> String {
        (metersPerSecond * 3.6).formatted(.number.precision(.fractionLength(1)).locale(russian))
    }

    static func meters(_ value: Double) -> String {
        Int(value.rounded()).formatted(.number.locale(russian))
    }

    /// Целое число с пробелом между тысячами: «1 461».
    static func count(_ value: Int) -> String {
        value.formatted(.number.locale(russian))
    }

    static func km(_ meters: Double) -> String {
        (meters / 1000).formatted(.number.precision(.fractionLength(1)).locale(russian))
    }

    static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(russian))
    }

    /// «1:42» или «2 ч 05 мин».
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded()), 0)
        if total >= 3600 {
            return String(format: "%d ч %02d мин", total / 3600, total % 3600 / 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// «воскресенье · 15 ноября».
    static func day(_ date: Date) -> String {
        let weekday = date.formatted(.dateTime.weekday(.wide).locale(russian))
        let number = date.formatted(.dateTime.day().month(.wide).locale(russian))
        return "\(weekday) · \(number)"
    }

    /// Слово по числу: plural(3, "спуск", "спуска", "спусков") = «спуска».
    static func plural(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let tens = count % 100
        let ones = count % 10
        if ones == 1 && tens != 11 { return one }
        if (2...4).contains(ones) && !(12...14).contains(tens) { return few }
        return many
    }
}
