import SwiftUI

/// The four screens of the display, in swipe order.
public enum PulseScreen: Int, CaseIterable, Identifiable, Sendable {
    case clock
    case stopwatch
    case gitHub
    case uptime

    public var id: Int { rawValue }
}

/// The root of the app: four full-screen views the user pages through horizontally.
///
/// Screens stay alive while off-screen, which is what lets a running stopwatch keep
/// running when the user swipes away. Screens that poll a network do their own
/// visibility gating against `activeScreen` rather than relying on `onAppear`.
public struct PulsePager: View {

    @State private var activeScreen: PulseScreen = .clock

    /// Creates the pager.
    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            TabView(selection: $activeScreen) {
                ForEach(PulseScreen.allCases) { screen in
                    view(for: screen)
                        .tag(screen)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .environment(\.pixelMetrics, PixelMetrics(width: proxy.size.width))
            .environment(\.activeScreen, activeScreen)
        }
        .background(PixelTheme.background)
        .ignoresSafeArea()
        .statusBarHidden()
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
    }

    @ViewBuilder
    private func view(for screen: PulseScreen) -> some View {
        switch screen {
        case .clock: ClockScreen()
        case .stopwatch: StopwatchScreen()
        case .gitHub: GitHubScreen()
        case .uptime: UptimeScreen()
        }
    }
}

private struct ActiveScreenKey: EnvironmentKey {
    static let defaultValue = PulseScreen.clock
}

extension EnvironmentValues {

    /// The screen currently paged into view.
    ///
    /// Screens compare this against their own identity to decide whether to run a
    /// poll loop, so a background screen never holds the network open.
    public var activeScreen: PulseScreen {
        get { self[ActiveScreenKey.self] }
        set { self[ActiveScreenKey.self] = newValue }
    }
}

/// The chrome every screen shares: a black field with the reference's horizontal
/// padding, laid out top-down.
public struct PixelScreenBackdrop<Content: View>: View {

    private let alignment: HorizontalAlignment
    private let content: Content

    @Environment(\.pixelMetrics) private var metrics

    /// Wraps `content` in the standard screen surface.
    public init(
        alignment: HorizontalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.content = content()
    }

    public var body: some View {
        ZStack {
            PixelTheme.background.ignoresSafeArea()
            VStack(alignment: alignment, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, metrics(26))
        }
    }
}
