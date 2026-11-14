import MapKit
import SwiftUI

/// Первая сборка: рельеф Apple Maps над Idre Fjäll.
/// Камеру можно наклонять и вращать жестами, внизу готовые виды на склоны.
struct MapScreen: View {
    @StateObject private var location = LocationManager()
    @State private var position: MapCameraPosition = .camera(Resort.ViewPreset.overview.camera)
    @State private var look: MapLook = .satellite
    @State private var preset: Resort.ViewPreset? = .overview
    @State private var camera: MapCamera = Resort.ViewPreset.overview.camera

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            Annotation(Resort.name, coordinate: Resort.summit) {
                SummitMarker()
            }
        }
        .mapStyle(look.style)
        .mapControls {
            MapCompass()
            MapPitchToggle()
            MapScaleView()
            MapUserLocationButton()
        }
        .onMapCameraChange { context in
            camera = context.camera
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
                Text("IDRE FJÄLL · РЕЛЬЕФ APPLE MAPS")
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Resort.ViewPreset.allCases) { item in
                        presetChip(item)
                    }
                }
                .padding(.horizontal, 20)
            }

            HStack {
                Text(cameraReadout)
                    .font(Theme.caption(11))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
                Spacer()
                Text(buildLabel)
                    .font(Theme.caption(11))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Theme.surface.opacity(0.92))
    }

    private func presetChip(_ item: Resort.ViewPreset) -> some View {
        let isActive = item == preset
        return Button {
            preset = item
            withAnimation(.easeInOut(duration: 1.2)) {
                position = .camera(item.camera)
            }
        } label: {
            Text(item.rawValue)
                .font(Theme.caption())
                .foregroundStyle(isActive ? Theme.onAccent : Theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isActive ? Theme.accent : Theme.raised, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Параметры камеры: по ним подберём вид по умолчанию после первой сборки.
    private var cameraReadout: String {
        let lat = String(format: "%.4f", camera.centerCoordinate.latitude)
        let lon = String(format: "%.4f", camera.centerCoordinate.longitude)
        let distance = Int(camera.distance.rounded())
        let heading = Int(camera.heading.rounded())
        let pitch = Int(camera.pitch.rounded())
        return "\(lat), \(lon) · \(distance) м · курс \(heading)° · наклон \(pitch)°"
    }

    private var buildLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }
}

/// Метка вершины.
private struct SummitMarker: View {
    var body: some View {
        Image(systemName: "mountain.2.fill")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Theme.onAccent)
            .frame(width: 28, height: 28)
            .background(Theme.accent, in: Circle())
            .overlay(Circle().stroke(Theme.base, lineWidth: 2))
    }
}
