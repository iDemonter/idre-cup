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
        case evening

        var title: String {
            switch self {
            case .rating: return "Рейтинг"
            case .duels: return "Дуэли"
            case .map: return "Карта"
            case .day: return "Мой день"
            case .evening: return "Вечер"
            }
        }

        var symbol: String {
            switch self {
            case .rating: return "trophy.fill"
            case .duels: return "flag.checkered.2.crossed"
            case .map: return "mountain.2.fill"
            case .day: return "chart.bar.fill"
            case .evening: return "moon.stars.fill"
            }
        }
    }

    @ObservedObject private var tracker = Tracker.shared
    @ObservedObject private var network = NetworkMonitor.shared
    @StateObject private var homeStore = HomeStore()
    @StateObject private var session = Session()
    @State private var section: Screen
    @State private var live = LiveRide()
    private let data: PisteData
    private let terrain: TerrainData?

    init() {
        data = PisteData.load()
        terrain = TerrainData.load()
        // Раздел и демо-день можно задать при запуске: -section map -demo YES (для снимков экрана).
        // По умолчанию «Мой день»: утром там вся сводка дня (решено 17.11.2026).
        let asked = UserDefaults.standard.string(forKey: "section").flatMap { Screen(rawValue: $0) }
        _section = State(initialValue: asked ?? .day)
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
            if section == .evening {
                EveningScreen(data: data, terrain: terrain)
            }
            if UserDefaults.standard.bool(forKey: "livePreview") {
                LivePreview()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sectionBar
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            // Предложение 7: без сети жёлтый баннер. Трек пишется дальше, точки уйдут, когда появится связь.
            if network.isOffline {
                NoticeBanner(text: tracker.isRecording
                    ? "Нет связи. Запись идёт, трек уйдёт на сервер, когда появится сеть."
                    : "Нет связи. Показываем последние данные, обновим, когда появится сеть.")
            }
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
            // Часы показывают место, очки, событие и дуэль, пока приложение на телефоне живо.
            PhoneLink.shared.extra = { [weak session] in
                guard let session else { return [:] }
                var extra: [String: Any] = [:]
                if let place = session.todayPlace { extra["place"] = place }
                if let points = session.todayPoints { extra["points"] = points }
                if let title = session.eventTitle, let end = session.eventEnds {
                    extra["event"] = title
                    extra["eventEnds"] = end.timeIntervalSince1970
                }
                if let rival = session.duelWith, let end = session.duelEnds {
                    extra["duel"] = rival
                    extra["duelEnds"] = end.timeIntervalSince1970
                }
                return extra
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
                // Место и очки на часах обновляются вместе с рейтингом.
                PhoneLink.shared.trackerChanged()
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
                            // Предложение 5: флажки покачиваются, пока ждёт вызов на дуэль.
                            .symbolEffect(.wiggle, options: .repeating, isActive: item == .duels && session.duelCalls > 0)
                            .frame(width: 56, height: 30)
                            .background(isActive ? Palette.accentSoft : Color.clear, in: Capsule())
                            .overlay(alignment: .topTrailing) {
                                // Кто-то вызвал на дуэль и ждёт ответа.
                                if item == .duels && session.duelCalls > 0 {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Palette.error)
                                        .symbolEffect(.pulse, options: .repeating)
                                        .offset(x: -8, y: 2)
                                }
                            }
                        Text(item.title)
                            .font(Typo.caption2)
                    }
                    .foregroundStyle(isActive ? Palette.accentText : Palette.textSecondary)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Palette.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.border.opacity(0.6))
                .frame(height: 1)
        }
    }
}
