import Foundation

/// Recovers per-day contribution counts from the HTML fragment returned by
/// `https://github.com/users/{username}/contributions`.
///
/// **Known fragility.** There is no official public API for the contribution graph.
/// This endpoint returns an HTML fragment that is parsed here for per-day counts, and
/// GitHub can change that markup at any time, without notice and without a version to
/// pin, which will break this parser. Nothing in here may trap: every match is
/// optional, no result is force-unwrapped, and a fragment this parser does not
/// understand yields an empty array so the screen can fall back to a stale or empty
/// state instead of crashing.
///
/// The shape depended on, as observed:
///
/// ```html
/// <td ... data-date="2026-08-30" id="contribution-day-component-0-52"
///     data-level="1" class="ContributionCalendar-day"></td>
/// <tool-tip ... for="contribution-day-component-0-52">3 contributions on August 30th.</tool-tip>
/// ```
///
/// The exact count lives only in the tooltip text. GitHub's `data-level` is **not** a
/// second source for it: it is a quartile bucket relative to the account's own busiest
/// day, so the same level stands for wildly different counts on different accounts.
/// Losing the tooltips therefore means losing the data, not falling back to a coarser
/// version of it, and this parser treats it that way — no tooltips at all, or tooltips
/// for fewer than half the day cells, yields no days rather than a plausible-looking
/// fabrication presented as fresh truth.
public enum GitHubContributionsParser {

    /// Parses every calendar day out of `html`.
    ///
    /// - Returns: The days found, in document order. Empty when the markup does not
    ///   match, which callers must treat as "no data", never as an error to trap on.
    public static func parse(_ html: String) -> [ContributionDay] {
        let tooltips = tooltipCounts(in: html)

        // The tooltips carry the only exact counts in the document. If that element is
        // renamed or restructured the day cells still parse, so without this guard the
        // parser would return a full year of level-derived guesses and the screen would
        // show them as real data. An empty result is the honest outcome.
        guard !tooltips.isEmpty else { return [] }

        let cells = dayCells(in: html)

        // A level-derived count is only ever a stand-in for one isolated cell whose
        // tooltip is missing. If coverage is worse than that, the markup has changed
        // shape and nothing is derived at all.
        let allowsLevelFallback = tooltips.count * 2 >= cells.count

        var days: [ContributionDay] = []
        days.reserveCapacity(cells.count)

        for cell in cells {
            if let identifier = cell.identifier, let exact = tooltips[identifier] {
                days.append(
                    ContributionDay(date: cell.date, count: max(0, exact), isCountExact: true)
                )
            } else if allowsLevelFallback, let level = cell.level {
                days.append(
                    ContributionDay(
                        date: cell.date,
                        count: ContributionIntensity.approximateCount(forLevel: level),
                        isCountExact: false
                    )
                )
            }
        }

        return days
    }

    // MARK: - Day cells

    /// One day cell of the calendar table, before its count is resolved.
    private struct DayCell {
        let date: String
        let identifier: String?
        let level: Int?
    }

    /// Every `<td>` in the document that carries a calendar day.
    private static func dayCells(in html: String) -> [DayCell] {
        var cells: [DayCell] = []

        for tag in matches(of: dayCellExpression, in: html) {
            guard let cell = capture(1, of: tag, in: html),
                  cell.contains("ContributionCalendar-day"),
                  let date = attribute(dateExpression, in: cell),
                  date.count == 10 else {
                continue
            }

            cells.append(
                DayCell(
                    date: date,
                    identifier: attribute(identifierExpression, in: cell),
                    level: attribute(levelExpression, in: cell).flatMap(Int.init)
                )
            )
        }

        return cells
    }

    // MARK: - Tooltips

    /// Maps a day cell's `id` to the exact contribution count in its tooltip.
    private static func tooltipCounts(in html: String) -> [String: Int] {
        var counts: [String: Int] = [:]

        for match in matches(of: tooltipExpression, in: html) {
            guard let identifier = capture(1, of: match, in: html),
                  let text = capture(2, of: match, in: html),
                  let count = contributionCount(inTooltipText: text) else {
                continue
            }
            counts[identifier] = count
        }

        return counts
    }

    /// Reads the leading count out of a tooltip such as `12 contributions on May 3rd.`
    /// or `No contributions on May 3rd.`
    private static func contributionCount(inTooltipText text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("no contribution") { return 0 }

        let digits = trimmed.prefix { $0.isNumber || $0 == "," }
        guard !digits.isEmpty else { return nil }
        return Int(digits.filter(\.isNumber))
    }

    // MARK: - Attributes

    /// Reads a double-quoted attribute value out of a single tag's source.
    private static func attribute(
        _ expression: NSRegularExpression?,
        in tag: String
    ) -> String? {
        guard let expression else { return nil }
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        guard let match = expression.firstMatch(in: tag, options: [], range: range),
              let value = Range(match.range(at: 1), in: tag) else {
            return nil
        }
        return String(tag[value])
    }

    // MARK: - Expressions

    /// A `<td>` opening tag. The class attribute is checked afterwards rather than in
    /// the pattern, so the parser does not depend on attribute order.
    private static let dayCellExpression = try? NSRegularExpression(
        pattern: "<td\\b([^>]*)>",
        options: [.caseInsensitive]
    )

    /// A `<tool-tip>` element: its `for` target and its text.
    private static let tooltipExpression = try? NSRegularExpression(
        pattern: "<tool-tip\\b[^>]*\\bfor=\"([^\"]+)\"[^>]*>([^<]*)</tool-tip>",
        options: [.caseInsensitive]
    )

    /// Attribute patterns, compiled once rather than once per attribute per cell.
    private static let dateExpression = attributeExpression(named: "data-date")
    private static let identifierExpression = attributeExpression(named: "id")
    private static let levelExpression = attributeExpression(named: "data-level")

    private static func attributeExpression(named name: String) -> NSRegularExpression? {
        try? NSRegularExpression(
            pattern: "\\b\(NSRegularExpression.escapedPattern(for: name))=\"([^\"]*)\"",
            options: []
        )
    }

    private static func matches(
        of expression: NSRegularExpression?,
        in html: String
    ) -> [NSTextCheckingResult] {
        guard let expression else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return expression.matches(in: html, options: [], range: range)
    }

    private static func capture(
        _ index: Int,
        of match: NSTextCheckingResult,
        in html: String
    ) -> String? {
        guard index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: html) else {
            return nil
        }
        return String(html[range])
    }
}
