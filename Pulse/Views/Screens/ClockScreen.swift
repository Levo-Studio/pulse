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
/// A double tap on the time reveals seconds and a second double tap hides them
/// again; a single tap does nothing. The choice persists across paging and
/// relaunch. `HH:mm:ss` does not fit the reference's content width at size 70 —
/// see `ClockTimeMetrics` for the measurement and the size the seconds readout
/// uses instead.
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
    @State private var preferences = ClockPreferences()

    /// Creates the screen.
    public init() {}

    public var body: some View {
        // The stack carries no spacing of its own and every gap is stated as top
        // padding on the line below it. That is not a style choice: a `VStack`
        // still charges its spacing for a conditional child whose condition is
        // false, so with `spacing: 20` an absent temperature left a residual gap
        // and shifted the date down. With the gaps in the padding, a line that is
        // not drawn costs nothing, and the two-line clock renders exactly as it
        // did before the temperature existed.
        PixelScreenBackdrop(spacing: 0) {
            PixelLabel(
                preferences.showsSeconds ? ticker.reading.timeWithSeconds : ticker.reading.time,
                size: preferences.showsSeconds ? ClockTimeMetrics.secondsSize : ClockTimeMetrics.size,
                tracking: 2,
                color: PixelTheme.primary,
                // The reference sets `line-height: 1` on the time, so the 20 units
                // below it are measured from a one-em box, not from the taller box
                // the face asks for.
                lineBox: .tight
            )
            // The gesture is scoped to the time's own box: an explicit hit shape
            // stops a tap meant for the weather line from reaching this one, and
            // vice versa. A tap gesture yields to the pager's horizontal drag, so
            // swiping between screens is unaffected.
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { preferences.showsSeconds.toggle() }
            // The readout itself stays the accessibility label — replacing it with
            // the word "Time" would cost a VoiceOver user the value they came for.
            .accessibilityHint("Double tap to show or hide seconds")

            PixelLabel(
                ticker.reading.date,
                size: 16,
                tracking: 5,
                color: PixelTheme.muted
            )
            .padding(.top, metrics(ClockLayout.dateGap))

            if let temperature = weather.temperatureText {
                weatherLine(temperature: temperature)
                    .padding(.top, metrics(ClockLayout.temperatureGap))
            }
        }
        .onAppear { synchroniseTicker() }
        .onDisappear { ticker.stop() }
        .onChange(of: activeScreen) { synchroniseTicker() }
        .onChange(of: scenePhase) { synchroniseTicker() }
        .onChange(of: preferences.showsSeconds, initial: true) {
            ticker.granularity = preferences.showsSeconds ? .second : .minute
        }
        .task(id: isVisible) {
            guard isVisible else { return }
            await weather.run()
        }
    }

    /// The temperature, with the condition indicator to its left when there is one
    /// to draw and the user has not hidden it.
    ///
    /// The indicator sits **on** the temperature line rather than above it. The
    /// reference draws three lines and the screen keeps three: the condition is a
    /// property of the same reading as the temperature, so setting it as a
    /// separate row would give the weather more of the screen than the date has,
    /// and would push the whole block off the vertical centre the reference
    /// composes around. Reading left to right, the figure qualifies the number the
    /// way a unit does.
    ///
    /// The indicator's cell is 2 reference units, so the figure is 14 units tall
    /// against the line's 16 unit type — visibly subordinate to the time at 70,
    /// and no taller than the line it belongs to.
    @ViewBuilder
    private func weatherLine(temperature: String) -> some View {
        HStack(spacing: metrics(WeatherLineMetrics.gap)) {
            if preferences.showsCondition, let condition = weather.condition {
                PixelWeatherIcon(
                    condition: condition,
                    cell: metrics(WeatherLineMetrics.iconCell),
                    color: PixelTheme.muted
                )
            }

            PixelLabel(temperature, size: 16, tracking: 5, color: PixelTheme.muted)
        }
        // The second of the screen's two hit shapes. Scoping it to this line keeps
        // a tap here off the time above, and a tap on the time off this line.
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { preferences.showsCondition.toggle() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(weatherAccessibilityLabel(temperature: temperature))
        .accessibilityHint("Double tap to show or hide the condition")
    }

    private func weatherAccessibilityLabel(temperature: String) -> String {
        guard preferences.showsCondition, let condition = weather.condition else {
            return temperature
        }
        return "\(condition.rawValue), \(temperature)"
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

/// The vertical gaps between the clock's lines, in design-reference units.
///
/// The reference frame lays its three lines out with `gap: 20` on the flex
/// container and an extra `margin-top: 26` on the temperature, so the drop from
/// the date to the temperature is deliberately larger than the drop from the time
/// to the date. Both numbers are stated here as top padding on the line below the
/// gap rather than as stack spacing, because a `VStack` charges its spacing for a
/// conditional child even when the condition is false: with the gap in the
/// spacing, an absent temperature left a residual gap behind and moved the date.
enum ClockLayout {

    /// Space between the time and the date — the reference's flex `gap`.
    static let dateGap: CGFloat = 20

    /// Space between the date and the temperature: the same flex `gap` plus the
    /// temperature's own `margin-top: 26`.
    static let temperatureGap: CGFloat = dateGap + 26
}

/// The measurements of the weather line, in design-reference units.
///
/// The reference draws only the temperature there, at size 16 with 5 units of
/// tracking; the condition indicator is an addition, so its size is derived from
/// the line it joins rather than transcribed.
enum WeatherLineMetrics {

    /// Side of one cell of the indicator's grid.
    ///
    /// Two units, making the eight-by-seven figure 16 units wide and 14 tall. That
    /// is a shade taller than the line's 10 unit cap height and shorter than its
    /// 20.5 unit line box, so the figure sits inside the line rather than
    /// stretching it.
    static let iconCell: CGFloat = 2

    /// Space between the indicator and the temperature.
    ///
    /// Six units, a little wider than the 5 units of tracking inside the number,
    /// so the figure reads as a separate mark rather than as another glyph of the
    /// same word.
    static let gap: CGFloat = 6

    /// Width of the whole line at its widest: the figure, the gap, and a
    /// four-character temperature such as `-21°C` at size 16 with 5 units of
    /// tracking.
    ///
    /// Measured from the bundled face: Silkscreen advances the wide digits
    /// 0.75 em, the degree sign 0.625 em, `C` 0.75 em and the minus 0.625 em.
    static let widestWidth: CGFloat = {
        let icon = CGFloat(PixelWeatherIcon.columns) * iconCell
        let glyphs: CGFloat = (0.625 + 0.75 + 0.75 + 0.625 + 0.75) * 16
        let tracking: CGFloat = 5 * 5
        return icon + gap + glyphs + tracking
    }()
}

/// The arithmetic behind the size of the time readout, in design-reference units.
///
/// The reference frame draws `14:32` at size 70, and that is what the screen
/// ships. It gives no layout for the seconds variant, and `HH:mm:ss` does not fit
/// at that size, so the number that replaces it is kept here with its working
/// rather than left as a literal in the view.
///
/// **The measurement.** Silkscreen has an em of 1000 units. Measured from the
/// bundled `Silkscreen-Regular.ttf` with Core Text, the digits advance 0.75 em
/// except `1`, which advances 0.625, and the colon advances **0.375**. The table
/// below charges every digit 0.75, so every width it gives is an upper bound: a
/// readout containing a `1` comes out narrower than predicted, never wider. With
/// the reference's 2 units of tracking after each character, at size 70:
///
/// - `HH:mm` is `4 * 52.5 + 26.25 + 5 * 2` = **246.25** units.
/// - `HH:mm:ss` is `6 * 52.5 + 2 * 26.25 + 8 * 2` = **383.5** units.
///
/// The content width is the 360 unit frame less the backdrop's 26 units of
/// padding either side — **308** units. That is also the narrowest budget any
/// device offers: `PixelMetrics` scales on the smaller of the two axes, so a
/// display whose width is the limiting axis lands on exactly 308 reference units
/// of content, and a taller, narrower one such as an iPhone SE gets more. So 308
/// is the number to fit, and `HH:mm:ss` at 70 overruns it by 75.5 units — very
/// nearly a quarter of the line — which `PixelLabel` would neither wrap nor
/// compress, pushing the readout off both edges of the screen.
///
/// **What is done instead: size 48, which is the reference's own answer.** The
/// design reference already sets an eight-character readout — the stopwatch's
/// `00:00:00` — and it sets it at 48. Taking the same size here follows the
/// reference's own idiom rather than inventing a number, it makes the app's two
/// eight-character readouts agree, and it leaves real margin:
/// `6 * 36 + 2 * 18 + 8 * 2` = **268** units against 308.
///
/// Solving the width against the budget gives a ceiling of 55.6, so sizes in the
/// low fifties do fit arithmetically. None was used: none of them is a number the
/// design already contains, and the largest of them scrape the limit. The minute
/// readout is untouched at 70, so the screen as the reference draws it is exactly
/// as it was.
///
/// The alternative — keeping `HH:mm` at 70 and setting the seconds beside it at a
/// smaller size — was rejected because it changes the shape of the headline
/// rather than its size, and leaves two type sizes on the screen's one dominant
/// line.
enum ClockTimeMetrics {

    /// Width of the reference frame's content area: the 360 unit frame less the
    /// backdrop's 26 units of padding either side. Also the narrowest budget any
    /// supported display offers, in reference units.
    static let contentWidth: CGFloat = 360 - (2 * 26)

    /// Advance of one digit, as a fraction of the em.
    ///
    /// The wide digit. `1` advances `oneAdvance` instead, so charging every digit
    /// this much makes the widths below upper bounds rather than estimates.
    static let digitAdvance: CGFloat = 0.75

    /// Advance of the digit `1`, as a fraction of the em.
    ///
    /// Deliberately not used by `width(digits:colons:size:)`, which budgets for
    /// the wide digit throughout. Recorded so that bound stays auditable.
    static let oneAdvance: CGFloat = 0.625

    /// Advance of the colon, as a fraction of the em.
    static let colonAdvance: CGFloat = 0.375

    /// Tracking applied to the time, per the reference.
    static let tracking: CGFloat = 2

    /// Size of the `HH:mm` readout, straight from the reference.
    static let size: CGFloat = 70

    /// Size of the `HH:mm:ss` readout.
    ///
    /// The size the reference itself sets its own eight-character readout in —
    /// the stopwatch's `00:00:00`.
    static let secondsSize: CGFloat = 48

    /// Width of a readout made of `digits` digits and `colons` colons at `size`.
    ///
    /// An upper bound: every digit is charged the wide advance.
    static func width(digits: Int, colons: Int, size: CGFloat) -> CGFloat {
        let glyphs = CGFloat(digits) * digitAdvance + CGFloat(colons) * colonAdvance
        return glyphs * size + CGFloat(digits + colons) * tracking
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
/// The location provider and the weather source are injected, with the real
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

    /// The condition to draw beside the temperature, or `nil` when the service
    /// reported a code the display does not cover.
    ///
    /// Always `nil` when `temperatureText` is: the indicator belongs to the
    /// temperature line and never appears without it.
    private(set) var condition: WeatherCondition?

    /// When the displayed reading was taken.
    private var lastSuccess: Date?

    /// When a lookup was last attempted, successfully or not.
    private var lastAttempt: Date?

    /// Set once the user has refused; stops the loop for this visit.
    private var isRefused = false

    private let location: CoarseLocationProviding
    private let source: WeatherSource

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - location: Where the coordinate comes from. `nil` builds the real
    ///     CoreLocation provider, which cannot be a default argument because those
    ///     are evaluated outside the main actor it is confined to.
    ///   - source: Where the weather comes from.
    ///   - staleAfter: How old a cached reading may get before it is dropped.
    init(
        location: CoarseLocationProviding? = nil,
        source: WeatherSource = OpenMeteoClient(),
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
            let snapshot = try await source.weather(at: coordinate)
            temperatureText = snapshot.temperature.displayText
            condition = snapshot.condition
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
        condition = nil
        lastSuccess = nil
    }
}

#Preview {
    ClockScreen()
        .background(PixelTheme.background)
}
