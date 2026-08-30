import Foundation

/// What a run of taps on the stopwatch screen turned out to mean.
public enum StopwatchTapOutcome: Equatable, Sendable {

    /// The sequence was too short to mean anything. A single tap is deliberately
    /// inert, so that a stray touch cannot start or stop a run.
    case ignore

    /// Start or stop the stopwatch, as of the instant the last tap of the sequence
    /// arrived. The instant is carried rather than left to the caller because the
    /// decision is reached after a wait, and the reading must not inherit that wait.
    case toggle(at: Date)

    /// Return the stopwatch to a stopped zero.
    case reset
}

/// Accumulates taps on the stopwatch screen and decides what they mean.
///
/// The screen counts taps itself rather than composing two tap gestures, because
/// neither arrangement of a pair works. Stacking `onTapGesture(count: 3)` and
/// `onTapGesture(count: 2)` lets the two-tap recogniser succeed the instant the second
/// tap lands, so a triple tap starts the stopwatch and the third tap arrives as an
/// unrelated single tap. `TapGesture(count: 3).exclusively(before: TapGesture(count: 2))`
/// fails the opposite way: the two-tap gesture does wait for the three-tap one, but
/// `TapGesture` has no failure timeout, so after two taps the longer gesture never
/// fails and the double tap never fires at all.
///
/// Counting is the only arrangement that waits for a bounded time and then commits.
/// The caller owns that timer: it calls `register(at:)` for each tap, acts at once on
/// any outcome that comes back, and otherwise calls `close()` once its window has
/// passed with no further tap.
public struct StopwatchTapSequence: Equatable, Sendable {

    /// Number of taps that starts and stops the stopwatch.
    public static let toggleTapCount = 2

    /// Number of taps that resets the stopwatch to zero.
    public static let resetTapCount = 3

    /// Taps seen so far in the current sequence.
    public private(set) var count = 0

    /// When the most recent tap arrived, or `nil` if no sequence is open.
    public private(set) var lastTap: Date?

    /// Creates an empty sequence.
    public init() {}

    /// Whether a sequence is currently open and waiting to be closed.
    public var isOpen: Bool { count > 0 }

    /// Adds a tap to the sequence.
    ///
    /// - Parameter date: The instant the tap arrived.
    /// - Returns: An outcome if the sequence is already decided and the caller should
    ///   act now, or `nil` if it must wait out its window and then call `close()`.
    ///   Only the reset decides early: three taps is the longest sequence the screen
    ///   recognises, so there is nothing left to wait for.
    public mutating func register(at date: Date) -> StopwatchTapOutcome? {
        count += 1
        lastTap = date

        guard count >= Self.resetTapCount else { return nil }

        reset()
        return .reset
    }

    /// Ends the sequence and reports what it meant, leaving it empty.
    ///
    /// - Returns: The outcome of the taps gathered so far.
    public mutating func close() -> StopwatchTapOutcome {
        defer { reset() }

        guard count == Self.toggleTapCount, let lastTap else { return .ignore }
        return .toggle(at: lastTap)
    }

    /// Empties the sequence.
    private mutating func reset() {
        count = 0
        lastTap = nil
    }
}
