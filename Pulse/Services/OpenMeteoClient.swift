import Foundation

/// Something that can report the current temperature at a coordinate.
///
/// The clock screen depends on this rather than on `OpenMeteoClient` directly, so
/// the screen's failure handling can be exercised without a network.
nonisolated public protocol TemperatureSource: Sendable {

    /// The current temperature at `coordinate`.
    ///
    /// - Throws: Any error. Callers treat every failure the same way — the
    ///   temperature line is simply absent.
    func temperature(at coordinate: Coordinate) async throws -> TemperatureReading
}

/// Reads the current temperature from Open-Meteo.
///
/// ```
/// GET https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&current=temperature_2m
/// ```
///
/// **The service needs no API key, no account and no token.** That is why it was
/// chosen: the project rules forbid a credential in source, in a plist or in git
/// history, and this endpoint requires none — only the base URL is hardcoded,
/// which the rules permit. It is a European open-data service, which matters for
/// this project's data-handling rules.
///
/// The coordinate is coarsened to two decimal places before it is sent and is
/// never logged or persisted. No response is written to a disk cache.
///
/// Declared `nonisolated`: the project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION =
/// MainActor`, so without this the request and the decode of its response would
/// both be pinned to the main actor.
nonisolated public struct OpenMeteoClient: TemperatureSource {

    /// Why a request did not produce a reading.
    public enum Failure: Error, Equatable, Sendable {

        /// The request never completed — offline, DNS, TLS, timeout.
        case unreachable

        /// The service answered with an unexpected status code.
        case server(status: Int)

        /// The body could not be read as a Celsius reading.
        case malformedResponse
    }

    /// The forecast endpoint. A base URL is the only thing that may be hardcoded,
    /// and here it is also the only thing there is: the request carries no
    /// credential.
    ///
    /// Force-unwrapped: the argument is a compile-time string literal that is a
    /// valid absolute URL, so the initialiser cannot return `nil` here, and a build
    /// that broke that would fail on the first lookup.
    public static let endpoint = URL(string: "https://api.open-meteo.com/v1/forecast")!

    /// The value of the `current=` parameter: the 2 metre air temperature.
    public static let currentFields = "temperature_2m"

    private let session: URLSession

    /// Creates a client.
    ///
    /// - Parameter session: The session used for requests. The default is ephemeral
    ///   so no response touches a disk cache, and short-timeouted so a hung server
    ///   cannot hold a request open across a refresh interval.
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

    /// The current temperature at `coordinate`.
    ///
    /// - Parameter coordinate: Where to read the temperature. Coarsened before it
    ///   is sent.
    /// - Returns: The current temperature in degrees Celsius.
    /// - Throws: `Failure`, or `CancellationError` when the caller's task was
    ///   cancelled mid-flight.
    public func temperature(at coordinate: Coordinate) async throws -> TemperatureReading {
        var request = URLRequest(url: Self.url(for: coordinate))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            // The refresh loop cancels in flight when the screen is paged away;
            // that is not a failure the display should react to.
            throw CancellationError()
        } catch {
            throw Failure.unreachable
        }

        guard let http = response as? HTTPURLResponse else {
            throw Failure.malformedResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            throw Failure.server(status: http.statusCode)
        }

        do {
            return try TemperatureResponseDecoder.decode(data)
        } catch {
            throw Failure.malformedResponse
        }
    }

    /// Builds the request URL for `coordinate`.
    ///
    /// Exposed for tests, which pin the query the service is actually sent —
    /// including that it carries nothing but the two coordinates and the field
    /// list, and no credential of any kind.
    public static func url(for coordinate: Coordinate) -> URL {
        let coarse = coordinate.coarsened

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: format(coarse.latitude)),
            URLQueryItem(name: "longitude", value: format(coarse.longitude)),
            URLQueryItem(name: "current", value: currentFields)
        ]

        // The components were built from a valid absolute URL and every added value
        // is percent-encodable, so `url` cannot be `nil`; the bare endpoint is
        // returned rather than force-unwrapping, and a request to it fails the same
        // graceful way as any other bad response.
        return components?.url ?? endpoint
    }

    /// Formats a coordinate component for the query string.
    ///
    /// Pinned to a POSIX locale so a device set to a region that writes decimals
    /// with a comma still sends `52.52` rather than `52,52`.
    private static func format(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
