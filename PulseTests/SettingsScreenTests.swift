import CoreGraphics
import SwiftUI
import Testing

@testable import Pulse

/// Covers the settings screen: what it reports about the stored credentials, what it
/// is allowed to write, and that the preference rows and the clock's double taps are
/// the same two values rather than two copies of them.
///
/// Every Keychain item is written under a service identifier unique to the test and
/// removed afterwards, so the user's own items are never read or altered. The values
/// are obvious placeholders, not credentials.
@MainActor
@Suite(.serialized)
struct SettingsScreenTests {

    private static let stored = "stored-placeholder-value"
    private static let replacement = "replacement-placeholder-value"

    private func makeStore() -> KeychainStore {
        KeychainStore(service: "levo-studio.PulseTests.\(UUID().uuidString)")
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "levo-studio.PulseTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: - Reported state

    @Test("A stored key is reported as present, and its value is never read")
    func storedKeyIsReportedWithoutBeingRead() {
        let keychain = makeStore()
        #expect(keychain.set(Self.stored, for: .uptimeAPIKey))
        defer { keychain.remove(.uptimeAPIKey) }

        // The presence query returns a status and no data at all: the stored bytes
        // never leave the Keychain.
        #expect(keychain.hasValue(for: .uptimeAPIKey))

        let model = SettingsModel(keychain: keychain)
        model.readStoredState()

        #expect(model.isUptimeKeyStored)
        #expect(model.uptimeKeyDetail == "SET")

        // And the key is not held anywhere on the model either. Asserting against the
        // one string the row draws could not fail — `SET` cannot contain a key — so
        // the whole object is walked instead. This is the assertion that bites when
        // someone adds a `storedKey` property to fill in a richer row: it fails on the
        // property existing, before any view is written to draw it.
        for value in Self.strings(in: model) {
            #expect(!value.contains(Self.stored))
        }
    }

    /// Every string reachable from `subject` by reflection, one level of nesting deep.
    ///
    /// Deep enough to see a stored property holding a credential, whether it is held
    /// directly, in an optional, or in a small wrapper. `@Observable` keeps its stored
    /// properties as ordinary backing fields, so they are visible here.
    private static func strings(in subject: Any) -> [String] {
        var found: [String] = []
        for child in Mirror(reflecting: subject).children {
            if let text = child.value as? String {
                found.append(text)
                continue
            }
            for grandchild in Mirror(reflecting: child.value).children {
                if let text = grandchild.value as? String { found.append(text) }
            }
        }
        return found
    }

    @Test("The reflection guard would catch a credential held on the model")
    func reflectionGuardBites() {
        // The guard above is only worth its lines if it fails when it should, so the
        // shape it is looking for is put in front of it here.
        struct Careless { let key = SettingsScreenTests.stored }

        #expect(Self.strings(in: Careless()).contains(Self.stored))
    }

    @Test("An absent key is reported as absent")
    func absentKeyIsReportedAsAbsent() {
        let keychain = makeStore()
        #expect(!keychain.hasValue(for: .uptimeAPIKey))

        let model = SettingsModel(keychain: keychain)
        model.readStoredState()

        #expect(!model.isUptimeKeyStored)
        #expect(model.uptimeKeyDetail == "NOT SET")
    }

    @Test("The GitHub handle is shown, because it is not a credential")
    func storedUsernameIsShown() {
        let keychain = makeStore()
        #expect(keychain.set("octocat", for: .gitHubUsername))
        defer { keychain.remove(.gitHubUsername) }

        let model = SettingsModel(keychain: keychain)
        model.readStoredState()

        #expect(model.gitHubUsername == "octocat")
        #expect(model.gitHubUsernameDetail == "octocat")
    }

    @Test("A handle too long for a row is shortened rather than allowed to overrun")
    func longHandleIsShortened() {
        let handle = String(repeating: "w", count: 39)
        let shortened = SettingsRowMetrics.detail(for: handle)

        #expect(shortened.count <= SettingsRowMetrics.characterBudget)
        #expect(shortened.hasSuffix(SettingsRowMetrics.truncationMarker))
        #expect(SettingsRowMetrics.detail(for: "octocat") == "octocat")

        // The budget has to leave room for the state square and the gap beside it.
        let width = CGFloat(SettingsRowMetrics.characterBudget) * SettingsRowMetrics.characterWidth
        #expect(width + SettingsRowMetrics.squareSide + SettingsRowMetrics.gapWidth <= SettingsRowMetrics.contentWidth)
    }

    // MARK: - Writing

    @Test("Opening and cancelling a credential edit leaves the Keychain untouched")
    func cancelledEditWritesNothing() {
        let keychain = makeStore()
        #expect(keychain.set(Self.stored, for: .uptimeAPIKey))
        #expect(keychain.set("octocat", for: .gitHubUsername))
        defer {
            keychain.remove(.uptimeAPIKey)
            keychain.remove(.gitHubUsername)
        }

        let model = SettingsModel(keychain: keychain)
        model.readStoredState()

        model.beginEditing(.uptimeKey)
        #expect(model.editing == .uptimeKey)
        model.cancelEditing()

        model.beginEditing(.gitHubUsername)
        #expect(model.editing == .gitHubUsername)
        model.cancelEditing()

        #expect(model.editing == nil)
        #expect(keychain.string(for: .uptimeAPIKey) == Self.stored)
        #expect(keychain.string(for: .gitHubUsername) == "octocat")
    }

    @Test("The uptime prompt is told why it is open, and told when a write succeeds")
    func uptimeNoticeFollowsTheEdit() {
        let keychain = makeStore()
        defer { keychain.remove(.uptimeAPIKey) }

        let model = SettingsModel(keychain: keychain)
        model.readStoredState()

        // Nothing stored yet: the prompt is a first-use prompt, with no notice.
        model.beginEditing(.uptimeKey)
        #expect(model.uptimeNotice == .firstUse)

        #expect(model.save(uptimeKey: Self.stored))
        #expect(model.uptimeNotice == .firstUse)

        // With a key stored the prompt has to say the old one is kept until the new one
        // is saved, exactly as the uptime screen's own route does.
        model.beginEditing(.uptimeKey)
        #expect(model.uptimeNotice == .replacing)

        model.cancelEditing()
        #expect(model.uptimeNotice == .firstUse)
        #expect(keychain.string(for: .uptimeAPIKey) == Self.stored)
    }

    @Test("A saved key overwrites the stored one and closes the prompt")
    func savedKeyOverwrites() {
        let keychain = makeStore()
        #expect(keychain.set(Self.stored, for: .uptimeAPIKey))
        defer { keychain.remove(.uptimeAPIKey) }

        let model = SettingsModel(keychain: keychain)
        model.readStoredState()
        model.beginEditing(.uptimeKey)

        #expect(model.save(uptimeKey: "  \(Self.replacement)  "))

        #expect(model.editing == nil)
        #expect(model.isUptimeKeyStored)
        #expect(keychain.string(for: .uptimeAPIKey) == Self.replacement)
    }

    @Test("A saved username overwrites the stored one, and an invalid one is refused")
    func savedUsernameOverwrites() {
        let keychain = makeStore()
        #expect(keychain.set("octocat", for: .gitHubUsername))
        defer { keychain.remove(.gitHubUsername) }

        let model = SettingsModel(keychain: keychain)
        model.readStoredState()
        model.beginEditing(.gitHubUsername)

        #expect(!model.save(username: "not a username"))
        #expect(model.editing == .gitHubUsername)
        #expect(keychain.string(for: .gitHubUsername) == "octocat")

        #expect(model.save(username: " monalisa "))
        #expect(model.editing == nil)
        #expect(model.gitHubUsername == "monalisa")
        #expect(keychain.string(for: .gitHubUsername) == "monalisa")
    }

    @Test("An empty key is refused rather than written over a good one")
    func emptyKeyIsRefused() {
        let keychain = makeStore()
        #expect(keychain.set(Self.stored, for: .uptimeAPIKey))
        defer { keychain.remove(.uptimeAPIKey) }

        let model = SettingsModel(keychain: keychain)
        model.readStoredState()

        #expect(!model.save(uptimeKey: "   "))
        #expect(keychain.string(for: .uptimeAPIKey) == Self.stored)
    }

    // MARK: - Shared preferences

    @Test("A preference changed in settings is the value the clock draws")
    func preferenceChangeReachesTheClock() throws {
        let preferences = ClockPreferences(defaults: try makeDefaults())
        let settings = SettingsScreen(
            preferences: preferences,
            model: SettingsModel(keychain: makeStore())
        )
        let clock = ClockScreen(preferences: preferences)

        // Arriving on the settings screen writes nothing: a stray swipe into it must
        // leave every preference exactly as it was.
        _ = try render(settings)
        #expect(preferences.showsSeconds == false)
        #expect(preferences.showsCondition == true)

        let minutes = try render(clock)

        // What the SECONDS row's tap does, on the very object the clock was handed.
        preferences.showsSeconds = true

        let seconds = try render(clock)
        #expect(minutes != seconds, "The clock must redraw from the preference settings changed")

        // And the other direction: the clock's own double tap is visible to the row.
        preferences.showsSeconds = false
        #expect(SettingsRow.switchDetail(preferences.showsSeconds) == "OFF")
        preferences.showsCondition = false
        #expect(SettingsRow.switchDetail(preferences.showsCondition) == "OFF")
    }

    // MARK: - Rendering

    private static let renderSize = CGSize(width: 360, height: 780)

    /// Renders `view` at a fixed size and returns its raw RGBA bytes, in the same way
    /// `ClockLayoutTests` does: every input is fixed, so two renders of the same
    /// arrangement are byte-identical and one differing pixel is a real difference.
    private func render(_ view: some View) throws -> [UInt8] {
        let renderer = ImageRenderer(
            content: view.frame(width: Self.renderSize.width, height: Self.renderSize.height)
        )
        renderer.scale = 1

        let image = try #require(renderer.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(
            CGContext(
                data: &pixels,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }
}
