import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Pulse

/// Renders the GitHub screen at real device sizes and checks the block of small labels
/// at its foot still fits.
///
/// The design reference ends the frame with one line; Pulse can end it with four. That
/// is the kind of change that looks fine on a large phone and runs off the bottom of a
/// small one, so the check is made by rendering the actual view rather than by
/// re-deriving its arithmetic here: the render is what the user sees.
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

    @Test("The footer block fits above the bottom edge at every supported size",
          arguments: GitHubScreenLayoutTests.sizes)
    func footerFitsTheFrame(size: CGSize) async throws {
        let model = try await preparedModel()
        // The screen only earns this check with every line present.
        #expect(model.lastCommitLine != nil)
        #expect(model.pullRequestLine != nil)
        #expect(model.lastCheckLine != nil)

        let image = try render(model: model, size: size)
        let lowestLitRow = try lowestLitRow(in: image)

        // A margin below the last line, rather than merely "not clipped": text touching
        // the bottom edge is already a layout that has run out of room.
        let bottomMargin = CGFloat(image.height) - CGFloat(lowestLitRow)
        #expect(bottomMargin >= 8 * image.scale)

        if ProcessInfo.processInfo.environment["PULSE_RENDER_OUTPUT"] != nil {
            let name = "github-\(Int(size.width))x\(Int(size.height)).png"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try write(image, to: url)
            print("PULSE_RENDER_WROTE \(url.path)")
        }
    }

    // MARK: - Rendering

    private struct RenderedImage {
        let cgImage: CGImage
        let scale: CGFloat
        var width: Int { cgImage.width }
        var height: Int { cgImage.height }
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
        return RenderedImage(cgImage: image, scale: 3)
    }

    /// The lowest row of the render carrying anything but the black field.
    ///
    /// Every element on this screen is drawn in a grey or white on pure black, so "lit"
    /// is simply "brighter than the background". The faintest label in use is `#3D3D3D`,
    /// well above the threshold.
    private func lowestLitRow(in image: RenderedImage) throws -> Int {
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

        for row in stride(from: height - 1, through: 0, by: -1) {
            for column in 0..<width where pixels[(row * width + column) * 4] > 24 {
                return row
            }
        }
        Issue.record("The render is entirely black; nothing was drawn.")
        return height
    }

    private func write(_ image: RenderedImage, to url: URL) throws {
        let data = try #require(UIImage(cgImage: image.cgImage).pngData())
        try data.write(to: url)
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

    /// A push and both kinds of pull request event, timestamped now so they count as
    /// today wherever the suite runs.
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
