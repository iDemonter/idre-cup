import ActivityKit
import SwiftUI

/// Live Activity записи трека: начинается с записью, обновляется по ходу, убирается вместе с ней.
/// Данные идут прямо из приложения (оно живо в фоне, пока пишет трек), пуши для этого не нужны.
@MainActor
final class LiveRide {
    private var activity: Activity<RideAttributes>?
    private var shown: RideAttributes.ContentState?
    private var lastUpdate = Date.distantPast
    /// Запущена проверочная карточка (-liveTest YES): запись её не трогает.
    private var isTest = false
    /// Что последний раз сказали виджету и кнопке записи: связку ключей трогаем только при смене.
    private var sharedRecording: Bool?

    /// Приводит Live Activity в соответствие с записью. Вызывается при каждом пересчёте трека и раз в полминуты.
    func sync(tracker: Tracker, session: Session) {
        guard !isTest else { return }
        let stats = tracker.stats
        let state = RideAttributes.ContentState(
            topSpeed: (stats.topSpeed * 36).rounded() / 36,
            vertical: stats.vertical.rounded(),
            runs: stats.runs,
            place: session.todayPlace,
            points: session.todayPoints,
            duelWith: session.duelWith,
            duelEnds: session.duelEnds,
            eventTitle: session.eventTitle,
            eventEnds: session.eventEnds,
            paused: tracker.isPaused
        )
        // Виджет и кнопка записи: идёт ли запись (цифры дня виджет берёт с сервера, см. Session.publishToWidget).
        let recording = tracker.isRecording || tracker.isPaused
        if !tracker.isDemo, recording != sharedRecording {
            sharedRecording = recording
            WidgetShare.update { $0.recording = recording }
        }
        // На паузе карточка остаётся: день не закончен.
        apply(isRecording: (tracker.isRecording || tracker.isPaused) && !tracker.isDemo, cupName: session.cup?.name ?? "Idre Cup", state: state)
    }

    private func apply(isRecording: Bool, cupName: String, state: RideAttributes.ContentState) {
        guard isRecording else {
            end()
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if activity == nil {
            // Приложение перезапустилось во время записи: подхватываем уже показанную карточку.
            activity = Activity<RideAttributes>.activities.first
        }
        if let activity {
            // Система ограничивает частые обновления: не чаще раза в 10 секунд и только когда есть что менять.
            guard state != shown, Date().timeIntervalSince(lastUpdate) >= 10 else { return }
            shown = state
            lastUpdate = Date()
            let content = Self.content(state)
            Task { await activity.update(content) }
        } else {
            let attributes = RideAttributes(cupName: cupName, startedAt: Date())
            // Начать можно только из открытого приложения; если не вышло, попробуем при следующем вызове.
            activity = try? Activity.request(attributes: attributes, content: Self.content(state), pushType: nil)
            shown = state
            lastUpdate = Date()
        }
    }

    /// Через 10 минут без обновлений карточка помечается устаревшей: приложение, скорее всего, закрыли.
    private static func content(_ state: RideAttributes.ContentState) -> ActivityContent<RideAttributes.ContentState> {
        ActivityContent(state: state, staleDate: Date().addingTimeInterval(600))
    }

    func end() {
        activity = nil
        shown = nil
        let running = Activity<RideAttributes>.activities
        guard !running.isEmpty else { return }
        Task {
            for item in running {
                await item.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// Для снимков экрана при сборке (-liveTest YES): карточка с выдуманными цифрами без записи трека.
    func startTest() {
        isTest = true
        let attributes = RideAttributes(cupName: "Idre Cup 2027", startedAt: Date().addingTimeInterval(-4_980))
        activity = try? Activity.request(attributes: attributes, content: Self.content(LivePreview.sample), pushType: nil)
    }
}

/// Карточка экрана блокировки внутри приложения (-livePreview YES): проверка вёрстки по снимку экрана.
struct LivePreview: View {
    static let sample = RideAttributes.ContentState(
        topSpeed: 21.2,
        vertical: 1_840,
        runs: 9,
        place: 2,
        points: 19,
        duelWith: "Олег",
        duelEnds: Date().addingTimeInterval(1_500),
        eventTitle: "Охота на лидера",
        eventEnds: Date().addingTimeInterval(760)
    )

    var body: some View {
        VStack(spacing: 16) {
            Text("LIVE ACTIVITY · ЭКРАН БЛОКИРОВКИ")
                .font(Typo.overline)
                .foregroundStyle(Palette.textSecondary)
            card(LivePreview.sample, isStale: false)
            card(RideAttributes.ContentState(topSpeed: 0, vertical: 0, runs: 0), isStale: false)
            card(LivePreview.sample, isStale: true)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }

    private func card(_ state: RideAttributes.ContentState, isStale: Bool) -> some View {
        RideLockScreenView(cupName: "Idre Cup 2027", startedAt: Date().addingTimeInterval(-4_980), state: state, isStale: isStale)
            .background(Palette.base, in: RoundedRectangle(cornerRadius: Radius.cardLarge, style: .continuous))
    }
}
