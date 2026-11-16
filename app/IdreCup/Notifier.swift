import UserNotifications

/// Уведомления на самом телефоне (без сервера Apple): приложение узнаёт новости при обмене с сервером
/// раз в полминуты и показывает их сама. Работает, пока приложение открыто или пишет трек в фоне.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    /// Что делать по кнопке «Начать запись» в уведомлении. Задаёт RootView.
    var onStartRecording: (() -> Void)?
    /// Нажали кнопку, пока RootView ещё не готов: запись начнётся, как только он задаст onStartRecording.
    var pendingStart = false

    private static let category = "record"
    private static let startAction = "start"
    static let morningPrefix = "morning-"

    /// Вызывается при запуске: без этого уведомления не показываются, пока приложение на экране.
    func install() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let start = UNNotificationAction(identifier: Self.startAction, title: "Начать запись", options: [.foreground])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [start], intentIdentifiers: [])])
    }

    /// Утренние напоминания включить запись: в 9:15 каждого дня кубка. Пересоздаются при смене дат.
    static func scheduleMornings(startsOn: String?, days: Int) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix(morningPrefix) })
            guard let startsOn, let first = ISO8601DateFormatter.day.date(from: startsOn) else { return }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
            for index in 0..<days {
                guard let day = calendar.date(byAdding: .day, value: index, to: first),
                      let moment = calendar.date(bySettingHour: 9, minute: 15, second: 0, of: day),
                      moment > Date() else { continue }
                let content = UNMutableNotificationContent()
                content.title = index == days - 1 ? "Последний день кубка: очки ×2" : "День \(index + 1) кубка"
                content.body = "Включи запись трека, чтобы спуски пошли в зачёт."
                content.sound = .default
                content.categoryIdentifier = category
                let parts = calendar.dateComponents(in: calendar.timeZone, from: moment)
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: DateComponents(timeZone: calendar.timeZone, year: parts.year, month: parts.month, day: parts.day, hour: parts.hour, minute: parts.minute),
                    repeats: false
                )
                center.add(UNNotificationRequest(identifier: "\(morningPrefix)\(index)", content: content, trigger: trigger))
            }
        }
    }

    /// Уведомление с кнопкой «Начать запись».
    static func postRecordPrompt(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let isPrompt = response.notification.request.content.categoryIdentifier == Self.category
        if isPrompt && (response.actionIdentifier == Self.startAction || response.actionIdentifier == UNNotificationDefaultActionIdentifier) {
            DispatchQueue.main.async {
                if let start = self.onStartRecording {
                    start()
                } else {
                    self.pendingStart = true
                }
            }
        }
        completionHandler()
    }

    /// Спросить разрешение. Система показывает вопрос один раз, повторные вызовы безвредны.
    static func askPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

extension ISO8601DateFormatter {
    /// «2027-01-03» в часовом поясе курорта.
    static let day: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(identifier: "Europe/Stockholm")
        return formatter
    }()
}
