import Foundation

/// Reads the Levo Studio uptime list.
///
/// Only the base URL is hardcoded. The bearer key belongs to the user, is entered on
/// first use, and lives in the Keychain; it is passed in per request and is never
/// logged, stored in this type, or included in any error.
///
/// Declared `nonisolated`: the project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION =
/// MainActor`, so without this the request and the decode of its response would both
/// be pinned to the main actor.
nonisolated public struct UptimeAPIClient: Sendable {

    /// Why a request did not produce a list of services.
    public enum Failure: Error, Equatable, Sendable {

        /// The API rejected the key. `401` is the documented answer to a request
        /// without a usable key; `403` is treated the same way, since both mean the
        /// key on file will not work. The key must be re-entered; this is
        /// deliberately distinct from a transport failure so the screen can re-prompt
        /// instead of showing a network error.
        case unauthorized

        /// The request never completed — offline, DNS, TLS, timeout.
        case unreachable

        /// The API answered with an unexpected status code.
        case server(status: Int)

        /// The body could not be read as a list of services. The body itself is not
        /// carried here: it may contain infrastructure detail.
        case malformedResponse
    }

    /// The uptime endpoint. A base URL is the only thing that may be hardcoded.
    ///
    /// Force-unwrapped: the argument is a compile-time string literal that is a valid
    /// absolute URL, so the initialiser cannot return `nil` here, and a build that
    /// broke that would be caught by the first launch.
    public static let endpoint = URL(string: "https://tickets.levo-studio.com/api/uptime/listall")!

    private let session: URLSession

    /// Creates a client.
    ///
    /// - Parameter session: The session used for requests. The default is ephemeral so
    ///   no response touches a disk cache, and short-timeouted so a hung server cannot
    ///   stall the 20 second poll cadence.
    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            configuration.timeoutIntervalForResource = 15
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    /// Fetches the current service list.
    ///
    /// - Parameter key: The user's bearer key, read from the Keychain by the caller.
    /// - Returns: The services to display, in the order the API sent them.
    /// - Throws: `Failure`.
    public func services(key: String) async throws -> [UptimeService] {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            // The poll loop cancels in flight when the screen is paged away; that is
            // not a failure the display should react to.
            throw CancellationError()
        } catch {
            throw Failure.unreachable
        }

        guard let http = response as? HTTPURLResponse else {
            throw Failure.malformedResponse
        }

        switch http.statusCode {
        case 200..<300:
            do {
                return try UptimeResponseDecoder.decode(data)
            } catch {
                throw Failure.malformedResponse
            }
        case 401, 403:
            throw Failure.unauthorized
        default:
            throw Failure.server(status: http.statusCode)
        }
    }
}
