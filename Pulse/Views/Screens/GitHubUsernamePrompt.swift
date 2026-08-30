import SwiftUI

/// Asks the user which GitHub account the contribution screen should display.
///
/// Shown on first use, and again whenever the user corrects a username that returns
/// no data. The design reference contains no onboarding frame, so this view is built
/// from the same palette, typeface and letter-spacing as the rest of the screen
/// rather than from a reference of its own.
public struct GitHubUsernamePrompt: View {

    private let canCancel: Bool
    private let onSubmit: (String) -> Void
    private let onCancel: () -> Void

    @State private var text: String
    @State private var isRejected = false
    @FocusState private var isFocused: Bool

    @Environment(\.pixelMetrics) private var metrics

    /// Creates the prompt.
    ///
    /// - Parameters:
    ///   - initialUsername: Username to pre-fill, empty on first use.
    ///   - canCancel: Whether the user may dismiss without entering a name. False on
    ///     first use, when the screen has nothing to fall back to.
    ///   - onSubmit: Called with a syntactically valid username.
    ///   - onCancel: Called when the user dismisses the prompt.
    public init(
        initialUsername: String = "",
        canCancel: Bool,
        onSubmit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        self.canCancel = canCancel
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        self._text = State(initialValue: initialUsername)
    }

    public var body: some View {
        PixelScreenBackdrop(placement: .centred, spacing: 22) {
            PixelLabel("GITHUB USERNAME", size: 11, tracking: 4, color: PixelTheme.muted)

            VStack(spacing: metrics(10)) {
                TextField(
                    "",
                    text: $text,
                    prompt: Text("USERNAME").foregroundStyle(PixelTheme.faint)
                )
                .font(PixelFont.regular(metrics(18)))
                .tracking(metrics(2))
                .foregroundStyle(PixelTheme.primary)
                .tint(PixelTheme.muted)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .submitLabel(.done)
                .focused($isFocused)
                .onChange(of: text) { _, _ in isRejected = false }
                .onSubmit(submit)

                Rectangle()
                    .fill(PixelTheme.separator)
                    .frame(height: max(1, metrics(1)))
            }
            .frame(maxWidth: .infinity)

            PixelLabel(
                isRejected ? "NOT A VALID USERNAME" : " ",
                size: 9,
                tracking: 2,
                color: PixelTheme.muted
            )

            HStack(spacing: metrics(28)) {
                if canCancel {
                    action("CANCEL", color: PixelTheme.faint, perform: onCancel)
                }
                action("CONTINUE", color: PixelTheme.bright, perform: submit)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused = false }
        .onAppear { isFocused = true }
    }

    private func action(
        _ title: String,
        color: Color,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            PixelLabel(title, size: 10, tracking: 4, color: color)
                .frame(minWidth: 88, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func submit() {
        let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard GitHubContributionsClient.isValidUsername(candidate) else {
            isRejected = true
            return
        }
        isFocused = false
        onSubmit(candidate)
    }
}

#Preview {
    GitHubUsernamePrompt(canCancel: false, onSubmit: { _ in })
}
