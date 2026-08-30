// Verification of the uptime response decoder against authored sample payloads.
//
// The Xcode project has a single app target and no test target, and this directory
// sits outside `Pulse/`, so nothing here is compiled into the app. Run it with:
//
//     xcrun swiftc -o /tmp/uptime-decoder-checks \
//       Pulse/Models/UptimeService.swift Tests/UptimeDecoderChecks/main.swift \
//       && /tmp/uptime-decoder-checks
//
// The payloads below are invented. The real response shape of
// `GET /api/uptime/listall` has never been observed — the endpoint answers 401
// without a key — so these cover every shape the decoder claims to accept, not a
// recorded response. No key appears here, and none is needed: nothing in this file
// touches the network.

import Foundation

var failures = 0

func expect(_ condition: Bool, _ label: String) {
    if condition {
        print("PASS  \(label)")
    } else {
        failures += 1
        print("FAIL  \(label)")
    }
}

func decode(_ json: String, _ label: String) -> [UptimeService]? {
    guard let data = json.data(using: .utf8) else { return nil }
    do {
        return try UptimeResponseDecoder.decode(data)
    } catch {
        failures += 1
        print("FAIL  \(label) — threw \(error)")
        return nil
    }
}

// 1. Top-level array, canonical keys.
if let s = decode(#"""
[{"name":"API-GATEWAY","status":"up"},
 {"name":"REDIS-CACHE","status":"degraded"},
 {"name":"K3S-CLUSTER","status":"down"},
 {"name":"BACKUP-JOB","status":"wat"}]
"""#, "top-level array") {
    expect(s.map(\.name) == ["API-GATEWAY", "REDIS-CACHE", "K3S-CLUSTER", "BACKUP-JOB"], "array: names in order")
    expect(s.map(\.status) == [.operational, .degraded, .down, .unknown], "array: statuses incl. unrecognised -> unknown")
}

// 2. {"data": [...]} wrapper, alternative key spellings.
if let s = decode(#"""
{"data":[{"service_name":"WEB-FRONTEND","currentStatus":"Operational"},
         {"friendly_name":"POSTGRES-01","state":"Partial Outage"}]}
"""#, "data wrapper") {
    expect(s.map(\.name) == ["WEB-FRONTEND", "POSTGRES-01"], "data: alternative name keys")
    expect(s.map(\.status) == [.operational, .degraded], "data: mixed-case and spaced tokens")
}

// 3. {"services": [...]} wrapper with boolean and numeric states.
if let s = decode(#"""
{"services":[{"title":"WORKER-QUEUE","up":true},
             {"label":"MAIL-RELAY","online":false},
             {"name":"CDN-EDGE","status":1},
             {"name":"OBJECT-STORE","status":0}]}
"""#, "services wrapper") {
    expect(s.map(\.status) == [.operational, .down, .operational, .down], "services: bool and numeric states")
    expect(s.map(\.name) == ["WORKER-QUEUE", "MAIL-RELAY", "CDN-EDGE", "OBJECT-STORE"], "services: names")
}

// 4. Other plausible wrappers.
for key in ["results", "items", "monitors", "list", "checks"] {
    if let s = decode("{\"\(key)\":[{\"name\":\"X\",\"health\":\"healthy\"}]}", "\(key) wrapper") {
        expect(s == [UptimeService(name: "X", status: .operational)], "\(key): wrapper accepted")
    }
}

// 5. Nested wrapper: {"data":{"services":[...]}}.
if let s = decode(#"{"data":{"services":[{"name":"NESTED","status":"ok"}]}}"#, "nested wrapper") {
    expect(s == [UptimeService(name: "NESTED", status: .operational)], "nested: one level of nesting accepted")
}

// 6. Missing status, unnamed entries, bare strings.
if let s = decode(#"""
[{"name":"NO-STATUS"},
 {"status":"up"},
 "BARE-STRING",
 {"name":"  PADDED  ","status":"  UP  "}]
"""#, "tolerance") {
    expect(s.map(\.name) == ["NO-STATUS", "BARE-STRING", "PADDED"], "tolerance: nameless entry dropped, bare string kept, name trimmed")
    expect(s.map(\.status) == [.unknown, .unknown, .operational], "tolerance: missing status -> unknown, padded token trimmed")
}

// 7. Empty list is valid and empty.
if let s = decode(#"{"data":[]}"#, "empty list") {
    expect(s.isEmpty, "empty: decodes to no rows")
}

// 8. Shapes that must throw rather than silently return nothing.
for bad in [#"{"error":"Unauthorized","code":"UNAUTHORIZED"}"#, "not json at all", #"42"#] {
    let data = Data(bad.utf8)
    var threw = false
    do { _ = try UptimeResponseDecoder.decode(data) } catch { threw = true }
    expect(threw, "rejects unusable body: \(bad.prefix(24))")
}

// 9. Vocabulary spot checks through the public mapping.
expect(UptimeResponseDecoder.status(for: nil) == .unknown, "vocabulary: nil -> unknown")
expect(UptimeResponseDecoder.status(for: "MAINTENANCE") == .unknown, "vocabulary: maintenance -> unknown")
expect(UptimeResponseDecoder.status(for: "degraded-performance") == .degraded, "vocabulary: hyphenated token")
expect(UptimeResponseDecoder.status(for: "MAJOR OUTAGE") == .down, "vocabulary: spaced token")

print(failures == 0 ? "\nALL CHECKS PASSED" : "\n\(failures) CHECK(S) FAILED")
exit(failures == 0 ? 0 : 1)
