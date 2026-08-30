import SwiftUI

/// Converts measurements taken from the design reference into points for the
/// screen the app is actually running on.
///
/// Every size in `design/Pulse.dc.html` is authored against a 360 pt-wide frame.
/// Rather than hardcoding those numbers, screens scale them through this type so
/// the layout holds from a small iPhone up to an iPad.
public struct PixelMetrics: Equatable, Sendable {

    /// The width the design reference was authored against.
    public static let referenceWidth: CGFloat = 360

    /// Ratio between the live frame width and the reference width.
    public let scale: CGFloat

    /// Creates metrics for a frame of the given width.
    ///
    /// The scale is clamped so that very wide frames — an iPad, or a Mac window —
    /// do not blow the display up to an absurd size.
    public init(width: CGFloat) {
        let raw = width / Self.referenceWidth
        self.scale = min(max(raw, 0.75), 1.8)
    }

    /// Scales a length taken from the design reference.
    public func callAsFunction(_ referenceValue: CGFloat) -> CGFloat {
        referenceValue * scale
    }
}

private struct PixelMetricsKey: EnvironmentKey {
    static let defaultValue = PixelMetrics(width: PixelMetrics.referenceWidth)
}

extension EnvironmentValues {

    /// Metrics for the current display, injected by `PulsePager`.
    public var pixelMetrics: PixelMetrics {
        get { self[PixelMetricsKey.self] }
        set { self[PixelMetricsKey.self] = newValue }
    }
}
