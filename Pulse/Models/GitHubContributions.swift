import Foundation

/// One day of the GitHub contribution calendar.
public struct ContributionDay: Equatable, Sendable, Identifiable {

    /// The calendar day, formatted `yyyy-MM-dd`, exactly as GitHub publishes it.
    public let date: String

    /// Number of contributions recorded on that day.
    public let count: Int

    /// Whether `count` is the exact figure GitHub published for the day, rather than
    /// an approximation recovered from its account-relative level bucket.
    ///
    /// Only an exact count may be shown as a number to the user; an approximate one is
    /// good enough to shade a heatmap cell and nothing more.
    public let isCountExact: Bool

    /// Stable identity for `ForEach`; GitHub emits one entry per day.
    public var id: String { date }

    /// Creates a day.
    public init(date: String, count: Int, isCountExact: Bool = true) {
        self.date = date
        self.count = count
        self.isCountExact = isCountExact
    }

    /// Heatmap intensity step, `0...4`.
    public var intensityStep: Int { ContributionIntensity.step(for: count) }
}

/// Maps a day's contribution count onto the five-step heatmap ramp.
public enum ContributionIntensity {

    /// The step, `0...4`, for `count`.
    ///
    /// Transcribed from the design reference: `0` → 0, `1–2` → 1, `3–5` → 2,
    /// `6–9` → 3, `10+` → 4.
    public static func step(for count: Int) -> Int {
        switch count {
        case ..<1: return 0
        case ..<3: return 1
        case ..<6: return 2
        case ..<10: return 3
        default: return 4
        }
    }

    /// A rough contribution count for one of GitHub's own `data-level` buckets.
    ///
    /// GitHub's level and this type's step are **not the same scale**. The step above is
    /// absolute — it comes from the design reference and means the same thing on every
    /// account. GitHub's level is a quartile relative to that account's busiest day, so
    /// on a busy account level 1 can be twenty contributions and on a quiet one it can
    /// be a single contribution. Converting between them is therefore guesswork, and the
    /// result may only shade a heatmap cell when a single day's exact count is missing.
    /// It must never be shown to the user as a number.
    public static func approximateCount(forLevel level: Int) -> Int {
        switch level {
        case ..<1: return 0
        case 1: return 1
        case 2: return 3
        case 3: return 6
        default: return 10
        }
    }
}

/// A user's contribution calendar: per-day counts keyed by day.
///
/// The type holds no networking and no parsing; it is the value the GitHub screen
/// renders from, and it is safe to render before any fetch has succeeded.
public struct ContributionCalendar: Equatable, Sendable {

    /// Contribution counts keyed by `yyyy-MM-dd`. Good enough to shade a heatmap cell;
    /// a value here may have been approximated from GitHub's account-relative level.
    public let countsByDate: [String: Int]

    /// The days whose count is GitHub's exact published figure.
    public let exactDates: Set<String>

    /// When these counts were fetched, used to distinguish fresh from stale data.
    public let fetchedAt: Date

    /// Creates a calendar from parsed days.
    public init(days: [ContributionDay], fetchedAt: Date = Date()) {
        var counts: [String: Int] = [:]
        var exact: Set<String> = []
        counts.reserveCapacity(days.count)
        for day in days {
            counts[day.date] = day.count
            if day.isCountExact { exact.insert(day.date) }
        }
        self.countsByDate = counts
        self.exactDates = exact
        self.fetchedAt = fetchedAt
    }

    /// A calendar with no data, used before the first successful fetch.
    public static let empty = ContributionCalendar(days: [], fetchedAt: .distantPast)

    /// Whether any day was parsed.
    public var isEmpty: Bool { countsByDate.isEmpty }

    /// Contributions recorded on `dayKey`, or `0` when the day is absent.
    ///
    /// May be approximate. Use it to shade a cell, not to display a number.
    public func count(on dayKey: String) -> Int {
        countsByDate[dayKey] ?? 0
    }

    /// GitHub's exact count for `dayKey`, or `nil` when the day is absent or its count
    /// was only approximated from a level bucket.
    ///
    /// The commit count is the headline of the GitHub screen, so it is drawn from this
    /// and shows nothing at all rather than a number that might be wrong.
    public func exactCount(on dayKey: String) -> Int? {
        guard exactDates.contains(dayKey) else { return nil }
        return countsByDate[dayKey]
    }

    /// Formats `date` into the `yyyy-MM-dd` key GitHub uses.
    ///
    /// GitHub labels each cell with a plain calendar date, so the key is built in
    /// the device's own time zone: the day the user calls "today" is the day the
    /// screen highlights.
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else {
            // dateComponents always fills the fields it is asked for; the fallback
            // exists only so the parser never force-unwraps.
            return ""
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
