import Foundation
import Testing

@testable import Pulse

/// Pins the behaviour of the stopwatch's reset.
///
/// Elapsed time is derived from a start timestamp plus the accumulated intervals of
/// the earlier runs, never from a timer tick. A reset that cleared only one of those
/// two halves would look correct on screen for a moment and then drift as wall-clock
/// time passed, so the assertions here always re-read the value at a later instant as
/// well as at the instant of the reset.
struct StopwatchStateTests {

    /// A fixed instant to run the arithmetic against, so nothing depends on `Date()`.
    private let origin = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test("Resetting a stopped stopwatch clears the accumulated runs")
    func resetFromStopped() {
        let stopwatch = StopwatchState()
        stopwatch.toggle(at: origin)
        stopwatch.toggle(at: origin.addingTimeInterval(42))
        #expect(stopwatch.elapsed(at: origin.addingTimeInterval(42)) == 42)

        stopwatch.reset()

        #expect(stopwatch.isRunning == false)
        #expect(stopwatch.elapsed(at: origin.addingTimeInterval(42)) == 0)
    }

    @Test("Resetting a running stopwatch stops it at zero")
    func resetFromRunning() {
        let stopwatch = StopwatchState()
        stopwatch.toggle(at: origin)
        #expect(stopwatch.isRunning)

        stopwatch.reset()

        // A reset never leaves the stopwatch running: the reading has to stay at zero
        // rather than climb away from the value the gesture just asked for.
        #expect(stopwatch.isRunning == false)
        #expect(stopwatch.elapsed(at: origin.addingTimeInterval(10)) == 0)
    }

    @Test("Resetting mid-run drops the accumulated total as well as the current run")
    func resetDropsBothHalves() {
        let stopwatch = StopwatchState()
        stopwatch.toggle(at: origin)
        stopwatch.toggle(at: origin.addingTimeInterval(30))
        stopwatch.toggle(at: origin.addingTimeInterval(60))

        stopwatch.reset()

        #expect(stopwatch.elapsed(at: origin.addingTimeInterval(90)) == 0)
    }

    @Test("Starting again after a reset counts from zero")
    func startAfterReset() {
        let stopwatch = StopwatchState()
        stopwatch.toggle(at: origin)
        stopwatch.toggle(at: origin.addingTimeInterval(120))
        stopwatch.reset()

        stopwatch.toggle(at: origin.addingTimeInterval(200))

        #expect(stopwatch.isRunning)
        #expect(stopwatch.elapsed(at: origin.addingTimeInterval(205)) == 5)
    }

    @Test("A reset value survives a long gap with nothing redrawing")
    func resetSurvivesSuspension() {
        let stopwatch = StopwatchState()
        stopwatch.toggle(at: origin)
        stopwatch.reset()

        // Stands in for the screen being paged away or the app suspended: no tick
        // runs, and the value is read again an hour of wall-clock time later.
        #expect(stopwatch.elapsed(at: origin.addingTimeInterval(3600)) == 0)
        #expect(stopwatch.isRunning == false)
    }

    @Test("A run started after a reset survives the same gap")
    func runAfterResetSurvivesSuspension() {
        let stopwatch = StopwatchState()
        stopwatch.toggle(at: origin)
        stopwatch.toggle(at: origin.addingTimeInterval(15))
        stopwatch.reset()
        stopwatch.toggle(at: origin.addingTimeInterval(20))

        #expect(stopwatch.elapsed(at: origin.addingTimeInterval(3620)) == 3600)
    }

    @Test("Resetting twice is the same as resetting once")
    func resetIsIdempotent() {
        let stopwatch = StopwatchState()
        stopwatch.toggle(at: origin)
        stopwatch.reset()
        stopwatch.reset()

        #expect(stopwatch.isRunning == false)
        #expect(stopwatch.elapsed(at: origin.addingTimeInterval(5)) == 0)
    }
}
