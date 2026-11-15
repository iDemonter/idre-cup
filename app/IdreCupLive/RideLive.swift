import ActivityKit
import SwiftUI
import WidgetKit

/// Расширение с Live Activity. Виджетов рабочего стола здесь нет.
@main
struct IdreCupLiveBundle: WidgetBundle {
    var body: some Widget {
        RideLiveActivity()
    }
}

/// «Запись идёт»: экран блокировки, Dynamic Island, на Apple Watch показывается сама.
/// Данные обновляет приложение, пока пишет трек (см. LiveRide.swift).
struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideAttributes.self) { context in
            RideLockScreenView(
                cupName: context.attributes.cupName,
                startedAt: context.attributes.startedAt,
                state: context.state,
                isStale: context.isStale
            )
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
