import Foundation

/// One reading of the current weather: a temperature, and the condition to draw
/// beside it.
///
/// The condition is optional and the temperature is not. The temperature is the
/// line the design reference asks for; the condition is an addition to it, and a
/// reading whose WMO code is outside the mapped set still shows its temperature.
///
/// Declared `nonisolated`: the project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION =
/// MainActor`, so without this the decode of a response would run on the main
/// actor behind the display.
nonisolated public struct WeatherSnapshot: Equatable, Sendable {

    /// The current air temperature.
    public let temperature: TemperatureReading

    /// What the sky is doing, or `nil` when the service reported a code the
    /// display does not cover.
    public let condition: WeatherCondition?

    /// Creates a snapshot.
    public init(temperature: TemperatureReading, condition: WeatherCondition?) {
        self.temperature = temperature
        self.condition = condition
    }
}

// MARK: - Response decoding

/// Decodes the payload of Open-Meteo's
/// `current=temperature_2m,weather_code` forecast request.
///
/// The response shape was verified against the live endpoint:
///
/// ```json
/// {
///   "current_units": { "time": "iso8601", "temperature_2m": "°C", "weather_code": "wmo code" },
///   "current": { "time": "2026-08-30T09:00", "temperature_2m": 21.3, "weather_code": 3 }
/// }
/// ```
///
/// The temperature unit is checked rather than assumed. Celsius is the service's
/// default and the request does not ask for anything else, but the clock draws a
/// literal `°C`, so a response in another unit would silently mislabel the number.
/// Such a response is treated as malformed, which leaves the line absent — the
/// same outcome as any other failure.
///
/// The weather code is not treated that way. A missing or unmapped code costs
/// only the indicator, so it yields a snapshot with no condition rather than an
/// error, and the temperature is still shown.
nonisolated public enum WeatherResponseDecoder {

    /// The unit string the display's hardcoded `°C` suffix is correct for.
    public static let expectedUnit = "°C"

    /// Reads a snapshot out of a response body.
    ///
    /// - Parameter data: The raw response body.
    /// - Returns: The current temperature, and the condition if the code maps.
    /// - Throws: `Failure` when the body carries no usable Celsius reading.
    public static func decode(_ data: Data) throws -> WeatherSnapshot {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw Failure.malformed
        }

        if let unit = payload.currentUnits?.temperature, unit != expectedUnit {
            throw Failure.unexpectedUnit(unit)
        }

        guard let temperature = TemperatureReading(celsius: payload.current.temperature) else {
            throw Failure.malformed
        }

        let condition = payload.current.weatherCode.flatMap(WeatherCondition.init(wmoCode:))

        return WeatherSnapshot(temperature: temperature, condition: condition)
    }

    /// Why a response did not yield a snapshot.
    public enum Failure: Error, Equatable, Sendable {

        /// The body was not the documented shape, or carried a temperature that
        /// has no display form.
        case malformed

        /// The body reported a temperature unit other than degrees Celsius.
        case unexpectedUnit(String)
    }

    /// The subset of the response the app reads. Every other field the service
    /// sends — the elevation, the timezone, the generation time — is ignored.
    private struct Payload: Decodable {

        struct Current: Decodable {
            let temperature: Double
            let weatherCode: Int?

            private enum CodingKeys: String, CodingKey {
                case temperature = "temperature_2m"
                case weatherCode = "weather_code"
            }
        }

        struct Units: Decodable {
            let temperature: String?

            private enum CodingKeys: String, CodingKey {
                case temperature = "temperature_2m"
            }
        }

        let current: Current
        let currentUnits: Units?

        private enum CodingKeys: String, CodingKey {
            case current
            case currentUnits = "current_units"
        }
    }
}
