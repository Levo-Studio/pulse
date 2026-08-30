import Foundation
import Testing

@testable import Pulse

/// Verification of the public events decoder against the shape the endpoint actually
/// returns.
///
/// The payloads below were authored from a live response to
/// `GET https://api.github.com/users/{username}/events/public?per_page=100`, checked
/// while building this. Account names, repository names and identifiers are replaced
/// with neutral ones: the shape is what is being pinned, and no real account belongs in
/// the repository. Nothing here touches the network.
struct GitHubEventsDecoderTests {

    /// The trimmed feed shape, as observed: `PullRequestEvent` reports `"merged"` as an
    /// action in its own right, and its embedded pull request is a stub with no
    /// `merged` flag to read.
    private static let observedFeed = """
    [
      {"id":"1","type":"PullRequestEvent",
       "actor":{"id":1,"login":"octocat"},
       "repo":{"id":2,"name":"example-org/example-repo"},
       "payload":{"action":"opened","number":6,
                  "pull_request":{"id":3,"number":6,"url":"https://api.github.com/x",
                                  "head":{"ref":"feat/example"},"base":{"ref":"main"}}},
       "public":true,"created_at":"2026-08-30T09:30:18Z"},
      {"id":"2","type":"PullRequestEvent",
       "actor":{"id":1,"login":"octocat"},
       "repo":{"id":2,"name":"example-org/example-repo"},
       "payload":{"action":"merged","number":5,
                  "pull_request":{"id":4,"number":5,"url":"https://api.github.com/y",
                                  "head":{"ref":"fix/example"},"base":{"ref":"main"}}},
       "public":true,"created_at":"2026-08-30T09:14:02Z"},
      {"id":"3","type":"PushEvent",
       "actor":{"id":1,"login":"octocat"},
       "repo":{"id":2,"name":"example-org/example-repo"},
       "payload":{"repository_id":2,"push_id":9,"ref":"refs/heads/main",
                  "head":"0000000000000000000000000000000000000000",
                  "before":"1111111111111111111111111111111111111111"},
       "public":true,"created_at":"2026-08-30T09:23:30Z"},
      {"id":"4","type":"DeleteEvent",
       "actor":{"id":1,"login":"octocat"},
       "repo":{"id":2,"name":"example-org/example-repo"},
       "payload":{"ref":"feat/example","ref_type":"branch"},
       "public":true,"created_at":"2026-08-30T09:14:05Z"}
    ]
    """

    @Test("The observed feed decodes to the kinds and timestamps the screen reads")
    func observedShape() throws {
        let events = try GitHubEventsClient.decode(Data(Self.observedFeed.utf8))

        #expect(events.count == 4)
        #expect(events.map(\.kind) == [.pullRequestOpened, .pullRequestMerged, .push, .other])
        #expect(events[2].createdAt == Date(timeIntervalSince1970: 1_788_081_810))
    }

    @Test("The documented shape is understood too: closed plus a merged flag is a merge")
    func documentedMergeShape() throws {
        let json = """
        [{"type":"PullRequestEvent","created_at":"2026-08-30T09:14:02Z",
          "payload":{"action":"closed","number":5,"pull_request":{"merged":true}}}]
        """

        let events = try GitHubEventsClient.decode(Data(json.utf8))
        #expect(events.map(\.kind) == [.pullRequestMerged])
    }

    @Test("A pull request closed without merging is not counted as a merge")
    func closedWithoutMerge() throws {
        let json = """
        [{"type":"PullRequestEvent","created_at":"2026-08-30T09:14:02Z",
          "payload":{"action":"closed","number":5,"pull_request":{"merged":false}}},
         {"type":"PullRequestEvent","created_at":"2026-08-30T09:15:02Z",
          "payload":{"action":"reopened","number":5,"pull_request":{"id":1}}}]
        """

        let events = try GitHubEventsClient.decode(Data(json.utf8))
        // Reopening is not opening: it would inflate a count of what was opened today
        // with work started on another day.
        #expect(events.map(\.kind) == [.other, .other])
    }

    @Test("One unreadable entry costs that entry, not the page")
    func unreadableEntryIsSkipped() throws {
        let json = """
        [{"type":"PushEvent","created_at":"2026-08-30T09:23:30Z","payload":{}},
         {"type":"PushEvent","created_at":"not a date","payload":{}},
         "wat",
         {"type":"PushEvent","created_at":"2026-08-30T10:23:30Z","payload":{}}]
        """

        let events = try GitHubEventsClient.decode(Data(json.utf8))
        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.kind == .push })
    }

    @Test("A body that is not the event array is reported, not trapped on")
    func nonArrayBody() {
        let json = #"{"message":"API rate limit exceeded"}"#

        #expect(throws: GitHubEventsClient.Failure.undecodableResponse) {
            try GitHubEventsClient.decode(Data(json.utf8))
        }
    }
}

/// The day boundary, checked away from UTC.
///
/// "Today" on this screen is the user's own day, so a feed timestamp published in UTC
/// has to be bucketed in the device's time zone. These cases pin that: the same three
/// events fall on different days depending on where the device is.
struct GitHubActivitySummaryTests {

    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        // A named zone that exists in every copy of the time zone database; the
        // fallback keeps the test honest by failing on comparison rather than by
        // silently running in UTC.
        calendar.timeZone = TimeZone(identifier: identifier) ?? .gmt
        return calendar
    }

    private func date(_ iso: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        return try #require(formatter.date(from: iso))
    }

    @Test("Ahead of UTC, a late-evening UTC event already belongs to the next local day")
    func boundaryAheadOfUTC() throws {
        // Pacific/Kiritimati is UTC+14 with no daylight saving.
        let events = [
            GitHubEvent(kind: .pullRequestOpened, createdAt: try date("2026-08-30T09:30:00Z")),
            GitHubEvent(kind: .pullRequestMerged, createdAt: try date("2026-08-30T23:30:00Z"))
        ]
        let now = try date("2026-08-30T09:40:00Z")

        let summary = GitHubActivitySummary(
            events: events,
            now: now,
            calendar: calendar("Pacific/Kiritimati"),
            fetchedAt: now
        )

        // Locally it is already the 30th at 23:30 for the first event, while the second
        // has landed on the 31st.
        #expect(summary.pullRequestsOpenedToday == 1)
        #expect(summary.pullRequestsMergedToday == 0)
    }

    @Test("Behind UTC, an early-morning UTC event still belongs to the previous local day")
    func boundaryBehindUTC() throws {
        // Pacific/Midway is UTC-11 with no daylight saving.
        let events = [
            GitHubEvent(kind: .pullRequestOpened, createdAt: try date("2026-08-30T09:30:00Z")),
            GitHubEvent(kind: .pullRequestMerged, createdAt: try date("2026-08-30T23:30:00Z"))
        ]
        let now = try date("2026-08-30T23:40:00Z")

        let summary = GitHubActivitySummary(
            events: events,
            now: now,
            calendar: calendar("Pacific/Midway"),
            fetchedAt: now
        )

        // Locally "now" is the 30th at 12:40. The first event was the 29th at 22:30.
        #expect(summary.pullRequestsOpenedToday == 0)
        #expect(summary.pullRequestsMergedToday == 1)
    }

    @Test("The newest push wins, whatever order the page arrives in")
    func newestPush() throws {
        let older = try date("2026-08-30T07:00:00Z")
        let newer = try date("2026-08-30T09:23:30Z")
        let summary = GitHubActivitySummary(
            events: [
                GitHubEvent(kind: .push, createdAt: older),
                GitHubEvent(kind: .push, createdAt: newer),
                GitHubEvent(kind: .push, createdAt: older)
            ],
            now: newer,
            calendar: calendar("Europe/Berlin"),
            fetchedAt: newer
        )

        #expect(summary.lastPushAt == newer)
    }

    @Test("A window with no push has no push time, and pull requests alone do not invent one")
    func noPushInWindow() throws {
        let now = try date("2026-08-30T09:40:00Z")
        let summary = GitHubActivitySummary(
            events: [GitHubEvent(kind: .pullRequestOpened, createdAt: now)],
            now: now,
            calendar: calendar("Europe/Berlin"),
            fetchedAt: now
        )

        #expect(summary.lastPushAt == nil)
        #expect(summary.hasPullRequestActivityToday)
    }

    @Test("An empty window is quiet rather than zeroed")
    func emptyWindow() throws {
        let now = try date("2026-08-30T09:40:00Z")
        let summary = GitHubActivitySummary(events: [], now: now, fetchedAt: now)

        #expect(summary.lastPushAt == nil)
        #expect(!summary.hasPullRequestActivityToday)
    }
}
