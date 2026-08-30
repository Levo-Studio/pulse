import CoreText
import SwiftUI
import Testing

@testable import Pulse

/// Pins the line box `PixelLabel` gives a line of display type.
///
/// The correction that makes a `.tight` label match the reference's `line-height: 1`
/// is derived from the bundled face's own metrics. Those metrics are stated in the
/// source as fixed numbers, so they are re-measured here: if the font file is ever
/// replaced by one with a different ascent or descent, the arithmetic in `PixelLabel`
/// stops describing reality and this fails rather than drifting silently.
@MainActor
struct PixelLabelLineBoxTests {

    /// Every font size the four screens actually use, in design-reference units.
    private static let sizesInUse: [CGFloat] = [76, 70, 48, 16, 14, 13, 11, 10, 9]

    /// The bundled face at `size` points, or `nil` when it is not registered.
    private func silkscreen(_ size: CGFloat) -> CTFont? {
        PixelFont.register()
        let font = CTFontCreateWithName("Silkscreen-Regular" as CFString, size, nil)
        guard CTFontCopyPostScriptName(font) as String == "Silkscreen-Regular" else {
            return nil
        }
        return font
    }

    @Test("The bundled face reports the metrics the correction is derived from")
    func bundledFaceMetrics() throws {
        let font = try #require(silkscreen(1000), "Silkscreen-Regular is not registered")

        // Read at an em of 1000 points so the figures are the font's own design units:
        // ascent 1030, descent 250, leading 0, and a natural line box of 1.28 em.
        #expect(CTFontGetAscent(font) == 1030)
        #expect(CTFontGetDescent(font) == 250)
        #expect(CTFontGetLeading(font) == 0)

        let naturalLineBox = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
        #expect(naturalLineBox == 1280)
    }

    @Test("A tight box keeps the uppercase glyphs, descenders included, inside it")
    func tightBoxHoldsTheGlyphs() throws {
        let font = try #require(silkscreen(1000), "Silkscreen-Regular is not registered")

        // The tight box runs from 0.89 em above the baseline to 0.11 em below it: a
        // one em box centred on the natural one trims 0.14 em of half-leading at each
        // end of a 1.28 em line.
        let halfLeading = (1280 - CGFloat(1000)) / 2
        let boxTop = CTFontGetAscent(font) - halfLeading
        let boxBottom = CTFontGetDescent(font) - halfLeading
        #expect(boxTop == 890)
        #expect(boxBottom == 110)

        let bounds = uppercaseBounds(in: font)
        // Caps reach 0.625 em, well inside the 0.89 em of headroom.
        #expect(bounds.maxY == 625)
        #expect(bounds.maxY < boxTop)
        // `Q` is the one uppercase glyph that descends. Its tail overhangs the bottom
        // edge by 0.015 em, which a frame does not clip.
        #expect(bounds.minY == -125)
        #expect(-bounds.minY - boxBottom == 15)
    }

    @Test("A tight label's box is exactly the font size, at every size in use")
    func tightLineBoxHeight() {
        for size in Self.sizesInUse {
            let height = renderedHeight(of: PixelLabel(
                "OQ08",
                size: size,
                tracking: 2,
                color: PixelTheme.primary,
                lineBox: .tight
            ))
            #expect(abs(height - size) <= 0.5, "size \(size) rendered \(height) pt tall")
        }
    }

    @Test("A natural label keeps the taller box the face asks for")
    func naturalLineBoxHeight() {
        for size in Self.sizesInUse {
            let height = renderedHeight(of: PixelLabel(
                "OQ08",
                size: size,
                tracking: 2,
                color: PixelTheme.primary
            ))
            #expect(height > size, "size \(size) rendered \(height) pt tall")
        }
    }

    @Test("The tight box scales with the metrics, rather than being a fixed offset")
    func tightLineBoxScales() {
        let doubled = PixelMetrics(
            size: CGSize(
                width: PixelMetrics.referenceWidth * 1.5,
                height: PixelMetrics.referenceHeight * 1.5
            )
        )
        let height = renderedHeight(
            of: PixelLabel("00:00", size: 48, tracking: 2, color: PixelTheme.primary, lineBox: .tight)
                .environment(\.pixelMetrics, doubled)
        )
        #expect(abs(height - doubled(48)) <= 0.5)
    }

    // MARK: - Measurement

    /// The height `view` renders at, in points.
    private func renderedHeight(of view: some View) -> CGFloat {
        let renderer = ImageRenderer(content: view)
        // A render at scale 1 reports the layout size directly.
        renderer.scale = 1
        return renderer.uiImage?.size.height ?? 0
    }

    /// Bounds of `A`–`Z` and `0`–`9` in `font`, unioned.
    private func uppercaseBounds(in font: CTFont) -> CGRect {
        let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        var buffer = characters
        CTFontGetGlyphsForCharacters(font, &buffer, &glyphs, characters.count)
        return CTFontGetBoundingRectsForGlyphs(font, .default, &glyphs, nil, glyphs.count)
    }
}
