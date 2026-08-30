import SwiftUI

/// The CLOCK screen: the time of day, the date beneath it, and the local
/// temperature beneath that.
///
/// Transcribed from the `01 CLOCK` frame of `design/Pulse.dc.html` — content
/// centred in the frame, time at reference size 70 with 2 units of tracking in
/// `PixelTheme.primary`, date at size 16 with 5 units of tracking in
/// `PixelTheme.muted`, and 20 reference units between the two lines. The
/// temperature repeats the date's type at the same size, tracking and colour,
/// with the reference's additional 26 units of top margin on top of that 20 unit
/// gap. All sizes pass through `PixelMetrics`, so the screen holds its
/// proportions on any device. Drawn flat: the reference is labelled `NO GLOW`.
///
/// The temperature is the only part of the screen that can be absent. When
/// location is refused or unavailable, or the lookup fails, the line is simply
/// not drawn and the screen renders exactly as time plus date — the reference
/// has no failure state for it, and an ambient display should not nag. Weather
/// and location work never blocks, delays or degrades the time and the date,
/// which come from a separate ticker.
public struct ClockScreen: View {

    @Environment(\.pixelMetrics) private var metrics
    @Environment(\.activeScreen) private var activeScreen
    @Environment(\.scenePhase) private var scenePhase

    @State private var ticker = ClockTicker()
    @State private var weather = ClockWeatherModel()

    /// Creates the screen.
    public init() {}

    public var body: some View {
        PixelScreenBackdrop(spacing: 20) {
            PixelLabel(
                ticker.reading.time,
                size: 70,
                tracking: 2,
                color: PixelTheme.primary,
                // The reference sets `line-height: 1` on the time, so the 20 units
                // below it are measured from a one-em box, not from the taller box
                // the face asks for.
                lineBox: .tight
            )

            PixelLabel(
                ticker.reading.date,
                size: 16,
                tracking: 5,
                color: PixelTheme.muted
            )

            if let temperature = weather.temperatureText {
                // The reference gives this line `margin-top: 26` on top of the
                // frame's 20 unit gap, so the drop below the date is deliberately
                // larger than the drop from the time to the date.
                PixelLabel(temperature, size: 16, tracking: 5, color: PixelTheme.muted)
                    .padding(.top, metrics(26))
            }
        }
        .accessibilityElement(children: .combine)
        .onAppear { synchroniseTicker() }
        .onDisappear { ticker.stop() }
        .onChange(of: activeScreen) { synchroniseTicker() }
        .onChange(of: scenePhase) { synchroniseTicker() }
        .task(id: isVisible) {
            guard isVisible else { return }
            await weather.run()
        }
    }

    /// Whether the screen is the one the user is actually looking at.
    ///
    /// The pager may keep a page alive off-screen, and the app may be in the
    /// background with the view still mounted; in either case the clock has no
    /// reason to tick and no reason to hold the network or the location hardware.
    private var isVisible: Bool {
        activeScreen == .clock && scenePhase == .active
    }

    private func synchroniseTicker() {
        if isVisible {
            // `start` also refreshes, so a screen returning to view never shows a
            // stale minute from before it was paged away.
            ticker.start()
        } else {
            ticker.stop()
        }
    }
}

/// The temperature line's state: the reading currently on display, when it was
/// taken, and whether there is any point asking for another.
///
/// The model exists so the clock's display code stays a transcription of the
/// reference. It owns three decisions:
///
/// - **Absence over error.** Every failure — refused authorisation, no fix, an
///   unreachable service, an unreadable body — leaves `temperatureText` `nil`,
///   which the screen renders as no line at all. There is no error string, no
///   placeholder and no dash anywhere in this type.
/// - **A cached reading survives paging.** The last successful reading is kept, so
///   returning to the clock shows the previous temperature immediately rather than
///   blanking the line while a new lookup runs. It is dropped once it is older
///   than `staleAfter`, so a long outage ends in an absent line rather than a
///   wrong one.
/// - **A refusal ends the loop.** Once the user has declined, no further request
///   is made for as long as the screen stays in view. Paging back restarts the
///   loop, so authorisation granted in Settings is picked up on the next visit.
///
/// The location provider and the temperature source are injected, with the real
/// ones as defaults, so every one of those paths is reachable from tests without a
/// prompt, a fix, or a network.
@MainActor
@Observable
final class ClockWeatherModel {

    /// How long between lookups while the clock is in view.
    ///
    /// Thirty minutes. Open-Meteo advances its `current` block on a 15 minute grid,
    /// so anything faster re-fetches values that have not changed; the display
    /// shows whole degrees, which move far more slowly than that; and this is an
    /// ambient screen that may be left on for hours, where two requests an hour is
    /// a courteous load on a free, unauthenticated open-data service. The first
    /// lookup happens immediately when the screen becomes active, so the interval
    /// never delays the first reading.
    static let refreshInterval: TimeInterval = 30 * 60

    /// How old a cached reading may get before it is dropped.
    ///
    /// Three hours. Long enough that a brief outage or a tunnel does not blank the
    /// line, short enough that the screen never presents this morning's temperature
    /// as the current one.
    nonisolated static let defaultStaleAfter: TimeInterval = 3 * 60 * 60

    /// This model's staleness limit. Injectable so the expiry path is reachable
    /// from a test without waiting three hours for it.
    let staleAfter: TimeInterval

    /// The temperature as the screen should draw it, or `nil` when there is
    /// nothing to draw.
    private(set) var temperatureText: String?

    /// When the displayed reading was taken.
    private var lastSuccess: Date?

    /// When a lookup was last attempted, successfully or not.
    private var lastAttempt: Date?

    /// Set once the user has refused; stops the loop for this visit.
    private var isRefused = false

    private let location: CoarseLocationProviding
    private let source: TemperatureSource

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - location: Where the coordinate comes from. `nil` builds the real
    ///     CoreLocation provider, which cannot be a default argument because those
    ///     are evaluated outside the main actor it is confined to.
    ///   - source: Where the temperature comes from.
    ///   - staleAfter: How old a cached reading may get before it is dropped.
    init(
        location: CoarseLocationProviding? = nil,
        source: TemperatureSource = OpenMeteoClient(),
        staleAfter: TimeInterval = ClockWeatherModel.defaultStaleAfter
    ) {
        self.location = location ?? CoreLocationProvider()
        self.source = source
        self.staleAfter = staleAfter
    }

    /// Keeps the reading current until the enclosing task is cancelled.
    ///
    /// The screen starts this when the clock becomes the active screen and the app
    /// is in the foreground, and SwiftUI cancels it when either stops being true.
    func run() async {
        // A refusal is reconsidered once per visit rather than never: the user may
        // have granted authorisation in Settings since the last time.
        isRefused = false

        while !Task.isCancelled {
            if isRefreshDue {
                await refresh()
            }

            guard !isRefused else { return }

            let wait = max(1, secondsUntilRefresh)
            do {
                try await Task.sleep(for: .seconds(wait))
            } catch {
                return
            }
        }
    }

    /// Performs a single lookup, whatever the schedule says.
    func refresh() async {
        lastAttempt = Date()

        let outcome = await location.coarseCoordinate()

        switch outcome {
        case .denied:
            // A refusal is the one failure that clears a cached reading: the user
            // has withdrawn the input the line depends on, so it should go away
            // rather than linger.
            isRefused = true
            discard()
            return
        case .unavailable:
            expireIfStale()
            return
        case .coordinate(let coordinate):
            await load(at: coordinate)
        }
    }

    /// Whether a lookup is due, from the timestamp of the last attempt rather than
    /// from an accumulating counter, so a screen paged away for an hour refreshes
    /// once on return instead of replaying missed ticks.
    private var isRefreshDue: Bool {
        guard !isRefused else { return false }
        guard let lastAttempt else { return true }
        return Date().timeIntervalSince(lastAttempt) >= Self.refreshInterval
    }

    /// Whole seconds until the next lookup.
    private var secondsUntilRefresh: Int {
        guard let lastAttempt else { return 0 }
        let elapsed = max(0, Date().timeIntervalSince(lastAttempt))
        return max(0, Int((Self.refreshInterval - elapsed).rounded(.up)))
    }

    private func load(at coordinate: Coordinate) async {
        do {
            let fetched = try await source.temperature(at: coordinate)
            temperatureText = fetched.displayText
            lastSuccess = Date()
        } catch is CancellationError {
            // The loop was cancelled mid-flight; the cached line stays as it was.
        } catch {
            // Every other failure is the same failure as far as the display is
            // concerned. Nothing is logged: a response body from a weather service
            // is not worth a line in the console, and the error is not actionable.
            expireIfStale()
        }
    }

    /// Drops the cached reading once it is too old to stand for the present.
    private func expireIfStale() {
        guard let lastSuccess else { return }
        if Date().timeIntervalSince(lastSuccess) >= staleAfter {
            discard()
        }
    }

    private func discard() {
        temperatureText = nil
        lastSuccess = nil
    }
}

#Preview {
    ClockScreen()
        .background(PixelTheme.background)
}
