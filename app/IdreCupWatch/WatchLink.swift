import Foundation
import WatchConnectivity
import WatchKit

/// Что телефон рассказал о записи. Ключи совпадают с PhoneLink в приложении на телефоне.
struct PhoneState: Equatable {
    var recording = false
    var paused = false
    /// м/с
    var speed = 0.0
    var vertical = 0.0
    var runs = 0
    var moving: TimeInterval = 0
    var always = false
    var denied = false
    var place: Int?
    var points: Int?
    var event: String?
    var eventEnds: Date?
    var duel: String?
    var duelEnds: Date?
    /// Когда телефон это прислал.
    var time: Date?

    init() {}

    init(_ dictionary: [String: Any]) {
        recording = dictionary["recording"] as? Bool ?? false
        paused = dictionary["paused"] as? Bool ?? false
        speed = dictionary["speed"] as? Double ?? 0
        vertical = dictionary["vertical"] as? Double ?? 0
        runs = dictionary["runs"] as? Int ?? 0
        moving = dictionary["moving"] as? Double ?? 0
        always = dictionary["always"] as? Bool ?? false
        denied = dictionary["denied"] as? Bool ?? false
        place = dictionary["place"] as? Int
        points = dictionary["points"] as? Int
        event = dictionary["event"] as? String
        eventEnds = (dictionary["eventEnds"] as? Double).map(Date.init(timeIntervalSince1970:))
        duel = dictionary["duel"] as? String
        duelEnds = (dictionary["duelEnds"] as? Double).map(Date.init(timeIntervalSince1970:))
        time = (dictionary["t"] as? Double).map(Date.init(timeIntervalSince1970:))
    }
}

/// Связь с телефоном: команды «start», «pause», «stop» и состояние записи в ответ.
final class WatchLink: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var state = PhoneState()
    @Published private(set) var isSending = false
    /// Подсказка от телефона или о связи. Пропадает со следующим успешным ответом.
    @Published private(set) var note: String?
    /// Команда ушла в очередь: телефон сейчас недоступен и выполнит её, когда появится связь.
    @Published private(set) var isQueued = false

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ command: String) {
        let session = WCSession.default
        guard session.activationState == .activated else {
            note = "Нет связи с телефоном"
            return
        }
        WKInterfaceDevice.current().play(command == "start" ? .start : .stop)
        // Сразу показываем ожидаемое, телефон потом подтвердит.
        switch command {
        case "start": state.recording = true; state.paused = false
        case "pause": state.recording = false; state.paused = true
        default: state.recording = false; state.paused = false
        }
        if session.isReachable {
            isSending = true
            session.sendMessage(["command": command], replyHandler: { reply in
                DispatchQueue.main.async {
                    self.isSending = false
                    self.isQueued = false
                    self.state = PhoneState(reply)
                    self.note = reply["note"] as? String
                }
            }, errorHandler: { _ in
                DispatchQueue.main.async {
                    self.isSending = false
                    self.queue(command)
                }
            })
        } else {
            queue(command)
        }
    }

    /// Телефон недоступен: команда дойдёт, когда появится связь.
    private func queue(_ command: String) {
        WCSession.default.transferUserInfo(["command": command, "t": Date().timeIntervalSince1970])
        isQueued = true
        note = "Телефон не отвечает. Команда выполнится, когда он будет рядом."
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        DispatchQueue.main.async {
            if !context.isEmpty { self.state = PhoneState(context) }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async {
            self.state = PhoneState(applicationContext)
            self.isQueued = false
        }
    }
}
