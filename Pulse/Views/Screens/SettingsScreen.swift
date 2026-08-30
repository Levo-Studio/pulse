import SwiftUI

/// The SETTINGS screen: the two stored credentials and the two clock display
/// preferences, in one place.
///
/// The design reference has no settings frame, so this screen is assembled from the
/// vocabulary the reference does define rather than invented: the pure black field,
/// the `PixelTheme` palette, letter-spaced uppercase pixel labels, and flat surfaces
/// with no shadow, blur or bloom. The row itself is the uptime list's — name on the
/// left, indicator square on the right, 20 reference units of vertical padding, a
/// one-unit `PixelTheme.separator` hairline underneath — with a second, fainter line
/// under the name carrying the row's current value.
///
/// It is the least-used of the five screens and is reached by the same swipe as the
/// other four, so it is deliberately inert on arrival: nothing is written, nothing is
/// fetched, and no field takes focus. Every change costs a deliberate tap on a row.
///
/// Nothing here is a second source of truth. The clock preferences are the very
/// object the clock screen reads, so a toggle here shows on the clock without a
/// relaunch and the clock's own double taps show here. The credentials are read from
/// and written to the same Keychain items the GitHub and uptime screens use, through
/// the same prompts.
public struct SettingsScreen: View {

    private let preferences: ClockPreferences

    @State private var model: SettingsModel

    @Environment(\.pixelMetrics) private var metrics
    @Environment(\.activeScreen) private var activeScreen

    /// Creates the screen.
    ///
    /// - Parameters:
    ///   - preferences: The clock's display preferences. The same instance the clock
    ///     screen reads, so neither surface can drift from the other.
    ///   - model: The credential state, or `nil` for one reading the app's own
    ///     Keychain items. Tests inject a model over a throwaway service identifier.
    ///     Built inside the initialiser rather than as a default argument, because a
    ///     default argument is evaluated in the caller's isolation and this type is
    ///     main-actor bound.
    public init(preferences: ClockPreferences, model: SettingsModel? = nil) {
        self.preferences = preferences
        _model = State(initialValue: model ?? SettingsModel())
    }

    public var body: some View {
        Group {
            switch model.editing {
            case .none:
                rows
            case .uptimeKey:
                UptimeKeyPrompt(
                    notice: model.isUptimeKeyStored ? .replacing : .firstUse,
                    canCancel: true,
                    submit: { model.save(uptimeKey: $0) },
                    cancel: { model.cancelEditing() }
                )
            case .gitHubUsername:
                GitHubUsernamePrompt(
                    canCancel: true,
                    onSubmit: { model.save(username: $0) },
                    onCancel: { model.cancelEditing() }
                )
            }
        }
        // The Keychain is read once as the page is built and again whenever the screen
        // is paged into view, so a credential changed on the GitHub or uptime screen
        // is current here. Both are single queries on arrival: this screen never polls
        // and does no work at all while it is off-screen. The read on appear is what
        // keeps a row from showing `NOT SET` for the frame between the page being
        // rendered behind the swipe and the swipe being committed.
        .onAppear { model.readStoredState() }
        .task(id: activeScreen) {
            guard activeScreen == .settings else { return }
            model.readStoredState()
        }
    }

    // MARK: - Rows

    private var rows: some View {
        PixelScreenBackdrop(placement: .topInset, alignment: .leading, spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    PixelLabel("SETTINGS", size: 13, tracking: 4, color: PixelTheme.bright)

                    section("CREDENTIALS")

                    SettingsRow(
                        name: "UPTIME API KEY",
                        detail: model.uptimeKeyDetail,
                        isOn: model.isUptimeKeyStored,
                        accessibilityHint: "Opens the prompt to replace the stored key",
                        action: { model.beginEditing(.uptimeKey) }
                    )

                    SettingsRow(
                        name: "GITHUB USERNAME",
                        detail: model.gitHubUsernameDetail,
                        isOn: model.gitHubUsername != nil,
                        accessibilityHint: "Opens the prompt to change the account",
                        action: { model.beginEditing(.gitHubUsername) }
                    )

                    section("CLOCK DISPLAY")

                    SettingsRow(
                        name: "SECONDS",
                        detail: SettingsRow.switchDetail(preferences.showsSeconds),
                        isOn: preferences.showsSeconds,
                        accessibilityHint: "Shows or hides seconds in the clock time",
                        action: { preferences.showsSeconds.toggle() }
                    )

                    SettingsRow(
                        name: "WEATHER CONDITION",
                        detail: SettingsRow.switchDetail(preferences.showsCondition),
                        isOn: preferences.showsCondition,
                        accessibilityHint: "Shows or hides the condition indicator beside the temperature",
                        action: { preferences.showsCondition.toggle() }
                    )

                    PixelLabel(
                        "TAP A ROW TO CHANGE IT",
                        size: 9,
                        tracking: 2,
                        color: PixelTheme.faint
                    )
                    .padding(.top, metrics(24))
                    .padding(.bottom, metrics(16))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// A group heading, in the faintest label colour so it separates without shouting.
    private func section(_ title: String) -> some View {
        PixelLabel(title, size: 9, tracking: 4, color: PixelTheme.faint)
            .padding(.top, metrics(34))
            .padding(.bottom, metrics(4))
    }
}

/// One settings row: what the setting is, what it currently says, and a square
/// standing for its state.
///
/// The whole row is the tap target, so no part of it can be missed on a display this
/// sparse, and it is a `Button` rather than a tap gesture — a button does not fire
/// while a drag is in flight, which is what keeps a swipe between screens from
/// changing anything on the way past.
struct SettingsRow: View {

    /// The setting's name, in the uptime list's row type.
    let name: String

    /// The current value, on its own fainter line under the name.
    let detail: String

    /// Whether the indicator square reads as set or as absent.
    let isOn: Bool

    /// What tapping the row does, for VoiceOver.
    let accessibilityHint: String

    /// Performs the row's one mutation.
    let action: () -> Void

    @Environment(\.pixelMetrics) private var metrics

    /// The value line of a preference row.
    static func switchDetail(_ isOn: Bool) -> String {
        isOn ? "ON" : "OFF"
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: metrics(12)) {
                VStack(alignment: .leading, spacing: metrics(6)) {
                    PixelLabel(name, size: 13, tracking: 2, color: PixelTheme.bright)
                    PixelLabel(detail, size: 10, tracking: 2, color: PixelTheme.muted)
                }
                Spacer(minLength: metrics(12))
                PixelCell(
                    // The palette's own "no data" square stands for off and for
                    // absent, exactly as it does on the uptime list, so the screen
                    // needs no colour the reference does not already carry.
                    color: isOn ? PixelTheme.bright : PixelTheme.statusUnknown,
                    side: metrics(SettingsRowMetrics.squareSide)
                )
            }
            .padding(.vertical, metrics(20))
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(PixelTheme.separator)
                    .frame(height: max(1, metrics(1)))
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(detail)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
    }
}

/// The row arithmetic behind the value line, in design-reference units.
///
/// A GitHub handle is up to 39 characters and `PixelLabel` neither wraps nor
/// compresses, so an unshortened handle would run off both edges of the row. The
/// figures are kept apart from the view and pinned by a test rather than left as
/// inline literals, exactly as `UptimeRowMetrics` is.
enum SettingsRowMetrics {

    /// Width of the reference frame's content area: the 360 unit frame less the
    /// backdrop's 26 units of padding either side.
    static let contentWidth: CGFloat = 360 - (2 * 26)

    /// Side of the state square, matching the uptime list's status square.
    static let squareSide: CGFloat = 11

    /// Horizontal space the row spends between its text and the square: the `HStack`
    /// spacing either side of the spacer, plus the spacer's own minimum length.
    static let gapWidth: CGFloat = 3 * 12

    /// Width the value line has to itself.
    static let detailWidthBudget = contentWidth - squareSide - gapWidth

    /// Advance of one character of the value line, at size 10 with 2 units of
    /// tracking, budgeted against Silkscreen's **widest** advance of 0.875 em. The
    /// face is not fixed-pitch, so budgeting against an average would under-reserve
    /// for a value made entirely of wide glyphs.
    static let characterWidth: CGFloat = (10 * 0.875) + 2

    /// How many characters of a value fit on a row.
    static let characterBudget = Int(detailWidthBudget / characterWidth)

    /// Marker appended to a shortened value, matching the uptime list's.
    static let truncationMarker = "..."

    /// Shortens `value` to what a row can hold.
    static func detail(for value: String) -> String {
        guard value.count > characterBudget else { return value }
        let kept = characterBudget - truncationMarker.count
        return value.prefix(max(kept, 1)) + truncationMarker
    }
}

/// The state behind the settings screen: which credentials are stored, and which
/// prompt — if any — the user has deliberately opened.
///
/// **The uptime key's value is never read into this type.** Whether one is stored is
/// answered by a Keychain query that returns no data at all, so the screen can report
/// `SET` without the secret ever being copied out of the Keychain, held in memory, or
/// put somewhere it could be drawn or logged. The GitHub username is not a credential
/// and is shown in full.
///
/// The Keychain store is injected, with the real one as the default, so the tests
/// exercise a throwaway service identifier rather than the user's own items.
@MainActor
@Observable
public final class SettingsModel {

    /// Which prompt is open.
    public enum Editing: Equatable, Sendable {

        /// The uptime API key prompt.
        case uptimeKey

        /// The GitHub username prompt.
        case gitHubUsername
    }

    /// Whether an uptime API key is stored. The value itself is never read.
    public private(set) var isUptimeKeyStored = false

    /// The stored GitHub handle, or `nil` when none is stored.
    public private(set) var gitHubUsername: String?

    /// The prompt the user has opened, or `nil` when the row list is showing.
    public private(set) var editing: Editing?

    @ObservationIgnored private let keychain: KeychainStore

    /// Creates the model.
    ///
    /// - Parameter keychain: Where the credentials are read from and written to.
    public init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    /// The uptime row's value line.
    ///
    /// Deliberately says only whether a key exists. Never the key, never a prefix of
    /// it, never its length: a fragment of a bearer token on an always-on ambient
    /// display is still a fragment of a bearer token.
    public var uptimeKeyDetail: String {
        isUptimeKeyStored ? "SET" : "NOT SET"
    }

    /// The GitHub row's value line: the handle, shortened to what a row can hold.
    public var gitHubUsernameDetail: String {
        guard let gitHubUsername else { return "NOT SET" }
        return SettingsRowMetrics.detail(for: gitHubUsername)
    }

    /// Re-reads what is stored. Called when the screen is paged into view.
    public func readStoredState() {
        isUptimeKeyStored = keychain.hasValue(for: .uptimeAPIKey)
        gitHubUsername = keychain.string(for: .gitHubUsername)
    }

    /// Opens a prompt. Nothing is written and nothing stored is touched.
    public func beginEditing(_ target: Editing) {
        editing = target
    }

    /// Closes a prompt without writing anything.
    public func cancelEditing() {
        editing = nil
    }

    /// Stores a new uptime API key, replacing any already there.
    ///
    /// The typed value is handed straight to the Keychain and dropped: it is not held
    /// on this type and is never logged.
    ///
    /// - Returns: `true` when the key reached the Keychain, which closes the prompt.
    @discardableResult
    public func save(uptimeKey key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, keychain.set(trimmed, for: .uptimeAPIKey) else { return false }
        isUptimeKeyStored = true
        editing = nil
        return true
    }

    /// Stores a new GitHub username, replacing any already there.
    ///
    /// Validity is checked here as well as in the prompt, so the model cannot be made
    /// to store a name the GitHub client would refuse to request.
    ///
    /// - Returns: `true` when the name reached the Keychain, which closes the prompt.
    @discardableResult
    public func save(username name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard GitHubContributionsClient.isValidUsername(trimmed) else { return false }
        guard keychain.set(trimmed, for: .gitHubUsername) else { return false }
        gitHubUsername = trimmed
        editing = nil
        return true
    }
}

#Preview {
    @Previewable @State var preferences = ClockPreferences()

    SettingsScreen(preferences: preferences)
}
