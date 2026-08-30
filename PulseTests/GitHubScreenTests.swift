import Foundation
import SwiftUI
import Testing

@testable import Pulse

/// The lines the GitHub screen draws below the heatmap, and how they behave when the
/// events feed stops answering.
///
/// Every request is served by a stub, so nothing here touches the network or spends a
/// request against the hourly quota. The Keychain item is written under a service
/// identifier unique to the test and removed afterwards, so the user's own stored
/// username is never read or altered.
///
/// Serialized: the stub carries its canned responses in static state, which concurrent
/// cases would overwrite for each other.
@Suite(.serialized)
@MainActor
struct GitHubActivityModelTests {

    /// A placeholder account name. Never sent anywhere: the stub answers without
    /// looking at the request.
    private static let storedPlaceholder = "example-account"

    private func makeStore() -> KeychainStore {
        let store = KeychainStore(service: "levo-studio.PulseTests.\(UUID().uuidString)")
        #expect(store.set(Self.storedPlaceholder, for: .gitHubUsername))
        return store
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GitHubStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeModel(store: KeychainStore) -> GitHubActivityModel {
        let session = makeSession()
        let model = GitHubActivityModel(
            store: store,
            client: GitHubContributionsClient(session: session),
            eventsClient: GitHubEventsClient(session: session)
        )
        model.restoreUsername()
        return model
    }

    private func feed(pushedAt: String, opened: Int, merged: Int, on day: String) -> String {
        var entries = [
            #"{"type":"PushEvent","created_at":"\#(pushedAt)","payload":{"ref":"refs/heads/main"}}"#
        ]
        for index in 0..<opened {
            entries.append(
                #"{"type":"PullRequestEvent","created_at":"\#(day)T08:0\#(index):00Z","payload":{"action":"opened","number":\#(index)}}"#
            )
        }
        for index in 0..<merged {
            entries.append(
                #"{"type":"PullRequestEvent","created_at":"\#(day)T09:0\#(index):00Z","payload":{"action":"merged","number":\#(index)}}"#
            )
        }
        return "[\(entries.joined(separator: ","))]"
    }

    private func date(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    // MARK: - Lines

    @Test("A push in the window restores the reference's LAST COMMIT AT line")
    func lastCommitLine() async throws {
        let store = makeStore()
        defer { store.remove(.gitHubUsername) }

        GitHubStubURLProtocol.reset()
        GitHubStubURLProtocol.eventsBody = Data(
            feed(pushedAt: "2026-08-30T09:23:30Z", opened: 0, merged: 0, on: "2026-08-30").utf8
        )

        let model = makeModel(store: store)
        let now = try date("2026-08-30T09:40:00Z")
        await model.refresh(now: now)

        let expected = Self.localMinutes(of: try date("2026-08-30T09:23:30Z"))
        #expect(model.lastCommitLine == "LAST COMMIT AT: \(expected)")
    }

    @Test("With no push in the window the line is absent, not a placeholder")
    func noPushInWindow() async throws {
        let store = makeStore()
        defer { store.remove(.gitHubUsername) }

        GitHubStubURLProtocol.reset()
        GitHubStubURLProtocol.eventsBody = Data("[]".utf8)

        let model = makeModel(store: store)
        await model.refresh(now: try date("2026-08-30T09:40:00Z"))

        #expect(model.activity != nil)
        #expect(model.lastCommitLine == nil)
        // A quiet day shows no pull request line either: a zero would claim something
        // the public feed cannot support.
        #expect(model.pullRequestLine == nil)
    }

    @Test("Pull request wording follows what actually happened today")
    func pullRequestWording() async throws {
        let store = makeStore()
        defer { store.remove(.gitHubUsername) }

        let now = try date("2026-08-30T12:00:00Z")
        let cases: [(Int, Int, String)] = [
            (2, 0, "PUBLIC PR OPENED: 2"),
            (0, 3, "PUBLIC PR MERGED: 3"),
            (2, 1, "PUBLIC PR: 2 OPENED 1 MERGED")
        ]

        for (opened, merged, expected) in cases {
            GitHubStubURLProtocol.reset()
            GitHubStubURLProtocol.eventsBody = Data(
                feed(pushedAt: "2026-08-30T09:23:30Z", opened: opened, merged: merged, on: "2026-08-30").utf8
            )

            let model = makeModel(store: store)
            await model.refresh(now: now)

            #expect(model.pullRequestLine == expected)
        }
    }

    @Test("Double-digit counts still read correctly and still fit the line")
    func doubleDigitCounts() async throws {
        let store = makeStore()
        defer { store.remove(.gitHubUsername) }

        GitHubStubURLProtocol.reset()
        GitHubStubURLProtocol.eventsBody = Data(
            feed(pushedAt: "2026-08-30T09:23:30Z", opened: 12, merged: 10, on: "2026-08-30").utf8
        )

        let model = makeModel(store: store)
        await model.refresh(now: try date("2026-08-30T12:00:00Z"))

        // Thirty characters, against a worst-case character budget of 28 — which is why
        // the line is checked by measuring it rather than by counting it. Digits are
        // 0.75 em and spaces 0.625, nowhere near the 0.875 the budget assumes.
        let line = try #require(model.pullRequestLine)
        #expect(line == "PUBLIC PR: 12 OPENED 10 MERGED")
        #expect(line.count == 30)
        #expect(GitHubLabelMeasurement.width(of: line, size: 10, tracking: 2)
            <= GitHubHeaderRow.contentWidth)
    }

    @Test("A push from an earlier day never reaches the line", arguments: [true, false])
    func stalePushIsNotRendered(hasPullRequests: Bool) async throws {
        let store = makeStore()
        defer { store.remove(.gitHubUsername) }

        GitHubStubURLProtocol.reset()
        GitHubStubURLProtocol.eventsBody = Data(
            feed(
                pushedAt: "2026-08-29T18:42:00Z",
                opened: hasPullRequests ? 1 : 0,
                merged: 0,
                on: "2026-08-30"
            ).utf8
        )

        let model = makeModel(store: store)
        await model.refresh(now: try date("2026-08-30T09:40:00Z"))

        // Yesterday's push, on a screen that says COMMITS TODAY and carries no date.
        #expect(model.activity?.lastPushAt == nil)
        #expect(model.lastCommitLine == nil)
        // The rest of the block is unaffected: one source of silence is not another's.
        #expect((model.pullRequestLine != nil) == hasPullRequests)
        #expect(model.lastCheckLine != nil)
    }

    @Test("The freshness line reports the older source, never the newer one")
    func freshnessLineTakesTheOlderSource() async throws {
        let store = makeStore()
        defer { store.remove(.gitHubUsername) }

        GitHubStubURLProtocol.reset()
        GitHubStubURLProtocol.eventsBody = Data("[]".utf8)
        // The contributions page fails, so only the events fetch stamps a time.
        GitHubStubURLProtocol.contributionsStatus = 500

        let model = makeModel(store: store)
        let now = try date("2026-08-30T09:40:00Z")
        await model.refresh(now: now)

        #expect(model.contributions.isEmpty)
        #expect(model.lastCheckLine == "LAST CHECK: \(Self.localSeconds(of: now))")
    }

    // MARK: - Rate limiting

    @Test("An exhausted quota keeps the last good data and stops asking until it resets")
    func rateLimitedPathDegradesAndBacksOff() async throws {
        let store = makeStore()
        defer { store.remove(.gitHubUsername) }

        GitHubStubURLProtocol.reset()
        GitHubStubURLProtocol.eventsBody = Data(
            feed(pushedAt: "2026-08-30T09:23:30Z", opened: 1, merged: 0, on: "2026-08-30").utf8
        )

        let model = makeModel(store: store)
        let now = try date("2026-08-30T09:40:00Z")
        await model.refresh(now: now)

        let good = try #require(model.activity)
        #expect(GitHubStubURLProtocol.eventsRequestCount == 1)

        // The quota runs out, as it can at any time: it is 60 an hour for the whole
        // address, not for this app.
        let resetAt = now.addingTimeInterval(900)
        GitHubStubURLProtocol.eventsStatus = 403
        GitHubStubURLProtocol.eventsHeaders = [
            "x-ratelimit-remaining": "0",
            "x-ratelimit-reset": String(Int(resetAt.timeIntervalSince1970))
        ]
        GitHubStubURLProtocol.eventsBody = Data(#"{"message":"API rate limit exceeded"}"#.utf8)

        await model.refresh(now: now.addingTimeInterval(600))

        #expect(model.eventsFailure == .rateLimited(resetAt: resetAt))
        // The screen keeps showing what it last knew rather than blanking.
        #expect(model.activity == good)
        #expect(GitHubStubURLProtocol.eventsRequestCount == 2)

        // Polls inside the closed window spend no request at all.
        await model.refresh(now: now.addingTimeInterval(700))
        await model.refresh(now: now.addingTimeInterval(800))
        #expect(GitHubStubURLProtocol.eventsRequestCount == 2)
        #expect(model.activity == good)

        // Once the quota is back, so is the feed.
        GitHubStubURLProtocol.eventsStatus = 200
        GitHubStubURLProtocol.eventsHeaders = [:]
        GitHubStubURLProtocol.eventsBody = Data(
            feed(pushedAt: "2026-08-30T09:50:00Z", opened: 0, merged: 2, on: "2026-08-30").utf8
        )

        await model.refresh(now: resetAt.addingTimeInterval(1))

        #expect(GitHubStubURLProtocol.eventsRequestCount == 3)
        #expect(model.eventsFailure == nil)
        #expect(model.pullRequestLine == "PUBLIC PR MERGED: 2")
    }

    @Test("A failing events feed leaves the heatmap's own status line alone")
    func eventsFailureIsNotAScreenFailure() async throws {
        let store = makeStore()
        defer { store.remove(.gitHubUsername) }

        GitHubStubURLProtocol.reset()
        GitHubStubURLProtocol.eventsStatus = 403

        let model = makeModel(store: store)
        await model.refresh(now: try date("2026-08-30T09:40:00Z"))

        #expect(model.eventsFailure == .rateLimited(resetAt: nil))
        #expect(model.lastCommitLine == nil)
        #expect(model.pullRequestLine == nil)
        // The contributions fetch is what the status line speaks for, and it is
        // untouched by the events feed failing.
        #expect(model.lastFailure == .unparsableMarkup)
    }

    // MARK: - Helpers

    private static func localMinutes(of date: Date) -> String {
        format(date, as: "HH:mm")
    }

    private static func localSeconds(of date: Date) -> String {
        format(date, as: "HH:mm:ss")
    }

    /// Formats in the device's own zone, which is exactly what the screen does: the
    /// expectation has to move with the machine running the suite.
    private static func format(_ date: Date, as pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

/// The header row: its readout, its tick gate and the width arithmetic that keeps a
/// long username off the seconds field.
@MainActor
struct GitHubHeaderRowTests {

    @Test("The readout is HH:mm:ss in the device's own zone")
    func secondsReadout() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-08-30T09:23:04Z"))

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"

        let readout = GitHubHeaderRow.timeReadout(for: date)
        #expect(readout == formatter.string(from: date))
        #expect(readout.count == 8)
        #expect(readout.filter { $0 == ":" }.count == 2)
    }

    @Test("The ticker runs only while the readout is being looked at")
    func tickGate() {
        #expect(
            GitHubHeaderRow.shouldTick(
                activeScreen: .gitHub, scenePhase: .active,
                hasUsername: true, isEditingUsername: false
            )
        )
        // Paged away.
        #expect(
            !GitHubHeaderRow.shouldTick(
                activeScreen: .clock, scenePhase: .active,
                hasUsername: true, isEditingUsername: false
            )
        )
        // Backgrounded, or in the app switcher, with the page still mounted.
        for phase in [ScenePhase.background, .inactive] {
            #expect(
                !GitHubHeaderRow.shouldTick(
                    activeScreen: .gitHub, scenePhase: phase,
                    hasUsername: true, isEditingUsername: false
                )
            )
        }
        // The prompt replaces the header, so there is nothing to tick.
        #expect(
            !GitHubHeaderRow.shouldTick(
                activeScreen: .gitHub, scenePhase: .active,
                hasUsername: true, isEditingUsername: true
            )
        )
        #expect(
            !GitHubHeaderRow.shouldTick(
                activeScreen: .gitHub, scenePhase: .active,
                hasUsername: false, isEditingUsername: false
            )
        )
    }

    @Test("A ticker only ticks between start and stop")
    func tickerLifecycle() {
        let ticker = SecondTicker(now: .distantPast)
        #expect(!ticker.isRunning)

        ticker.start()
        #expect(ticker.isRunning)
        // `start` refreshes, so a screen returning to view never shows a stale second.
        #expect(ticker.now.timeIntervalSinceNow > -1)

        ticker.stop()
        #expect(!ticker.isRunning)
    }

    @Test("The row's width accounting matches what it spends")
    func widthAccounting() {
        #expect(GitHubHeaderRow.contentWidth == 308)
        #expect(GitHubHeaderRow.characterWidth == (10 * 0.875) + 2)
        // Eight characters of HH:mm:ss, three more than the reference's HH:mm.
        #expect(GitHubHeaderRow.timeWidth == 8 * GitHubHeaderRow.characterWidth)
        #expect(GitHubHeaderRow.characterBudget == 18)
    }

    @Test("The gap the row reserves is the gap the layout actually spends")
    func gapWidthIsMeasured() {
        // The quantity, not the constant: a stack laid out exactly like the header row,
        // with the two labels replaced by blocks of a known width. Asserting the
        // constant against itself is how a missing gap survives a test suite.
        let block = CGFloat(10)
        let row = HStack(alignment: .firstTextBaseline, spacing: 8) {
            Color.clear.frame(width: block, height: block)
            Spacer(minLength: 8)
            Color.clear.frame(width: block, height: block)
        }

        let controller = UIHostingController(rootView: row)
        let ideal = controller.sizeThatFits(in: CGSize(width: .max, height: .max))

        // The spacer is a subview, so the stack's spacing lands on both sides of it and
        // the spacer's own minimum is additive: three gaps, not two.
        #expect(ideal.width - (2 * block) == GitHubHeaderRow.gapWidth)
        #expect(GitHubHeaderRow.gapWidth == 24)
    }

    @Test("A budget-length name plus the time and the gaps fits, one more does not")
    func budgetIsTight() {
        let widest = CGFloat(GitHubHeaderRow.characterBudget) * GitHubHeaderRow.characterWidth
            + GitHubHeaderRow.gapWidth
            + GitHubHeaderRow.timeWidth
        #expect(widest <= GitHubHeaderRow.contentWidth)

        let overlong = CGFloat(GitHubHeaderRow.characterBudget + 1) * GitHubHeaderRow.characterWidth
            + GitHubHeaderRow.gapWidth
            + GitHubHeaderRow.timeWidth
        #expect(overlong > GitHubHeaderRow.contentWidth)

        // And the same again as measured quantities rather than as the budget's own
        // assumptions, so the row is checked against what it draws: a budget-length
        // name of the widest glyph in the face, beside a real readout.
        let name = GitHubLabelMeasurement.width(
            of: String(repeating: "M", count: GitHubHeaderRow.characterBudget),
            size: 10,
            tracking: 2
        )
        let readout = GitHubLabelMeasurement.width(of: "23:59:59", size: 10, tracking: 2)
        #expect(name + readout + GitHubHeaderRow.gapWidth <= GitHubHeaderRow.contentWidth)
    }

    @Test("Every line the footer can draw fits the content width when measured")
    func footerLinesFitWhenMeasured() {
        let lines = [
            "LAST COMMIT AT: 23:59",
            "PUBLIC PR OPENED: 12",
            "PUBLIC PR MERGED: 12",
            "PUBLIC PR: 12 OPENED 10 MERGED",
            "NO SUCH USER - TAP TO CHANGE",
            "OFFLINE - SHOWING LAST DATA",
            "NO COUNT FOR TODAY"
        ]

        for line in lines {
            let width = GitHubLabelMeasurement.width(of: line, size: 10, tracking: 2)
            #expect(width <= GitHubHeaderRow.contentWidth, "\(line) is \(width) units wide")
        }

        // The freshness line is a size smaller than the rest of the block.
        #expect(
            GitHubLabelMeasurement.width(of: "LAST CHECK: 23:59:59", size: 9, tracking: 2)
                <= GitHubHeaderRow.contentWidth
        )
    }

    @Test("The longest username GitHub allows is shortened rather than left to overrun")
    func truncation() {
        let short = String(repeating: "M", count: GitHubHeaderRow.characterBudget)
        #expect(GitHubHeaderRow.displayName(for: short) == short)

        // 39 characters is GitHub's maximum.
        let longest = String(repeating: "W", count: 39)
        let shortened = GitHubHeaderRow.displayName(for: longest)
        #expect(shortened.count == GitHubHeaderRow.characterBudget)
        #expect(shortened.hasSuffix(GitHubHeaderRow.truncationMarker))
    }
}

/// Measures a line of display type as the screen actually draws it.
///
/// The header budget reserves the widest advance Silkscreen has for every character,
/// which is right for a username of unknown composition and far too pessimistic for a
/// line of known words and digits. Where the copy is fixed, measuring it is both tighter
/// and closer to the truth.
@MainActor
enum GitHubLabelMeasurement {

    /// Rendered width of `text`, in design-reference units.
    static func width(of text: String, size: CGFloat, tracking: CGFloat) -> CGFloat {
        PixelFont.register()

        let label = PixelLabel(text, size: size, tracking: tracking, color: PixelTheme.primary)
            .environment(
                \.pixelMetrics,
                PixelMetrics(
                    size: CGSize(
                        width: PixelMetrics.referenceWidth,
                        height: PixelMetrics.referenceHeight
                    )
                )
            )

        let controller = UIHostingController(rootView: label)
        return controller.sizeThatFits(in: CGSize(width: .max, height: .max)).width
    }
}

/// Serves canned GitHub responses, routed by host, so both sources can be exercised
/// independently without a network.
final class GitHubStubURLProtocol: URLProtocol, @unchecked Sendable {

    /// Status the events endpoint answers with.
    nonisolated(unsafe) static var eventsStatus = 200

    /// Body the events endpoint answers with.
    nonisolated(unsafe) static var eventsBody = Data("[]".utf8)

    /// Extra headers on the events response, for the rate limit fields.
    nonisolated(unsafe) static var eventsHeaders: [String: String] = [:]

    /// How many events requests have been made, so a back-off can be proved.
    nonisolated(unsafe) static var eventsRequestCount = 0

    /// Status the contributions page answers with.
    nonisolated(unsafe) static var contributionsStatus = 200

    /// Body the contributions page answers with. The default parses to nothing, which
    /// the client reports as unparsable markup.
    nonisolated(unsafe) static var contributionsBody = Data("<html></html>".utf8)

    /// Returns every field to its default.
    static func reset() {
        eventsStatus = 200
        eventsBody = Data("[]".utf8)
        eventsHeaders = [:]
        eventsRequestCount = 0
        contributionsStatus = 200
        contributionsBody = Data("<html></html>".utf8)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let isEvents = url.host() == "api.github.com"
        if isEvents { Self.eventsRequestCount += 1 }

        var headers = ["Content-Type": isEvents ? "application/json" : "text/html"]
        if isEvents { headers.merge(Self.eventsHeaders) { _, new in new } }

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: isEvents ? Self.eventsStatus : Self.contributionsStatus,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: isEvents ? Self.eventsBody : Self.contributionsBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
