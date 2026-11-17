// Сгенерировано design/generate-tokens.js из design/tokens.json. Руками не править:
// сначала меняется Figma (страница «Основа»), потом tokens.json, потом запускается скрипт.

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Цвета. Имена совпадают с переменными Figma (коллекция «Цвета», режимы Light и Dark).
/// Один акцент — `accent`; текстом и значками на фоне — `accentText`.
enum Palette {
    // MARK: Поверхности
    /// фон экрана
    static let base = Color(light: 0xF2F5FC, dark: 0x0B1026)
    /// поверхность: карточки, таб-бар
    static let surface = Color(light: 0xFFFFFF, dark: 0x161D3F)
    /// приподнятое: вторичные кнопки, бейджи, поля
    static let raised = Color(light: 0xE6EBF7, dark: 0x232C5C)
    /// разделитель и обводка
    static let border = Color(light: 0xD3DAEE, dark: 0x2E3870)
    /// затемнение под листом
    static let scrim = Color(light: 0x0B1026, dark: 0x05070F, lightAlpha: 0.4, darkAlpha: 0.6)

    // MARK: Текст
    /// текст 1
    static let textPrimary = Color(light: 0x0B1026, dark: 0xFFFFFF)
    /// текст 2: подписи
    static let textSecondary = Color(light: 0x4B5680, dark: 0xA9B4E0)
    /// текст 3: сноски, источники карт; не для мелкого важного текста
    static let textTertiary = Color(light: 0x7A84AA, dark: 0x7C87B6)

    // MARK: Акцент
    /// единственный акцент: заливки кнопок, активная вкладка, своя строка
    static let accent = Color(light: 0x22C3F2, dark: 0x4FD8FF)
    /// нажатое состояние
    static let accentPressed = Color(light: 0x0FA8D6, dark: 0x2FB9E0)
    /// акцент текстом и значками на surface/base (контраст ≥ 4.5:1)
    static let accentText = Color(light: 0x00769F, dark: 0x4FD8FF)
    /// подложка подсказок и выбранных чипов (в коде accent.opacity(0.18))
    static let accentSoft = Color(light: 0x00A3D6, dark: 0x4FD8FF, lightAlpha: 0.12, darkAlpha: 0.18)
    /// текст и значки на заливке accent
    static let onAccent = Color(light: 0x0B1026, dark: 0x0B1026)

    // MARK: Состояния
    /// успех, рост места ↑
    static let success = Color(light: 0x1C9E5F, dark: 0x2FC27A)
    /// ошибка, удаление, точка записи, падение места ↓
    static let error = Color(light: 0xD92B51, dark: 0xF03E64)
    /// предупреждение, «нет связи»
    static let warning = Color(light: 0xF5B400, dark: 0xFFC94D)
    /// текст на warning
    static let onWarning = Color(light: 0x1A1300, dark: 0x1A1300)
    /// подложка успеха (чипы, ↑)
    static let successSoft = Color(light: 0x1C9E5F, dark: 0x2FC27A, lightAlpha: 0.15, darkAlpha: 0.2)
    /// подложка ошибки (в коде сейчас pisteRed.opacity(0.35))
    static let errorSoft = Color(light: 0xD92B51, dark: 0xF03E64, lightAlpha: 0.15, darkAlpha: 0.35)
    /// подложка предупреждения
    static let warningSoft = Color(light: 0xF5B400, dark: 0xFFC94D, lightAlpha: 0.2, darkAlpha: 0.2)

    // MARK: Трассы
    /// очень лёгкая (круглый бейдж)
    static let pisteGreen = Color(light: 0x2FC27A, dark: 0x2FC27A)
    /// лёгкая
    static let pisteBlue = Color(light: 0x4F8BFF, dark: 0x4F8BFF)
    /// средняя
    static let pisteRed = Color(light: 0xF03E64, dark: 0xF03E64)
    /// сложная (белая обводка)
    static let pisteBlack = Color(light: 0x05070F, dark: 0x05070F)

    // MARK: Участники
    /// символ на значке
    static let personInk = Color(light: 0xFFFFFF, dark: 0xFFFFFF)
    /// символ на светлых значках 06 и 12
    static let personInkDark = Color(light: 0x1A1A1A, dark: 0x1A1A1A)

    // MARK: Стекло
    /// тонировка Liquid Glass (iOS 26+): .glassEffect(.regular.tint(glassTint)). На стекле только textPrimary и accentText: textSecondary над картой — 2,9–3,4:1
    static let glassTint = Color(light: 0xFFFFFF, dark: 0x161D3F, lightAlpha: 0.35, darkAlpha: 0.35)
    /// светлый край стекла
    static let glassStroke = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.7, darkAlpha: 0.14)
    /// запасной вид iOS 18: .ultraThinMaterial + эта подложка
    static let materialTint = Color(light: 0xFFFFFF, dark: 0x161D3F, lightAlpha: 0.72, darkAlpha: 0.75)

    // MARK: Значки участников
    /// 12 цветов значков участников по порядку в кубке (PersonIcon). Одинаковы в обеих темах.
    static let person: [Color] = [
        Color(light: 0xF03E64, dark: 0xF03E64), // person01 · hare.fill
        Color(light: 0x4F8BFF, dark: 0x4F8BFF), // person02 · tortoise.fill
        Color(light: 0x2FC27A, dark: 0x2FC27A), // person03 · bird.fill
        Color(light: 0xFF8A3D, dark: 0xFF8A3D), // person04 · fish.fill
        Color(light: 0x9B6BFF, dark: 0x9B6BFF), // person05 · pawprint.fill
        Color(light: 0xFFC94D, dark: 0xFFC94D), // person06 · ladybug.fill · тёмный символ
        Color(light: 0x2EC4B6, dark: 0x2EC4B6), // person07 · ant.fill
        Color(light: 0xFF6FB5, dark: 0xFF6FB5), // person08 · leaf.fill
        Color(light: 0xB07D4F, dark: 0xB07D4F), // person09 · snowflake
        Color(light: 0x6B7AA1, dark: 0x6B7AA1), // person10 · flame.fill
        Color(light: 0xE04BE0, dark: 0xE04BE0), // person11 · bolt.fill
        Color(light: 0x7BD3FF, dark: 0x7BD3FF), // person12 · star.fill · тёмный символ
    ]

    /// SF Symbol значка участника, по тому же индексу, что и `person`.
    static let personSymbols = ["hare.fill", "tortoise.fill", "bird.fill", "fish.fill", "pawprint.fill", "ladybug.fill", "ant.fill", "leaf.fill", "snowflake", "flame.fill", "bolt.fill", "star.fill"]
}

/// Отступы (коллекция «Размеры», группа «Отступы»).
enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    /// поля экрана слева и справа
    static let screen: CGFloat = 20
}

/// Радиусы скругления (коллекция «Размеры», группа «Радиусы»). Скругления в коде — `.continuous`.
enum Radius {
    /// номер трассы в списке, мелкие плашки
    static let badge: CGFloat = 10
    /// кнопки в карточках, подсказки, поля
    static let control: CGFloat = 14
    /// карточка: строка рейтинга, плитка, большая кнопка
    static let card: CGFloat = 18
    /// крупная карточка: скорость, объём, лист
    static let cardLarge: CGFloat = 24
    /// капсула: чипы, теги, таб-бар (в SwiftUI Capsule())
    static let capsule: CGFloat = 999
}

/// Шрифты: SF Pro Rounded по стилям Dynamic Type (растут с настройкой размера текста).
/// Имена совпадают с текстовыми стилями Figma «Текст/…» и «Цифры/…».
enum Typo {
    /// Large Title: 34/41 heavy
    static let largeTitle = Font.system(.largeTitle, design: .rounded).weight(.heavy)
    /// Title 1: 28/34 heavy
    static let title1 = Font.system(.title, design: .rounded).weight(.heavy)
    /// Title 2: 22/28 heavy
    static let title2 = Font.system(.title2, design: .rounded).weight(.heavy)
    /// Title 3: 20/25 bold
    static let title3 = Font.system(.title3, design: .rounded).weight(.bold)
    /// Headline: 17/22 bold
    static let headline = Font.system(.headline, design: .rounded).weight(.bold)
    /// Body: 17/22 medium
    static let body = Font.system(.body, design: .rounded).weight(.medium)
    /// Callout: 16/21 bold
    static let callout = Font.system(.callout, design: .rounded).weight(.bold)
    /// Subheadline: 15/20 bold
    static let subheadline = Font.system(.subheadline, design: .rounded).weight(.bold)
    /// Footnote: 13/18 semibold
    static let footnote = Font.system(.footnote, design: .rounded).weight(.semibold)
    /// Caption 1: 12/16 semibold
    static let caption1 = Font.system(.caption, design: .rounded).weight(.semibold)
    /// Caption 2: 11/13 semibold
    static let caption2 = Font.system(.caption2, design: .rounded).weight(.semibold)
    /// Overline: 11/13 bold. надстрочник: «IDRE CUP 2027 · ДЕНЬ 2»
    static let overline = Font.system(.caption2, design: .rounded).weight(.bold)
    /// Цифры/XL: 68/72 heavy. главная цифра: скорость в «Мой день»
    static let numberXL = Font.system(size: 68, weight: .heavy, design: .rounded).monospacedDigit()
    /// Цифры/L: 34/38 heavy. очки, перепад, подиум
    static let numberL = Font.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit()
    /// Цифры/M: 22/26 heavy. очки в строке рейтинга, Live Activity
    static let numberM = Font.system(size: 22, weight: .heavy, design: .rounded).monospacedDigit()
}

extension View {
    /// Надстрочник «IDRE CUP 2027 · ДЕНЬ 2»: Typo.overline, прописные, трекинг.
    func overlineStyle() -> some View {
        font(Typo.overline).textCase(.uppercase).tracking(0.66)
    }

    /// Стеклянная подложка: Liquid Glass на iOS 26+, материал ultraThin на iOS 18.
    /// На стекле — только Palette.textPrimary и Palette.accentText.
    @ViewBuilder
    func glassBackground<S: Shape>(in shape: S) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(Palette.glassTint), in: shape)
        } else {
            background(Palette.materialTint, in: shape).background(.ultraThinMaterial, in: shape)
        }
        #else
        background(Palette.materialTint, in: shape).background(.ultraThinMaterial, in: shape)
        #endif
    }
}

extension Color {
    /// Цвет для светлой и тёмной темы из шестнадцатеричных RGB.
    init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        #if canImport(UIKit) && !os(watchOS)
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(rgb: dark, alpha: darkAlpha)
                : UIColor(rgb: light, alpha: lightAlpha)
        })
        #else
        self.init(
            .sRGB,
            red: Double((dark >> 16) & 0xFF) / 255,
            green: Double((dark >> 8) & 0xFF) / 255,
            blue: Double(dark & 0xFF) / 255,
            opacity: darkAlpha
        )
        #endif
    }
}

#if canImport(UIKit) && !os(watchOS)
private extension UIColor {
    convenience init(rgb: UInt32, alpha: Double) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: CGFloat(alpha)
        )
    }
}
#endif
