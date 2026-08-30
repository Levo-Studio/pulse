import XCTest

/// Exercises the stopwatch screen's tap gestures against the running app.
///
/// Whether a triple tap resets without also toggling is a property of how real
/// touches arrive at a real gesture recogniser, not of any value type, so it cannot be
/// settled in a unit test. These drive the app instead.
///
/// The readout redraws four times a second, and every accessibility query has to
/// snapshot a tree that is changing underneath it. Queries are therefore kept to the
/// assertions: taps go to the window rather than to a freshly resolved element, and
/// each test starts from a terminated app so nothing carries over from the last one.
///
/// Even so, XCTest's snapshotting still stalls against this screen often enough that
/// the suite cannot be trusted to gate a merge. It therefore lives in its own shared
/// scheme rather than in `Pulse`, so the project's build-and-test command stays
/// deterministic. Run it deliberately whenever the gestures change:
///
/// ```sh
/// xcodebuild test -project Pulse.xcodeproj -scheme PulseUITests \
///   -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
/// ```
///
/// A stall shows up as `Lost connection to the application`; every later assertion in
/// the same run then reads a stale snapshot and fails misleadingly. Re-run before
/// concluding that anything is actually broken.
final class StopwatchGestureUITests: XCTestCase {

    /// The readout's resting value.
    private static let zero = "00:00:00"

    /// How long to leave a resolved gesture to take effect before reading the readout
    /// back. Longer than the screen's tap window and its redraw cadence together.
    private static let settleAfterGesture: TimeInterval = 0.8

    /// How long to wait before concluding that a reading is stable rather than merely
    /// between ticks. Longer than one second of stopwatch resolution, so a stopwatch
    /// that is still running cannot go unnoticed.
    private static let settleInterval: TimeInterval = 2.2

    private var app: XCUIApplication?

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    /// Launches the app and pages across to the stopwatch.
    private func launchOnStopwatch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        self.app = app
        // The pager opens on the clock; the stopwatch is one page to the right.
        app.swipeLeft()
        XCTAssertTrue(readout(in: app).waitForExistence(timeout: 10))
        return app
    }

    /// The elapsed readout, picked out by its `HH:MM:SS` shape. The only other text on
    /// the screen is the five-character time of day.
    private func readout(in app: XCUIApplication) -> XCUIElement {
        let shape = NSPredicate(format: "label MATCHES %@", "[0-9]{2}:[0-9]{2}:[0-9]{2}")
        return app.staticTexts.matching(shape).firstMatch
    }

    /// The readout's current value.
    private func reading(in app: XCUIApplication) -> String {
        readout(in: app).label
    }

    /// Taps the middle of the screen, where the gesture area is, without resolving the
    /// readout first. Resolving it would snapshot the whole changing tree on every
    /// tap, which is slow enough to push the taps outside the screen's tap window.
    private func tap(_ app: XCUIApplication, times: Int) {
        app.windows.firstMatch.tap(withNumberOfTaps: times, numberOfTouches: 1)
    }

    func testSingleTapDoesNothing() {
        let app = launchOnStopwatch()

        tap(app, times: 1)
        Thread.sleep(forTimeInterval: Self.settleInterval)

        XCTAssertEqual(reading(in: app), Self.zero, "A single tap must not start the stopwatch")
    }

    func testDoubleTapStartsAndStops() {
        let app = launchOnStopwatch()

        tap(app, times: 2)
        Thread.sleep(forTimeInterval: Self.settleInterval)
        XCTAssertNotEqual(reading(in: app), Self.zero, "A double tap must start the stopwatch")

        tap(app, times: 2)
        Thread.sleep(forTimeInterval: Self.settleAfterGesture)
        let atStop = reading(in: app)
        Thread.sleep(forTimeInterval: Self.settleInterval)

        XCTAssertEqual(reading(in: app), atStop, "A second double tap must stop the stopwatch")
    }

    func testTripleTapResetsWithoutLeavingItRunning() {
        let app = launchOnStopwatch()

        tap(app, times: 2)
        Thread.sleep(forTimeInterval: Self.settleInterval)
        XCTAssertNotEqual(reading(in: app), Self.zero)

        tap(app, times: 3)
        Thread.sleep(forTimeInterval: Self.settleAfterGesture)
        XCTAssertEqual(reading(in: app), Self.zero, "A triple tap must reset the readout")

        // The reset has to leave the stopwatch stopped, not restart it from zero: if it
        // were still running the reading would have climbed away by now.
        Thread.sleep(forTimeInterval: Self.settleInterval)
        XCTAssertEqual(reading(in: app), Self.zero, "A triple tap must not leave the stopwatch running")
    }

    func testTripleTapOnAStoppedStopwatchDoesNotToggleIt() {
        let app = launchOnStopwatch()

        // The risk the tap window exists to remove: a two-tap recogniser claiming the
        // gesture and starting the stopwatch behind the reset.
        tap(app, times: 3)
        Thread.sleep(forTimeInterval: Self.settleInterval)

        XCTAssertEqual(reading(in: app), Self.zero, "A triple tap must not toggle the stopwatch")
    }

    func testDoubleTapStillWorksAfterAReset() {
        let app = launchOnStopwatch()

        tap(app, times: 2)
        Thread.sleep(forTimeInterval: Self.settleInterval)
        tap(app, times: 3)
        Thread.sleep(forTimeInterval: Self.settleAfterGesture)
        XCTAssertEqual(reading(in: app), Self.zero)

        tap(app, times: 2)
        Thread.sleep(forTimeInterval: Self.settleInterval)

        XCTAssertNotEqual(reading(in: app), Self.zero, "The stopwatch must start again after a reset")
    }

    func testResetSurvivesPagingAwayAndBack() {
        let app = launchOnStopwatch()

        tap(app, times: 2)
        Thread.sleep(forTimeInterval: Self.settleInterval)
        tap(app, times: 3)
        Thread.sleep(forTimeInterval: Self.settleAfterGesture)

        app.swipeRight()
        Thread.sleep(forTimeInterval: Self.settleInterval)
        app.swipeLeft()

        XCTAssertTrue(readout(in: app).waitForExistence(timeout: 10))
        XCTAssertEqual(reading(in: app), Self.zero, "A reset must survive paging away and back")
    }
}
