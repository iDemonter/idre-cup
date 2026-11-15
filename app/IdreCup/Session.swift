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

    // MARK: - Дуэли

    /// Дуэли кубка. Заодно обновляет число вызовов, ждущих моего ответа (точка на вкладке).
    func duels() async -> DuelsReply? {
        guard let api, phase == .signedIn else { return nil }
        guard let reply: DuelsReply = try? await api.send("GET", "/v1/duels") else { return nil }
        let waiting = reply.duels.filter { $0.status == "pending" && $0.opponent.id == me?.id }.count
        if waiting != duelCalls { duelCalls = waiting }
        return reply
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
