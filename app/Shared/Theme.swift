import SwiftUI

/// Цвета и шрифты из макета Figma («Полярная ночь», один акцент).
enum Theme {
    static let base = Color(red: 0x0B / 255, green: 0x10 / 255, blue: 0x26 / 255)
    static let surface = Color(red: 0x16 / 255, green: 0x1D / 255, blue: 0x3F / 255)
    static let raised = Color(red: 0x23 / 255, green: 0x2C / 255, blue: 0x5C / 255)
    static let border = Color(red: 0x2E / 255, green: 0x38 / 255, blue: 0x70 / 255)
    static let textPrimary = Color.white
    static let textSecondary = Color(red: 0xA9 / 255, green: 0xB4 / 255, blue: 0xE0 / 255)
    static let onAccent = Color(red: 0x0B / 255, green: 0x10 / 255, blue: 0x26 / 255)
    static let accent = Color(red: 0x4F / 255, green: 0xD8 / 255, blue: 0xFF / 255)

    // Цвета сложности трасс, как на официальной карте курорта.
    static let pisteGreen = Color(red: 0x2F / 255, green: 0xC2 / 255, blue: 0x7A / 255)
    static let pisteBlue = Color(red: 0x4F / 255, green: 0x8B / 255, blue: 0xFF / 255)
    static let pisteRed = Color(red: 0xF0 / 255, green: 0x3E / 255, blue: 0x64 / 255)
    static let pisteBlack = Color(red: 0x05 / 255, green: 0x07 / 255, blue: 0x0F / 255)

    static func title(_ size: CGFloat = 24) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    static func headline(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func caption(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    static func overline(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}
