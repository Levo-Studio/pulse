import SwiftUI

/// The four screens of the display, in swipe order.
public enum PulseScreen: Int, CaseIterable, Identifiable, Sendable {

    /// Time of day with the date below it.
    case clock

    /// A double-tap stopwatch.
    case stopwatch

    /// GitHub contribution activity.
    case gitHub

    /// Levo Studio service uptime.
    case uptime

    /// Stable identity for `ForEach`.
    public var id: Int { rawValue }
}

/// The root of the app: four full-screen views the user pages through horizontally.
///
/// The pager publishes the screen currently in view through the environment, so a
/// screen that polls the network can stop polling the moment it is paged away.
/// Screens must not assume they stay alive off-screen — `TabView` may tear a page
/// down — so any state that has to survive paging is derived from a timestamp or
/// held above this view rather than inside a page.
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
            .environment(\.pixelMetrics, PixelMetrics(size: fullFrame(proxy)))
            .environment(\.activeScreen, activeScreen)
            // Only the container regions are ignored, so the four display screens are
            // full-bleed to the bezel while the keyboard region keeps its inset. An
            // unqualified `ignoresSafeArea()` here also swallowed `.keyboard`, which
            // left every descendant — including the credential prompts — with no
            // keyboard inset to be lifted by, so the keyboard covered the field and
            // the submit control.
            .ignoresSafeArea(.container)
        }
        .background(PixelTheme.background.ignoresSafeArea())
        .statusBarHidden()
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
    }

    /// The size of the whole frame, safe-area insets included.
    ///
    /// The geometry reader is laid out inside the safe area, so its own size shrinks
    /// while the keyboard is up. Type is scaled from the full frame instead, so the
    /// display never resizes itself when a keyboard appears or goes away.
    private func fullFrame(_ proxy: GeometryProxy) -> CGSize {
        CGSize(
            width: proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
            height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
        )
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
/// padding.
///
/// The reference lays its centred screens — clock and stopwatch — out around the
/// vertical middle, and its list screens — GitHub and uptime — from a 70 pt top
/// inset. `placement` selects between the two.
public struct PixelScreenBackdrop<Content: View>: View {

    /// How the content sits in the frame.
    public enum Placement: Equatable, Sendable {

        /// Centred vertically, as on the clock and stopwatch screens.
        case centred

        /// Flush to the top, below the reference's 70 pt inset, as on the GitHub
        /// and uptime screens.
        case topInset
    }

    private let placement: Placement
    private let alignment: HorizontalAlignment
    private let spacing: CGFloat
    private let content: Content

    @Environment(\.pixelMetrics) private var metrics

    /// Wraps `content` in the standard screen surface.
    ///
    /// - Parameters:
    ///   - placement: Vertical placement of the content in the frame.
    ///   - alignment: Horizontal alignment within the content stack.
    ///   - spacing: Spacing between stacked children, in design-reference units.
    ///   - content: The screen's own content.
    public init(
        placement: Placement = .centred,
        alignment: HorizontalAlignment = .center,
        spacing: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.placement = placement
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        ZStack {
            PixelTheme.background.ignoresSafeArea()

            VStack(alignment: alignment, spacing: metrics(spacing)) {
                if placement == .topInset {
                    Spacer(minLength: 0).frame(height: metrics(70))
                }
                content
                if placement == .topInset {
                    Spacer(minLength: 0)
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: Alignment(horizontal: alignment, vertical: .center)
            )
            .padding(.horizontal, metrics(26))
        }
    }
}
