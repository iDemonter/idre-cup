import SwiftUI

@main
struct IdreCupApp: App {
    var body: some Scene {
        WindowGroup {
            MapScreen()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
