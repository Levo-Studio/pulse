import SwiftUI

/// The GITHUB screen: today's commit count above a 17-week contribution heatmap.
///
/// Laid out from the `03 GITHUB` frame of `design/Pulse.dc.html`.
///
/// Two public sources feed it, and they are not interchangeable. The heatmap and the
/// headline count come from the scraped contributions page, which has per-day totals
/// and nothing finer. The reference's `LAST COMMIT AT` line, today's pull request
/// activity and the freshness line come from the public events API, which has
/// timestamps but sees public activity only. The two may legitimately disagree; the
/// screen labels the event-sourced lines as public rather than reconciling them.
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
                    initialUsername: model.username ?? "",
                    canCancel: model.username != nil,
                    onSubmit: { name in
                        model.save(username: name)
                        isEditingUsername = false
                    },
                    onCancel: { isEditingUsername = false }
                )
            }
        }
        .task { model.restoreUsername() }
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

                commitCount
                    .padding(.top, metrics(96))

                ContributionHeatmapGrid(contributions: model.contributions)
                    .padding(.top, metrics(110))

                axis
                    .padding(.top, metrics(16))

                footer
            }
        }
    }

    /// The block of small labels below the heatmap axis.
    ///
    /// The reference has a single line here, `LAST COMMIT AT`, at a 46 unit gap. Pulse
    /// can have up to four: the status line the screen already used this slot for, the
    /// reference's own line, the invented pull request line, and the freshness line.
    /// They stack at the reference's own 6 unit meta-line gap — the value the uptime
    /// frame uses between `LAST CHECK` and `NEXT REFRESH` — so the block keeps the
    /// rhythm of the design rather than inventing a second one, and the 46 unit gap
    /// still separates it from the axis above.
    @ViewBuilder
    private var footer: some View {
        if model.hasFooterContent {
            VStack(alignment: .leading, spacing: metrics(6)) {
                if let status = model.statusLine {
                    statusRow(status)
                }
                if let line = model.lastCommitLine {
                    // The reference's own line, in the reference's own colour.
                    PixelLabel(line, size: 10, tracking: 2, color: PixelTheme.muted)
                }
                if let line = model.pullRequestLine {
                    // Invented, so it sits a step below the reference's line and well
                    // below the headline count the screen is built around.
                    PixelLabel(line, size: 10, tracking: 2, color: PixelTheme.faint)
                }
                if let line = model.lastCheckLine {
                    // Same wording and same treatment as the uptime screen's own
                    // freshness line, so the two screens read as one system.
                    PixelLabel(line, size: 10, tracking: 2, color: PixelTheme.faint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, metrics(46))
        }
    }

    private func header(username: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: metrics(8)) {
            Button {
                isEditingUsername = true
            } label: {
                PixelLabel(
                    GitHubHeaderRow.displayName(for: username),
                    size: 10,
                    tracking: 2,
                    color: PixelTheme.bright
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("GitHub username \(username). Tap to change.")

            Spacer(minLength: metrics(8))

            // The current time, and the only unlabelled readout on the screen. The
            // three at the foot all name what they report, so nothing else here can be
            // mistaken for now.
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

    private var commitCount: some View {
        VStack(spacing: 0) {
            PixelLabel(
                // A placeholder rather than a zero when today has no exact count: the
                // screen must not state a figure it cannot stand behind.
                model.commitsToday.map(String.init) ?? "--",
                size: 76,
                tracking: 1,
                color: PixelTheme.primary,
                // `line-height: 1` in the reference: both the 96 units above the
                // count and the 14 below it are measured from a one-em box.
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

    @ViewBuilder
    private func statusRow(_ status: String) -> some View {
        if model.lastFailure == nil {
            // The only status the screen shows without a failure behind it is a
            // missing count for today, which no rename can fix. It reads as plain
            // text, because a tap that silently opened the username prompt would be
            // offering a repair for a problem the user does not have — and nothing on
            // the row suggests a tap would start one.
            statusLabel(status)
        } else {
            // Every failure line ends in TAP TO CHANGE, so the row is the way back to
            // the prompt.
            Button {
                isEditingUsername = true
            } label: {
                statusLabel(status)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func statusLabel(_ status: String) -> some View {
        PixelLabel(status, size: 10, tracking: 2, color: PixelTheme.muted)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
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

    /// The gaps the row spends: the stack's own spacing and the spacer's minimum.
    static let gapWidth: CGFloat = 8 + 8

    /// How many characters fit on a line that has the content width to itself, which
    /// is what every label in the block at the foot of the screen has.
    ///
    /// The wording of those lines is chosen against this, so none of them can overrun
    /// the frame on the narrowest device whatever counts they carry.
    static var footerCharacterBudget: Int { Int(contentWidth / characterWidth) }

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
    /// It heads the block of small labels at the foot of the screen and doubles as the
    /// way back to the username prompt. Only the contributions fetch is reported here:
    /// a failed events fetch costs three subordinate lines, not the screen's subject,
    /// and those lines simply do not appear.
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
            return "NO SUCH USER - TAP TO CHANGE"
        case .unparsableMarkup:
            return "NO DATA - TAP TO CHANGE"
        case .unreachable, .unexpectedStatus:
            return contributions.isEmpty
                ? "OFFLINE - TAP TO CHANGE"
                : "OFFLINE - SHOWING LAST DATA"
        }
    }

    // MARK: - Event-sourced lines

    /// The reference's `LAST COMMIT AT` line, or `nil` when the events window holds no
    /// push.
    ///
    /// Two honesty notes are baked into this. The feed timestamps the *push*, not the
    /// authoring of the commit inside it, which is the closest a tokenless client can
    /// get to the reference's wording. And the feed is public activity only, so a push
    /// to a private repository leaves this line showing an older public one, or absent.
    /// Absent is the deliberate choice over a placeholder: a dash where a time belongs
    /// invites being read as a time.
    var lastCommitLine: String? {
        guard let pushedAt = activity?.lastPushAt else { return nil }
        return "LAST COMMIT AT: \(Self.minuteFormatter.string(from: pushedAt))"
    }

    /// Today's public pull request activity, or `nil` when there was none.
    ///
    /// Not in the design reference — this line is an addition. It is written as
    /// `PUBLIC` first so it cannot be read as an account-wide total: the feed behind it
    /// never sees private repositories, while the heatmap above it can, and the two are
    /// allowed to disagree.
    ///
    /// A day with no pull requests shows nothing rather than a zero. A zero would be a
    /// claim — "you merged nothing today" — that this source cannot support, since the
    /// work may simply have been private.
    var pullRequestLine: String? {
        guard let activity, activity.hasPullRequestActivityToday else { return nil }
        let opened = activity.pullRequestsOpenedToday
        let merged = activity.pullRequestsMergedToday

        switch (opened, merged) {
        case (0, let merged):
            return "PUBLIC PR MERGED: \(merged)"
        case (let opened, 0):
            return "PUBLIC PR OPENED: \(opened)"
        default:
            return "PUBLIC PR: \(opened) OPENED \(merged) MERGED"
        }
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
        statusLine != nil || lastCommitLine != nil || pullRequestLine != nil
            || lastCheckLine != nil
    }

    // MARK: - Fetching

    /// Stores `name` in the Keychain and drops any data belonging to the old account.
    func save(username name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard GitHubContributionsClient.isValidUsername(trimmed) else { return }
        guard store.set(trimmed, for: .gitHubUsername) else { return }

        username = trimmed
        contributions = .empty
        lastFailure = nil
        activity = nil
        eventsFailure = nil
        eventsBackoffUntil = nil
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
