import SwiftUI

/// Итоги дня карточками на весь экран, как истории (предложение 6, Figma StoryCard 35:329).
/// Нажатие справа — следующая, слева — назад. Последняя — «Лучший день» с конфетти и вибрацией «успех».
struct CeremonyStories: View {
    let ceremony: Ceremony
    let people: [Person]
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    struct Slide {
        let title: String
        let name: String?
        let value: String
        let detail: String?
        var final = false
    }

    private var slides: [Slide] {
        var list: [Slide] = []
        if let best = ceremony.fastest {
            list.append(Slide(title: "Быстрее всех", name: best.name, value: "\(Format.kmh(best.value)) км/ч", detail: "лучшая скорость на спусках, держал 3 секунды"))
        }
        if let best = ceremony.vertical {
            list.append(Slide(title: "Больше метров", name: best.name, value: "\(Format.meters(best.value)) м", detail: "перепад на спусках за день"))
        }
        if let best = ceremony.runs {
            let count = Int(best.value)
            list.append(Slide(title: "Больше спусков", name: best.name, value: "\(count)", detail: Format.plural(count, "спуск", "спуска", "спусков") + " за день"))
        }
        if !ceremony.crowns.isEmpty {
            let stolen = ceremony.crowns.filter { $0.from != nil }
            let lines = ceremony.crowns.prefix(4).map { crown in
                "\(Format.trail(crown.number)) \(crown.name): \(crown.holder)" + (crown.from.map { " отобрал у \($0)" } ?? "")
            }
            list.append(Slide(title: "Короны дня", name: nil, value: "\(ceremony.crowns.count)", detail: (stolen.isEmpty ? "" : "отобрано: \(stolen.count)\n") + lines.joined(separator: "\n")))
        }
        if !ceremony.duels.isEmpty {
            let lines = ceremony.duels.prefix(4).map { duel in
                "\(duel.challenger) — \(duel.opponent): " + (duel.winner.map { "\($0) +\(duel.stake)" } ?? "ничья")
            }
            list.append(Slide(title: "Дуэли", name: nil, value: "\(ceremony.duels.count)", detail: lines.joined(separator: "\n")))
        }
        if let pair = ceremony.pairs?.first {
            list.append(Slide(title: "Лучшая пара", name: nil, value: pair.names.joined(separator: " + "), detail: "\(pair.score) очков на двоих"))
        }
        if let top = ceremony.rows.first, top.runs > 0 {
            let leader = ceremony.standings.first.map { "в общем зачёте ведёт \($0.name), \($0.points) очков" }
            list.append(Slide(title: "Лучший день", name: top.name, value: "+\(top.points)", detail: leader, final: true))
        }
        return list
    }

    var body: some View {
        let all = slides
        let slide = all.isEmpty ? nil : all[min(index, all.count - 1)]
        ZStack {
            Palette.base.ignoresSafeArea()
            if slide?.final == true {
                RadialGradient(colors: [Palette.accent.opacity(0.35), .clear], center: .center, startRadius: 10, endRadius: 380)
                    .ignoresSafeArea()
                ConfettiView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            VStack(spacing: Spacing.l) {
                progress(count: all.count)
                Spacer()
                if let slide {
                    card(slide, number: index + 1, of: all.count)
                        .id(index)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
                Spacer()
                Label(index + 1 < all.count ? "нажми — дальше" : "нажми — закрыть", systemImage: "hand.tap")
                    .font(Typo.caption1)
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.vertical, Spacing.m)
            // Левая треть — назад, остальное — дальше.
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle())
                    .frame(maxWidth: .infinity)
                    .onTapGesture { step(-1, count: all.count) }
                Color.clear.contentShape(Rectangle())
                    .frame(maxWidth: .infinity)
                    .onTapGesture { step(1, count: all.count) }
                Color.clear.contentShape(Rectangle())
                    .frame(maxWidth: .infinity)
                    .onTapGesture { step(1, count: all.count) }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .padding(.top, Spacing.l)
            .padding(.trailing, Spacing.s)
            .accessibilityLabel("Закрыть итоги")
        }
        .sensoryFeedback(trigger: slide?.final == true) { _, final in
            final ? .success : nil
        }
        .preferredColorScheme(.dark)
    }

    private func step(_ delta: Int, count: Int) {
        let next = index + delta
        if next >= count {
            dismiss()
        } else {
            withAnimation(.snappy) { index = max(0, next) }
        }
    }

    private func progress(count: Int) -> some View {
        HStack(spacing: Spacing.xs) {
            ForEach(0..<max(count, 1), id: \.self) { item in
                Capsule()
                    .fill(item <= index ? Palette.textPrimary : Palette.textPrimary.opacity(0.25))
                    .frame(height: 3)
            }
        }
        .padding(.top, Spacing.s)
        .padding(.trailing, 44)
    }

    private func card(_ slide: Slide, number: Int, of count: Int) -> some View {
        VStack(spacing: Spacing.m) {
            Text("ИТОГИ ДНЯ\(ceremony.dayNumber.map { " \($0)" } ?? "") · \(number) ИЗ \(count)")
                .font(Typo.overline)
                .foregroundStyle(Palette.textSecondary)
            Text(slide.title)
                .font(Typo.largeTitle)
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)
            if let name = slide.name {
                AvatarView(person: person(named: name), size: 120)
                    .padding(.top, Spacing.s)
                Text(name)
                    .font(Typo.title2)
                    .foregroundStyle(Palette.textPrimary)
            }
            Text(slide.value)
                .font(.system(size: 54, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(Palette.accentText)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .lineLimit(2)
            if let detail = slide.detail, !detail.isEmpty {
                Text(detail)
                    .font(Typo.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func person(named name: String) -> Person {
        people.first { $0.name == name } ?? Person(id: name, name: name, isAdmin: false, avatar: nil)
    }
}

/// Конфетти: падающие разноцветные кусочки (Canvas + TimelineView, без внешних библиотек).
struct ConfettiView: View {
    private struct Piece {
        let x: Double
        let speed: Double
        let sway: Double
        let size: Double
        let spin: Double
        let color: Color
        let delay: Double
    }

    private static let colors: [Color] = [Palette.accent, Palette.warning, Palette.error, Palette.success, Palette.pisteBlue, Color(red: 0.62, green: 0.45, blue: 1)]
    private let pieces: [Piece] = (0..<70).map { item in
        var generator = SeededRandom(seed: UInt64(item + 1) * 2_654_435_761)
        return Piece(
            x: generator.next(),
            speed: 0.12 + generator.next() * 0.18,
            sway: generator.next() * 2 * .pi,
            size: 5 + generator.next() * 7,
            spin: 1 + generator.next() * 3,
            color: colors[item % colors.count],
            delay: generator.next() * 2.5
        )
    }
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { canvas, size in
                let time = context.date.timeIntervalSince(start)
                for piece in pieces {
                    let run = time - piece.delay
                    guard run > 0 else { continue }
                    // Падают сверху вниз и начинают заново; через 6 секунд затихают.
                    let fall = (run * piece.speed).truncatingRemainder(dividingBy: 1.2) - 0.1
                    let opacity = max(0, min(1, 7 - time))
                    guard opacity > 0 else { continue }
                    let x = piece.x * size.width + sin(run * 2 + piece.sway) * 14
                    let y = fall * size.height
                    var shape = canvas
                    shape.opacity = opacity
                    shape.translateBy(x: x, y: y)
                    shape.rotate(by: .radians(run * piece.spin))
                    shape.fill(Path(CGRect(x: -piece.size / 2, y: -piece.size / 4, width: piece.size, height: piece.size / 2)), with: .color(piece.color))
                }
            }
        }
        .onAppear { start = Date() }
    }
}

/// Простой воспроизводимый генератор (одинаковое конфетти при каждом показе).
private struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }
}
