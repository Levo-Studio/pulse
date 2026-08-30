import Foundation

/// The single line of weather the clock screen shows: an air temperature in
/// degrees Celsius.
///
/// The design reference's `01 CLOCK` frame renders it as `21°C` — a whole number
/// with no space and no decimal — so the reading carries the value it was given
/// and formats it only for display.
///
/// Declared `nonisolated`: the project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION =
/// MainActor`, so without this the decode of a response would run on the main actor
/// behind the display.
nonisolated public struct TemperatureReading: Equatable, Sendable {

    /// Air temperature in degrees Celsius, as reported by the weather service.
    public let celsius: Double

    /// Creates a reading.
    ///
    /// - Parameter celsius: Air temperature in degrees Celsius. Must be finite;
    ///   a non-finite value has no display form and is rejected.
    public init?(celsius: Double) {
        guard celsius.isFinite else { return nil }
        self.celsius = celsius
    }

    /// The reading as the reference draws it — a whole number, the degree sign,
    /// and `C`, for example `21°C`.
    ///
    /// Rounded to the nearest whole degree rather than truncated, so 21.6 reads as
    /// `22` and not `21`, and a half degree rounds away from zero in both
    /// directions — 21.5 is `22` and -17.5 is `-18`. The conversion to `Int` also
    /// removes a negative zero, so a reading just below freezing point reads
    /// `0°C` rather than `-0°C`.
    ///
    /// U+00B0 DEGREE SIGN is present in the bundled Silkscreen face — glyph 190,
    /// advance 0.625 em, drawn as a hollow square from 0.25 to 0.625 em above the
    /// baseline — so the line renders in the pixel typeface with no substitution.
    public var displayText: String {
        // Clamped before the conversion: `Int(_:)` traps on a value outside its
        // range, and the bounds are far outside any temperature the service reports.
        let whole = Int(min(max(celsius.rounded(), -999), 999))
        return "\(whole)°C"
    }
}
