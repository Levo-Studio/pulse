import SwiftUI

/// The GitHub contribution heatmap: 17 columns of 7 square cells, filling the width
/// available to it.
///
/// Laid out the way a contribution graph is: one column per week, one row per weekday
/// with Sunday at the top, the oldest week on the left, and today in the last column.
/// The reference draws a full 17 × 7 block, so the days after today in the final week
/// are drawn at the ramp's darkest step rather than left blank, which keeps the block
/// rectangular.
public struct ContributionHeatmapGrid: View {

    /// Number of week columns, from the reference's `17 WEEKS` axis label.
    public static let columnCount = 17

    /// Number of weekday rows.
    public static let rowCount = 7

    /// Gap between cells, in design-reference units.
    private static let referenceGap: CGFloat = 5

    private let contributions: ContributionCalendar
    private let today: Date
    private let calendar: Calendar

    @Environment(\.pixelMetrics) private var metrics

    /// Creates the grid.
    ///
    /// - Parameters:
    ///   - contributions: Per-day counts to colour the cells with.
    ///   - today: The day highlighted with the green ramp. Defaults to now.
    ///   - calendar: Calendar used to walk weeks and days. Defaults to the current one.
    public init(
        contributions: ContributionCalendar,
        today: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.contributions = contributions
        self.today = today
        self.calendar = calendar
    }

    public var body: some View {
        let gap = metrics(Self.referenceGap)
        let todayKey = ContributionCalendar.dayKey(for: today, calendar: calendar)

        HStack(spacing: gap) {
            ForEach(0..<Self.columnCount, id: \.self) { column in
                VStack(spacing: gap) {
                    ForEach(0..<Self.rowCount, id: \.self) { row in
                        Rectangle()
                            .fill(colour(row: row, column: column, todayKey: todayKey))
                            // Cells are flexible in the row and square by aspect ratio,
                            // so the grid fills the width it is given without measuring it.
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Contribution heatmap, the last 17 weeks")
    }

    /// Fill colour for one cell.
    private func colour(row: Int, column: Int, todayKey: String) -> Color {
        guard let date = date(row: row, column: column) else {
            return PixelTheme.heatmapRamp[0]
        }
        let key = ContributionCalendar.dayKey(for: date, calendar: calendar)
        let step = ContributionIntensity.step(for: contributions.count(on: key))

        if key == todayKey {
            return PixelTheme.heatmapTodayRamp[clamped(step, in: PixelTheme.heatmapTodayRamp)]
        }
        return PixelTheme.heatmapRamp[clamped(step, in: PixelTheme.heatmapRamp)]
    }

    /// The day a cell stands for, walking back from the week containing today.
    private func date(row: Int, column: Int) -> Date? {
        let weekdayOfToday = calendar.component(.weekday, from: today)
        // `weekday` is 1-based with Sunday as 1, matching the grid's top row.
        let daysSinceSunday = weekdayOfToday - 1
        let weeksBack = (Self.columnCount - 1) - column
        let offset = -daysSinceSunday - (weeksBack * Self.rowCount) + row
        return calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: today))
    }

    private func clamped(_ step: Int, in ramp: [Color]) -> Int {
        min(max(step, 0), ramp.count - 1)
    }
}

#Preview {
    let days = (0..<130).map { offset -> ContributionDay in
        let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
        return ContributionDay(
            date: ContributionCalendar.dayKey(for: date),
            count: (offset * 7) % 13
        )
    }

    return ContributionHeatmapGrid(contributions: ContributionCalendar(days: days))
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PixelTheme.background)
}
