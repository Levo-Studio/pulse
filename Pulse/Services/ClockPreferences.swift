import Foundation
import Observation

/// The two things the user can change about the clock screen by double-tapping
/// it: whether the time shows seconds, and whether the weather condition
/// indicator is drawn.
///
/// Both are display preferences, not credentials, so they live in `UserDefaults`.
/// Nothing here is secret, nothing identifies the user, and nothing belongs in
/// the Keychain — which is reserved for the GitHub username and the uptime API
/// key.
///
/// The defaults store is injected so the persistence can be exercised against a
/// throwaway suite rather than the user's own.
@MainActor
@Observable
public final class ClockPreferences {

    /// The `UserDefaults` keys, namespaced to the screen that owns them.
    public enum Key: String, CaseIterable, Sendable {

        /// Whether the time reads `HH:mm:ss` instead of `HH:mm`.
        case showsSeconds = "clock.showsSeconds"

        /// Whether the weather condition indicator is drawn beside the temperature.
        case showsCondition = "clock.showsCondition"
    }

    /// Whether the time reads `HH:mm:ss` instead of `HH:mm`.
    ///
    /// Off by default: the design reference draws `14:32`, and the minute readout
    /// is what the screen ships as.
    public var showsSeconds: Bool {
        didSet { defaults.set(showsSeconds, forKey: Key.showsSeconds.rawValue) }
    }

    /// Whether the weather condition indicator is drawn beside the temperature.
    ///
    /// On by default, so the indicator is visible without the user having to
    /// discover the gesture. It only ever appears when there is a temperature to
    /// sit beside.
    public var showsCondition: Bool {
        didSet { defaults.set(showsCondition, forKey: Key.showsCondition.rawValue) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Loads the stored preferences, falling back to the shipped defaults for any
    /// key that has never been written.
    ///
    /// - Parameter defaults: Where the preferences are read from and written to.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // `bool(forKey:)` cannot tell "never set" from "set to false", so the
        // presence of the key is checked before its value is trusted. Without
        // that, `showsCondition` could never default to `true`.
        showsSeconds = Self.value(in: defaults, for: .showsSeconds, default: false)
        showsCondition = Self.value(in: defaults, for: .showsCondition, default: true)
    }

    private static func value(in defaults: UserDefaults, for key: Key, default fallback: Bool) -> Bool {
        guard defaults.object(forKey: key.rawValue) != nil else { return fallback }
        return defaults.bool(forKey: key.rawValue)
    }
}
