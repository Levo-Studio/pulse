import SwiftUI

/// The UPTIME screen: the Levo Studio service list with a status square per row,
/// the time of the last successful check, and a countdown to the next one.
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
            if model.needsKey {
                keyPrompt
            } else {
                display
            }
        }
        .task(id: isPolling) {
            guard isPolling else { return }
            await model.poll()
        }
    }

    /// Whether the poll loop should be running: this screen is in view, the app is
    /// in the foreground, and there is a key to authenticate with.
    private var isPolling: Bool {
        activeScreen == .uptime && scenePhase == .active && !model.needsKey
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
                if model.isUnreachable {
                    PixelLabel("CONNECTION FAILED", size: 10, tracking: 2, color: PixelTheme.faint)
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
        }
    }

    // MARK: - First-use key prompt

    private var keyPrompt: some View {
        PixelScreenBackdrop(placement: .centred, alignment: .leading, spacing: 0) {
            UptimeKeyPrompt(
                wasRejected: model.keyWasRejected,
                submit: { model.store(key: $0) }
            )
        }
    }
}

/// One row of the uptime list: the service name against its status square.
private struct UptimeRow: View {

    let service: UptimeService

    @Environment(\.pixelMetrics) private var metrics

    var body: some View {
        HStack(alignment: .center, spacing: metrics(12)) {
            PixelLabel(service.name, size: 13, tracking: 2, color: PixelTheme.bright)
            Spacer(minLength: metrics(12))
            PixelCell(color: colour, side: metrics(11))
        }
        .padding(.vertical, metrics(20))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PixelTheme.separator)
                .frame(height: metrics(1))
        }
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
/// The design reference contains no onboarding frame, so this is built from the same
/// palette and type scale as the rest of the screen rather than from a drawn source.
/// The field is masked, the value goes straight to the Keychain, and it is never held
/// anywhere else.
private struct UptimeKeyPrompt: View {

    let wasRejected: Bool
    let submit: (String) -> Void

    @State private var key = ""

    @Environment(\.pixelMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics(14)) {
            PixelLabel("UPTIME", size: 13, tracking: 2, color: PixelTheme.bright)

            PixelLabel(
                wasRejected ? "KEY REJECTED — ENTER IT AGAIN" : "ENTER YOUR API KEY",
                size: 10,
                tracking: 2,
                color: wasRejected ? PixelTheme.statusDown : PixelTheme.faint
            )

            VStack(alignment: .leading, spacing: metrics(8)) {
                SecureField("", text: $key)
                    .font(PixelFont.regular(metrics(13)))
                    .foregroundStyle(PixelTheme.bright)
                    .tint(PixelTheme.bright)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)
                    .submitLabel(.done)
                    .onSubmit(save)

                Rectangle()
                    .fill(PixelTheme.separator)
                    .frame(height: metrics(1))
            }

            Button(action: save) {
                PixelLabel("SAVE", size: 10, tracking: 2, color: PixelTheme.bright)
                    .padding(.vertical, metrics(9))
                    .padding(.horizontal, metrics(12))
                    .overlay {
                        Rectangle()
                            .stroke(PixelTheme.separator, lineWidth: metrics(1))
                    }
            }
            .buttonStyle(.plain)
            .disabled(trimmedKey.isEmpty)
            .opacity(trimmedKey.isEmpty ? 0.4 : 1)

            PixelLabel("STORED IN THE KEYCHAIN ONLY", size: 10, tracking: 2, color: PixelTheme.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        let value = trimmedKey
        guard !value.isEmpty else { return }
        key = ""
        submit(value)
    }
}

/// The state behind the uptime screen: the last fetched list, when it was fetched,
/// and whether a key is needed.
///
/// Scheduling is timestamp-based. `lastAttempt` is the only clock the loop consults,
/// so a screen that was paged away for a minute refreshes once on return rather than
/// replaying missed ticks.
@MainActor
@Observable
private final class UptimeModel {

    /// Seconds between polls, per the brief.
    static let pollInterval: TimeInterval = 20

    /// The services currently displayed.
    private(set) var services: [UptimeService] = []

    /// Whether the user still has to supply a key.
    private(set) var needsKey: Bool

    /// Whether the last stored key was rejected by the API, as opposed to never set.
    private(set) var keyWasRejected = false

    /// Whether the last attempt failed to reach the API.
    private(set) var isUnreachable = false

    /// When the last check completed, successfully or not. Drives the countdown.
    private var lastAttempt: Date?

    /// When the displayed list was last successfully fetched.
    private var lastSuccess: Date?

    /// Re-read on every loop pass so the countdown ticks without a stored counter.
    private var now = Date()

    private let keychain = KeychainStore()
    private let client = UptimeAPIClient()

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        // Fixed 24-hour format, matching the reference's `LAST CHECK: 14:32:05`.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    init() {
        needsKey = keychain.string(for: .uptimeAPIKey) == nil
    }

    /// The time of the last successful check, or placeholder dashes before the first.
    var lastCheckText: String {
        guard let lastSuccess else { return "--:--:--" }
        return Self.clockFormatter.string(from: lastSuccess)
    }

    /// Whole seconds left until the next poll, derived from the last attempt.
    var secondsUntilRefresh: Int {
        guard let lastAttempt else { return 0 }
        let remaining = Self.pollInterval - now.timeIntervalSince(lastAttempt)
        return max(0, Int(remaining.rounded(.up)))
    }

    /// Stores a user-supplied key and resumes polling.
    ///
    /// The value is written to the Keychain and dropped; it is never logged and never
    /// held in this type.
    func store(key: String) {
        guard keychain.set(key, for: .uptimeAPIKey) else { return }
        keyWasRejected = false
        needsKey = false
        lastAttempt = nil
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

    private func refresh() async {
        guard let key = keychain.string(for: .uptimeAPIKey) else {
            needsKey = true
            return
        }

        do {
            let fetched = try await client.services(key: key)
            services = fetched
            lastAttempt = Date()
            lastSuccess = lastAttempt
            isUnreachable = false
            keyWasRejected = false
        } catch is CancellationError {
            // Paged away mid-request: leave the schedule untouched so returning to
            // the screen refreshes immediately rather than waiting out an interval.
            return
        } catch UptimeAPIClient.Failure.unauthorized {
            keychain.remove(.uptimeAPIKey)
            services = []
            lastAttempt = nil
            lastSuccess = nil
            isUnreachable = false
            keyWasRejected = true
            needsKey = true
        } catch {
            // Transport and schema failures both leave the previous list on screen;
            // the next attempt is scheduled normally so a flapping API is not hammered.
            lastAttempt = Date()
            isUnreachable = true
        }
    }
}

#Preview {
    UptimeScreen()
}
