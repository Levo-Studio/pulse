import Foundation
import Testing

@testable import Pulse

/// Verification of `UptimeResponseDecoder` against the documented schema of
/// `GET /api/uptime/listall`.
///
/// The payloads here are built from the API documentation's own example, including it
/// verbatim, so a change to the endpoint's contract fails here rather than on the
/// screen. Nothing touches the network and no key is involved: the sample key metadata
/// is the documentation's placeholder, not a credential.
struct UptimeResponseDecoderTests {

    // MARK: - The documented payload

    /// The example response from the API documentation, reproduced field for field.
    private static let documentedPayload = """
    {
      "data": {
        "key": { "id": "uuid", "name": "Statuspage", "keyPrefix": "lsu_abcd1234" },
        "projects": [
          {
            "id": "notion-page-id",
            "name": "Levo Studio Analytics",
            "customer": "Julius Grimm",
            "domain": "analytics.levo-studio.com",
            "category": "apps-internal",
            "serverLocation": "DE",
            "hostingPrice": 42,
            "currentStatus": "up",
            "lastCheckedAt": "2026-06-13T12:00:00.000Z",
            "lastStatusChangeAt": "2026-06-13T11:30:00.000Z",
            "monitoringPausedAt": null,
            "consecutiveFailureCount": 0,
            "summary": {
              "totalChecks": 120, "successfulChecks": 118, "degradedChecks": 2,
              "downChecks": 0, "uptimePercent": 100, "avgResponseMs": 180,
              "medianResponseMs": 170, "p95ResponseMs": 260, "minResponseMs": 120,
              "maxResponseMs": 3200, "latestResponseMs": 175,
              "latestCheckedAt": "2026-06-13T12:00:00.000Z", "incidentCount": 0
            }
          }
        ]
      }
    }
    """

    @Test("The documented payload decodes to its one project, timestamp included")
    func documentedPayloadDecodes() throws {
        let services = try UptimeResponseDecoder.decode(Data(Self.documentedPayload.utf8))

        #expect(services.count == 1)
        #expect(services.first?.name == "Levo Studio Analytics")
        #expect(services.first?.status == .operational)
        // 2026-06-13T12:00:00.000Z.
        #expect(services.first?.lastCheckedAt == Date(timeIntervalSince1970: 1_781_352_000))
    }

    @Test("Fields the screen does not draw are ignored rather than rejected")
    func unusedFieldsAreIgnored() throws {
        // The documented payload above carries the customer, domain, hosting price and
        // the whole summary block. None is decoded, and none of it fails the parse.
        #expect(try UptimeResponseDecoder.decode(Data(Self.documentedPayload.utf8)).count == 1)
    }

    // MARK: - Status mapping

    @Test("Every documented status maps to its square, in the order the API sent them")
    func everyStatus() throws {
        let json = """
        {"data":{"key":{"id":"uuid","name":"Statuspage","keyPrefix":"lsu_abcd1234"},
         "projects":[
           {"id":"1","name":"API GATEWAY","currentStatus":"up","lastCheckedAt":"2026-06-13T12:00:00.000Z"},
           {"id":"2","name":"REDIS CACHE","currentStatus":"slow","lastCheckedAt":"2026-06-13T12:00:01.000Z"},
           {"id":"3","name":"POSTGRES 01","currentStatus":"degraded","lastCheckedAt":"2026-06-13T12:00:02.000Z"},
           {"id":"4","name":"K3S CLUSTER","currentStatus":"down","lastCheckedAt":"2026-06-13T12:00:03.000Z"},
           {"id":"5","name":"BACKUP JOB","currentStatus":"unknown","lastCheckedAt":null}]}}
        """

        let services = try UptimeResponseDecoder.decode(Data(json.utf8))

        #expect(services.map(\.name) == [
            "API GATEWAY", "REDIS CACHE", "POSTGRES 01", "K3S CLUSTER", "BACKUP JOB"
        ])
        // `slow` and `degraded` share the amber square: the reference draws four
        // colours against the API's five states.
        #expect(services.map(\.status) == [.operational, .degraded, .degraded, .down, .unknown])
        #expect(services.last?.lastCheckedAt == nil)
    }

    @Test(
        "A status outside the documented vocabulary is unknown, never a guessed state",
        arguments: [
            "maintenance", "paused", "UP-ISH", "ok", "true", "1", "", "operational"
        ]
    )
    func unrecognisedStatus(value: String) throws {
        let json = """
        {"data":{"projects":[{"id":"1","name":"MYSTERY","currentStatus":"\(value)"}]}}
        """

        let services = try UptimeResponseDecoder.decode(Data(json.utf8))

        #expect(services == [UptimeService(name: "MYSTERY", status: .unknown)])
    }

    @Test("A missing status is unknown, and casing alone does not blank a row")
    func missingAndMiscasedStatus() throws {
        let json = """
        {"data":{"projects":[{"id":"1","name":"NO STATUS"},
                             {"id":"2","name":"SHOUTED","currentStatus":"DOWN"}]}}
        """

        let services = try UptimeResponseDecoder.decode(Data(json.utf8))

        #expect(services.map(\.status) == [.unknown, .down])
    }

    // MARK: - Empty and malformed

    @Test("An empty projects array is valid and decodes to no rows")
    func emptyProjects() throws {
        let json = #"{"data":{"key":{"id":"uuid","name":"Statuspage"},"projects":[]}}"#

        #expect(try UptimeResponseDecoder.decode(Data(json.utf8)).isEmpty)
    }

    @Test("Absent key metadata still yields the project list")
    func keyMetadataIsOptional() throws {
        let json = #"{"data":{"projects":[{"id":"1","name":"X","currentStatus":"up"}]}}"#

        #expect(try UptimeResponseDecoder.decode(Data(json.utf8)).count == 1)
    }

    @Test(
        "A body that is not the documented envelope is rejected",
        arguments: [
            // A missing `projects` key is a real failure, never an empty screen.
            #"{"data":{"key":{"id":"uuid","name":"Statuspage"}}}"#,
            // As is a missing `data` wrapper, however plausible the inner shape.
            #"{"projects":[{"id":"1","name":"X","currentStatus":"up"}]}"#,
            // The documented error bodies are not project lists.
            #"{"error":"Unauthorized","code":"UNAUTHORIZED"}"#,
            #"{"error":"Project not found","code":"PROJECT_NOT_FOUND"}"#,
            // Neither is a bare list, a scalar, or something that is not JSON at all.
            #"[{"id":"1","name":"X","currentStatus":"up"}]"#,
            "42",
            "not json at all"
        ]
    )
    func unusableBodies(body: String) {
        #expect(throws: (any Error).self) {
            try UptimeResponseDecoder.decode(Data(body.utf8))
        }
    }

    @Test("A project with no name is a malformed response, not a blank row")
    func namelessProjectIsRejected() {
        let json = #"{"data":{"projects":[{"id":"1","currentStatus":"up"}]}}"#

        #expect(throws: (any Error).self) {
            try UptimeResponseDecoder.decode(Data(json.utf8))
        }
    }

    @Test("A timestamp without fractional seconds is accepted")
    func wholeSecondTimestamp() throws {
        let json = """
        {"data":{"projects":[{"id":"1","name":"X","currentStatus":"up",
         "lastCheckedAt":"2026-06-13T12:00:00Z"}]}}
        """

        let services = try UptimeResponseDecoder.decode(Data(json.utf8))

        #expect(services.first?.lastCheckedAt == Date(timeIntervalSince1970: 1_781_352_000))
    }

    @Test(
        "An unusable timestamp costs that project its check time, not the whole list",
        arguments: [
            #""yesterday""#,      // Not a date at all.
            #""13/06/2026""#,     // A date, but not ISO 8601.
            "1781352000",          // The right instant in the wrong type.
            "null",
            "{}"
        ]
    )
    func unusableTimestampDegrades(value: String) throws {
        let json = """
        {"data":{"projects":[
          {"name":"BROKEN STAMP","currentStatus":"down","lastCheckedAt":\(value)},
          {"name":"GOOD STAMP","currentStatus":"up","lastCheckedAt":"2026-06-13T12:00:00.000Z"}]}}
        """

        let services = try UptimeResponseDecoder.decode(Data(json.utf8))

        // Both rows still render, with their real states: a check time is not a row.
        #expect(services.map(\.name) == ["BROKEN STAMP", "GOOD STAMP"])
        #expect(services.map(\.status) == [.down, .operational])
        #expect(services.first?.lastCheckedAt == nil)
        #expect(services.last?.lastCheckedAt == Date(timeIntervalSince1970: 1_781_352_000))
    }

    @Test("An unusable status field costs that project its state, not the whole list")
    func unusableStatusDegrades() throws {
        // `currentStatus` sent as a number rather than a string: the row survives as
        // unknown, on the same rule the timestamp follows.
        let json = #"{"data":{"projects":[{"name":"NUMERIC","currentStatus":1}]}}"#

        #expect(try UptimeResponseDecoder.decode(Data(json.utf8))
            == [UptimeService(name: "NUMERIC", status: .unknown)])
    }

    @Test("Fields the screen never draws cannot fail the parse, whatever their type")
    func undrawnFieldsAreNotRequired() throws {
        // No `id` on the project, no `id` or `keyPrefix` on the key, and an `id` sent
        // as a number rather than a string. None of it is decoded, so none of it can
        // reject a response the screen could otherwise draw.
        let json = """
        {"data":{"key":{"name":"Statuspage"},
         "projects":[{"id":7,"name":"NUMERIC ID","currentStatus":"up"},
                     {"name":"NO ID","currentStatus":"down"}]}}
        """

        let services = try UptimeResponseDecoder.decode(Data(json.utf8))

        #expect(services.map(\.name) == ["NUMERIC ID", "NO ID"])
        #expect(services.map(\.status) == [.operational, .down])
    }

    @Test("A timestamp ahead of the device clock is kept as the API sent it")
    func futureTimestampIsNotClamped() throws {
        // Deliberate: the line reports the API's own clock, and silently rewriting a
        // skewed timestamp to "now" would hide the skew behind a plausible time.
        let json = """
        {"data":{"projects":[{"name":"AHEAD","currentStatus":"up",
         "lastCheckedAt":"2099-01-01T00:00:00.000Z"}]}}
        """

        let stamp = try #require(
            UptimeResponseDecoder.decode(Data(json.utf8)).first?.lastCheckedAt
        )

        #expect(stamp > Date())
    }
}
