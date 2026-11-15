import SwiftUI

extension GameEvent {
    var isRunning: Bool { status == "active" || status == "counting" }

    var title: String {
        switch kind {
        case "double": return "Двойной счёт"
        case "best": return "Побей себя"
        case "explore": return "Новая трасса"
        default: return "Охота на лидера"
        }
    }

    /// Правило одной фразой. leaderName нужен только охоте.
    func rule(leaderName: String?) -> String {
        let prize = points.map { "+\($0)" } ?? ""
        switch kind {
        case "double":
            return "\(Duel.span(minutes).capitalizedFirst) всё, что проедешь, идёт в объём дня дважды."
        case "best":
            return "Покажи скорость выше своей лучшей за сегодня: \(prize). Нужен хотя бы один спуск до события."
        case "explore":
            return "Проедь зачётную трассу, на которой ещё не был в этом кубке: \(prize)."
        default:
            let leader = leaderName ?? "лидер"
            return "Лидер зачёта: \(leader). Обгони его по скорости за время события: \(prize). Не обгонит никто, очки получит лидер."
        }
    }

    /// Что участник показал за время события.
    func progress(_ entry: Entry) -> String {
        switch kind {
        case "double":
            return entry.value.map { "+\(Format.meters($0)) м в объём" } ?? "пока без спусков"
        case "explore":
            return entry.value.map { "трасса \(Int($0))" } ?? "пока нет"
        case "best":
            guard let goal = entry.goal else { return "нет спусков до события" }
            let shown = entry.value.map { "\(Format.kmh($0)) км/ч" } ?? "пока нет"
            return "\(shown) · надо больше \(Format.kmh(goal))"
        default:
            let shown = entry.value.map { "\(Format.kmh($0)) км/ч" } ?? "пока нет"
            return entry.leader == true ? "\(shown) · лидер" : shown
        }
    }

    /// Итог одной строкой: кто получил очки.
    var outcome: String {
        if kind == "double" { return "объём шёл дважды" }
        if awards.isEmpty { return "никто не выполнил" }
        let names = awards.map(\.name).joined(separator: ", ")
        return "+\(awards[0].points): \(names)"
    }
}

extension String {
    /// «30 минут» → «30 минут», «1 час» → «1 час»: первая буква заглавная, если это буква.
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}

/// События дня в «Рейтинге»: идущее с ходом каждого участника и уже законченные.
struct EventsCard: View {
    let reply: EventsReply
    /// Насколько часы сервера впереди часов телефона, секунды.
    let clockOffset: Double
    let myID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(reply.events.filter { $0.isRunning }) { event in
                running(event)
            }
            let past = reply.events.filter { !$0.isRunning }
            if !past.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(past) { event in
                        finished(event)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func running(_ event: GameEvent) -> some View {
        let leaderName = event.entries.first { $0.leader == true }?.name
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(event.status == "counting" ? "СОБЫТИЕ · СЧИТАЕМ ИТОГ" : "СОБЫТИЕ · ИДЁТ")
                    .font(Theme.overline(10))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.accent, in: Capsule())
                Spacer()
                if event.status == "active" {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("осталось \(Format.duration(max(event.endsAt - context.date.timeIntervalSince1970 - clockOffset, 0)))")
                            .font(Theme.caption())
                            .monospacedDigit()
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(Theme.headline(18))
                    .foregroundStyle(Theme.textPrimary)
                Text(event.rule(leaderName: leaderName))
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textSecondary)
            }
            VStack(spacing: 6) {
                ForEach(event.entries, id: \.id) { entry in
                    HStack(spacing: 8) {
                        Image(systemName: entry.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(entry.done ? Theme.accent : Theme.border)
                        Text(entry.name)
                            .font(Theme.caption(13))
                            .foregroundStyle(entry.id == myID ? Theme.accent : Theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(event.progress(entry))
                            .font(Theme.caption())
                            .foregroundStyle(entry.done ? Theme.accent : Theme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.accent.opacity(0.7), lineWidth: 1.5)
        )
    }

    private func finished(_ event: GameEvent) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.accent)
            Text("\(event.title) · \(Format.clock(Date(timeIntervalSince1970: event.startsAt - clockOffset)))")
                .font(Theme.caption())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(event.outcome)
                .font(Theme.caption())
                .foregroundStyle(event.awards.isEmpty ? Theme.textSecondary : Theme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
