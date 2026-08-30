import Foundation

/// Fetches a public GitHub contribution calendar.
///
/// The request is unauthenticated by design: Pulse stores no GitHub token, so the
/// authenticated GraphQL API is deliberately not used. Only the base URL is hardcoded;
/// the username is supplied by the user and kept in the Keychain.
public struct GitHubContributionsClient: Sendable {

    /// Why a fetch did not produce a calendar.
    public enum Failure: Error, Equatable, Sendable {

        /// The username is empty or contains characters GitHub does not allow.
        case invalidUsername

        /// GitHub has no such account, or it exposes no contribution graph.
        case unknownUser

        /// The request did not complete, or the response was not HTTP.
        case unreachable

        /// GitHub answered, but not with success.
        case unexpectedStatus(Int)

        /// The response body carried no calendar this parser recognises.
        case unparsableMarkup
    }

    /// The public contributions fragment endpoint.
    private static let baseURL = URL(string: "https://github.com/users")

    private let session: URLSession

    /// Creates a client.
    ///
    /// - Parameter session: Transport to use. Defaults to a short-timeout ephemeral
    ///   session so a scraped page is never written to the shared URL cache.
    public init(session: URLSession = GitHubContributionsClient.makeDefaultSession()) {
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

    /// Loads the contribution calendar of `username`.
    ///
    /// - Throws: `Failure` for every failure mode; the caller renders an empty or
    ///   stale state rather than surfacing a crash.
    public func calendar(for username: String) async throws -> ContributionCalendar {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidUsername(trimmed), let url = Self.contributionsURL(for: trimmed) else {
            throw Failure.invalidUsername
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/html", forHTTPHeaderField: "Accept")

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
        case 404: throw Failure.unknownUser
        default: throw Failure.unexpectedStatus(http.statusCode)
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw Failure.unparsableMarkup
        }

        let days = GitHubContributionsParser.parse(html)
        guard !days.isEmpty else { throw Failure.unparsableMarkup }
        return ContributionCalendar(days: days)
    }

    /// Whether `username` matches GitHub's account name rules.
    ///
    /// Checked before the request so a malformed entry is reported as a bad username
    /// rather than as a network failure.
    public static func isValidUsername(_ username: String) -> Bool {
        guard (1...39).contains(username.count) else { return false }
        guard !username.hasPrefix("-"), !username.hasSuffix("-") else { return false }
        return username.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    private static func contributionsURL(for username: String) -> URL? {
        baseURL?
            .appendingPathComponent(username)
            .appendingPathComponent("contributions")
    }
}
