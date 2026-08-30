import Foundation

/// The weather conditions the clock screen can draw an indicator for.
///
/// Deliberately small. The indicator is a seven-by-eight pixel figure sitting
/// beside a size 16 line of type, subordinate to the time; a set fine enough to
/// separate light drizzle from moderate rain could not be drawn at that scale and
/// would not be read at that scale either. Six conditions is what the grid can
/// carry legibly.
///
/// Declared `nonisolated`: the project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION =
/// MainActor`, so without this the mapping could not run off the main actor with
/// the rest of the response decode.
nonisolated public enum WeatherCondition: String, Equatable, Sendable, CaseIterable {

    /// Clear or nearly clear sky.
    case clear

    /// Partly cloudy through to overcast.
    case cloudy

    /// Fog or depositing rime fog.
    case fog

    /// Drizzle or rain, freezing or not, steady or in showers.
    case rain

    /// Snow, snow grains, or snow showers.
    case snow

    /// A thunderstorm, with or without hail.
    case thunderstorm
}

// MARK: - WMO weather codes

nonisolated extension WeatherCondition {

    /// The one place the WMO code mapping lives.
    ///
    /// Open-Meteo reports `weather_code` as a WMO 4677 present-weather code. The
    /// full table is far finer than this display can draw, so the codes are
    /// collapsed into `WeatherCondition`:
    ///
    /// | Codes | Condition | WMO meaning |
    /// |---|---|---|
    /// | 0, 1 | `clear` | clear sky, mainly clear |
    /// | 2, 3 | `cloudy` | partly cloudy, overcast |
    /// | 45, 48 | `fog` | fog, depositing rime fog |
    /// | 51, 53, 55 | `rain` | drizzle: light, moderate, dense |
    /// | 56, 57 | `rain` | freezing drizzle: light, dense |
    /// | 61, 63, 65 | `rain` | rain: slight, moderate, heavy |
    /// | 66, 67 | `rain` | freezing rain: light, heavy |
    /// | 80, 81, 82 | `rain` | rain showers: slight, moderate, violent |
    /// | 71, 73, 75 | `snow` | snow fall: slight, moderate, heavy |
    /// | 77 | `snow` | snow grains |
    /// | 85, 86 | `snow` | snow showers: slight, heavy |
    /// | 95 | `thunderstorm` | thunderstorm, slight or moderate |
    /// | 96, 99 | `thunderstorm` | thunderstorm with slight or heavy hail |
    ///
    /// Freezing drizzle and freezing rain are folded into `rain` rather than
    /// `snow`: they fall as liquid, and the indicator says what is coming out of
    /// the sky, not what it does when it lands.
    ///
    /// Anything outside the table — a code the service adds later, or a value that
    /// is not a code at all — yields `nil`. The indicator is then simply not drawn
    /// and the temperature stands on its own, which is the same graceful absence
    /// the rest of this screen uses. It is never guessed at and never drawn as a
    /// question mark.
    ///
    /// - Parameter wmoCode: The value of Open-Meteo's `weather_code` field.
    /// - Returns: The condition to draw, or `nil` for a code this set does not
    ///   cover.
    public init?(wmoCode: Int) {
        switch wmoCode {
        case 0, 1:
            self = .clear
        case 2, 3:
            self = .cloudy
        case 45, 48:
            self = .fog
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82:
            self = .rain
        case 71, 73, 75, 77, 85, 86:
            self = .snow
        case 95, 96, 99:
            self = .thunderstorm
        default:
            return nil
        }
    }

    /// Every WMO code the mapping covers, for the condition it maps to.
    ///
    /// Exposed so the table above can be verified against the implementation
    /// rather than trusted.
    public static let mappedCodes: [WeatherCondition: [Int]] = [
        .clear: [0, 1],
        .cloudy: [2, 3],
        .fog: [45, 48],
        .rain: [51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82],
        .snow: [71, 73, 75, 77, 85, 86],
        .thunderstorm: [95, 96, 99]
    ]
}
