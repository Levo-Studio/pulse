import SwiftUI

/// The STOPWATCH screen.
///
/// A centred `HH:MM:SS` readout with the time of day beneath it, matching frame
/// `02 STOPWATCH` in `design/Pulse.dc.html`. Double-tapping anywhere on the readout
/// starts and stops the stopwatch; a single tap does nothing.
///
/// The screen holds no stopwatch state of its own. It reads `StopwatchState` from
/// the environment, which lives above the pager, and only drives the redraw: the
/// tick loop runs while this screen is the active page and stops when it is not.
/// Elapsed time is derived from a timestamp, so it keeps advancing correctly while
/// nothing is redrawing.
public struct StopwatchScreen: View {

    /// How often the readout is refreshed while the screen is on-screen. The display
    /// has one-second resolution; refreshing a little faster keeps the second
    /// boundary from lagging visibly without redrawing wastefully.
    private static let tickInterval: Duration = .milliseconds(250)

    /// Formats the time-of-day readout. Fixed to `en_US_POSIX` so the 24-hour
    /// pattern in the reference is honoured regardless of the device's locale or its
    /// 12-hour clock setting.
    private static let timeOfDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    @Environment(\.pixelMetrics) private var metrics
    @Environment(StopwatchState.self) private var stopwatch
    @Environment(\.activeScreen) private var activeScreen
    @Environment(\.scenePhase) private var scenePhase

    /// The instant the readout was last rendered against. Advanced by the tick loop.
    @State private var now = Date()

    /// Creates the screen.
    public init() {}

    public var body: some View {
        PixelScreenBackdrop(spacing: 22) {
            PixelLabel(
                Self.elapsedText(stopwatch.elapsed(at: now)),
                size: 48,
                tracking: 2,
                color: PixelTheme.primary
            )

            PixelLabel(
                Self.timeOfDayFormatter.string(from: now),
                size: 14,
                tracking: 4,
                color: PixelTheme.faint
            )
            // The reference offsets the time-of-day line by a further 2 units on top
            // of the frame's 22-unit gap.
            .padding(.top, metrics(2))
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            stopwatch.toggle()
        }
        .task(id: tickIdentity) {
            await runTickLoop()
        }
    }

    /// The conditions that decide whether the readout should be refreshing. Changing
    /// any of them restarts the tick loop, which also resyncs `now` immediately.
    private var tickIdentity: TickIdentity {
        TickIdentity(isActiveScreen: activeScreen == .stopwatch, scenePhase: scenePhase)
    }

    /// Refreshes `now` on a fixed cadence while the screen is the active page and the
    /// app is in the foreground. Cancelled automatically when either stops holding.
    private func runTickLoop() async {
        now = Date()

        guard tickIdentity.isActiveScreen, scenePhase == .active else { return }

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: Self.tickInterval)
            } catch {
                return
            }
            now = Date()
        }
    }

    /// Renders an elapsed interval as `HH:MM:SS`.
    ///
    /// The reference shows three two-digit groups without naming them; they are read
    /// here as hours, minutes and seconds. Past 99 hours the hours field simply grows
    /// rather than wrapping, so a long run stays truthful.
    private static func elapsedText(_ elapsed: TimeInterval) -> String {
        let total = Int(max(0, elapsed))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

/// The inputs that gate the readout's tick loop.
private struct TickIdentity: Equatable {
    let isActiveScreen: Bool
    let scenePhase: ScenePhase
}

#Preview {
    StopwatchScreen()
        .environment(StopwatchState())
}
