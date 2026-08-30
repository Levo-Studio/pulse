import CoreText
import SwiftUI

/// Loads and vends the Silkscreen pixel typeface used across the display.
///
/// The font file ships inside the app bundle and is registered with Core Text at
/// launch rather than through an `UIAppFonts` Info.plist entry, because the project
/// generates its Info.plist from build settings and has no file to edit.
///
/// Registration is deliberately synchronous. The asynchronous variant of the Core
/// Text API returns before the face is available, which lets the first frames render
/// in a fallback face without triggering a redraw once registration lands.
///
/// Silkscreen is licensed under the SIL Open Font License 1.1; the licence text is
/// bundled alongside the font file in `Pulse/Resources/Fonts/OFL.txt`.
public enum PixelFont {

    /// PostScript name of the bundled face. The design reference renders every
    /// element at weight 400, so only the regular face is shipped.
    private static let faceName = "Silkscreen-Regular"

    /// Whether registration succeeded. When `false`, callers fall back to a
    /// monospaced system face so the app still renders legibly rather than
    /// silently dropping to a proportional default.
    private static var isRegistered = false

    /// Registers the bundled face with Core Text.
    ///
    /// Safe to call more than once; subsequent calls are ignored. Registration
    /// failure is not fatal — the display degrades to a monospaced system font.
    public static func register() {
        guard !isRegistered else { return }

        guard let url = Bundle.main.url(forResource: faceName, withExtension: "ttf") else {
            assertionFailure("\(faceName).ttf is missing from the app bundle")
            return
        }

        var error: Unmanaged<CFError>?
        let didRegister = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)

        if didRegister {
            isRegistered = true
            return
        }

        // A face registered by an earlier call in the same process is already usable;
        // anything else is a bundling mistake worth catching in development.
        let failure = error?.takeRetainedValue()
        if let failure, CFErrorGetCode(failure) == CTFontManagerError.alreadyRegistered.rawValue {
            isRegistered = true
        } else {
            assertionFailure("Failed to register \(faceName): \(String(describing: failure))")
        }
    }

    /// The pixel font at `size` points.
    ///
    /// The returned font is fixed-size on purpose: the display is laid out against a
    /// reference frame and scaled by `PixelMetrics`, so it must not also respond to
    /// Dynamic Type, which would break the pixel grid.
    public static func regular(_ size: CGFloat) -> Font {
        isRegistered
            ? .custom(faceName, fixedSize: size)
            : .system(size: size, weight: .regular, design: .monospaced)
    }
}
