import SwiftUI
import UIKit

/// Тип подъёмника: от него зависит значок на карте.
enum LiftKind: String, CaseIterable {
    case gondola
    case chair
    case platter
    case tbar
    case carpet

    /// Тип из OpenStreetMap (тег aerialway).
    init(osm: String) {
        switch osm {
        case "gondola", "cable_car", "mixed_lift":
            self = .gondola
        case "chair_lift":
            self = .chair
        case "t-bar":
            self = .tbar
        case "magic_carpet":
            self = .carpet
        default:
            self = .platter
        }
    }

    var title: String {
        switch self {
        case .gondola: return "гондола"
        case .chair: return "кресельный"
        case .platter: return "бугель"
        case .tbar: return "якорный"
        case .carpet: return "лента"
        }
    }
}

/// Значки подъёмников: тёмный кружок со светлым рисунком типа.
/// Рисуются кодом, чтобы один и тот же значок был и на карте Apple, и на 3D-модели.
enum LiftIcon {
    private static var ready: [String: UIImage] = [:]
    private static let stroke: CGFloat = 0.09

    static func badge(_ kind: LiftKind) -> UIImage {
        if let image = ready[kind.rawValue] {
            return image
        }
        let side: CGFloat = 72
        let paper = UIColor(Theme.raised)
        let ink = UIColor.white
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            let box = CGRect(x: 3, y: 3, width: side - 6, height: side - 6)
            let circle = UIBezierPath(ovalIn: box)
            paper.setFill()
            circle.fill()
            UIColor.white.withAlphaComponent(0.9).setStroke()
            circle.lineWidth = 3.5
            circle.stroke()
            draw(kind, in: box.insetBy(dx: side * 0.13, dy: side * 0.13), ink: ink, paper: paper)
        }
        ready[kind.rawValue] = image
        return image
    }

    /// Рисунок в квадрате area. Координаты ниже заданы в долях стороны: 0 слева и сверху, 1 справа и снизу.
    private static func draw(_ kind: LiftKind, in area: CGRect, ink: UIColor, paper: UIColor) {
        func point(_ px: CGFloat, _ py: CGFloat) -> CGPoint {
            CGPoint(x: area.minX + px * area.width, y: area.minY + py * area.height)
        }

        func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, width: CGFloat, color: UIColor) {
            let path = UIBezierPath()
            path.move(to: point(x1, y1))
            path.addLine(to: point(x2, y2))
            path.lineWidth = width * area.width
            path.lineCapStyle = .round
            color.setStroke()
            path.stroke()
        }

        func block(_ left: CGFloat, _ top: CGFloat, _ width: CGFloat, _ height: CGFloat, radius: CGFloat, color: UIColor) {
            let origin = point(left, top)
            let box = CGRect(x: origin.x, y: origin.y, width: width * area.width, height: height * area.height)
            color.setFill()
            UIBezierPath(roundedRect: box, cornerRadius: radius * area.width).fill()
        }

        func dot(_ cx: CGFloat, _ cy: CGFloat, radius: CGFloat, color: UIColor) {
            let center = point(cx, cy)
            let size = radius * area.width
            color.setFill()
            UIBezierPath(ovalIn: CGRect(x: center.x - size, y: center.y - size, width: size * 2, height: size * 2)).fill()
        }

        let cable = stroke
        switch kind {
        case .gondola:
            // Трос, подвес, кабина с окном.
            line(0.14, 0.27, 0.86, 0.15, width: cable, color: ink)
            line(0.5, 0.21, 0.5, 0.40, width: cable, color: ink)
            block(0.27, 0.38, 0.46, 0.44, radius: 0.11, color: ink)
            block(0.335, 0.46, 0.33, 0.13, radius: 0.03, color: paper)
        case .chair:
            // Трос, подвес, широкое кресло с местами.
            line(0.14, 0.27, 0.86, 0.15, width: cable, color: ink)
            line(0.5, 0.21, 0.5, 0.46, width: cable, color: ink)
            block(0.15, 0.44, 0.70, 0.30, radius: 0.09, color: ink)
            dot(0.31, 0.59, radius: 0.062, color: paper)
            dot(0.5, 0.59, radius: 0.062, color: paper)
            dot(0.69, 0.59, radius: 0.062, color: paper)
        case .platter:
            // Трос, штанга, тарелка.
            line(0.14, 0.27, 0.86, 0.15, width: cable, color: ink)
            line(0.5, 0.21, 0.5, 0.66, width: cable, color: ink)
            block(0.33, 0.64, 0.34, 0.13, radius: 0.065, color: ink)
        case .tbar:
            // Трос, штанга, широкая перекладина на двоих.
            line(0.14, 0.27, 0.86, 0.15, width: cable, color: ink)
            line(0.5, 0.21, 0.5, 0.72, width: cable, color: ink)
            line(0.24, 0.72, 0.76, 0.72, width: cable * 1.25, color: ink)
        case .carpet:
            // Наклонная лента и человек на ней.
            line(0.17, 0.76, 0.83, 0.50, width: 0.15, color: ink)
            line(0.20, 0.748, 0.80, 0.512, width: 0.035, color: paper)
            dot(0.52, 0.30, radius: 0.085, color: ink)
            line(0.52, 0.40, 0.52, 0.50, width: cable * 1.2, color: ink)
        }
    }
}
