import Foundation

/// The state of a single monitored service, as displayed by the status square on
/// the uptime screen.
///
/// The API reports five states — `up`, `slow`, `degraded`, `down`, `unknown` — and the
/// reference design draws four colours, so `slow` and `degraded` share the amber
/// square. `Self.init(apiValue:)` is the only place that mapping lives.
///
/// Declared `nonisolated`: the project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION =
/// MainActor`, so without this every type in this file would be main-actor isolated
/// and the response parse would run on the main actor behind the display.
nonisolated public enum UptimeStatus: String, Sendable, CaseIterable {

    /// The service is up. Drawn `#22C55E`.
    case operational

    /// The service is reachable but impaired — the API's `slow` and `degraded`.
    /// Drawn `#F59E0B`.
    case degraded

    /// The service is down. Drawn `#EF4444`.
    case down

    /// No usable state was reported for the service. Drawn `#2A2D2E`.
    case unknown

    /// Maps a `currentStatus` value from the API onto a displayed state.
    ///
    /// The documented vocabulary is exactly `up`, `slow`, `degraded`, `down` and
    /// `unknown`. **Anything else becomes `.unknown`**: a value outside the contract
    /// means the API is saying something this build does not understand, and an
    /// honest blank square is preferable to a guessed colour. Matching is
    /// case-insensitive so a change of casing alone does not blank the list.
    ///
    /// - Parameter apiValue: The raw `currentStatus` string, or `nil` when absent.
    public init(apiValue: String?) {
        switch apiValue?.lowercased() {
        case "up": self = .operational
        case "slow", "degraded": self = .degraded
        case "down": self = .down
        default: self = .unknown
        }
    }
}

/// One row of the uptime list: a service name, its current state, and when the API
/// last checked it.
nonisolated public struct UptimeService: Sendable, Equatable {

    /// The name shown on the left of the row, the project's `name`.
    public let name: String

    /// The state shown as a coloured square on the right of the row.
    public let status: UptimeStatus

    /// When the API itself last checked this project, from `lastCheckedAt`.
    ///
    /// `nil` when the API sent no timestamp — a project that has never been checked.
    /// This is the API's clock, not the device's: it says when the state being drawn
    /// was actually observed, not when the app last asked for it.
    public let lastCheckedAt: Date?

    /// Creates a service entry.
    public init(name: String, status: UptimeStatus, lastCheckedAt: Date? = nil) {
        self.name = name
        self.status = status
        self.lastCheckedAt = lastCheckedAt
    }
}

// MARK: - Response decoding

/// Decodes the documented payload of `GET /api/uptime/listall` into `UptimeService`
/// values.
///
/// The response is an object with a single `data` member carrying the calling key's
/// metadata and the project list:
///
/// ```json
/// { "data": { "key": { … }, "projects": [ { "name": "…", "currentStatus": "up", … } ] } }
/// ```
///
/// Only the fields the screen draws are decoded; every other field the API sends is
/// ignored rather than rejected, so the endpoint can grow without breaking this build.
/// A **missing `data` or `projects` member is an error**, not an empty result: it means
/// the response is not the documented shape, and silently drawing an empty list would
/// be indistinguishable from monitoring nothing.
nonisolated public enum UptimeResponseDecoder {

    /// The top-level response envelope.
    public struct Response: Decodable, Sendable {

        /// The single `data` member.
        public let data: Payload
    }

    /// The contents of `data`: the calling key's metadata and the project list.
    public struct Payload: Decodable, Sendable {

        /// Metadata about the key the request authenticated with.
        ///
        /// Optional so a response that omits it still yields a usable project list;
        /// the screen does not draw it.
        public let key: KeyMetadata?

        /// The monitored projects, in the order the API sent them.
        public let projects: [Project]
    }

    /// Metadata about the API key the request authenticated with.
    ///
    /// The API also sends a `keyPrefix` — the leading characters of the user's own
    /// bearer token, `lsu_` plus eight more. It is **deliberately not decoded**: it is
    /// a fragment of a credential, the app has no use for it, and a value that is never
    /// held cannot be logged or leaked by accident.
    public struct KeyMetadata: Decodable, Sendable {

        /// The key's identifier.
        public let id: String

        /// The human-readable name the key was given.
        public let name: String
    }

    /// One monitored project.
    ///
    /// The API sends more per project — customer, domain, category, server location,
    /// hosting price, failure counts and a `summary` block of response-time statistics.
    /// None of it is drawn by the uptime screen, so none of it is decoded; the fields
    /// are simply ignored.
    public struct Project: Decodable, Sendable {

        /// The project's identifier.
        public let id: String

        /// The project's display name.
        public let name: String

        /// The reported state: `up`, `slow`, `degraded`, `down` or `unknown`.
        ///
        /// Kept as the raw string and mapped through `UptimeStatus.init(apiValue:)`,
        /// so an unrecognised value degrades to `.unknown` instead of failing the whole
        /// response. Optional for the same reason.
        public let currentStatus: String?

        /// When the API last checked this project.
        public let lastCheckedAt: Date?
    }

    /// Decodes a response body into service rows.
    ///
    /// - Parameter data: The raw response body. It is never logged: it may contain
    ///   infrastructure detail, and error messages must not carry it either.
    /// - Returns: One entry per project, in the order the API sent them. An empty
    ///   `projects` array yields no rows and is not an error.
    /// - Throws: `DecodingError` when the body is not JSON, or is not the documented
    ///   envelope — including when `data` or `projects` is absent.
    public static func decode(_ data: Data) throws -> [UptimeService] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(timestamp(from:))

        return try decoder.decode(Response.self, from: data).data.projects.map { project in
            UptimeService(
                name: project.name,
                status: UptimeStatus(apiValue: project.currentStatus),
                lastCheckedAt: project.lastCheckedAt
            )
        }
    }

    /// Reads an ISO 8601 timestamp, with or without fractional seconds.
    ///
    /// The documented example carries milliseconds (`2026-06-13T12:00:00.000Z`), which
    /// `ISO8601DateFormatter` rejects unless it is told to expect them. Both spellings
    /// are accepted so a timestamp that lands on a whole second does not fail the parse.
    private static func timestamp(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)

        for formatter in [fractionalSecondsFormatter, wholeSecondsFormatter] {
            if let date = formatter.date(from: raw) { return date }
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Timestamp is not an ISO 8601 date"
        )
    }

    private static let fractionalSecondsFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let wholeSecondsFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
