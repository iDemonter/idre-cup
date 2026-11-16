import SwiftUI

@main
struct IdreCupApp: App {
    init() {
        Notifier.shared.install()
        // Трекер создаётся сразу: команда с часов может разбудить приложение в фоне, без экранов.
        _ = Tracker.shared
        // Кнопки на экране блокировки (Live Activity) управляют тем же трекером.
        RecordingCommands.handler = { command in
            switch command {
            case "start": Tracker.shared.start()
            case "pause": Tracker.shared.pause()
            default: Tracker.shared.stop()
            }
        }
        PhoneLink.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
