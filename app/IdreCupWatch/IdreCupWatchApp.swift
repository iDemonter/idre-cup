import SwiftUI

/// Idre Cup на часах: пульт записи трека. GPS пишет телефон в кармане, часы только управляют им.
@main
struct IdreCupWatchApp: App {
    @StateObject private var link = WatchLink()

    var body: some Scene {
        WindowGroup {
            WatchHome()
                .environmentObject(link)
                .tint(Theme.accent)
        }
    }
}
