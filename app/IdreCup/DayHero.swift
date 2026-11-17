import SwiftUI

/// Главный блок «Моего дня» (предложение 3, Figma DayHero 42:451): скорость крупно, под ней перепад, спуски и километры.
/// Цифры меняются плавно (numericText), рамка акцентом, пока идёт запись.
struct DayHero: View {
    enum Mode {
        case recording, paused, off
    }

    let state: Mode
    let stats: DayStats

    private var hasRuns: Bool { stats.runs > 0 }

    private var status: String {
        let time = stats.movingTime > 0 ? " · \(Format.duration(stats.movingTime))" : ""
        switch state {
        case .recording: return "ЗАПИСЬ ИДЁТ" + time
        case .paused: return "ПАУЗА" + time
        case .off: return "ЗАПИСЬ ВЫКЛЮЧЕНА"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                Circle()
                    .fill(state == .recording ? Palette.error : Palette.textSecondary)
                    .frame(width: 8, height: 8)
                Text(status)
                    .font(Typo.overline)
                    .foregroundStyle(state == .recording ? Palette.accentText : Palette.textSecondary)
                    .contentTransition(.numericText())
            }
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text(Format.kmh(hasRuns ? stats.topSpeed : 0))
                    .font(.system(size: 96, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(Palette.accent)
                    .opacity(hasRuns ? 1 : 0.35)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText(value: stats.topSpeed))
                Text("км/ч")
                    .font(Typo.title3)
                    .foregroundStyle(Palette.textSecondary)
            }
            Text(hasRuns ? "максимум за день, держал 3 секунды" : "скорость появится после первого спуска")
                .font(Typo.caption1)
                .foregroundStyle(Palette.textSecondary)
            HStack(alignment: .top, spacing: Spacing.xl) {
                figure(Format.meters(stats.vertical), "м перепада", value: stats.vertical)
                figure(String(stats.runs), Format.plural(stats.runs, "спуск", "спуска", "спусков"), value: Double(stats.runs))
                figure(Format.km(stats.runDistance), "км", value: stats.runDistance)
            }
            .padding(.top, Spacing.s)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.l + 2)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.cardLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.cardLarge, style: .continuous)
                .stroke(state == .recording ? Palette.accent : Palette.border, lineWidth: state == .recording ? 2 : 1)
        )
        .animation(.snappy, value: stats.topSpeed)
        .animation(.snappy, value: stats.vertical)
        .animation(.snappy, value: stats.runs)
        .animation(.snappy, value: state)
    }

    private func figure(_ text: String, _ unit: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(Typo.numberL)
                .foregroundStyle(Palette.textPrimary)
                .contentTransition(.numericText(value: value))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(unit)
                .font(Typo.caption1)
                .foregroundStyle(Palette.textSecondary)
        }
    }
}
