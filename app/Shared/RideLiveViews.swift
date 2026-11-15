import SwiftUI

/// Карточка записи для экрана блокировки.
/// Лежит в общем коде: приложение показывает её же при сборке, чтобы проверить вёрстку по снимку экрана.
struct RideLockScreenView: View {
    let cupName: String
    let startedAt: Date
    let state: RideAttributes.ContentState
    var isStale = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "figure.skiing.downhill")
                    .foregroundStyle(Theme.accent)
                Text(cupName.uppercased())
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isStale {
                    Text("НЕТ СВЕЖИХ ДАННЫХ")
                } else if state.paused {
                    Image(systemName: "pause.fill")
                    Text("ПАУЗА")
                } else {
                    Circle()
                        .fill(Theme.pisteRed)
                        .frame(width: 7, height: 7)
                    Text(startedAt, style: .timer)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 66, alignment: .trailing)
                }
            }
            .font(Theme.overline(11))
            .foregroundStyle(Theme.textSecondary)

            HStack(alignment: .top, spacing: 0) {
                metric(Format.kmh(state.topSpeed), "км/ч макс", isMain: true)
                metric(Format.meters(state.vertical), "м перепад")
                metric(String(state.runs), Format.plural(state.runs, "спуск", "спуска", "спусков"))
                if let points = state.points {
                    metric(points < 0 ? "−\(-points)" : "+\(points)", state.place.map { "\($0)-е место" } ?? "очки")
                }
            }

            if isStale {
                Text("Откройте Idre Cup: запись могла остановиться.")
                    .font(Theme.caption(11))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                if let title = state.eventTitle, let end = state.eventEnds, end > Date() {
                    countdown("bolt.fill", "Событие: \(title)", until: end)
                }
                if let rival = state.duelWith, let end = state.duelEnds, end > Date() {
                    countdown("flag.checkered.2.crossed", "Дуэль: \(rival)", until: end)
                }
            }
        }
        .padding(16)
    }

    /// Строка «что идёт · осталось 12:40».
    private func countdown(_ symbol: String, _ text: String, until end: Date) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(text)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("осталось")
                .foregroundStyle(Theme.textSecondary)
            Text(end, style: .timer)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 66, alignment: .trailing)
        }
        .font(Theme.caption(12))
        .foregroundStyle(Theme.accent)
    }

    private func metric(_ value: String, _ label: String, isMain: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(Theme.title(isMain ? 26 : 22))
                .foregroundStyle(isMain ? Theme.accent : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(Theme.caption(10))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
