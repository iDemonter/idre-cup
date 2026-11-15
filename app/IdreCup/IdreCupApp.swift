import SwiftUI

@main
struct IdreCupApp: App {
    init() {
        Notifier.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
