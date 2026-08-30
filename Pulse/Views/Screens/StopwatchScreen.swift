import SwiftUI

/// The STOPWATCH screen.
///
/// A centred `HH:MM:SS` readout with the time of day beneath it, matching frame
/// `02 STOPWATCH` in `design/Pulse.dc.html`. Double-tapping anywhere on the readout
/// starts and stops the stopwatch, triple-tapping resets it to zero, and a single tap
/// does nothing. Telling the two sequences apart costs the double tap a short wait;
/// see `registerTap()`.
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

    /// Number of taps that starts and stops the stopwatch.
    private static let toggleTapCount = 2

    /// Number of taps that resets the stopwatch to zero.
    private static let resetTapCount = 3

    /// How long the screen waits after a tap before deciding no further tap is
    /// coming. It sets the cost of telling a double tap from a triple one: only the
    /// double tap pays it, and it has to be long enough that an ordinary triple tap
    /// still lands inside it. Close to the system's own multi-tap interval, so a tap
    /// rhythm that works elsewhere on iOS works here.
    private static let tapWindow: Duration = .milliseconds(300)

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

    /// Taps seen so far in the current sequence.
    @State private var tapCount = 0

    /// Closes the current tap sequence once `tapWindow` passes with no further tap.
    @State private var tapWindowTask: Task<Void, Never>?

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
        .onTapGesture { registerTap() }
        .onDisappear {
            tapWindowTask?.cancel()
            tapCount = 0
        }
        .task(id: tickIdentity) {
            await runTickLoop()
        }
    }

    /// Folds one tap into the current sequence and acts once the sequence closes.
    ///
    /// The two counts are resolved here rather than by two tap gestures. Two
    /// recognisers — stacked as separate modifiers or composed with
    /// `exclusively(before:)` — both let the two-tap one succeed the instant the
    /// second tap lands, which starts the stopwatch underneath a triple tap that was
    /// meant to reset it. Counting the taps explicitly is the only arrangement that
    /// can tell the two apart, because it is the only one that waits.
    ///
    /// Three taps is the longest sequence the screen recognises, so a reset fires as
    /// soon as the third tap lands. Only the shorter sequences wait out the window,
    /// and only the two-tap one does anything at the end of it; a single tap is
    /// deliberately inert.
    private func registerTap() {
        tapWindowTask?.cancel()
        tapCount += 1

        guard tapCount < Self.resetTapCount else {
            tapCount = 0
            performReset()
            return
        }

        tapWindowTask = Task {
            do {
                try await Task.sleep(for: Self.tapWindow)
            } catch {
                return
            }

            let taps = tapCount
            tapCount = 0
            if taps == Self.toggleTapCount {
                stopwatch.toggle()
            }
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
