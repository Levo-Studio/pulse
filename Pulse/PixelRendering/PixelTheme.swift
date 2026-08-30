import SwiftUI

/// The colour palette of the Pulse display, transcribed from the design reference
/// at `design/Pulse.dc.html` (variant `1B — PURE BLACK & WHITE`).
///
/// The reference is explicitly labelled `NO GLOW`: display elements are drawn flat,
/// without shadows, blurs or bloom.
public enum PixelTheme {

    // MARK: - Surface

    /// The background of every screen.
    public static let background = Color(hex: 0x000000)

    // MARK: - Type

    /// Primary display type: clock time, stopwatch time, commit count.
    public static let primary = Color(hex: 0xFFFFFF)

    /// Bright secondary type: GitHub username, uptime service names.
    public static let bright = Color(hex: 0xE6E6E6)

    /// Muted labels: date, `COMMITS TODAY`, `LAST COMMIT AT`.
    public static let muted = Color(hex: 0x525252)

    /// The faintest labels: time-of-day readouts, `LAST CHECK`, `NEXT REFRESH`, axis labels.
    public static let faint = Color(hex: 0x3D3D3D)

    /// The hairline separating rows in the uptime list.
    public static let separator = Color(hex: 0x1C1C1C)

    // MARK: - Heatmap

    /// The five-step monochrome intensity ramp of the contribution heatmap.
    public static let heatmapRamp: [Color] = [
        Color(hex: 0x141414),
        Color(hex: 0x3D3D3D),
        Color(hex: 0x6E6E6E),
        Color(hex: 0xA3A3A3),
        Color(hex: 0xFFFFFF)
    ]

    /// The five-step green ramp used only for the cell representing today.
    public static let heatmapTodayRamp: [Color] = [
        Color(hex: 0x123A20),
        Color(hex: 0x166534),
        Color(hex: 0x199C48),
        Color(hex: 0x22C55E),
        Color(hex: 0x4ADE80)
    ]

    // MARK: - Status

    /// A service that is up.
    public static let statusOperational = Color(hex: 0x22C55E)

    /// A service that is reachable but impaired.
    public static let statusDegraded = Color(hex: 0xF59E0B)

    /// A service that is down.
    public static let statusDown = Color(hex: 0xEF4444)

    /// A service whose state is not known yet.
    public static let statusUnknown = Color(hex: 0x2A2D2E)
}

extension Color {

    /// Creates an opaque colour from a 24-bit `0xRRGGBB` literal.
    ///
    /// Used so the palette above can be read against the hex values in the design
    /// reference without conversion.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
