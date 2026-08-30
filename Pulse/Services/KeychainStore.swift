import Foundation
import Security

/// Stores the small pieces of user-supplied configuration Pulse needs — a GitHub
/// username and an Uptime API key — in the system Keychain.
///
/// Nothing here is ever written to `UserDefaults` or to a plist: the API key is a
/// credential, and the username is entered by the user and kept beside it so both
/// are removed together when the user resets the app.
public struct KeychainStore {

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

    /// Stores `value` under `key`, replacing anything already there.
    ///
    /// - Returns: `true` when the write succeeded.
    @discardableResult
    public func set(_ value: String, for key: Key) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query = baseQuery(for: key)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
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
