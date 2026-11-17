import SwiftUI

/// Вид дуэли. Названия совпадают с сервером (server/API.md, раздел «Дуэли»).
enum DuelKind: String, CaseIterable, Identifiable {
    case race
    case speed
    case endurance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .race: return "Гонка"
        case .speed: return "Скорость"
        case .endurance: return "Выносливость"
        }
    }

    var hint: String {
        switch self {
        case .race: return "Кто быстрее пройдёт выбранную трассу сверху донизу. Ехать вместе не обязательно: считается лучшее время каждого."
        case .speed: return "У кого выше максимальная скорость на спусках (держать 3 секунды)."
        case .endurance: return "Кто наберёт больше метров перепада на спусках."
        }
    }

    /// Сколько может длиться, минуты. Сервер присылает свой список; это запасной.
    var spans: [Int] {
        self == .speed ? [30, 60] : [60, 120]
    }
}

extension Duel {
    var isRunning: Bool { status == "active" || status == "counting" }
    var isPending: Bool { status == "pending" }
    var isOver: Bool { !isRunning && !isPending }

    func involves(_ id: String?) -> Bool {
        challenger.id == id || opponent.id == id
    }

    var title: String {
        switch kind {
        case "race": return trail.map { "Гонка · \(Format.trail($0.number)) \($0.name)" } ?? "Гонка"
        case "speed": return "Скорость"
        default: return "Выносливость"
        }
    }

    var rule: String {
        switch kind {
        case "race": return "Лучшее время на трассе за \(Duel.span(minutes))"
        case "speed": return "Максимальная скорость за \(Duel.span(minutes))"
        default: return "Больше метров спуска за \(Duel.span(minutes))"
        }
    }

    /// Результат словами: время, скорость или метры. Без результата прочерк.
    func text(_ value: Double?) -> String {
        guard let value else { return "—" }
        switch kind {
        case "race": return Format.lap(value)
        case "speed": return "\(Format.kmh(value)) км/ч"
        default: return "\(Format.meters(value)) м"
        }
    }

    /// Кто впереди сейчас или победил. nil при равенстве и когда результатов нет.
    var leader: String? {
        if let winner { return winner }
        guard isRunning || status == "finished" else { return nil }
        guard let mine = challenger.value else {
            return opponent.value == nil ? nil : opponent.id
        }
        guard let theirs = opponent.value else { return challenger.id }
        if mine == theirs { return nil }
        let challengerAhead = kind == "race" ? mine < theirs : mine > theirs
        return challengerAhead ? challenger.id : opponent.id
    }

    /// «30 минут», «1 час», «2 часа».
    static func span(_ minutes: Int) -> String {
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return "\(hours) \(Format.plural(hours, "час", "часа", "часов"))"
        }
        return "\(minutes) \(Format.plural(minutes, "минуту", "минуты", "минут"))"
    }
}

/// «Дуэли»: вызовы один на один. Итог считает сервер по трекам обоих за время дуэли.
struct DuelsScreen: View {
    @EnvironmentObject private var session: Session
    @State private var reply: DuelsReply?
    @State private var didLoad = false
    /// Насколько часы сервера впереди часов телефона, секунды: по нему идёт отсчёт.
    @State private var clockOffset: Double = 0
    @State private var showsNew: Bool
    @State private var failure: String?

    init() {
        // Для снимков экрана: -newDuel YES.
        _showsNew = State(initialValue: UserDefaults.standard.bool(forKey: "newDuel"))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.base.ignoresSafeArea())
        .refreshable {
            await load()
        }
        .task {
            // Пока экран открыт, дуэли обновляются сами.
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .sheet(isPresented: $showsNew, onDismiss: reload) {
            NewDuelSheet(options: reply)
                .environmentObject(session)
                .preferredColorScheme(.dark)
        }
    }

    private func reload() {
        Task { await load() }
    }

    private func load() async {
        guard session.phase == .signedIn else { return }
        let fresh = await session.duels()
        if let fresh {
            reply = fresh
            clockOffset = fresh.now - Date().timeIntervalSince1970
        }
        didLoad = true
    }

    private func act(_ duel: Duel, _ action: String) async {
        let done = await session.answer(duel, action)
        failure = done ? nil : session.problem
        session.problem = nil
        await load()
    }

    // MARK: - Шапка и состояния

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("ОДИН НА ОДИН · СТАВКА \(reply?.stake ?? 5) ОЧКОВ")
                .font(Theme.overline())
                .foregroundStyle(Theme.textSecondary)
            Text("Дуэли")
                .font(Theme.title(32))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if session.phase != .signedIn {
            note("Дуэли идут внутри кубка. Войдите в кубок или создайте свой в разделе «Рейтинг».")
        } else if let reply {
            board(reply)
        } else if didLoad {
            note("Не удалось загрузить дуэли: нет связи или сервер ещё не обновлён. Потяните экран вниз, чтобы попробовать снова.")
        } else {
            SkeletonList(rows: 3)
        }
    }

    @ViewBuilder
    private func board(_ reply: DuelsReply) -> some View {
        let myID = session.me?.id
        let incoming = reply.duels.filter { $0.isPending && $0.opponent.id == myID }
        let outgoing = reply.duels.filter { $0.isPending && $0.challenger.id == myID }
        let running = reply.duels.filter { $0.isRunning }
        let others = reply.duels.filter { $0.isPending && !$0.involves(myID) }
        let past = reply.duels.filter { $0.isOver }
        let isBusy = reply.duels.contains { !$0.isOver && $0.involves(myID) }

        if let failure {
            warning(failure)
        }
        ForEach(incoming) { duel in
            incomingCard(duel)
        }
        ForEach(running) { duel in
            runningCard(duel)
        }
        ForEach(outgoing) { duel in
            outgoingCard(duel)
        }
        if reply.duels.isEmpty, reply.left > 0 {
            EmptyState(
                symbol: "flag.2.crossed.fill",
                title: "Дуэлей пока нет",
                text: "Брось вызов другу: гонка по трассе, скорость или выносливость. Победитель забирает \(reply.stake) очков.",
                button: "Вызвать на дуэль"
            ) { showsNew = true }
        } else {
            challengeButton(isBusy: isBusy, left: reply.left)
        }
        if !others.isEmpty {
            sectionTitle("ЖДУТ ОТВЕТА")
            ForEach(others) { duel in
                pastRow(duel)
            }
        }
        if !past.isEmpty {
            sectionTitle("ИСТОРИЯ")
            ForEach(past) { duel in
                pastRow(duel)
            }
        }
        Text("Победитель забирает \(reply.stake) очков у проигравшего. Отказаться может любой, это ничего не стоит. В день не больше трёх дуэлей и не больше одной с тем же соперником.")
            .font(Theme.caption(11))
            .foregroundStyle(Theme.textSecondary.opacity(0.8))
            .padding(.top, 4)
    }

    // MARK: - Карточки

    private func incomingCard(_ duel: Duel) -> some View {
        card(highlight: true) {
            tag("ВЫЗОВ ТЕБЕ")
            HStack(spacing: 12) {
                AvatarView(person: person(duel.challenger), size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(duel.challenger.name) вызывает тебя")
                        .font(Theme.headline(17))
                        .foregroundStyle(Theme.textPrimary)
                    Text(duel.title)
                        .font(Theme.caption())
                        .foregroundStyle(Theme.accent)
                }
            }
            Text("\(duel.rule). Время пойдёт, как только примешь. Проигравший отдаёт \(duel.stake) очков.\(deadline(duel))")
                .font(Theme.caption())
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 10) {
                Button {
                    Task { await act(duel, "accept") }
                } label: {
                    actionLabel("Принять", filled: true)
                }
                .buttonStyle(.plain)
                Button {
                    Task { await act(duel, "decline") }
                } label: {
                    actionLabel("Отказаться", filled: false)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func outgoingCard(_ duel: Duel) -> some View {
        card(highlight: true) {
            tag("ТВОЙ ВЫЗОВ")
            HStack(spacing: 12) {
                AvatarView(person: person(duel.opponent), size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ждём ответа: \(duel.opponent.name)")
                        .font(Theme.headline(17))
                        .foregroundStyle(Theme.textPrimary)
                    Text(duel.title)
                        .font(Theme.caption())
                        .foregroundStyle(Theme.accent)
                }
            }
            Text("\(duel.rule).\(deadline(duel))")
                .font(Theme.caption())
                .foregroundStyle(Theme.textSecondary)
            Button {
                Task { await act(duel, "cancel") }
            } label: {
                actionLabel("Отозвать вызов", filled: false)
            }
            .buttonStyle(.plain)
        }
    }

    private func runningCard(_ duel: Duel) -> some View {
        card(highlight: duel.involves(session.me?.id)) {
            HStack {
                tag(duel.status == "counting" ? "СЧИТАЕМ ИТОГ" : "ИДЁТ")
                Spacer()
                if duel.status == "active", let end = duel.endsAt {
                    countdown(to: end)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(duel.title)
                    .font(Theme.headline(17))
                    .foregroundStyle(Theme.textPrimary)
                Text(duel.rule)
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textSecondary)
            }
            versus(duel)
            if duel.status == "counting" {
                Text("Время вышло. Ждём остаток треков с телефонов, обычно это пара минут.")
                    .font(Theme.caption(11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func versus(_ duel: Duel) -> some View {
        HStack(alignment: .top, spacing: 8) {
            side(duel, duel.challenger)
            Text("VS")
                .font(Theme.overline())
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 16)
            side(duel, duel.opponent)
        }
    }

    private func side(_ duel: Duel, _ who: Duel.Side) -> some View {
        let isAhead = duel.leader == who.id
        return VStack(spacing: 4) {
            AvatarView(person: person(who), size: 46)
            Text(who.name)
                .font(Theme.caption())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text(duel.text(who.value))
                .font(Theme.headline(18))
                .foregroundStyle(isAhead ? Theme.accent : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func countdown(to end: Double) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text("осталось \(Format.duration(max(end - context.date.timeIntervalSince1970 - clockOffset, 0)))")
                .font(Theme.caption())
                .monospacedDigit()
                .foregroundStyle(Theme.accent)
        }
    }

    private func pastRow(_ duel: Duel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(duel.challenger.name) — \(duel.opponent.name)")
                    .font(Theme.headline(15))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(outcome(duel))
                    .font(Theme.caption())
                    .foregroundStyle(duel.winner == nil ? Theme.textSecondary : Theme.accent)
                    .lineLimit(1)
            }
            Text(pastDetail(duel))
                .font(Theme.caption())
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func outcome(_ duel: Duel) -> String {
        switch duel.status {
        case "finished":
            guard let winner = duel.winner else { return "ничья" }
            let name = winner == duel.challenger.id ? duel.challenger.name : duel.opponent.name
            return "\(name) +\(duel.stake)"
        case "declined": return "отказ"
        case "cancelled": return "вызов отозван"
        case "expired": return "без ответа"
        default: return "ждёт ответа"
        }
    }

    private func pastDetail(_ duel: Duel) -> String {
        var parts = [duel.title]
        if duel.status == "finished" {
            parts.append("\(duel.text(duel.challenger.value)) : \(duel.text(duel.opponent.value))")
        } else {
            parts.append(Duel.span(duel.minutes))
        }
        parts.append(Format.clock(Date(timeIntervalSince1970: (duel.startsAt ?? duel.createdAt) - clockOffset)))
        return parts.joined(separator: " · ")
    }

    private func challengeButton(isBusy: Bool, left: Int) -> some View {
        let isOpen = !isBusy && left > 0
        return VStack(spacing: 6) {
            Button {
                failure = nil
                showsNew = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "flag.checkered.2.crossed")
                    Text("Вызвать на дуэль")
                }
                .font(Theme.headline())
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!isOpen)
            .opacity(isOpen ? 1 : 0.4)
            Text(buttonHint(isBusy: isBusy, left: left))
                .font(Theme.caption(11))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func buttonHint(isBusy: Bool, left: Int) -> String {
        if isBusy { return "Новый вызов можно бросить, когда закончится текущая дуэль" }
        if left <= 0 { return "На сегодня дуэли закончились" }
        return "Сегодня осталось: \(left) \(Format.plural(left, "дуэль", "дуэли", "дуэлей"))"
    }

    // MARK: - Мелочи

    private func person(_ who: Duel.Side) -> Person {
        session.people.first { $0.id == who.id } ?? Person(id: who.id, name: who.name, isAdmin: false, avatar: nil)
    }

    /// « Ответить до 14:35.» для вызова, который ещё ждёт ответа.
    private func deadline(_ duel: Duel) -> String {
        guard let answerBy = duel.answerBy else { return "" }
        return " Ответить до \(Format.clock(Date(timeIntervalSince1970: answerBy - clockOffset)))."
    }

    private func card<Content: View>(highlight: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.accent.opacity(highlight ? 0.7 : 0), lineWidth: 1.5)
        )
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(Theme.overline(10))
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.accent, in: Capsule())
    }

    private func actionLabel(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(Theme.headline(15))
            .foregroundStyle(filled ? Theme.onAccent : Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(filled ? Theme.accent : Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(Theme.overline())
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, 6)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Theme.caption())
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func warning(_ text: String) -> some View {
        Text(text)
            .font(Theme.caption())
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.pisteRed.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Новый вызов: соперник, вид дуэли, трасса для гонки и время.
private struct NewDuelSheet: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    let options: DuelsReply?

    @State private var opponent: Person?
    @State private var kind = DuelKind.race
    @State private var trail = 0
    @State private var minutes = 60
    @State private var trails: [CrownRow] = []
    @State private var failure: String?
    @State private var isSending = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Новая дуэль")
                    .font(Theme.title(28))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 8)
                group("СОПЕРНИК") {
                    opponents
                }
                group("ВИД") {
                    Picker("", selection: $kind) {
                        ForEach(DuelKind.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(kind.hint)
                        .font(Theme.caption())
                        .foregroundStyle(Theme.textSecondary)
                }
                if kind == .race {
                    group("ТРАССА") {
                        trailPicker
                    }
                }
                group("ВРЕМЯ") {
                    Picker("", selection: $minutes) {
                        ForEach(spans(kind), id: \.self) { value in
                            Text(Duel.span(value)).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Время пойдёт, когда соперник примет вызов. На ответ у него \(options?.answerMinutes ?? 30) минут.")
                        .font(Theme.caption())
                        .foregroundStyle(Theme.textSecondary)
                }
                if let failure {
                    Text(failure)
                        .font(Theme.caption())
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.pisteRed.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                sendButton
                Text("Победитель забирает \(options?.stake ?? 5) очков у проигравшего. Отказ ничего не стоит.")
                    .font(Theme.caption(11))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
            }
            .padding(20)
        }
        .background(Theme.base.ignoresSafeArea())
        .task {
            minutes = spans(kind).first ?? 60
            // Список трасс приходит с сервера; при плохой связи пробуем снова, пока лист открыт.
            while trails.isEmpty && !Task.isCancelled {
                if let reply = await session.crowns() {
                    trails = reply.trails
                    if trail == 0 {
                        trail = reply.trails.first?.number ?? 0
                    }
                } else {
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
        .onChange(of: kind) { _, fresh in
            minutes = spans(fresh).first ?? 60
        }
    }

    private func spans(_ kind: DuelKind) -> [Int] {
        options?.minutes[kind.rawValue] ?? kind.spans
    }

    private var canSend: Bool {
        opponent != nil && !isSending && (kind != .race || trail > 0)
    }

    private func send() async {
        guard let opponent else { return }
        isSending = true
        let done = await session.challenge(opponent, kind: kind.rawValue, trail: kind == .race ? trail : nil, minutes: minutes)
        isSending = false
        if done {
            dismiss()
        } else {
            failure = session.problem ?? "Не получилось отправить вызов"
            session.problem = nil
        }
    }

    @ViewBuilder
    private var opponents: some View {
        let others = session.people.filter { $0.id != session.me?.id }
        if others.isEmpty {
            Text("В кубке пока никого, кроме тебя. Позови друзей кодом из профиля.")
                .font(Theme.caption())
                .foregroundStyle(Theme.textSecondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(others) { person in
                        opponentButton(person)
                    }
                }
            }
        }
    }

    private func opponentButton(_ person: Person) -> some View {
        let isPicked = person.id == opponent?.id
        return Button {
            opponent = person
        } label: {
            VStack(spacing: 6) {
                AvatarView(person: person, size: 52)
                Text(person.name)
                    .font(Theme.caption())
                    .foregroundStyle(isPicked ? Theme.accent : Theme.textPrimary)
                    .lineLimit(1)
            }
            .frame(width: 78)
            .padding(.vertical, 10)
            .background(isPicked ? Theme.accent.opacity(0.18) : Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.accent.opacity(isPicked ? 1 : 0), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var trailPicker: some View {
        if trails.isEmpty {
            Text("Список трасс загружается…")
                .font(Theme.caption())
                .foregroundStyle(Theme.textSecondary)
        } else {
            Picker("Трасса", selection: $trail) {
                ForEach(trails) { row in
                    Text("\(Format.trail(row.number)) · \(row.name)").tag(row.number)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var sendButton: some View {
        Button {
            Task { await send() }
        } label: {
            Text(opponent.map { "Вызвать: \($0.name)" } ?? "Выбери соперника")
                .font(Theme.headline())
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .opacity(canSend ? 1 : 0.4)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.overline())
                .foregroundStyle(Theme.textSecondary)
            content()
        }
    }
}
