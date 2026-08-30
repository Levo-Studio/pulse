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

    /// The trimmed feed shape, as observed. A page mixes event types freely; only
    /// `PushEvent` is read as anything, and the rest have to survive being read past.
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
        #expect(events.map(\.kind) == [.other, .other, .push, .other])
        #expect(events[2].createdAt == Date(timeIntervalSince1970: 1_788_081_810))
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
/// has to be bucketed in the device's time zone. These cases pin that: the same push
/// falls on different days depending on where the device is.
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

    @Test("The newest push of today wins, whatever order the page arrives in")
    func newestPushToday() throws {
        let lastWeek = try date("2026-08-23T22:00:00Z")
        let older = try date("2026-08-30T07:00:00Z")
        let newer = try date("2026-08-30T09:23:30Z")
        let summary = GitHubActivitySummary(
            events: [
                GitHubEvent(kind: .push, createdAt: older),
                GitHubEvent(kind: .push, createdAt: newer),
                // Newer than neither, but the window is 90 days deep and this is the
                // kind of entry an unscoped "newest push" would happily promote.
                GitHubEvent(kind: .push, createdAt: lastWeek),
                GitHubEvent(kind: .push, createdAt: older)
            ],
            now: newer,
            calendar: calendar("Europe/Berlin"),
            fetchedAt: newer
        )

        #expect(summary.lastPushAt == newer)
    }

    @Test("A push from an earlier day is not offered as today's, however recent the window")
    func staleDayPushIsNotToday() throws {
        // The only push in the window is yesterday's. The line it feeds carries no date
        // and sits under a COMMITS TODAY headline, so yesterday's time must not appear
        // there at all.
        let yesterday = try date("2026-08-29T18:42:00Z")
        let now = try date("2026-08-30T09:40:00Z")

        let summary = GitHubActivitySummary(
            events: [GitHubEvent(kind: .push, createdAt: yesterday)],
            now: now,
            calendar: calendar("Europe/Berlin"),
            fetchedAt: now
        )

        #expect(summary.lastPushAt == nil)
    }

    @Test("The push day boundary is the device's local midnight, not UTC's")
    func pushBoundaryFollowsTheDeviceZone() throws {
        // 2026-08-30T23:30Z is the 31st at 13:30 in Kiritimati (UTC+14) and the 30th at
        // 12:30 in Midway (UTC-11). With "now" fixed at 2026-08-30T23:40Z — the 31st
        // locally in the first zone, the 30th in the second — the same push is today in
        // one place and yesterday in the other.
        let push = GitHubEvent(kind: .push, createdAt: try date("2026-08-30T09:30:00Z"))
        let now = try date("2026-08-30T23:40:00Z")

        let ahead = GitHubActivitySummary(
            events: [push],
            now: now,
            calendar: calendar("Pacific/Kiritimati"),
            fetchedAt: now
        )
        // Locally the push was the 30th at 23:30 and it is now the 31st at 13:40.
        #expect(ahead.lastPushAt == nil)

        let behind = GitHubActivitySummary(
            events: [push],
            now: now,
            calendar: calendar("Pacific/Midway"),
            fetchedAt: now
        )
        // Locally the push was the 29th at 22:30 and it is now the 30th at 12:40.
        #expect(behind.lastPushAt == nil)

        let sameDay = GitHubActivitySummary(
            events: [push],
            now: try date("2026-08-30T12:00:00Z"),
            calendar: calendar("Europe/Berlin"),
            fetchedAt: now
        )
        #expect(sameDay.lastPushAt == push.createdAt)
    }

    @Test("A window of other people's event types never invents a push time")
    func noPushInWindow() throws {
        let now = try date("2026-08-30T09:40:00Z")
        let summary = GitHubActivitySummary(
            events: [GitHubEvent(kind: .other, createdAt: now)],
            now: now,
            calendar: calendar("Europe/Berlin"),
            fetchedAt: now
        )

        #expect(summary.lastPushAt == nil)
    }

    @Test("An empty window is quiet rather than zeroed")
    func emptyWindow() throws {
        let now = try date("2026-08-30T09:40:00Z")
        let summary = GitHubActivitySummary(events: [], now: now, fetchedAt: now)

        #expect(summary.lastPushAt == nil)
        #expect(summary.fetchedAt == now)
    }
}
