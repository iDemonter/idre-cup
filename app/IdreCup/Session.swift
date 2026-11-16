import Foundation
import UIKit

/// Связь с сервером: кто я, мой кубок, участники. Здесь же отправка треков и аватары.
@MainActor
final class Session: ObservableObject {
    enum Phase {
        case loading
        /// Адрес сервера неизвестен.
        case noServer
        case signedOut
        case signedIn
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var cup: CupInfo?
    @Published private(set) var me: Person?
    @Published private(set) var people: [Person] = []
    /// Где сейчас остальные участники (без меня).
    @Published private(set) var friends: [LivePosition] = []
    /// Текст последней ошибки для показа человеку.
    /// Сколько вызовов на дуэль ждут моего ответа.
    @Published private(set) var duelCalls = 0
    /// Моё место и очки за сегодня и идущая дуэль (соперник, конец по часам телефона): для Live Activity.
    private(set) var todayPlace: Int?
    private(set) var todayPoints: Int?
    private(set) var duelWith: String?
    private(set) var duelEnds: Date?
    /// Идущее событие дня: название и конец по часам телефона.
    private(set) var eventTitle: String?
    private(set) var eventEnds: Date?
    private let seenEventsKey = "announcedEvents"
    private var askedNotifications = false
    private let seenKey = "announcedDuels"
    @Published var problem: String?
    @Published private(set) var isBusy = false

    private var server: URL?
    private var token: String?
    /// Токен задан параметром запуска (снимки экрана): в связку ключей его не кладём.
    private var isTokenTemporary = false
    private var uploadedUntil: Double?
    private var isSyncing = false
    private var avatars = NSCache<NSString, UIImage>()

    private let defaults = UserDefaults.standard
    private let serverKey = "serverURL"
    private let cacheKey = "sessionCache"
    private static let configURL = URL(string: "https://raw.githubusercontent.com/iDemonter/idre-cup/main/config/app.json")!

    private var api: API? {
        server.map { API(base: $0, token: token) }
    }

    var isAdmin: Bool { me?.isAdmin ?? false }

    // MARK: - Запуск

    func start() async {
        // Адрес: сначала тот, что знали раньше (или из параметра запуска), затем свежий из настроек в репозитории.
        if let known = defaults.string(forKey: serverKey), let url = URL(string: known) {
            server = url
        }
        if defaults.volatileDomain(forName: UserDefaults.argumentDomain)[serverKey] == nil {
            await loadServerAddress()
        }
        guard server != nil else {
            phase = .noServer
            return
        }

        if let given = defaults.volatileDomain(forName: UserDefaults.argumentDomain)["token"] as? String {
            token = given
            isTokenTemporary = true
        } else {
            token = Keychain.readToken()
        }
        guard token != nil else {
            phase = .signedOut
            return
        }

        // Пока сервер отвечает, показываем то, что знали в прошлый раз.
        if !isTokenTemporary, let data = defaults.data(forKey: cacheKey), let cached = try? JSONDecoder().decode(MeReply.self, from: data) {
            apply(cached)
            phase = .signedIn
        }
        await refresh()
        if phase == .loading {
            phase = cup == nil ? .signedOut : .signedIn
        }
    }

    private struct AppConfig: Decodable {
        let server: String?
    }

    private func loadServerAddress() async {
        var request = URLRequest(url: Self.configURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        guard
            let (data, _) = try? await URLSession.shared.data(for: request),
            let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return }
        if let address = config.server, let url = URL(string: address) {
            server = url
            defaults.set(address, forKey: serverKey)
        }
    }

    func retry() async {
        phase = .loading
        await start()
    }

    // MARK: - Вход

    private func apply(_ reply: MeReply) {
        cup = reply.cup
        me = reply.me
        people = reply.participants
    }

    private func remember(_ reply: MeReply) {
        apply(reply)
        if !isTokenTemporary, let data = try? JSONEncoder().encode(reply) {
            defaults.set(data, forKey: cacheKey)
        }
    }

    /// Выполняет действие с сервером: показывает занятость и превращает ошибку в текст.
    @discardableResult
    private func attempt(_ work: (API) async throws -> Void) async -> Bool {
        guard let api else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            try await work(api)
            problem = nil
            return true
        } catch {
            problem = error.localizedDescription
            return false
        }
    }

    private func enter(_ entry: EntryReply) async {
        token = entry.token
        isTokenTemporary = false
        Keychain.saveToken(entry.token)
        uploadedUntil = nil
        remember(MeReply(cup: entry.cup, me: entry.me, participants: [entry.me]))
        phase = .signedIn
        await refresh()
    }

    func createCup(name: String, cupName: String, anywhere: Bool) async {
        await attempt { api in
            let entry: EntryReply = try await api.send("POST", "/v1/cups", body: ["cupName": cupName, "name": name, "geofence": !anywhere])
            await enter(entry)
        }
    }

    func join(name: String, code: String) async {
        await attempt { api in
            let entry: EntryReply = try await api.send("POST", "/v1/join", body: ["code": code, "name": name])
            await enter(entry)
        }
    }

    /// Вход с нового телефона по коду возврата: очки и место в кубке сохраняются.
    func restore(code: String) async {
        await attempt { api in
            let entry: EntryReply = try await api.send("POST", "/v1/restore", body: ["code": code])
            await enter(entry)
        }
    }

    /// Одноразовый код возврата для участника (свой может получить каждый, чужой только админ).
    func restoreCode(for person: Person) async -> RestoreCode? {
        var result: RestoreCode?
        await attempt { api in
            result = try await api.send("POST", "/v1/participants/\(person.id)/restore")
        }
        return result
    }

    /// Где сейчас друзья. Вызывается раз в 15 секунд, пока открыта карта.
    func loadFriends() async {
        guard let api, phase == .signedIn else {
            if !friends.isEmpty { friends = [] }
            return
        }
        if let reply: LiveReply = try? await api.send("GET", "/v1/live") {
            let others = reply.positions.filter { $0.id != me?.id }
            if others != friends { friends = others }
        }
    }

    /// Обновить кубок и участников. Если сервер говорит, что меня удалили, выходим.
    func refresh() async {
        guard let api, token != nil else { return }
        do {
            let reply: MeReply = try await api.send("GET", "/v1/me")
            remember(reply)
            phase = .signedIn
        } catch let failure as ApiFailure where failure.code == "bad_token" || failure.code == "no_token" {
            forget()
            problem = "Этого телефона больше нет в кубке"
        } catch {
            // Нет связи: остаёмся с тем, что знали.
        }
    }

    private func forget() {
        if !isTokenTemporary { Keychain.deleteToken() }
        defaults.removeObject(forKey: cacheKey)
        token = nil
        cup = nil
        me = nil
        people = []
        friends = []
        duelCalls = 0
        todayPlace = nil
        todayPoints = nil
        duelWith = nil
        duelEnds = nil
        eventTitle = nil
        eventEnds = nil
        uploadedUntil = nil
        phase = .signedOut
    }

    /// Выйти из кубка на этом телефоне. Вернуться можно будет только заново, новым участником.
    func signOut() {
        forget()
        problem = nil
    }

    // MARK: - Кубок и участники

    func rename(_ person: Person, to name: String) async {
        await attempt { api in
            let _: OkReply = try await api.send("PATCH", "/v1/participants/\(person.id)", body: ["name": name])
            await refresh()
        }
    }

    func remove(_ person: Person) async {
        await attempt { api in
            let _: OkReply = try await api.send("DELETE", "/v1/participants/\(person.id)")
            await refresh()
        }
    }

    func makeAdmin(_ person: Person) async {
        await attempt { api in
            let _: OkReply = try await api.send("POST", "/v1/participants/\(person.id)/admin")
            await refresh()
        }
    }

    func newCode() async {
        await attempt { api in
            let reply: CupReply = try await api.send("POST", "/v1/cup/code")
            cup = reply.cup
        }
    }

    func updateCup(_ changes: [String: Any]) async {
        await attempt { api in
            let reply: CupReply = try await api.send("PATCH", "/v1/cup", body: changes)
            cup = reply.cup
        }
    }

    /// Общее жильё кубка. Ошибку связи не показываем: звёздочка останется на телефоне и уйдёт позже.
    func shareHome(_ home: HomePoint?) async {
        guard let api, phase == .signedIn, cup?.home != home else { return }
        let value: Any = home.map { ["lat": $0.lat, "lon": $0.lon] } ?? NSNull()
        if let reply: CupReply = try? await api.send("PATCH", "/v1/cup", body: ["home": value]) {
            cup = reply.cup
        }
    }

    // MARK: - Рейтинг

    func day() async -> DayReply? {
        guard let api, phase == .signedIn else { return nil }
        return try? await api.send("GET", "/v1/day")
    }

    func standings() async -> StandingsReply? {
        guard let api, phase == .signedIn else { return nil }
        return try? await api.send("GET", "/v1/standings")
    }

    func crowns() async -> CrownsReply? {
        guard let api, phase == .signedIn else { return nil }
        return try? await api.send("GET", "/v1/crowns")
    }

    // MARK: - Вечер

    func ceremony() async -> Ceremony? {
        guard let api, phase == .signedIn else { return nil }
        return try? await api.send("GET", "/v1/ceremony")
    }

    func replay() async -> ReplayReply? {
        guard let api, phase == .signedIn else { return nil }
        return try? await api.send("GET", "/v1/replay")
    }

    func games() async -> GamesReply? {
        guard let api, phase == .signedIn else { return nil }
        return try? await api.send("GET", "/v1/games")
    }

    /// Начать «Реакцию» (только админ).
    func startGame() async -> Bool {
        await attempt { api in
            let _: GameReply = try await api.send("POST", "/v1/games", body: [:])
        }
    }

    /// Мои времена в мс; nil за фальстарт.
    func sendReaction(_ game: ReactionGame, times: [Double?]) async -> Bool {
        let payload: [Any] = times.map { $0.map { Int($0.rounded()) as Any } ?? NSNull() }
        return await attempt { api in
            let _: GameReply = try await api.send("POST", "/v1/games/\(game.id)/result", body: ["times": payload])
        }
    }

    // MARK: - Дуэли

    /// Дуэли кубка. Заодно обновляет число вызовов, ждущих моего ответа (точка на вкладке).
    func duels() async -> DuelsReply? {
        guard let api, phase == .signedIn else { return nil }
        guard let reply: DuelsReply = try? await api.send("GET", "/v1/duels") else { return nil }
        let waiting = reply.duels.filter { $0.status == "pending" && $0.opponent.id == me?.id }.count
        if waiting != duelCalls { duelCalls = waiting }

        // Идущая дуэль со мной: время сервера переводим в часы телефона.
        let offset = reply.now - Date().timeIntervalSince1970
        if let mine = reply.duels.first(where: { $0.status == "active" && $0.involves(me?.id) }), let end = mine.endsAt {
            duelWith = mine.challenger.id == me?.id ? mine.opponent.name : mine.challenger.name
            duelEnds = Date(timeIntervalSince1970: end - offset)
        } else {
            duelWith = nil
            duelEnds = nil
        }

        if !isTokenTemporary {
            if !askedNotifications {
                askedNotifications = true
                Notifier.askPermission()
            }
            announce(reply)
        }
        return reply
    }

    /// Уведомления о дуэлях: вызов мне, ответ на мой вызов, итог. Каждое показывается один раз,
    /// старые новости (после переустановки или долгого перерыва) пропускаются.
    private func announce(_ reply: DuelsReply) {
        guard let myID = me?.id else { return }
        var seen = Set(defaults.stringArray(forKey: seenKey) ?? [])
        for duel in reply.duels where duel.involves(myID) {
            let key = "\(duel.id):\(duel.status)"
            if seen.contains(key) { continue }
            seen.insert(key)
            let iChallenged = duel.challenger.id == myID
            let other = iChallenged ? duel.opponent.name : duel.challenger.name
            let mine = iChallenged ? duel.challenger.value : duel.opponent.value
            let theirs = iChallenged ? duel.opponent.value : duel.challenger.value
            switch duel.status {
            case "pending" where !iChallenged:
                Notifier.post(id: key, title: "\(other) вызывает тебя на дуэль", body: "\(duel.title). \(duel.rule). Ответить можно в разделе «Дуэли».")
            case "active" where iChallenged && reply.now - (duel.startsAt ?? 0) < 600:
                Notifier.post(id: key, title: "Вызов принят: \(other)", body: "\(duel.title). Время пошло: \(duel.rule.lowercased()).")
            case "declined" where iChallenged && reply.now - duel.createdAt < 2_400:
                Notifier.post(id: key, title: "Дуэли не будет: \(other)", body: "\(duel.title): вызов отклонён, очки на месте.")
            case "finished" where reply.now - (duel.endsAt ?? 0) < 2_400:
                let score = "\(duel.title): \(duel.text(mine)) против \(duel.text(theirs))."
                if duel.winner == nil {
                    Notifier.post(id: key, title: "Дуэль с \(other): ничья", body: "\(score) Очки на месте.")
                } else if duel.winner == myID {
                    Notifier.post(id: key, title: "Дуэль с \(other): победа, +\(duel.stake)", body: score)
                } else {
                    Notifier.post(id: key, title: "Дуэль с \(other): поражение, −\(duel.stake)", body: score)
                }
            default:
                break
            }
        }
        // Помним только дуэли из свежего списка: он ограничен, список отметок тоже.
        let listed = Set(reply.duels.map(\.id))
        let kept = seen.filter { key in listed.contains(String(key.prefix { $0 != ":" })) }
        defaults.set(Array(kept), forKey: seenKey)
    }

    // MARK: - События дня

    /// События сегодня. Заодно запоминает идущее (для Live Activity) и показывает уведомления о начале и итоге.
    func events() async -> EventsReply? {
        guard let api, phase == .signedIn else { return nil }
        guard let reply: EventsReply = try? await api.send("GET", "/v1/events") else { return nil }
        let offset = reply.now - Date().timeIntervalSince1970
        if let running = reply.events.first(where: { $0.status == "active" }) {
            eventTitle = running.title
            eventEnds = Date(timeIntervalSince1970: running.endsAt - offset)
        } else {
            eventTitle = nil
            eventEnds = nil
        }
        if !isTokenTemporary {
            announce(reply)
        }
        return reply
    }

    private func announce(_ reply: EventsReply) {
        var seen = Set(defaults.stringArray(forKey: seenEventsKey) ?? [])
        for event in reply.events {
            let key = "\(event.id):\(event.status == "finished" ? "finished" : "started")"
            if seen.contains(key) { continue }
            seen.insert(key)
            if event.status == "finished" {
                guard reply.now - event.endsAt < 2_400 else { continue }
                let mine = event.awards.first { $0.id == me?.id }
                let body = mine.map { "Тебе +\($0.points). Итог: \(event.outcome)." } ?? "Итог: \(event.outcome)."
                Notifier.post(id: key, title: "Событие окончено: \(event.title)", body: body)
            } else if event.status == "active" {
                let leaderName = event.entries.first { $0.leader == true }?.name
                Notifier.post(id: key, title: "Событие: \(event.title)", body: "\(event.rule(leaderName: leaderName)) Время: \(Duel.span(event.minutes)).")
            }
        }
        let listed = Set(reply.events.map(\.id))
        let kept = seen.filter { key in listed.contains(String(key.prefix { $0 != ":" })) }
        defaults.set(Array(kept), forKey: seenEventsKey)
    }

    /// Запустить событие прямо сейчас (только админ). kind: double, best, explore, hunt или nil для случайного.
    func startEvent(kind: String?) async {
        let body: [String: Any] = kind.map { ["kind": $0] } ?? [:]
        await attempt { api in
            let _: EventReply = try await api.send("POST", "/v1/events", body: body)
        }
    }

    /// Моё место и очки за сегодня: их показывает Live Activity. Вызывается раз в полминуты во время записи.
    func refreshToday() async {
        guard let reply = await day(), let index = reply.rows.firstIndex(where: { $0.id == me?.id }) else { return }
        let row = reply.rows[index]
        todayPoints = row.points
        todayPlace = row.points > 0 ? index + 1 : nil
    }

    /// Вызвать на дуэль. Причина отказа сервера (соперник занят, предел на день) попадает в problem.
    func challenge(_ opponent: Person, kind: String, trail: Int?, minutes: Int) async -> Bool {
        var body: [String: Any] = ["opponent": opponent.id, "kind": kind, "minutes": minutes]
        if let trail { body["trail"] = trail }
        let payload = body
        return await attempt { api in
            let _: DuelReply = try await api.send("POST", "/v1/duels", body: payload)
        }
    }

    /// Ответ на вызов: accept, decline или cancel.
    func answer(_ duel: Duel, _ action: String) async -> Bool {
        await attempt { api in
            let _: DuelReply = try await api.send("POST", "/v1/duels/\(duel.id)/\(action)")
        }
    }

    // MARK: - Аватары

    func setAvatar(_ image: UIImage) async {
        guard let jpeg = Self.avatarData(from: image) else {
            problem = "Не получилось подготовить картинку"
            return
        }
        await attempt { api in
            _ = try await api.uploadAvatar(jpeg)
            await refresh()
        }
    }

    func removeAvatar() async {
        await attempt { api in
            let _: AvatarReply = try await api.send("DELETE", "/v1/me/avatar")
            await refresh()
        }
    }

    func avatarImage(for person: Person) async -> UIImage? {
        guard let version = person.avatar, let api else { return nil }
        let key = "\(person.id)-\(version)" as NSString
        if let ready = avatars.object(forKey: key) { return ready }
        guard let data = try? await api.avatar(of: person.id, version: version), let image = UIImage(data: data) else { return nil }
        avatars.setObject(image, forKey: key)
        return image
    }

    /// Квадрат 256×256 из середины картинки, JPEG около 20–40 КБ.
    private static func avatarData(from image: UIImage) -> Data? {
        let side = min(image.size.width, image.size.height)
        guard side > 0 else { return nil }
        let target = CGSize(width: 256, height: 256)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let scale = target.width / side
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (target.width - drawn.width) / 2, y: (target.height - drawn.height) / 2)
        let square = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: origin, size: drawn))
        }
        return square.jpegData(compressionQuality: 0.82)
    }

    // MARK: - Отправка трека

    /// Отправляет на сервер точки, которых там ещё нет. Вызывается раз в полминуты и при открытии приложения.
    func sync(_ tracker: Tracker) async {
        guard let api, phase == .signedIn, !isSyncing, let me else { return }
        isSyncing = true
        defer { isSyncing = false }

        let key = "uploadedUntil-\(me.id)"
        if uploadedUntil == nil {
            if defaults.object(forKey: key) != nil {
                uploadedUntil = defaults.double(forKey: key)
            } else if let reply: TracksReply = try? await api.send("GET", "/v1/tracks/last") {
                uploadedUntil = reply.last ?? 0
            } else {
                return
            }
        }

        // Не больше пяти пачек за раз, чтобы не держать связь слишком долго.
        for _ in 0..<5 {
            let batch = tracker.points(after: uploadedUntil ?? 0, limit: 2_000)
            guard let lastPoint = batch.last else { return }
            let rows = batch.map { [$0.time.timeIntervalSince1970, $0.latitude, $0.longitude, $0.altitude, $0.speed, $0.accuracy] }
            guard let _: TracksReply = try? await api.send("POST", "/v1/tracks", body: ["points": rows]) else { return }
            uploadedUntil = lastPoint.time.timeIntervalSince1970
            defaults.set(uploadedUntil, forKey: key)
            if batch.count < 2_000 { return }
        }
    }
}
