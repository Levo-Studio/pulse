import SwiftUI

/// Asks the user which GitHub account the contribution screen should display.
///
/// Shown on first use, and again whenever the user chooses to change the account.
/// The username is not a secret, so the field is never masked — but it is still
/// case-preserving text the user has to be able to check, so the entered value is
/// drawn in a monospaced system face by `PixelCredentialField` while the labels
/// around it stay in the pixel face.
///
/// The design reference contains no onboarding frame, so the layout comes from
/// `CredentialPromptScaffold`, which is shared with the uptime key prompt.
public struct GitHubUsernamePrompt: View {

    private let owner: PulseScreen
    private let canCancel: Bool
    private let onSubmit: (String) -> Bool
    private let onCancel: () -> Void

    @State private var text = ""
    @State private var notice: Notice?
    @FocusState private var isFocused: Bool

    /// What went wrong with the last attempt, if anything.
    private enum Notice: Equatable {

        /// The typed value is not a syntactically valid GitHub username.
        case invalid

        /// The Keychain refused the write.
        case storageFailed
    }

    /// Creates the prompt.
    ///
    /// The field always opens empty. A stored value is never pre-filled: the same
    /// prompt is used for a credential, and the stored item is replaced only when a
    /// new value is saved.
    ///
    /// - Parameters:
    ///   - owner: The screen this prompt is drawn on. The settings screen shows the
    ///     same prompt, and the focus release has to know which page it is watching
    ///     for.
    ///   - canCancel: Whether the user may dismiss without entering a name. False on
    ///     first use, when the screen has nothing to fall back to.
    ///   - onSubmit: Called with a syntactically valid username. Returns `true` once
    ///     the value has been stored, which closes the prompt.
    ///   - onCancel: Called when the user dismisses the prompt.
    public init(
        owner: PulseScreen,
        canCancel: Bool,
        onSubmit: @escaping (String) -> Bool,
        onCancel: @escaping () -> Void = {}
    ) {
        self.owner = owner
        self.canCancel = canCancel
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    public var body: some View {
        CredentialPromptScaffold(
            eyebrow: "GITHUB",
            title: "USERNAME",
            explanation: [
                "THE ACCOUNT WHOSE",
                "CONTRIBUTION GRAPH IS SHOWN.",
                "PUBLIC DATA ONLY - NO TOKEN",
                "IS REQUESTED OR STORED."
            ],
            notice: scaffoldNotice,
            submitTitle: "CONTINUE",
            isSubmitEnabled: !trimmed.isEmpty,
            submit: submit,
            cancel: canCancel ? onCancel : nil
        ) {
            PixelCredentialField(
                title: "HANDLE",
                placeholder: "YOUR GITHUB NAME",
                privacy: .plain,
                text: $text,
                isFocused: $isFocused,
                onSubmit: submit
            )
        }
        .onAppear { isFocused = true }
        // The keyboard this prompt raises belongs to the window, not to the page, so
        // without this it stays up over the next screen and holds a safe-area inset
        // there. See `releasesFocusWhenPagedAway(from:isFocused:)`.
        .releasesFocusWhenPagedAway(from: owner, isFocused: $isFocused)
        .onChange(of: text) { _, _ in notice = nil }
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var scaffoldNotice: CredentialPromptScaffold<PixelCredentialField>.Notice? {
        switch notice {
        case .none: nil
        case .invalid: .init(text: "NOT A VALID USERNAME.", isFailure: true)
        case .storageFailed: .init(text: "KEYCHAIN WRITE FAILED. RETRY.", isFailure: true)
        }
    }

    private func submit() {
        let candidate = trimmed
        guard GitHubContributionsClient.isValidUsername(candidate) else {
            notice = .invalid
            return
        }
        guard onSubmit(candidate) else {
            notice = .storageFailed
            return
        }
        isFocused = false
    }
}

#Preview {
    GitHubUsernamePrompt(owner: .gitHub, canCancel: false, onSubmit: { _ in true })
}
