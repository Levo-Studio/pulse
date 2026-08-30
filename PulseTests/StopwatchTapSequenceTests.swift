import Foundation
import Testing

@testable import Pulse

/// Pins what a run of taps on the stopwatch screen means, and when it is deemed to
/// have happened.
///
/// The instant matters as much as the outcome. A double tap is only recognised once
/// the screen has waited long enough to rule out a third tap, so if the toggle were
/// recorded at the end of that wait every start and every stop would be stored a third
/// of a second late — not as display latency, but baked into the timestamp the whole
/// reading derives from. The sequence therefore carries the tap's own instant, and
/// these assertions are what stop that being quietly dropped again.
struct StopwatchTapSequenceTests {

    /// A fixed instant to run the arithmetic against, so nothing depends on `Date()`.
    private let origin = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test("A single tap means nothing")
    func singleTapIsIgnored() {
        var sequence = StopwatchTapSequence()

        #expect(sequence.register(at: origin) == nil)
        #expect(sequence.close() == .ignore)
    }

    @Test("Two taps mean toggle, dated to the second tap and not to the close")
    func doubleTapCarriesTheTapInstant() {
        var sequence = StopwatchTapSequence()
        let secondTap = origin.addingTimeInterval(0.09)

        #expect(sequence.register(at: origin) == nil)
        #expect(sequence.register(at: secondTap) == nil)

        // Closed a window later, as the screen does. The outcome must still be dated
        // to the tap, not to this moment.
        #expect(sequence.close() == .toggle(at: secondTap))
    }

    @Test("A third tap decides at once, without waiting out a window")
    func tripleTapDecidesEarly() {
        var sequence = StopwatchTapSequence()

        #expect(sequence.register(at: origin) == nil)
        #expect(sequence.register(at: origin.addingTimeInterval(0.05)) == nil)
        #expect(sequence.register(at: origin.addingTimeInterval(0.12)) == .reset)
    }

    @Test("A decided reset leaves nothing behind to close")
    func resetClearsTheSequence() {
        var sequence = StopwatchTapSequence()
        _ = sequence.register(at: origin)
        _ = sequence.register(at: origin.addingTimeInterval(0.05))
        _ = sequence.register(at: origin.addingTimeInterval(0.12))

        #expect(sequence.isOpen == false)
        // A stray fourth tap must not be read as the tail of the reset.
        #expect(sequence.close() == .ignore)
    }

    @Test("Closing a sequence empties it")
    func closeEmptiesTheSequence() {
        var sequence = StopwatchTapSequence()
        _ = sequence.register(at: origin)
        _ = sequence.register(at: origin.addingTimeInterval(0.09))
        #expect(sequence.isOpen)

        _ = sequence.close()

        #expect(sequence.isOpen == false)
        #expect(sequence.close() == .ignore)
    }

    @Test("A sequence flushed early still toggles, at the instant it was tapped")
    func flushedSequenceKeepsItsInstant() {
        var sequence = StopwatchTapSequence()
        let secondTap = origin.addingTimeInterval(0.07)
        _ = sequence.register(at: origin)
        _ = sequence.register(at: secondTap)

        // Stands in for the page going away mid-window: the screen closes the
        // sequence rather than discarding it, so a completed double tap is not lost.
        #expect(sequence.close() == .toggle(at: secondTap))
    }

    @Test("A toggle applied late still reads exactly")
    func lateToggleReadsExactly() {
        let stopwatch = StopwatchState()
        let tap = origin

        // The screen learns of the tap a tap window later, but applies it against the
        // instant the tap arrived, so the delay never enters the reading.
        stopwatch.toggle(at: tap)

        #expect(stopwatch.elapsed(at: tap.addingTimeInterval(10)) == 10)

        let stoppingTap = tap.addingTimeInterval(25)
        stopwatch.toggle(at: stoppingTap)

        #expect(stopwatch.elapsed(at: tap.addingTimeInterval(600)) == 25)
    }
}
