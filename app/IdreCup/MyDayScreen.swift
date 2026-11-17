import SwiftUI
import UIKit

/// «Мой день»: запись трека и итоги дня по нему. Макет: Figma, экран 04.
/// Места и очки появятся, когда заработает сервер; пока здесь только свои цифры.
struct MyDayScreen: View {
    @EnvironmentObject private var tracker: Tracker
    @EnvironmentObject private var session: Session
    @ObservedObject private var link = PhoneLink.shared
    /// Мои пройденные трассы за день с сервера: ими подписываются спуски.
    @State private var trails: [MyTrail] = []
    /// Погода, лифты и снег на курорте, где сейчас телефон (иначе Idre Fjäll).
    @State private var conditions: ConditionsReply?
    /// Показать демо-день (трек строит RootView: ему известны трассы и рельеф).
    let startDemo: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if tracker.isDemo {
                    demoBanner
                }
                if isActive {
                    // Запись или пауза: наверху скорость и объём (предложение 3), сводка свёрнута в полосу.
                    DayHero(state: tracker.isRecording ? .recording : .paused, stats: tracker.stats)
                    recordButton
                    if let conditions {
                        ConditionsStrip(conditions: conditions)
                    }
                } else {
                    // До записи: сводка дня — погода, лифты, трассы, снег, прогноз (решено 17.11.2026).
                    if let conditions {
                        DayBrief(conditions: conditions)
                    }
                    recordButton
                    if tracker.stats.pointCount > 0 || tracker.isDemo {
                        DayHero(state: .off, stats: tracker.stats)
                    }
                }
                if tracker.isDenied {
                    deniedNote
                }
                if let note = tracker.autoStopNote, !tracker.isRecording {
                    Text(note)
                        .font(Typo.caption1)
                        .foregroundStyle(Palette.accentText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                }
                recordingCard
                segmentList
                if !tracker.isDemo {
                    demoButton
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Palette.base.ignoresSafeArea())
        .task(id: session.phase == .signedIn) {
            while !Task.isCancelled && session.phase == .signedIn {
                if let day = await session.day() {
                    trails = day.myTrails ?? []
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .task(id: session.phase == .signedIn) {
            // Условия меняются медленно: раз в 5 минут хватает (сервер сам ходит на сайты не чаще раза в 10 минут).
            while !Task.isCancelled && session.phase == .signedIn {
                if let fresh = await session.conditions(near: tracker.here) {
                    conditions = fresh
                    ConditionsAlerts.updateMorning(fresh)
                    ConditionsAlerts.scheduleClosing(fresh, recording: tracker.isRecording && !tracker.isDemo)
                }
                try? await Task.sleep(for: .seconds(300))
            }
        }
        .onChange(of: tracker.isRecording) { _, recording in
            if let conditions {
                ConditionsAlerts.scheduleClosing(conditions, recording: recording && !tracker.isDemo)
            }
        }
    }

    /// Идёт запись или пауза: тогда наверху DayHero, а не сводка дня.
    private var isActive: Bool { tracker.isRecording || tracker.isPaused }

    /// Трасса, пройденная на этом спуске: её отрезок лежит внутри спуска (с запасом на сглаживание).
    private func trail(for segment: TrackSegment) -> MyTrail? {
        guard segment.kind == .run, !tracker.isDemo else { return nil }
        let from = segment.start.timeIntervalSince1970 - 40
        let to = segment.end.timeIntervalSince1970 + 40
        return trails.first { $0.start >= from && $0.end <= to }
    }

    // MARK: - Шапка

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.day(Date()).uppercased())
                    .font(Typo.overline)
                    .foregroundStyle(Palette.textSecondary)
                Text("Мой день")
                    .font(Typo.largeTitle)
                    .foregroundStyle(Palette.textPrimary)
            }
            Spacer()
        }
    }

    private var demoBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.circle.fill")
            Text("Демо-день: цифры выдуманы, трек проложен по трассам Nord")
                .font(Typo.caption1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.accentText)
        .padding(12)
        .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }


    // MARK: - Запись

    @ViewBuilder
    private var recordButton: some View {
        if tracker.isDemo {
            bigButton("Вернуться к своему дню", symbol: "arrow.uturn.backward", filled: false) { tracker.leaveDemo() }
        } else if tracker.isRecording {
            HStack(spacing: 10) {
                bigButton("Пауза", symbol: "pause.fill", filled: false) { tracker.pause() }
                bigButton("Стоп", symbol: "stop.fill", filled: false) { tracker.stop() }
            }
        } else if tracker.isPaused {
            HStack(spacing: 10) {
                bigButton("Продолжить", symbol: "play.fill", filled: true) { tracker.start() }
                bigButton("Стоп", symbol: "stop.fill", filled: false) { tracker.stop() }
            }
        } else {
            bigButton("Начать запись", symbol: "record.circle", filled: true) { tracker.start() }
        }
        if link.hasWatchApp && !tracker.isAlways && !tracker.isDemo {
            Button {
                tracker.requestAlways()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "applewatch")
                    Text("Чтобы включать запись с часов, когда телефон в кармане, разреши геопозицию «Всегда». Нажми здесь.")
                        .multilineTextAlignment(.leading)
                }
                .font(Typo.caption1)
                .foregroundStyle(Palette.accentText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func bigButton(_ title: String, symbol: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(Typo.headline)
            .foregroundStyle(filled ? Palette.onAccent : Palette.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(filled ? Palette.accent : Palette.raised, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Palette.border, lineWidth: filled ? 0 : 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var deniedNote: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "location.slash.fill")
                Text("Нет доступа к геопозиции. Открыть настройки")
                    .font(Typo.caption1)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
            }
            .foregroundStyle(Palette.textPrimary)
            .padding(14)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Всё, что записано, включая дорогу без спусков: по этой строке видно, что запись работает.
    private var recordingCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ЗАПИСАНО ЗА ДЕНЬ")
                .font(Typo.overline)
                .foregroundStyle(Palette.textSecondary)
            Text("\(Format.km(tracker.stats.totalDistance)) км · в движении \(Format.duration(tracker.stats.movingTime)) · \(Format.count(tracker.stats.pointCount)) \(Format.plural(tracker.stats.pointCount, "точка", "точки", "точек"))")
                .font(Typo.footnote)
                .foregroundStyle(Palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    // MARK: - Спуски и подъёмы

    @ViewBuilder
    private var segmentList: some View {
        if !tracker.stats.segments.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("СПУСКИ И ПОДЪЁМЫ")
                    .font(Typo.overline)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.bottom, 6)
                ForEach(Array(tracker.stats.segments.reversed())) { segment in
                    segmentRow(segment)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }

    private func segmentRow(_ segment: TrackSegment) -> some View {
        let isRun = segment.kind == .run
        return HStack(spacing: 12) {
            Image(systemName: isRun ? "arrow.down.right" : "arrow.up.right")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(isRun ? Palette.onAccent : Palette.textSecondary)
                .frame(width: 30, height: 30)
                .background(isRun ? Palette.accent : Palette.raised, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("\(isRun ? "Спуск" : "Подъём") · \(Format.clock(segment.start))")
                    .font(Typo.subheadline)
                    .foregroundStyle(Palette.textPrimary)
                if let trail = trail(for: segment) {
                    Text("\(Format.trail(trail.number)) \(trail.name) · \(Format.lap(trail.seconds))")
                        .font(Typo.caption1)
                        .foregroundStyle(Palette.accentText)
                        .lineLimit(1)
                }
                Text(segmentDetails(segment))
                    .font(Typo.caption1)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 0)
            if isRun {
                Text(Format.kmh(segment.topSpeed))
                    .font(Typo.headline)
                    .foregroundStyle(Palette.accentText)
            }
        }
        .padding(.vertical, 8)
    }

    private func segmentDetails(_ segment: TrackSegment) -> String {
        let sign = segment.kind == .run ? "−" : "+"
        return "\(sign)\(Format.meters(segment.vertical)) м · \(Format.km(segment.distance)) км · \(Format.duration(segment.duration))"
    }

    // MARK: - Демо

    private var demoButton: some View {
        Button {
            startDemo()
        } label: {
            Text("Показать демо-день")
                .font(Typo.caption1)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .stroke(Palette.border, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                )
        }
        .buttonStyle(.plain)
    }
}
