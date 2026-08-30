import SwiftUI

/// The GITHUB screen: today's commit count above a 17-week contribution heatmap.
///
/// Laid out from the `03 GITHUB` frame of `design/Pulse.dc.html`. The reference's
/// `LAST COMMIT AT` line is deliberately not implemented: the public contributions
/// page exposes per-day totals only, never commit timestamps, and Pulse stores no
/// GitHub token that would let it ask for more.
public struct GitHubScreen: View {

    @Environment(\.activeScreen) private var activeScreen
    @Environment(\.pixelMetrics) private var metrics

    @State private var model = GitHubActivityModel()
    @State private var isEditingUsername = false

    /// Creates the screen.
    public init() {}

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

                if let status = model.statusLine {
                    statusRow(status)
                        .padding(.top, metrics(46))
                }
            }
        }
    }

    private func header(username: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: metrics(8)) {
            Button {
                isEditingUsername = true
            } label: {
                PixelLabel(username, size: 10, tracking: 2, color: PixelTheme.bright)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("GitHub username \(username). Tap to change.")

            Spacer(minLength: metrics(8))

            TimelineView(.everyMinute) { context in
                PixelLabel(
                    Self.clockFormatter.string(from: context.date),
                    size: 10,
                    tracking: 2,
                    color: PixelTheme.faint
                )
            }
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
                color: PixelTheme.primary
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

    private func statusRow(_ status: String) -> some View {
        Button {
            isEditingUsername = true
        } label: {
            PixelLabel(status, size: 10, tracking: 2, color: PixelTheme.muted)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Polling

    private var isActive: Bool { activeScreen == .gitHub }

    private var pollingKey: String {
        "\(isActive)-\(isEditingUsername)-\(model.username ?? "")"
    }

    /// Wall-clock formatter for the header. Fixed pattern and POSIX locale, because
    /// the reference shows a 24-hour readout regardless of device settings.
    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
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

    private let store: KeychainStore
    private let client: GitHubContributionsClient

    /// Creates the model.
    ///
    /// Nothing is read from the Keychain here — see `restoreUsername()`. The
    /// dependencies are built inside the initialiser rather than as default arguments,
    /// because a default argument is evaluated in the caller's isolation and these are
    /// main-actor bound.
    init(store: KeychainStore? = nil, client: GitHubContributionsClient? = nil) {
        self.store = store ?? KeychainStore()
        self.client = client ?? GitHubContributionsClient()
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
    /// It occupies the slot the reference fills with `LAST COMMIT AT`, which Pulse
    /// does not implement, and doubles as the way back to the username prompt.
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

    /// Stores `name` in the Keychain and drops any data belonging to the old account.
    func save(username name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard GitHubContributionsClient.isValidUsername(trimmed) else { return }
        guard store.set(trimmed, for: .gitHubUsername) else { return }

        username = trimmed
        contributions = .empty
        lastFailure = nil
    }

    /// Fetches the calendar for the stored username.
    func refresh() async {
        guard let username else { return }
        do {
            contributions = try await client.calendar(for: username)
            lastFailure = nil
        } catch let failure as GitHubContributionsClient.Failure {
            lastFailure = failure
        } catch {
            lastFailure = .unreachable
        }
    }
}

#Preview {
    GitHubScreen()
}
