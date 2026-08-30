import Foundation
import Testing

@testable import Pulse

/// Verification of `UptimeResponseDecoder` against authored sample payloads.
///
/// The real response shape of `GET /api/uptime/listall` has never been observed — the
/// endpoint answers `401` without a key — so these payloads are invented rather than
/// recorded. They cover every shape the decoder claims to accept, which is what makes
/// the tolerance auditable: when the real schema is confirmed, the cases that no longer
/// apply can be deleted with the tolerance they describe.
///
/// Nothing here touches the network and no key is involved.
struct UptimeResponseDecoderTests {

    // MARK: - Shapes

    @Test("A top-level array decodes in order, with unrecognised states unknown")
    func topLevelArray() throws {
        let json = """
        [{"name":"API-GATEWAY","status":"up"},
         {"name":"REDIS-CACHE","status":"degraded"},
         {"name":"K3S-CLUSTER","status":"down"},
         {"name":"BACKUP-JOB","status":"wat"}]
        """

        let services = try UptimeResponseDecoder.decode(Data(json.utf8))

        #expect(services.map(\.name) == ["API-GATEWAY", "REDIS-CACHE", "K3S-CLUSTER", "BACKUP-JOB"])
        #expect(services.map(\.status) == [.operational, .degraded, .down, .unknown])
    }

    @Test("Alternative name and status keys are read, in any case or separator style")
    func alternativeKeySpellings() throws {
        let json = """
        {"data":[{"service_name":"WEB-FRONTEND","currentStatus":"Operational"},
                 {"friendly_name":"POSTGRES-01","state":"Partial Outage"}]}
        """

        let services = try UptimeResponseDecoder.decode(Data(json.utf8))

        #expect(services.map(\.name) == ["WEB-FRONTEND", "POSTGRES-01"])
        #expect(services.map(\.status) == [.operational, .degraded])
    }

    @Test("Every accepted wrapper key yields the list", arguments: UptimeResponseDecoder.envelopeKeys)
    func envelopeKeys(key: String) throws {
        let json = #"{"\#(key)":[{"name":"X","health":"healthy"}]}"#

        let services = try UptimeResponseDecoder.decode(Data(json.utf8))

        #expect(services == [UptimeService(name: "X", status: .operational)])
    }

    @Test("A wrapper nested one level deeper still yields the list")
    func nestedEnvelope() throws {
        let json = #"{"data":{"services":[{"name":"NESTED","status":"ok"}]}}"#

        let services = try UptimeResponseDecoder.decode(Data(json.utf8))

        #expect(services == [UptimeService(name: "NESTED", status: .operational)])
    }

    @Test("An empty list is valid and decodes to no rows")
    func emptyList() throws {
        #expect(try UptimeResponseDecoder.decode(Data(#"{"data":[]}"#.utf8)).isEmpty)
    }

    // MARK: - Tolerance

    @Test("Names are trimmed, bare strings are names, and nameless entries are dropped")
    func entryTolerance() throws {
        let json = """
        [{"name":"NO-STATUS"},
         {"status":"up"},
         "BARE-STRING",
         {"name":"  PADDED  ","status":"  UP  "}]
        """

        let services = try UptimeResponseDecoder.decode(Data(json.utf8))

        #expect(services.map(\.name) == ["NO-STATUS", "BARE-STRING", "PADDED"])
        #expect(services.map(\.status) == [.unknown, .unknown, .operational])
    }

    @Test("Boolean states are read; numeric ones are not guessed at")
    func booleanAndNumericStates() throws {
        let json = """
        {"services":[{"title":"WORKER-QUEUE","up":true},
                     {"label":"MAIL-RELAY","online":false},
                     {"name":"CDN-EDGE","status":1},
                     {"name":"OBJECT-STORE","status":0}]}
        """

        let services = try UptimeResponseDecoder.decode(Data(json.utf8))

        #expect(services.map(\.name) == ["WORKER-QUEUE", "MAIL-RELAY", "CDN-EDGE", "OBJECT-STORE"])
        // 1 and 0 stay unknown on purpose: numeric status codes are not standardised
        // across uptime products, so reading them would risk a confidently wrong square.
        #expect(services.map(\.status) == [.operational, .down, .unknown, .unknown])
    }

    @Test(
        "State tokens map through the vocabulary regardless of case or separator",
        arguments: [
            ("operational", UptimeStatus.operational),
            ("Degraded-Performance", .degraded),
            ("MAJOR OUTAGE", .down),
            ("MAINTENANCE", .unknown),
            ("something new", .unknown)
        ]
    )
    func vocabulary(token: String, expected: UptimeStatus) {
        #expect(UptimeResponseDecoder.status(for: token) == expected)
    }

    @Test("A missing state is unknown")
    func missingState() {
        #expect(UptimeResponseDecoder.status(for: nil) == .unknown)
    }

    // MARK: - Rejection

    @Test(
        "A body that is not a list of services is rejected",
        arguments: [
            #"{"error":"Unauthorized","code":"UNAUTHORIZED"}"#,
            "not json at all",
            "42"
        ]
    )
    func unusableBodies(body: String) {
        #expect(throws: (any Error).self) {
            try UptimeResponseDecoder.decode(Data(body.utf8))
        }
    }

    @Test("A list whose entries yield no rows is an error, not an empty screen")
    func unreadableEntriesAreRejected() {
        // Names keyed as `host` — outside `nameKeys` — would otherwise decode to an
        // empty list and blank the display with no signal at all.
        let json = #"{"services":[{"host":"api.example.com","status":"up"}]}"#

        #expect(throws: (any Error).self) {
            try UptimeResponseDecoder.decode(Data(json.utf8))
        }
    }
}
