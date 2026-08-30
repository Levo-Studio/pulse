import SwiftUI

/// A weather condition drawn as pixel art on the display's own grid.
///
/// Not an SF Symbol and not an emoji. Both would arrive with their own drawing —
/// curves, gradients, colour — beside a bitmap typeface whose glyphs are square
/// cells on a 1000 unit em, and would read as pasted in from another app. These
/// figures are square cells too, filled flat in one colour, so the indicator is
/// made of the same material as everything else on the screen.
///
/// Each figure is authored as an eight-column, seven-row bitmap. Eight by seven
/// is the smallest grid that separates the six conditions legibly: rain needs a
/// cloud with two rows beneath it for the fall, and the cloud needs three rows to
/// read as a cloud rather than a blob.
///
/// Drawn flat, with no shadow, blur or bloom: the reference is labelled `NO GLOW`.
public struct PixelWeatherIcon: View {

    /// Columns in every figure.
    public static let columns = 8

    /// Rows in every figure.
    public static let rows = 7

    private let condition: WeatherCondition
    private let cell: CGFloat
    private let color: Color

    /// Creates an icon.
    ///
    /// - Parameters:
    ///   - condition: Which figure to draw.
    ///   - cell: Side of one grid cell in points, already scaled by
    ///     `PixelMetrics` by the caller.
    ///   - color: Fill colour, normally taken from `PixelTheme`.
    public init(condition: WeatherCondition, cell: CGFloat, color: Color) {
        self.condition = condition
        self.cell = cell
        self.color = color
    }

    public var body: some View {
        Path { path in
            for (row, line) in Self.bitmap(for: condition).enumerated() {
                for (column, mark) in line.enumerated() where mark == Self.filled {
                    path.addRect(
                        CGRect(
                            x: CGFloat(column) * cell,
                            y: CGFloat(row) * cell,
                            width: cell,
                            height: cell
                        )
                    )
                }
            }
        }
        .fill(color)
        .frame(width: CGFloat(Self.columns) * cell, height: CGFloat(Self.rows) * cell)
        .accessibilityHidden(true)
    }

    /// The character marking a filled cell in the bitmaps below.
    static let filled: Character = "#"

    /// The figure for a condition, as seven rows of eight characters, top row
    /// first. `#` is a filled cell and `.` is an empty one.
    ///
    /// The figures share a vocabulary so they read as one set: a three-row cloud
    /// in the top four rows for everything that falls out of one, and the bottom
    /// two rows for what is falling. Rain is two slanted two-cell streaks; snow is
    /// scattered single cells, which cannot be mistaken for a streak; the
    /// thunderbolt is one connected diagonal, thicker at its foot. Clear is a sun
    /// with four straight and four diagonal rays, and fog is three broken bars
    /// with no cloud above them.
    static func bitmap(for condition: WeatherCondition) -> [String] {
        switch condition {
        case .clear:
            [
                "...##...",
                ".#....#.",
                "..####..",
                "#.####.#",
                "..####..",
                ".#....#.",
                "...##..."
            ]
        case .cloudy:
            [
                "........",
                "...##...",
                "..#####.",
                ".#######",
                ".#######",
                "........",
                "........"
            ]
        case .fog:
            [
                "........",
                ".######.",
                "........",
                "########",
                "........",
                ".######.",
                "........"
            ]
        case .rain:
            [
                "...##...",
                "..#####.",
                ".#######",
                ".#######",
                "........",
                "...#..#.",
                "..#..#.."
            ]
        case .snow:
            [
                "...##...",
                "..#####.",
                ".#######",
                ".#######",
                "........",
                "..#.#.#.",
                "...#.#.."
            ]
        case .thunderstorm:
            [
                "...##...",
                "..#####.",
                ".#######",
                ".#######",
                "........",
                "....##..",
                "..###..."
            ]
        }
    }
}

#Preview {
    HStack(spacing: 14) {
        ForEach(WeatherCondition.allCases, id: \.self) { condition in
            PixelWeatherIcon(condition: condition, cell: 4, color: PixelTheme.muted)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(PixelTheme.background)
}
