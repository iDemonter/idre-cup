import CoreLocation
import SceneKit
import SwiftUI
import UIKit

/// Друг на карте: где он и что рисовать в кружке.
struct FriendMark: Equatable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let letter: String
    let photo: UIImage?
    /// Меняется вместе с аватаром: по нему модель понимает, что кружок пора перерисовать.
    let photoKey: String

    static func == (left: FriendMark, right: FriendMark) -> Bool {
        left.id == right.id && left.photoKey == right.photoKey
            && left.coordinate.latitude == right.coordinate.latitude && left.coordinate.longitude == right.coordinate.longitude
    }
}

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
    /// Остальные участники кубка: их аватары на горе.
    let friends: [FriendMark]
    /// Лес, дома и полезные места. Нажатие на значок места кладёт его в selectedPlace.
    let scenery: SceneryData?
    @Binding var selectedPlace: SceneryData.Place?
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
        if UserDefaults.standard.bool(forKey: "flipTest") {
            coordinator.flipForTest()
        }
        coordinator.select(selectedID)
        coordinator.showTrack(path, version: pathVersion)
        coordinator.showHome(home)
        coordinator.showFriends(friends)
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
        if friends != coordinator.friends {
            coordinator.showFriends(friends)
        }
    }

    // MARK: - Сцена

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        var parent: TerrainView
        let scene = SCNScene()
        let cameraNode = SCNNode()
        private(set) var cameraID: Int?
        /// Куда камеру направили последний раз: запасная точка поворота для keepUpright.
        private var lookTarget = SCNVector3Zero
        private(set) var selectedID: Int?
        private(set) var trackVersion: Int?
        private(set) var home: CLLocationCoordinate2D?
        private(set) var friends: [FriendMark] = []
        /// Кружки друзей. Меняются с главного потока, читаются при отрисовке: отсюда замок.
        private var friendNodes: [String: (node: SCNNode, photoKey: String)] = [:]
        private var friendList: [SCNNode] = []
        private let friendLock = NSLock()

        /// Одна единица сцены = 100 м.
        private let unit: Double = 100
        private let frame: LocalFrame
        private let terrain: TerrainData
        private let data: PisteData
        /// Всё, на что можно нажать: гора, трассы, значки. Лес и дома лежат отдельно и нажатия не ловят.
        private let touchable = SCNNode()
        private let highlightNode = SCNNode()
        private let trackNode = SCNNode()
        private var meNode: SCNNode?
        private var homeNode: SCNNode?
        /// Объёмные ели: видны вблизи, издалека лес нарисован на самой горе.
        private var treesNode: SCNNode?
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
            /// Ширина к высоте: у подписей районов значок вытянут.
            let aspect: Double
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
            scene.rootNode.addChildNode(touchable)

            let ground = SCNNode(geometry: terrainGeometry())
            ground.name = terrainName
            touchable.addChildNode(ground)
            touchable.addChildNode(highlightNode)
            touchable.addChildNode(trackNode)

            for lift in data.lifts {
                let line = lift.coords.map { frame.local($0) }
                let geometry = ribbon(line, width: 7, lift: 16, color: UIColor(Theme.raised))
                touchable.addChildNode(SCNNode(geometry: geometry))
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
                touchable.addChildNode(level)
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

            // Лес и дома.
            if let scenery = parent.scenery {
                let builder = SceneryBuilder(terrain: terrain, unit: unit)
                let forest = builder.trees(scenery.trees)
                scene.rootNode.addChildNode(forest)
                treesNode = forest
                scene.rootNode.addChildNode(builder.buildings(scenery.buildings))

                // Полезные места: светлый кружок с рисунком. Появляются вблизи, когда есть место.
                for (index, place) in scenery.places.enumerated() {
                    let image = Self.symbolImage(place.symbol, fill: UIColor.white, tint: UIColor(Theme.base))
                    addBadge(image: image, at: (place.east, place.north), above: 30, name: "place-\(index)", size: 20, rank: 3_000 - Double(index), number: nil)
                }
                // Названия районов посёлка.
                for (index, area) in scenery.areas.enumerated() {
                    let label = Self.labelImage(area.name)
                    addBadge(image: label.image, at: (area.east, area.north), above: 45, name: nil, size: 15, rank: 2_000 - Double(index), number: nil, aspect: label.aspect)
                }
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
        private func addBadge(image: UIImage, at place: (east: Double, north: Double), above: Double, name: String?, size: Double, rank: Double, number: Int?, always: Bool = false, aspect: Double = 1) -> SCNNode {
            let node = Self.badgeNode(image: image)
            node.name = name
            node.position = point(place.east, place.north, lift: above)
            touchable.addChildNode(node)
            badges.append(Badge(node: node, size: size, rank: rank, number: number, always: always, aspect: aspect, east: place.east, north: place.north, up: Double(node.position.y)))
            return node
        }

        /// Плоская картинка, всегда повёрнутая к камере и нарисованная поверх горы.
        private static func badgeNode(image: UIImage) -> SCNNode {
            let plane = SCNPlane(width: 1, height: 1)
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = image
            material.isDoubleSided = true
            material.readsFromDepthBuffer = false
            material.writesToDepthBuffer = false
            plane.materials = [material]
            let node = SCNNode(geometry: plane)
            node.constraints = [SCNBillboardConstraint()]
            node.renderingOrder = 100
            return node
        }

        /// Друзья: кружок с аватаром или буквой на месте последней точки каждого.
        func showFriends(_ marks: [FriendMark]) {
            friends = marks
            var next: [String: (node: SCNNode, photoKey: String)] = [:]
            for mark in marks {
                let place = frame.local(mark.coordinate)
                guard terrain.contains(east: place.east, north: place.north) else { continue }
                var entry = friendNodes[mark.id]
                if entry == nil || entry?.photoKey != mark.photoKey {
                    entry?.node.removeFromParentNode()
                    let node = Self.badgeNode(image: Self.friendImage(letter: mark.letter, photo: mark.photo))
                    node.renderingOrder = 110
                    touchable.addChildNode(node)
                    entry = (node, mark.photoKey)
                }
                if let entry {
                    entry.node.position = point(place.east, place.north, lift: 22)
                    next[mark.id] = entry
                }
            }
            for (id, entry) in friendNodes where next[id] == nil {
                entry.node.removeFromParentNode()
            }
            friendLock.lock()
            friendNodes = next
            friendList = next.values.map { $0.node }
            friendLock.unlock()
        }

        /// Кружок друга: фото или буква, тёмная обводка, чтобы читался на снегу.
        private static func friendImage(letter: String, photo: UIImage?) -> UIImage {
            let side: CGFloat = 96
            return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
                let box = CGRect(x: 6, y: 6, width: side - 12, height: side - 12)
                let circle = UIBezierPath(ovalIn: box)
                context.cgContext.saveGState()
                circle.addClip()
                if let photo {
                    photo.draw(in: box)
                } else {
                    UIColor(Theme.raised).setFill()
                    circle.fill()
                    let label = NSAttributedString(string: letter, attributes: [
                        .font: roundedFont(size: side * 0.42),
                        .foregroundColor: UIColor.white,
                    ])
                    let size = label.size()
                    label.draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2))
                }
                context.cgContext.restoreGState()
                UIColor.white.setStroke()
                circle.lineWidth = 6
                circle.stroke()
            }
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
            lookTarget = target
        }

        /// Проверка при сборке (-flipTest YES): ставит камеру за вершину вверх ногами.
        /// На снимке экрана модель должна остаться неперевёрнутой: keepUpright возвращает камеру.
        func flipForTest() {
            let eye = cameraNode.worldPosition
            let offsetX = eye.x - lookTarget.x
            let offsetY = eye.y - lookTarget.y
            let offsetZ = eye.z - lookTarget.z
            let reach = (offsetX * offsetX + offsetY * offsetY + offsetZ * offsetZ).squareRoot()
            let flat = max((offsetX * offsetX + offsetZ * offsetZ).squareRoot(), 0.001)
            let lean = Float(sin(10 * Double.pi / 180)) * reach
            let rise = Float(cos(10 * Double.pi / 180)) * reach
            cameraNode.worldPosition = SCNVector3(
                lookTarget.x - offsetX / flat * lean,
                lookTarget.y + rise,
                lookTarget.z - offsetZ / flat * lean
            )
            cameraNode.look(at: lookTarget, up: SCNVector3(0, -1, 0), localFront: SCNVector3(0, 0, -1))
        }

        /// Не даёт перевернуть модель. Камера всегда смотрит вниз под углом от 8° до 86° к горизонту,
        /// не заваливается набок и не оказывается вверх ногами: штатные ограничения SCNCameraController
        /// этого не гарантируют (жестом можно было перевалить через вершину). Вызывается перед каждым кадром.
        private func keepUpright(_ viewpoint: SCNNode) {
            let front = viewpoint.worldFront
            let up = viewpoint.worldUp
            let right = viewpoint.worldRight
            let lowest = 8.0
            let highest = 86.0
            // Угол взгляда вниз от горизонта, градусы.
            let down = Double(asin(max(-1, min(1, -front.y)))) * 180 / .pi
            let isFlipped = up.y < 0
            let isRolled = abs(right.y) > 0.03
            guard isFlipped || isRolled || down < lowest - 0.5 || down > highest + 0.5 else { return }

            // Куда камера смотрит по земле. Перевёрнутая смотрит назад; при взгляде отвесно вниз направление даёт верх кадра.
            var aheadX = Double(isFlipped ? -front.x : front.x)
            var aheadZ = Double(isFlipped ? -front.z : front.z)
            var length = (aheadX * aheadX + aheadZ * aheadZ).squareRoot()
            if length < 0.05 {
                aheadX = Double(up.x)
                aheadZ = Double(up.z)
                length = (aheadX * aheadX + aheadZ * aheadZ).squareRoot()
            }
            guard length > 0.001 else { return }
            aheadX /= length
            aheadZ /= length

            // Точка, вокруг которой поворачиваем: земля вдоль взгляда, а если взгляд выше горизонта, цель камеры.
            let eye = viewpoint.worldPosition
            let toTargetX = Double(eye.x - lookTarget.x)
            let toTargetY = Double(eye.y - lookTarget.y)
            let toTargetZ = Double(eye.z - lookTarget.z)
            var reach = (toTargetX * toTargetX + toTargetY * toTargetY + toTargetZ * toTargetZ).squareRoot()
            if front.y < -0.07 {
                let alongView = Double((eye.y - 2) / -front.y)
                if alongView > 1 { reach = min(alongView, 400) }
            }
            reach = max(reach, 1)
            let pivot = SCNVector3(
                eye.x + front.x * Float(reach),
                eye.y + front.y * Float(reach),
                eye.z + front.z * Float(reach)
            )
            let tilt = (isFlipped ? highest : min(max(down, lowest), highest)) * .pi / 180
            let position = SCNVector3(
                pivot.x - Float(aheadX * cos(tilt) * reach),
                pivot.y + Float(sin(tilt) * reach),
                pivot.z - Float(aheadZ * cos(tilt) * reach)
            )
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0
            viewpoint.worldPosition = position
            viewpoint.look(at: pivot, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
            SCNTransaction.commit()
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
                SCNHitTestOption.rootNode: touchable,
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
                guard let name = hit.node.name else { continue }
                if name.hasPrefix("piste-"), let id = Int(name.dropFirst(6)) {
                    parent.selectedPlace = nil
                    parent.selectedID = id
                    return
                }
                if name.hasPrefix("place-"), let index = Int(name.dropFirst(6)), let places = parent.scenery?.places, places.indices.contains(index) {
                    parent.selectedID = nil
                    parent.selectedPlace = places[index]
                    return
                }
            }
        }

        // MARK: - Размер и видимость значков

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard let viewpoint = renderer.pointOfView, let lens = viewpoint.camera else { return }
            keepUpright(viewpoint)
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
            treesNode?.isHidden = ground > 5_200
            var chosen = false
            for level in ribbonLevels {
                let fits = !chosen && ground <= level.upTo
                level.node.isHidden = !fits
                chosen = chosen || fits
            }

            // Значки: постоянный размер на экране; за горой и под более важным значком прячутся.
            var taken: [CGRect] = []

            // Друзья: всегда видны, значки трасс под ними прячутся.
            friendLock.lock()
            let friendsNow = friendList
            friendLock.unlock()
            for node in friendsNow {
                let dx = Double(node.position.x - eye.x)
                let dy = Double(node.position.y - eye.y)
                let dz = Double(node.position.z - eye.z)
                let away = max((dx * dx + dy * dy + dz * dz).squareRoot(), 0.01)
                let scale = Float(30 * away * spread / heightPoints)
                node.scale = SCNVector3(scale, scale, scale)
                let spot = renderer.projectPoint(node.position)
                taken.append(CGRect(x: Double(spot.x) - 16, y: Double(spot.y) - 16, width: 32, height: 32))
            }

            for badge in badges {
                let dx = Double(badge.node.position.x - eye.x)
                let dy = Double(badge.node.position.y - eye.y)
                let dz = Double(badge.node.position.z - eye.z)
                let away = max((dx * dx + dy * dy + dz * dz).squareRoot(), 0.01)
                let scale = Float(badge.size * away * spread / heightPoints)
                badge.node.scale = SCNVector3(scale * Float(badge.aspect), scale, scale)

                if badge.always {
                    // Своя точка и жильё: ничем не заслоняются и никого не вытесняют.
                    badge.node.isHidden = badge.node === homeNode ? !isHomeShown : !isMeShown
                    continue
                }

                let isSelected = badge.number != nil && badge.number == selectedNumber
                let spot = renderer.projectPoint(badge.node.position)
                let half = badge.size / 2 + 1.5
                let wide = half * badge.aspect
                let box = CGRect(x: Double(spot.x) - wide, y: Double(spot.y) - half, width: wide * 2, height: half * 2)
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

        /// Подпись района: тёмная плашка со светлым текстом. Возвращает картинку и её ширину к высоте.
        private static func labelImage(_ text: String) -> (image: UIImage, aspect: Double) {
            let height: CGFloat = 44
            let label = NSAttributedString(string: text.uppercased(), attributes: [
                .font: roundedFont(size: 22),
                .foregroundColor: UIColor.white,
                .kern: 1.2,
            ])
            let textSize = label.size()
            let size = CGSize(width: ceil(textSize.width) + 28, height: height)
            let image = UIGraphicsImageRenderer(size: size).image { _ in
                let plate = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1), cornerRadius: height / 2)
                UIColor(Theme.base).withAlphaComponent(0.78).setFill()
                plate.fill()
                label.draw(at: CGPoint(x: 14, y: (height - textSize.height) / 2))
            }
            return (image, Double(size.width / size.height))
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
