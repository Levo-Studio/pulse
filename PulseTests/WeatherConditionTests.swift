import Foundation
import Testing

@testable import Pulse

/// Verification of the WMO code mapping and of the pixel figures drawn from it.
///
/// The mapping is the one place a service value becomes a drawn figure, so the
/// table in its documentation is checked against the implementation rather than
/// trusted, and the unmapped case is pinned: an unknown code must cost the
/// indicator and nothing else.
struct WeatherConditionTests {

    // MARK: - The mapping

    @Test("Every code in the documented table maps to the condition it claims")
    func documentedTable() throws {
        for (condition, codes) in WeatherCondition.mappedCodes {
            for code in codes {
                #expect(WeatherCondition(wmoCode: code) == condition, "code \(code)")
            }
        }
    }

    @Test("The six conditions between them cover every mapped code exactly once")
    func tableIsComplete() {
        let all = WeatherCondition.mappedCodes.values.flatMap { $0 }

        #expect(Set(WeatherCondition.mappedCodes.keys) == Set(WeatherCondition.allCases))
        #expect(all.count == Set(all).count)
    }

    @Test("The headline codes read as expected", arguments: [
        (0, WeatherCondition.clear),
        (1, WeatherCondition.clear),
        (2, WeatherCondition.cloudy),
        (3, WeatherCondition.cloudy),
        (45, WeatherCondition.fog),
        (61, WeatherCondition.rain),
        (66, WeatherCondition.rain),
        (75, WeatherCondition.snow),
        (95, WeatherCondition.thunderstorm)
    ])
    func headlineCodes(code: Int, expected: WeatherCondition) {
        #expect(WeatherCondition(wmoCode: code) == expected)
    }

    @Test("Freezing drizzle and freezing rain fall as rain, not as snow")
    func freezingPrecipitationIsRain() {
        for code in [56, 57, 66, 67] {
            #expect(WeatherCondition(wmoCode: code) == .rain, "code \(code)")
        }
    }

    @Test("An unmapped code yields no condition rather than a guess", arguments: [
        4, 5, 10, 30, 44, 50, 70, 79, 84, 90, 97, 100, -1, Int.max
    ])
    func unmappedCode(code: Int) {
        // The indicator is then simply not drawn. The temperature is unaffected —
        // see `WeatherResponseDecoderTests.unmappedWeatherCode`.
        #expect(WeatherCondition(wmoCode: code) == nil)
    }

    // MARK: - The figures

    @Test("Every condition has a figure of the declared grid size")
    func figureDimensions() {
        for condition in WeatherCondition.allCases {
            let bitmap = PixelWeatherIcon.bitmap(for: condition)

            #expect(bitmap.count == PixelWeatherIcon.rows, "\(condition)")
            for row in bitmap {
                #expect(row.count == PixelWeatherIcon.columns, "\(condition)")
            }
        }
    }

    @Test("Every figure is drawn only from the two grid characters, and is not empty")
    func figureAlphabet() {
        for condition in WeatherCondition.allCases {
            let bitmap = PixelWeatherIcon.bitmap(for: condition)
            let characters = Set(bitmap.joined())

            #expect(characters.isSubset(of: [PixelWeatherIcon.filled, "."]), "\(condition)")
            #expect(characters.contains(PixelWeatherIcon.filled), "\(condition)")
        }
    }

    @Test("No two conditions share a figure")
    func figuresAreDistinct() {
        let figures = WeatherCondition.allCases.map { PixelWeatherIcon.bitmap(for: $0) }

        #expect(Set(figures.map { $0.joined() }).count == WeatherCondition.allCases.count)
    }

    @Test("The falling conditions share the cloud and differ only below it")
    func fallingConditionsShareTheCloud() {
        let cloud = PixelWeatherIcon.bitmap(for: .cloudy)

        for condition in [WeatherCondition.rain, .snow, .thunderstorm] {
            let figure = PixelWeatherIcon.bitmap(for: condition)
            // The cloud occupies rows 0 to 3; `cloudy` draws it one row lower so it
            // sits centred on its own, so the shape is compared rather than the rows.
            let cloudRows = Set(cloud.filter { $0.contains(PixelWeatherIcon.filled) })
            let figureRows = Set(figure.prefix(4))

            #expect(cloudRows == figureRows, "\(condition)")
        }
    }
}
