import SwiftUI

/// The GITHUB screen: today's commit count above a 17-week contribution heatmap.
///
/// Laid out from the `03 GITHUB` frame of `design/Pulse.dc.html`, with three
/// deviations the repository owner asked for and `CLAUDE.md` §2 records: the
/// reference's `LAST COMMIT AT:` label is dropped and its time set bare above the
/// count, the invented pull request line is gone, and the reference's fixed `+96` and
/// `+110` vertical offsets — authored for its own 360 × 780 frame — are replaced by
/// gaps that flex, so a taller frame shares its extra height between the blocks
/// instead of dropping all of it into the spacer above the last line.
///
/// Two public sources feed it, and they are not interchangeable. The heatmap and the
/// headline count come from the scraped contributions page, which has per-day totals
/// and nothing finer. The time above the count and the freshness line come from the
/// public events API, which has timestamps but sees public activity only. The two may
/// legitimately disagree, and the screen does not reconcile them.
public struct GitHubScreen: View {

    @Environment(\.activeScreen) private var activeScreen
    @Environment(\.pixelMetrics) private var metrics
    @Environment(\.scenePhase) private var scenePhase

    @State private var model = GitHubActivityModel()
    @State private var isEditingUsername = false
    @State private var ticker = SecondTicker()

    /// Creates the screen.
    public init() {}

    /// Creates the screen around a model that is already prepared.
    ///
    /// Used to render the screen with known data — by the layout checks that verify the
    /// block of small labels still fits the shortest supported device, and by previews.
    /// The screen's own behaviour is identical either way.
    init(model: GitHubActivityModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        Group {
            if !model.hasRestoredUsername {
                // Neither state is correct until the Keychain has been read.
                PixelScreenBackdrop(placement: .topInset) { EmptyView() }
            } else if let username = model.username, !isEditingUsername {
                display(username: username)
            } else {
                GitHubUsernamePrompt(
                    owner: .gitHub,
                    canCancel: model.username != nil,
                    onSubmit: { name in
                        guard model.save(username: name) else { return false }
                        isEditingUsername = false
                        return true
                    },
                    onCancel: { isEditingUsername = false }
                )
            }
        }
        .task { model.restoreUsername() }
        // The settings screen writes the same Keychain item, so the stored name is
        // re-read whenever this screen is paged back into view. Without it a name
        // changed in settings would only take effect on the next launch.
        .onChange(of: activeScreen) {
            guard activeScreen == .gitHub else { return }
            model.adoptStoredUsername()
        }
        .onAppear { synchroniseTicker() }
        .onDisappear { ticker.stop() }
        .onChange(of: isHeaderTimeVisible) { synchroniseTicker() }
        // Polling is keyed on both the active screen and the username, so it starts
        // when the screen is paged in or the name changes, and is cancelled the
        // moment the user pages away.
        .task(id: pollingKey) {
            guard isActive, model.username != nil, !isEditingUsername else { return }
            while !Task.isCancelled {
                await model.refresh()
                // The endpoint is a public page that is being scraped; per-day totals
                // change slowly, so it is polled gently.
                try? await Task.sleep(for: .seconds(600))
            }
        }
    }

    // MARK: - Display

    private func display(username: String) -> some View {
        PixelScreenBackdrop(placement: .topInset) {
            VStack(spacing: 0) {
                header(username: username)

                flexibleGap(minimum: 32)

                commitBlock

                // A little more space is reserved below the count than above it, so the
                // block reads as optically centred between the header and the heatmap
                // rather than sitting fractionally low under its own descender space.
                flexibleGap(minimum: 48)

                ContributionHeatmapGrid(contributions: model.contributions)
                    // The grid is the one block whose height is a consequence of its
                    // width: its cells are square by aspect ratio, so a stack that
                    // hands it less height than its width asks for returns a narrower
                    // grid with dead margins either side, not a shorter one. Laying it
                    // out first means it is offered the space the flexing gaps have not
                    // yet claimed, answers with the height its own width implies, and
                    // hands the rest straight back to them.
                    .layoutPriority(1)

                axis
                    .padding(.top, metrics(16))

                // The reference's own 46 unit gap below the axis, allowed to grow a
                // little but not without limit: the surplus of a tall screen belongs to
                // the two gaps above, and the footer belongs at the foot.
                flexibleGap(minimum: 46, maximum: 96)

                footer

                changeUsernameAction
            }
        }
    }

    /// Vertical space that grows with the screen, stated in design-reference units.
    ///
    /// The reference pins the count at `+96` below the header and the heatmap at `+110`
    /// below the count. Those are fixed offsets in a 360 × 780 frame, and a taller
    /// frame has to put the difference somewhere: transcribed literally it all collects
    /// in the trailing spacer, which strands `LAST CHECK` 117 points above
    /// `CHANGE USERNAME` at 393 × 852 rather than sharing the height out. Flexing the
    /// gaps instead keeps every block's internal spacing exactly as drawn while the
    /// space between blocks absorbs whatever height the device actually has.
    ///
    /// - Parameters:
    ///   - minimum: Space the gap never goes below — the smallest supported screen is
    ///     the case that has to survive.
    ///   - maximum: Ceiling on the gap, or `nil` to let it take its share of whatever
    ///     is left.
    private func flexibleGap(minimum: CGFloat, maximum: CGFloat? = nil) -> some View {
        Spacer(minLength: metrics(minimum))
            .frame(maxHeight: maximum.map { metrics($0) } ?? .infinity)
    }

    /// The block of small labels below the heatmap axis.
    ///
    /// The reference has a single line here, `LAST COMMIT AT`, at a 46 unit gap. That
    /// line has moved above the count and the pull request line is gone, so in health
    /// this block is one line, `LAST CHECK`, and the `CHANGE USERNAME` action below it.
    /// A failing fetch adds the status line above it; the two stack at the reference's
    /// own 6 unit meta-line gap — the value the uptime frame uses between `LAST CHECK`
    /// and `NEXT REFRESH` — so the block keeps the rhythm of the design rather than
    /// inventing a second one.
    @ViewBuilder
    private var footer: some View {
        if model.hasFooterContent {
            VStack(alignment: .leading, spacing: metrics(6)) {
                if let status = model.statusLine {
                    statusLabel(status)
                }
                if let line = model.lastCheckLine {
                    // The uptime screen's wording, one size below its size. This line
                    // and the header both carry an eight-character HH:MM:SS in the same
                    // faint grey, and for the first minutes after every refresh they
                    // read the identical value, so they are separated on every axis
                    // that is left: this one is smaller, labelled, and at the opposite
                    // corner. Nine is also the reference's own smallest size, which is
                    // what a line about the data rather than in it should be.
                    PixelLabel(line, size: 9, tracking: 2, color: PixelTheme.faint)
                        // Set off from a status line above by a doubled gap; nothing to
                        // set off from when the screen is healthy.
                        .padding(.top, model.statusLine == nil ? 0 : metrics(6))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func header(username: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: metrics(8)) {
            PixelLabel(
                GitHubHeaderRow.displayName(for: username),
                size: 10,
                tracking: 2,
                color: PixelTheme.bright
            )

            Spacer(minLength: metrics(8))

            // The current time. It is not the only unlabelled readout any more — the
            // time of today's last push sits bare above the count — so it is kept
            // deliberately small, faint, right-aligned and ticking by the second,
            // which is what separates a clock from a timestamp here. See
            // `commitBlock`.
            PixelLabel(
                GitHubHeaderRow.timeReadout(for: ticker.now),
                size: 10,
                tracking: 2,
                color: PixelTheme.faint
            )
            .accessibilityLabel("Current time")
        }
        .frame(maxWidth: .infinity)
    }

    /// The time of today's last public push, the count, and its label, as one block.
    ///
    /// The reference labels the time `LAST COMMIT AT:` at the foot of the frame. The
    /// owner asked for it bare and directly above the number instead, which puts a
    /// second unlabelled time on a screen whose header already carries one. They are
    /// told apart by everything except their wording:
    ///
    /// - **Size.** 16 against the header's 10 — and 16 is the reference's own size for
    ///   the clock's date and temperature lines, not an invented one. The tracking is
    ///   4, not the 5 those clock lines carry: 16 at 5 in `#525252` would be that
    ///   line's style character for character, and quoting the one screen in the app
    ///   that really is a clock is the last thing this time should do. 4 is the
    ///   tracking of `COMMITS TODAY` directly below it, which is the rhythm it belongs
    ///   to.
    /// - **Colour.** `#525252`, the reference's colour for `LAST COMMIT AT` and for
    ///   `COMMITS TODAY` directly below, against the header's fainter `#3D3D3D`. The
    ///   time and the label below the count are therefore the same grey, bracketing the
    ///   white number as one block.
    /// - **Position.** Centred on the count, at the count's own 14 unit gap, in the
    ///   middle of the screen; the header readout is right-aligned in a row at the top.
    /// - **Precision.** `HH:mm` against the header's `HH:mm:ss`, so the header ticks
    ///   every second and this does not.
    ///
    /// It is still, honestly, a bare time — a glance that reads only the digits can
    /// take it for a clock. What the treatment buys is that it never reads as a clock
    /// *in place*: it is bound to the number it sits on.
    private var commitBlock: some View {
        VStack(spacing: 0) {
            if let time = model.lastCommitTime {
                PixelLabel(time, size: 16, tracking: 4, color: PixelTheme.muted)
                    .padding(.bottom, metrics(14))
                    .accessibilityLabel("Last commit at \(time)")
            }
            PixelLabel(
                // A placeholder rather than a zero when today has no exact count: the
                // screen must not state a figure it cannot stand behind.
                model.commitsToday.map(String.init) ?? "--",
                size: 76,
                tracking: 1,
                color: PixelTheme.primary,
                // `line-height: 1` in the reference: the 14 unit gaps either side of
                // the count are measured from a one-em box.
                lineBox: .tight
            )
            PixelLabel("COMMITS TODAY", size: 11, tracking: 4, color: PixelTheme.muted)
                .padding(.top, metrics(14))
        }
        .frame(maxWidth: .infinity)
    }

    private var axis: some View {
        HStack(spacing: metrics(8)) {
            PixelLabel("17 WEEKS", size: 9, tracking: 2, color: PixelTheme.faint)
            Spacer(minLength: metrics(8))
            PixelLabel("TODAY", size: 9, tracking: 2, color: PixelTheme.primary)
        }
        .frame(maxWidth: .infinity)
    }

    /// A status line reports; it never doubles as a control.
    private func statusLabel(_ status: String) -> some View {
        PixelLabel(status, size: 10, tracking: 2, color: PixelTheme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The single way back to the username prompt once a name is stored.
    ///
    /// The screen used to route both the header and the failing status line into the
    /// prompt, which left the affordance hidden until something went wrong and
    /// invisible when everything was fine. Both are plain labels now and this is the
    /// only path, kept at the foot of the screen in the faintest colour so it does not
    /// compete with the count and the heatmap.
    private var changeUsernameAction: some View {
        Button {
            isEditingUsername = true
        } label: {
            PixelLabel("CHANGE USERNAME", size: 10, tracking: 3, color: PixelTheme.faint)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, metrics(16))
    }

    // MARK: - Polling

    private var isActive: Bool { activeScreen == .gitHub }

    private var pollingKey: String {
        "\(isActive)-\(isEditingUsername)-\(model.username ?? "")"
    }

    // MARK: - Header ticking

    /// Whether the header readout is actually being looked at.
    ///
    /// A 1 Hz timer earns its keep only while its output is visible, so it is gated on
    /// three things: the pager may keep this page alive off-screen, the app may be
    /// backgrounded with the view still mounted, and the username prompt replaces the
    /// header entirely while it is up.
    private var isHeaderTimeVisible: Bool {
        GitHubHeaderRow.shouldTick(
            activeScreen: activeScreen,
            scenePhase: scenePhase,
            hasUsername: model.username != nil,
            isEditingUsername: isEditingUsername
        )
    }

    private func synchroniseTicker() {
        if isHeaderTimeVisible {
            // `start` also refreshes, so a screen returning to view never shows the
            // second it was paged away on.
            ticker.start()
        } else {
            ticker.stop()
        }
    }
}

/// The arithmetic and formatting of the GitHub screen's header row, in
/// design-reference units.
///
/// The row is a `space-between` pair — username on the left, time on the right — of
/// two labels that are both `fixedSize(horizontal: true)`, so neither compresses and a
/// `Spacer` between them cannot rescue an overlong row. A GitHub username may be 39
/// characters, which never fitted beside the reference's `HH:mm`; beside `HH:mm:ss` it
/// fits three characters less. The name is therefore truncated to a budget that holds
/// whatever glyphs it is made of, rather than being left to overrun the frame.
///
/// The figures are in reference units and scale with everything else through
/// `PixelMetrics`, so the row holds at every device width.
enum GitHubHeaderRow {

    /// Width available inside the screen's 26 unit horizontal padding.
    static let contentWidth: CGFloat = PixelMetrics.referenceWidth - (2 * 26)

    /// Advance of one header character, worst case.
    ///
    /// Silkscreen has an em of 1000 units and advances of 0.375, 0.625, 0.75 and
    /// 0.875 em across the characters these labels can contain, with `M N V W X Y` at
    /// the widest. Budgeting against the widest means a name of any composition fits;
    /// the budget only ever errs towards truncating early.
    static let characterWidth: CGFloat = (10 * 0.875) + 2

    /// The readout is `HH:mm:ss`: eight characters.
    static let timeWidth: CGFloat = 8 * characterWidth

    /// The gaps the row spends: **three**, not two.
    ///
    /// The `Spacer` is a subview like any other, so `HStack(spacing: 8)` inserts its
    /// spacing on both sides of it, and the spacer's own `minLength` is additive rather
    /// than absorbing that spacing. A row of two 10 unit blocks around a spacer of
    /// minimum length 8 is 44 units wide, not 36. Counting two gaps here would
    /// under-reserve by a whole gap, and the shortfall would only surface the day the
    /// worst-case character advance below is replaced with real glyph widths.
    static let gapWidth: CGFloat = 8 + 8 + 8

    /// Width left for the username once the time and the gaps are paid for.
    static let nameWidthBudget: CGFloat = contentWidth - timeWidth - gapWidth

    /// How many characters of a username fit.
    static let characterBudget: Int = Int(nameWidthBudget / characterWidth)

    /// Marker replacing the tail of a username too long for the row.
    ///
    /// Three full stops rather than an ellipsis, matching the uptime rows: Silkscreen
    /// draws `…` as one wide glyph where three narrow stops read more clearly.
    static let truncationMarker = "..."

    /// The username as the header draws it, shortened when it cannot fit.
    ///
    /// The full name is still what is stored and what the prompt shows, so nothing is
    /// lost — only the row is kept intact.
    static func displayName(for username: String) -> String {
        guard username.count > characterBudget else { return username }
        let kept = characterBudget - truncationMarker.count
        return username.prefix(max(kept, 1)) + truncationMarker
    }

    /// Whether the one-second ticker behind the header readout should be running.
    ///
    /// Stated as a function of the four conditions rather than inline in the view, so
    /// the gate can be exercised without mounting a view hierarchy.
    static func shouldTick(
        activeScreen: PulseScreen,
        scenePhase: ScenePhase,
        hasUsername: Bool,
        isEditingUsername: Bool
    ) -> Bool {
        activeScreen == .gitHub && scenePhase == .active && hasUsername && !isEditingUsername
    }

    /// The header readout for `date`, `HH:mm:ss`.
    static func timeReadout(for date: Date) -> String {
        formatter.string(from: date)
    }

    /// Fixed pattern and POSIX locale, because the reference shows a 24-hour readout
    /// regardless of device settings. The time zone is the device's own.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

/// State behind the GitHub screen: the stored username, the last calendar fetched,
/// and how the last fetch went.
///
/// Failures never propagate to the view as errors to trap on. A failed refresh keeps
/// whatever data was last shown and sets a short status line instead.
@MainActor
@Observable
final class GitHubActivityModel {

    /// The account being displayed, or `nil` until the user has entered one.
    private(set) var username: String?

    /// The most recent calendar fetched. Empty before the first success.
    private(set) var contributions: ContributionCalendar = .empty

    /// Why the last refresh failed, or `nil` when it succeeded.
    private(set) var lastFailure: GitHubContributionsClient.Failure?

    /// What the public events feed last said about today, or `nil` before the first
    /// successful fetch of it.
    ///
    /// Kept separate from `contributions` on purpose. The two come from different
    /// sources with different visibility — the feed is public activity only, the
    /// heatmap may include private contributions — so they are never merged into one
    /// figure, and one source failing leaves the other on screen.
    private(set) var activity: GitHubActivitySummary?

    /// Why the last events fetch failed, or `nil` when it succeeded.
    private(set) var eventsFailure: GitHubEventsClient.Failure?

    /// When the events feed may be asked again after the hourly quota ran out.
    ///
    /// The unauthenticated quota is 60 requests an hour and is shared by every client
    /// behind the same address, so it can be spent by someone else entirely. While it
    /// is, the screen keeps showing the last good figures and does not retry — a retry
    /// would only spend a request that is not there.
    private var eventsBackoffUntil: Date?

    private let store: KeychainStore
    private let client: GitHubContributionsClient
    private let eventsClient: GitHubEventsClient

    /// Creates the model.
    ///
    /// Nothing is read from the Keychain here — see `restoreUsername()`. The
    /// dependencies are built inside the initialiser rather than as default arguments,
    /// because a default argument is evaluated in the caller's isolation and these are
    /// main-actor bound.
    init(
        store: KeychainStore? = nil,
        client: GitHubContributionsClient? = nil,
        eventsClient: GitHubEventsClient? = nil
    ) {
        self.store = store ?? KeychainStore()
        self.client = client ?? GitHubContributionsClient()
        self.eventsClient = eventsClient ?? GitHubEventsClient()
    }

    /// Whether the stored username has been looked up yet.
    ///
    /// The screen shows neither the display nor the prompt until it has, so a Keychain
    /// read that has not happened yet is never mistaken for "no username stored".
    private(set) var hasRestoredUsername = false

    /// Reads the stored username, once.
    ///
    /// Done here rather than in `init` because the pager rebuilds every screen value on
    /// each swipe, which would put a `SecItemCopyMatching` call on the main thread each
    /// time and then discard the result.
    func restoreUsername() {
        guard !hasRestoredUsername else { return }
        username = store.string(for: .gitHubUsername)
        hasRestoredUsername = true
    }

    /// Re-reads the stored username, adopting a change made on another screen.
    ///
    /// The settings screen writes the same Keychain item, so the two can disagree
    /// while this screen is paged away. A name that has not changed costs nothing; a
    /// name that has drops the previous account's data rather than leaving one
    /// account's heatmap under another account's handle, exactly as `save(username:)`
    /// does.
    ///
    /// Does nothing before the first read, which `restoreUsername()` owns: adopting
    /// `nil` from a Keychain that has not been consulted yet would be indistinguishable
    /// from the user clearing the name.
    func adoptStoredUsername() {
        guard hasRestoredUsername else { return }
        let stored = store.string(for: .gitHubUsername)
        guard stored != username else { return }

        username = stored
        contributions = .empty
        lastFailure = nil
        activity = nil
        eventsFailure = nil
        eventsBackoffUntil = nil
    }

    /// The headline: GitHub's exact count for today, or `nil` when there is no exact
    /// figure for it.
    ///
    /// Deliberately never falls back to a level-derived approximation. GitHub's levels
    /// are relative to the account's own busiest day, so an approximation here could be
    /// off by an order of magnitude while looking entirely ordinary. The screen shows a
    /// placeholder instead, and the status line says why.
    var commitsToday: Int? {
        contributions.exactCount(on: ContributionCalendar.dayKey(for: Date()))
    }

    /// A short line describing a problem, or `nil` when the screen is healthy.
    ///
    /// It heads the block of small labels at the foot of the screen. Only the
    /// contributions fetch is reported here: a failed events fetch costs the time above
    /// the count, not the screen's subject, and that time simply does not appear.
    ///
    /// The line only reports. The way back to the username prompt is the screen's own
    /// `CHANGE USERNAME` action, so there is a single visible route rather than one
    /// that appears only when something has already gone wrong.
    var statusLine: String? {
        switch lastFailure {
        case .none:
            // A calendar that parsed but carries no exact figure for today: the
            // headline shows a placeholder, so say why rather than leave it bare.
            guard contributions.isEmpty || commitsToday != nil else {
                return "NO COUNT FOR TODAY"
            }
            return nil
        case .invalidUsername, .unknownUser:
            return "NO SUCH USER"
        case .unparsableMarkup:
            return "NO DATA FOR THIS ACCOUNT"
        case .unreachable, .unexpectedStatus:
            return contributions.isEmpty
                ? "OFFLINE"
                : "OFFLINE - SHOWING LAST DATA"
        }
    }

    // MARK: - Event-sourced lines

    /// The time of today's last public push, `HH:mm`, or `nil` when there has been
    /// none.
    ///
    /// The reference draws this as `LAST COMMIT AT: 13:58` at the foot of the frame.
    /// The owner asked for the label dropped and the time moved directly above the
    /// count, so the value is the time alone; what it means is carried by its position
    /// rather than by words. See `GitHubScreen.commitBlock` for how it is kept apart
    /// from the header's clock.
    ///
    /// Three honesty notes are baked into this. The line is scoped to today, like every
    /// other figure on the screen: it carries no date, and it sits under a headline
    /// that says `COMMITS TODAY`, so a time from earlier in the 90-day window would
    /// read as today's. The feed timestamps the *push*, not the authoring of the commit
    /// inside it, which is the closest a tokenless client can get to the reference's
    /// wording. And the feed is public activity only, so a day spent in a private
    /// repository leaves the line absent rather than late.
    ///
    /// Absent is the deliberate choice over a placeholder, and over a stale time: a
    /// dash where a time belongs invites being read as a time, and a wrong time reads
    /// more confidently still.
    var lastCommitTime: String? {
        guard let pushedAt = activity?.lastPushAt else { return nil }
        return Self.minuteFormatter.string(from: pushedAt)
    }

    /// When the data on screen was last fetched, in the uptime screen's own wording.
    ///
    /// It reports the **older** of the two sources' successes, never the newer and
    /// never the last attempt. Both feeds can lag — GitHub's events by a few minutes —
    /// so the one guarantee worth making is that nothing on screen is older than this
    /// line says.
    var lastCheckLine: String? {
        let stamps = [
            contributions.isEmpty ? nil : contributions.fetchedAt,
            activity?.fetchedAt
        ].compactMap { $0 }

        guard let oldest = stamps.min() else { return nil }
        return "LAST CHECK: \(Self.secondFormatter.string(from: oldest))"
    }

    /// Whether any line belongs in the block at the foot of the screen.
    var hasFooterContent: Bool {
        statusLine != nil || lastCheckLine != nil
    }

    // MARK: - Fetching

    /// Stores `name` in the Keychain and drops any data belonging to the old account.
    ///
    /// The stored item is overwritten only here, on a successful write. Opening or
    /// cancelling the prompt never touches it.
    ///
    /// - Returns: `true` when the name reached the Keychain.
    func save(username name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard GitHubContributionsClient.isValidUsername(trimmed) else { return false }
        guard store.set(trimmed, for: .gitHubUsername) else { return false }

        username = trimmed
        contributions = .empty
        lastFailure = nil
        activity = nil
        eventsFailure = nil
        eventsBackoffUntil = nil
        return true
    }

    /// Refreshes both sources for the stored username.
    ///
    /// They are fetched in sequence and reported separately: neither failure clears the
    /// other's data, so a rate-limited events feed leaves the heatmap intact and an
    /// unparsable contributions page leaves the event-sourced lines intact.
    func refresh(now: Date = Date()) async {
        guard let username else { return }
        await refreshContributions(for: username)
        await refreshActivity(for: username, now: now)
    }

    private func refreshContributions(for username: String) async {
        do {
            contributions = try await client.calendar(for: username)
            lastFailure = nil
        } catch let failure as GitHubContributionsClient.Failure {
            lastFailure = failure
        } catch {
            lastFailure = .unreachable
        }
    }

    private func refreshActivity(for username: String, now: Date) async {
        if let backoff = eventsBackoffUntil, now < backoff { return }
        eventsBackoffUntil = nil

        do {
            let events = try await eventsClient.events(for: username)
            activity = GitHubActivitySummary(events: events, now: now, fetchedAt: now)
            eventsFailure = nil
        } catch let failure as GitHubEventsClient.Failure {
            eventsFailure = failure
            if case .rateLimited(let resetAt) = failure {
                // An unknown reset is waited out for a full quota window rather than
                // guessed at, which is still only one skipped poll at this cadence.
                eventsBackoffUntil = resetAt ?? now.addingTimeInterval(3600)
            }
        } catch {
            eventsFailure = .unreachable
        }
    }

    /// `HH:mm` for the event-sourced commit time. Fixed pattern and POSIX locale like
    /// the rest of the display, so the readout is 24-hour regardless of device
    /// settings; the time zone is the device's, so a UTC timestamp reads as local time.
    private static let minuteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// `HH:mm:ss` for the freshness line, matching the uptime screen's readout.
    private static let secondFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

#Preview {
    GitHubScreen()
}
