import Foundation
import Testing

@testable import Pulse

/// Verification that revealing seconds moves the ticker onto the second boundary
/// and hiding them puts it back on the minute boundary.
///
/// The scheduled fire date is inspected rather than the tick being waited for: the
/// point of the granularity is which boundary the next wake-up lands on, and a
/// test that waited for it would take a minute to prove the minute case.
@MainActor
struct ClockTickerGranularityTests {

    @Test("A stopped ticker has nothing scheduled")
    func stoppedTickerHasNoTick() {
        let ticker = ClockTicker()

        #expect(ticker.isRunning == false)
        #expect(ticker.nextTick == nil)
    }

    @Test("The default cadence is the wall-clock minute")
    func defaultCadenceIsMinute() throws {
        let ticker = ClockTicker()
        ticker.start()
        defer { ticker.stop() }

        #expect(ticker.granularity == .minute)

        let fire = try #require(ticker.nextTick)
        // The next minute boundary is at most a minute away and never in the past.
        let delay = fire.timeIntervalSinceNow
        #expect(delay > 0)
        #expect(delay <= 60)
        #expect(isOnBoundary(fire, period: 60))
    }

    @Test("Revealing seconds moves the next tick onto the second boundary")
    func secondsCadence() throws {
        let ticker = ClockTicker()
        ticker.start()
        defer { ticker.stop() }

        ticker.granularity = .second

        let fire = try #require(ticker.nextTick)
        let delay = fire.timeIntervalSinceNow
        #expect(delay > 0)
        #expect(delay <= 1)
        #expect(isOnBoundary(fire, period: 1))
    }

    @Test("Hiding seconds again puts the ticker back on the minute boundary")
    func backToMinuteCadence() throws {
        let ticker = ClockTicker()
        ticker.start()
        defer { ticker.stop() }

        ticker.granularity = .second
        ticker.granularity = .minute

        #expect(ticker.granularity == .minute)

        let fire = try #require(ticker.nextTick)
        #expect(fire.timeIntervalSinceNow > 1)
        #expect(isOnBoundary(fire, period: 60))
    }

    @Test("Changing the granularity while stopped schedules nothing")
    func stoppedTickerStaysStopped() {
        let ticker = ClockTicker()

        ticker.granularity = .second

        #expect(ticker.isRunning == false)
        #expect(ticker.nextTick == nil)
    }

    @Test("The two granularities carry their own period and tolerance")
    func granularityValues() {
        #expect(ClockGranularity.minute.period == 60)
        #expect(ClockGranularity.second.period == 1)
        // A second readout cannot afford the minute readout's coalescing slack.
        #expect(ClockGranularity.second.tolerance < ClockGranularity.minute.tolerance)
        #expect(ClockGranularity.second.tolerance < ClockGranularity.second.period)
    }

    @Test("Both forms of the time come from the same instant")
    func readingFormsAgree() {
        let reading = ClockReading(instant: Date(timeIntervalSince1970: 1_756_547_580))

        #expect(reading.timeWithSeconds.hasPrefix(reading.time))
        #expect(reading.time.count == 5)
        #expect(reading.timeWithSeconds.count == 8)
    }

    /// Whether `date` sits on a whole multiple of `period` seconds, within the
    /// floating-point slack of a `TimeInterval`.
    private func isOnBoundary(_ date: Date, period: TimeInterval) -> Bool {
        let remainder = date.timeIntervalSince1970.truncatingRemainder(dividingBy: period)
        return remainder < 0.001 || period - remainder < 0.001
    }
}

/// Verification that the two clock display preferences survive a relaunch, and
/// that they are stored where a display preference belongs.
@MainActor
struct ClockPreferencesTests {

    /// A throwaway defaults suite, so nothing here touches the user's own.
    private func makeDefaults() throws -> UserDefaults {
        let suite = "pulse.tests.\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: suite))
    }

    @Test("Before anything is stored, the shipped defaults apply")
    func shippedDefaults() throws {
        let preferences = ClockPreferences(defaults: try makeDefaults())

        // The reference draws `14:32`, so the minute readout is what ships.
        #expect(preferences.showsSeconds == false)
        // The indicator is visible without the user having to find the gesture.
        #expect(preferences.showsCondition == true)
    }

    @Test("Both preferences survive being reloaded from the same store")
    func bothPreferencesPersist() throws {
        let defaults = try makeDefaults()

        let first = ClockPreferences(defaults: defaults)
        first.showsSeconds = true
        first.showsCondition = false

        let reloaded = ClockPreferences(defaults: defaults)

        #expect(reloaded.showsSeconds == true)
        #expect(reloaded.showsCondition == false)
    }

    @Test("A preference set back to its default is remembered as set, not as absent")
    func falseIsDistinctFromUnset() throws {
        let defaults = try makeDefaults()

        let first = ClockPreferences(defaults: defaults)
        // `showsCondition` defaults to `true`, so storing `false` is the case a
        // naive `bool(forKey:)` read would silently undo on the next launch.
        first.showsCondition = false

        #expect(ClockPreferences(defaults: defaults).showsCondition == false)
    }

    @Test("The preferences are keyed under the screen that owns them")
    func keysAreNamespaced() {
        for key in ClockPreferences.Key.allCases {
            #expect(key.rawValue.hasPrefix("clock."))
        }
    }
}

/// Verification of the measurement that decides the size of the time readout.
///
/// These numbers are the reason the seconds variant does not use the reference's
/// size 70, so they are pinned rather than left in a comment.
struct ClockTimeMetricsTests {

    @Test("The reference's own readout fits the content width at size 70")
    func minuteReadoutFits() {
        let width = ClockTimeMetrics.width(digits: 4, colons: 1, size: ClockTimeMetrics.size)

        #expect(width == 237.5)
        #expect(width < ClockTimeMetrics.contentWidth)
    }

    @Test("The seconds readout does not fit at size 70, which is why it is smaller")
    func secondsReadoutDoesNotFitAtReferenceSize() {
        let width = ClockTimeMetrics.width(digits: 6, colons: 2, size: ClockTimeMetrics.size)

        #expect(width == 366)
        #expect(width > ClockTimeMetrics.contentWidth)
    }

    @Test("The seconds readout fits at the size it actually uses")
    func secondsReadoutFits() {
        let width = ClockTimeMetrics.width(digits: 6, colons: 2, size: ClockTimeMetrics.secondsSize)

        #expect(width == 296)
        #expect(width < ClockTimeMetrics.contentWidth)
    }

    @Test("The chosen size keeps real margin rather than only just fitting")
    func chosenSizeKeepsMargin() {
        let width = ClockTimeMetrics.width(digits: 6, colons: 2, size: ClockTimeMetrics.secondsSize)

        // Size 58 also fits, at 306 against 308, but two units is inside the slack
        // of a hand-derived advance table. The size in use leaves twelve.
        #expect(ClockTimeMetrics.contentWidth - width >= 10)
        // Anything larger than the next step up overruns outright.
        #expect(ClockTimeMetrics.width(digits: 6, colons: 2, size: 60) > ClockTimeMetrics.contentWidth)
    }
}
