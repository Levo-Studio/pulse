import Foundation
import Testing

@testable import Pulse

/// Covers the deliberate change-credential path on both screens.
///
/// The rule under test is the same in each case: opening or cancelling the prompt
/// must leave the stored item exactly as it was, and only a successful save may
/// overwrite it. A user who taps `CHANGE API KEY`, thinks better of it and cancels
/// must not lose the key they still depend on.
///
/// Only the uptime cancel is covered here, because only it exists as a model
/// transition. The GitHub prompt is dismissed by the view alone and the model is
/// never asked to do anything, so there is nothing a test could drive: a case
/// asserting the stored name afterwards would only restate what the save cases
/// already establish, and could not fail.
///
/// Every item is written under a service identifier unique to the test and removed
/// afterwards, so the user's own Keychain items are never read or altered. The values
/// are obvious placeholders, not credentials.
@Suite(.serialized)
struct CredentialChangeTests {

    private static let stored = "stored-placeholder-value"
    private static let replacement = "replacement-placeholder-value"

    private func makeStore() -> KeychainStore {
        KeychainStore(service: "levo-studio.PulseTests.\(UUID().uuidString)")
    }

    // MARK: - Uptime

    @Test("Opening a key change keeps the stored key and offers a way out")
    func uptimeChangeOpensWithoutTouchingTheKey() {
        let keychain = makeStore()
        #expect(keychain.set(Self.stored, for: .uptimeAPIKey))
        defer { keychain.remove(.uptimeAPIKey) }

        let model = UptimeModel(keychain: keychain, client: UptimeAPIClient())
        #expect(!model.isPromptVisible)

        model.beginKeyChange()

        #expect(model.isPromptVisible)
        #expect(model.canCancelKeyChange)
        #expect(model.promptNotice == .replacing)
        #expect(keychain.string(for: .uptimeAPIKey) == Self.stored)
    }

    @Test("Cancelling a key change restores the display and destroys nothing")
    func uptimeCancelKeepsTheStoredKey() {
        let keychain = makeStore()
        #expect(keychain.set(Self.stored, for: .uptimeAPIKey))
        defer { keychain.remove(.uptimeAPIKey) }

        let model = UptimeModel(keychain: keychain, client: UptimeAPIClient())
        model.beginKeyChange()
        model.cancelKeyChange()

        #expect(!model.isPromptVisible)
        #expect(model.promptNotice == .firstUse)
        #expect(keychain.string(for: .uptimeAPIKey) == Self.stored)
    }

    @Test("Saving during a key change overwrites the stored key and closes the prompt")
    func uptimeSaveOverwritesTheStoredKey() {
        let keychain = makeStore()
        #expect(keychain.set(Self.stored, for: .uptimeAPIKey))
        defer { keychain.remove(.uptimeAPIKey) }

        let model = UptimeModel(keychain: keychain, client: UptimeAPIClient())
        model.beginKeyChange()

        #expect(model.store(key: Self.replacement))
        #expect(!model.isPromptVisible)
        #expect(!model.canCancelKeyChange)
        #expect(keychain.string(for: .uptimeAPIKey) == Self.replacement)
    }

    @Test("With no key stored the prompt cannot be cancelled")
    func uptimeFirstUseCannotBeCancelled() {
        let model = UptimeModel(keychain: makeStore(), client: UptimeAPIClient())

        #expect(model.isPromptVisible)
        #expect(!model.canCancelKeyChange)

        // Cancelling a change that was never started must not close the first-use prompt.
        model.cancelKeyChange()
        #expect(model.isPromptVisible)
    }

    // MARK: - GitHub

    @Test("Saving a new username overwrites the stored one and drops the old data")
    @MainActor
    func gitHubSaveOverwritesTheStoredUsername() {
        let keychain = makeStore()
        #expect(keychain.set("octocat", for: .gitHubUsername))
        defer { keychain.remove(.gitHubUsername) }

        let model = GitHubActivityModel(store: keychain)
        model.restoreUsername()
        #expect(model.username == "octocat")

        #expect(model.save(username: "monalisa"))
        #expect(model.username == "monalisa")
        #expect(model.contributions.isEmpty)
        #expect(keychain.string(for: .gitHubUsername) == "monalisa")
    }

    @Test("A rejected username leaves the stored one in place")
    @MainActor
    func gitHubInvalidNameKeepsTheStoredUsername() {
        let keychain = makeStore()
        #expect(keychain.set("octocat", for: .gitHubUsername))
        defer { keychain.remove(.gitHubUsername) }

        let model = GitHubActivityModel(store: keychain)
        model.restoreUsername()

        #expect(!model.save(username: "not a valid name"))
        #expect(model.username == "octocat")
        #expect(keychain.string(for: .gitHubUsername) == "octocat")
    }
}
