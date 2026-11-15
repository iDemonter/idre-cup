import MapKit
import SwiftUI

/// Карта трасс: 3D-модель горы или рельеф Apple Maps, поверх трассы по цветам сложности,
/// подъёмники и значки с номерами. Нажатие на значок открывает карточку трассы.
struct MapScreen: View {
    private let data: PisteData
    private let terrain: TerrainData?
    private let scenery = SceneryData.load()

    @EnvironmentObject private var tracker: Tracker
    @EnvironmentObject private var homeStore: HomeStore
    @EnvironmentObject private var session: Session
    /// Скачанные аватары друзей для кружков на карте: ключ «id-версия».
    @State private var friendPhotos: [String: UIImage] = [:]
    /// Короны по номеру трассы: для карточки трассы. Загружаются, когда трассу выбрали.
    @State private var crowns: [Int: CrownRow] = [:]
    @State private var position: MapCameraPosition
    @State private var look: MapLook
    @State private var modelCamera: ModelCamera
    @State private var activePreset: String?
    @State private var distance: Double = MapScreen.overviewDistance
    @State private var selectedID: Int?
    /// Выбранное на модели место: ресторан, прокат, ски-центр.
    @State private var selectedPlace: SceneryData.Place?
    /// Режим «поставить жильё»: следующее нажатие на карту ставит звёздочку.
    @State private var isPlacingHome = false

    private static let overviewName = "Обзор"
    private static let overviewDistance: Double = 9_500

    init(data loaded: PisteData, terrain loadedTerrain: TerrainData?) {
        data = loaded
        terrain = loadedTerrain

        // Вид и зону можно задать при запуске: -look Спутник -preset Nord.
        // Так делаются снимки экрана при сборке.
        let defaults = UserDefaults.standard
        let askedLook = defaults.string(forKey: "look").flatMap { MapLook(rawValue: $0) }
        let fallback: MapLook = loadedTerrain == nil ? .satellite : .model
        _look = State(initialValue: askedLook ?? fallback)

        // Для снимков экрана: -selectTrail 28 открывает карточку трассы с этим номером.
        let askedTrail = defaults.integer(forKey: "selectTrail")
        if askedTrail > 0, let piste = loaded.labelled.first(where: { $0.number == askedTrail }) {
            _selectedID = State(initialValue: piste.id)
        }

        let askedZone = defaults.string(forKey: "preset").flatMap { name in loaded.zones.first { $0.name == name } }
        if let zone = askedZone {
            _activePreset = State(initialValue: zone.name)
            _modelCamera = State(initialValue: MapScreen.modelCamera(for: zone, in: loaded))
            _position = State(initialValue: .camera(MapScreen.mapCamera(for: zone)))
        } else if defaults.string(forKey: "preset") == MapScreen.areaName {
            _activePreset = State(initialValue: MapScreen.areaName)
            _modelCamera = State(initialValue: MapScreen.modelArea)
            _position = State(initialValue: .camera(MapScreen.areaCamera(for: loaded)))
        } else {
            _activePreset = State(initialValue: MapScreen.overviewName)
            _modelCamera = State(initialValue: MapScreen.modelOverview(id: 0))
            _position = State(initialValue: .camera(MapScreen.overviewCamera(for: loaded)))
        }
    }

    private static func mapCamera(for zone: Zone) -> MapCamera {
        MapCamera(centerCoordinate: zone.coordinate, distance: 3_300, heading: zone.heading, pitch: 58)
    }

    /// Камера модели для зоны: смотрим от подножия к вершине, как и на карте Apple.
    private static func modelCamera(for zone: Zone, in data: PisteData) -> ModelCamera {
        let place = LocalFrame(origin: data.summitCoordinate).local(zone.center)
        return ModelCamera(id: 0, east: place.east, north: place.north, distance: 3_600, heading: zone.heading, pitch: 60)
    }

    private static func overviewCamera(for data: PisteData) -> MapCamera {
        MapCamera(centerCoordinate: data.summitCoordinate, distance: overviewDistance, heading: 0, pitch: 45)
    }

    /// Общий вид модели: с юго-запада, как на официальной карте курорта.
    private static func modelOverview(id: Int) -> ModelCamera {
        ModelCamera(id: id, east: -900, north: -350, distance: 6_400, heading: 55, pitch: 54)
    }

    /// «Весь район»: оба курорта и Städjan.
    private static let areaName = "Весь район"
    /// Смотрим с востока на запад: район вытянут с запада на восток и так целиком входит в высокий экран.
    /// Idre Fjäll ближе к зрителю, Himmelfjäll дальше, Städjan справа.
    private static let modelArea = ModelCamera(id: 0, east: -2_000, north: 1_350, distance: 16_000, heading: 270, pitch: 50)

    private static func areaCamera(for data: PisteData) -> MapCamera {
        MapCamera(
            centerCoordinate: LocalFrame(origin: data.summitCoordinate).coordinate(east: -2_000, north: 1_350),
            distance: 21_000,
            heading: 270,
            pitch: 40
        )
    }

    private var showsModel: Bool { look == .model && terrain != nil }

    private func person(for friend: LivePosition) -> Person {
        session.people.first { $0.id == friend.id } ?? Person(id: friend.id, name: friend.name ?? "?", isAdmin: false, avatar: nil)
    }

    /// Друзья для 3D-модели: место, буква и фото, если оно уже скачано.
    private var friendMarks: [FriendMark] {
        session.friends.map { friend in
            let who = person(for: friend)
            let key = "\(who.id)-\(who.avatar ?? 0)"
            let photo = friendPhotos[key]
            return FriendMark(
                id: friend.id,
                coordinate: CLLocationCoordinate2D(latitude: friend.lat, longitude: friend.lon),
                letter: String(who.name.prefix(1)).uppercased(),
                photo: photo,
                photoKey: photo == nil ? "буква-\(who.name.prefix(1))" : key
            )
        }
    }

    private func loadFriendPhotos() async {
        for friend in session.friends {
            let who = person(for: friend)
            let key = "\(who.id)-\(who.avatar ?? 0)"
            if who.avatar != nil, friendPhotos[key] == nil, let image = await session.avatarImage(for: who) {
                friendPhotos[key] = image
            }
        }
    }

    /// Звёздочка жилья для карты Apple: одна или ни одной.
    private var homeMarks: [HomeMark] {
        homeStore.home.map { [HomeMark(coordinate: $0)] } ?? []
    }

    private func placeHome(_ place: CLLocationCoordinate2D) {
        homeStore.set(place)
        isPlacingHome = false
    }

    /// Камера на жильё: смотрим от него в сторону вершины.
    private func showHome() {
        guard let home = homeStore.home else { return }
        let place = LocalFrame(origin: data.summitCoordinate).local(home)
        let heading = (atan2(-place.east, -place.north) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        activePreset = nil
        modelCamera = ModelCamera(id: modelCamera.id + 1, east: place.east, north: place.north, distance: 2_600, heading: heading, pitch: 58)
        withAnimation(.easeInOut(duration: 1.2)) {
            position = .camera(MapCamera(centerCoordinate: home, distance: 2_200, heading: heading, pitch: 55))
        }
    }

    /// «1,4 км» до жилья по прямой, если известно, где телефон.
    private var homeDistance: String? {
        guard let home = homeStore.home, let here = tracker.here else { return nil }
        let meters = CLLocation(latitude: here.latitude, longitude: here.longitude)
            .distance(from: CLLocation(latitude: home.latitude, longitude: home.longitude))
        guard meters < 50_000 else { return nil }
        return meters < 1_000 ? "\(Format.meters(meters)) м" : "\(Format.km(meters)) км"
    }

    /// Линия своего трека для карты Apple: одна или ни одной.
    private var trackLines: [TrackLine] {
        tracker.path.count > 1 ? [TrackLine(id: tracker.pathVersion, coordinates: tracker.path)] : []
    }

    private var selected: Piste? {
        guard let selectedID else { return nil }
        return data.pistes.first { $0.id == selectedID }
    }

    /// Все участки выбранной трассы: у одной трассы бывает несколько отрезков.
    private var selectedSegments: [Piste] {
        guard let selected else { return [] }
        guard let number = selected.number else { return [selected] }
        return data.pistes.filter { $0.number == number }
    }

    /// Значки появляются по мере приближения: у каждого своя высота камеры, с которой
    /// он не задевает соседние. Значок выбранной трассы виден всегда.
    private var visiblePisteBadges: [Piste] {
        data.labelled.filter { $0.number == selected?.number || distance <= ($0.show ?? 8_000) }
    }

    private var visibleLiftBadges: [Lift] {
        data.codedLifts.filter { distance <= ($0.show ?? 4_500) }
    }

    var body: some View {
        Group {
            if showsModel, let terrain {
                TerrainView(
                    data: data,
                    terrain: terrain,
                    camera: modelCamera,
                    path: tracker.path,
                    pathVersion: tracker.pathVersion,
                    home: homeStore.home,
                    isPlacingHome: isPlacingHome,
                    onPlaceHome: placeHome,
                    friends: friendMarks,
                    scenery: scenery,
                    selectedPlace: $selectedPlace,
                    selectedID: $selectedID
                )
                    .ignoresSafeArea()
            } else {
                appleMap
            }
        }
        .background(Theme.base.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            header
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomPanel
        }
        .onAppear {
            tracker.requestAccess()
            tracker.locateOnce()
        }
        .task(id: session.phase == .signedIn) {
            // Пока карта жива, раз в 15 секунд узнаём, где друзья.
            while !Task.isCancelled {
                await session.loadFriends()
                await loadFriendPhotos()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private var appleMap: some View {
        MapReader { proxy in
            appleMapContent
                // Нажатие ставит жильё только в режиме «поставить жильё», в остальное время жест не мешает карте.
                .gesture(isPlacingHome ? SpatialTapGesture().onEnded { tap in
                    if let place = proxy.convert(tap.location, from: .local) {
                        placeHome(place)
                    }
                } : nil)
        }
    }

    private var appleMapContent: some View {
        Map(position: $position) {
            ForEach(data.lifts) { lift in
                MapPolyline(coordinates: lift.coordinates)
                    .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 5]))
            }

            ForEach(selectedSegments) { piste in
                MapPolyline(coordinates: piste.coordinates)
                    .stroke(Theme.accent.opacity(0.7), style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
            }

            ForEach(data.outlinedPistes) { piste in
                MapPolyline(coordinates: piste.coordinates)
                    .stroke(Color.white.opacity(0.9), style: piste.outline)
            }

            ForEach(data.pistes) { piste in
                MapPolyline(coordinates: piste.coordinates)
                    .stroke(piste.color, style: piste.stroke)
            }

            ForEach(visibleLiftBadges) { lift in
                Annotation("", coordinate: lift.midCoordinate) {
                    LiftBadge(kind: LiftKind(osm: lift.kind))
                }
            }

            ForEach(visiblePisteBadges) { piste in
                Annotation("", coordinate: piste.midCoordinate) {
                    Button {
                        selectedID = piste.id
                    } label: {
                        PisteBadge(piste: piste, isSelected: piste.number == selected?.number)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let peaks = data.peaks, !peaks.isEmpty {
                ForEach(peaks) { peak in
                    Annotation(peak.title, coordinate: peak.coordinate) {
                        SummitMarker()
                    }
                }
            } else {
                Annotation(Resort.name, coordinate: data.summitCoordinate) {
                    SummitMarker()
                }
            }

            // Друзья.
            ForEach(session.friends) { friend in
                Annotation(friend.name ?? "", coordinate: CLLocationCoordinate2D(latitude: friend.lat, longitude: friend.lon)) {
                    AvatarView(person: person(for: friend), size: 30)
                        .environmentObject(session)
                }
            }

            // Жильё.
            ForEach(homeMarks) { mark in
                Annotation("", coordinate: mark.coordinate) {
                    HomeBadge()
                }
            }

            // Свой трек за день.
            ForEach(trackLines) { line in
                MapPolyline(coordinates: line.coordinates)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }

            UserAnnotation()
        }
        .mapStyle(look.style)
        .mapControls {
            MapCompass()
            MapPitchToggle()
            MapScaleView()
            MapUserLocationButton()
        }
        .onMapCameraChange { context in
            distance = context.camera.distance
        }
    }

    // MARK: - Шапка

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mapOverline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .font(Theme.overline())
                    .foregroundStyle(Theme.textSecondary)
                Text("Карта трасс")
                    .font(Theme.title())
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            lookMenu
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [Theme.base.opacity(0.95), Theme.base.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    /// «IDRE FJÄLL · 41 ТРАССА · HIMMELFJÄLL · 25».
    private var mapOverline: String {
        let neighbour = data.labelled.filter { $0.resort == "himmel" }.count
        let own = "IDRE FJÄLL · \(pisteCountTitle)"
        return neighbour > 0 ? "\(own) · HIMMELFJÄLL · \(neighbour)" : "\(own) НА КАРТЕ"
    }

    /// «41 трасса», «32 трассы», «35 трасс»: трассы самого Idre Fjäll.
    private var pisteCountTitle: String {
        let count = data.labelled.filter { $0.resort != "himmel" }.count
        let word: String
        if count % 10 == 1 && count % 100 != 11 {
            word = "ТРАССА"
        } else if (2...4).contains(count % 10) && !(12...14).contains(count % 100) {
            word = "ТРАССЫ"
        } else {
            word = "ТРАСС"
        }
        return "\(count) \(word)"
    }

    private var lookMenu: some View {
        Menu {
            ForEach(MapLook.allCases) { item in
                Button {
                    look = item
                } label: {
                    if item == look {
                        Label(item.rawValue, systemImage: "checkmark")
                    } else {
                        Text(item.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.3.layers.3d")
                Text(look.rawValue)
            }
            .font(Theme.caption())
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.accent, in: Capsule())
        }
    }

    // MARK: - Нижняя панель

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isPlacingHome {
                placingBanner
                    .padding(.horizontal, 20)
            } else if let selected {
                pisteCard(selected)
                    .padding(.horizontal, 20)
            } else if let place = selectedPlace, showsModel {
                placeCard(place)
                    .padding(.horizontal, 20)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    homeChip
                    presetChip(MapScreen.overviewName, model: MapScreen.modelOverview(id: 0)) {
                        MapScreen.overviewCamera(for: data)
                    }
                    ForEach(data.zones) { zone in
                        presetChip(zone.name, model: MapScreen.modelCamera(for: zone, in: data)) {
                            MapScreen.mapCamera(for: zone)
                        }
                    }
                    // Оба курорта и Städjan разом: видно, как они стоят относительно друг друга.
                    presetChip(MapScreen.areaName, model: MapScreen.modelArea) {
                        MapScreen.areaCamera(for: data)
                    }
                }
                .padding(.horizontal, 20)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    legendItem(Theme.pisteGreen, "очень лёгкая")
                    legendItem(Theme.pisteBlue, "лёгкая")
                    legendItem(Theme.pisteRed, "средняя")
                    legendItem(Theme.pisteBlack, "сложная", outlined: true)
                    ForEach(LiftKind.allCases, id: \.self) { kind in
                        HStack(spacing: 5) {
                            LiftBadge(kind: kind, size: 16)
                            Text(kind.title)
                                .font(Theme.caption(11))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            HStack {
                Text(showsModel ? "Карта: © OpenStreetMap · Высоты: Copernicus DEM" : "Трассы: © участники OpenStreetMap")
                    .font(Theme.caption(10))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
                Spacer()
                Text(buildLabel)
                    .font(Theme.caption(10))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Theme.surface.opacity(0.94))
    }

    // MARK: - Жильё

    /// Кнопка со звёздочкой: ставит жильё, а если оно уже стоит, показывает его.
    @ViewBuilder
    private var homeChip: some View {
        if homeStore.home == nil {
            Button {
                isPlacingHome = true
                tracker.locateOnce()
            } label: {
                homeChipLabel("Жильё")
            }
            .buttonStyle(.plain)
        } else {
            Menu {
                Button {
                    showHome()
                } label: {
                    Label("Показать на карте", systemImage: "scope")
                }
                Button {
                    isPlacingHome = true
                    tracker.locateOnce()
                } label: {
                    Label("Переставить", systemImage: "mappin.and.ellipse")
                }
                Button(role: .destructive) {
                    homeStore.clear()
                } label: {
                    Label("Убрать", systemImage: "trash")
                }
            } label: {
                homeChipLabel(homeDistance ?? "Жильё")
            } primaryAction: {
                showHome()
            }
        }
    }

    private func homeChipLabel(_ title: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "star.fill")
                .font(.system(size: 11, weight: .bold))
            Text(title)
        }
        .font(Theme.caption())
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.accent.opacity(0.18), in: Capsule())
    }

    private var placingBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                HomeBadge()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Нажмите на карту, где ваше жильё")
                        .font(Theme.headline(15))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Точнее всего на виде «Спутник»: там видны дома.")
                        .font(Theme.caption())
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                if let here = tracker.here {
                    Button {
                        placeHome(here)
                    } label: {
                        Text("Я сейчас в нём")
                            .font(Theme.caption())
                            .foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Theme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    isPlacingHome = false
                } label: {
                    Text("Отмена")
                        .font(Theme.caption())
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.raised, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Theme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func placeCard(_ place: SceneryData.Place) -> some View {
        HStack(spacing: 12) {
            Image(systemName: place.symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.base)
                .frame(width: 40, height: 40)
                .background(Color.white, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name ?? place.kindTitle)
                    .font(Theme.headline())
                    .foregroundStyle(Theme.textPrimary)
                Text(place.kindTitle)
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                selectedPlace = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Theme.raised, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Theme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func pisteCard(_ piste: Piste) -> some View {
        HStack(spacing: 12) {
            PisteBadge(piste: piste, isSelected: false, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(piste.name ?? "Трасса без названия")
                    .font(Theme.headline())
                    .foregroundStyle(Theme.textPrimary)
                Text(pisteDetails(piste))
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textSecondary)
                if let line = crownLine(piste) {
                    HStack(spacing: 5) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(line)
                            .font(Theme.caption())
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(Theme.accent)
                }
            }
            Spacer()
            Button {
                selectedID = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Theme.raised, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Theme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        // Ключ включает вход в кубок: карточка могла открыться раньше, чем приложение узнало участника.
        .task(id: "\(piste.id)-\(session.phase == .signedIn)") {
            if let reply = await session.crowns() {
                crowns = Dictionary(reply.trails.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })
            }
        }
    }

    /// Король трассы и его время; у незачётных трасс и вне кубка строки нет.
    private func crownLine(_ piste: Piste) -> String? {
        guard let number = piste.number, let row = crowns[number] else { return nil }
        guard let holder = row.holder else { return "корона свободна" }
        var text = "\(holder.name ?? "?") · \(Format.lap(holder.seconds))"
        if holder.id != session.me?.id {
            text += row.mine.map { " · моё \(Format.lap($0))" } ?? " · я здесь ещё не был"
        }
        return text
    }

    private func pisteDetails(_ piste: Piste) -> String {
        var parts: [String] = []
        if let zone = piste.zone { parts.append(zone) }
        parts.append(piste.difficultyName)
        let total = selectedSegments.filter { !$0.isAlternative }.reduce(0) { $0 + $1.length }
        if total > 0 { parts.append(piste.isApproximate ? "около \(total) м" : "\(total) м") }
        if piste.lit { parts.append("освещена") }
        if piste.isApproximate { parts.append("линия примерная") }
        return parts.joined(separator: " · ")
    }

    private func presetChip(_ name: String, model: ModelCamera, camera: @escaping () -> MapCamera) -> some View {
        let isActive = name == activePreset
        return Button {
            activePreset = name
            var next = model
            next.id = modelCamera.id + 1
            modelCamera = next
            withAnimation(.easeInOut(duration: 1.2)) {
                position = .camera(camera())
            }
        } label: {
            Text(name)
                .font(Theme.caption())
                .foregroundStyle(isActive ? Theme.onAccent : Theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isActive ? Theme.accent : Theme.raised, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func legendItem(_ color: Color, _ title: String, outlined: Bool = false) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(Color.white.opacity(outlined ? 0.85 : 0), lineWidth: 1))
            Text(title)
                .font(Theme.caption(11))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var buildLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }
}

/// Жильё как элемент списка для карты.
private struct HomeMark: Identifiable {
    let id = "home"
    let coordinate: CLLocationCoordinate2D
}

/// Звёздочка жилья.
private struct HomeBadge: View {
    var body: some View {
        Image(systemName: "star.fill")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Theme.onAccent)
            .frame(width: 28, height: 28)
            .background(Theme.accent, in: Circle())
            .overlay(Circle().stroke(Theme.base, lineWidth: 2))
    }
}

/// Линия трека как элемент списка для карты.
private struct TrackLine: Identifiable {
    let id: Int
    let coordinates: [CLLocationCoordinate2D]
}

/// Значок трассы: номер на цвете сложности, как на официальной карте.
private struct PisteBadge: View {
    let piste: Piste
    let isSelected: Bool
    var size: CGFloat = 26

    var body: some View {
        let isRound = piste.difficulty == "green"
        let radius = isRound ? size / 2 : size * 0.3
        let needsOutline = piste.difficulty == "black"
        let title = piste.badgeText
        return Text(title)
            .font(.system(size: size * 0.46, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.white)
            .frame(width: size, height: size)
            .background(piste.color, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(isSelected ? Theme.accent : Color.white.opacity(needsOutline ? 0.9 : 0.55), lineWidth: isSelected ? 3 : 1.5)
            )
    }
}

/// Значок подъёмника: рисунок по типу (гондола, кресельный, бугель, якорный, лента).
private struct LiftBadge: View {
    let kind: LiftKind
    var size: CGFloat = 22

    var body: some View {
        Image(uiImage: LiftIcon.badge(kind))
            .resizable()
            .frame(width: size, height: size)
    }
}

/// Метка вершины.
private struct SummitMarker: View {
    var body: some View {
        Image(systemName: "mountain.2.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.onAccent)
            .frame(width: 24, height: 24)
            .background(Theme.accent, in: Circle())
            .overlay(Circle().stroke(Theme.base, lineWidth: 2))
    }
}
