import SwiftUI

/// A line of display type in the pixel typeface.
///
/// All copy in the design reference is uppercase and letter-spaced, so this view
/// applies both rather than leaving them to each call site. Sizes and tracking are
/// given in design-reference units and scaled through `PixelMetrics`.
public struct PixelLabel: View {

    private let text: String
    private let size: CGFloat
    private let tracking: CGFloat
    private let color: Color

    @Environment(\.pixelMetrics) private var metrics

    /// Creates a label.
    ///
    /// - Parameters:
    ///   - text: The copy to display. Uppercased for rendering.
    ///   - size: Font size in design-reference units.
    ///   - tracking: Letter spacing in design-reference units.
    ///   - color: Fill colour, normally taken from `PixelTheme`.
    public init(
        _ text: String,
        size: CGFloat,
        tracking: CGFloat,
        color: Color
    ) {
        self.text = text
        self.size = size
        self.tracking = tracking
        self.color = color
    }

    public var body: some View {
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
        PixelLabel("14:32", size: 70, tracking: 2, color: PixelTheme.primary)
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
