import CoreText
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
@MainActor
struct ClockTimeMetricsTests {

    // MARK: - The advance table, against the actual font

    /// Advance of `character` in the bundled face, as a fraction of the em.
    ///
    /// The table in `ClockTimeMetrics` is only worth anything if it describes the
    /// font the app actually ships. Read here through Core Text so these checks
    /// fail if the table drifts, if the bundled face is replaced, or if
    /// registration silently falls back to a system font — none of which a test
    /// written against hardcoded numbers would notice.
    private func measuredAdvance(of character: Character) throws -> CGFloat {
        // The app registers the face at launch; doing it here too makes the test
        // independent of whether the host application has started yet.
        PixelFont.register()

        let em: CGFloat = 1000
        let font = try #require(CTFontCreateWithName("Silkscreen-Regular" as CFString, em, nil) as CTFont?)
        #expect(CTFontCopyPostScriptName(font) as String == "Silkscreen-Regular",
                "the bundled face is not registered; every advance below would be a system font's")

        var utf16 = Array(String(character).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        #expect(CTFontGetGlyphsForCharacters(font, &utf16, &glyphs, utf16.count))

        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyphs, &advance, 1)
        return advance.width / em
    }

    @Test("The wide digits advance what the table charges them")
    func digitAdvanceMatchesTheFont() throws {
        for digit in "023456789" {
            #expect(try measuredAdvance(of: digit) == ClockTimeMetrics.digitAdvance, "digit \(digit)")
        }
    }

    @Test("The digit 1 is the narrow one, which is what makes the table a bound")
    func oneIsNarrower() throws {
        #expect(try measuredAdvance(of: "1") == ClockTimeMetrics.oneAdvance)
        #expect(ClockTimeMetrics.oneAdvance < ClockTimeMetrics.digitAdvance)
    }

    @Test("The colon advances what the table charges it")
    func colonAdvanceMatchesTheFont() throws {
        #expect(try measuredAdvance(of: ":") == ClockTimeMetrics.colonAdvance)
    }

    @Test("A predicted width is never narrower than the font actually sets")
    func predictionIsAnUpperBound() throws {
        // `11:11` is the narrowest a four-digit readout gets, and the one the
        // bound has to stay above.
        let measured = try "11:11".reduce(CGFloat.zero) { total, character in
            total + (try measuredAdvance(of: character)) * ClockTimeMetrics.size
        } + CGFloat(5) * ClockTimeMetrics.tracking

        let predicted = ClockTimeMetrics.width(digits: 4, colons: 1, size: ClockTimeMetrics.size)

        #expect(predicted >= measured)
    }

    // MARK: - What fits

    @Test("The reference's own readout fits the content width at size 70")
    func minuteReadoutFits() {
        let width = ClockTimeMetrics.width(digits: 4, colons: 1, size: ClockTimeMetrics.size)

        #expect(width == 246.25)
        #expect(width < ClockTimeMetrics.contentWidth)
    }

    @Test("The seconds readout does not fit at size 70, which is why it is smaller")
    func secondsReadoutDoesNotFitAtReferenceSize() {
        let width = ClockTimeMetrics.width(digits: 6, colons: 2, size: ClockTimeMetrics.size)

        #expect(width == 383.5)
        #expect(width > ClockTimeMetrics.contentWidth)
        // The overrun is very nearly a quarter of the line, not a rounding matter.
        #expect(width - ClockTimeMetrics.contentWidth == 75.5)
    }

    @Test("The seconds readout fits at the size it actually uses")
    func secondsReadoutFits() {
        let width = ClockTimeMetrics.width(digits: 6, colons: 2, size: ClockTimeMetrics.secondsSize)

        #expect(width == 268)
        #expect(width < ClockTimeMetrics.contentWidth)
    }

    @Test("The seconds readout is set at the size the reference sets its own")
    func secondsSizeFollowsTheStopwatch() {
        // The reference draws the stopwatch's `00:00:00` at 48. The clock's
        // eight-character readout takes the same size rather than inventing one.
        #expect(ClockTimeMetrics.secondsSize == 48)
    }

    @Test("The chosen size keeps real margin rather than scraping the limit")
    func chosenSizeKeepsMargin() {
        let width = ClockTimeMetrics.width(digits: 6, colons: 2, size: ClockTimeMetrics.secondsSize)

        // Solving `5.25s + 16 <= 308` puts the ceiling at 55.6, so the low fifties
        // fit arithmetically while leaving almost nothing. This leaves 40 units.
        #expect(ClockTimeMetrics.contentWidth - width >= 40)
        #expect(ClockTimeMetrics.width(digits: 6, colons: 2, size: 56) > ClockTimeMetrics.contentWidth)
    }
}
