import Foundation
import Testing

@testable import Pulse

/// Verification that the clock's temperature line degrades by disappearing.
///
/// The brief for this screen is unusually strict: there is no error text, no
/// placeholder and no dash. Every path that does not end in a reading must end in
/// `temperatureText == nil`, which the screen renders as no line at all. These
/// tests walk each of those paths with a stubbed location provider and a stubbed
/// temperature source, so none of them touches CoreLocation or the network.
@MainActor
struct ClockWeatherModelTests {

    // MARK: - Stubs

    /// A location provider that answers with whatever the test asked for, and
    /// counts how often it was asked.
    private final class StubLocation: CoarseLocationProviding {
        var outcome: CoarseLocationOutcome
        private(set) var callCount = 0

        init(_ outcome: CoarseLocationOutcome) {
            self.outcome = outcome
        }

        func coarseCoordinate() async -> CoarseLocationOutcome {
            callCount += 1
            return outcome
        }
    }

    /// A temperature source that answers with whatever the test asked for.
    private final class StubSource: TemperatureSource, @unchecked Sendable {
        enum Answer {
            case reading(Double)
            case failure(any Error)
        }

        var answer: Answer
        private(set) var callCount = 0

        init(_ answer: Answer) {
            self.answer = answer
        }

        func temperature(at coordinate: Coordinate) async throws -> TemperatureReading {
            callCount += 1
            switch answer {
            case .reading(let celsius):
                guard let reading = TemperatureReading(celsius: celsius) else {
                    throw OpenMeteoClient.Failure.malformedResponse
                }
                return reading
            case .failure(let error):
                throw error
            }
        }
    }

    private static func coordinate() throws -> Coordinate {
        try #require(Coordinate(latitude: 52.52, longitude: 13.41))
    }

    // MARK: - The line is present

    @Test("A fix and a reading put the temperature on screen")
    func successfulLookup() async throws {
        let model = ClockWeatherModel(
            location: StubLocation(.coordinate(try Self.coordinate())),
            source: StubSource(.reading(21.3))
        )

        await model.refresh()

        #expect(model.temperatureText == "21°C")
    }

    // MARK: - The line is absent

    @Test("Nothing is shown before the first lookup")
    func beforeFirstLookup() {
        let model = ClockWeatherModel(
            location: StubLocation(.denied),
            source: StubSource(.reading(21))
        )

        #expect(model.temperatureText == nil)
    }

    @Test("A refused authorisation leaves no line and never reaches the network")
    func authorisationRefused() async {
        let source = StubSource(.reading(21))
        let model = ClockWeatherModel(location: StubLocation(.denied), source: source)

        await model.refresh()

        #expect(model.temperatureText == nil)
        #expect(source.callCount == 0)
    }

    @Test("No fix leaves no line and never reaches the network")
    func noFix() async {
        let source = StubSource(.reading(21))
        let model = ClockWeatherModel(location: StubLocation(.unavailable), source: source)

        await model.refresh()

        #expect(model.temperatureText == nil)
        #expect(source.callCount == 0)
    }

    @Test("A failing lookup with nothing cached leaves no line", arguments: [
        OpenMeteoClient.Failure.unreachable,
        OpenMeteoClient.Failure.server(status: 429),
        OpenMeteoClient.Failure.server(status: 500),
        OpenMeteoClient.Failure.malformedResponse
    ])
    func failingLookup(failure: OpenMeteoClient.Failure) async throws {
        let model = ClockWeatherModel(
            location: StubLocation(.coordinate(try Self.coordinate())),
            source: StubSource(.failure(failure))
        )

        await model.refresh()

        #expect(model.temperatureText == nil)
    }

    // MARK: - The cached reading

    @Test("A later failure keeps the last reading rather than blanking the line")
    func cacheSurvivesFailure() async throws {
        let source = StubSource(.reading(21))
        let model = ClockWeatherModel(
            location: StubLocation(.coordinate(try Self.coordinate())),
            source: source
        )

        await model.refresh()
        source.answer = .failure(OpenMeteoClient.Failure.unreachable)
        await model.refresh()

        #expect(model.temperatureText == "21°C")
    }

    @Test("A cached reading is dropped once it is older than the staleness limit")
    func cacheExpires() async throws {
        let source = StubSource(.reading(21))
        let model = ClockWeatherModel(
            location: StubLocation(.coordinate(try Self.coordinate())),
            source: source,
            staleAfter: 0
        )

        await model.refresh()
        #expect(model.temperatureText == "21°C")

        source.answer = .failure(OpenMeteoClient.Failure.unreachable)
        await model.refresh()

        #expect(model.temperatureText == nil)
    }

    @Test("A refusal clears a reading that is already on screen")
    func refusalClearsCache() async throws {
        let location = StubLocation(.coordinate(try Self.coordinate()))
        let model = ClockWeatherModel(location: location, source: StubSource(.reading(21)))

        await model.refresh()
        #expect(model.temperatureText == "21°C")

        location.outcome = .denied
        await model.refresh()

        #expect(model.temperatureText == nil)
    }

    @Test("A cancelled lookup keeps the line as it was")
    func cancellationIsNotAFailure() async throws {
        let source = StubSource(.reading(21))
        let model = ClockWeatherModel(
            location: StubLocation(.coordinate(try Self.coordinate())),
            source: source
        )

        await model.refresh()
        source.answer = .failure(CancellationError())
        await model.refresh()

        #expect(model.temperatureText == "21°C")
    }

    // MARK: - The loop

    @Test("The loop takes one reading and then waits out the refresh interval")
    func loopRefreshesOnceThenWaits() async throws {
        let location = StubLocation(.coordinate(try Self.coordinate()))
        let model = ClockWeatherModel(location: location, source: StubSource(.reading(21)))

        let loop = Task { await model.run() }
        // Long enough for the immediate first pass, far short of the interval.
        try await Task.sleep(for: .milliseconds(200))
        loop.cancel()
        _ = await loop.value

        #expect(model.temperatureText == "21°C")
        #expect(location.callCount == 1)
    }

    @Test("The loop stops asking once the user has refused")
    func loopStopsAfterRefusal() async {
        let location = StubLocation(.denied)
        let model = ClockWeatherModel(location: location, source: StubSource(.reading(21)))

        await model.run()

        #expect(model.temperatureText == nil)
        #expect(location.callCount == 1)
    }
}
