import AppIntents
import SwiftUI
import WidgetKit

// Предложение 9 из Figma: «Начать запись» в Пункте управления и на экране блокировки (RecordControl, узел 35:483)
// и виджет с местом и очками (RideWidget, узел 35:510).

/// Кнопка записи для Пункта управления, экрана блокировки и кнопки действия.
/// Нажатие выполняется в приложении (SetRecordingIntent — LiveActivityIntent): оно включает GPS и Live Activity.
struct RecordControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetShare.recordControlKind, provider: RecordingValue()) { isOn in
            ControlWidgetToggle("Запись трека", isOn: isOn, action: SetRecordingIntent()) { on in
                Label(on ? "Идёт запись" : "Начать запись", systemImage: on ? "stop.circle.fill" : "record.circle")
            }
            .tint(Palette.accent)
        }
        .displayName("Запись трека")
        .description("Начать или остановить запись трека Idre Cup.")
    }
}

struct RecordingValue: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        WidgetShare.read()?.recording ?? false
    }
}

// MARK: - Виджет: место и очки за сегодня

struct RideEntry: TimelineEntry {
    let date: Date
    let snapshot: RideSnapshot?
}

struct RideProvider: TimelineProvider {
    static let sample = RideSnapshot(cupName: "Idre Cup", dayNumber: 2, place: 2, points: 19, behind: "за Максом 4 очка", topSpeed: 76.3 / 3.6, vertical: 1840, runs: 9, recording: false, date: RideSnapshot.today())

    func placeholder(in context: Context) -> RideEntry {
        RideEntry(date: Date(), snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (RideEntry) -> Void) {
        completion(RideEntry(date: Date(), snapshot: context.isPreview ? Self.sample : WidgetShare.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RideEntry>) -> Void) {
        // Данные обновляет приложение; сама перерисовка раз в полчаса нужна, чтобы в полночь пропали вчерашние цифры.
        let entry = RideEntry(date: Date(), snapshot: WidgetShare.read())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

struct RideWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShare.rideWidgetKind, provider: RideProvider()) { entry in
            RideWidgetView(entry: entry)
                .containerBackground(Palette.surface, for: .widget)
        }
        .configurationDisplayName("Место в кубке")
        .description("Место и очки за сегодня, скорость и перепад.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct RideWidgetView: View {
    let entry: RideEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: RideSnapshot? { entry.snapshot?.isToday == true ? entry.snapshot : nil }

    private var title: String {
        let cup = (entry.snapshot?.cupName ?? "Idre Cup").uppercased()
        return snapshot?.dayNumber.map { "\(cup) · ДЕНЬ \($0)" } ?? cup
    }

    private var placeText: String {
        snapshot?.place.map { "\($0)-е" } ?? "–"
    }

    private var pointsLine: String {
        guard let snapshot, let points = snapshot.points else { return "сегодня ещё без спусков" }
        let sign = points > 0 ? "+\(points)" : "\(points)"
        return [sign, snapshot.behind].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Typo.overline)
                    .widgetAccentable()
                Text(snapshot?.place.map { "\($0)-е место · \(snapshot?.points.map { $0 > 0 ? "+\($0)" : "\($0)" } ?? "0")" } ?? "сегодня без спусков")
                    .font(Typo.headline)
                if let snapshot, snapshot.runs > 0 {
                    Text("макс \(Format.kmh(snapshot.topSpeed)) · \(Format.meters(snapshot.vertical)) м")
                        .font(Typo.caption1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            VStack(alignment: .leading, spacing: Spacing.s) {
                header
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: Spacing.xl) {
                    stat(snapshot.map { Format.kmh($0.topSpeed) } ?? "0", "км/ч")
                    stat(snapshot.map { Format.meters($0.vertical) } ?? "0", "м")
                    stat(String(snapshot?.runs ?? 0), "спусков")
                    Spacer(minLength: 0)
                    recordingMark
                }
            }
        default:
            VStack(alignment: .leading, spacing: Spacing.s) {
                header
                Spacer(minLength: 0)
                recordingMark
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(Palette.accentText)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(Typo.overline)
            .foregroundStyle(Palette.textSecondary)
            Text(placeText)
                .font(Typo.numberL)
                .foregroundStyle(Palette.textPrimary)
            Text(pointsLine)
                .font(Typo.caption1)
                .foregroundStyle(Palette.accentText)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var recordingMark: some View {
        if entry.snapshot?.recording == true {
            Label("идёт запись", systemImage: "record.circle")
                .font(Typo.caption2)
                .foregroundStyle(Palette.error)
        }
    }

    private func stat(_ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(Typo.numberM)
                .foregroundStyle(Palette.textPrimary)
            Text(unit)
                .font(Typo.caption2)
                .foregroundStyle(Palette.textSecondary)
        }
    }
}
