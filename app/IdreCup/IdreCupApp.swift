import SwiftUI

@main
struct IdreCupApp: App {
    init() {
        Notifier.shared.install()
        // Трекер создаётся сразу: команда с часов может разбудить приложение в фоне, без экранов.
        _ = Tracker.shared
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
