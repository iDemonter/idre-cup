import SwiftUI

/// Аватар участника: его картинка или первая буква имени. Свой выделен акцентом.
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
                Text(String(person.name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.44, weight: .heavy, design: .rounded))
                    .foregroundStyle(isMe ? Theme.onAccent : Theme.textPrimary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(isMe ? Theme.accent : Theme.raised)
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
    }

    @EnvironmentObject private var session: Session
    @State private var mode: Mode
    @State private var day: DayReply?
    @State private var standings: StandingsReply?
    @State private var crowns: CrownsReply?
    @State private var showsProfile: Bool

    init() {
        // Для снимков экрана: -ratingTab week -showProfile YES.
        let defaults = UserDefaults.standard
        let asked = defaults.string(forKey: "ratingTab")
        _mode = State(initialValue: asked == "week" ? .week : (asked == "crowns" ? .crowns : .day))
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
                        points: "+\(row.points)",
                        footnote: row.runs > 0 ? dayFootnote(row) : nil
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
                        detail: row.days.isEmpty ? "пока без очков" : row.days.map { String($0) }.joined(separator: " + "),
                        points: String(row.points),
                        footnote: nil
                    )
                }
            }
        } else {
            ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding(.top, 40)
        }
    }

    private func dayFootnote(_ row: DayRow) -> String {
        var parts = ["скорость \(place(row.speedPlace))", "объём \(place(row.volumePlace))"]
        if let count = row.crowns, count > 0 {
            parts.append("\(count) \(Format.plural(count, "корона", "короны", "корон"))")
        }
        if let wins = row.raceWins, wins > 0 {
            parts.append("\(wins) \(Format.plural(wins, "гонка", "гонки", "гонок"))")
        }
        return parts.joined(separator: " · ")
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
                Text(free.map { "\($0.number) \($0.name)" }.joined(separator: " · "))
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
            Text(String(row.number))
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
                        .lineLimit(1)
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
