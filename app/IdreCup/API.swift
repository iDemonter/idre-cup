import Foundation
import Security

// Ответы сервера. Описание запросов: server/API.md.

struct HomePoint: Codable, Equatable {
    let lat: Double
    let lon: Double
}

struct CupInfo: Codable, Equatable {
    let id: String
    var name: String
    var code: String
    var startsOn: String?
    var days: Int
    var prize: String?
    var geofence: Bool
    var home: HomePoint?
}

struct Person: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    var isAdmin: Bool
    /// Номер версии аватара или nil, если его нет.
    var avatar: Int?
}

struct EntryReply: Decodable {
    let cup: CupInfo
    let me: Person
    let token: String
}

struct MeReply: Codable {
    var cup: CupInfo
    var me: Person
    var participants: [Person]
}

struct CupReply: Decodable {
    let cup: CupInfo
}

struct DayRow: Decodable, Identifiable {
    let id: String
    let name: String
    /// м/с
    let topSpeed: Double
    let vertical: Double
    let runs: Int
    let distance: Double
    let speedPlace: Int?
    let speedPoints: Int
    let volumePlace: Int?
    let volumePoints: Int
    let points: Int
    /// Короны на конец дня и выигранные автогонки. На старом сервере этих полей нет.
    let crowns: Int?
    let raceWins: Int?
    /// Очки дуэлей за день: плюс за победы, минус за поражения.
    let duelPoints: Int?
    /// Очки за события дня и метры, которые «двойной счёт» добавил в объём.
    let eventPoints: Int?
    let bonusVertical: Double?
}

struct CrownRow: Decodable, Identifiable {
    struct Holder: Decodable {
        let id: String
        let name: String?
        let seconds: Double
    }

    let number: Int
    let name: String
    let holder: Holder?
    /// Моё лучшее время на трассе, секунды.
    let mine: Double?

    var id: Int { number }
}

struct CrownsReply: Decodable {
    let trails: [CrownRow]
}

struct DayReply: Decodable {
    let date: String
    let dayNumber: Int?
    let multiplier: Int
    let rows: [DayRow]
}

struct StandingRow: Decodable, Identifiable {
    let id: String
    let name: String
    let points: Int
    let days: [Int]
    let place: Int
    /// Какой день (номер в days) закрыт джокером. На старом сервере поля нет.
    let joker: Int?
}

/// Майки: у кого какая. nil, если лидера нет или лидеров несколько.
struct Jerseys: Decodable {
    let leader: String?
    let crowns: String?
    let volume: String?
}

struct StandingsReply: Decodable {
    let today: String
    let dates: [String]
    let rows: [StandingRow]
    let jerseys: Jerseys?
}

/// Где сейчас участник: его последняя точка за 15 минут.
struct LivePosition: Decodable, Identifiable, Equatable {
    let id: String
    let name: String?
    let t: Double
    let lat: Double
    let lon: Double
}

struct LiveReply: Decodable {
    let positions: [LivePosition]
}

/// Дуэль один на один. Значения сторон: гонка в секундах, скорость в м/с, выносливость в метрах.
struct Duel: Decodable, Identifiable, Equatable {
    struct Side: Decodable, Equatable {
        let id: String
        let name: String
        let value: Double?
    }

    struct Trail: Decodable, Equatable {
        let number: Int
        let name: String
    }

    let id: String
    /// race, speed или endurance.
    let kind: String
    let trail: Trail?
    let minutes: Int
    let stake: Int
    /// pending, active, counting, finished, declined, cancelled или expired.
    let status: String
    let createdAt: Double
    let answerBy: Double?
    let startsAt: Double?
    let endsAt: Double?
    let challenger: Side
    let opponent: Side
    let winner: String?
}

struct DuelsReply: Decodable {
    /// Время сервера, секунды с 1970: по нему телефон ведёт отсчёт.
    let now: Double
    let stake: Int
    let answerMinutes: Int
    /// Вид дуэли → сколько минут она может длиться.
    let minutes: [String: [Int]]
    /// Сколько дуэлей мне осталось сегодня.
    let left: Int
    let duels: [Duel]
}

struct DuelReply: Decodable {
    let duel: Duel
}

/// Событие дня: короткое задание для всего кубка. Виды: double, best, explore, hunt.
struct GameEvent: Decodable, Identifiable, Equatable {
    struct Entry: Decodable, Equatable {
        let id: String
        let name: String
        /// Что показал за время события: метры (double), м/с (best, hunt) или номер трассы (explore).
        let value: Double?
        /// Что надо превзойти, м/с.
        let goal: Double?
        let done: Bool
        let leader: Bool?
    }

    struct Award: Decodable, Equatable {
        let id: String
        let name: String
        let points: Int
    }

    let id: String
    let kind: String
    /// active, counting или finished.
    let status: String
    let startsAt: Double
    let endsAt: Double
    let minutes: Int
    let points: Int?
    let leader: String?
    let entries: [Entry]
    let awards: [Award]
}

struct EventsReply: Decodable {
    let now: Double
    /// Сколько событий ещё будет сегодня. Их время сервер не раскрывает.
    let upcoming: Int
    let events: [GameEvent]
}

struct EventReply: Decodable {
    let event: GameEvent
}

struct RestoreCode: Decodable, Identifiable {
    let code: String
    let name: String
    let hours: Int

    var id: String { code }
}

struct TracksReply: Decodable {
    let last: Double?
}

struct AvatarReply: Decodable {
    let avatar: Int?
}

struct OkReply: Decodable {
    let ok: Bool?
}

/// Ошибка с текстом, который можно показать человеку.
struct ApiFailure: LocalizedError {
    let code: String
    let message: String

    var errorDescription: String? { message }

    static let offline = ApiFailure(code: "network", message: "Нет связи с сервером")
}

/// Запросы к серверу Idre Cup.
struct API {
    let base: URL
    var token: String?

    private struct Failure: Decodable {
        let error: String
        let message: String?
    }

    private func makeRequest(_ method: String, _ path: String) -> URLRequest {
        var request = URLRequest(url: URL(string: path, relativeTo: base) ?? base)
        request.httpMethod = method
        request.timeoutInterval = 20
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ApiFailure.offline
        }
        guard let http = response as? HTTPURLResponse else { throw ApiFailure.offline }
        guard (200..<300).contains(http.statusCode) else {
            if let failure = try? JSONDecoder().decode(Failure.self, from: data) {
                throw ApiFailure(code: failure.error, message: failure.message ?? "Сервер ответил ошибкой")
            }
            throw ApiFailure(code: "http_\(http.statusCode)", message: "Сервер ответил ошибкой \(http.statusCode)")
        }
        return data
    }

    /// Запрос с телом JSON (или без тела) и разбором ответа.
    func send<Reply: Decodable>(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> Reply {
        var request = makeRequest(method, path)
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data = try await perform(request)
        do {
            return try JSONDecoder().decode(Reply.self, from: data)
        } catch {
            throw ApiFailure(code: "bad_reply", message: "Сервер ответил непонятно. Возможно, приложение пора обновить")
        }
    }

    func uploadAvatar(_ jpeg: Data) async throws -> Int? {
        var request = makeRequest("PUT", "/v1/me/avatar")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = jpeg
        let data = try await perform(request)
        return (try? JSONDecoder().decode(AvatarReply.self, from: data))?.avatar
    }

    func avatar(of id: String, version: Int) async throws -> Data {
        try await perform(makeRequest("GET", "/v1/participants/\(id)/avatar?v=\(version)"))
    }
}

/// Токен устройства в связке ключей: переживает обновление приложения.
enum Keychain {
    private static let service = "com.idemonter.idrecup"
    private static let account = "device-token"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func readToken() -> String? {
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func saveToken(_ token: String) {
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    static func deleteToken() {
        SecItemDelete(query as CFDictionary)
    }
}
