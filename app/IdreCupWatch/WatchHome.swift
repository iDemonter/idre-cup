import SwiftUI

/// Главный экран часов: что с записью, цифры дня и кнопки «Старт», «Пауза», «Стоп».
struct WatchHome: View {
    @EnvironmentObject private var link: WatchLink
    @State private var asksStop = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                status
                Text("\(Format.kmh(link.state.speed)) км/ч")
                    .font(Typo.numberL)
                    .foregroundStyle(Palette.textPrimary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("\(Format.meters(link.state.vertical)) м · \(link.state.runs) \(Format.plural(link.state.runs, "спуск", "спуска", "спусков"))")
                    .font(Typo.footnote)
                    .foregroundStyle(Palette.textSecondary)
                if let points = link.state.points {
                    Text(rating(points))
                        .font(Typo.footnote)
                        .foregroundStyle(Palette.accentText)
                }
                countdown("bolt.fill", link.state.event, link.state.eventEnds)
                countdown("flag.checkered.2.crossed", link.state.duel, link.state.duelEnds)
                buttons
                    .padding(.top, 4)
                if let note = link.note {
                    Text(note)
                        .font(Typo.caption2)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog("Закончить запись на сегодня?", isPresented: $asksStop) {
            Button("Стоп", role: .destructive) { link.send("stop") }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var status: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(link.state.recording ? Palette.error : Palette.textSecondary)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(Typo.overline)
                .foregroundStyle(link.state.recording ? Palette.accentText : Palette.textSecondary)
            if link.isSending || link.isQueued {
                Spacer(minLength: 4)
                ProgressView()
                    .frame(width: 14, height: 14)
            }
        }
    }

    private var statusText: String {
        if link.state.recording { return "ЗАПИСЬ ИДЁТ" }
        if link.state.paused { return "ПАУЗА" }
        return "ЗАПИСЬ ВЫКЛЮЧЕНА"
    }

    @ViewBuilder
    private var buttons: some View {
        if link.state.recording {
            HStack(spacing: 6) {
                control("Пауза", "pause.fill", filled: false) { link.send("pause") }
                control("Стоп", "stop.fill", filled: false) { asksStop = true }
            }
        } else if link.state.paused {
            HStack(spacing: 6) {
                control("Дальше", "play.fill", filled: true) { link.send("start") }
                control("Стоп", "stop.fill", filled: false) { asksStop = true }
            }
        } else {
            control("Старт", "record.circle", filled: true) { link.send("start") }
        }
    }

    private func control(_ title: String, _ symbol: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .bold))
                Text(title)
                    .font(Typo.caption1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .tint(filled ? Palette.accent : Palette.raised)
        .foregroundStyle(filled ? Palette.onAccent : Palette.textPrimary)
        .buttonStyle(.borderedProminent)
        .disabled(link.isSending)
    }

    @ViewBuilder
    private func countdown(_ symbol: String, _ title: String?, _ end: Date?) -> some View {
        if let title, let end, end > Date() {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(end, style: .timer)
                    .monospacedDigit()
            }
            .font(Typo.caption2)
            .foregroundStyle(Palette.accentText)
        }
    }

    /// «2-е место · +19».
    private func rating(_ points: Int) -> String {
        let score = points < 0 ? "−\(-points)" : "+\(points)"
        return link.state.place.map { "\($0)-е место · \(score)" } ?? score
    }
}
