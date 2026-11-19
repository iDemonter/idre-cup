import SwiftUI

/// Сводка дня в «Моём дне» до записи (Figma: компонент DayBrief 63:530, экран «Мой день · сводка дня»).
/// Сверху погода сейчас на мягкой акцентной подложке: значок, температура, низ и ветер.
/// Ниже плитки «Лифты», «Трассы», «Снег», прогноз по часам со значками, днём и завтра.
/// Нажатие — ConditionsDetails. Чего курорт не отдаёт, того в сводке нет (у снега — «нет данных»).
struct DayBrief: View {
    let conditions: ConditionsReply
    @State private var showsDetails = false

    var body: some View {
        Button {
            showsDetails = true
        } label: {
            VStack(alignment: .leading, spacing: Spacing.m + 2) {
                hero
                tiles
                hours
                VStack(alignment: .leading, spacing: Spacing.s) {
                    if let day = conditions.forecast?.day {
                        dayRow("Днём", symbol: day.symbol, text: day.summary)
                    }
                    if let tomorrow = conditions.forecast?.tomorrow {
                        dayRow("Завтра", symbol: tomorrow.symbol, text: tomorrow.summary)
                    }
                }
                .padding(.horizontal, Spacing.xs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.m)
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

    /// Ближайший час прогноза: из него значок и описание погоды.
    private var currentHour: ConditionsReply.Hour? {
        let hours = conditions.forecast?.hours ?? []
        let formatter = ISO8601DateFormatter()
        let soon = Date().addingTimeInterval(-30 * 60)
        return hours.first { (formatter.date(from: $0.time) ?? .distantPast) >= soon } ?? hours.first
    }

    private var hero: some View {
        let top = weather?.top?.temp
        let temp = top ?? weather?.valley?.temp ?? currentHour?.temp
        return VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: 6) {
                Text("\(conditions.resort.name) · сегодня")
                    .overlineStyle()
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Typo.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            HStack(alignment: .center, spacing: Spacing.m) {
                Image(systemName: WeatherSymbol.name(for: currentHour?.symbol))
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Palette.accentText)
                    .frame(width: 56)
                    .accessibilityHidden(true)
                if let temp {
                    Text("\(Format.degrees(temp))°")
                        .font(Typo.numberXL)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentHour?.text.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "Сейчас")
                        .font(Typo.headline)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(top != nil ? "на вершине" : (weather?.valley?.temp != nil ? "внизу" : "прогноз"))
                        .font(Typo.caption1)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            pills(onTop: top != nil)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    /// «внизу −6°» и «ветер 4 м/с, порывы 8».
    @ViewBuilder
    private func pills(onTop: Bool) -> some View {
        let place = onTop ? weather?.top : weather?.valley
        let wind = place?.wind ?? currentHour?.wind
        let valley = onTop ? weather?.valley?.temp : nil
        if valley != nil || wind != nil {
            HStack(spacing: 6) {
                if let valley {
                    pill("mountain.2.fill", "внизу \(Format.degrees(valley))°")
                }
                if let wind {
                    let gust = place?.gust.map { ", порывы \(Int($0.rounded()))" } ?? ""
                    pill("wind", "ветер \(Int(wind.rounded())) м/с\(gust)")
                }
            }
        }
    }

    private func pill(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(Typo.caption2)
                .foregroundStyle(Palette.accentText)
            Text(text)
                .font(Typo.caption1)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, Spacing.s)
        .background(Palette.surface, in: Capsule())
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

    private struct Tile: Identifiable {
        let title: String
        let symbol: String
        let value: String
        let note: String
        var id: String { title }
    }

    private var tileItems: [Tile] {
        guard let status = conditions.status else { return [] }
        var items: [Tile] = []
        if let closes = status.closes {
            let note = [opens.map { "с \($0)" }, status.lifts.map { "\($0.open) из \($0.total)" }].compactMap { $0 }
            items.append(Tile(title: "Лифты", symbol: "clock.fill", value: "до \(short(closes))", note: note.isEmpty ? "работают" : note.joined(separator: " · ")))
        } else if let count = status.lifts, count.total > 0 {
            items.append(Tile(title: "Лифты", symbol: "clock.fill", value: "\(count.open)/\(count.total)", note: "открыто"))
        }
        if let count = status.pistes, count.total > 0 {
            items.append(Tile(title: "Трассы", symbol: "figure.skiing.downhill", value: "\(count.open)/\(count.total)", note: count.open == 0 ? "ещё закрыты" : "открыто"))
        }
        // Толщина снега: в трассе, иначе вне трасс; свежий за сутки — подписью.
        let snow = status.snow
        let depth = snow?.piste ?? snow?.terrain
        let fresh = snow?.fresh ?? snow?.last24h
        var note = depth == nil ? "нет данных" : (snow?.piste != nil ? "в трассе" : "вне трасс")
        if let fresh, fresh > 0 { note += " · +\(Int(fresh.rounded())) см" }
        items.append(Tile(title: "Снег", symbol: "snowflake", value: depth.map { "\(Int($0.rounded())) см" } ?? "—", note: note))
        return items
    }

    @ViewBuilder
    private var tiles: some View {
        let items = tileItems
        if !items.isEmpty {
            HStack(spacing: Spacing.s) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Image(systemName: item.symbol)
                                .font(Typo.caption2)
                                .foregroundStyle(Palette.accentText)
                            Text(item.title)
                                .overlineStyle()
                                .foregroundStyle(Palette.textSecondary)
                        }
                        Text(item.value)
                            .font(Typo.title3)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(item.note)
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
                    VStack(spacing: 4) {
                        Text(Format.hour(hour.time))
                            .font(Typo.caption2)
                            .foregroundStyle(Palette.textSecondary)
                        Image(systemName: WeatherSymbol.name(for: hour.symbol))
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Palette.accentText)
                            .frame(height: 22)
                            .accessibilityLabel(hour.text ?? "")
                        Text("\(Format.degrees(hour.temp))°")
                            .font(Typo.subheadline)
                            .foregroundStyle(Palette.textPrimary)
                        Text("\(Int(hour.wind.rounded())) м/с")
                            .font(Typo.caption2)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            .padding(.horizontal, Spacing.xs)
        }
    }

    // MARK: - Днём и завтра

    private func dayRow(_ title: String, symbol: String?, text: String) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: WeatherSymbol.name(for: symbol))
                .symbolRenderingMode(.hierarchical)
                .font(Typo.footnote)
                .foregroundStyle(Palette.accentText)
                .frame(width: 20)
            Text(title)
                .font(Typo.footnote)
                .foregroundStyle(Palette.textPrimary)
            Text(text)
                .font(Typo.caption1)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(2)
        }
    }
}

/// Значок SF Symbols по коду погоды MET Norway (yr.no): «partlycloudy_day» → cloud.sun.fill.
enum WeatherSymbol {
    static func name(for code: String?) -> String {
        guard let code else { return "cloud.fill" }
        let night = code.hasSuffix("_night") || code.hasSuffix("_polartwilight")
        let base = code
            .replacingOccurrences(of: "_day", with: "")
            .replacingOccurrences(of: "_night", with: "")
            .replacingOccurrences(of: "_polartwilight", with: "")
        switch base {
        case "clearsky": return night ? "moon.stars.fill" : "sun.max.fill"
        case "fair", "partlycloudy": return night ? "cloud.moon.fill" : "cloud.sun.fill"
        case "cloudy": return "cloud.fill"
        case "fog": return "cloud.fog.fill"
        default:
            if base.contains("thunder") { return "cloud.bolt.fill" }
            if base.contains("sleet") { return "cloud.sleet.fill" }
            if base.contains("snow") { return "cloud.snow.fill" }
            if base.contains("lightrain") { return "cloud.drizzle.fill" }
            if base.contains("rain") { return "cloud.rain.fill" }
            return "cloud.fill"
        }
    }
}
