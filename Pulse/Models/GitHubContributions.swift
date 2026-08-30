import Foundation

/// One day of the GitHub contribution calendar.
public struct ContributionDay: Equatable, Sendable, Identifiable {

    /// The calendar day, formatted `yyyy-MM-dd`, exactly as GitHub publishes it.
    public let date: String

    /// Number of contributions recorded on that day.
    public let count: Int

    /// Stable identity for `ForEach`; GitHub emits one entry per day.
    public var id: String { date }

    /// Creates a day.
    public init(date: String, count: Int) {
        self.date = date
        self.count = count
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

    /// The smallest contribution count that produces `step`.
    ///
    /// Used when GitHub gives a bucketed level for a day but no exact count.
    public static func representativeCount(forStep step: Int) -> Int {
        switch step {
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

    /// Contribution counts keyed by `yyyy-MM-dd`.
    public let countsByDate: [String: Int]

    /// When these counts were fetched, used to distinguish fresh from stale data.
    public let fetchedAt: Date

    /// Creates a calendar from parsed days.
    public init(days: [ContributionDay], fetchedAt: Date = Date()) {
        var counts: [String: Int] = [:]
        counts.reserveCapacity(days.count)
        for day in days {
            counts[day.date] = day.count
        }
        self.countsByDate = counts
        self.fetchedAt = fetchedAt
    }

    /// A calendar with no data, used before the first successful fetch.
    public static let empty = ContributionCalendar(days: [], fetchedAt: .distantPast)

    /// Whether any day was parsed.
    public var isEmpty: Bool { countsByDate.isEmpty }

    /// Contributions recorded on `dayKey`, or `0` when the day is absent.
    public func count(on dayKey: String) -> Int {
        countsByDate[dayKey] ?? 0
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
