import SwiftUI

/// The STOPWATCH screen.
///
/// A centred `HH:MM:SS` readout with the time of day beneath it, matching frame
/// `02 STOPWATCH` in `design/Pulse.dc.html`. Double-tapping anywhere on the readout
/// starts and stops the stopwatch, triple-tapping resets it to zero, and a single tap
/// does nothing.
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

    /// How far the readout dims at the bottom of the reset acknowledgement. Deep
    /// enough to register, shallow enough that the digits never leave the screen.
    private static let resetDipOpacity: Double = 0.2

    /// How long the readout takes to dim on a reset.
    private static let resetDipDuration: TimeInterval = 0.08

    /// How long the readout takes to come back up to full after the dip.
    private static let resetRecoveryDuration: TimeInterval = 0.4

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The instant the readout was last rendered against. Advanced by the tick loop.
    @State private var now = Date()

    /// The readout's opacity. Held at `1` except during the brief dip that
    /// acknowledges a reset.
    @State private var readoutOpacity: Double = 1

    /// Creates the screen.
    public init() {}

    public var body: some View {
        PixelScreenBackdrop(spacing: 22) {
            PixelLabel(
                Self.elapsedText(stopwatch.elapsed(at: now)),
                size: 48,
                tracking: 2,
                color: PixelTheme.primary,
                // `line-height: 1` in the reference, as on the clock: the 22 units
                // below the readout start at the bottom of a one-em box.
                lineBox: .tight
            )
            .opacity(readoutOpacity)

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
        .gesture(
            // The two gestures are composed rather than stacked as two separate
            // `onTapGesture` modifiers. Stacked, the two-tap recogniser wins the
            // moment the second tap lands and the third tap is never seen, so the
            // reset would either never fire or fire after an unwanted toggle.
            // `exclusively(before:)` attempts the longer gesture first and only falls
            // through to the shorter one once the third tap has failed to arrive.
            TapGesture(count: 3)
                .onEnded { performReset() }
                .exclusively(before: TapGesture(count: 2).onEnded { stopwatch.toggle() })
        )
        .task(id: tickIdentity) {
            await runTickLoop()
        }
    }

    /// Resets the stopwatch and acknowledges it on the readout.
    ///
    /// The readout is already showing `00:00:00` by the time the dip plays, so the
    /// animation only has to say *something happened*; it carries no information of
    /// its own and is dropped entirely when the user has asked for reduced motion.
    /// Only `opacity` is animated, and nothing about the gesture waits on it.
    private func performReset() {
        stopwatch.reset()
        now = Date()

        guard !reduceMotion else { return }

        withAnimation(.linear(duration: Self.resetDipDuration)) {
            readoutOpacity = Self.resetDipOpacity
        }
        withAnimation(.easeOut(duration: Self.resetRecoveryDuration).delay(Self.resetDipDuration)) {
            readoutOpacity = 1
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
