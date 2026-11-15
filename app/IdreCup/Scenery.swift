import SceneKit
import UIKit

/// Окружение 3D-модели из файла Resources/scenery.json (собирает tools/build_terrain.py):
/// деревья, дома, полезные места и названия районов посёлка.
/// Дома и места: © участники OpenStreetMap. Лес расставлен по высоте: в данных он отмечен не везде.
struct SceneryData: Decodable {
    struct Place: Decodable, Equatable {
        let kind: String
        let name: String?
        let east: Double
        let north: Double

        /// Название вида места по-русски.
        var kindTitle: String {
            switch kind {
            case "center": return "Ски-центр"
            case "food": return "Еда"
            case "shop": return "Магазин"
            case "rental": return "Прокат"
            case "hotel": return "Отель и ресепшен"
            case "tickets": return "Скипассы"
            case "fun": return "Развлечения"
            case "shelter": return "Укрытие с очагом"
            case "fuel": return "Заправка"
            case "parking": return "Парковка"
            default: return "Место"
            }
        }

        var symbol: String {
            switch kind {
            case "center": return "house.lodge.fill"
            case "food": return "fork.knife"
            case "shop": return "cart.fill"
            case "rental": return "wrench.and.screwdriver.fill"
            case "hotel": return "bed.double.fill"
            case "tickets": return "ticket.fill"
            case "fun": return "figure.play"
            case "shelter": return "flame.fill"
            case "fuel": return "fuelpump.fill"
            case "parking": return "parkingsign"
            default: return "mappin"
            }
        }
    }

    struct Area: Decodable {
        let name: String
        let east: Double
        let north: Double
    }

    /// Тройки чисел: восток, север (метры от вершины) и размер от 0 до 9.
    let trees: [Int]
    /// Пятёрки чисел: середина (восток, север), длина, ширина, поворот в градусах.
    let buildings: [[Double]]
    let places: [Place]
    let areas: [Area]

    static func load() -> SceneryData? {
        guard
            let url = Bundle.main.url(forResource: "scenery", withExtension: "json"),
            let raw = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(SceneryData.self, from: raw)
    }
}

/// Строит лес и дома: много одинаковых простых фигур, слитых в несколько больших геометрий,
/// чтобы сцена рисовалась быстро. Грани раскрашены по трём тонам, как будто свет идёт с северо-запада
/// (так же, как тени на раскраске горы).
struct SceneryBuilder {
    let terrain: TerrainData
    /// Сколько метров в одной единице сцены.
    let unit: Double

    /// Направление на свет: восток, север, вверх.
    private let light = (east: -0.525, north: 0.525, up: 0.669)

    private func point(_ east: Double, _ north: Double, up: Double) -> SCNVector3 {
        SCNVector3(Float(east / unit), Float(up / unit), Float(-north / unit))
    }

    private func ground(_ east: Double, _ north: Double) -> Double {
        terrain.height(east: east, north: north) * terrain.exaggeration
    }

    private func brightness(east: Double, north: Double, up: Double) -> Double {
        let length = max((east * east + north * north + up * up).squareRoot(), 0.0001)
        return max(0, (east * light.east + north * light.north + up * light.up) / length)
    }

    private func node(_ triangles: [SCNVector3], color: UIColor) -> SCNNode {
        let indices = (0..<UInt32(triangles.count)).map { $0 }
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: triangles)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.diffuse.contents = color
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// Ели: пятигранные конусы. Освещённая сторона в снегу, теневая тёмная.
    func trees(_ data: [Int]) -> SCNNode {
        var lit: [SCNVector3] = []
        var mid: [SCNVector3] = []
        var dark: [SCNVector3] = []
        let sides = 5
        var index = 0
        while index + 2 < data.count {
            let east = Double(data[index])
            let north = Double(data[index + 1])
            let size = Double(data[index + 2])
            let number = index / 3
            index += 3

            let height = 26 + size * 2.2
            let radius = height * 0.27
            let base = ground(east, north) - 3
            let apex = point(east, north, up: base + height)
            let turn = Double(number % 7) * 0.37
            for side in 0..<sides {
                let from = turn + Double(side) / Double(sides) * 2 * .pi
                let to = turn + Double(side + 1) / Double(sides) * 2 * .pi
                let middle = (from + to) / 2
                let shade = brightness(east: cos(middle) * height, north: sin(middle) * height, up: radius)
                let triangle = [
                    apex,
                    point(east + cos(from) * radius, north + sin(from) * radius, up: base),
                    point(east + cos(to) * radius, north + sin(to) * radius, up: base),
                ]
                if shade > 0.6 {
                    lit.append(contentsOf: triangle)
                } else if shade > 0.28 {
                    mid.append(contentsOf: triangle)
                } else {
                    dark.append(contentsOf: triangle)
                }
            }
        }
        let forest = SCNNode()
        forest.addChildNode(node(lit, color: Self.rgb(0xC2CFEE)))
        forest.addChildNode(node(mid, color: Self.rgb(0x5E74AE)))
        forest.addChildNode(node(dark, color: Self.rgb(0x2F3D73)))
        return forest
    }

    /// Дома: коробка и двускатная крыша в снегу. Высота немного вытянута, чтобы домики читались.
    func buildings(_ data: [[Double]]) -> SCNNode {
        var wallLit: [SCNVector3] = []
        var wallDark: [SCNVector3] = []
        var roofLit: [SCNVector3] = []
        var roofDark: [SCNVector3] = []

        for item in data where item.count >= 5 {
            let length = item[2]
            let width = item[3]
            let angle = item[4] * .pi / 180
            let along = (east: cos(angle), north: sin(angle))
            let across = (east: -sin(angle), north: cos(angle))
            let isBig = length * width > 350
            let wall = (isBig ? 9.0 : 4.4) * 2
            let rise = min(width * 0.38, isBig ? 7 : 5) * 2

            func corner(_ u: Double, _ v: Double) -> (east: Double, north: Double) {
                (item[0] + along.east * u * length / 2 + across.east * v * width / 2,
                 item[1] + along.north * u * length / 2 + across.north * v * width / 2)
            }
            let corners = [corner(-1, -1), corner(1, -1), corner(1, 1), corner(-1, 1)]
            let heights = corners.map { ground($0.east, $0.north) }
            let bottom = (heights.min() ?? 0) - 2
            let top = (heights.max() ?? 0) + wall

            // Стены.
            for side in 0..<4 {
                let a = corners[side]
                let b = corners[(side + 1) % 4]
                let outward = (east: b.north - a.north, north: -(b.east - a.east))
                let quad = [
                    point(a.east, a.north, up: bottom), point(b.east, b.north, up: bottom), point(b.east, b.north, up: top),
                    point(a.east, a.north, up: bottom), point(b.east, b.north, up: top), point(a.east, a.north, up: top),
                ]
                if brightness(east: outward.east, north: outward.north, up: 0) > 0.2 {
                    wallLit.append(contentsOf: quad)
                } else {
                    wallDark.append(contentsOf: quad)
                }
            }

            // Крыша: конёк вдоль длинной стороны, два ската и два фронтона.
            let ridgeA = corner(-1, 0)
            let ridgeB = corner(1, 0)
            let ridge = top + rise
            for side in [-1.0, 1.0] {
                let a = corner(-1, side)
                let b = corner(1, side)
                let slope = [
                    point(a.east, a.north, up: top), point(b.east, b.north, up: top), point(ridgeB.east, ridgeB.north, up: ridge),
                    point(a.east, a.north, up: top), point(ridgeB.east, ridgeB.north, up: ridge), point(ridgeA.east, ridgeA.north, up: ridge),
                ]
                let shade = brightness(east: across.east * side * rise, north: across.north * side * rise, up: width / 2)
                if shade > 0.6 {
                    roofLit.append(contentsOf: slope)
                } else {
                    roofDark.append(contentsOf: slope)
                }
            }
            for end in [-1.0, 1.0] {
                let a = corner(end, -1)
                let b = corner(end, 1)
                let peak = corner(end, 0)
                let gable = [point(a.east, a.north, up: top), point(b.east, b.north, up: top), point(peak.east, peak.north, up: ridge)]
                if brightness(east: along.east * end, north: along.north * end, up: 0) > 0.2 {
                    wallLit.append(contentsOf: gable)
                } else {
                    wallDark.append(contentsOf: gable)
                }
            }
        }

        let village = SCNNode()
        village.addChildNode(node(wallLit, color: Self.rgb(0x46538F)))
        village.addChildNode(node(wallDark, color: Self.rgb(0x232C5C)))
        village.addChildNode(node(roofLit, color: Self.rgb(0xFFFFFF)))
        village.addChildNode(node(roofDark, color: Self.rgb(0xC3CFEC)))
        return village
    }
}
