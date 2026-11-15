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
    /// Показать демо-день (трек строит RootView: ему известны трассы и рельеф).
    let startDemo: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if tracker.isDemo {
                    demoBanner
                }
                speedCard
                volumeCard
                recordButton
                if tracker.isDenied {
                    deniedNote
                }
                if let note = tracker.autoStopNote, !tracker.isRecording {
                    Text(note)
                        .font(Theme.caption())
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        .background(Theme.base.ignoresSafeArea())
        .task(id: session.phase == .signedIn) {
            while !Task.isCancelled && session.phase == .signedIn {
                if let day = await session.day() {
                    trails = day.myTrails ?? []
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

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
                    .font(Theme.overline())
                    .foregroundStyle(Theme.textSecondary)
                Text("Мой день")
                    .font(Theme.title(32))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(tracker.isRecording ? Theme.onAccent : Theme.textSecondary)
                    .frame(width: 8, height: 8)
                Text(tracker.isRecording ? "Запись идёт" : (tracker.isPaused ? "Пауза" : "Запись выключена"))
            }
            .font(Theme.caption())
            .foregroundStyle(tracker.isRecording ? Theme.onAccent : Theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tracker.isRecording ? Theme.accent : Theme.raised, in: Capsule())
        }
    }

    private var demoBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.circle.fill")
            Text("Демо-день: цифры выдуманы, трек проложен по трассам Nord")
                .font(Theme.caption())
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.accent)
        .padding(12)
        .background(Theme.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Скорость

    private var speedCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("МАКС. СКОРОСТЬ · ДЕРЖАЛ 3 СЕКУНДЫ")
                .font(Theme.overline())
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Format.kmh(tracker.stats.runs > 0 ? tracker.stats.topSpeed : 0))
                    .font(.system(size: 68, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .opacity(tracker.stats.runs > 0 ? 1 : 0.35)
                Text("км/ч")
                    .font(Theme.title(22))
            }
            Text(tracker.stats.runs > 0 ? "лучшая на спусках за день" : "появится после первого спуска")
                .font(Theme.caption())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(Theme.accent)
                .background(Theme.onAccent, in: Capsule())
        }
        .foregroundStyle(Theme.onAccent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Объём

    private var volumeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Объём")
                .font(Theme.headline(19))
                .foregroundStyle(Theme.textPrimary)
            HStack(alignment: .top, spacing: 8) {
                volumeItem("mountain.2.fill", Format.meters(tracker.stats.vertical) + " м", "перепад")
                volumeItem("arrow.triangle.2.circlepath", String(tracker.stats.runs), Format.plural(tracker.stats.runs, "спуск", "спуска", "спусков"))
                volumeItem("point.topleft.down.to.point.bottomright.curvepath", Format.km(tracker.stats.runDistance) + " км", "на спусках")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func volumeItem(_ symbol: String, _ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(height: 18)
            Text(value)
                .font(Theme.headline(20))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(Theme.caption())
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .font(Theme.caption())
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            .font(Theme.headline())
            .foregroundStyle(filled ? Theme.onAccent : Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(filled ? Theme.accent : Theme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.border, lineWidth: filled ? 0 : 1.5)
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
                    .font(Theme.caption())
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(14)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Всё, что записано, включая дорогу без спусков: по этой строке видно, что запись работает.
    private var recordingCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ЗАПИСАНО ЗА ДЕНЬ")
                .font(Theme.overline())
                .foregroundStyle(Theme.textSecondary)
            Text("\(Format.km(tracker.stats.totalDistance)) км · в движении \(Format.duration(tracker.stats.movingTime)) · \(Format.count(tracker.stats.pointCount)) \(Format.plural(tracker.stats.pointCount, "точка", "точки", "точек"))")
                .font(Theme.caption(13))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Спуски и подъёмы

    @ViewBuilder
    private var segmentList: some View {
        if !tracker.stats.segments.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("СПУСКИ И ПОДЪЁМЫ")
                    .font(Theme.overline())
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.bottom, 6)
                ForEach(Array(tracker.stats.segments.reversed())) { segment in
                    segmentRow(segment)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func segmentRow(_ segment: TrackSegment) -> some View {
        let isRun = segment.kind == .run
        return HStack(spacing: 12) {
            Image(systemName: isRun ? "arrow.down.right" : "arrow.up.right")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(isRun ? Theme.onAccent : Theme.textSecondary)
                .frame(width: 30, height: 30)
                .background(isRun ? Theme.accent : Theme.raised, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("\(isRun ? "Спуск" : "Подъём") · \(Format.clock(segment.start))")
                    .font(Theme.headline(15))
                    .foregroundStyle(Theme.textPrimary)
                if let trail = trail(for: segment) {
                    Text("\(trail.number) \(trail.name) · \(Format.lap(trail.seconds))")
                        .font(Theme.caption())
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                }
                Text(segmentDetails(segment))
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            if isRun {
                Text(Format.kmh(segment.topSpeed))
                    .font(Theme.headline(17))
                    .foregroundStyle(Theme.accent)
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
                .font(Theme.caption())
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.border, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                )
        }
        .buttonStyle(.plain)
    }
}
