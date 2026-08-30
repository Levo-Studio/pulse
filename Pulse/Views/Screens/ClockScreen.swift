import SwiftUI

/// The CLOCK screen.
///
/// Placeholder surface: the paging container and shared pixel primitives are in
/// place, the screen's own content is not implemented yet.
public struct ClockScreen: View {

    /// Creates the screen.
    public init() {}

    public var body: some View {
        PixelScreenBackdrop {
            PixelLabel("CLOCK", size: 16, tracking: 5, color: PixelTheme.faint)
        }
    }
}

#Preview {
    ClockScreen()
}
