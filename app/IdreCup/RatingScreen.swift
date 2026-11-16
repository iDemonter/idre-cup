import SwiftUI

/// Аватар участника: его картинка или значок (свой цвет и символ). Свой выделен акцентом.
struct AvatarView: View {
    @EnvironmentObject private var session: Session
    let person: Person
    var size: CGFloat = 40

    @State private var image: UIImage?

    var body: some View {
        let isMe = person.id == session.me?.id
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                // Без фото: свой цвет и символ участника, как на карте.
                let icon = session.icon(for: person.id)
                Image(systemName: icon.symbol)
                    .font(.system(size: size * 0.44, weight: .bold))
                    .foregroundStyle(Color(icon.ink))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(icon.color))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(isMe ? Theme.accent : Theme.border, lineWidth: size > 60 ? 3 : 2))
        .task(id: "\(person.id)-\(person.avatar ?? 0)") {
            image = await session.avatarImage(for: person)
        }
    }
}

/// «Рейтинг»: вход в кубок, рейтинг дня и общий зачёт. Макет: Figma, экран 01.
struct RatingScreen: View {
    enum Mode: String, CaseIterable {
        case day = "Сегодня"
        case week = "Неделя"
        case crowns = "Короны"
        case season = "Сезон"
    }

    @EnvironmentObject private var session: Session
    @State private var mode: Mode
    @State private var day: DayReply?
    @State private var standings: StandingsReply?
    @State private var crowns: CrownsReply?
    @State private var season: SeasonReply?
    @State private var events: EventsReply?
    /// Насколько часы сервера впереди часов телефона на момент загрузки событий, секунды.
    @State private var eventsOffset: Double = 0
    @State private var showsProfile: Bool

    init() {
        // Для снимков экрана: -ratingTab week -showProfile YES.
        let defaults = UserDefaults.standard
        let asked = defaults.string(forKey: "ratingTab")
        _mode = State(initialValue: Mode.allCases.first { "\($0)" == asked } ?? .day)
        _showsProfile = State(initialValue: defaults.bool(forKey: "showProfile"))
    }

    var body: some View {
        Group {
            switch session.phase {
            case .loading:
                ProgressView()
                    .tint(Theme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .noServer:
                noServer
            case .signedOut:
                JoinView()
            case .signedIn:
                board
            }
        }
        .background(Theme.base.ignoresSafeArea())
    }

    private var noServer: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
            Text("Нет связи с сервером игры")
                .font(Theme.headline())
                .foregroundStyle(Theme.textPrimary)
            Text("Карта и запись трека работают и так. Рейтинг появится, когда будет интернет.")
                .font(Theme.caption())
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await session.retry() }
            } label: {
                Text("Попробовать ещё раз")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Рейтинг

    private var board: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                switch mode {
                case .day: dayList
                case .week: weekList
                case .crowns: crownList
                case .season: seasonList
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable {
            await load()
        }
        .task {
            // Пока экран открыт, рейтинг обновляется сам.
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(20))
            }
        }
        .sheet(isPresented: $showsProfile) {
            ProfileScreen()
                .environmentObject(session)
                .preferredColorScheme(.dark)
        }
    }

    private func load() async {
        await session.refresh()
        async let freshDay = session.day()
        async let freshStandings = session.standings()
        if let reply = await freshDay { day = reply }
        if let reply = await freshStandings { standings = reply }
        if let reply = await session.crowns() { crowns = reply }
        if let reply = await session.season() { season = reply }
        if let reply = await session.events() {
            events = reply
            eventsOffset = reply.now - Date().timeIntervalSince1970
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(overline.uppercased())
                    .font(Theme.overline())
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Text("Рейтинг")
                    .font(Theme.title(32))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            if let me = session.me {
                Button {
                    showsProfile = true
                } label: {
                    AvatarView(person: me, size: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var overline: String {
        var parts = [session.cup?.name ?? "Кубок"]
        if let number = day?.dayNumber {
            parts.append("день \(number)")
        }
        return parts.joined(separator: " · ")
    }

    private func person(_ id: String, _ name: String) -> Person {
        session.people.first { $0.id == id } ?? Person(id: id, name: name, isAdmin: false, avatar: nil)
    }

    @ViewBuilder
    private var dayList: some View {
        if let day {
            if day.multiplier > 1 {
                note("Последний день кубка: очки ×\(day.multiplier)")
            }
            if let pairs = day.pairs, !pairs.isEmpty {
                note(pairNote(pairs))
            }
            if let events, !events.events.isEmpty {
                EventsCard(reply: events, clockOffset: eventsOffset, myID: session.me?.id)
            }
            if day.rows.allSatisfy({ $0.runs == 0 }) {
                note("Сегодня ещё никто не катался. Включите запись в «Моём дне» и сделайте первый спуск.")
            }
            VStack(spacing: 8) {
                ForEach(Array(day.rows.enumerated()), id: \.element.id) { index, row in
                    rowCard(
                        place: row.points > 0 ? index + 1 : nil,
                        person: person(row.id, row.name),
                        detail: row.runs > 0
                            ? "\(Format.kmh(row.topSpeed)) км/ч · \(Format.meters(row.vertical)) м · \(row.runs) \(Format.plural(row.runs, "спуск", "спуска", "спусков"))"
                            : "ещё не катался",
                        points: signed(row.points),
                        footnote: dayFootnote(row)
                    )
                }
            }
        } else {
            ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding(.top, 40)
        }
    }

    @ViewBuilder
    private var weekList: some View {
        if let standings {
            if standings.dates.isEmpty {
                note("Зачёт начнётся с первого дня с треками.")
            }
            VStack(spacing: 8) {
                ForEach(standings.rows) { row in
                    rowCard(
                        place: row.place,
                        person: person(row.id, row.name),
                        detail: row.days.isEmpty ? "пока без очков" : daySum(row.days, joker: row.joker),
                        points: String(row.points),
                        footnote: weekFootnote(row, standings.jerseys)
                    )
                }
            }
        } else {
            ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding(.top, 40)
        }
    }

    /// «10 + 🃏8 + 19»: очки по дням, день под джокером отмечен картой.
    private func daySum(_ days: [Int], joker: Int? = nil) -> String {
        var text = ""
        for (index, value) in days.enumerated() {
            let mark = index == joker ? "🃏" : ""
            if index == 0 {
                text = mark + (value < 0 ? "−\(-value)" : String(value))
            } else {
                text += value < 0 ? " − \(mark)\(-value)" : " + \(mark)\(value)"
            }
        }
        return text
    }

    /// «Парный день: ты с Олегом. Пары: Иван + Олег 31 · Анна (одна, ×2) 24». Лучшие пары получают бонус каждому.
    private func pairNote(_ pairs: [DayPair]) -> String {
        let mine = pairs.first { $0.ids.contains(session.me?.id ?? "") }
        var text = "Парный день"
        if let mine {
            let partner = zip(mine.ids, mine.names).first { $0.0 != session.me?.id }?.1
            text += partner.map { ". Твоя пара: \($0)." } ?? ". Ты без пары: твои очки считаются за двоих."
        } else {
            text += "."
        }
        let list = pairs.map { pair in
            "\(pair.place). \(pair.names.joined(separator: " + ")) · \(pair.score)" + (pair.bonus > 0 ? " (+\(pair.bonus))" : "")
        }
        return text + " Очки пары = сумма очков дня обоих, лучшие пары получают бонус каждому.\n" + list.joined(separator: "\n")
    }

    /// Майки и джокер под строкой недели.
    private func weekFootnote(_ row: StandingRow, _ jerseys: Jerseys?) -> String? {
        var parts: [String] = []
        if jerseys?.leader == row.id { parts.append("🟡 майка лидера") }
        if jerseys?.crowns == row.id { parts.append("👑 майка корон") }
        if jerseys?.volume == row.id { parts.append("⛰ майка объёма") }
        if row.joker != nil { parts.append("🃏 джокер сыгран") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// «+19», «−5»: в день можно уйти в минус, проиграв дуэль.
    private func signed(_ points: Int) -> String {
        points < 0 ? "−\(-points)" : "+\(points)"
    }

    private func dayFootnote(_ row: DayRow) -> String? {
        var parts: [String] = []
        if row.runs > 0 {
            parts = ["скорость \(place(row.speedPlace))", "объём \(place(row.volumePlace))"]
        }
        if let count = row.crowns, count > 0 {
            parts.append("👑 \(count)")
        }
        if let wins = row.raceWins, wins > 0 {
            parts.append("🏁 \(wins)")
        }
        if let duels = row.duelPoints, duels != 0 {
            parts.append("дуэли \(signed(duels))")
        }
        if let events = row.eventPoints, events != 0 {
            parts.append("события \(signed(events))")
        }
        if let pair = row.pairPoints {
            parts.append(row.partner.map { "пара: \($0) \(signed(pair))" } ?? "без пары \(signed(pair))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Короны: у каждой зачётной трассы король с лучшим временем недели. Рядом своё лучшее время.
    @ViewBuilder
    private var crownList: some View {
        if let crowns {
            let taken = crowns.trails.filter { $0.holder != nil }
            let free = crowns.trails.filter { $0.holder == nil }
            note("Корона у того, кто быстрее всех прошёл трассу сверху донизу. Каждая корона на конец дня даёт +2 очка, отобрать её можно в любой момент.")
            VStack(spacing: 8) {
                ForEach(taken) { row in
                    crownCard(row)
                }
            }
            if !free.isEmpty {
                Text("СВОБОДНЫЕ КОРОНЫ · \(free.count)")
                    .font(Theme.overline())
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 6)
                Text(free.map { "\(Format.trail($0.number)) \($0.name)" }.joined(separator: " · "))
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textSecondary)
            }
        } else {
            ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding(.top, 40)
        }
    }

    private func crownCard(_ row: CrownRow) -> some View {
        let holder = row.holder
        let isMine = holder?.id == session.me?.id
        return HStack(spacing: 12) {
            Text(Format.trail(row.number))
                .font(Theme.headline(15))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 34, height: 34)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(Theme.headline(16))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(row.mine.map { "моё время \(Format.lap($0))" } ?? "я здесь ещё не был")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            if let holder {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 5) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(holder.name ?? "?")
                            .font(Theme.caption())
                            .lineLimit(1)
                    }
                    .foregroundStyle(Theme.accent)
                    Text(Format.lap(holder.seconds))
                        .font(Theme.headline(17))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.accent.opacity(isMine ? 0.7 : 0), lineWidth: 1.5)
        )
    }

    // MARK: - Сезон

    /// Сезон: каждый катается где хочет, очки копятся с начала до конца сезона.
    @ViewBuilder
    private var seasonList: some View {
        if let season {
            let rules = season.rules
            note("Сезон \(Format.date(season.from)) – \(Format.date(season.to)): Idre, Åre, Vemdalen, горки Стокгольма. День на склоне +\(rules.dayPoints), +1 за каждые \(rules.verticalPer) м перепада (до \(rules.verticalMax)), катались вместе на одном курорте +\(rules.meetPoints), корона сезона +\(rules.crownPoints).")
            VStack(spacing: 8) {
                ForEach(season.rows) { row in
                    rowCard(
                        place: row.days > 0 ? row.place : nil,
                        person: person(row.id, row.name),
                        detail: row.days > 0
                            ? "\(row.days) \(Format.plural(row.days, "день", "дня", "дней")) · \(Format.meters(row.vertical)) м · \(Format.kmh(row.topSpeed)) км/ч"
                            : "ещё не катался в этом сезоне",
                        points: String(row.points),
                        footnote: seasonFootnote(row)
                    )
                }
            }
            if let mine = season.rows.first(where: { $0.id == session.me?.id }), !mine.history.isEmpty {
                sectionTitle("МОИ ДНИ")
                VStack(spacing: 6) {
                    ForEach(mine.history) { day in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(Format.date(day.date)) · \(day.resorts.joined(separator: ", "))")
                                    .font(Theme.headline(14))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Text("\(Format.meters(day.vertical)) м · \(day.runs) \(Format.plural(day.runs, "спуск", "спуска", "спусков")) · \(Format.kmh(day.topSpeed)) км/ч\(day.met ? " · вместе 🤝" : "")")
                                    .font(Theme.caption())
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Text("+\(day.points)")
                                .font(Theme.headline(16))
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            if !season.crowns.isEmpty {
                sectionTitle("КОРОНЫ СЕЗОНА · \(season.crowns.count)")
                VStack(spacing: 6) {
                    ForEach(season.crowns) { crown in
                        let isMine = crown.holder.id == session.me?.id
                        HStack(spacing: 10) {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(isMine ? Theme.accent : Theme.textSecondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text([crown.label, crown.name].compactMap { $0 }.joined(separator: " "))
                                    .font(Theme.headline(14))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Text("\(crown.resort) · \(crown.holder.name ?? "?") \(Format.lap(crown.holder.seconds))\(crown.mine.map { isMine ? "" : " · моё \(Format.lap($0))" } ?? "")")
                                    .font(Theme.caption())
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        } else {
            ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding(.top, 40)
        }
    }

    private func seasonFootnote(_ row: SeasonReply.Row) -> String? {
        var parts: [String] = []
        if !row.resorts.isEmpty { parts.append(row.resorts.joined(separator: ", ")) }
        if row.meets > 0 { parts.append("🤝 \(row.meets)") }
        if row.crowns > 0 { parts.append("👑 \(row.crowns)") }
        if row.bestDay > 0 { parts.append("лучший день \(Format.meters(row.bestDay)) м") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(Theme.overline())
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, 6)
    }

    private func place(_ value: Int?) -> String {
        value.map { "\($0)-е" } ?? "нет"
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Theme.caption())
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func rowCard(place: Int?, person: Person, detail: String, points: String, footnote: String?) -> some View {
        let isMe = person.id == session.me?.id
        return HStack(spacing: 12) {
            Text(place.map { String($0) } ?? "–")
                .font(Theme.headline(18))
                .foregroundStyle(place == 1 ? Theme.accent : Theme.textSecondary)
                .frame(width: 22)
            AvatarView(person: person, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                    .font(Theme.headline(16))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(detail)
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let footnote {
                    Text(footnote)
                        .font(Theme.caption(10))
                        .foregroundStyle(Theme.textSecondary.opacity(0.75))
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 8)
            Text(points)
                .font(Theme.title(22))
                .foregroundStyle(Theme.accent)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.accent.opacity(isMe ? 0.7 : 0), lineWidth: 1.5)
        )
    }
}

/// Первый экран для того, кто ещё не в кубке: войти по коду или создать свой.
private struct JoinView: View {
    enum Way: String, CaseIterable {
        case join = "Войти по коду"
        case create = "Создать кубок"
    }

    @EnvironmentObject private var session: Session
    @State private var way: Way = .join
    @State private var name = ""
    @State private var code = ""
    @State private var cupName = "Idre Cup 2027"
    @State private var anywhere = false

    /// Восемь знаков = код возврата от админа: имя вводить не нужно.
    private var isRestore: Bool {
        code.trimmingCharacters(in: .whitespaces).count == 8
    }

    private var isReady: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespaces).isEmpty
        if way == .join, isRestore { return true }
        return hasName && (way == .join ? code.count >= 6 : !cupName.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("IDRE FJÄLL · ЯНВАРЬ 2027")
                        .font(Theme.overline())
                        .foregroundStyle(Theme.textSecondary)
                    Text("Idre Cup")
                        .font(Theme.title(32))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Неделя на склоне, шесть зачётных дней. Проигравшие кормят победителя ужином.")
                        .font(Theme.caption(13))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 4)
                }

                Picker("", selection: $way) {
                    ForEach(Way.allCases, id: \.self) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                field("Как вас зовут", text: $name)
                    .textContentType(.givenName)

                if way == .join {
                    field("Код кубка, 6 знаков", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(size: 20, weight: .heavy, design: .monospaced))
                    Text("Код кубка: 6 знаков. Если вы уже были в кубке и сменили телефон, введите код возврата из 8 знаков, его выдаёт админ.")
                        .font(Theme.caption())
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    field("Название кубка", text: $cupName)
                    Toggle(isOn: $anywhere) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Пробный кубок")
                                .font(Theme.headline(15))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Считать спуски где угодно, а не только в Idre Fjäll. Для проверки дома.")
                                .font(Theme.caption())
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .tint(Theme.accent)
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                if let problem = session.problem {
                    Text(problem)
                        .font(Theme.caption())
                        .foregroundStyle(Theme.pisteRed)
                }

                Button {
                    Task {
                        let cleanName = name.trimmingCharacters(in: .whitespaces)
                        if way == .join, isRestore {
                            await session.restore(code: code.trimmingCharacters(in: .whitespaces))
                        } else if way == .join {
                            await session.join(name: cleanName, code: code.trimmingCharacters(in: .whitespaces))
                        } else {
                            await session.createCup(name: cleanName, cupName: cupName.trimmingCharacters(in: .whitespaces), anywhere: anywhere)
                        }
                    }
                } label: {
                    Text(way == .create ? "Создать кубок" : (isRestore ? "Вернуться в кубок" : "Войти в кубок"))
                        .font(Theme.headline())
                        .foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!isReady || session.isBusy)
                .opacity(isReady && !session.isBusy ? 1 : 0.4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(title).foregroundStyle(Theme.textSecondary.opacity(0.7)))
            .font(Theme.headline())
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
