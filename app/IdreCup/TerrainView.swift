import CoreLocation
import SceneKit
import SwiftUI
import UIKit

/// Вид «Модель»: 3D-гора из сетки высот, на ней трассы, подъёмники и значки.
/// Высота вытянута (TerrainData.exaggeration), чтобы пологая гора читалась.
/// Крутится одним пальцем, приближается щипком, сдвигается двумя пальцами.
struct TerrainView: UIViewRepresentable {
    let data: PisteData
    let terrain: TerrainData
    let camera: ModelCamera
    /// Свой трек за день и его номер версии: линия перестраивается, когда номер меняется.
    let path: [CLLocationCoordinate2D]
    let pathVersion: Int
    /// Жильё: звёздочка на модели. В режиме isPlacingHome нажатие на гору ставит её.
    let home: CLLocationCoordinate2D?
    let isPlacingHome: Bool
    let onPlaceHome: (CLLocationCoordinate2D) -> Void
    @Binding var selectedID: Int?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        let coordinator = context.coordinator
        view.scene = coordinator.scene
        view.backgroundColor = UIColor(Theme.base)
        view.antialiasingMode = .multisampling4X
        view.pointOfView = coordinator.cameraNode
        view.delegate = coordinator

        view.allowsCameraControl = true
        let controller = view.defaultCameraController
        controller.interactionMode = .orbitTurntable
        controller.inertiaEnabled = true
        controller.worldUp = SCNVector3(0, 1, 0)
        controller.minimumVerticalAngle = 8
        controller.maximumVerticalAngle = 86

        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)

        coordinator.apply(camera, to: view, animated: false)
        coordinator.select(selectedID)
        coordinator.showTrack(path, version: pathVersion)
        coordinator.showHome(home)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if camera.id != coordinator.cameraID {
            coordinator.apply(camera, to: view, animated: true)
        }
        if selectedID != coordinator.selectedID {
            coordinator.select(selectedID)
        }
        if pathVersion != coordinator.trackVersion {
            coordinator.showTrack(path, version: pathVersion)
        }
        if home?.latitude != coordinator.home?.latitude || home?.longitude != coordinator.home?.longitude {
            coordinator.showHome(home)
        }
    }

    // MARK: - Сцена

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        var parent: TerrainView
        let scene = SCNScene()
        let cameraNode = SCNNode()
        private(set) var cameraID: Int?
        private(set) var selectedID: Int?
        private(set) var trackVersion: Int?
        private(set) var home: CLLocationCoordinate2D?

        /// Одна единица сцены = 100 м.
        private let unit: Double = 100
        private let frame: LocalFrame
        private let terrain: TerrainData
        private let data: PisteData
        private let highlightNode = SCNNode()
        private let trackNode = SCNNode()
        private var meNode: SCNNode?
        private var homeNode: SCNNode?
        private var isHomeShown = false
        private let terrainName = "terrain"
        private var badges: [Badge] = []
        private var selectedNumber: Int?
        private var isMeShown = false
        private let screenScale = Double(UIScreen.main.scale)

        /// Ленты трасс трёх ширин: чем дальше камера, тем шире лента, иначе издалека её не видно.
        private var ribbonLevels: [(node: SCNNode, width: Double, upTo: Double)] = []

        /// Значок, который держит постоянный размер на экране.
        private struct Badge {
            let node: SCNNode
            /// Размер на экране в пунктах.
            let size: Double
            /// Важность: при нехватке места остаётся более важный значок.
            let rank: Double
            /// Номер трассы: значок выбранной трассы виден всегда.
            let number: Int?
            /// Виден всегда и поверх всего: своя точка.
            let always: Bool
            /// Место значка: метры от вершины и высота в единицах сцены.
            let east: Double
            let north: Double
            let up: Double
        }

        init(parent: TerrainView) {
            self.parent = parent
            terrain = parent.terrain
            data = parent.data
            frame = LocalFrame(origin: parent.data.summitCoordinate)
            super.init()
            buildScene()
        }

        private func buildScene() {
            scene.background.contents = UIColor(Theme.base)

            let lens = SCNCamera()
            lens.fieldOfView = 50
            lens.zNear = 0.5
            lens.zFar = 900
            cameraNode.camera = lens
            scene.rootNode.addChildNode(cameraNode)

            let ground = SCNNode(geometry: terrainGeometry())
            ground.name = terrainName
            scene.rootNode.addChildNode(ground)
            scene.rootNode.addChildNode(highlightNode)
            scene.rootNode.addChildNode(trackNode)

            for lift in data.lifts {
                let line = lift.coords.map { frame.local($0) }
                let geometry = ribbon(line, width: 7, lift: 16, color: UIColor(Theme.raised))
                scene.rootNode.addChildNode(SCNNode(geometry: geometry))
            }

            let lines = data.pistes.map { piste in piste.coords.map { frame.local($0) } }
            for (width, upTo) in [(22.0, 4_200.0), (34.0, 6_800.0), (52.0, Double.infinity)] {
                let level = SCNNode()
                for (piste, line) in zip(data.pistes, lines) {
                    let own = piste.isApproximate ? width * 0.6 : width
                    let node = SCNNode(geometry: ribbon(line, width: own, lift: lift(for: piste), color: UIColor(piste.color)))
                    node.name = "piste-\(piste.id)"
                    level.addChildNode(node)
                }
                level.isHidden = !ribbonLevels.isEmpty
                scene.rootNode.addChildNode(level)
                ribbonLevels.append((level, width, upTo))
            }

            let summit = Self.symbolImage("mountain.2.fill", fill: UIColor(Theme.accent), tint: UIColor(Theme.onAccent))
            addBadge(image: summit, at: (0, 0), above: 10, name: nil, size: 24, rank: 1_000_000, number: nil)

            for piste in data.labelled {
                let title = piste.number.map { String($0) } ?? "•"
                let outline = piste.difficulty == "black" ? UIColor.white : UIColor.white.withAlphaComponent(0.75)
                let image = Self.badgeImage(text: title, fill: UIColor(piste.color), outline: outline, isRound: piste.difficulty == "green", fontScale: 0.46)
                addBadge(image: image, at: frame.local(piste.mid), above: 10, name: "piste-\(piste.id)", size: 26, rank: 100_000 + (piste.show ?? 0), number: piste.number)
            }

            for lift in data.codedLifts {
                guard let mid = lift.mid else { continue }
                let image = LiftIcon.badge(LiftKind(osm: lift.kind))
                addBadge(image: image, at: frame.local(mid), above: 16, name: nil, size: 22, rank: lift.show ?? 0, number: nil)
            }

            // Жильё: звёздочка, видна всегда.
            let star = Self.symbolImage("star.fill", fill: UIColor(Theme.accent), tint: UIColor(Theme.onAccent))
            let homeMark = addBadge(image: star, at: (0, 0), above: 14, name: nil, size: 28, rank: 3_000_000, number: nil, always: true)
            homeMark.isHidden = true
            homeNode = homeMark

            // Своя точка: появляется вместе с треком.
            let me = addBadge(image: Self.dotImage(), at: (0, 0), above: 12, name: nil, size: 18, rank: 2_000_000, number: nil, always: true)
            me.isHidden = true
            meNode = me

            // Важные значки занимают место первыми.
            badges.sort { $0.rank > $1.rank }
        }

        /// Трассы разной сложности лежат на чуть разной высоте, чтобы не мерцать на пересечениях.
        private func lift(for piste: Piste) -> Double {
            switch piste.difficulty {
            case "green": return 5.0
            case "blue": return 5.6
            case "red": return 6.2
            case "black": return 6.8
            default: return 4.4
            }
        }

        private func point(_ east: Double, _ north: Double, lift: Double = 0) -> SCNVector3 {
            let up = terrain.height(east: east, north: north) * terrain.exaggeration + lift
            return SCNVector3(Float(east / unit), Float(up / unit), Float(-north / unit))
        }

        private func terrainGeometry() -> SCNGeometry {
            var vertices: [SCNVector3] = []
            var coordinates: [CGPoint] = []
            vertices.reserveCapacity(terrain.cols * terrain.rows)
            coordinates.reserveCapacity(terrain.cols * terrain.rows)
            for row in 0..<terrain.rows {
                for column in 0..<terrain.cols {
                    let east = terrain.west + Double(column) * terrain.step
                    let north = terrain.north - Double(row) * terrain.step
                    vertices.append(point(east, north))
                    coordinates.append(CGPoint(
                        x: Double(column) / Double(terrain.cols - 1),
                        y: Double(row) / Double(terrain.rows - 1)
                    ))
                }
            }

            var indices: [UInt32] = []
            indices.reserveCapacity((terrain.cols - 1) * (terrain.rows - 1) * 6)
            for row in 0..<(terrain.rows - 1) {
                for column in 0..<(terrain.cols - 1) {
                    let a = UInt32(row * terrain.cols + column)
                    let b = a + 1
                    let c = UInt32((row + 1) * terrain.cols + column)
                    let d = c + 1
                    indices.append(contentsOf: [a, c, b, b, c, d])
                }
            }

            let geometry = SCNGeometry(
                sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(textureCoordinates: coordinates)],
                elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
            )
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.isDoubleSided = true
            if let url = Bundle.main.url(forResource: "terrain", withExtension: "jpg"), let image = UIImage(contentsOfFile: url.path) {
                material.diffuse.contents = image
                material.diffuse.mipFilter = .linear
            } else {
                material.diffuse.contents = UIColor(Theme.textSecondary)
            }
            geometry.materials = [material]
            return geometry
        }

        /// Лента вдоль линии, лежащая на склоне. Ширина и подъём над землёй в метрах.
        private func ribbon(_ line: [(east: Double, north: Double)], width: Double, lift: Double, color: UIColor) -> SCNGeometry {
            // Дробим линию на шаги по 12 м, чтобы лента повторяла рельеф.
            var path: [(east: Double, north: Double)] = []
            for index in line.indices {
                let current = line[index]
                if index == 0 {
                    path.append(current)
                    continue
                }
                let previous = line[index - 1]
                let length = hypot(current.east - previous.east, current.north - previous.north)
                let parts = max(1, Int((length / 12).rounded(.up)))
                for part in 1...parts {
                    let t = Double(part) / Double(parts)
                    path.append((previous.east + (current.east - previous.east) * t, previous.north + (current.north - previous.north) * t))
                }
            }

            var vertices: [SCNVector3] = []
            var indices: [UInt32] = []
            if path.count >= 2 {
                for index in path.indices {
                    let before = path[max(index - 1, 0)]
                    let after = path[min(index + 1, path.count - 1)]
                    var dx = after.east - before.east
                    var dy = after.north - before.north
                    let length = max(hypot(dx, dy), 0.001)
                    dx /= length
                    dy /= length
                    let here = path[index]
                    let half = width / 2
                    vertices.append(point(here.east - dy * half, here.north + dx * half, lift: lift))
                    vertices.append(point(here.east + dy * half, here.north - dx * half, lift: lift))
                }
                for index in 0..<(path.count - 1) {
                    let a = UInt32(index * 2)
                    indices.append(contentsOf: [a, a + 1, a + 2, a + 2, a + 1, a + 3])
                }
            }

            let geometry = SCNGeometry(
                sources: [SCNGeometrySource(vertices: vertices)],
                elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
            )
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.isDoubleSided = true
            material.diffuse.contents = color
            geometry.materials = [material]
            return geometry
        }

        @discardableResult
        private func addBadge(image: UIImage, at place: (east: Double, north: Double), above: Double, name: String?, size: Double, rank: Double, number: Int?, always: Bool = false) -> SCNNode {
            let plane = SCNPlane(width: 1, height: 1)
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = image
            material.isDoubleSided = true
            material.readsFromDepthBuffer = false
            material.writesToDepthBuffer = false
            plane.materials = [material]

            let node = SCNNode(geometry: plane)
            node.name = name
            node.position = point(place.east, place.north, lift: above)
            node.constraints = [SCNBillboardConstraint()]
            node.renderingOrder = 100
            scene.rootNode.addChildNode(node)
            badges.append(Badge(node: node, size: size, rank: rank, number: number, always: always, east: place.east, north: place.north, up: Double(node.position.y)))
            return node
        }

        // MARK: - Камера и выбор

        func apply(_ camera: ModelCamera, to view: SCNView, animated: Bool) {
            cameraID = camera.id
            let target = point(camera.east, camera.north)
            let heading = camera.heading * .pi / 180
            let pitch = camera.pitch * .pi / 180
            let reach = camera.distance / unit
            let position = SCNVector3(
                target.x - Float(sin(heading) * sin(pitch) * reach),
                target.y + Float(cos(pitch) * reach),
                target.z + Float(cos(heading) * sin(pitch) * reach)
            )
            let viewpoint = view.pointOfView ?? cameraNode
            SCNTransaction.begin()
            SCNTransaction.animationDuration = animated ? 1.0 : 0
            viewpoint.position = position
            viewpoint.look(at: target, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
            SCNTransaction.commit()
            view.defaultCameraController.target = target
        }

        func select(_ id: Int?) {
            selectedID = id
            let piste = data.pistes.first { $0.id == id }
            selectedNumber = piste?.number
            highlightNode.childNodes.forEach { $0.removeFromParentNode() }
            guard let piste else { return }
            let segments = piste.number == nil ? [piste] : data.pistes.filter { $0.number == piste.number }
            for segment in segments {
                let line = segment.coords.map { frame.local($0) }
                let geometry = ribbon(line, width: 64, lift: 3.4, color: UIColor(Theme.accent))
                highlightNode.addChildNode(SCNNode(geometry: geometry))
            }
        }

        /// Свой трек: лента акцентного цвета и точка в его конце. Куски вне модели не рисуются.
        func showTrack(_ path: [CLLocationCoordinate2D], version: Int) {
            trackVersion = version
            trackNode.childNodes.forEach { $0.removeFromParentNode() }

            var pieces: [[(east: Double, north: Double)]] = []
            var piece: [(east: Double, north: Double)] = []
            for coordinate in path {
                let place = frame.local(coordinate)
                let jumped = piece.last.map { hypot($0.east - place.east, $0.north - place.north) > 400 } ?? false
                if !terrain.contains(east: place.east, north: place.north) || jumped {
                    if piece.count > 1 { pieces.append(piece) }
                    piece = []
                }
                if terrain.contains(east: place.east, north: place.north) {
                    piece.append(place)
                }
            }
            if piece.count > 1 { pieces.append(piece) }

            for line in pieces {
                trackNode.addChildNode(SCNNode(geometry: ribbon(line, width: 14, lift: 9, color: UIColor(Theme.accent))))
            }

            if let last = path.last {
                let place = frame.local(last)
                if terrain.contains(east: place.east, north: place.north) {
                    meNode?.position = point(place.east, place.north, lift: 12)
                    meNode?.isHidden = false
                    isMeShown = true
                    return
                }
            }
            isMeShown = false
            meNode?.isHidden = true
        }

        /// Звёздочка жилья. Если жильё за пределами модели, её не видно.
        func showHome(_ place: CLLocationCoordinate2D?) {
            home = place
            if let place {
                let spot = frame.local(place)
                if terrain.contains(east: spot.east, north: spot.north) {
                    homeNode?.position = point(spot.east, spot.north, lift: 14)
                    homeNode?.isHidden = false
                    isHomeShown = true
                    return
                }
            }
            isHomeShown = false
            homeNode?.isHidden = true
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            let hits = view.hitTest(gesture.location(in: view), options: [
                SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue,
            ])
            if parent.isPlacingHome {
                // Ближайшее к камере место на горе под пальцем.
                if let hit = hits.first(where: { $0.node.name == terrainName }) {
                    let spot = hit.worldCoordinates
                    parent.onPlaceHome(frame.coordinate(east: Double(spot.x) * unit, north: -Double(spot.z) * unit))
                }
                return
            }
            for hit in hits {
                if let name = hit.node.name, name.hasPrefix("piste-"), let id = Int(name.dropFirst(6)) {
                    parent.selectedID = id
                    return
                }
            }
        }

        // MARK: - Размер и видимость значков

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard let viewpoint = renderer.pointOfView, let lens = viewpoint.camera else { return }
            let heightPoints = Double(renderer.currentViewport.height) / screenScale
            guard heightPoints > 0 else { return }
            let eye = viewpoint.presentation.worldPosition
            let front = viewpoint.presentation.worldFront
            let spread = 2 * tan(Double(lens.fieldOfView) * .pi / 360)

            // Ширина лент по расстоянию от камеры до земли вдоль взгляда.
            var ground = Double.infinity
            if front.y < -0.01 {
                ground = Double((eye.y - 2) / -front.y) * unit
            }
            var chosen = false
            for level in ribbonLevels {
                let fits = !chosen && ground <= level.upTo
                level.node.isHidden = !fits
                chosen = chosen || fits
            }

            // Значки: постоянный размер на экране; за горой и под более важным значком прячутся.
            var taken: [CGRect] = []
            for badge in badges {
                let dx = Double(badge.node.position.x - eye.x)
                let dy = Double(badge.node.position.y - eye.y)
                let dz = Double(badge.node.position.z - eye.z)
                let away = max((dx * dx + dy * dy + dz * dz).squareRoot(), 0.01)
                let scale = Float(badge.size * away * spread / heightPoints)
                badge.node.scale = SCNVector3(scale, scale, scale)

                if badge.always {
                    // Своя точка и жильё: ничем не заслоняются и никого не вытесняют.
                    badge.node.isHidden = badge.node === homeNode ? !isHomeShown : !isMeShown
                    continue
                }

                let isSelected = badge.number != nil && badge.number == selectedNumber
                let spot = renderer.projectPoint(badge.node.position)
                let half = badge.size / 2 + 1.5
                let box = CGRect(x: Double(spot.x) - half, y: Double(spot.y) - half, width: half * 2, height: half * 2)
                var visible = spot.z > 0 && spot.z < 1
                if visible && !isSelected {
                    visible = !isBehindTerrain(badge, eye: eye) && !taken.contains { $0.intersects(box) }
                }
                badge.node.isHidden = !visible
                if visible {
                    taken.append(box)
                }
            }
        }

        /// Закрыт ли значок склоном: идём от значка к камере и сравниваем высоту луча с рельефом.
        private func isBehindTerrain(_ badge: Badge, eye: SCNVector3) -> Bool {
            let eyeEast = Double(eye.x) * unit
            let eyeNorth = -Double(eye.z) * unit
            let eyeUp = Double(eye.y)
            let flat = hypot(eyeEast - badge.east, eyeNorth - badge.north)
            guard flat > 120 else { return false }
            let reach = min(flat, 5_000)
            var walked = 80.0
            while walked < reach {
                let t = walked / flat
                let east = badge.east + (eyeEast - badge.east) * t
                let north = badge.north + (eyeNorth - badge.north) * t
                let ray = badge.up + (eyeUp - badge.up) * t
                let land = terrain.height(east: east, north: north) * terrain.exaggeration / unit
                if land > ray + 0.06 {
                    return true
                }
                walked += 40
            }
            return false
        }

        // MARK: - Картинки значков

        private static func badgeImage(text: String, fill: UIColor, outline: UIColor, isRound: Bool, fontScale: CGFloat) -> UIImage {
            let side: CGFloat = 64
            return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
                let box = CGRect(x: 3, y: 3, width: side - 6, height: side - 6)
                let path = UIBezierPath(roundedRect: box, cornerRadius: isRound ? box.width / 2 : box.width * 0.3)
                fill.setFill()
                path.fill()
                outline.setStroke()
                path.lineWidth = 4
                path.stroke()

                let label = NSAttributedString(string: text, attributes: [
                    .font: roundedFont(size: side * fontScale),
                    .foregroundColor: UIColor.white,
                ])
                let size = label.size()
                label.draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2))
            }
        }

        private static func symbolImage(_ name: String, fill: UIColor, tint: UIColor) -> UIImage {
            let side: CGFloat = 64
            return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
                let box = CGRect(x: 3, y: 3, width: side - 6, height: side - 6)
                let path = UIBezierPath(ovalIn: box)
                fill.setFill()
                path.fill()
                UIColor(Theme.base).setStroke()
                path.lineWidth = 5
                path.stroke()

                let setup = UIImage.SymbolConfiguration(pointSize: side * 0.36, weight: .bold)
                if let symbol = UIImage(systemName: name, withConfiguration: setup)?.withTintColor(tint, renderingMode: .alwaysOriginal) {
                    symbol.draw(at: CGPoint(x: (side - symbol.size.width) / 2, y: (side - symbol.size.height) / 2))
                }
            }
        }

        /// Своя точка: акцентный кружок в светлой обводке.
        private static func dotImage() -> UIImage {
            let side: CGFloat = 64
            return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
                let box = CGRect(x: 6, y: 6, width: side - 12, height: side - 12)
                let path = UIBezierPath(ovalIn: box)
                UIColor(Theme.accent).setFill()
                path.fill()
                UIColor.white.setStroke()
                path.lineWidth = 8
                path.stroke()
            }
        }

        private static func roundedFont(size: CGFloat) -> UIFont {
            let font = UIFont.systemFont(ofSize: size, weight: .heavy)
            if let descriptor = font.fontDescriptor.withDesign(.rounded) {
                return UIFont(descriptor: descriptor, size: size)
            }
            return font
        }
    }
}
