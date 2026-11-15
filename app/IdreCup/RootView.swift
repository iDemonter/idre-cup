import CoreLocation
import SwiftUI

/// Корень приложения: разделы и нижняя панель. Раздел «Вечер» из макета
/// добавится вместе с вечерними играми.
struct RootView: View {
    enum Screen: String, CaseIterable {
        case rating
        case duels
        case map
        case day

        var title: String {
            switch self {
            case .rating: return "Рейтинг"
            case .duels: return "Дуэли"
            case .map: return "Карта"
            case .day: return "Мой день"
            }
        }

        var symbol: String {
            switch self {
            case .rating: return "trophy.fill"
            case .duels: return "flag.checkered.2.crossed"
            case .map: return "mountain.2.fill"
            case .day: return "chart.bar.fill"
            }
        }
    }

    @StateObject private var tracker = Tracker()
    @StateObject private var homeStore = HomeStore()
    @StateObject private var session = Session()
    @State private var section: Screen
    @State private var live = LiveRide()
    private let data: PisteData
    private let terrain: TerrainData?

    init() {
        data = PisteData.load()
        terrain = TerrainData.load()
        // Раздел и демо-день можно задать при запуске: -section day -demo YES (для снимков экрана).
        let asked = UserDefaults.standard.string(forKey: "section").flatMap { Screen(rawValue: $0) }
        _section = State(initialValue: asked ?? .map)
    }

    var body: some View {
        ZStack {
            // Карта остаётся в памяти, чтобы 3D-сцена не строилась заново при каждом переключении.
            MapScreen(data: data, terrain: terrain)
                .opacity(section == .map ? 1 : 0)
                .allowsHitTesting(section == .map)
            if section == .day {
                MyDayScreen(startDemo: showDemo)
            }
            if section == .rating {
                RatingScreen()
            }
            if section == .duels {
                DuelsScreen()
            }
            if UserDefaults.standard.bool(forKey: "livePreview") {
                LivePreview()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sectionBar
        }
        .environmentObject(tracker)
        .environmentObject(homeStore)
        .environmentObject(session)
        .task {
            // Live Activity следует за записью: трекер сообщает о каждом пересчёте, в том числе в фоне.
            let tracker = self.tracker
            let session = self.session
            let live = self.live
            if UserDefaults.standard.bool(forKey: "liveTest") {
                live.startTest()
            }
            // Кнопка «Начать запись» в уведомлении: включаем запись и открываем «Мой день».
            Notifier.shared.onStartRecording = { [weak tracker] in
                tracker?.start()
                section = .day
            }
            if Notifier.shared.pendingStart {
                Notifier.shared.pendingStart = false
                tracker.start()
                section = .day
            }
            tracker.onChange = { [weak tracker, weak session] in
                guard let tracker, let session else { return }
                live.sync(tracker: tracker, session: session)
            }
            await session.start()
            // Пока приложение живо (в том числе в фоне во время записи), трек уходит на сервер раз в полминуты.
            while !Task.isCancelled {
                await session.sync(tracker)
                // Заодно узнаём, не вызвал ли кто на дуэль: на вкладке загорится точка.
                _ = await session.duels()
                _ = await session.events()
                if tracker.isRecording {
                    await session.refreshToday()
                }
                live.sync(tracker: tracker, session: session)
                try? await Task.sleep(for: .seconds(30))
            }
        }
        // Утренние напоминания включить запись: по датам кубка.
        .onChange(of: "\(session.cup?.startsOn ?? "")|\(session.cup?.days ?? 0)") { _, _ in
            if session.phase == .signedIn {
                Notifier.scheduleMornings(startsOn: session.cup?.startsOn, days: session.cup?.days ?? 0)
            }
        }
        // Жильё общее на кубок: что поставил один, видят все.
        .onChange(of: session.cup?.home) { _, shared in
            if let shared {
                homeStore.set(CLLocationCoordinate2D(latitude: shared.lat, longitude: shared.lon))
            } else if session.phase == .signedIn, let mine = homeStore.home {
                Task { await session.shareHome(HomePoint(lat: mine.latitude, lon: mine.longitude)) }
            }
        }
        .onChange(of: homeKey) { _, _ in
            let mine = homeStore.home.map { HomePoint(lat: $0.latitude, lon: $0.longitude) }
            Task { await session.shareHome(mine) }
        }
        .onAppear {
            if UserDefaults.standard.bool(forKey: "demo") {
                showDemo()
            }
        }
    }

    /// Меняется, когда человек ставит, двигает или убирает жильё.
    private var homeKey: String {
        homeStore.home.map { "\($0.latitude),\($0.longitude)" } ?? "нет"
    }

    private func showDemo() {
        guard let terrain else { return }
        tracker.showDemo(DemoTrack.make(data: data, terrain: terrain))
    }

    private var sectionBar: some View {
        HStack(spacing: 4) {
            ForEach(Screen.allCases, id: \.self) { item in
                let isActive = item == section
                Button {
                    section = item
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 17, weight: .bold))
                            .frame(width: 56, height: 30)
                            .background(isActive ? Theme.accent.opacity(0.18) : Color.clear, in: Capsule())
                            .overlay(alignment: .topTrailing) {
                                // Кто-то вызвал на дуэль и ждёт ответа.
                                if item == .duels && session.duelCalls > 0 {
                                    Circle()
                                        .fill(Theme.pisteRed)
                                        .frame(width: 10, height: 10)
                                        .offset(x: -8, y: 2)
                                }
                            }
                        Text(item.title)
                            .font(Theme.caption(11))
                    }
                    .foregroundStyle(isActive ? Theme.accent : Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Theme.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.border.opacity(0.6))
                .frame(height: 1)
        }
    }
}
