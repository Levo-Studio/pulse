import SwiftUI

/// A single-line entry field for a credential, drawn to sit on the black pixel field
/// without borrowing iOS chrome.
///
/// **The entered value deliberately breaks the pixel typography rule.** Everything
/// else in Pulse is rendered through `PixelLabel`, which draws Silkscreen and
/// uppercases its copy. That is right for display type and wrong for input: an uptime
/// API key is case-sensitive and contains lowercase letters, and Silkscreen is an
/// uppercase-oriented face with no distinct lowercase forms. A key typed into a pixel
/// field is unreadable and unverifiable — the user cannot confirm what they typed, and
/// a wrong character stays invisible until the request is rejected. The value is
/// therefore drawn in a monospaced system face, at its natural case, and never passes
/// through `PixelLabel`. The label, placeholder and reveal control around it stay in
/// the pixel face, so the field still reads as part of the display.
///
/// The field is flat: a near-black surface with a hairline that brightens on focus,
/// no shadow, blur or bloom, matching the reference's `NO GLOW` treatment.
public struct PixelCredentialField: View {

    /// Whether the field hides what is typed into it.
    public enum Privacy: Equatable, Sendable {

        /// A secret. Masked by default, with a control to reveal it for checking.
        case secret

        /// Not a secret, and never masked.
        case plain
    }

    private let title: String
    private let placeholder: String
    private let privacy: Privacy
    private let text: Binding<String>
    private let isFocused: FocusState<Bool>.Binding
    private let onSubmit: () -> Void

    @State private var isRevealed = false

    @Environment(\.pixelMetrics) private var metrics

    /// Creates a credential field.
    ///
    /// - Parameters:
    ///   - title: Pixel-face label above the field.
    ///   - placeholder: Pixel-face hint shown while the field is empty.
    ///   - privacy: Whether the value is masked by default.
    ///   - text: The entered value. Held by the caller and never persisted anywhere
    ///     but the Keychain.
    ///   - isFocused: Focus binding owned by the caller, so it can focus the field on
    ///     appear and drop focus on submit.
    ///   - onSubmit: Called when the keyboard's return key is pressed.
    public init(
        title: String,
        placeholder: String,
        privacy: Privacy,
        text: Binding<String>,
        isFocused: FocusState<Bool>.Binding,
        onSubmit: @escaping () -> Void
    ) {
        self.title = title
        self.placeholder = placeholder
        self.privacy = privacy
        self.text = text
        self.isFocused = isFocused
        self.onSubmit = onSubmit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: metrics(10)) {
            HStack(alignment: .center, spacing: metrics(12)) {
                PixelLabel(title, size: 9, tracking: 3, color: PixelTheme.muted)
                Spacer(minLength: metrics(12))
                // The reveal only makes sense once there is something to reveal, and an
                // empty field should not carry the brightest control on the screen.
                if privacy == .secret, !text.wrappedValue.isEmpty {
                    revealToggle
                }
            }

            field
        }
    }

    // MARK: - Field surface

    private var field: some View {
        ZStack(alignment: .leading) {
            if text.wrappedValue.isEmpty {
                PixelLabel(placeholder, size: 10, tracking: 3, color: PixelTheme.faint)
                    .allowsHitTesting(false)
            }
            input
        }
        .padding(.horizontal, metrics(14))
        .frame(height: metrics(52))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.surface)
        .overlay {
            Rectangle()
                .stroke(
                    // Focus is stated in the palette's own terms: the hairline goes from
                    // the list separator to bright, which is how the reference marks
                    // what is current.
                    isFocused.wrappedValue ? PixelTheme.bright : PixelTheme.separator,
                    lineWidth: max(1, metrics(1))
                )
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused.wrappedValue = true }
    }

    @ViewBuilder
    private var input: some View {
        if privacy == .secret, !isRevealed {
            SecureField("", text: text)
                .textContentType(.password)
                .modifier(CredentialInputStyle())
                .focused(isFocused)
                .onSubmit(onSubmit)
        } else {
            TextField("", text: text)
                .textContentType(privacy == .secret ? .password : .username)
                .modifier(CredentialInputStyle())
                .focused(isFocused)
                .onSubmit(onSubmit)
        }
    }

    /// Lets the user check a long opaque token before submitting it.
    ///
    /// Masking stays the default; revealing is an explicit, reversible act by the
    /// person who typed the value.
    private var revealToggle: some View {
        Button {
            isRevealed.toggle()
            // Swapping between the secure and plain field replaces the responder, so
            // focus is re-asserted rather than dropped mid-edit.
            isFocused.wrappedValue = true
        } label: {
            PixelLabel(
                isRevealed ? "HIDE" : "SHOW",
                size: 9,
                tracking: 3,
                color: PixelTheme.bright
            )
            .frame(minWidth: metrics(52), minHeight: 44, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRevealed ? "Hide the entered value" : "Show the entered value")
    }

    /// The field's surface: a shade above pure black, so the field reads as a field on
    /// a black screen without a rounded iOS control behind it.
    private static let surface = Color(hex: 0x0C0C0C)
}

/// The shared appearance of an entry field's value.
///
/// Kept in one place so the uptime key and the GitHub username are typographically
/// identical, and so the reasoning for the monospaced system face lives beside the
/// only code that applies it.
private struct CredentialInputStyle: ViewModifier {

    func body(content: Content) -> some View {
        content
            // A case-sensitive credential must be readable exactly as typed, so this is
            // the one place in the app that does not use the pixel face.
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(PixelTheme.primary)
            .tint(PixelTheme.primary)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.asciiCapable)
            .submitLabel(.done)
    }
}

#Preview {
    @Previewable @State var value = ""
    @Previewable @FocusState var focus: Bool

    VStack(spacing: 40) {
        PixelCredentialField(
            title: "API KEY",
            placeholder: "PASTE OR TYPE YOUR KEY",
            privacy: .secret,
            text: $value,
            isFocused: $focus,
            onSubmit: {}
        )
        PixelCredentialField(
            title: "USERNAME",
            placeholder: "GITHUB HANDLE",
            privacy: .plain,
            text: $value,
            isFocused: $focus,
            onSubmit: {}
        )
    }
    .padding(26)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(PixelTheme.background)
}
