import SwiftUI

/// Pulse — an ambient pixel display.
///
/// Four full-screen views the user pages through: clock, stopwatch, GitHub
/// contributions, and Levo Studio service uptime. The app is dark-mode only.
@main
struct PulseApp: App {

    init() {
        PixelFont.register()
    }

    var body: some Scene {
        WindowGroup {
            PulsePager()
        }
    }
}
