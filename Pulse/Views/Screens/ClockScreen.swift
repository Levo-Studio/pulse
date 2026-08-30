import SwiftUI

/// The CLOCK screen: the time of day with the date beneath it.
///
/// Transcribed from the `01 CLOCK` frame of `design/Pulse.dc.html` — content
/// centred in the frame, time at reference size 70 with 2 units of tracking in
/// `PixelTheme.primary`, date at size 16 with 5 units of tracking in
/// `PixelTheme.muted`, and 20 reference units between the two lines. All sizes
/// pass through `PixelMetrics`, so the screen holds its proportions on any
/// device. Drawn flat: the reference is labelled `NO GLOW`.
///
/// The reference frame also carries a third line, `21°C`. No weather source is
/// specified in the brief and the app stores no weather credential, so it is not
/// implemented; the screen ships as time plus date.
public struct ClockScreen: View {

    @Environment(\.activeScreen) private var activeScreen
    @Environment(\.scenePhase) private var scenePhase

    @State private var ticker = ClockTicker()

    /// Creates the screen.
    public init() {}

    public var body: some View {
        PixelScreenBackdrop(spacing: 20) {
            PixelLabel(
                ticker.reading.time,
                size: 70,
                tracking: 2,
                color: PixelTheme.primary,
                // The reference sets `line-height: 1` on the time, so the 20 units
                // below it are measured from a one-em box, not from the taller box
                // the face asks for.
                lineBox: .tight
            )

            PixelLabel(
                ticker.reading.date,
                size: 16,
                tracking: 5,
                color: PixelTheme.muted
            )
        }
        .accessibilityElement(children: .combine)
        .onAppear { synchroniseTicker() }
        .onDisappear { ticker.stop() }
        .onChange(of: activeScreen) { synchroniseTicker() }
        .onChange(of: scenePhase) { synchroniseTicker() }
    }

    /// Whether the screen is the one the user is actually looking at.
    ///
    /// The pager may keep a page alive off-screen, and the app may be in the
    /// background with the view still mounted; in either case the clock has no
    /// reason to tick.
    private var isVisible: Bool {
        activeScreen == .clock && scenePhase == .active
    }

    private func synchroniseTicker() {
        if isVisible {
            // `start` also refreshes, so a screen returning to view never shows a
            // stale minute from before it was paged away.
            ticker.start()
        } else {
            ticker.stop()
        }
    }
}

#Preview {
    ClockScreen()
        .background(PixelTheme.background)
}
