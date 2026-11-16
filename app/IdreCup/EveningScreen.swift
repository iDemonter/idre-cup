import SwiftUI

/// «Вечер»: итоги дня (церемония) и игра «Реакция». Очки игры идут в сегодняшний день.
struct EveningScreen: View {
    let data: PisteData
    let terrain: TerrainData?
    @EnvironmentObject private var session: Session
    /// Повтор дня на модели. Для снимков экрана: -replay YES.
    @State private var showsReplay = UserDefaults.standard.bool(forKey: "replay")
    @State private var ceremony: Ceremony?
    @State private var games: GamesReply?
    @State private var didLoad = false
    @State private var playing: ReactionGame?
    @State private var failure: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if session.phase != .signedIn {
                    note("Вечер идёт внутри кубка. Войдите в кубок в разделе «Рейтинг».")
                } else {
                    if terrain != nil {
                        replayButton
                    }
                    gameCard
                    if let ceremony {
                        ceremonyCards(ceremony)
                    } else if didLoad {
                        note("Итоги дня не загрузились: нет связи или сервер ещё не обновлён.")
                    } else {
                        ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding(.top, 30)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.base.ignoresSafeArea())
        .refreshable { await load() }
        .task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .fullScreenCover(isPresented: $showsReplay) {
            if let terrain {
                ReplayView(data: data, terrain: terrain)
                    .environmentObject(session)
            }
        }
        .fullScreenCover(item: $playing) { game in
            ReactionView(game: game) { times in
                Task {
                    if !(await session.sendReaction(game, times: times)) {
                        failure = session.problem
                        session.problem = nil
                    }
                    playing = nil
                    await load()
                }
            } onCancel: {
                playing = nil
            }
        }
    }

    private func load() async {
        guard session.phase == .signedIn else { return }
        async let freshCeremony = session.ceremony()
        async let freshGames = session.games()
        if let value = await freshCeremony { ceremony = value }
        if let value = await freshGames { games = value }
        didLoad = true
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(overline)
                .font(Theme.overline())
                .foregroundStyle(Theme.textSecondary)
            Text("Вечер")
                .font(Theme.title(32))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var overline: String {
        if let number = ceremony?.dayNumber { return "ИТОГИ ДНЯ \(number)" }
        return "ИТОГИ ДНЯ И ИГРЫ"
    }

    private var replayButton: some View {
        Button {
            showsReplay = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 24, weight: .bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Повтор дня на карте")
                        .font(Theme.headline(17))
                    Text("Все треки за день одновременно, час за минуту")
                        .font(Theme.caption())
                        .opacity(0.8)
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
            .foregroundStyle(Theme.onAccent)
            .padding(16)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - «Реакция»

    @ViewBuilder
    private var gameCard: some View {
        let open = games?.games.first { $0.status == "open" }
        let last = games?.games.first { $0.status == "finished" && $0.day == ceremony?.date }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ИГРА «РЕАКЦИЯ»")
                    .font(Theme.overline())
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if open != nil {
                    Text("ИДЁТ")
                        .font(Theme.overline(10))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.accent, in: Capsule())
                }
            }
            Text("Три раунда: экран красный, ждёшь зелёного и жмёшь как можно быстрее. Нажал раньше — фальстарт, секунда штрафа. Время меряет твой телефон. Места дают 6, 4, 2 и 1 очко в сегодняшний день.")
                .font(Theme.caption())
                .foregroundStyle(Theme.textSecondary)
            if let failure {
                Text(failure)
                    .font(Theme.caption())
                    .foregroundStyle(Theme.pisteRed)
            }
            if let open {
                if open.mine == nil {
                    actionButton("Играть", symbol: "hand.tap.fill") { playing = open }
                } else {
                    Text("Ты сыграл: \(ms(open.mine?.score)). Ждём остальных: сыграли \(open.played.joined(separator: ", ")).")
                        .font(Theme.caption())
                        .foregroundStyle(Theme.accent)
                }
                results(open.results)
            } else {
                if let last {
                    results(last.results)
                }
                if session.isAdmin {
                    actionButton(last == nil ? "Начать игру для всех" : "Ещё одна игра", symbol: "play.fill") {
                        Task {
                            if !(await session.startGame()) {
                                failure = session.problem
                                session.problem = nil
                            }
                            await load()
                        }
                    }
                } else if last == nil {
                    Text("Игру начинает админ кубка.")
                        .font(Theme.caption())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func results(_ rows: [ReactionGame.Result]) -> some View {
        if !rows.isEmpty {
            VStack(spacing: 6) {
                ForEach(rows) { row in
                    HStack {
                        Text("\(row.place). \(row.name)")
                            .font(Theme.headline(15))
                            .foregroundStyle(row.id == session.me?.id ? Theme.accent : Theme.textPrimary)
                        Spacer()
                        Text(ms(row.score))
                            .font(Theme.caption())
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                        Text("+\(row.points)")
                            .font(Theme.headline(15))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func ms(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded())) мс"
    }

    // MARK: - Церемония

    @ViewBuilder
    private func ceremonyCards(_ day: Ceremony) -> some View {
        if day.rows.allSatisfy({ $0.runs == 0 }) {
            note("Сегодня ещё никто не катался: итоги появятся после первых спусков.")
        } else {
            awards(day)
            if !day.crowns.isEmpty {
                section("КОРОНЫ ДНЯ") {
                    ForEach(day.crowns) { crown in
                        line(
                            "crown.fill",
                            "\(crown.number) \(crown.name)",
                            crown.from.map { "\(crown.holder) отобрал у \($0) · \(Format.lap(crown.seconds))" } ?? "\(crown.holder) · \(Format.lap(crown.seconds))"
                        )
                    }
                }
            }
            if !day.duels.isEmpty {
                section("ДУЭЛИ") {
                    ForEach(Array(day.duels.enumerated()), id: \.offset) { _, duel in
                        line(
                            "flag.checkered.2.crossed",
                            "\(duel.challenger) — \(duel.opponent)",
                            duel.winner.map { "\($0) +\(duel.stake)" } ?? "ничья"
                        )
                    }
                }
            }
            if !day.events.isEmpty {
                section("СОБЫТИЯ") {
                    ForEach(Array(day.events.enumerated()), id: \.offset) { _, event in
                        line("bolt.fill", eventTitle(event.kind), eventOutcome(event))
                    }
                }
            }
            if let pairs = day.pairs, let best = pairs.first {
                section("ПАРНЫЙ ДЕНЬ") {
                    line("person.2.fill", best.names.joined(separator: " + "), "лучшая пара · \(best.score) очков")
                }
            }
            section("ОБЩИЙ ЗАЧЁТ ПОСЛЕ ДНЯ") {
                ForEach(Array(day.standings.enumerated()), id: \.offset) { _, row in
                    line(row.place == 1 ? "trophy.fill" : "medal.fill", "\(row.place). \(row.name)", "\(row.points) очков")
                }
                if let leader = day.jerseys["leader"] ?? nil {
                    line("tshirt.fill", "Майка лидера", leader)
                }
            }
        }
    }

    private func awards(_ day: Ceremony) -> some View {
        let top = day.rows.first
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                tile("ЛУЧШИЙ ДЕНЬ", top?.name, top.map { "+\($0.points)" })
                tile("БЫСТРЕЕ ВСЕХ", day.fastest?.name, day.fastest.map { "\(Format.kmh($0.value)) км/ч" })
            }
            HStack(spacing: 8) {
                tile("БОЛЬШЕ МЕТРОВ", day.vertical?.name, day.vertical.map { "\(Format.meters($0.value)) м" })
                tile("БОЛЬШЕ СПУСКОВ", day.runs?.name, day.runs.map { "\(Int($0.value))" })
            }
        }
    }

    private func tile(_ title: String, _ name: String?, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.overline(10))
                .foregroundStyle(Theme.textSecondary)
            Text(name ?? "—")
                .font(Theme.headline(17))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text(value ?? " ")
                .font(Theme.title(20))
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.overline())
                .foregroundStyle(Theme.textSecondary)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func line(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 20)
            Text(title)
                .font(Theme.headline(15))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(detail)
                .font(Theme.caption())
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func eventTitle(_ kind: String) -> String {
        switch kind {
        case "double": return "Двойной счёт"
        case "best": return "Побей себя"
        case "explore": return "Новая трасса"
        default: return "Охота на лидера"
        }
    }

    private func eventOutcome(_ event: Ceremony.EventResult) -> String {
        if event.kind == "double" { return "объём дважды" }
        if event.awards.isEmpty { return "никто" }
        return "+\(event.awards[0].points): " + event.awards.map(\.name).joined(separator: ", ")
    }

    private func actionButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(Theme.headline())
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Theme.caption())
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Сама игра: раунд за раундом на весь экран. Время меряется по часам телефона.
private struct ReactionView: View {
    enum Phase {
        case ready
        case waiting
        case go
        case shown(Double?)
    }

    let game: ReactionGame
    let onFinish: ([Double?]) -> Void
    let onCancel: () -> Void

    @State private var round = 0
    @State private var phase = Phase.ready
    @State private var times: [Double?] = []
    @State private var greenAt: Date?
    @State private var timer: Task<Void, Never>?

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("РАУНД \(min(round + 1, game.delays.count)) ИЗ \(game.delays.count)")
                    .font(Theme.overline(13))
                    .foregroundStyle(.white.opacity(0.8))
                Text(title)
                    .font(Theme.title(40))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(Theme.headline(17))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            .padding(30)
        }
        .contentShape(Rectangle())
        .onTapGesture { tap() }
        .overlay(alignment: .topTrailing) {
            if case .ready = phase, round == 0 {
                Button("Отмена", action: onCancel)
                    .font(Theme.headline(15))
                    .foregroundStyle(.white)
                    .padding(20)
            }
        }
        .onDisappear { timer?.cancel() }
    }

    private var background: Color {
        switch phase {
        case .waiting: return Theme.pisteRed
        case .go: return Theme.pisteGreen
        default: return Theme.base
        }
    }

    private var title: String {
        switch phase {
        case .ready: return "Готов?"
        case .waiting: return "Жди зелёного…"
        case .go: return "ЖМИ!"
        case let .shown(time): return time.map { "\(Int($0.rounded())) мс" } ?? "Фальстарт"
        }
    }

    private var subtitle: String {
        switch phase {
        case .ready: return "Нажми в любом месте экрана, чтобы начать раунд."
        case .waiting: return "Не нажимай, пока экран красный."
        case .go: return ""
        case .shown(nil): return "Штраф \(Int(game.falseStartMs)) мс. Нажми, чтобы продолжить."
        case .shown: return round + 1 < game.delays.count ? "Нажми, чтобы продолжить." : "Нажми, чтобы отправить результат."
        }
    }

    private func tap() {
        switch phase {
        case .ready:
            phase = .waiting
            let delay = game.delays[round] / 1000
            timer = Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, case .waiting = phase else { return }
                greenAt = Date()
                phase = .go
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
        case .waiting:
            timer?.cancel()
            record(nil)
        case .go:
            let time = greenAt.map { Date().timeIntervalSince($0) * 1000 }
            record(time.map { min(max($0, 50), 5_000) })
        case .shown:
            if times.count >= game.delays.count {
                onFinish(times)
            } else {
                round += 1
                phase = .ready
            }
        }
    }

    private func record(_ time: Double?) {
        times.append(time)
        phase = .shown(time)
        UINotificationFeedbackGenerator().notificationOccurred(time == nil ? .error : .success)
    }
}
