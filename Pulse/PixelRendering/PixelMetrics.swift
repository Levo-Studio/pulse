import SwiftUI

/// Converts measurements taken from the design reference into points for the
/// screen the app is actually running on.
///
/// Every size in `design/Pulse.dc.html` is authored against a 360 × 780 pt frame.
/// Rather than hardcoding those numbers, screens scale them through this type so
/// the layout holds from a small iPhone up to an iPad.
public struct PixelMetrics: Equatable, Sendable {

    /// The frame width the design reference was authored against.
    public static let referenceWidth: CGFloat = 360

    /// The frame height the design reference was authored against.
    public static let referenceHeight: CGFloat = 780

    /// Ratio between the live frame and the reference frame.
    public let scale: CGFloat

    /// Creates metrics for a frame of the given size.
    ///
    /// Both axes are taken into account: scaling on width alone would blow the
    /// display far past the available height on a short, wide frame. The result is
    /// clamped so a large frame does not scale the type up to an absurd size.
    public init(size: CGSize) {
        let raw = min(
            size.width / Self.referenceWidth,
            size.height / Self.referenceHeight
        )
        self.scale = min(max(raw, 0.75), 1.8)
    }

    /// Scales a length taken from the design reference.
    public func callAsFunction(_ referenceValue: CGFloat) -> CGFloat {
        referenceValue * scale
    }
}

private struct PixelMetricsKey: EnvironmentKey {
    static let defaultValue = PixelMetrics(
        size: CGSize(
            width: PixelMetrics.referenceWidth,
            height: PixelMetrics.referenceHeight
        )
    )
}

extension EnvironmentValues {

    /// Metrics for the current display, injected by `PulsePager`.
    public var pixelMetrics: PixelMetrics {
        get { self[PixelMetricsKey.self] }
        set { self[PixelMetricsKey.self] = newValue }
    }
}
