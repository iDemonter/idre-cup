import UIKit
import WatchConnectivity

/// Связь с часами. Часы присылают команды «старт», «пауза», «стоп», телефон отвечает своим состоянием
/// и сам шлёт его на часы, когда оно меняется. Команда с часов будит приложение на телефоне в фоне.
final class PhoneLink: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = PhoneLink()

    /// На часах стоит Idre Cup: «Мой день» тогда предлагает разрешение «Всегда».
    @Published private(set) var hasWatchApp = false

    /// Место и очки за сегодня, идущие событие и дуэль. Задаёт RootView, пока приложение открыто.
    var extra: (() -> [String: Any])?

    private var lastSent: [String: Any] = [:]
    private var lastSentAt = Date.distantPast

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Трекер что-то поменял: шлём на часы. Смену записи и паузы сразу, цифры не чаще раза в 10 секунд.
    func trackerChanged(force: Bool = false) {
        DispatchQueue.main.async {
            let state = self.state()
            let flipped = state["recording"] as? Bool != self.lastSent["recording"] as? Bool
                || state["paused"] as? Bool != self.lastSent["paused"] as? Bool
            guard force || flipped || Date().timeIntervalSince(self.lastSentAt) >= 10 else { return }
            self.send(state)
        }
    }

    private func send(_ state: [String: Any]) {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        lastSent = state
        lastSentAt = Date()
        try? session.updateApplicationContext(state)
    }

    /// Состояние для часов. Пустых значений в словаре быть не может: их просто нет.
    private func state() -> [String: Any] {
        let tracker = Tracker.shared
        let stats = tracker.stats
        var state: [String: Any] = [
            "recording": tracker.isRecording && !tracker.isDemo,
            "paused": tracker.isPaused,
            "speed": stats.topSpeed,
            "vertical": stats.vertical,
            "runs": stats.runs,
            "moving": stats.movingTime,
            "always": tracker.isAlways,
            "denied": tracker.isDenied,
            "t": Date().timeIntervalSince1970,
        ]
        for (key, value) in extra?() ?? [:] {
            state[key] = value
        }
        return state
    }

    private func handle(_ command: String) -> [String: Any] {
        let tracker = Tracker.shared
        var note: String?
        switch command {
        case "start":
            if tracker.isDenied {
                note = "Геопозиция запрещена. Разреши её Idre Cup в настройках телефона."
            } else {
                tracker.start()
                // Из кармана запись начнётся только с разрешением «Всегда».
                if !tracker.isAlways && !Self.isForeground {
                    note = "Открой Idre Cup на телефоне: в «Моём дне» разреши геопозицию «Всегда»."
                }
            }
        case "pause":
            tracker.pause()
        case "stop":
            tracker.stop()
        default:
            break
        }
        var reply = state()
        if let note { reply["note"] = note }
        send(reply)
        return reply
    }

    private static var isForeground: Bool {
        var active = false
        let check = { active = UIApplication.shared.applicationState == .active }
        if Thread.isMainThread { check() } else { DispatchQueue.main.sync(execute: check) }
        return active
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.hasWatchApp = session.isPaired && session.isWatchAppInstalled
            self.trackerChanged(force: true)
        }
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.hasWatchApp = session.isPaired && session.isWatchAppInstalled
            self.trackerChanged(force: true)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Сменились часы: подключаемся заново.
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let command = message["command"] as? String ?? ""
        DispatchQueue.main.async {
            replyHandler(self.handle(command))
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let command = message["command"] as? String ?? ""
        DispatchQueue.main.async {
            _ = self.handle(command)
        }
    }

    /// Команда, отправленная, когда телефон был недоступен: доходит позже.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let command = userInfo["command"] as? String ?? ""
        DispatchQueue.main.async {
            _ = self.handle(command)
        }
    }
}
