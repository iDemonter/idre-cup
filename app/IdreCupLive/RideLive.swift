import ActivityKit
import SwiftUI
import WidgetKit

/// Расширение: Live Activity, виджет «Место в кубке» и кнопка записи для Пункта управления.
@main
struct IdreCupLiveBundle: WidgetBundle {
    var body: some Widget {
        RideLiveActivity()
        RideWidget()
        RecordControl()
    }
}

/// «Запись идёт»: экран блокировки, Dynamic Island, на Apple Watch показывается сама.
/// Данные обновляет приложение, пока пишет трек (см. LiveRide.swift).
struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideAttributes.self) { context in
            RideContent(context: context)
            .activityBackgroundTint(Theme.base)
            .activitySystemActionForegroundColor(Theme.textPrimary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.skiing.downhill")
                        Text("\(Format.kmh(context.state.topSpeed)) км/ч")
                            .lineLimit(1)
                    }
                    .font(Theme.headline(16))
                    .foregroundStyle(Theme.accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startedAt, style: .timer)
                        .font(Theme.headline(16))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 76, alignment: .trailing)
                        .foregroundStyle(Theme.textPrimary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(summary(context.state))
                        .font(Theme.caption(12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            } compactLeading: {
                Image(systemName: "figure.skiing.downhill")
                    .foregroundStyle(Theme.accent)
            } compactTrailing: {
                Text(Format.kmh(context.state.topSpeed))
                    .font(Theme.caption(13))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
            } minimal: {
                Image(systemName: "figure.skiing.downhill")
                    .foregroundStyle(Theme.accent)
            }
        }
        // Своя раскладка для Smart Stack на Apple Watch.
        .supplementalActivityFamilies([.small])
    }

    /// «629 м · 3 спуска · 2-е место, +19».
    private func summary(_ state: RideAttributes.ContentState) -> String {
        var parts = [
            "\(Format.meters(state.vertical)) м",
            "\(state.runs) \(Format.plural(state.runs, "спуск", "спуска", "спусков"))",
        ]
        if let points = state.points {
            let score = points < 0 ? "−\(-points)" : "+\(points)"
            parts.append(state.place.map { "\($0)-е место, \(score)" } ?? score)
        }
        if let title = state.eventTitle {
            parts.append("событие: \(title)")
        } else if let rival = state.duelWith {
            parts.append("дуэль: \(rival)")
        }
        return parts.joined(separator: " · ")
    }
}

/// Экран блокировки телефона или маленькая карточка в Smart Stack на часах.
private struct RideContent: View {
    @Environment(\.activityFamily) private var family
    let context: ActivityViewContext<RideAttributes>

    var body: some View {
        switch family {
        case .small:
            small
        default:
            RideLockScreenView(
                cupName: context.attributes.cupName,
                startedAt: context.attributes.startedAt,
                state: context.state,
                isStale: context.isStale
            )
        }
    }

    /// Часы: крупно скорость, ниже перепад, спуски и очки.
    private var small: some View {
        let state = context.state
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: state.paused ? "pause.fill" : "figure.skiing.downhill")
                Text(state.paused ? "ПАУЗА" : "ЗАПИСЬ")
                Spacer(minLength: 2)
                if !state.paused {
                    Text(context.attributes.startedAt, style: .timer)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                }
            }
            .font(Theme.overline(10))
            .foregroundStyle(Theme.accent)
            Text("\(Format.kmh(state.topSpeed)) км/ч")
                .font(Theme.title(22))
                .foregroundStyle(Theme.textPrimary)
                .minimumScaleFactor(0.7)
            Text(line(state))
                .font(Theme.caption(11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 4)
    }

    private func line(_ state: RideAttributes.ContentState) -> String {
        var parts = ["\(Format.meters(state.vertical)) м", "\(state.runs) \(Format.plural(state.runs, "спуск", "спуска", "спусков"))"]
        if let points = state.points {
            parts.append(points < 0 ? "−\(-points)" : "+\(points)")
        }
        return parts.joined(separator: " · ")
    }
}
