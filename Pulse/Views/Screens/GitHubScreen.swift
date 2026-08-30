import SwiftUI

/// The GITHUB screen.
///
/// Placeholder surface: the paging container and shared pixel primitives are in
/// place, the screen's own content is not implemented yet.
public struct GitHubScreen: View {

    /// Creates the screen.
    public init() {}

    public var body: some View {
        PixelScreenBackdrop {
            PixelLabel("GITHUB", size: 16, tracking: 5, color: PixelTheme.faint)
        }
    }
}

#Preview {
    GitHubScreen()
}
