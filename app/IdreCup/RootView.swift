import CoreLocation
import SwiftUI

/// Корень приложения: разделы и нижняя панель. Разделы «Дуэли» и «Вечер» из макета
/// добавятся вместе с этими механиками.
struct RootView: View {
    enum Screen: String, CaseIterable {
        case rating
        case map
        case day

        var title: String {
            switch self {
            case .rating: return "Рейтинг"
            case .map: return "Карта"
            case .day: return "Мой день"
            }
        }

        var symbol: String {
            switch self {
            case .rating: return "trophy.fill"
            case .map: return "mountain.2.fill"
            case .day: return "chart.bar.fill"
            }
        }
    }

    @StateObject private var tracker = Tracker()
    @StateObject private var homeStore = HomeStore()
    @StateObject private var session = Session()
    @State private var section: Screen
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
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sectionBar
        }
        .environmentObject(tracker)
        .environmentObject(homeStore)
        .environmentObject(session)
        .task {
            await session.start()
            // Пока приложение живо (в том числе в фоне во время записи), трек уходит на сервер раз в полминуты.
            while !Task.isCancelled {
                await session.sync(tracker)
                try? await Task.sleep(for: .seconds(30))
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
        HStack(spacing: 8) {
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
                        Text(item.title)
                            .font(Theme.caption(11))
                    }
                    .foregroundStyle(isActive ? Theme.accent : Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
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
