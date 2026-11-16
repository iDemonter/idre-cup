import CoreLocation
import SwiftUI

/// Повтор дня: аватары всех участников едут по своим трекам на 3D-модели одновременно.
struct ReplayView: View {
    let data: PisteData
    let terrain: TerrainData
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss

    @State private var reply: ReplayReply?
    @State private var didLoad = false
    @State private var clock: Double = 0
    @State private var isPlaying = true
    /// Во сколько раз быстрее жизни.
    @State private var speed: Double = 60
    @State private var photos: [String: UIImage] = [:]
    private let camera = ModelCamera(id: 0, east: -900, north: -350, distance: 6_400, heading: 55, pitch: 54)

    private static let scenery = SceneryData.load()
    private static let speeds: [Double] = [30, 60, 120, 300]
    /// Дольше этого без точек: человек пропадает с карты (запись выключена или нет связи).
    private static let gap: Double = 180

    var body: some View {
        ZStack(alignment: .bottom) {
            TerrainView(
                data: data,
                terrain: terrain,
                camera: camera,
                path: [],
                pathVersion: 0,
                here: nil,
                home: nil,
                isPlacingHome: false,
                onPlaceHome: { _ in },
                friends: marks,
                scenery: Self.scenery,
                selectedPlace: .constant(nil),
                selectedID: .constant(nil)
            )
            .ignoresSafeArea()
            .overlay(alignment: .top) { header }
            panel
        }
        .background(Theme.base.ignoresSafeArea())
        // Повтор могут открыть раньше, чем приложение вошло в кубок: загружаем, как только вошло.
        .task(id: session.phase == .signedIn) {
            if session.phase == .signedIn { await load() }
        }
        .task {
            // Шаг анимации 15 раз в секунду.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(66))
                guard isPlaying, let range else { continue }
                let next = clock + 0.066 * speed
                if next >= range.upperBound {
                    clock = range.upperBound
                    isPlaying = false
                } else {
                    clock = next
                }
            }
        }
    }

    private func load() async {
        let fresh = await session.replay()
        reply = fresh
        didLoad = true
        if let range {
            let start = UserDefaults.standard.double(forKey: "replayAt")
            clock = range.lowerBound + (range.upperBound - range.lowerBound) * (start > 0 ? start : 0)
            if start > 0 { isPlaying = false }
        }
        for track in fresh?.tracks ?? [] {
            if let person = session.people.first(where: { $0.id == track.id }), person.avatar != nil,
               let image = await session.avatarImage(for: person) {
                photos[track.id] = image
            }
        }
    }

    /// От первой до последней точки дня.
    private var range: ClosedRange<Double>? {
        let times = (reply?.tracks ?? []).flatMap { [$0.points.first?[0], $0.points.last?[0]] }.compactMap { $0 }
        guard let first = times.min(), let last = times.max(), last > first else { return nil }
        return first...last
    }

    /// Где человек был в момент clock: между соседними точками по прямой. nil, если в это время его не было.
    private func position(_ track: ReplayReply.Track) -> (coordinate: CLLocationCoordinate2D, speed: Double)? {
        let points = track.points
        guard let first = points.first, let last = points.last, clock >= first[0], clock <= last[0] else { return nil }
        var low = 0
        var high = points.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if points[middle][0] <= clock { low = middle } else { high = middle }
        }
        let before = points[low]
        let after = points[high]
        let span = after[0] - before[0]
        guard span <= Self.gap else { return nil }
        let share = span > 0 ? (clock - before[0]) / span : 0
        let coordinate = CLLocationCoordinate2D(
            latitude: before[1] + (after[1] - before[1]) * share,
            longitude: before[2] + (after[2] - before[2]) * share
        )
        let meters = CLLocation(latitude: before[1], longitude: before[2]).distance(from: CLLocation(latitude: after[1], longitude: after[2]))
        return (coordinate, span > 0 ? meters / span : 0)
    }

    private var marks: [FriendMark] {
        (reply?.tracks ?? []).compactMap { track in
            guard let spot = position(track) else { return nil }
            let photo = photos[track.id]
            return FriendMark(
                id: track.id,
                coordinate: spot.coordinate,
                letter: String(track.name.prefix(1)).uppercased(),
                photo: photo,
                photoKey: photo == nil ? "буква" : "фото"
            )
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("ПОВТОР ДНЯ")
                    .font(Theme.overline())
                    .foregroundStyle(Theme.textSecondary)
                Text(range == nil ? "—" : Format.clock(Date(timeIntervalSince1970: clock)))
                    .font(Theme.title(34))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(Theme.raised, in: Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let reply, let range {
                riders(reply)
                Slider(value: $clock, in: range)
                    .tint(Theme.accent)
                HStack(spacing: 8) {
                    Button {
                        if clock >= range.upperBound { clock = range.lowerBound }
                        isPlaying.toggle()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.onAccent)
                            .frame(width: 48, height: 40)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    ForEach(Self.speeds, id: \.self) { value in
                        Button {
                            speed = value
                        } label: {
                            Text(value == 60 ? "час/мин" : "×\(Int(value))")
                                .font(Theme.caption(12))
                                .foregroundStyle(speed == value ? Theme.onAccent : Theme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(speed == value ? Theme.accent : Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
                .buttonStyle(.plain)
            } else if didLoad || session.phase == .signedOut {
                Text("За сегодня треков нет: повтор появится после первых спусков.")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(Theme.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    /// Кто сейчас на карте и с какой скоростью едет.
    private func riders(_ reply: ReplayReply) -> some View {
        VStack(spacing: 4) {
            ForEach(reply.tracks) { track in
                let spot = position(track)
                HStack {
                    Text(track.name)
                        .font(Theme.headline(14))
                        .foregroundStyle(spot == nil ? Theme.textSecondary : Theme.textPrimary)
                    Spacer()
                    Text(spot.map { "\(Format.kmh($0.speed)) км/ч" } ?? "не на склоне")
                        .font(Theme.caption())
                        .monospacedDigit()
                        .foregroundStyle(spot == nil ? Theme.textSecondary : Theme.accent)
                }
            }
        }
    }
}
