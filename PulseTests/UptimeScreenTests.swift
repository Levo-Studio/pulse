import Foundation
import Testing

@testable import Pulse

/// Pins the row arithmetic that keeps a long service name from pushing the status
/// square off the screen.
///
/// The budget is easy to get wrong — it has to account for every gap the row spends
/// and for the widest glyph the face can draw — and a mistake is invisible on the
/// devices where `PixelMetrics` has horizontal slack. These assertions make the
/// arithmetic fail loudly instead of drifting.
struct UptimeRowMetricsTests {

    @Test("The row reserves the full content width it actually spends")
    func widthAccounting() {
        #expect(UptimeRowMetrics.contentWidth == 308)
        // Three gaps: the HStack spacing either side of the spacer, and the spacer's
        // own minimum length.
        #expect(UptimeRowMetrics.gapWidth == 36)
        #expect(UptimeRowMetrics.nameWidthBudget == 261)
    }

    @Test("The character advance is the widest Silkscreen draws, not an average")
    func characterAdvance() {
        // Measured from the bundled face: A-Z 0-9 - _ . advance 0.375, 0.625, 0.75 or
        // 0.875 em, with M N V W X Y at the widest.
        #expect(UptimeRowMetrics.characterWidth == (13 * 0.875) + 2)
    }

    @Test("A full-length name plus the gaps and the square fits the content width")
    func budgetFitsTheRow() {
        let widest = CGFloat(UptimeRowMetrics.characterBudget) * UptimeRowMetrics.characterWidth
            + UptimeRowMetrics.gapWidth
            + UptimeRowMetrics.squareSide

        #expect(UptimeRowMetrics.characterBudget == 19)
        #expect(widest <= UptimeRowMetrics.contentWidth)
    }

    @Test("One more character than the budget would overrun")
    func budgetIsTight() {
        let overlong = CGFloat(UptimeRowMetrics.characterBudget + 1) * UptimeRowMetrics.characterWidth
            + UptimeRowMetrics.gapWidth
            + UptimeRowMetrics.squareSide

        #expect(overlong > UptimeRowMetrics.contentWidth)
    }

    @Test("Names within the budget are untouched, longer ones are marked")
    func truncation() {
        let short = String(repeating: "M", count: UptimeRowMetrics.characterBudget)
        #expect(UptimeRowMetrics.displayName(for: short) == short)

        let long = String(repeating: "M", count: 60)
        let shortened = UptimeRowMetrics.displayName(for: long)
        #expect(shortened.count == UptimeRowMetrics.characterBudget)
        #expect(shortened.hasSuffix(UptimeRowMetrics.truncationMarker))
    }
}

/// Covers the uptime model's failure paths, which are reachable because the Keychain
/// store and the API client are injected.
///
/// Every request is served by a stub, so nothing here touches the network, and every
/// Keychain item is written under a service identifier unique to the test and removed
/// afterwards, so the user's own item is never read or altered.
///
/// Serialized: the stub protocol carries its canned response in static state, which
/// concurrent cases would overwrite for each other.
@Suite(.serialized)
struct UptimeModelTests {

    /// A placeholder for a stored credential. Not a key, and never sent anywhere: the
    /// stub answers without inspecting the request.
    private static let storedPlaceholder = "stored-placeholder-value"

    private func makeStore() -> KeychainStore {
        KeychainStore(service: "levo-studio.PulseTests.\(UUID().uuidString)")
    }

    /// An empty but well-formed response body, in the documented envelope.
    private static let emptyPayload = #"{"data":{"projects":[]}}"#

    private func makeClient(status: Int, body: String = emptyPayload) -> UptimeAPIClient {
        StubURLProtocol.statusCode = status
        StubURLProtocol.body = Data(body.utf8)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return UptimeAPIClient(session: URLSession(configuration: configuration))
    }

    @Test("A rejected key re-prompts but is never deleted from the Keychain")
    func rejectedKeyIsRetained() async {
        let keychain = makeStore()
        #expect(keychain.set(Self.storedPlaceholder, for: .uptimeAPIKey))
        defer { keychain.remove(.uptimeAPIKey) }

        let model = UptimeModel(keychain: keychain, client: makeClient(status: 401))
        await model.refresh()

        #expect(model.needsKey)
        #expect(model.promptNotice == .keyRejected)
        // The stored value may be the user's only copy of a long opaque token, so a
        // single transient 401 must not destroy it.
        #expect(keychain.string(for: .uptimeAPIKey) == Self.storedPlaceholder)
    }

    @Test("A stored key is overwritten only when a new one is saved")
    func savingReplacesTheStoredKey() {
        let keychain = makeStore()
        #expect(keychain.set(Self.storedPlaceholder, for: .uptimeAPIKey))
        defer { keychain.remove(.uptimeAPIKey) }

        let model = UptimeModel(keychain: keychain, client: makeClient(status: 200))
        #expect(model.store(key: "replacement-placeholder-value"))

        #expect(!model.needsKey)
        #expect(model.promptNotice == .firstUse)
        #expect(keychain.string(for: .uptimeAPIKey) == "replacement-placeholder-value")
    }

    @Test("With no key stored, the model asks for one instead of calling the API")
    func missingKeyPrompts() async {
        let keychain = makeStore()
        let model = UptimeModel(keychain: keychain, client: makeClient(status: 200))

        #expect(model.needsKey)
        await model.refresh()
        #expect(model.needsKey)
    }

    @Test("A server error is reported as itself, not as a connection failure")
    func serverErrorIsDescribedPrecisely() async {
        let keychain = makeStore()
        #expect(keychain.set(Self.storedPlaceholder, for: .uptimeAPIKey))
        defer { keychain.remove(.uptimeAPIKey) }

        let model = UptimeModel(keychain: keychain, client: makeClient(status: 500))
        await model.refresh()

        #expect(model.faultText == "SERVER ERROR: 500")
        // A server fault must not send the user back to the prompt: the key is fine.
        #expect(!model.needsKey)
    }

    @Test("A body that will not decode is reported as unreadable, and 403 is not a rejected key")
    func otherFaults() async {
        let keychain = makeStore()
        #expect(keychain.set(Self.storedPlaceholder, for: .uptimeAPIKey))
        defer { keychain.remove(.uptimeAPIKey) }

        let unreadable = UptimeModel(keychain: keychain, client: makeClient(status: 200, body: "not json"))
        await unreadable.refresh()
        #expect(unreadable.faultText == "UNREADABLE RESPONSE")

        // 403 means authenticated but not permitted: re-typing the same key cannot fix
        // it, so it must not send the user back to the prompt.
        let forbidden = UptimeModel(keychain: keychain, client: makeClient(status: 403))
        await forbidden.refresh()
        #expect(forbidden.faultText == "SERVER ERROR: 403")
        #expect(!forbidden.needsKey)
    }

    @Test("A successful fetch fills the list and stamps the check time")
    func successfulFetch() async {
        let keychain = makeStore()
        #expect(keychain.set(Self.storedPlaceholder, for: .uptimeAPIKey))
        defer { keychain.remove(.uptimeAPIKey) }

        let body = """
        {"data":{"key":{"id":"uuid","name":"Statuspage","keyPrefix":"lsu_abcd1234"},
         "projects":[{"id":"1","name":"API-GATEWAY","currentStatus":"up",
                      "lastCheckedAt":"2026-06-13T12:00:00.000Z"}]}}
        """
        let model = UptimeModel(keychain: keychain, client: makeClient(status: 200, body: body))
        await model.refresh()

        #expect(model.services == [
            UptimeService(
                name: "API-GATEWAY",
                status: .operational,
                lastCheckedAt: Date(timeIntervalSince1970: 1_781_352_000)
            )
        ])
        #expect(model.faultText == nil)
        // LAST CHECK reports the API's own check time, not when the app last asked.
        #expect(model.lastCheckText == Self.localClockText(for: 1_781_352_000))
        // The countdown must never read above the interval, whatever the relationship
        // between the sampled clock and the attempt that has just completed.
        #expect(model.secondsUntilRefresh <= 20)
        #expect(model.secondsUntilRefresh >= 0)
    }

    @Test("LAST CHECK reads the newest API timestamp, and dashes when there is none")
    func lastCheckSource() async {
        let keychain = makeStore()
        #expect(keychain.set(Self.storedPlaceholder, for: .uptimeAPIKey))
        defer { keychain.remove(.uptimeAPIKey) }

        let body = """
        {"data":{"projects":[
          {"id":"1","name":"OLDER","currentStatus":"up","lastCheckedAt":"2026-06-13T11:59:00.000Z"},
          {"id":"2","name":"NEWER","currentStatus":"down","lastCheckedAt":"2026-06-13T12:00:00.000Z"}]}}
        """
        let model = UptimeModel(keychain: keychain, client: makeClient(status: 200, body: body))
        await model.refresh()
        #expect(model.lastCheckText == Self.localClockText(for: 1_781_352_000))

        // A response the API stamps with no check time leaves the line as dashes
        // rather than quietly substituting the device's own fetch time, which is a
        // different quantity and would read as the same one.
        let unstamped = UptimeModel(
            keychain: keychain,
            client: makeClient(status: 200, body: #"{"data":{"projects":[{"id":"1","name":"X"}]}}"#)
        )
        await unstamped.refresh()
        #expect(unstamped.services.count == 1)
        #expect(unstamped.lastCheckText == "--:--:--")
    }

    @Test("A 404 is reported as itself and does not send the user back to the prompt")
    func projectNotFound() async {
        let keychain = makeStore()
        #expect(keychain.set(Self.storedPlaceholder, for: .uptimeAPIKey))
        defer { keychain.remove(.uptimeAPIKey) }

        let model = UptimeModel(
            keychain: keychain,
            client: makeClient(status: 404, body: #"{"error":"Not found","code":"PROJECT_NOT_FOUND"}"#)
        )
        await model.refresh()

        #expect(model.faultText == "SERVER ERROR: 404")
        #expect(!model.needsKey)
    }

    /// The reference's `HH:mm:ss`, in the device's time zone, for an instant.
    ///
    /// Computed rather than hardcoded so the expectation holds wherever the tests run.
    private static func localClockText(for epochSeconds: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date(timeIntervalSince1970: epochSeconds))
    }
}

/// Serves canned responses so the model's failure paths can be exercised without a
/// network or a key.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {

    /// Status code the stub answers with.
    nonisolated(unsafe) static var statusCode = 200

    /// Body the stub answers with.
    nonisolated(unsafe) static var body = Data(#"{"data":{"projects":[]}}"#.utf8)

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // Both force-unwraps are safe here: `request.url` is set by the client for
        // every request it makes, and `HTTPURLResponse` returns nil only for a nil URL.
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
