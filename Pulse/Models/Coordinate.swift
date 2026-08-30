import Foundation

/// A point on the globe, used only to ask a weather service what the temperature
/// is there.
///
/// The value is held in memory for the duration of a single lookup and then
/// dropped. It is never written to disk, never put in `UserDefaults` or the
/// Keychain, and never logged — the app has no reason to remember where the user
/// was, and a temperature reading does not need a precise fix to begin with.
///
/// Declared `nonisolated`: the project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION =
/// MainActor`, so without this the type would be pinned to the main actor and the
/// request that consumes it could not be built off it.
nonisolated public struct Coordinate: Equatable, Sendable {

    /// Degrees north of the equator, `-90...90`.
    public let latitude: Double

    /// Degrees east of the prime meridian, `-180...180`.
    public let longitude: Double

    /// Creates a coordinate, rejecting values outside the valid ranges.
    ///
    /// CoreLocation reports `kCLLocationCoordinate2DInvalid` — a pair of `NaN`s —
    /// when it has no usable fix, and a `NaN` would otherwise be formatted into a
    /// query string and sent to the weather service. Validating here means the
    /// rest of the app can treat a `Coordinate` as usable without re-checking.
    ///
    /// - Returns: `nil` when either value is not finite or is out of range.
    public init?(latitude: Double, longitude: Double) {
        guard latitude.isFinite, longitude.isFinite else { return nil }
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }

        self.latitude = latitude
        self.longitude = longitude
    }

    /// The coordinate rounded to two decimal places.
    ///
    /// Two decimals is roughly a 1.1 km grid at the equator and less than that
    /// away from it, which is finer than any weather model the app queries and
    /// far coarser than a street address. The lookup sends this rather than the
    /// raw fix so the request itself carries no more precision than the answer
    /// needs.
    public var coarsened: Coordinate {
        // The rounding cannot push either value out of range, so the failable
        // initialiser cannot return `nil` here; the original is returned rather
        // than force-unwrapping to make that structural instead of asserted.
        Coordinate(
            latitude: (latitude * 100).rounded() / 100,
            longitude: (longitude * 100).rounded() / 100
        ) ?? self
    }
}
