import Foundation
import Security
import WidgetKit

/// Что видят виджет и кнопка записи в Пункте управления: место и очки за сегодня, цифры дня, идёт ли запись.
/// Приложение пишет это в общую связку ключей (группа ...idrecup.shared), расширение читает.
/// Общая связка ключей вместо App Group: для неё не нужна настройка в портале Apple, подпись в CI делает её сама.
struct RideSnapshot: Codable, Equatable {
    var cupName = "Idre Cup"
    var dayNumber: Int?
    var place: Int?
    var points: Int?
    /// «за Максом 4 очка» или «лидер дня».
    var behind: String?
    var topSpeed: Double = 0
    var vertical: Double = 0
    var runs = 0
    var recording = false
    /// День снимка (2026-11-17, по Стокгольму): вчерашние цифры виджет не показывает.
    var date = ""

    static func today() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    var isToday: Bool { date == Self.today() }
}

enum WidgetShare {
    static let rideWidgetKind = "com.idemonter.idrecup.ride"
    static let recordControlKind = "com.idemonter.idrecup.record"

    private static let service = "com.idemonter.idrecup.widget"
    private static let account = "snapshot"

    /// Группа связки ключей с префиксом команды: «ABCDE12345.com.idemonter.idrecup.shared».
    private static var group: String? {
        guard let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String, !prefix.isEmpty else { return nil }
        return prefix + "com.idemonter.idrecup.shared"
    }

    private static var query: [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        if let group { query[kSecAttrAccessGroup as String] = group }
        return query
    }

    static func read() -> RideSnapshot? {
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(RideSnapshot.self, from: data)
    }

    /// Меняет снимок и, если он правда изменился, просит систему перерисовать виджет и кнопку.
    static func update(_ change: (inout RideSnapshot) -> Void) {
        let old = read()
        var snapshot = old ?? RideSnapshot()
        if !snapshot.isToday {
            // Новый день: цифры с нуля, название кубка и запись остаются.
            snapshot = RideSnapshot(cupName: snapshot.cupName, recording: snapshot.recording)
        }
        snapshot.date = RideSnapshot.today()
        change(&snapshot)
        guard snapshot != old, let data = try? JSONEncoder().encode(snapshot) else { return }
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        // Экран блокировки: виджет читает данные и при заблокированном телефоне.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
        WidgetCenter.shared.reloadTimelines(ofKind: rideWidgetKind)
        if old?.recording != snapshot.recording {
            ControlCenter.shared.reloadControls(ofKind: recordControlKind)
        }
    }
}
