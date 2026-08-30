import Foundation
import Security

/// Stores the small pieces of user-supplied configuration Pulse needs — a GitHub
/// username and an Uptime API key — in the system Keychain.
///
/// Nothing here is ever written to `UserDefaults` or to a plist: the API key is a
/// credential, and the username is entered by the user and kept beside it so both
/// are removed together when the user resets the app.
///
/// Declared `nonisolated`: the project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION =
/// MainActor`, so without this the store could not be constructed as a default
/// argument or used off the main actor, though it only ever calls Security framework
/// functions that are safe from any thread.
nonisolated public struct KeychainStore {

    /// The items Pulse persists.
    public enum Key: String, CaseIterable, Sendable {

        /// The GitHub account whose contribution graph is displayed.
        case gitHubUsername = "github.username"

        /// The bearer token for the Levo Studio uptime API.
        case uptimeAPIKey = "uptime.api-key"
    }

    /// Keychain service identifier scoping every item Pulse writes.
    private let service: String

    /// Creates a store.
    ///
    /// - Parameter service: Keychain service identifier. Defaults to the app's
    ///   bundle identifier so items cannot collide with another app's.
    public init(service: String = Bundle.main.bundleIdentifier ?? "levo-studio.Pulse") {
        self.service = service
    }

    /// Reads the string stored under `key`, or `nil` if there is none.
    public func string(for key: Key) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    /// Whether an item is stored under `key`, **without reading its value**.
    ///
    /// The query asks for no data and no attributes, so the Keychain answers with a
    /// status and nothing else: the stored bytes are never copied out of the Keychain
    /// and never exist in the app's memory. This is how the settings screen reports
    /// that an API key is set — a value never held cannot be drawn, logged or leaked.
    ///
    /// Use `string(for:)` only where the value is actually needed, which for the API
    /// key is the one place that authenticates a request.
    public func hasValue(for key: Key) -> Bool {
        var query = baseQuery(for: key)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// Stores `value` under `key`, replacing anything already there.
    ///
    /// - Returns: `true` when the write succeeded.
    @discardableResult
    public func set(_ value: String, for key: Key) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query = baseQuery(for: key)
        // Repeated on the update path so an item written by an earlier build is
        // migrated to the stricter accessibility class rather than keeping its own.
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    /// Removes the item stored under `key`. Succeeds when there was nothing to remove.
    @discardableResult
    public func remove(_ key: Key) -> Bool {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func baseQuery(for key: Key) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
    }
}
