import CoreLocation
import SwiftUI
import UserNotifications

/// Условия на курорте с сервера: лифты, трассы, часы, погода, снег (с сайта курорта) и прогноз (yr.no).
struct ConditionsReply: Decodable {
    struct Resort: Decodable {
        let id: String
        let name: String
    }

    struct Count: Decodable {
        let open: Int
        let total: Int
    }

    struct Hours: Decodable {
        let opens: String
        let closes: String
    }

    struct Lift: Decodable, Identifiable {
        let code: String
        let name: String
        let status: String?
        let today: Hours?
        let comment: String?
        var id: String { code + name }
        var isOpen: Bool { status == "open" }
        var isClosed: Bool { status == "closed" }
    }

    struct Place: Decodable {
        let temp: Double?
        let wind: Double?
        let gust: Double?
    }

    struct Weather: Decodable {
        let top: Place?
        let valley: Place?
    }

    struct Snow: Decodable {
        let piste: Double?
        let terrain: Double?
        let fresh: Double?
        let last24h: Double?
    }

    struct Status: Decodable {
        let lifts: Count?
        let pistes: Count?
        let liftList: [Lift]?
        let weather: Weather?
        let snow: Snow?
        let closes: String?
        let source: String?
    }

    struct Day: Decodable {
        let date: String
        let min: Int
        let max: Int
        let wind: Int
        let precipitation: Double
        let text: String?
    }

    struct Hour: Decodable, Identifiable {
        let time: String
        let temp: Double
        let wind: Double
        let precipitation: Double
        let text: String?
        var id: String { time }
    }

    struct Forecast: Decodable {
        let day: Day
        let tomorrow: Day?
        let hours: [Hour]
    }

    let resort: Resort
    let status: Status?
    let forecast: Forecast?

    /// Лифт по коду с карты Idre Fjäll («A», «L»…).
    func lift(code: String) -> Lift? {
        status?.liftList?.first { $0.code == code }
    }
}

extension ConditionsReply.Day {
    /// «−12…−8°, ветер до 6 м/с, небольшой снег».
    var summary: String {
        let temp = min == max ? "\(Format.degrees(Double(min)))" : "\(Format.degrees(Double(min)))…\(Format.degrees(Double(max)))"
        var parts = ["\(temp)°", "ветер до \(wind) м/с"]
        if let text { parts.append(text) }
        return parts.joined(separator: ", ")
    }
}

/// Полоса условий в «Моём дне»: погода сейчас и днём, до скольки лифты, сколько открыто. Нажатие — подробности.
struct ConditionsStrip: View {
    let conditions: ConditionsReply
    @State private var showsDetails = false

    var body: some View {
        Button {
            showsDetails = true
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(conditions.resort.name.uppercased())
                        .font(Theme.overline())
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    if let top = conditions.status?.weather?.top?.temp {
                        value("\(Format.degrees(top))°", "вершина")
                    }
                    if let valley = conditions.status?.weather?.valley?.temp {
                        value("\(Format.degrees(valley))°", "внизу")
                    }
                    if let closes = conditions.status?.closes {
                        value(closes, "лифты до")
                    }
                    if let pistes = conditions.status?.pistes, pistes.total > 0 {
                        value("\(pistes.open)/\(pistes.total)", "трасс")
                    }
                }
                if let day = conditions.forecast?.day {
                    Text("Днём: \(day.summary)")
                        .font(Theme.caption())
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showsDetails) {
            ConditionsDetails(conditions: conditions)
                .preferredColorScheme(.dark)
                .presentationDetents([.medium, .large])
        }
    }

    private func value(_ big: String, _ small: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(big)
                .font(Theme.title(20))
                .foregroundStyle(Theme.textPrimary)
            Text(small)
                .font(Theme.caption(10))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

/// Подробно: ветер, снег, лифты с часами и статусом, прогноз по часам.
struct ConditionsDetails: View {
    let conditions: ConditionsReply

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(conditions.resort.name)
                    .font(Theme.title(28))
                    .foregroundStyle(Theme.textPrimary)
                if let status = conditions.status {
                    if let top = status.weather?.top {
                        line("Вершина", [top.temp.map { "\(Format.degrees($0))°" }, top.wind.map { "ветер \(Int($0)) м/с" }, top.gust.map { "порывы \(Int($0))" }])
                    }
                    if let valley = status.weather?.valley {
                        line("Внизу", [valley.temp.map { "\(Format.degrees($0))°" }, valley.wind.map { "ветер \(Int($0)) м/с" }])
                    }
                    if let snow = status.snow {
                        line("Снег", [snow.piste.map { "в трассе \(Int($0)) см" }, snow.terrain.map { "вне трасс \(Int($0)) см" }, (snow.fresh ?? snow.last24h).map { "свежий \(Int($0)) см" }])
                    }
                    if let lifts = status.lifts {
                        line("Открыто", ["лифтов \(lifts.open) из \(lifts.total)", status.pistes.map { "трасс \($0.open) из \($0.total)" }])
                    }
                    if let list = status.liftList, !list.isEmpty {
                        Text("ЛИФТЫ")
                            .font(Theme.overline())
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.top, 4)
                        ForEach(list) { lift in
                            HStack {
                                Circle()
                                    .fill(lift.isOpen ? Theme.pisteGreen : (lift.isClosed ? Theme.pisteRed : Theme.textSecondary))
                                    .frame(width: 8, height: 8)
                                Text(lift.code == lift.name ? lift.name : "\(lift.code) · \(lift.name)")
                                    .font(Theme.headline(14))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text(lift.today.map { "\($0.opens)–\($0.closes)" } ?? (lift.isClosed ? "закрыт" : ""))
                                    .font(Theme.caption())
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            if let comment = lift.comment {
                                Text(comment)
                                    .font(Theme.caption(10))
                                    .foregroundStyle(Theme.textSecondary)
                                    .padding(.leading, 16)
                            }
                        }
                    }
                } else {
                    Text("Сайт курорта сейчас не отдаёт данные о лифтах. Ниже прогноз погоды.")
                        .font(Theme.caption())
                        .foregroundStyle(Theme.textSecondary)
                }
                if let forecast = conditions.forecast {
                    Text("ПРОГНОЗ")
                        .font(Theme.overline())
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 4)
                    line("Сегодня", [forecast.day.summary])
                    if let tomorrow = forecast.tomorrow {
                        line("Завтра", [tomorrow.summary])
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(forecast.hours) { hour in
                                VStack(spacing: 2) {
                                    Text(Format.hour(hour.time))
                                        .font(Theme.caption(10))
                                        .foregroundStyle(Theme.textSecondary)
                                    Text("\(Format.degrees(hour.temp))°")
                                        .font(Theme.headline(15))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("\(Int(hour.wind.rounded())) м/с")
                                        .font(Theme.caption(10))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                    Text("Прогноз: MET Norway (yr.no). Лифты и снег: сайт курорта.")
                        .font(Theme.caption(10))
                        .foregroundStyle(Theme.textSecondary.opacity(0.7))
                }
            }
            .padding(20)
        }
        .background(Theme.base.ignoresSafeArea())
    }

    private func line(_ title: String, _ parts: [String?]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.headline(14))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 80, alignment: .leading)
            Text(parts.compactMap { $0 }.joined(separator: " · "))
                .font(Theme.caption())
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

enum ConditionsAlerts {
    static let closingID = "lifts-closing"

    /// Утреннее напоминание с погодой: ближайшее 9:15 (сегодня или завтра) получает прогноз.
    static func updateMorning(_ conditions: ConditionsReply) {
        guard let forecast = conditions.forecast else { return }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
            for request in requests where request.identifier.hasPrefix(Notifier.morningPrefix) {
                guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
                      let date = trigger.nextTriggerDate() else { continue }
                let day: ConditionsReply.Day?
                if calendar.isDateInToday(date) {
                    day = forecast.day
                } else if calendar.isDateInTomorrow(date) {
                    day = forecast.tomorrow
                } else {
                    continue
                }
                guard let day, let content = request.content.mutableCopy() as? UNMutableNotificationContent else { continue }
                content.body = "\(conditions.resort.name): \(day.summary). Включи запись трека, чтобы спуски пошли в зачёт."
                center.add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger))
            }
        }
    }

    /// За 30 минут до закрытия последнего лифта, пока идёт запись.
    static func scheduleClosing(_ conditions: ConditionsReply, recording: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [closingID])
        guard recording, let closes = conditions.status?.closes else { return }
        let parts = closes.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
        guard let closing = calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: Date()) else { return }
        let warning = closing.addingTimeInterval(-30 * 60)
        guard warning > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Лифты закрываются в \(closes)"
        content.body = "\(conditions.resort.name): осталось полчаса, успей на последний подъём."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: warning.timeIntervalSinceNow, repeats: false)
        center.add(UNNotificationRequest(identifier: closingID, content: content, trigger: trigger))
    }
}
