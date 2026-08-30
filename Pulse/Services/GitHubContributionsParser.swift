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
/// The exact count lives only in the tooltip text, so it is preferred when present and
/// the bucketed `data-level` is used as a fallback.
public enum GitHubContributionsParser {

    /// Parses every calendar day out of `html`.
    ///
    /// - Returns: The days found, in document order. Empty when the markup does not
    ///   match, which callers must treat as "no data", never as an error to trap on.
    public static func parse(_ html: String) -> [ContributionDay] {
        let tooltips = tooltipCounts(in: html)
        var days: [ContributionDay] = []

        for tag in matches(of: dayCellExpression, in: html) {
            guard let cell = capture(1, of: tag, in: html),
                  cell.contains("ContributionCalendar-day"),
                  let date = attribute("data-date", in: cell),
                  date.count == 10 else {
                continue
            }

            let identifier = attribute("id", in: cell)
            let level = attribute("data-level", in: cell).flatMap(Int.init)
            let exactCount = identifier.flatMap { tooltips[$0] }
            let count = exactCount
                ?? level.map(ContributionIntensity.representativeCount(forStep:))

            guard let count else { continue }
            days.append(ContributionDay(date: date, count: max(0, count)))
        }

        return days
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
    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let expression = try? NSRegularExpression(
            pattern: "\\b\(NSRegularExpression.escapedPattern(for: name))=\"([^\"]*)\"",
            options: []
        ) else {
            return nil
        }
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
