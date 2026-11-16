import SwiftUI
import UIKit

/// Значок участника без фото: свой цвет и свой символ, чтобы на карте было видно, кто где, без имён.
/// Номер берётся по порядку участника в кубке, поэтому у первых 12 значки не повторяются.
struct PersonIcon: Equatable {
    let symbol: String
    let color: UIColor
    /// На светлом фоне символ тёмный.
    let ink: UIColor

    private static let symbols = [
        "hare.fill", "tortoise.fill", "bird.fill", "fish.fill", "pawprint.fill", "ladybug.fill",
        "ant.fill", "leaf.fill", "snowflake", "flame.fill", "bolt.fill", "star.fill",
    ]
    private static let colors: [(UInt32, Bool)] = [
        (0xF03E64, false), (0x4F8BFF, false), (0x2FC27A, false), (0xFF8A3D, false),
        (0x9B6BFF, false), (0xFFC94D, true), (0x2EC4B6, false), (0xFF6FB5, false),
        (0xB07D4F, false), (0x6B7AA1, false), (0xE04BE0, false), (0x7BD3FF, true),
    ]

    static func of(index: Int) -> PersonIcon {
        let slot = max(index, 0)
        let (hex, light) = colors[slot % colors.count]
        let color = UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
        // Цвета и символы сдвинуты относительно друг друга, чтобы после 12-го пары не повторялись.
        let symbol = symbols[(slot + slot / colors.count) % symbols.count]
        return PersonIcon(symbol: symbol, color: color, ink: light ? UIColor(white: 0.1, alpha: 1) : .white)
    }

    /// Картинка значка для 3D-модели.
    func image(side: CGFloat) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: side * 0.46, weight: .bold)
        return UIImage(systemName: symbol, withConfiguration: configuration)?.withTintColor(ink, renderingMode: .alwaysOriginal)
    }
}

extension Session {
    /// Значок участника по его месту в списке кубка.
    func icon(for id: String) -> PersonIcon {
        PersonIcon.of(index: people.firstIndex { $0.id == id } ?? abs(id.hashValue) % 12)
    }
}
