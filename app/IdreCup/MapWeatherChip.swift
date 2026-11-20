import SwiftUI

/// Погода и условия курорта, открытого на карте (Figma: компонент MapWeatherChip 82:5174).
/// Стеклянная капсула под названием курорта: значок погоды, температура, до скольки лифты, сколько трасс.
/// На стекле — только textPrimary и accentText. Нажатие — ConditionsDetails этого курорта.
struct MapWeatherChip: View {
    let conditions: ConditionsReply
    let action: () -> Void

    /// Ближайший час прогноза: значок и температура, если курорт сам её не даёт.
    private var hour: ConditionsReply.Hour? {
        let hours = conditions.forecast?.hours ?? []
        let formatter = ISO8601DateFormatter()
        let soon = Date().addingTimeInterval(-30 * 60)
        return hours.first { (formatter.date(from: $0.time) ?? .distantPast) >= soon } ?? hours.first
    }

    private var temperature: Double? {
        conditions.status?.weather?.top?.temp ?? conditions.status?.weather?.valley?.temp ?? hour?.temp
    }

    /// «лифты до 16:00 · 54/71 трасс».
    private var detail: String? {
        var parts: [String] = []
        if let closes = conditions.status?.closes {
            parts.append("лифты до \(closes.hasPrefix("0") ? String(closes.dropFirst()) : closes)")
        }
        if let pistes = conditions.status?.pistes, pistes.total > 0 {
            parts.append("\(pistes.open)/\(pistes.total) трасс")
        }
        if parts.isEmpty, let wind = hour?.wind {
            parts.append("ветер \(Int(wind.rounded())) м/с")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: WeatherSymbol.name(for: hour?.symbol))
                    .symbolRenderingMode(.hierarchical)
                    .font(Typo.subheadline)
                    .foregroundStyle(Palette.accentText)
                if let temperature {
                    Text("\(Format.degrees(temperature))°")
                        .font(Typo.subheadline)
                        .foregroundStyle(Palette.textPrimary)
                }
                if let detail {
                    Text(detail)
                        .font(Typo.caption1)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Image(systemName: "chevron.right")
                    .font(Typo.caption2)
                    .foregroundStyle(Palette.accentText)
            }
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: 36)
            .glassBackground(in: Capsule())
            .overlay(Capsule().stroke(Palette.glassStroke, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Погода и условия: \(conditions.resort.name)")
    }
}
