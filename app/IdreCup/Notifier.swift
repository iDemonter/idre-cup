import UserNotifications

/// Уведомления на самом телефоне (без сервера Apple): приложение узнаёт новости при обмене с сервером
/// раз в полминуты и показывает их сама. Работает, пока приложение открыто или пишет трек в фоне.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    /// Вызывается при запуске: без этого уведомления не показываются, пока приложение на экране.
    func install() {
        UNUserNotificationCenter.current().delegate = self
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
