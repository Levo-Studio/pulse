import SwiftUI

/// Pulse — an ambient pixel display.
///
/// Five full-screen views the user pages through: clock, stopwatch, GitHub
/// contributions, Levo Studio service uptime, and the settings holding the stored
/// credentials and the clock's display preferences. The app is dark-mode only.
@main
struct PulseApp: App {

    /// The stopwatch, owned here rather than by its screen so paging away from a
    /// running stopwatch cannot tear its state down with the page.
    @State private var stopwatch = StopwatchState()

    init() {
        PixelFont.register()
    }

    var body: some Scene {
        WindowGroup {
            PulsePager()
                .environment(stopwatch)
        }
    }
}
