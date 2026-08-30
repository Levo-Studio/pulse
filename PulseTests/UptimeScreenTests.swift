import Foundation
import Testing

@testable import Pulse

/// Pins the row arithmetic that keeps a long service name from pushing the status
/// square off the screen.
///
/// The budget is easy to get wrong — it has to account for every gap the row spends
/// and for the widest glyph the face can draw — and a mistake is invisible on the
/// devices where `PixelMetrics` has horizontal slack. These assertions make the
/// arithmetic fail loudly instead of drifting.
struct UptimeRowMetricsTests {

    @Test("The row reserves the full content width it actually spends")
    func widthAccounting() {
        #expect(UptimeRowMetrics.contentWidth == 308)
        // Three gaps: the HStack spacing either side of the spacer, and the spacer's
        // own minimum length.
        #expect(UptimeRowMetrics.gapWidth == 36)
        #expect(UptimeRowMetrics.nameWidthBudget == 261)
    }

    @Test("The character advance is the widest Silkscreen draws, not an average")
    func characterAdvance() {
        // Measured from the bundled face: A-Z 0-9 - _ . advance 0.375, 0.625, 0.75 or
        // 0.875 em, with M N V W X Y at the widest.
        #expect(UptimeRowMetrics.characterWidth == (13 * 0.875) + 2)
    }

    @Test("A full-length name plus the gaps and the square fits the content width")
    func budgetFitsTheRow() {
        let widest = CGFloat(UptimeRowMetrics.characterBudget) * UptimeRowMetrics.characterWidth
            + UptimeRowMetrics.gapWidth
            + UptimeRowMetrics.squareSide

        #expect(UptimeRowMetrics.characterBudget == 19)
        #expect(widest <= UptimeRowMetrics.contentWidth)
    }

    @Test("One more character than the budget would overrun")
    func budgetIsTight() {
        let overlong = CGFloat(UptimeRowMetrics.characterBudget + 1) * UptimeRowMetrics.characterWidth
            + UptimeRowMetrics.gapWidth
            + UptimeRowMetrics.squareSide

        #expect(overlong > UptimeRowMetrics.contentWidth)
    }

    @Test("Names within the budget are untouched, longer ones are marked")
    func truncation() {
        let short = String(repeating: "M", count: UptimeRowMetrics.characterBudget)
        #expect(UptimeRowMetrics.displayName(for: short) == short)

        let long = String(repeating: "M", count: 60)
        let shortened = UptimeRowMetrics.displayName(for: long)
        #expect(shortened.count == UptimeRowMetrics.characterBudget)
        #expect(shortened.hasSuffix(UptimeRowMetrics.truncationMarker))
    }
}
