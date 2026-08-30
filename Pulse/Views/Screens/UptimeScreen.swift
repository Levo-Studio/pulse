import SwiftUI

/// The UPTIME screen: the Levo Studio service list with a status square per row,
/// the time the API last checked those services, and a countdown to the next refresh.
///
/// The list is refreshed every 20 seconds, but only while this screen is the one in
/// view and the app is in the foreground. Both the countdown and the poll schedule
/// are derived from the timestamp of the last attempt rather than from an
/// accumulating tick, so they stay correct across paging away and back.
public struct UptimeScreen: View {

    @State private var model = UptimeModel()

    @Environment(\.pixelMetrics) private var metrics
    @Environment(\.activeScreen) private var activeScreen
    @Environment(\.scenePhase) private var scenePhase

    /// Creates the screen.
    public init() {}

    public var body: some View {
        Group {
            if model.isPromptVisible {
                keyPrompt
            } else {
                display
            }
        }
        .task(id: isPolling) {
            guard isPolling else { return }
            await model.poll()
        }
        // The settings screen writes the same Keychain item, so a key stored there
        // while this screen was waiting for one is picked up as soon as the screen is
        // paged back into view, rather than on the next launch.
        .onChange(of: activeScreen) {
            guard activeScreen == .uptime else { return }
            model.adoptStoredKey()
        }
    }

    /// Whether the poll loop should be running: this screen is in view, the app is
    /// in the foreground, and there is a key to authenticate with.
    private var isPolling: Bool {
        activeScreen == .uptime && scenePhase == .active && !model.isPromptVisible
    }

    // MARK: - Service list

    private var display: some View {
        PixelScreenBackdrop(placement: .topInset, alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: metrics(6)) {
                PixelLabel(
                    "LAST CHECK: \(model.lastCheckText)",
                    size: 10,
                    tracking: 2,
                    color: PixelTheme.faint
                )
                PixelLabel(
                    "NEXT REFRESH: \(model.secondsUntilRefresh)S",
                    size: 10,
                    tracking: 2,
                    color: PixelTheme.faint
                )
                if let faultText = model.faultText {
                    PixelLabel(faultText, size: 10, tracking: 2, color: PixelTheme.faint)
                }
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.services.enumerated()), id: \.offset) { _, service in
                        UptimeRow(service: service)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .padding(.top, metrics(54))

            changeKeyAction
        }
    }

    /// The way back to the key prompt once a key is stored.
    ///
    /// Without it the only route to the prompt is a key the API has already rejected,
    /// which leaves a user with a rotated key stuck. Kept at the foot of the screen in
    /// the faintest colour so it never competes with the service list above it.
    private var changeKeyAction: some View {
        Button {
            model.beginKeyChange()
        } label: {
            PixelLabel("CHANGE API KEY", size: 10, tracking: 3, color: PixelTheme.faint)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, metrics(20))
        .padding(.bottom, metrics(16))
    }

    // MARK: - First-use key prompt

    private var keyPrompt: some View {
        UptimeKeyPrompt(
            owner: .uptime,
            notice: model.promptNotice,
            canCancel: model.canCancelKeyChange,
            submit: { model.store(key: $0) },
            cancel: { model.cancelKeyChange() }
        )
    }
}

/// The row arithmetic behind name truncation, in design-reference units.
///
/// These are the numbers that decide whether a service name can push the status square
/// off the screen, so they are kept apart from the view and pinned by a test rather
/// than left as inline literals.
///
/// The figures hold at every scale: the widths and the character advance are all
/// design-reference units, so `PixelMetrics` scales them together. Where the scale is
/// clamped on a large display the real row is wider than assumed here, so the limit
/// only ever errs towards truncating early.
enum UptimeRowMetrics {

    /// Width of the reference frame's content area: the 360 unit frame less the
    /// backdrop's 26 units of padding either side.
    static let contentWidth: CGFloat = 360 - (2 * 26)

    /// Side of the status square.
    static let squareSide: CGFloat = 11

    /// Horizontal space the row spends between the name and the square: the `HStack`
    /// spacing either side of the spacer, plus the spacer's own minimum length.
    static let gapWidth: CGFloat = 3 * 12

    /// Width the name has to itself.
    static let nameWidthBudget = contentWidth - squareSide - gapWidth

    /// Advance of one character of the name, at size 13 with 2 units of tracking.
    ///
    /// Silkscreen is **not** fixed-pitch. Measured from the bundled face, which has an
    /// em of 1000 units, advances across `A-Z 0-9 - _ .` run 0.375, 0.625, 0.75 and
    /// 0.875 em, with `M N V W X Y` at the widest. Budgeting against an average would
    /// under-reserve for any name made of wide glyphs, so the widest advance is used
    /// and a name can never overrun regardless of which characters it contains.
    static let characterWidth: CGFloat = (13 * 0.875) + 2

    /// How many characters of a name fit on a row.
    static let characterBudget = Int(nameWidthBudget / characterWidth)

    /// Marker appended to a shortened name.
    ///
    /// Three full stops rather than `…`. The bundled face does carry U+2026, but it
    /// draws it as one 0.875 em glyph, where three 0.375 em stops read more clearly on
    /// the pixel grid.
    static let truncationMarker = "..."

    /// Shortens `name` to what a row can hold.
    static func displayName(for name: String) -> String {
        guard name.count > characterBudget else { return name }
        let kept = characterBudget - truncationMarker.count
        return name.prefix(max(kept, 1)) + truncationMarker
    }
}

/// One row of the uptime list: the service name against its status square.
private struct UptimeRow: View {

    let service: UptimeService

    @Environment(\.pixelMetrics) private var metrics

    var body: some View {
        HStack(alignment: .center, spacing: metrics(12)) {
            // `PixelLabel` is deliberately `fixedSize`, so it cannot be compressed by
            // the spacer: an overlong name would push the status square off-screen.
            // Names come from the API and are not under the app's control, so they are
            // shortened here rather than by relaxing the shared label.
            PixelLabel(displayName, size: 13, tracking: 2, color: PixelTheme.bright)
            Spacer(minLength: metrics(12))
            PixelCell(color: colour, side: metrics(UptimeRowMetrics.squareSide))
        }
        .padding(.vertical, metrics(20))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PixelTheme.separator)
                .frame(height: metrics(1))
        }
    }

    /// The service name, shortened to what the row can hold.
    private var displayName: String {
        UptimeRowMetrics.displayName(for: service.name)
    }

    private var colour: Color {
        switch service.status {
        case .operational: PixelTheme.statusOperational
        case .degraded: PixelTheme.statusDegraded
        case .down: PixelTheme.statusDown
        case .unknown: PixelTheme.statusUnknown
        }
    }
}

/// Asks the user for their own uptime API key.
///
/// The key is a long, case-sensitive, opaque bearer token, so the entered value is
/// drawn in a monospaced system face by `PixelCredentialField` while every label
/// around it stays in the pixel face. It is masked by default with an explicit
/// reveal, and the typed value is handed straight to the Keychain and dropped; it is
/// never logged and never held anywhere else.
struct UptimeKeyPrompt: View {

    /// Why the prompt is being shown, which decides the notice above the submit action.
    enum Notice: Equatable {

        /// No key has been supplied yet.
        case firstUse

        /// The API answered `401` with the stored key.
        case keyRejected

        /// The Keychain refused the write.
        case storageFailed

        /// The user asked to replace a key that is already stored.
        case replacing
    }

    /// The screen this prompt is drawn on. The settings screen shows the same
    /// prompt, and the focus release has to know which page it is watching for.
    let owner: PulseScreen

    let notice: Notice
    let canCancel: Bool
    let submit: (String) -> Bool
    let cancel: () -> Void

    @State private var key = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        CredentialPromptScaffold(
            eyebrow: "UPTIME",
            title: "API KEY",
            explanation: [
                "BEARER TOKEN FOR THE",
                "LEVO STUDIO UPTIME API.",
                "GET ONE FROM YOUR ACCOUNT",
                "SETTINGS ON THE UPTIME SITE."
            ],
            notice: scaffoldNotice,
            submitTitle: "SAVE KEY",
            isSubmitEnabled: !trimmedKey.isEmpty,
            submit: save,
            cancel: canCancel ? cancel : nil
        ) {
            PixelCredentialField(
                title: "KEY",
                placeholder: "PASTE OR TYPE YOUR KEY",
                privacy: .secret,
                text: $key,
                isFocused: $isFocused,
                onSubmit: save
            )
        }
        .onAppear { isFocused = true }
        // The keyboard this prompt raises belongs to the window, not to the page, so
        // without this it stays up over the next screen and holds a safe-area inset
        // there. See `releasesFocusWhenPagedAway(from:isFocused:)`.
        .releasesFocusWhenPagedAway(from: owner, isFocused: $isFocused)
    }

    private var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var scaffoldNotice: CredentialPromptScaffold<PixelCredentialField>.Notice? {
        switch notice {
        case .firstUse:
            nil
        case .replacing:
            .init(text: "EXISTING KEY KEPT UNTIL SAVED.", isFailure: false)
        case .keyRejected:
            .init(text: "KEY REJECTED. ENTER IT AGAIN.", isFailure: true)
        case .storageFailed:
            .init(text: "KEYCHAIN WRITE FAILED. RETRY.", isFailure: true)
        }
    }

    /// Hands the typed key over, clearing the field only once it is safely stored.
    private func save() {
        let value = trimmedKey
        guard !value.isEmpty else { return }
        if submit(value) {
            key = ""
            isFocused = false
        }
    }
}

/// The state behind the uptime screen: the last fetched list, when it was fetched,
/// and whether a key is needed.
///
/// Scheduling is timestamp-based. `lastAttempt` is the only clock the loop consults,
/// so a screen that was paged away for a minute refreshes once on return rather than
/// replaying missed ticks.
///
/// The Keychain store and the API client are injected, with the real ones as defaults,
/// so the failure paths that matter — a rejected key leaving the stored one intact, a
/// refused Keychain write — are reachable from tests without touching the network or
/// the user's own item.
@MainActor
@Observable
final class UptimeModel {

    /// Seconds between polls, per the brief.
    static let pollInterval: TimeInterval = 20

    /// The services currently displayed.
    private(set) var services: [UptimeService] = []

    /// Whether the user still has to supply a key.
    private(set) var needsKey: Bool

    /// Whether the user asked to replace a key that is already stored.
    private(set) var isChangingKey = false

    /// Why the key prompt is on screen.
    private(set) var promptNotice: UptimeKeyPrompt.Notice = .firstUse

    /// A description of the last failed refresh, or `nil` when the last one succeeded.
    private(set) var faultText: String?

    /// When the last request completed, successfully or not. Drives the countdown.
    private var lastAttempt: Date?

    /// The newest `lastCheckedAt` across the displayed projects.
    ///
    /// This is the API's own clock, not the device's. `LAST CHECK` reports when the
    /// monitoring service last observed the states on screen, which is what the
    /// squares actually mean; when the app last asked is an implementation detail of
    /// this display and is already implied by the refresh countdown beside it. The
    /// newest of the projects is used because the line answers "when was a check last
    /// performed"; per-project staleness is not drawn, so the two figures are never
    /// shown side by side unlabelled.
    private var lastCheckedAt: Date?

    /// Re-read on every loop pass so the countdown ticks without a stored counter.
    private var now = Date()

    private let keychain: KeychainStore
    private let client: UptimeAPIClient

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        // Fixed 24-hour format, matching the reference's `LAST CHECK: 14:32:05`.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - keychain: Where the API key is read from and written to.
    ///   - client: The uptime API client.
    init(keychain: KeychainStore = KeychainStore(), client: UptimeAPIClient = UptimeAPIClient()) {
        self.keychain = keychain
        self.client = client
        needsKey = keychain.string(for: .uptimeAPIKey) == nil
    }

    /// Whether the key prompt is on screen, either because no key is stored or
    /// because the user asked to replace the one that is.
    var isPromptVisible: Bool { needsKey || isChangingKey }

    /// Whether the prompt may be dismissed without saving.
    ///
    /// Only when a key is already stored: the screen has nothing to fall back to
    /// otherwise.
    var canCancelKeyChange: Bool { isChangingKey }

    /// Opens the prompt so the user can replace the stored key.
    ///
    /// The field opens empty — a stored secret is never pre-filled into a field that
    /// can be revealed — and the stored item is left untouched until a new value is
    /// saved.
    func beginKeyChange() {
        promptNotice = .replacing
        isChangingKey = true
    }

    /// Re-checks whether a key is stored, adopting one saved on another screen.
    ///
    /// The settings screen writes the same Keychain item. Only the presence of the
    /// item is consulted, never its value, and only the "a key has appeared" direction
    /// is acted on: a key that has vanished is left to the request that fails on it,
    /// which is the path that already knows how to re-prompt.
    func adoptStoredKey() {
        guard needsKey, !isChangingKey else { return }
        guard keychain.hasValue(for: .uptimeAPIKey) else { return }
        needsKey = false
        promptNotice = .firstUse
        lastAttempt = nil
    }

    /// Closes a key change without touching the stored key.
    func cancelKeyChange() {
        guard isChangingKey else { return }
        isChangingKey = false
        promptNotice = .firstUse
    }

    /// The time the API last checked the projects on screen, in the device's time
    /// zone, or placeholder dashes when it has reported none.
    var lastCheckText: String {
        guard let lastCheckedAt else { return "--:--:--" }
        return Self.clockFormatter.string(from: lastCheckedAt)
    }

    /// Whole seconds left until the next poll, derived from the last attempt.
    ///
    /// Before the first attempt this reads as a full interval rather than zero, so the
    /// line is a live countdown from the moment the screen appears, as in the reference.
    var secondsUntilRefresh: Int {
        guard let lastAttempt else { return Int(Self.pollInterval) }
        // Elapsed time is clamped at zero so the countdown can never read higher than
        // the interval: `now` is sampled by the loop and is momentarily older than the
        // attempt that has just completed, and a backwards system clock would do the
        // same thing more durably.
        let elapsed = max(0, now.timeIntervalSince(lastAttempt))
        return max(0, Int((Self.pollInterval - elapsed).rounded(.up)))
    }

    /// Stores a user-supplied key and resumes polling.
    ///
    /// The value is written to the Keychain and dropped; it is never logged and never
    /// held in this type. A write that fails is surfaced rather than swallowed: the
    /// prompt keeps what the user typed and says what went wrong, instead of leaving a
    /// cleared field behind a button that appears to do nothing.
    ///
    /// - Returns: `true` when the key reached the Keychain.
    func store(key: String) -> Bool {
        guard keychain.set(key, for: .uptimeAPIKey) else {
            promptNotice = .storageFailed
            return false
        }
        promptNotice = .firstUse
        needsKey = false
        isChangingKey = false
        lastAttempt = nil
        return true
    }

    /// Runs the poll loop until the enclosing task is cancelled.
    ///
    /// The loop wakes twice a second to advance the countdown, and issues a request
    /// only once the interval since the last attempt has elapsed.
    func poll() async {
        while !Task.isCancelled {
            now = Date()
            if isRefreshDue {
                await refresh()
                now = Date()
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private var isRefreshDue: Bool {
        guard !needsKey else { return false }
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= Self.pollInterval
    }

    /// Performs a single refresh, whatever the schedule says.
    func refresh() async {
        guard let key = keychain.string(for: .uptimeAPIKey) else {
            needsKey = true
            return
        }

        do {
            let fetched = try await client.services(key: key)
            services = fetched
            lastAttempt = Date()
            lastCheckedAt = fetched.compactMap(\.lastCheckedAt).max()
            faultText = nil
        } catch is CancellationError {
            // Paged away mid-request: leave the schedule untouched so returning to
            // the screen refreshes immediately rather than waiting out an interval.
            return
        } catch UptimeAPIClient.Failure.unauthorized {
            // The stored key is deliberately left in place. It may be the user's only
            // copy of a long opaque token, and a single transient 401 — a proxy
            // answering during a deploy, an auth-path blip — must not destroy it.
            // Re-prompting does not require deleting; the item is overwritten only
            // when the user saves a new value.
            services = []
            lastAttempt = nil
            lastCheckedAt = nil
            faultText = nil
            promptNotice = .keyRejected
            needsKey = true
        } catch {
            // Every other failure leaves the previous list on screen and schedules the
            // next attempt normally, so a flapping API is not hammered.
            lastAttempt = Date()
            faultText = Self.faultText(for: error)
        }
    }

    /// A short, honest description of a failed refresh for the meta block.
    ///
    /// A transport failure and a server or schema fault read differently: calling a
    /// `500` a connection failure misdescribes what happened. No response body and no
    /// underlying error text is used, since either could carry credentials.
    private static func faultText(for error: Error) -> String {
        switch error {
        case UptimeAPIClient.Failure.unreachable:
            "CONNECTION FAILED"
        case UptimeAPIClient.Failure.malformedResponse:
            "UNREADABLE RESPONSE"
        case UptimeAPIClient.Failure.server(let status):
            "SERVER ERROR: \(status)"
        default:
            "REFRESH FAILED"
        }
    }
}

#Preview {
    UptimeScreen()
}
