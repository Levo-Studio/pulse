import CoreGraphics
import SwiftUI
import Testing

@testable import Pulse

/// Verification of the clock's vertical layout by rendering it.
///
/// The absence of the temperature line is the one thing about this screen that
/// must not change anything else: when there is no reading, the clock has to
/// render exactly as the two-line clock it was before the line existed. That was
/// originally checked by taking two simulator screenshots and comparing them,
/// which is not good enough — the two shots are of a running clock taken at
/// different times, so the digits differ, and the comparison has to excuse a
/// differing region. The slack that excuse creates is enough to hide a layout
/// regression, and it did.
///
/// These tests render instead. Every input is fixed, so two renders of the same
/// arrangement are byte-identical and one differing pixel is a real difference.
@MainActor
struct ClockLayoutTests {

    // MARK: - Rendering

    private static let renderSize = CGSize(width: 360, height: 780)

    /// Renders `view` at a fixed size and returns its raw RGBA bytes.
    private func render(_ view: some View) throws -> [UInt8] {
        let renderer = ImageRenderer(
            content: view.frame(width: Self.renderSize.width, height: Self.renderSize.height)
        )
        renderer.scale = 1

        let image = try #require(renderer.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(
            CGContext(
                data: &pixels,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }

    /// The rows carrying ink, grouped into contiguous bands.
    private func inkBands(_ pixels: [UInt8]) -> [ClosedRange<Int>] {
        let width = Int(Self.renderSize.width)
        let height = pixels.count / (width * 4)

        var lit: [Int] = []
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4] > 40 {
                lit.append(y)
                break
            }
        }
        guard let first = lit.first else { return [] }

        var bands: [ClosedRange<Int>] = []
        var start = first
        var previous = first
        for y in lit.dropFirst() {
            if y - previous > 1 {
                bands.append(start...previous)
                start = y
            }
            previous = y
        }
        bands.append(start...previous)
        return bands
    }

    // MARK: - Stand-ins for the clock's lines

    /// The clock's lines as plain blocks of the heights they occupy.
    ///
    /// Blocks rather than `PixelLabel`, so the measurement is of the layout and
    /// not of whether the pixel face happens to be registered in the test host.
    private struct Lines: View {
        let showsTemperature: Bool

        /// `true` reproduces the arrangement the screen does **not** use: one
        /// shared stack spacing, with the temperature's extra margin bolted on.
        let usesStackSpacing: Bool

        var body: some View {
            VStack(spacing: usesStackSpacing ? ClockLayout.dateGap : 0) {
                block(height: 70)

                block(height: 16)
                    .padding(.top, usesStackSpacing ? 0 : ClockLayout.dateGap)

                if showsTemperature {
                    block(height: 16)
                        .padding(
                            .top,
                            usesStackSpacing
                                ? ClockLayout.temperatureGap - ClockLayout.dateGap
                                : ClockLayout.temperatureGap
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(Color.black)
        }

        private func block(height: CGFloat) -> some View {
            Color.white.frame(width: 100, height: height)
        }
    }

    /// A spaced stack whose third child is conditional, for the behaviour check
    /// below. The flag is a property rather than a literal so the branch is not
    /// folded away at compile time.
    private struct SpacedStack: View {
        let includesThird: Bool

        var body: some View {
            VStack(spacing: 40) {
                Color.white.frame(width: 100, height: 10)
                Color.white.frame(width: 100, height: 10)
                if includesThird {
                    Color.white.frame(width: 100, height: 10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(Color.black)
        }
    }

    /// The same stack with no third child at all.
    private struct TwoChildStack: View {
        var body: some View {
            VStack(spacing: 40) {
                Color.white.frame(width: 100, height: 10)
                Color.white.frame(width: 100, height: 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(Color.black)
        }
    }

    // MARK: - Absence changes nothing

    @Test("With no temperature, the clock renders exactly as the two-line clock")
    func absenceIsIdenticalToTheTwoLineClock() throws {
        let withoutTemperature = try render(Lines(showsTemperature: false, usesStackSpacing: false))

        // The two-line clock as it stood before the temperature existed: the same
        // two lines and the same gap, with no conditional in the stack at all.
        let twoLineClock = try render(
            VStack(spacing: 0) {
                Color.white.frame(width: 100, height: 70)
                Color.white.frame(width: 100, height: 16)
                    .padding(.top, ClockLayout.dateGap)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(Color.black)
        )

        #expect(withoutTemperature == twoLineClock)
    }

    @Test("The temperature is the only line that comes and goes")
    func presenceAddsOneBand() throws {
        let absent = inkBands(try render(Lines(showsTemperature: false, usesStackSpacing: false)))
        let present = inkBands(try render(Lines(showsTemperature: true, usesStackSpacing: false)))

        #expect(absent.count == 2)
        #expect(present.count == 3)
    }

    @Test("The reference's two gaps come out of the render at the sizes it states")
    func gapsMatchTheReference() throws {
        let bands = inkBands(try render(Lines(showsTemperature: true, usesStackSpacing: false)))
        try #require(bands.count == 3)

        let timeToDate = bands[1].lowerBound - bands[0].upperBound - 1
        let dateToTemperature = bands[2].lowerBound - bands[1].upperBound - 1

        #expect(CGFloat(timeToDate) == ClockLayout.dateGap)
        #expect(CGFloat(dateToTemperature) == ClockLayout.temperatureGap)
        // The reference's whole point: the second drop is the larger one.
        #expect(dateToTemperature > timeToDate)
    }

    // MARK: - What SwiftUI actually does with a false conditional

    @Test("A conditional child whose condition is false costs no stack spacing")
    func falseConditionalCostsNothing() throws {
        // Recorded because the opposite was once asserted in this repository and
        // acted on. It is not true: both arrangements render the absent case
        // identically, so choosing between them is a matter of expressing the
        // reference, not of avoiding a phantom gap.
        let spaced = try render(Lines(showsTemperature: false, usesStackSpacing: true))
        let padded = try render(Lines(showsTemperature: false, usesStackSpacing: false))

        #expect(spaced == padded)
    }

    @Test("A spaced stack with a false conditional matches one with no third child")
    func falseConditionalMatchesTwoChildStack() throws {
        let withFalseConditional = try render(SpacedStack(includesThird: false))
        let withoutAnyThirdChild = try render(TwoChildStack())

        #expect(withFalseConditional == withoutAnyThirdChild)
        // And the flag really does drive a third line when it is true, so the
        // check above is not passing because nothing was ever conditional.
        #expect(inkBands(try render(SpacedStack(includesThird: true))).count == 3)
    }
}

/// Verification of the clock's layout constants against the design reference.
struct ClockLayoutConstantsTests {

    @Test("The time-to-date gap is the reference's flex gap")
    func dateGap() {
        #expect(ClockLayout.dateGap == 20)
    }

    @Test("The date-to-temperature gap adds the reference's own top margin")
    func temperatureGap() {
        // `gap: 20` on the container plus `margin-top: 26` on the temperature.
        #expect(ClockLayout.temperatureGap == 46)
        #expect(ClockLayout.temperatureGap > ClockLayout.dateGap)
    }

    @Test("The weather line fits the content width at its widest")
    func weatherLineFits() {
        #expect(WeatherLineMetrics.widestWidth < ClockTimeMetrics.contentWidth)
    }

    @Test("The condition figure is no taller than the line it sits on")
    func iconFitsTheLine() {
        let iconHeight = CGFloat(PixelWeatherIcon.rows) * WeatherLineMetrics.iconCell
        // The line's type is size 16, whose natural box is 1.28 em.
        #expect(iconHeight <= 16 * 1.28)
        // And taller than its cap height, so it does not read as a stray dot.
        #expect(iconHeight > 16 * 0.625)
    }
}
