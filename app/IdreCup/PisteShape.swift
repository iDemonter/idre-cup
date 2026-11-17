import SwiftUI

/// Форма значка трассы (предложение 11, Figma «PisteBadge (формы)»): сложность читается и формой, не только цветом.
/// Зелёная — круг, синяя — квадрат, красная — шестиугольник, чёрная — ромб, без данных — круг пунктиром.
enum PisteForm {
    case circle, square, hexagon, diamond, unknown

    init(difficulty: String?) {
        switch difficulty {
        case "green": self = .circle
        case "blue": self = .square
        case "red": self = .hexagon
        case "black": self = .diamond
        default: self = .unknown
        }
    }

    /// Доля стороны под цифры: в ромбе места меньше.
    var fontScale: CGFloat { self == .diamond ? 0.36 : (self == .hexagon ? 0.42 : 0.46) }
}

struct PisteShape: Shape {
    let form: PisteForm

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let box = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        switch form {
        case .circle, .unknown:
            return Path(ellipseIn: box)
        case .square:
            return Path(roundedRect: box.insetBy(dx: side * 0.04, dy: side * 0.04), cornerRadius: side * 0.2, style: .continuous)
        case .hexagon:
            var path = Path()
            let radius = side / 2
            for index in 0..<6 {
                let angle = Double(index) * .pi / 3 - .pi / 2
                let point = CGPoint(x: box.midX + radius * cos(angle), y: box.midY + radius * sin(angle))
                index == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            path.closeSubpath()
            return path
        case .diamond:
            var path = Path()
            path.move(to: CGPoint(x: box.midX, y: box.minY))
            path.addLine(to: CGPoint(x: box.maxX, y: box.midY))
            path.addLine(to: CGPoint(x: box.midX, y: box.maxY))
            path.addLine(to: CGPoint(x: box.minX, y: box.midY))
            path.closeSubpath()
            return path
        }
    }
}

/// Значок трассы с номером: форма по сложности, цвет трассы, белая обводка (у чёрной ярче, у «без данных» пунктир).
struct ShapedPisteBadge: View {
    let text: String
    let difficulty: String?
    let color: Color
    var size: CGFloat = 26
    var isSelected = false

    var body: some View {
        let form = PisteForm(difficulty: difficulty)
        let outline = isSelected ? Palette.accent : Color.white.opacity(form == .diamond ? 0.95 : 0.6)
        Text(text)
            .font(.system(size: size * form.fontScale, weight: .heavy, design: .rounded))
            .foregroundStyle(form == .unknown ? Palette.textPrimary : Color.white)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .padding(.horizontal, size * 0.12)
            .frame(width: size, height: size)
            .background(form == .unknown ? Palette.surface : color, in: PisteShape(form: form))
            .overlay(
                PisteShape(form: form)
                    .stroke(outline, style: StrokeStyle(lineWidth: isSelected ? 3 : 1.5, dash: form == .unknown ? [3, 2] : []))
            )
            .accessibilityLabel("Трасса \(text)")
    }
}

extension PisteForm {
    /// Тот же контур для картинок значков на 3D-модели.
    func bezier(in rect: CGRect) -> UIBezierPath {
        UIBezierPath(cgPath: PisteShape(form: self).path(in: rect).cgPath)
    }
}
