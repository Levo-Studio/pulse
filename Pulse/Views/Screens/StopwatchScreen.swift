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

    /// How long the screen waits after a tap before deciding no further tap is
    /// coming. It has to be long enough that an ordinary triple tap lands inside it,
    /// and it is matched to UIKit's own multi-tap interval so a tap rhythm that works
    /// elsewhere on iOS works here.
    ///
    /// Only the double tap waits it out, and the wait is purely visual: the toggle is
    /// recorded against the instant the tap arrived, not the instant the window
    /// closed, so nothing about the reading depends on this value.
    private static let tapWindow: Duration = .milliseconds(350)

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

    /// The taps gathered so far, and what they mean.
    @State private var tapSequence = StopwatchTapSequence()

    /// Closes the current tap sequence once `tapWindow` passes with no further tap.
    @State private var tapWindowTask: Task<Void, Never>?

    /// The accessibility identifier of the elapsed readout, so UI tests can address
    /// it directly.
    public static let readoutIdentifier = "stopwatch.readout"

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
            // Named so a UI test can address the readout directly. Scanning every
            // static text for one shaped like a time instead means snapshotting and
            // filtering the whole tree on each read, against a view that redraws four
            // times a second.
            .accessibilityIdentifier(Self.readoutIdentifier)

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
        .onDisappear { flushPendingTaps() }
        .task(id: tickIdentity) {
            await runTickLoop()
        }
    }

    /// Folds one tap into the current sequence and acts once the sequence closes.
    ///
    /// `StopwatchTapSequence` holds the decision and records the instant each tap
    /// arrived; this view only owns the timer that decides when to stop waiting for a
    /// further tap. A reset comes back decided and fires straight away — three taps is
    /// the longest sequence the screen recognises — so only the double tap waits, and
    /// its wait is purely visual: the toggle is recorded against the instant the tap
    /// arrived, not the instant this view got around to telling the stopwatch.
    private func registerTap() {
        tapWindowTask?.cancel()
        tapWindowTask = nil

        if let decided = tapSequence.register(at: Date()) {
            apply(decided)
            return
        }

        tapWindowTask = Task {
            do {
                try await Task.sleep(for: Self.tapWindow)
            } catch {
                return
            }

            tapWindowTask = nil
            apply(tapSequence.close())
        }
    }

    /// Commits any sequence still inside its window, then clears it.
    ///
    /// Called when the page goes away. Discarding the pending sequence instead would
    /// swallow a double tap the user completed and then swiped away from inside the
    /// window, which reads as the gesture having been ignored. Because the sequence
    /// carries the tap's own instant, flushing early records the same moment the
    /// window would have.
    private func flushPendingTaps() {
        tapWindowTask?.cancel()
        tapWindowTask = nil
        apply(tapSequence.close())
    }

    /// Carries out what a run of taps turned out to mean.
    private func apply(_ outcome: StopwatchTapOutcome) {
        switch outcome {
        case .ignore:
            break
        case .toggle(let instant):
            stopwatch.toggle(at: instant)
        case .reset:
            performReset()
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
