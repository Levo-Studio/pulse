import SwiftUI

/// A line of display type in the pixel typeface.
///
/// All copy in the design reference is uppercase and letter-spaced, so this view
/// applies both rather than leaving them to each call site. Sizes and tracking are
/// given in design-reference units and scaled through `PixelMetrics`.
///
/// The height of the line the label occupies is part of the design, not an
/// afterthought: every gap the screens transcribe is measured from the edge of a CSS
/// line box, and the box the reference asks for is not always the one `Text` produces.
/// See `LineBox`.
public struct PixelLabel: View {

    /// The height of the box the glyphs sit in, mirroring the two `line-height`
    /// values the design reference uses.
    ///
    /// Measured from the bundled `Silkscreen-Regular.ttf` with Core Text: the face has
    /// an em of 1000 units, an ascent of 1030 and a descent of 250, with zero leading.
    /// Its natural line box is therefore 1.28 em — 97.28 pt at size 76, 89.60 at 70,
    /// 61.44 at 48, 12.80 at 10 — and the baseline sits 1.03 em below the box top. A
    /// browser lays `line-height: normal` out from exactly those numbers, so an
    /// unadjusted SwiftUI `Text` already matches the reference wherever the reference
    /// leaves the line height alone.
    ///
    /// Where the reference sets `line-height: 1` the box is one em instead, and the
    /// browser trims the difference as half-leading: 0.14 em off the top and 0.14 em
    /// off the bottom. `Text` does not do that, so those lines render with up to
    /// 0.14 em of dead space on each side — 10.6 pt at size 76, 9.8 at 70, 6.7 at 48 —
    /// stacked on top of the gap the screen asked for.
    public enum LineBox: Equatable, Sendable {

        /// The box the face itself asks for, 1.28 em for Silkscreen. Mirrors
        /// `line-height: normal`, which is what the reference leaves every label at
        /// except its three display lines.
        case natural

        /// A box exactly one em tall, mirroring the reference's `line-height: 1` on
        /// the clock time, the stopwatch readout and the GitHub commit count.
        case tight
    }

    private let text: String
    private let size: CGFloat
    private let tracking: CGFloat
    private let color: Color
    private let lineBox: LineBox

    @Environment(\.pixelMetrics) private var metrics

    /// Creates a label.
    ///
    /// - Parameters:
    ///   - text: The copy to display. Uppercased for rendering.
    ///   - size: Font size in design-reference units.
    ///   - tracking: Letter spacing in design-reference units.
    ///   - color: Fill colour, normally taken from `PixelTheme`.
    ///   - lineBox: Height of the line the glyphs sit in. Defaults to `.natural`,
    ///     matching the reference's default line height.
    public init(
        _ text: String,
        size: CGFloat,
        tracking: CGFloat,
        color: Color,
        lineBox: LineBox = .natural
    ) {
        self.text = text
        self.size = size
        self.tracking = tracking
        self.color = color
        self.lineBox = lineBox
    }

    public var body: some View {
        switch lineBox {
        case .natural:
            // No frame at all rather than one of a nil height, so a label the
            // reference does not adjust is laid out exactly as it was, including the
            // baseline it offers a surrounding stack.
            line
        case .tight:
            line.frame(height: metrics(size) * Self.tightLineBoxFactor, alignment: .center)
        }
    }

    private var line: some View {
        Text(text.uppercased())
            .font(PixelFont.regular(metrics(size)))
            .tracking(metrics(tracking))
            .foregroundStyle(color)
            // The pixel grid must not reflow, so a label never wraps. It keeps its
            // intrinsic width instead of being compressed, which would break the
            // glyph rhythm; an overlong string is a layout bug to fix at the source.
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
    }

    /// Why the tight box is a frame.
    ///
    /// The correction is stated as the height the box is supposed to have, rather
    /// than as negative vertical padding worked out from the measured ascent and
    /// descent. Both land the baseline in the same place — centring a 1.28 em box
    /// inside a 1 em box removes exactly the 0.14 em of half-leading at each end,
    /// which is what the browser does — but a frame does not depend on `Text`
    /// reporting the height the face's metrics predict, and it stays right if
    /// registration fails and `PixelFont` falls back to a system face with entirely
    /// different metrics.
    ///
    /// Nothing is clipped by it: a frame does not clip, and the glyphs sit inside the
    /// box anyway. Silkscreen's uppercase runs from the baseline to 0.625 em, which a
    /// one-em box carries with 0.265 em of room above and 0.11 em below; the deepest
    /// descender in the uppercase set is `Q` at -0.125 em, whose tail overhangs the
    /// bottom edge by 0.015 em — 1.1 pt at size 76 — and still draws in full.
    ///
    /// The height scales through `PixelMetrics` like every other measurement, so it
    /// holds at each of the sizes the screens use: 76, 70, 48, 16, 14, 13, 11, 10, 9.
    private static let tightLineBoxFactor: CGFloat = 1
}

/// A single square cell of the pixel grid, used by the contribution heatmap and
/// the uptime status dots.
///
/// Drawn flat and unrounded, matching the reference.
public struct PixelCell: View {

    private let color: Color
    private let side: CGFloat

    /// Creates a cell of `side` points filled with `color`.
    public init(color: Color, side: CGFloat) {
        self.color = color
        self.side = side
    }

    public var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: side, height: side)
    }
}

#Preview {
    VStack(spacing: 20) {
        PixelLabel("14:32", size: 70, tracking: 2, color: PixelTheme.primary, lineBox: .tight)
        PixelLabel("FR 30 AUG", size: 16, tracking: 5, color: PixelTheme.muted)
        HStack(spacing: 6) {
            PixelCell(color: PixelTheme.statusOperational, side: 11)
            PixelCell(color: PixelTheme.statusDegraded, side: 11)
            PixelCell(color: PixelTheme.statusDown, side: 11)
            PixelCell(color: PixelTheme.statusUnknown, side: 11)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(PixelTheme.background)
}
