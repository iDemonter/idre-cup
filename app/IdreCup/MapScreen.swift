import MapKit
import SwiftUI

/// Карта трасс: рельеф Apple Maps, поверх него трассы по цветам сложности,
/// подъёмники и значки с номерами. Нажатие на значок открывает карточку трассы.
struct MapScreen: View {
    private let data: PisteData
    private let dimAreas: [DimArea]

    @StateObject private var location = LocationManager()
    @State private var position: MapCameraPosition
    @State private var look: MapLook = .satellite
    @State private var activePreset: String? = MapScreen.overviewName
    @State private var distance: Double = MapScreen.overviewDistance
    @State private var selectedID: Int?

    private static let overviewName = "Обзор"
    private static let overviewDistance: Double = 9_500

    init() {
        let loaded = PisteData.load()
        data = loaded
        dimAreas = [DimArea(center: loaded.summitCoordinate)]
        _position = State(initialValue: .camera(MapScreen.overviewCamera(for: loaded)))
    }

    private static func overviewCamera(for data: PisteData) -> MapCamera {
        MapCamera(centerCoordinate: data.summitCoordinate, distance: overviewDistance, heading: 0, pitch: 45)
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

    /// Значки с номерами появляются при приближении, иначе они закрывают всю гору.
    private var showPisteBadges: Bool { distance < 8_000 }
    private var showLiftBadges: Bool { distance < 4_500 }

    var body: some View {
        Map(position: $position) {
            ForEach(look.dimmed ? dimAreas : []) { area in
                MapPolygon(coordinates: area.coordinates)
                    .foregroundStyle(Theme.base.opacity(0.45))
            }

            ForEach(data.lifts) { lift in
                MapPolyline(coordinates: lift.coordinates)
                    .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 5]))
            }

            ForEach(selectedSegments) { piste in
                MapPolyline(coordinates: piste.coordinates)
                    .stroke(Theme.accent.opacity(0.55), style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
            }

            ForEach(data.blackPistes) { piste in
                MapPolyline(coordinates: piste.coordinates)
                    .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 6.5, lineCap: .round, lineJoin: .round))
            }

            ForEach(data.pistes) { piste in
                MapPolyline(coordinates: piste.coordinates)
                    .stroke(piste.color, style: piste.stroke)
            }

            ForEach(showLiftBadges ? data.codedLifts : []) { lift in
                Annotation("", coordinate: lift.midCoordinate) {
                    LiftBadge(code: lift.code ?? "")
                }
            }

            ForEach(showPisteBadges ? data.labelled : []) { piste in
                Annotation("", coordinate: piste.midCoordinate) {
                    Button {
                        selectedID = piste.id
                    } label: {
                        PisteBadge(piste: piste, isSelected: piste.number == selected?.number)
                    }
                    .buttonStyle(.plain)
                }
            }

            Annotation(Resort.name, coordinate: data.summitCoordinate) {
                SummitMarker()
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
        .safeAreaInset(edge: .top, spacing: 0) {
            header
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomPanel
        }
        .onAppear {
            location.requestAccess()
        }
    }

    // MARK: - Шапка

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("IDRE FJÄLL · \(data.labelled.count) ТРАСС НА КАРТЕ")
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
            if let selected {
                pisteCard(selected)
                    .padding(.horizontal, 20)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    presetChip(MapScreen.overviewName) {
                        MapScreen.overviewCamera(for: data)
                    }
                    ForEach(data.zones) { zone in
                        presetChip(zone.name) {
                            MapCamera(centerCoordinate: zone.coordinate, distance: 4_200, heading: zone.heading, pitch: 58)
                        }
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
                    HStack(spacing: 5) {
                        Text("┄┄")
                            .font(Theme.caption(11))
                            .foregroundStyle(Color.white.opacity(0.8))
                        Text("подъёмник")
                            .font(Theme.caption(11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.horizontal, 20)
            }

            HStack {
                Text("Трассы: © участники OpenStreetMap")
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

    private func presetChip(_ name: String, camera: @escaping () -> MapCamera) -> some View {
        let isActive = name == activePreset
        return Button {
            activePreset = name
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

/// Значок трассы: номер на цвете сложности, как на официальной карте.
private struct PisteBadge: View {
    let piste: Piste
    let isSelected: Bool
    var size: CGFloat = 26

    var body: some View {
        let isRound = piste.difficulty == "green"
        let radius = isRound ? size / 2 : size * 0.3
        let needsOutline = piste.difficulty == "black"
        let title = piste.number.map { String($0) } ?? "•"
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

/// Значок подъёмника: буква с официальной карты.
private struct LiftBadge: View {
    let code: String

    var body: some View {
        Text(code)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.textPrimary)
            .frame(width: 18, height: 18)
            .background(Theme.raised, in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 1))
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
