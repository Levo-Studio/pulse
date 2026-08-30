import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Pulse

/// Renders the GitHub screen at real device sizes and checks where its elements land.
///
/// The screen draws eight horizontal bands — header, commit time, count, `COMMITS
/// TODAY`, heatmap, axis, `LAST CHECK`, `CHANGE USERNAME` — and every one of them is
/// drawn in a colour the palette assigns to it and to nothing else nearby. That is what
/// these cases measure: each band is located by its own colour in the render, and the
/// assertions are about where the bands sit and how wide the grid is. Measuring the
/// render rather than re-deriving the arithmetic keeps the check honest about what the
/// user sees; measuring *elements* rather than lit pixels keeps it honest about the
/// layout rather than about how bright a day's contributions happen to be.
///
/// An earlier version of this suite counted unlit rows instead. It could not fail on
/// the layout it was written to guard — the reference's fixed offsets passed it — and
/// it went red on a quiet day, because an empty heatmap is drawn in `#141414` and never
/// counted as lit. Both faults came from measuring brightness. Colour identifies the
/// element; brightness only reports the weather.
///
/// The shortest device the deployment target allows is 375 × 667, which has no
/// simulator runtime available on this machine, so it is covered here at exactly that
/// size instead.
///
/// Requests are served by the stub, so nothing here touches the network. Payloads are
/// authored, with neutral names; setting `PULSE_EVENTS_FIXTURE` and
/// `PULSE_CONTRIBUTIONS_FIXTURE` to recorded responses renders the same screen from
/// live data instead, which is how the screenshots in review are produced without a
/// real account name entering the repository.
@Suite(.serialized)
@MainActor
struct GitHubScreenLayoutTests {

    /// Device sizes to render, in points: the shortest screen the deployment target
    /// allows, and a current one.
    nonisolated static let sizes = [
        CGSize(width: 375, height: 667),
        CGSize(width: 393, height: 852)
    ]

    // MARK: - Cases

    @Test("The screen draws its eight bands in order, inside the frame",
          arguments: GitHubScreenLayoutTests.sizes)
    func bandsAreDrawnInOrder(size: CGSize) async throws {
        let model = try await preparedModel()
        // The screen only earns these checks with every line present.
        #expect(model.lastCommitTime != nil)
        #expect(model.lastCheckLine != nil)

        let layout = try measure(model: model, size: size)

        // Eight bands, in the order the screen is specified in. A missing or merged
        // band means something has been dropped, has collided with its neighbour, or
        // has run off the frame.
        #expect(layout.bands.count == 8)
        #expect(layout.header.top < layout.commitTime.top)
        #expect(layout.commitTime.bottom < layout.count.top)
        #expect(layout.count.bottom < layout.commitsLabel.top)
        #expect(layout.commitsLabel.bottom < layout.grid.minY)
        #expect(layout.grid.maxY < layout.axis.top)
        #expect(layout.axis.bottom < layout.lastCheck.top)
        #expect(layout.lastCheck.bottom < layout.changeUsername.top)

        // A margin below the last line, rather than merely "not clipped": text touching
        // the bottom edge is already a layout that has run out of room.
        #expect(layout.height - layout.changeUsername.bottom >= 8)
    }

    @Test("The header keeps the reference's top inset and the footer stays at the foot",
          arguments: GitHubScreenLayoutTests.sizes)
    func endsOfTheScreenAreAnchored(size: CGSize) async throws {
        let model = try await preparedModel()
        let layout = try measure(model: model, size: size)
        let inset = layout.metrics(70)

        // The reference sets the frame's content 70 units below the top edge. The
        // header's glyphs start a little below that, inside their own line box.
        #expect(layout.header.top >= inset)
        #expect(layout.header.top <= inset + layout.metrics(12))

        // And the action at the foot sits on the bottom padding rather than floating
        // up into the screen.
        #expect(layout.height - layout.changeUsername.bottom <= layout.metrics(40))

        // The two footer lines belong to each other. This is what the reference's fixed
        // offsets get wrong on a tall screen: with the leftover height falling into a
        // trailing spacer, `LAST CHECK` is left stranded well above `CHANGE USERNAME`
        // instead of the block sitting together at the foot.
        let footerGap = layout.changeUsername.top - layout.lastCheck.bottom
        #expect(
            footerGap <= layout.metrics(34),
            "The footer block is split by \(Int(footerGap)) points at \(size)"
        )
    }

    @Test("The count block is centred between the header and the grid",
          arguments: GitHubScreenLayoutTests.sizes)
    func countBlockIsCentred(size: CGSize) async throws {
        let model = try await preparedModel()
        let layout = try measure(model: model, size: size)

        let above = layout.commitTime.top - layout.header.bottom
        let below = layout.grid.minY - layout.commitsLabel.bottom
        #expect(above > 0)
        #expect(below > 0)

        // Optically centred, not arithmetically: the block is allowed to sit a little
        // high, and is not allowed to drift far either way.
        #expect(
            abs(above - below) <= 0.08 * layout.height,
            "The count block sits \(Int(above)) below the header and \(Int(below)) above the grid"
        )
    }

    @Test("The heatmap keeps the full content width at every supported size",
          arguments: GitHubScreenLayoutTests.sizes)
    func gridFillsTheContentWidth(size: CGSize) async throws {
        let model = try await preparedModel()
        let layout = try measure(model: model, size: size)

        // The reference's 26 unit horizontal padding is all the grid gives up.
        let contentWidth = size.width - (2 * layout.metrics(26))

        // The grid's cells are square by aspect ratio, so any shortfall in the height
        // it is granted comes back as a narrower grid with dead margins either side,
        // under an axis row that still spans the full width. One point of tolerance is
        // for the rounding of 17 cells and 16 gaps into whole pixels.
        #expect(
            layout.grid.width >= contentWidth - 1,
            "The grid draws \(Int(layout.grid.width)) points of \(Int(contentWidth)) at \(size)"
        )
        #expect(layout.grid.width <= contentWidth + 1)

        // And it is centred in that width rather than pushed to one side.
        let leading = layout.grid.minX
        let trailing = size.width - layout.grid.maxX
        #expect(abs(leading - trailing) <= 1)

        // Seven rows of square cells: the grid's own proportion, checked so a grid that
        // fills the width by being stretched rather than by being laid out cannot pass.
        let expectedHeight = (7 * ((layout.grid.width - (16 * layout.metrics(5))) / 17))
            + (6 * layout.metrics(5))
        #expect(abs(layout.grid.height - expectedHeight) <= 2)
    }

    // MARK: - Measurement

    /// Where each band of the screen was drawn, in points.
    private struct Layout {

        let bands: [Band]
        let grid: CGRect
        let height: CGFloat
        let metrics: PixelMetrics

        var header: Band { bands[0] }
        var commitTime: Band { bands[1] }
        var count: Band { bands[2] }
        var commitsLabel: Band { bands[3] }
        var axis: Band { bands[5] }
        var lastCheck: Band { bands[6] }
        var changeUsername: Band { bands[7] }
    }

    /// A run of rows carrying something the palette draws.
    private struct Band {
        let top: CGFloat
        let bottom: CGFloat
    }

    private func measure(model: GitHubActivityModel, size: CGSize) throws -> Layout {
        let image = try render(model: model, size: size)
        let pixels = try samples(of: image)
        let scale = image.scale
        let metrics = PixelMetrics(size: size)

        let rows = (0..<image.height).filter { row in
            (0..<image.width).contains { pixels.isPalette(row: row, column: $0) }
        }
        try #require(!rows.isEmpty, "The render is empty; nothing was drawn.")

        // Bands are runs of drawn rows, split wherever the screen leaves a gap of more
        // than eight reference units. Eight sits between the two gaps that matter: the
        // heatmap's own five unit gutter, which must not cut the grid into seven bands,
        // and the fourteen units the count block puts around its number, which is the
        // narrowest gap the screen leaves between two lines.
        let divider = metrics(8) * scale
        var runs: [(first: Int, last: Int)] = []
        var start = rows[0]
        var previous = rows[0]
        for row in rows.dropFirst() {
            if CGFloat(row - previous - 1) > divider {
                runs.append((start, previous))
                start = row
            }
            previous = row
        }
        runs.append((start, previous))

        let bands = runs.map {
            Band(top: CGFloat($0.first) / scale, bottom: CGFloat($0.last + 1) / scale)
        }

        return Layout(
            bands: bands,
            grid: try gridRect(of: runs, in: pixels, image: image),
            height: CGFloat(image.height) / scale,
            metrics: metrics
        )
    }

    /// The rectangle the heatmap was drawn in.
    ///
    /// The grid is the fifth band down, and its identity is confirmed rather than
    /// assumed: today's cell is drawn from the green ramp at every intensity, including
    /// zero, and green appears nowhere else on the screen. Its width is then the full
    /// horizontal extent of the band, which is what a shrunken grid gives up — its
    /// cells are square, so height it is not granted comes back as width it does not
    /// draw.
    private func gridRect(
        of runs: [(first: Int, last: Int)],
        in pixels: Samples,
        image: RenderedImage
    ) throws -> CGRect {
        let gridIndex = 4
        try #require(runs.count > gridIndex, "The render has no fifth band to be the grid.")
        let run = runs[gridIndex]

        var minX = Int.max
        var maxX = Int.min
        var isGreenSomewhere = false

        for row in run.first...run.last {
            for column in 0..<image.width where pixels.isPalette(row: row, column: column) {
                minX = min(minX, column)
                maxX = max(maxX, column)
                if pixels.isToday(row: row, column: column) { isGreenSomewhere = true }
            }
        }

        try #require(minX <= maxX, "The grid band is empty.")
        #expect(isGreenSomewhere, "The fifth band carries no green cell, so it is not the grid.")

        let scale = image.scale
        return CGRect(
            x: CGFloat(minX) / scale,
            y: CGFloat(run.first) / scale,
            width: CGFloat(maxX - minX + 1) / scale,
            height: CGFloat(run.last - run.first + 1) / scale
        )
    }

    // MARK: - Rendering

    private struct RenderedImage {
        let cgImage: CGImage
        let scale: CGFloat
        var width: Int { cgImage.width }
        var height: Int { cgImage.height }
    }

    /// The render's pixels, classified against the palette the screen draws with.
    private struct Samples {

        let data: [UInt8]
        let width: Int

        /// Today's green ramp, which is drawn on this screen and nowhere else in it.
        static let today: [UInt32] = [0x123A20, 0x166534, 0x199C48, 0x22C55E, 0x4ADE80]

        /// Every colour the screen can draw: both heatmap ramps and every type colour.
        static let palette: [UInt32] = today + [
            0x141414, 0x6E6E6E, 0xA3A3A3, 0xFFFFFF, 0xE6E6E6, 0x525252, 0x3D3D3D
        ]

        func isPalette(row: Int, column: Int) -> Bool {
            matches(row: row, column: column, any: Self.palette)
        }

        func isToday(row: Int, column: Int) -> Bool {
            matches(row: row, column: column, any: Self.today)
        }

        /// Whether a pixel is one of `colours`, allowing for the render's own rounding.
        ///
        /// The tolerance is two levels per channel. The palette's nearest neighbours are
        /// twenty levels apart, so nothing is confusable, and an antialiased glyph edge
        /// is simply not counted — the cores of the glyphs are what locate a line.
        private func matches(row: Int, column: Int, any colours: [UInt32]) -> Bool {
            let offset = ((row * width) + column) * 4
            let red = Int(data[offset])
            let green = Int(data[offset + 1])
            let blue = Int(data[offset + 2])

            return colours.contains { colour in
                abs(red - Int((colour >> 16) & 0xFF)) <= 2
                    && abs(green - Int((colour >> 8) & 0xFF)) <= 2
                    && abs(blue - Int(colour & 0xFF)) <= 2
            }
        }
    }

    private func render(model: GitHubActivityModel, size: CGSize) throws -> RenderedImage {
        PixelFont.register()

        let renderer = ImageRenderer(
            content: GitHubScreen(model: model)
                .environment(\.pixelMetrics, PixelMetrics(size: size))
                .environment(\.activeScreen, .gitHub)
                .frame(width: size.width, height: size.height)
                .background(PixelTheme.background)
        )
        renderer.scale = 3

        let image = try #require(renderer.cgImage)

        if ProcessInfo.processInfo.environment["PULSE_RENDER_OUTPUT"] != nil {
            let name = "github-\(Int(size.width))x\(Int(size.height)).png"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            let data = try #require(UIImage(cgImage: image).pngData())
            try data.write(to: url)
            print("PULSE_RENDER_WROTE \(url.path)")
        }

        return RenderedImage(cgImage: image, scale: 3)
    }

    private func samples(of image: RenderedImage) throws -> Samples {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        let context = try #require(
            CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.draw(image.cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return Samples(data: pixels, width: width)
    }

    // MARK: - Data

    private func preparedModel() async throws -> GitHubActivityModel {
        let store = KeychainStore(service: "levo-studio.PulseTests.\(UUID().uuidString)")
        #expect(store.set("example-account", for: .gitHubUsername))

        RenderStubURLProtocol.eventsBody = try payload("PULSE_EVENTS_FIXTURE", fallback: Self.events)
        RenderStubURLProtocol.contributionsBody = try payload(
            "PULSE_CONTRIBUTIONS_FIXTURE",
            fallback: Self.contributions
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RenderStubURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let model = GitHubActivityModel(
            store: store,
            client: GitHubContributionsClient(session: session),
            eventsClient: GitHubEventsClient(session: session)
        )
        model.restoreUsername()
        await model.refresh()
        store.remove(.gitHubUsername)
        return model
    }

    private func payload(_ variable: String, fallback: String) throws -> Data {
        guard let path = ProcessInfo.processInfo.environment[variable] else {
            return Data(fallback.utf8)
        }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    /// A push, timestamped now so it counts as today wherever the suite runs, beside
    /// two entries of a type the screen no longer reads.
    private static var events: String {
        let formatter = ISO8601DateFormatter()
        let now = formatter.string(from: Date().addingTimeInterval(-1800))
        return """
        [{"type":"PushEvent","created_at":"\(now)","payload":{"ref":"refs/heads/main"}},
         {"type":"PullRequestEvent","created_at":"\(now)","payload":{"action":"opened","number":1}},
         {"type":"PullRequestEvent","created_at":"\(now)","payload":{"action":"merged","number":2}}]
        """
    }

    /// A calendar fragment in the shape the parser reads, with an exact count for
    /// today so the headline is a number rather than the placeholder.
    private static var contributions: String {
        let today = ContributionCalendar.dayKey(for: Date())
        return """
        <table><tbody><tr>
        <td data-date="\(today)" id="day-0" data-level="3" class="ContributionCalendar-day"></td>
        </tr></tbody></table>
        <tool-tip for="day-0">7 contributions on today.</tool-tip>
        """
    }
}

/// Serves the two payloads these renders need.
///
/// Deliberately a class of its own rather than the model tests' stub: suites run in
/// parallel with each other, and a stub's canned state is static, so sharing one
/// between two suites lets each answer the other's requests.
final class RenderStubURLProtocol: URLProtocol, @unchecked Sendable {

    /// Body the events endpoint answers with.
    nonisolated(unsafe) static var eventsBody = Data("[]".utf8)

    /// Body the contributions page answers with.
    nonisolated(unsafe) static var contributionsBody = Data("<html></html>".utf8)

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let isEvents = url.host() == "api.github.com"
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": isEvents ? "application/json" : "text/html"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: isEvents ? Self.eventsBody : Self.contributionsBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
