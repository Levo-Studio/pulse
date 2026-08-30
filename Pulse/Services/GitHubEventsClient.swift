import Foundation

/// Fetches an account's public event feed from GitHub's documented JSON API.
///
/// ```
/// GET https://api.github.com/users/{username}/events/public?per_page=100
/// Accept: application/vnd.github+json
/// ```
///
/// The request is unauthenticated by design. Pulse stores no GitHub token, so this is
/// the public feed and nothing else; only the base URL is hardcoded, and the username
/// comes from the Keychain. Unlike the contributions page this is a versioned JSON API
/// rather than scraped markup, which is why it — and not the heatmap source — is where
/// the time of the day's last push comes from.
///
/// Two limits are load-bearing for callers:
///
/// - **Public activity only.** Private repository work never appears here, so figures
///   derived from this feed are a floor, not a total, and may disagree with the
///   contribution heatmap on the same screen. `GitHubActivitySummary` documents how
///   that is presented.
/// - **60 requests per hour per IP**, shared with everyone else behind that address.
///   Exhaustion answers `403` (or `429`) with `x-ratelimit-remaining: 0`; that is
///   reported as `Failure.rateLimited` carrying the reset time so the caller can wait
///   it out instead of retrying into a closed door.
public struct GitHubEventsClient: Sendable {

    /// Why a fetch did not produce events.
    public enum Failure: Error, Equatable, Sendable {

        /// The username is empty or contains characters GitHub does not allow.
        case invalidUsername

        /// GitHub has no such account.
        case unknownUser

        /// The request did not complete, or the response was not HTTP.
        case unreachable

        /// The hourly unauthenticated quota for this IP is spent.
        ///
        /// - Parameter resetAt: When the quota refills, as GitHub reported it, or
        ///   `nil` when the response carried no usable reset header.
        case rateLimited(resetAt: Date?)

        /// GitHub answered, but not with success.
        case unexpectedStatus(Int)

        /// The body was not the event array this client understands.
        case undecodableResponse
    }

    /// The public events API.
    private static let baseURL = URL(string: "https://api.github.com/users")

    /// The largest page GitHub serves. One page is all the display needs: it only ever
    /// asks about today, and the window is roughly the last 300 events or 90 days.
    private static let pageSize = 100

    private let session: URLSession

    /// Creates a client.
    ///
    /// - Parameter session: Transport to use. Defaults to a short-timeout ephemeral
    ///   session, so no response is written to the shared URL cache.
    public init(session: URLSession = GitHubEventsClient.makeDefaultSession()) {
        self.session = session
    }

    /// The session used unless a caller supplies its own.
    public static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    /// Loads one page of `username`'s public events, newest first.
    ///
    /// - Throws: `Failure` for every failure mode. Callers keep whatever they last
    ///   showed rather than surfacing an error to the user.
    public func events(for username: String) async throws -> [GitHubEvent] {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard GitHubContributionsClient.isValidUsername(trimmed),
              let url = Self.eventsURL(for: trimmed) else {
            throw Failure.invalidUsername
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Failure.unreachable
        }

        guard let http = response as? HTTPURLResponse else { throw Failure.unreachable }
        switch http.statusCode {
        case 200...299: break
        case 403, 429: throw Failure.rateLimited(resetAt: Self.rateLimitReset(from: http))
        case 404: throw Failure.unknownUser
        default: throw Failure.unexpectedStatus(http.statusCode)
        }

        return try Self.decode(data)
    }

    /// Decodes an event feed page.
    ///
    /// Exposed so the wire shape can be pinned by tests against recorded payloads
    /// without touching the network.
    ///
    /// - Throws: `Failure.undecodableResponse` when the body is not an array of events.
    public static func decode(_ data: Data) throws -> [GitHubEvent] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        guard let page = try? decoder.decode([LenientEvent].self, from: data) else {
            throw Failure.undecodableResponse
        }
        return page.compactMap(\.event)
    }

    /// The moment the quota refills, read from `x-ratelimit-reset`.
    ///
    /// The header is a Unix timestamp in seconds. A missing or unparsable value yields
    /// `nil`, which the caller treats as "unknown, back off for the usual interval"
    /// rather than as "retry now".
    private static func rateLimitReset(from response: HTTPURLResponse) -> Date? {
        guard let raw = response.value(forHTTPHeaderField: "x-ratelimit-reset"),
              let seconds = TimeInterval(raw.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func eventsURL(for username: String) -> URL? {
        guard let base = baseURL else { return nil }
        let path = base
            .appendingPathComponent(username)
            .appendingPathComponent("events")
            .appendingPathComponent("public")
        var components = URLComponents(url: path, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "per_page", value: String(pageSize))]
        return components?.url
    }
}

// MARK: - Wire shapes

/// One element of the feed array, decoded so a single unfamiliar entry cannot cost the
/// whole page.
///
/// GitHub emits dozens of event types and reshapes payloads of types this display does
/// not read. Decoding straight into `[WireEvent]` would abort the array on the first
/// one that does not fit; this wrapper always succeeds, consuming its element and
/// yielding `nil` for anything unreadable.
private struct LenientEvent: Decodable {

    let event: GitHubEvent?

    init(from decoder: Decoder) throws {
        event = (try? WireEvent(from: decoder))?.asEvent
    }
}

/// The subset of an event Pulse reads.
private struct WireEvent: Decodable {

    let type: String
    let createdAt: Date

    /// The display's view of this entry.
    ///
    /// Only pushes are distinguished. The screen reads one fact from this feed — when
    /// today's last push happened — so every other event type is `other` rather than
    /// being classified into a distinction nothing renders.
    var asEvent: GitHubEvent {
        GitHubEvent(kind: type == "PushEvent" ? .push : .other, createdAt: createdAt)
    }
}
