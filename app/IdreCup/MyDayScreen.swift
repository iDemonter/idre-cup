import SwiftUI
import UIKit

/// «Мой день»: запись трека и итоги дня по нему. Макет: Figma, экран 04.
/// Места и очки появятся, когда заработает сервер; пока здесь только свои цифры.
struct MyDayScreen: View {
    @EnvironmentObject private var tracker: Tracker
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
                recordingCard
                segmentList
                demoButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.base.ignoresSafeArea())
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
                Text(tracker.isRecording ? "Запись идёт" : "Запись выключена")
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
                Text(tracker.stats.runs > 0 ? Format.kmh(tracker.stats.topSpeed) : "—")
                    .font(.system(size: 68, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
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

    private var recordButton: some View {
        Button {
            if tracker.isRecording {
                tracker.stop()
            } else {
                tracker.start()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tracker.isRecording ? "stop.fill" : "record.circle")
                Text(tracker.isRecording ? "Остановить запись" : "Начать запись")
            }
            .font(Theme.headline())
            .foregroundStyle(tracker.isRecording ? Theme.textPrimary : Theme.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(tracker.isRecording ? Theme.raised : Theme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.border, lineWidth: tracker.isRecording ? 1.5 : 0)
            )
        }
        .buttonStyle(.plain)
        .disabled(tracker.isDemo)
        .opacity(tracker.isDemo ? 0.4 : 1)
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
            Text("\(Format.km(tracker.stats.totalDistance)) км · в движении \(Format.duration(tracker.stats.movingTime)) · \(tracker.stats.pointCount) \(Format.plural(tracker.stats.pointCount, "точка", "точки", "точек"))")
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
            if tracker.isDemo {
                tracker.leaveDemo()
            } else {
                startDemo()
            }
        } label: {
            Text(tracker.isDemo ? "Выйти из демо-дня" : "Показать демо-день")
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
