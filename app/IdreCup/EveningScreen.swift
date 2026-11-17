import SwiftUI

/// «Вечер»: итоги дня (церемония) и игра «Реакция». Очки игры идут в сегодняшний день.
struct EveningScreen: View {
    let data: PisteData
    let terrain: TerrainData?
    @EnvironmentObject private var session: Session
    /// Повтор дня на модели. Для снимков экрана: -replay YES.
    @State private var showsReplay = UserDefaults.standard.bool(forKey: "replay")
    @State private var ceremony: Ceremony?
    /// Итоги дня историями на весь экран. Для снимков экрана: -stories YES.
    @State private var showsStories = UserDefaults.standard.bool(forKey: "stories")
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
                    if let ceremony, ceremony.rows.contains(where: { $0.runs > 0 }) {
                        storiesButton
                    }
                    if terrain != nil {
                        replayButton
                    }
                    quizCard
                    gameCard
                    if let ceremony {
                        ceremonyCards(ceremony)
                    } else if didLoad {
                        note("Итоги дня не загрузились: нет связи или сервер ещё не обновлён.")
                    } else {
                        SkeletonList(rows: 2)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Palette.base.ignoresSafeArea())
        .refreshable { await load() }
        .task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(10))
            }
        }
        // Во время викторины состояние нужно каждую секунду.
        .task(id: games?.games.first { $0.kind == "quiz" && $0.status == "open" }?.id) {
            while !Task.isCancelled, games?.games.contains(where: { $0.kind == "quiz" && $0.status == "open" }) == true {
                try? await Task.sleep(for: .seconds(1))
                if let value = await session.games() { games = value }
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
                .font(Typo.overline)
                .foregroundStyle(Palette.textSecondary)
            Text("Вечер")
                .font(Typo.largeTitle)
                .foregroundStyle(Palette.textPrimary)
        }
    }

    private var overline: String {
        if let number = ceremony?.dayNumber { return "ИТОГИ ДНЯ \(number)" }
        return "ИТОГИ ДНЯ И ИГРЫ"
    }

    /// Предложение 6: итоги дня по одной награде на весь экран, финал с конфетти. Можно показать всем на ТВ через AirPlay.
    private var storiesButton: some View {
        Button {
            showsStories = true
        } label: {
            HStack(spacing: Spacing.m) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 24, weight: .bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Итоги дня")
                        .font(Typo.headline)
                    Text("По одной награде на экран, в конце лучший день")
                        .font(Typo.caption1)
                        .opacity(0.8)
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
            .foregroundStyle(Palette.onAccent)
            .padding(Spacing.l)
            .background(Palette.accent, in: RoundedRectangle(cornerRadius: Radius.card + 2, style: .continuous))
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showsStories) {
            if let ceremony {
                CeremonyStories(ceremony: ceremony, people: session.people)
            }
        }
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
                        .font(Typo.headline)
                    Text("Все треки за день одновременно, час за минуту")
                        .font(Typo.caption1)
                        .opacity(0.8)
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
            .foregroundStyle(Palette.onAccent)
            .padding(16)
            .background(Palette.accent, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }


    // MARK: - Викторина

    private static let optionColors: [Color] = [Palette.pisteRed, Palette.pisteBlue, Palette.warning, Palette.pisteGreen]
    private static let letters = ["A", "B", "C", "D"]

    @ViewBuilder
    private var quizCard: some View {
        let open = games?.games.first { $0.kind == "quiz" && $0.status == "open" }
        let last = games?.games.first { $0.kind == "quiz" && $0.status == "finished" && $0.day == ceremony?.date }
        let busy = games?.games.contains { $0.status == "open" } == true
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ВИКТОРИНА")
                    .font(Typo.overline)
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                if let state = open?.quiz, state.phase != "intro" {
                    Text("ВОПРОС \(min(state.index + 1, state.count)) ИЗ \(state.count)")
                        .font(Typo.overline)
                        .foregroundStyle(Palette.accentText)
                }
            }
            if let open, let state = open.quiz {
                quizLive(open, state)
            } else {
                Text("Вопросы на телевизоре, ответы на телефонах. 6 общих вопросов про Idre, горы и лыжи и до 4 про ваш сегодняшний день. На каждый 20 секунд: чем быстрее правильный ответ, тем больше очков. Места дают 6, 4, 2 и 1 очко в сегодняшний день.")
                    .font(Typo.caption1)
                    .foregroundStyle(Palette.textSecondary)
                if let last {
                    results(last.results, isQuiz: true)
                }
                if session.isAdmin {
                    actionButton("Начать викторину", symbol: "play.fill") {
                        Task {
                            if !(await session.startGame(kind: "quiz")) {
                                failure = session.problem
                                session.problem = nil
                            }
                            await load()
                        }
                    }
                    .disabled(busy)
                    .opacity(busy ? 0.4 : 1)
                }
            }
            if let path = games?.tv, let link = session.tvLink(path) {
                HStack(spacing: 8) {
                    Image(systemName: "tv")
                    Text("На телевизоре: \(link.host ?? "")\(link.path)")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    ShareLink(item: link) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .font(Typo.caption1)
                .foregroundStyle(Palette.accentText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    @ViewBuilder
    private func quizLive(_ game: ReactionGame, _ state: QuizState) -> some View {
        switch state.phase {
        case "intro":
            Text("Начинаем через \(state.left) с")
                .font(Typo.title1)
                .foregroundStyle(Palette.textPrimary)
            Text("Смотрите на телевизор, отвечайте здесь.")
                .font(Typo.caption1)
                .foregroundStyle(Palette.textSecondary)
        case "question", "reveal":
            if let question = state.question {
                HStack(alignment: .firstTextBaseline) {
                    Text(question.text)
                        .font(Typo.headline)
                        .foregroundStyle(Palette.textPrimary)
                    Spacer(minLength: 8)
                    if state.phase == "question" {
                        Text("\(state.left)")
                            .font(Typo.numberM)
                            .foregroundStyle(Palette.accentText)
                            .monospacedDigit()
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                        quizOption(game, state, index: index, text: option)
                    }
                }
                Text(quizNote(state))
                    .font(Typo.caption1)
                    .foregroundStyle(Palette.accentText)
            }
        default:
            Text("Считаем итоги…")
                .font(Typo.caption1)
                .foregroundStyle(Palette.textSecondary)
        }
        if !state.scores.isEmpty {
            VStack(spacing: 4) {
                ForEach(Array(state.scores.prefix(5).enumerated()), id: \.offset) { place, row in
                    HStack {
                        Text("\(place + 1). \(row.name)")
                            .foregroundStyle(row.id == session.me?.id ? Palette.accentText : Palette.textPrimary)
                        Spacer()
                        Text("\(row.score)")
                            .monospacedDigit()
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .font(Typo.footnote)
                }
            }
        }
    }

    private func quizOption(_ game: ReactionGame, _ state: QuizState, index: Int, text: String) -> some View {
        let isReveal = state.phase == "reveal"
        let picked = state.mine?.choice == index
        let faded = (isReveal && index != state.correct) || (state.mine != nil && !picked && !isReveal)
        return Button {
            guard state.phase == "question", state.mine == nil else { return }
            Task {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if !(await session.answerQuiz(game, question: state.index, choice: index)) {
                    failure = session.problem
                    session.problem = nil
                }
                if let value = await session.games() { games = value }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.letters[index])
                    .font(Typo.overline)
                    .opacity(0.8)
                Text(text)
                    .font(Typo.subheadline)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(index == 2 ? Color.black : Color.white)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
            .padding(12)
            .background(Self.optionColors[index], in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Color.white, lineWidth: picked ? 3 : 0)
            )
            .opacity(faded ? 0.3 : 1)
        }
        .buttonStyle(.plain)
    }

    private func quizNote(_ state: QuizState) -> String {
        if state.phase == "reveal" {
            guard let mine = state.mine else { return "Ты не ответил на этот вопрос." }
            return mine.points > 0 ? "Верно! +\(mine.points)" : "Мимо. Правильный ответ: \(Self.letters[state.correct ?? 0])"
        }
        if state.mine != nil { return "Ответ принят. Ждём остальных…" }
        return "Ответили: \(state.answered ?? 0)"
    }

    // MARK: - «Реакция»

    @ViewBuilder
    private var gameCard: some View {
        let open = games?.games.first { $0.kind != "quiz" && $0.status == "open" }
        let last = games?.games.first { $0.kind != "quiz" && $0.status == "finished" && $0.day == ceremony?.date }
        let quizRunning = games?.games.contains { $0.kind == "quiz" && $0.status == "open" } == true
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ИГРА «РЕАКЦИЯ»")
                    .font(Typo.overline)
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                if open != nil {
                    Text("ИДЁТ")
                        .font(Typo.overline)
                        .foregroundStyle(Palette.onAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Palette.accent, in: Capsule())
                }
            }
            Text("Три раунда: экран красный, ждёшь зелёного и жмёшь как можно быстрее. Нажал раньше — фальстарт, секунда штрафа. Время меряет твой телефон. Места дают 6, 4, 2 и 1 очко в сегодняшний день.")
                .font(Typo.caption1)
                .foregroundStyle(Palette.textSecondary)
            if let failure {
                Text(failure)
                    .font(Typo.caption1)
                    .foregroundStyle(Palette.error)
            }
            if let open {
                if open.mine == nil {
                    actionButton("Играть", symbol: "hand.tap.fill") { playing = open }
                } else {
                    Text("Ты сыграл: \(ms(open.mine?.score)). Ждём остальных: сыграли \(open.played.joined(separator: ", ")).")
                        .font(Typo.caption1)
                        .foregroundStyle(Palette.accentText)
                }
                results(open.results)
            } else {
                if let last {
                    results(last.results)
                }
                if session.isAdmin && !quizRunning {
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
                        .font(Typo.caption1)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    @ViewBuilder
    private func results(_ rows: [ReactionGame.Result], isQuiz: Bool = false) -> some View {
        if !rows.isEmpty {
            VStack(spacing: 6) {
                ForEach(rows) { row in
                    HStack {
                        Text("\(row.place). \(row.name)")
                            .font(Typo.subheadline)
                            .foregroundStyle(row.id == session.me?.id ? Palette.accentText : Palette.textPrimary)
                        Spacer()
                        Text(isQuiz ? "\(Int(row.score))" : ms(row.score))
                            .font(Typo.caption1)
                            .foregroundStyle(Palette.textSecondary)
                            .monospacedDigit()
                        Text("+\(row.points)")
                            .font(Typo.subheadline)
                            .foregroundStyle(Palette.accentText)
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
                            "\(Format.trail(crown.number)) \(crown.name)",
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
                .font(Typo.overline)
                .foregroundStyle(Palette.textSecondary)
            Text(name ?? "—")
                .font(Typo.headline)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Text(value ?? " ")
                .font(Typo.title3)
                .foregroundStyle(Palette.accentText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Typo.overline)
                .foregroundStyle(Palette.textSecondary)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func line(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.accentText)
                .frame(width: 20)
            Text(title)
                .font(Typo.subheadline)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(detail)
                .font(Typo.caption1)
                .foregroundStyle(Palette.textSecondary)
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
            .font(Typo.headline)
            .foregroundStyle(Palette.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Palette.accent, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Typo.caption1)
            .foregroundStyle(Palette.accentText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
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
                    .font(Typo.footnote)
                    .foregroundStyle(.white.opacity(0.8))
                Text(title)
                    .font(Typo.largeTitle)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(Typo.headline)
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
                    .font(Typo.subheadline)
                    .foregroundStyle(.white)
                    .padding(20)
            }
        }
        .onDisappear { timer?.cancel() }
    }

    private var background: Color {
        switch phase {
        case .waiting: return Palette.error
        case .go: return Palette.pisteGreen
        default: return Palette.base
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
