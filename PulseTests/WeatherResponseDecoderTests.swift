import Foundation
import Testing

@testable import Pulse

/// Verification of `WeatherResponseDecoder` against Open-Meteo's documented
/// response shape, and of the display form the clock draws from it.
///
/// The payloads are transcribed from the live endpoint's answer to
/// `?latitude=52.52&longitude=13.41&current=temperature_2m,weather_code`. Nothing
/// here touches the network, and the request carries no credential to leak into a
/// fixture.
struct WeatherResponseDecoderTests {

    // MARK: - Decoding

    @Test("A documented response yields the temperature and the condition")
    func documentedResponse() throws {
        let json = """
        {"latitude":52.52,"longitude":13.419998,"generationtime_ms":0.03,
         "utc_offset_seconds":0,"timezone":"GMT","elevation":38.0,
         "current_units":{"time":"iso8601","interval":"seconds","temperature_2m":"°C","weather_code":"wmo code"},
         "current":{"time":"2026-08-30T09:00","interval":900,"temperature_2m":21.3,"weather_code":3}}
        """

        let snapshot = try WeatherResponseDecoder.decode(Data(json.utf8))

        #expect(snapshot.temperature.celsius == 21.3)
        #expect(snapshot.temperature.displayText == "21°C")
        #expect(snapshot.condition == .cloudy)
    }

    @Test("A response without the units block is still read")
    func missingUnits() throws {
        let json = #"{"current":{"temperature_2m":-4.0,"weather_code":71}}"#

        let snapshot = try WeatherResponseDecoder.decode(Data(json.utf8))

        #expect(snapshot.temperature.displayText == "-4°C")
        #expect(snapshot.condition == .snow)
    }

    @Test("A missing weather code costs the indicator, not the temperature")
    func missingWeatherCode() throws {
        let json = #"{"current":{"temperature_2m":12.0}}"#

        let snapshot = try WeatherResponseDecoder.decode(Data(json.utf8))

        #expect(snapshot.temperature.displayText == "12°C")
        #expect(snapshot.condition == nil)
    }

    @Test("An unmapped weather code costs the indicator, not the temperature")
    func unmappedWeatherCode() throws {
        // 4 is "smoke" in WMO 4677 and is not one of the six conditions drawn.
        let json = #"{"current":{"temperature_2m":12.0,"weather_code":4}}"#

        let snapshot = try WeatherResponseDecoder.decode(Data(json.utf8))

        #expect(snapshot.temperature.displayText == "12°C")
        #expect(snapshot.condition == nil)
    }

    @Test("A unit other than Celsius is rejected rather than mislabelled")
    func unexpectedUnit() {
        let json = #"{"current_units":{"temperature_2m":"°F"},"current":{"temperature_2m":70.0}}"#

        #expect(throws: WeatherResponseDecoder.Failure.unexpectedUnit("°F")) {
            try WeatherResponseDecoder.decode(Data(json.utf8))
        }
    }

    @Test("A body that is not the documented shape is malformed", arguments: [
        #"{"current":{}}"#,
        #"{"current":{"temperature_2m":"warm"}}"#,
        #"{"hourly":{"temperature_2m":[21.3]}}"#,
        #"{"error":true,"reason":"Latitude must be in range of -90 to 90"}"#,
        "not json at all",
        ""
    ])
    func malformedBodies(json: String) {
        #expect(throws: WeatherResponseDecoder.Failure.malformed) {
            try WeatherResponseDecoder.decode(Data(json.utf8))
        }
    }

    // MARK: - Display form

    @Test("The reading renders as a whole number with the degree sign", arguments: [
        (21.0, "21°C"), (21.3, "21°C"), (21.6, "22°C"), (-0.4, "0°C"),
        (-0.6, "-1°C"), (-17.5, "-18°C"), (0.0, "0°C")
    ])
    func displayForm(celsius: Double, expected: String) throws {
        let reading = try #require(TemperatureReading(celsius: celsius))

        #expect(reading.displayText == expected)
    }

    @Test("The degree sign the display uses is U+00B0, which the bundled face carries")
    func degreeSignCodePoint() throws {
        let reading = try #require(TemperatureReading(celsius: 21))

        #expect(reading.displayText.unicodeScalars.contains("\u{00B0}"))
        // Uppercasing is applied by `PixelLabel` and must not disturb the suffix.
        #expect(reading.displayText.uppercased() == reading.displayText)
    }

    @Test("A non-finite value has no display form and is refused")
    func nonFiniteValue() {
        #expect(TemperatureReading(celsius: .nan) == nil)
        #expect(TemperatureReading(celsius: .infinity) == nil)
    }
}

/// Verification of the coordinate value type and the request built from it.
struct CoordinateTests {

    @Test("An out-of-range or non-finite pair is refused")
    func invalidPairs() {
        #expect(Coordinate(latitude: .nan, longitude: .nan) == nil)
        #expect(Coordinate(latitude: 91, longitude: 0) == nil)
        #expect(Coordinate(latitude: 0, longitude: 181) == nil)
    }

    @Test("Coarsening rounds to two decimal places")
    func coarsening() throws {
        let precise = try #require(Coordinate(latitude: 52.516_667, longitude: 13.388_888))

        #expect(precise.coarsened == Coordinate(latitude: 52.52, longitude: 13.39))
    }

    @Test("The request carries only the two coarsened coordinates and the field list")
    func requestQuery() throws {
        let coordinate = try #require(Coordinate(latitude: 52.516_667, longitude: -13.388_888))

        let url = OpenMeteoClient.url(for: coordinate)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = try #require(components.queryItems)

        #expect(components.host == "api.open-meteo.com")
        #expect(components.path == "/v1/forecast")
        #expect(items.count == 3)
        #expect(items.first { $0.name == "latitude" }?.value == "52.52")
        #expect(items.first { $0.name == "longitude" }?.value == "-13.39")
        #expect(items.first { $0.name == "current" }?.value == "temperature_2m,weather_code")

        // The service needs no credential, so the URL must never grow one.
        let query = components.query ?? ""
        for forbidden in ["key", "token", "apikey", "appid"] {
            #expect(!query.lowercased().contains(forbidden))
        }
    }
}
