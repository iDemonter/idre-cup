import SwiftUI

/// Сводка дня в «Моём дне» до записи (Figma: компонент DayBrief, экран «Мой день · сводка дня»):
/// погода сейчас, лифты, трассы, снег, прогноз по часам, день и завтра. Нажатие — ConditionsDetails.
/// Чего курорт не отдаёт, того в сводке нет.
struct DayBrief: View {
    let conditions: ConditionsReply
    @State private var showsDetails = false

    var body: some View {
        Button {
            showsDetails = true
        } label: {
            VStack(alignment: .leading, spacing: Spacing.m + 2) {
                HStack(spacing: 6) {
                    Text("\(conditions.resort.name) · сегодня")
                        .overlineStyle()
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(Typo.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
                now
                tiles
                hours
                if let day = conditions.forecast?.day {
                    Text("Днём: \(day.summary)")
                        .font(Typo.caption1)
                        .foregroundStyle(Palette.textSecondary)
                }
                if let tomorrow = conditions.forecast?.tomorrow {
                    Text("Завтра: \(tomorrow.summary)")
                        .font(Typo.caption1)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.l)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.cardLarge, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Подробно: каждый лифт, прогноз по часам")
        .sheet(isPresented: $showsDetails) {
            ConditionsDetails(conditions: conditions)
                .preferredColorScheme(.dark)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Погода сейчас

    private var weather: ConditionsReply.Weather? { conditions.status?.weather }

    /// Ближайший час прогноза: из него описание погоды, если курорт сам не даёт температуру.
    private var currentHour: ConditionsReply.Hour? {
        let hours = conditions.forecast?.hours ?? []
        let formatter = ISO8601DateFormatter()
        let soon = Date().addingTimeInterval(-30 * 60)
        return hours.first { (formatter.date(from: $0.time) ?? .distantPast) >= soon } ?? hours.first
    }

    @ViewBuilder
    private var now: some View {
        let top = weather?.top?.temp
        let temp = top ?? weather?.valley?.temp ?? currentHour?.temp
        if let temp {
            HStack(alignment: .center, spacing: Spacing.m) {
                Text("\(Format.degrees(temp))°")
                    .font(Typo.numberL)
                    .foregroundStyle(Palette.textPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline(onTop: top != nil))
                        .font(Typo.subheadline)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    if let detail = detail(onTop: top != nil) {
                        Text(detail)
                            .font(Typo.caption1)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    /// «Облачно»: описание ближайшего часа прогноза.
    private func headline(onTop: Bool) -> String {
        currentHour?.text.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "Сейчас"
    }

    /// «на вершине · внизу −5° · ветер 6 м/с, порывы 11».
    private func detail(onTop: Bool) -> String? {
        var parts: [String] = []
        if onTop {
            parts.append("на вершине")
            if let valley = weather?.valley?.temp { parts.append("внизу \(Format.degrees(valley))°") }
        } else if weather?.valley?.temp != nil {
            parts.append("внизу")
        }
        let place = onTop ? weather?.top : weather?.valley
        if let wind = place?.wind ?? currentHour?.wind {
            var text = "ветер \(Int(wind.rounded())) м/с"
            if let gust = place?.gust { text += ", порывы \(Int(gust.rounded()))" }
            parts.append(text)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Лифты, трассы, снег

    /// Самое раннее открытие среди лифтов: «9:00».
    private var opens: String? {
        let times = (conditions.status?.liftList ?? []).compactMap { $0.today?.opens }
        return times.min { minutes($0) < minutes($1) }.map(short)
    }

    private func minutes(_ time: String) -> Int {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        return parts.count == 2 ? parts[0] * 60 + parts[1] : .max
    }

    /// «09:00» → «9:00».
    private func short(_ time: String) -> String {
        time.hasPrefix("0") ? String(time.dropFirst()) : time
    }

    @ViewBuilder
    private var tiles: some View {
        let status = conditions.status
        let lifts: (String, String)? = {
            if let closes = status?.closes {
                let small = [opens.map { "с \($0)" }, status?.lifts.map { "\($0.open) из \($0.total)" }].compactMap { $0 }
                return ("до \(short(closes))", small.isEmpty ? "работают" : small.joined(separator: " · "))
            }
            if let count = status?.lifts, count.total > 0 { return ("\(count.open)/\(count.total)", "открыто") }
            return nil
        }()
        let pistes = status?.pistes.flatMap { $0.total > 0 ? ("\($0.open)/\($0.total)", "открыто") : nil }
        let snow: (String, String)? = {
            // Межсезонье: нули не показываем.
            guard let snow = status?.snow, (snow.fresh ?? snow.last24h ?? 0) > 0 || (snow.piste ?? 0) > 0 else { return nil }
            let depth = snow.piste.map { "покров \(Int($0)) см" }
            if let fresh = snow.fresh ?? snow.last24h, fresh > 0 { return ("+\(Int(fresh)) см", depth ?? "за сутки") }
            if let piste = snow.piste { return ("\(Int(piste)) см", "в трассе") }
            return nil
        }()
        let items = [lifts.map { ("Лифты", $0.0, $0.1) }, pistes.map { ("Трассы", $0.0, $0.1) }, snow.map { ("Снег", $0.0, $0.1) }].compactMap { $0 }
        if !items.isEmpty {
            HStack(spacing: Spacing.s) {
                ForEach(items, id: \.0) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.0)
                            .overlineStyle()
                            .foregroundStyle(Palette.textSecondary)
                        Text(item.1)
                            .font(Typo.title3)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(item.2)
                            .font(Typo.caption2)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                }
            }
        }
    }

    // MARK: - По часам

    /// Пять точек через два часа, начиная с ближайшего.
    @ViewBuilder
    private var hours: some View {
        let all = conditions.forecast?.hours ?? []
        let start = currentHour.flatMap { hour in all.firstIndex { $0.id == hour.id } } ?? 0
        let picked = Array(stride(from: start, to: all.count, by: 2).prefix(5).map { all[$0] })
        if picked.count >= 2 {
            HStack {
                ForEach(Array(picked.enumerated()), id: \.element.id) { index, hour in
                    if index > 0 { Spacer(minLength: 0) }
                    VStack(spacing: 2) {
                        Text(Format.hour(hour.time))
                            .font(Typo.caption2)
                            .foregroundStyle(Palette.textSecondary)
                        Text("\(Format.degrees(hour.temp))°")
                            .font(Typo.subheadline)
                            .foregroundStyle(Palette.textPrimary)
                        Text("\(Int(hour.wind.rounded())) м/с")
                            .font(Typo.caption2)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        }
    }
}
