import Foundation
import Testing

@testable import Pulse

/// Pins how much of a calendar the parser is willing to reconstruct from GitHub's
/// `data-level` when the tooltips that carry the exact counts are missing.
///
/// The levels are quartiles relative to the account's own busiest day, so a count
/// recovered from one is a guess with unbounded error. It never reaches the headline —
/// the screen shows a placeholder unless the day's figure is exact — but it does shade
/// the heatmap, and nothing on screen distinguishes a shaded guess from a shaded fact.
/// The budget is therefore what keeps a markup change from quietly redrawing the whole
/// grid out of fabrications, and it is asserted here rather than left to the comment
/// beside it.
struct GitHubContributionsParserTests {

    @Test("The level fallback budget is a handful of cells, not a proportion")
    func budget() {
        #expect(GitHubContributionsParser.levelFallbackBudget == 3)
    }

    @Test("A calendar missing no more than the budget is completed from levels")
    func fallbackWithinBudget() {
        let html = calendar(cells: 119, tooltips: 119 - GitHubContributionsParser.levelFallbackBudget)
        let days = GitHubContributionsParser.parse(html)

        #expect(days.count == 119)
        let derived = days.filter { !$0.isCountExact }.count
        #expect(derived == GitHubContributionsParser.levelFallbackBudget)
    }

    @Test("One cell past the budget, nothing is derived and only exact days survive")
    func fallbackBeyondBudget() {
        let missing = GitHubContributionsParser.levelFallbackBudget + 1
        let html = calendar(cells: 119, tooltips: 119 - missing)
        let days = GitHubContributionsParser.parse(html)

        #expect(days.count == 119 - missing)
        let everyDayExact = days.allSatisfy { $0.isCountExact }
        #expect(everyDayExact)
    }

    @Test("Half a year of tooltips no longer fabricates the other half")
    func halfCoverage() {
        let html = calendar(cells: 365, tooltips: 183)
        let days = GitHubContributionsParser.parse(html)

        #expect(days.count == 183)
        let everyDayExact = days.allSatisfy { $0.isCountExact }
        #expect(everyDayExact)
    }

    @Test("A complete calendar parses whole, with every count exact")
    func completeCalendar() {
        let days = GitHubContributionsParser.parse(calendar(cells: 119, tooltips: 119))

        #expect(days.count == 119)
        let everyDayExact = days.allSatisfy { $0.isCountExact }
        #expect(everyDayExact)
    }

    @Test("A document with no tooltips at all yields no days")
    func noTooltips() {
        #expect(GitHubContributionsParser.parse(calendar(cells: 119, tooltips: 0)).isEmpty)
    }

    // MARK: - Fixtures

    /// Builds a contributions fragment of `cells` day cells, the first `tooltips` of
    /// which carry the tooltip that holds the exact count.
    ///
    /// The markup mirrors the shape documented on the parser. Every cell carries a
    /// `data-level`, as GitHub's does, so a cell without a tooltip is exactly the case
    /// the budget governs.
    private func calendar(cells: Int, tooltips: Int) -> String {
        var html = "<table class=\"ContributionCalendar-grid\"><tbody>"
        var tips = ""

        for index in 0..<cells {
            let identifier = "contribution-day-component-\(index % 7)-\(index / 7)"
            let level = index % 5
            html += """
            <td data-date="\(date(dayAfterStart: index))" id="\(identifier)" \
            data-level="\(level)" class="ContributionCalendar-day"></td>
            """
            if index < tooltips {
                tips += """
                <tool-tip for="\(identifier)">\(level) contributions on a day.</tool-tip>
                """
            }
        }

        return html + "</tbody></table>" + tips
    }

    /// A `yyyy-MM-dd` key `offset` days after a fixed start, so every cell in a
    /// fixture has its own date.
    private func date(dayAfterStart offset: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        // A fixed zone keeps the fixture identical wherever the tests run.
        if let utc = TimeZone(identifier: "UTC") { calendar.timeZone = utc }
        let start = Date(timeIntervalSince1970: 0)
        let day = calendar.date(byAdding: .day, value: offset, to: start) ?? start
        return ContributionCalendar.dayKey(for: day, calendar: calendar)
    }
}
