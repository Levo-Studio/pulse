import Foundation

/// The state of a single monitored service, as displayed by the status square on
/// the uptime screen.
///
/// Declared `nonisolated`: the project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION =
/// MainActor`, so without this every type in this file would be main-actor isolated
/// and the response parse would run on the main actor behind the display.
nonisolated public enum UptimeStatus: String, Sendable, CaseIterable {

    /// The service is up.
    case operational

    /// The service is reachable but impaired.
    case degraded

    /// The service is down.
    case down

    /// No usable state was reported for the service.
    case unknown
}

/// One row of the uptime list: a service name and its current state.
nonisolated public struct UptimeService: Sendable, Equatable {

    /// The name shown on the left of the row.
    public let name: String

    /// The state shown as a coloured square on the right of the row.
    public let status: UptimeStatus

    /// Creates a service entry.
    public init(name: String, status: UptimeStatus) {
        self.name = name
        self.status = status
    }
}

// MARK: - Response decoding

/// Decodes the payload of `GET /api/uptime/listall` into `UptimeService` values.
///
/// **The response schema of that endpoint is unverified.** It could only be probed
/// without a key, which answers `401 {"error":"Unauthorized","code":"UNAUTHORIZED"}`,
/// so no successful body has ever been observed. Decoding is therefore deliberately
/// tolerant, and every assumption it makes is collected in this one type:
///
/// - the list may be the top-level JSON value, or wrapped in an object under one of
///   `envelopeKeys`;
/// - each entry's name is read from the first key present out of `nameKeys`;
/// - each entry's state is read from the first key present out of `statusKeys` and
///   mapped through `statusVocabulary`; a string that is not in the vocabulary, or a
///   missing key, yields `.unknown` rather than an error;
/// - a non-empty list none of whose entries yielded a row is an error, not an empty
///   result, so an unrecognised name key cannot silently blank the screen.
///
/// Once the real shape is known this is a one-line correction: add the actual key to
/// the relevant list, or replace these lookups with concrete `CodingKeys`.
nonisolated public enum UptimeResponseDecoder {

    /// Object keys that may wrap the list of services.
    public static let envelopeKeys = [
        "data", "services", "results", "items", "monitors", "list", "checks"
    ]

    /// Entry keys that may carry the service name, in order of preference.
    public static let nameKeys = [
        "name", "service", "servicename", "service_name", "displayname", "display_name",
        "friendlyname", "friendly_name", "title", "label", "monitor"
    ]

    /// Entry keys that may carry the service state, in order of preference.
    public static let statusKeys = [
        "status", "state", "health", "currentstatus", "current_status",
        "uptimestatus", "uptime_status", "up", "online", "healthy"
    ]

    /// Maps a normalised state token onto a displayed status.
    ///
    /// Normalisation lowercases the token and collapses spaces and hyphens into
    /// underscores, so `"Partial Outage"` and `"partial-outage"` both arrive here as
    /// `partial_outage`. Booleans and numbers are normalised to `"true"` / `"false"`
    /// and their decimal text before lookup.
    public static let statusVocabulary: [String: UptimeStatus] = [
        // Up
        "up": .operational, "ok": .operational, "operational": .operational,
        "online": .operational, "healthy": .operational, "running": .operational,
        "active": .operational, "pass": .operational, "passing": .operational,
        "available": .operational, "green": .operational, "good": .operational,
        "true": .operational, "1": .operational,
        // Impaired
        "degraded": .degraded, "degraded_performance": .degraded, "warning": .degraded,
        "warn": .degraded, "partial": .degraded, "partial_outage": .degraded,
        "impaired": .degraded, "slow": .degraded, "unstable": .degraded,
        "amber": .degraded, "yellow": .degraded, "orange": .degraded,
        // Down
        "down": .down, "offline": .down, "error": .down, "fail": .down,
        "failed": .down, "failing": .down, "critical": .down, "outage": .down,
        "major_outage": .down, "unhealthy": .down, "unavailable": .down,
        "stopped": .down, "red": .down, "false": .down, "0": .down,
        // Explicitly unknown
        "unknown": .unknown, "paused": .unknown, "pending": .unknown,
        "maintenance": .unknown, "under_maintenance": .unknown, "none": .unknown
    ]

    /// Decodes a response body into service rows.
    ///
    /// - Parameter data: The raw response body. It is never logged: it may contain
    ///   infrastructure detail, and error messages must not carry it either.
    /// - Returns: One entry per element of the list, in the order the API sent them.
    ///   Entries with no readable name are dropped, since a nameless row cannot be
    ///   rendered; unreadable states become `.unknown`.
    /// - Throws: `DecodingError` when the body is not JSON, is neither an array nor an
    ///   object containing a list under one of `envelopeKeys`, or contains entries none
    ///   of which yielded a row.
    public static func decode(_ data: Data) throws -> [UptimeService] {
        let root = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let entries = list(in: root) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Response is neither a list of services nor an object wrapping one"
                )
            )
        }

        let services = entries.compactMap(service(from:))

        // A payload that names its services with a key outside `nameKeys` would
        // otherwise decode successfully to nothing, emptying the list while the
        // countdown keeps ticking — indistinguishable from monitoring nothing. Since
        // the schema is unverified that is the likeliest real failure, so it is
        // raised instead: the caller keeps the previous list and reports the response
        // as malformed. An API that genuinely returns no services still sends an
        // empty list, which stays valid and empty.
        guard !entries.isEmpty, services.isEmpty else { return services }
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: [],
                debugDescription: "No entry in the response carried a readable service name"
            )
        )
    }

    /// The number of wrapper objects `list(in:)` will look through before giving up.
    ///
    /// A payload nests its list at most a level or two deep in practice; the cap keeps
    /// a deeply nested or self-similar body from walking the whole tree.
    private static let maximumEnvelopeDepth = 3

    /// Finds the array of service entries in a decoded body, looking through at most
    /// `maximumEnvelopeDepth` wrapper objects, as in `{"data":{"services":[…]}}`.
    private static func list(in root: JSONValue, depth: Int = 0) -> [JSONValue]? {
        if case .array(let entries) = root { return entries }
        guard case .object(let fields) = root, depth < maximumEnvelopeDepth else { return nil }

        for key in envelopeKeys {
            guard let value = fields[key] else { continue }
            if case .array(let entries) = value { return entries }
            if case .object = value, let nested = list(in: value, depth: depth + 1) { return nested }
        }
        return nil
    }

    /// Builds a row from one entry, or `nil` when it carries no usable name.
    private static func service(from entry: JSONValue) -> UptimeService? {
        // A list of bare strings is a plausible shape too: names with no state.
        if case .string(let name) = entry {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : UptimeService(name: trimmed, status: .unknown)
        }

        guard case .object(let fields) = entry else { return nil }
        let normalised = Dictionary(
            fields.map { (normaliseKey($0.key), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )

        guard let name = nameKeys.lazy
            .compactMap({ normalised[$0]?.plainText })
            .first(where: { !$0.isEmpty }) else {
            return nil
        }

        let token = statusKeys.lazy
            .compactMap { normalised[$0]?.plainText }
            .first { !$0.isEmpty }

        return UptimeService(name: name, status: status(for: token))
    }

    /// Maps a raw state token onto a status, defaulting to `.unknown`.
    public static func status(for token: String?) -> UptimeStatus {
        guard let token else { return .unknown }
        return statusVocabulary[normaliseKey(token)] ?? .unknown
    }

    /// Lowercases a key or token and collapses separators onto underscores.
    private static func normaliseKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }
}

/// A minimal JSON tree, used so the decoder can inspect a body whose shape is not
/// known ahead of time without resorting to `JSONSerialization` casts.
nonisolated enum JSONValue: Decodable {

    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    /// The scalar rendered as text, or `nil` for containers and null.
    ///
    /// Whole numbers render without a fractional part so an integer state code such
    /// as `1` looks up as `"1"` rather than `"1.0"`.
    var plainText: String? {
        switch self {
        case .string(let value):
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        case .bool(let value):
            return value ? "true" : "false"
        case .number(let value):
            return value == value.rounded() && abs(value) < 1e15
                ? String(Int(value))
                : String(value)
        case .object, .array, .null:
            return nil
        }
    }
}
