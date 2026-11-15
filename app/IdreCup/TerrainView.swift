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
    }

    // MARK: - Сцена

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        var parent: TerrainView
        let scene = SCNScene()
        let cameraNode = SCNNode()
        private(set) var cameraID: Int?
        private(set) var selectedID: Int?

        /// Одна единица сцены = 100 м.
        private let unit: Double = 100
        private let frame: LocalFrame
        private let terrain: TerrainData
        private let data: PisteData
        private let highlightNode = SCNNode()
        private var badges: [Badge] = []
        private var selectedNumber: Int?
        private let screenScale = Double(UIScreen.main.scale)

        /// Значок, который держит постоянный размер на экране.
        private struct Badge {
            let node: SCNNode
            /// Размер на экране в пунктах.
            let size: Double
            /// Сколько метров свободного места вокруг: значок виден, пока оно не меньше его размера.
            let room: Double
            /// Номер трассы: значок выбранной трассы виден всегда.
            let number: Int?
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

            scene.rootNode.addChildNode(SCNNode(geometry: terrainGeometry()))
            scene.rootNode.addChildNode(highlightNode)

            for lift in data.lifts {
                let line = lift.coords.map { frame.local($0) }
                let geometry = ribbon(line, width: 7, lift: 16, color: UIColor(Theme.raised))
                scene.rootNode.addChildNode(SCNNode(geometry: geometry))
            }

            for piste in data.pistes {
                let line = piste.coords.map { frame.local($0) }
                let node = SCNNode(geometry: ribbon(line, width: piste.isApproximate ? 14 : 24, lift: lift(for: piste), color: UIColor(piste.color)))
                node.name = "piste-\(piste.id)"
                scene.rootNode.addChildNode(node)
            }

            for lift in data.codedLifts {
                guard let mid = lift.mid, let code = lift.code else { continue }
                let image = Self.badgeImage(text: code, fill: UIColor(Theme.raised), outline: UIColor.white.withAlphaComponent(0.8), isRound: true, fontScale: 0.5)
                addBadge(image: image, at: frame.local(mid), above: 16, name: nil, size: 17, room: (lift.show ?? 4_500) / 24, number: nil)
            }

            for piste in data.labelled {
                let title = piste.number.map { String($0) } ?? "•"
                let outline = piste.difficulty == "black" ? UIColor.white : UIColor.white.withAlphaComponent(0.75)
                let image = Self.badgeImage(text: title, fill: UIColor(piste.color), outline: outline, isRound: piste.difficulty == "green", fontScale: 0.46)
                addBadge(image: image, at: frame.local(piste.mid), above: 10, name: "piste-\(piste.id)", size: 26, room: (piste.show ?? 8_000) / 24, number: piste.number)
            }

            let summit = Self.symbolImage("mountain.2.fill", fill: UIColor(Theme.accent), tint: UIColor(Theme.onAccent))
            addBadge(image: summit, at: (0, 0), above: 10, name: nil, size: 24, room: 100_000, number: nil)
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

        private func addBadge(image: UIImage, at place: (east: Double, north: Double), above: Double, name: String?, size: Double, room: Double, number: Int?) {
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
            badges.append(Badge(node: node, size: size, room: room, number: number))
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

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            let hits = view.hitTest(gesture.location(in: view), options: [
                SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue,
            ])
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
            let spread = 2 * tan(Double(lens.fieldOfView) * .pi / 360)
            for badge in badges {
                let place = badge.node.worldPosition
                let dx = Double(place.x - eye.x)
                let dy = Double(place.y - eye.y)
                let dz = Double(place.z - eye.z)
                let away = max((dx * dx + dy * dy + dz * dz).squareRoot(), 0.01)
                // Сколько единиц сцены приходится на один пункт экрана на этом расстоянии.
                let perPoint = away * spread / heightPoints
                let scale = Float(badge.size * perPoint)
                badge.node.scale = SCNVector3(scale, scale, scale)
                let roomPoints = badge.room / unit / perPoint
                let isSelected = badge.number != nil && badge.number == selectedNumber
                badge.node.isHidden = !isSelected && roomPoints < badge.size
            }
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

        private static func roundedFont(size: CGFloat) -> UIFont {
            let font = UIFont.systemFont(ofSize: size, weight: .heavy)
            if let descriptor = font.fontDescriptor.withDesign(.rounded) {
                return UIFont(descriptor: descriptor, size: size)
            }
            return font
        }
    }
}
