import XCTest

/// Drives the pager against the running app: all five screens must be reachable by
/// swiping left, and the same five by swiping back.
///
/// This cannot be settled in a unit test. Whether a page is actually reachable is a
/// property of `TabView` and of real drags arriving at a real gesture recogniser, not
/// of any value type, so it is checked here.
///
/// Two things make these cases trustworthy rather than merely green.
///
/// The anchors are tolerant of what is stored on the device. The GitHub and uptime
/// screens show their credential prompt when nothing is stored and their display when
/// something is, and Keychain items survive a reinstall, so each screen is identified
/// by either face rather than by the one a fresh device happens to show. Both faces
/// are addressed by exact label: a predicate scan filters the whole accessibility tree
/// on every read, which on these screens is slow enough to time a wait out by itself.
///
/// A screen counts as showing when its anchor **exists**, which is a sound signal
/// here rather than a lazy one: `TabView` builds the page it scrolls to and tears down
/// the one it leaves, so once a transition has settled only the current screen's
/// elements are in the tree. Measured on this pager, with uptime displayed,
/// `app.staticTexts["SETTINGS"]` did not exist after ten seconds of polling.
///
/// What that does **not** cover is a transition still in flight, where both pages are
/// briefly in the tree. That is what the settle before each read is for, and it is why
/// the drag cannot be allowed to overshoot: existence alone would report a skipped
/// page as an arrival.
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
    private static let arrival: TimeInterval = 8

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
    /// `swipeLeft()` starts in the centre, which on a credential prompt is the field or
    /// the keyboard below it — both swallow the drag, so the pager never sees it. Every
    /// screen's top band is inert, so a drag there reaches the pager whatever state the
    /// screen underneath is in. It is kept clear of both screen edges as well, where
    /// the system's own edge-pan gestures claim the touch first.
    ///
    /// The gesture is deliberately unhurried, and holds at the end rather than
    /// releasing mid-flight. A fast flick carries the pager **two** pages often enough
    /// to make a run meaningless, and a skipped page is a failure this suite cannot
    /// tell from a missing screen. A slow drag never overshoots; it occasionally does
    /// not take at all, which `page(_:toward:until:)` retries.
    private func flick(_ app: XCUIApplication, toward direction: CGFloat, from origin: XCUIElement? = nil) {
        // The band the drag crosses: the inert strip below the top of the screen by
        // default, or the vertical middle of a given element when the point of the case
        // is that a touch landing on that element still only pages.
        let band = origin.map { $0.frame.midY / app.frame.height } ?? 0.12
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5 - direction * 0.3, dy: band))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5 + direction * 0.3, dy: band))
        start.press(
            forDuration: 0.01,
            thenDragTo: end,
            withVelocity: XCUIGestureVelocity(400),
            thenHoldForDuration: 0.15
        )
    }

    /// Flicks toward the next page and waits for `arrived`, retrying the flick twice.
    ///
    /// A slow drag occasionally lands as a scroll the pager ignores, which is a
    /// property of the gesture recogniser rather than of the pager's order. Retrying
    /// separates "the swipe did not take" from "that screen is not there", which is
    /// what these cases are about — and it is safe only because the drag cannot
    /// overshoot: a retry after a swipe that did move would page past the screen under
    /// test.
    private func page(
        _ app: XCUIApplication,
        toward direction: CGFloat,
        from origin: XCUIElement? = nil,
        until arrived: () -> Bool
    ) -> Bool {
        for _ in 0..<3 {
            // The previous page's animation is given a moment to settle first: a flick
            // issued into a running transition is dropped, and the retry then reads as
            // a screen that is not there.
            Thread.sleep(forTimeInterval: 0.6)
            flick(app, toward: direction, from: origin)
            // The page transition is left to finish before the tree is read at all: a
            // query issued into a running transition returns a snapshot of a page that
            // is still moving, which is neither the screen being left nor the one
            // arriving.
            Thread.sleep(forTimeInterval: 1.5)
            if waitUntil(Self.arrival, arrived) { return true }
        }
        return false
    }

    /// One page to the right in the swipe order.
    private func pageForward(
        _ app: XCUIApplication,
        from origin: XCUIElement? = nil,
        until arrived: () -> Bool
    ) -> Bool {
        page(app, toward: -1, from: origin, until: arrived)
    }

    /// One page to the left in the swipe order.
    private func pageBack(
        _ app: XCUIApplication,
        from origin: XCUIElement? = nil,
        until arrived: () -> Bool
    ) -> Bool {
        page(app, toward: 1, from: origin, until: arrived)
    }

    /// Polls `condition` until it holds or the deadline passes.
    ///
    /// Deliberately unhurried. Every read snapshots the accessibility tree, which on a
    /// screen with a keyboard up is expensive enough that polling tightly slows the
    /// app it is measuring.
    private func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        return false
    }

    // MARK: - Screen anchors

    /// Whether an element is on the page currently in view.
    ///
    /// Existence is the signal, and it is a sound one here: `TabView` builds the page
    /// it scrolls to and tears the one it leaves down, so only the current screen's
    /// elements are in the tree once a transition has settled. Reading a frame as well
    /// would be a second expensive query per poll for a distinction the pager does not
    /// leave open.
    private func isOnScreen(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        element.exists
    }

    private func anyOnScreen(_ app: XCUIApplication, _ elements: XCUIElement...) -> Bool {
        elements.contains { $0.exists }
    }

    /// The clock: a `HH:mm` or `HH:mm:ss` readout, whichever the preference says.
    ///
    /// Queried as a button, which is what the readout is: it carries the double-tap
    /// action that reveals seconds, and an element with an action is not a static text.
    private func clockIsShowing(_ app: XCUIApplication) -> Bool {
        isOnScreen(clockReadout(in: app, pattern: "^[0-9]{2}:[0-9]{2}(:[0-9]{2})?$"), in: app)
    }

    private func clockReadout(in app: XCUIApplication, pattern: String) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "label MATCHES %@", pattern))
            .firstMatch
    }

    /// The stopwatch, by the identifier its readout carries.
    private func stopwatchIsShowing(_ app: XCUIApplication) -> Bool {
        isOnScreen(app.staticTexts["stopwatch.readout"], in: app)
    }

    /// GitHub: the `CHANGE USERNAME` control on the display, the `USERNAME` heading on
    /// the prompt.
    private func gitHubIsShowing(_ app: XCUIApplication) -> Bool {
        anyOnScreen(app, app.buttons["CHANGE USERNAME"], app.staticTexts["USERNAME"])
    }

    /// Uptime: the `CHANGE API KEY` control on the display, the `API KEY` heading on
    /// the prompt.
    private func uptimeIsShowing(_ app: XCUIApplication) -> Bool {
        anyOnScreen(app, app.buttons["CHANGE API KEY"], app.staticTexts["API KEY"])
    }

    /// Settings, by its heading. Its own rows are buttons rather than static texts, so
    /// they cannot be mistaken for the two screens before it.
    private func settingsIsShowing(_ app: XCUIApplication) -> Bool {
        isOnScreen(app.staticTexts["SETTINGS"], in: app)
    }

    // MARK: - Cases

    func testAllFiveScreensAreReachableBySwiping() {
        let app = launch()

        XCTAssertTrue(
            waitUntil(Self.arrival) { clockIsShowing(app) },
            "The app must open on the clock"
        )

        XCTAssertTrue(
            pageForward(app) { stopwatchIsShowing(app) },
            "The stopwatch must be one page right of the clock"
        )
        XCTAssertTrue(
            pageForward(app) { gitHubIsShowing(app) },
            "GitHub must be one page right of the stopwatch"
        )
        XCTAssertTrue(
            pageForward(app) { uptimeIsShowing(app) },
            "Uptime must be one page right of GitHub"
        )
        XCTAssertTrue(
            pageForward(app) { settingsIsShowing(app) },
            "Settings must be the fifth and last page"
        )

        XCTAssertTrue(
            pageBack(app) { uptimeIsShowing(app) },
            "Uptime must be one page left of settings"
        )
        XCTAssertTrue(
            pageBack(app) { gitHubIsShowing(app) },
            "GitHub must be one page left of uptime"
        )
        XCTAssertTrue(
            pageBack(app) { stopwatchIsShowing(app) },
            "The stopwatch must be one page left of GitHub"
        )
        XCTAssertTrue(
            pageBack(app) { clockIsShowing(app) },
            "The clock must be one page left of the stopwatch"
        )
    }

    /// Swiping across settings must not change anything: the rows are buttons, and a
    /// button does not fire while a drag is in flight.
    ///
    /// The drag deliberately **starts on a row**, not in the inert band at the top. A
    /// swipe over the header proves only that the header is safe; the risk this case
    /// exists for is a finger that lands on `SECONDS` on its way past, so that is where
    /// the touch goes down. A row rebuilt as a tap gesture rather than a button would
    /// fail here and pass a header swipe.
    func testPagingThroughSettingsChangesNothing() throws {
        let app = launch()
        pageToSettings(app)

        let seconds = app.buttons["SECONDS"]
        XCTAssertTrue(seconds.waitForExistence(timeout: Self.arrival))

        // Unwrapped rather than compared as an optional: two `nil`s are equal, so an
        // accessibility value that stopped being published would make the comparison
        // below pass without measuring anything.
        let before = try XCTUnwrap(seconds.value as? String, "The row must publish its state")

        XCTAssertTrue(pageBack(app, from: seconds) { uptimeIsShowing(app) })
        XCTAssertTrue(pageForward(app) { settingsIsShowing(app) })

        XCTAssertEqual(
            try XCTUnwrap(seconds.value as? String),
            before,
            "A swipe that starts on a row must not toggle it"
        )
    }

    /// The settings toggle and the clock's own double tap write the same preference
    /// object, so a change made here is on the clock without a relaunch.
    ///
    /// The starting state is **imposed, not read**. Launching with
    /// `-clock.showsSeconds NO` puts the value in `UserDefaults`' argument domain,
    /// which outranks anything written to the device, so the run starts on the minute
    /// readout whatever the last run left behind and whatever the person using this
    /// simulator prefers. Nothing has to be restored afterwards, which matters because
    /// `continueAfterFailure` is false: a restoring tap at the end of a case is exactly
    /// the cleanup an earlier failure skips.
    func testTogglingSecondsInSettingsShowsOnTheClock() {
        let app = XCUIApplication()
        app.launchArguments += ["-clock.showsSeconds", "NO"]
        app.launch()
        self.app = app

        let withoutSeconds = clockReadout(in: app, pattern: "^[0-9]{2}:[0-9]{2}$")
        let withSeconds = clockReadout(in: app, pattern: "^[0-9]{2}:[0-9]{2}:[0-9]{2}$")

        XCTAssertTrue(
            waitUntil(Self.arrival) { withoutSeconds.exists },
            "The launch argument must decide the starting state"
        )
        XCTAssertFalse(withSeconds.exists)

        pageToSettings(app)

        let seconds = app.buttons["SECONDS"]
        XCTAssertTrue(seconds.waitForExistence(timeout: Self.arrival))
        XCTAssertEqual(seconds.value as? String, "OFF", "The row must agree with the clock")
        seconds.tap()
        XCTAssertEqual(seconds.value as? String, "ON")
        Thread.sleep(forTimeInterval: 1)

        pageToClock(app)

        XCTAssertTrue(
            waitUntil(Self.arrival) { withSeconds.exists },
            "The clock must follow the preference toggled in settings"
        )

        // Back off again, and asserted on the way rather than tapped and hoped for.
        // Turning it off is worth a case of its own — a toggle that only ever gets
        // tested in one direction is half tested — and it happens to leave the device's
        // stored preference as this run found it.
        pageToSettings(app)
        XCTAssertEqual(seconds.value as? String, "ON")
        seconds.tap()
        XCTAssertEqual(seconds.value as? String, "OFF")
        Thread.sleep(forTimeInterval: 1)

        pageToClock(app)

        XCTAssertTrue(
            waitUntil(Self.arrival) { withoutSeconds.exists },
            "The clock must follow the preference in both directions"
        )
    }

    /// Arriving on settings from a credential prompt must leave the whole screen
    /// usable.
    ///
    /// This is the default path for a new user: no key is stored, the uptime screen
    /// prompts for one and takes focus, and the next swipe lands on settings. The
    /// keyboard that prompt raised belongs to the window, so it used to stay up —
    /// undrawn, but still claiming its inset — and take the bottom 378 points of a
    /// 874 point display with it. The last row and the hint under it were simply not
    /// there, on a screen with no scroll indicator to suggest otherwise.
    ///
    /// The case therefore checks two things that were both false before: no keyboard
    /// is up, and the **last** row is inside the frame without scrolling.
    func testSettingsIsWholeAfterACredentialPrompt() {
        let app = launch()
        pageToSettings(app)

        XCTAssertTrue(
            waitUntil(Self.arrival) { app.keyboards.count == 0 },
            "A keyboard raised by a prompt must not survive the swipe to settings"
        )

        let lastRow = app.buttons["WEATHER CONDITION"]
        XCTAssertTrue(lastRow.waitForExistence(timeout: Self.arrival))
        XCTAssertTrue(
            app.frame.contains(lastRow.frame),
            """
            The last settings row must be drawn in full without scrolling. \
            Row: \(lastRow.frame), screen: \(app.frame)
            """
        )

        let hint = app.staticTexts["TAP A ROW TO CHANGE IT"]
        XCTAssertTrue(hint.exists)
        XCTAssertTrue(app.frame.contains(hint.frame), "The hint under the rows must be drawn too")
    }

    /// Pages from the clock to settings, one screen at a time, so a swipe that does not
    /// take is retried rather than silently leaving the run on the wrong page.
    private func pageToSettings(_ app: XCUIApplication) {
        XCTAssertTrue(pageForward(app) { stopwatchIsShowing(app) })
        XCTAssertTrue(pageForward(app) { gitHubIsShowing(app) })
        XCTAssertTrue(pageForward(app) { uptimeIsShowing(app) })
        XCTAssertTrue(pageForward(app) { settingsIsShowing(app) })
    }

    /// The same journey back.
    private func pageToClock(_ app: XCUIApplication) {
        XCTAssertTrue(pageBack(app) { uptimeIsShowing(app) })
        XCTAssertTrue(pageBack(app) { gitHubIsShowing(app) })
        XCTAssertTrue(pageBack(app) { stopwatchIsShowing(app) })
        XCTAssertTrue(pageBack(app) { clockIsShowing(app) })
    }
}
