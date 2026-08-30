import XCTest

/// Drives the pager against the running app: all five screens must be reachable by
/// swiping left, and the same five by swiping back.
///
/// This cannot be settled in a unit test. Whether a page is actually reachable is a
/// property of `TabView` and of real drags arriving at a real gesture recogniser, not
/// of any value type, so it is checked here.
///
/// The anchors are deliberately tolerant of what is stored on the device. The GitHub
/// and uptime screens show their credential prompt when nothing is stored and their
/// display when something is, and Keychain items survive a reinstall, so each screen
/// is identified by a word that appears in both states rather than by a state that
/// only holds on a fresh device.
///
/// Like the stopwatch suite, this target keeps its own shared scheme. Run it
/// deliberately:
///
/// ```sh
/// xcodebuild test -project Pulse.xcodeproj -scheme PulseUITests \
///   -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
/// ```
final class PagingUITests: XCTestCase {

    /// How long a screen is given to arrive after a swipe.
    private static let arrival: TimeInterval = 10

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

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        self.app = app
        return app
    }

    // MARK: - Paging

    /// Drags across the top eighth of the screen rather than through its middle.
    ///
    /// `swipeLeft()` starts in the centre, which on a credential prompt is the field
    /// or the keyboard above it — both of which swallow the drag, so the pager never
    /// sees it. Every screen's top band is inert, so a drag there reaches the pager
    /// whatever state the screen underneath is in.
    private func page(_ app: XCUIApplication, toward direction: CGFloat) {
        // Kept clear of both screen edges, where the system's own edge-pan gestures
        // claim the touch before the pager sees it.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5 - direction * 0.3, dy: 0.12))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5 + direction * 0.3, dy: 0.12))
        // A flick, not a slow drag: `TabView` pages on velocity, and a drag issued
        // without one is absorbed as a scroll that ends where it started.
        start.press(forDuration: 0.01, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
    }

    /// One page to the right in the swipe order.
    private func pageForward(_ app: XCUIApplication) { page(app, toward: -1) }

    /// One page to the left in the swipe order.
    private func pageBack(_ app: XCUIApplication) { page(app, toward: 1) }

    // MARK: - Screen anchors

    /// The clock: a `HH:mm` or `HH:mm:ss` readout, whichever the preference says.
    ///
    /// Queried as a button, which is what the readout is: it carries the double-tap
    /// action that reveals seconds, and an element with an action is not a static text.
    private func clockIsShowing(_ app: XCUIApplication) -> Bool {
        clockReadout(in: app, pattern: "^[0-9]{2}:[0-9]{2}(:[0-9]{2})?$")
            .waitForExistence(timeout: Self.arrival)
    }

    private func clockReadout(in app: XCUIApplication, pattern: String) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "label MATCHES %@", pattern))
            .firstMatch
    }

    /// The stopwatch, by the identifier its readout carries.
    private func stopwatchIsShowing(_ app: XCUIApplication) -> Bool {
        app.staticTexts["stopwatch.readout"].waitForExistence(timeout: Self.arrival)
    }

    /// GitHub: `CHANGE USERNAME` on the display, `USERNAME` on the prompt.
    private func gitHubIsShowing(_ app: XCUIApplication) -> Bool {
        containsLabel(app, "USERNAME")
    }

    /// Uptime: `CHANGE API KEY` on the display, `API KEY` on the prompt.
    private func uptimeIsShowing(_ app: XCUIApplication) -> Bool {
        containsLabel(app, "API KEY")
    }

    /// Settings, by its title. Its own credential rows are buttons rather than static
    /// texts, so they cannot be mistaken for the two screens above.
    private func settingsIsShowing(_ app: XCUIApplication) -> Bool {
        app.staticTexts["SETTINGS"].waitForExistence(timeout: Self.arrival)
    }

    private func containsLabel(_ app: XCUIApplication, _ fragment: String) -> Bool {
        app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", fragment))
            .firstMatch
            .waitForExistence(timeout: Self.arrival)
    }

    // MARK: - Cases

    func testAllFiveScreensAreReachableBySwiping() {
        let app = launch()

        XCTAssertTrue(clockIsShowing(app), "The app must open on the clock")

        pageForward(app)
        XCTAssertTrue(stopwatchIsShowing(app), "The stopwatch must be one page right of the clock")

        pageForward(app)
        XCTAssertTrue(gitHubIsShowing(app), "GitHub must be one page right of the stopwatch")

        pageForward(app)
        XCTAssertTrue(uptimeIsShowing(app), "Uptime must be one page right of GitHub")

        pageForward(app)
        XCTAssertTrue(settingsIsShowing(app), "Settings must be the fifth and last page")

        // A sixth swipe has nowhere to go: settings is the end of the order.
        pageForward(app)
        XCTAssertTrue(settingsIsShowing(app), "Settings must stay put at the end of the order")

        pageBack(app)
        XCTAssertTrue(uptimeIsShowing(app), "Uptime must be one page left of settings")

        pageBack(app)
        XCTAssertTrue(gitHubIsShowing(app), "GitHub must be one page left of uptime")

        pageBack(app)
        XCTAssertTrue(stopwatchIsShowing(app), "The stopwatch must be one page left of GitHub")

        pageBack(app)
        XCTAssertTrue(clockIsShowing(app), "The clock must be one page left of the stopwatch")
    }

    /// Swiping across settings must not change anything: the rows are buttons, and a
    /// button does not fire while a drag is in flight.
    func testPagingThroughSettingsChangesNothing() {
        let app = launch()

        for _ in 0..<4 { pageForward(app) }
        XCTAssertTrue(settingsIsShowing(app))

        let seconds = app.buttons["SECONDS"]
        XCTAssertTrue(seconds.waitForExistence(timeout: Self.arrival))
        let before = seconds.value as? String

        pageBack(app)
        XCTAssertTrue(uptimeIsShowing(app))
        pageForward(app)
        XCTAssertTrue(settingsIsShowing(app))

        XCTAssertEqual(seconds.value as? String, before, "Swiping past a row must not toggle it")
    }

    /// The settings toggle and the clock's own double tap write the same preference
    /// object, so a change made here is on the clock without a relaunch.
    func testTogglingSecondsInSettingsShowsOnTheClock() {
        let app = launch()

        XCTAssertTrue(clockIsShowing(app))
        let withoutSeconds = clockReadout(in: app, pattern: "^[0-9]{2}:[0-9]{2}$")
        let withSeconds = clockReadout(in: app, pattern: "^[0-9]{2}:[0-9]{2}:[0-9]{2}$")
        let startedWithSeconds = withSeconds.exists

        for _ in 0..<4 { pageForward(app) }
        XCTAssertTrue(settingsIsShowing(app))

        let seconds = app.buttons["SECONDS"]
        XCTAssertTrue(seconds.waitForExistence(timeout: Self.arrival))
        seconds.tap()

        for _ in 0..<4 { pageBack(app) }

        let expected = startedWithSeconds ? withoutSeconds : withSeconds
        XCTAssertTrue(
            expected.waitForExistence(timeout: Self.arrival),
            "The clock must follow the preference toggled in settings"
        )

        // Left as it was found, so the run does not decide the next one's starting
        // state.
        for _ in 0..<4 { pageForward(app) }
        XCTAssertTrue(settingsIsShowing(app))
        seconds.tap()
    }
}
