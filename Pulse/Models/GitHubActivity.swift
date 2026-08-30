import Foundation

/// One entry of GitHub's public events feed, reduced to the two facts the display
/// needs: what happened, and when.
///
/// The feed is **public activity only**. Contributions to private repositories never
/// appear in it, whatever the account's "include private contributions" setting says,
/// so a summary built from these events is a floor and never a total. See
/// `GitHubActivitySummary` for what that means on screen.
public struct GitHubEvent: Equatable, Sendable {

    /// The kinds of event the display distinguishes. Everything else is `other`.
    public enum Kind: Equatable, Sendable {

        /// A push of one or more commits.
        case push

        /// A pull request was opened.
        case pullRequestOpened

        /// A pull request was merged.
        case pullRequestMerged

        /// Any other event, kept so counts of a feed page stay honest about what was
        /// read rather than silently dropping entries.
        case other
    }

    /// What happened.
    public let kind: Kind

    /// When GitHub recorded it, in UTC as published.
    public let createdAt: Date

    /// Creates an event.
    public init(kind: Kind, createdAt: Date) {
        self.kind = kind
        self.createdAt = createdAt
    }
}

/// What one page of the public events feed says about an account's day.
///
/// **This is not a total.** The feed carries public activity only, while the
/// contribution heatmap on the same screen can include private contributions when the
/// account enables that setting. The two sources may therefore legitimately disagree —
/// typically the heatmap shows more than these events imply — and Pulse makes no
/// attempt to reconcile them. Every line rendered from this type is labelled as public
/// so it cannot be read as an account-wide figure.
///
/// The feed is also a window, not a history: roughly the last 300 events or 90 days,
/// whichever ends first. That is ample for "today" and is used for nothing else. Events
/// can lag reality by a few minutes, which is why the screen also shows when it last
/// fetched.
public struct GitHubActivitySummary: Equatable, Sendable {

    /// When the newest push **of today** happened, in the device's own time zone, or
    /// `nil` when there has been none today.
    ///
    /// Scoped to today for the same reason the pull request counts are. The window
    /// behind it is 90 days of public activity, so the newest push in it can be from
    /// last week — and it is rendered on a screen whose headline says `COMMITS TODAY`
    /// and whose axis says `TODAY`, with no date beside it to say otherwise. An
    /// account that worked privately for a few days would get last week's time drawn
    /// exactly where today's belongs.
    ///
    /// A missing value means the screen omits the line entirely rather than showing a
    /// time it cannot stand behind. That is the same rule the headline count follows
    /// when GitHub publishes no exact figure for the day: silence over a confident
    /// wrong answer.
    public let lastPushAt: Date?

    /// Public pull requests opened today, in the device's own time zone.
    public let pullRequestsOpenedToday: Int

    /// Public pull requests merged today, in the device's own time zone.
    public let pullRequestsMergedToday: Int

    /// When the feed these figures came from was fetched.
    public let fetchedAt: Date

    /// Summarises `events`.
    ///
    /// - Parameters:
    ///   - events: The feed page, in any order.
    ///   - now: The moment "today" is measured against.
    ///   - calendar: Calendar used to decide what "today" means. Defaults to the
    ///     device's, so the boundary is the user's local midnight and not UTC's.
    ///   - fetchedAt: When the feed was retrieved.
    public init(
        events: [GitHubEvent],
        now: Date = Date(),
        calendar: Calendar = .current,
        fetchedAt: Date = Date()
    ) {
        var newestPush: Date?
        var opened = 0
        var merged = 0

        for event in events {
            switch event.kind {
            case .push:
                guard calendar.isDate(event.createdAt, inSameDayAs: now) else { continue }
                if let current = newestPush, current >= event.createdAt { continue }
                newestPush = event.createdAt
            case .pullRequestOpened:
                if calendar.isDate(event.createdAt, inSameDayAs: now) { opened += 1 }
            case .pullRequestMerged:
                if calendar.isDate(event.createdAt, inSameDayAs: now) { merged += 1 }
            case .other:
                continue
            }
        }

        self.lastPushAt = newestPush
        self.pullRequestsOpenedToday = opened
        self.pullRequestsMergedToday = merged
        self.fetchedAt = fetchedAt
    }

    /// Whether the window held any pull request activity today.
    public var hasPullRequestActivityToday: Bool {
        pullRequestsOpenedToday > 0 || pullRequestsMergedToday > 0
    }
}
