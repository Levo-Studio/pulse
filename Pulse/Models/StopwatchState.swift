import Foundation
import Observation

/// The running state of the stopwatch.
///
/// The value is owned above the pager and injected through the environment, because
/// `TabView` may tear a page down when it scrolls off-screen. Keeping it here means
/// swiping away from a running stopwatch and back leaves it untouched.
///
/// Elapsed time is never accumulated by a timer tick. It is derived from the
/// timestamp at which the current run began plus the intervals of the runs before
/// it, so it stays correct while the screen is off-screen, while the app is
/// backgrounded, and across missed ticks.
@Observable
public final class StopwatchState {

    /// When the current run began, or `nil` while the stopwatch is stopped.
    private var startedAt: Date?

    /// Total duration of the runs that have already been stopped.
    private var accumulated: TimeInterval

    /// Creates a stopped stopwatch reading zero.
    public init() {
        self.startedAt = nil
        self.accumulated = 0
    }

    /// Whether the stopwatch is currently running.
    public var isRunning: Bool { startedAt != nil }

    /// The time elapsed on the stopwatch as of `date`.
    ///
    /// - Parameter date: The instant to evaluate against, normally `Date()`. Passing
    ///   it in keeps the view's redraw cadence and the elapsed value independent.
    /// - Returns: The elapsed interval, never negative.
    public func elapsed(at date: Date) -> TimeInterval {
        guard let startedAt else { return accumulated }
        return max(0, accumulated + date.timeIntervalSince(startedAt))
    }

    /// Starts the stopwatch if it is stopped, stops it if it is running.
    ///
    /// - Parameter date: The instant the gesture happened, normally `Date()`.
    public func toggle(at date: Date = Date()) {
        if let startedAt {
            accumulated = max(0, accumulated + date.timeIntervalSince(startedAt))
            self.startedAt = nil
        } else {
            startedAt = date
        }
    }

    /// Returns the stopwatch to a stopped reading of zero.
    ///
    /// Both halves of the derived elapsed value are cleared: the accumulated total of
    /// the earlier runs and the timestamp the current run began at. A reset therefore
    /// reads `00:00:00` immediately and keeps reading it however much wall-clock time
    /// passes while the screen is paged away or the app is suspended.
    ///
    /// Resetting a running stopwatch **stops** it rather than restarting it from zero.
    /// The gesture is the only way back to zero, so it has to be able to reach a
    /// stopped zero; restarting instead would leave the reading climbing away from the
    /// value the user just asked for, and a restart is still one further double tap
    /// away.
    public func reset() {
        startedAt = nil
        accumulated = 0
    }
}
