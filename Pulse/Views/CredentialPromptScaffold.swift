import SwiftUI

/// The shared layout of Pulse's two credential prompts: the uptime API key and the
/// GitHub username.
///
/// The design reference carries no onboarding frame, so this screen is built from the
/// reference's own vocabulary rather than invented: the pure black field, the
/// `PixelTheme` palette, letter-spaced uppercase pixel labels, hairline rules, and
/// flat surfaces with no shadow, blur or bloom.
///
/// The hierarchy runs top to bottom in the order the user needs it: which screen is
/// asking, what it wants, where to get it, the field itself, a fixed notice slot, and
/// the submit action. The notice slot keeps its height whether or not a notice is
/// showing, so `KEY REJECTED` appearing never moves the field or the button under the
/// user's finger.
public struct CredentialPromptScaffold<Field: View>: View {

    /// A short line about the state of the prompt, shown above the submit action.
    public struct Notice: Equatable, Sendable {

        /// The copy, rendered in the pixel face like every other label.
        public let text: String

        /// Whether this is a failure, which is drawn in the down colour.
        public let isFailure: Bool

        /// Creates a notice.
        public init(text: String, isFailure: Bool) {
            self.text = text
            self.isFailure = isFailure
        }
    }

    private let eyebrow: String
    private let title: String
    private let explanation: [String]
    private let notice: Notice?
    private let submitTitle: String
    private let isSubmitEnabled: Bool
    private let submit: () -> Void
    private let cancel: (() -> Void)?
    private let field: Field

    @State private var hasAppeared = false

    @Environment(\.pixelMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates a prompt.
    ///
    /// - Parameters:
    ///   - eyebrow: The screen doing the asking, for example `UPTIME`.
    ///   - title: What is being asked for, for example `API KEY`.
    ///   - explanation: One line per row of supporting copy: what the credential is
    ///     for and where to find it. Pixel labels never wrap, so the caller breaks the
    ///     lines rather than passing a paragraph.
    ///   - notice: A state line, or `nil` for none. The slot keeps its height either way.
    ///   - submitTitle: Label of the submit control.
    ///   - isSubmitEnabled: Whether the submit control accepts a tap.
    ///   - submit: Called when the user submits.
    ///   - cancel: Called when the user backs out, or `nil` when there is nothing to
    ///     go back to.
    ///   - field: The entry field, normally a `PixelCredentialField`.
    public init(
        eyebrow: String,
        title: String,
        explanation: [String],
        notice: Notice?,
        submitTitle: String,
        isSubmitEnabled: Bool,
        submit: @escaping () -> Void,
        cancel: (() -> Void)? = nil,
        @ViewBuilder field: () -> Field
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.explanation = explanation
        self.notice = notice
        self.submitTitle = submitTitle
        self.isSubmitEnabled = isSubmitEnabled
        self.submit = submit
        self.cancel = cancel
        self.field = field()
    }

    public var body: some View {
        ZStack {
            PixelTheme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // The block is anchored to the bottom of the frame rather than the top,
                // which keeps the field and the submit control within thumb reach.
                // Clearing the keyboard is not this view's doing: it depends on the
                // keyboard safe-area inset surviving down from `PulsePager`, which is
                // why the pager ignores only the container regions.
                Spacer(minLength: metrics(40))

                heading
                    .modifier(Entrance(isVisible: hasAppeared, order: 0, reduceMotion: reduceMotion))

                field
                    .padding(.top, metrics(40))
                    .modifier(Entrance(isVisible: hasAppeared, order: 1, reduceMotion: reduceMotion))

                noticeSlot
                    .padding(.top, metrics(18))
                    .modifier(Entrance(isVisible: hasAppeared, order: 2, reduceMotion: reduceMotion))

                actions
                    .padding(.top, metrics(14))
                    .modifier(Entrance(isVisible: hasAppeared, order: 2, reduceMotion: reduceMotion))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, metrics(26))
            .padding(.bottom, metrics(28))
        }
        .onAppear { hasAppeared = true }
    }

    // MARK: - Heading

    private var heading: some View {
        VStack(alignment: .leading, spacing: 0) {
            PixelLabel(eyebrow, size: 9, tracking: 4, color: PixelTheme.faint)

            PixelLabel(title, size: 22, tracking: 2, color: PixelTheme.primary)
                .padding(.top, metrics(14))

            Rectangle()
                .fill(PixelTheme.separator)
                .frame(height: max(1, metrics(1)))
                .padding(.top, metrics(20))

            VStack(alignment: .leading, spacing: metrics(7)) {
                ForEach(Array(explanation.enumerated()), id: \.offset) { _, line in
                    PixelLabel(line, size: 9, tracking: 2, color: PixelTheme.muted)
                }
            }
            .padding(.top, metrics(20))
        }
    }

    // MARK: - Notice

    /// A slot of constant height, so a notice appearing or clearing never reflows the
    /// screen under the user's finger.
    private var noticeSlot: some View {
        PixelLabel(
            notice?.text ?? "",
            size: 9,
            tracking: 2,
            color: (notice?.isFailure ?? false) ? PixelTheme.statusDown : PixelTheme.muted
        )
        .frame(height: metrics(14), alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(notice == nil)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: metrics(6)) {
            Button(action: submit) {
                PixelLabel(
                    submitTitle,
                    size: 11,
                    tracking: 4,
                    color: isSubmitEnabled ? PixelTheme.primary : PixelTheme.faint
                )
                .frame(maxWidth: .infinity)
                .frame(height: max(44, metrics(54)))
                .overlay {
                    Rectangle()
                        .stroke(
                            isSubmitEnabled ? PixelTheme.muted : PixelTheme.separator,
                            lineWidth: max(1, metrics(1))
                        )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isSubmitEnabled)

            if let cancel {
                Button(action: cancel) {
                    PixelLabel("CANCEL", size: 9, tracking: 4, color: PixelTheme.faint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            PixelLabel(
                "STORED IN THE KEYCHAIN ONLY",
                size: 9,
                tracking: 2,
                color: PixelTheme.faint
            )
            .padding(.top, cancel == nil ? metrics(24) : metrics(4))
        }
    }
}

/// The prompt's entrance: a short fade and rise, staggered by block.
///
/// Motion is appropriate on an ambient display, but it must stay restrained and must
/// never gate interaction — the content is tappable throughout. Under
/// `accessibilityReduceMotion` the animation is dropped entirely rather than shortened.
private struct Entrance: ViewModifier {

    let isVisible: Bool
    let order: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible || reduceMotion ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 10)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.4).delay(Double(order) * 0.08),
                value: isVisible
            )
    }
}
