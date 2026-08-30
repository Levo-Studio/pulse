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

        /// Any other event, kept so a read of a feed page stays honest about what was
        /// in it rather than silently dropping entries.
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
/// attempt to reconcile them. Nothing rendered from this type may be presented as an
/// account-wide figure.
///
/// The feed is also a window, not a history: roughly the last 300 events or 90 days,
/// whichever ends first. That is ample for "today" and is used for nothing else. Events
/// can lag reality by a few minutes, which is why the screen also shows when it last
/// fetched.
public struct GitHubActivitySummary: Equatable, Sendable {

    /// When the newest push **of today** happened, in the device's own time zone, or
    /// `nil` when there has been none today.
    ///
    /// Scoped to today, like every other figure the screen draws. The window behind it
    /// is 90 days of public activity, so the newest push in it can be from last week —
    /// and it is rendered directly above a headline that says `COMMITS TODAY`, on a
    /// screen whose axis says `TODAY` and which carries no date to say otherwise. An
    /// account that worked privately for a few days would get last week's time drawn
    /// exactly where today's belongs.
    ///
    /// A missing value means the screen omits the line entirely rather than showing a
    /// time it cannot stand behind. That is the same rule the headline count follows
    /// when GitHub publishes no exact figure for the day: silence over a confident
    /// wrong answer.
    public let lastPushAt: Date?

    /// When the feed this figure came from was fetched.
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

        for event in events where event.kind == .push {
            guard calendar.isDate(event.createdAt, inSameDayAs: now) else { continue }
            if let current = newestPush, current >= event.createdAt { continue }
            newestPush = event.createdAt
        }

        self.lastPushAt = newestPush
        self.fetchedAt = fetchedAt
    }
}
