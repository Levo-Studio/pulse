import CoreText
import SwiftUI

/// Loads and vends the Silkscreen pixel typeface used across the display.
///
/// The font files ship inside the app bundle and are registered with Core Text at
/// launch rather than through an `UIAppFonts` Info.plist entry, because the project
/// generates its Info.plist from build settings and has no file to edit.
///
/// Silkscreen is licensed under the SIL Open Font License 1.1; the licence text is
/// bundled alongside the font files in `Pulse/Resources/Fonts/OFL.txt`.
public enum PixelFont {

    /// PostScript names of the bundled faces.
    private enum Face: String, CaseIterable {
        case regular = "Silkscreen-Regular"
        case bold = "Silkscreen-Bold"
    }

    /// Whether registration succeeded. When `false`, callers fall back to a
    /// monospaced system face so the app still renders rather than silently
    /// falling back to a proportional default.
    private static var isRegistered = false

    /// Registers the bundled faces with Core Text.
    ///
    /// Safe to call more than once; subsequent calls are ignored. Registration failure
    /// is not fatal — the display degrades to a monospaced system font.
    public static func register() {
        guard !isRegistered else { return }

        let urls = Face.allCases.compactMap {
            Bundle.main.url(forResource: $0.rawValue, withExtension: "ttf")
        }
        guard urls.count == Face.allCases.count else {
            assertionFailure("Silkscreen font files are missing from the app bundle")
            return
        }

        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true) { errors, _ in
            let failures = errors as? [Error] ?? []
            // A face already registered by an earlier launch of the same process is
            // not an error worth surfacing; anything else is a bundling mistake.
            if !failures.isEmpty {
                assertionFailure("Failed to register Silkscreen: \(failures)")
            }
            return true
        }
        isRegistered = true
    }

    /// A regular-weight pixel font at `size` points.
    ///
    /// The returned font is fixed-size on purpose: the display is laid out against a
    /// reference frame and scaled by `PixelMetrics`, so it must not also respond to
    /// Dynamic Type, which would break the pixel grid.
    public static func regular(_ size: CGFloat) -> Font {
        isRegistered
            ? .custom(Face.regular.rawValue, fixedSize: size)
            : .system(size: size, weight: .regular, design: .monospaced)
    }

    /// A bold-weight pixel font at `size` points.
    public static func bold(_ size: CGFloat) -> Font {
        isRegistered
            ? .custom(Face.bold.rawValue, fixedSize: size)
            : .system(size: size, weight: .bold, design: .monospaced)
    }
}
