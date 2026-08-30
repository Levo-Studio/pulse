import Foundation

/// The two lines the clock screen displays, formatted from a single instant.
///
/// Formatting is pinned to `en_US_POSIX` so the readout never localises: the
/// display is English-only and the pixel typeface carries no accented or
/// non-Latin glyphs. The time zone is read from the device at format time, so a
/// reading taken after the user travels reflects the new zone.
///
/// The shape follows the design reference `01 CLOCK` frame in
/// `design/Pulse.dc.html`: `14:32` above `FR 30 AUG`.
public struct ClockReading: Equatable, Sendable {

    /// Time of day as `HH:mm`, 24-hour.
    public let time: String

    /// Date as a two-letter weekday, day of month, and three-letter month —
    /// for example `FR 30 AUG`.
    public let date: String

    /// Creates a reading from already-formatted strings.
    ///
    /// Used by previews and tests; the app formats from an instant instead.
    public init(time: String, date: String) {
        self.time = time
        self.date = date
    }

    /// Formats the given instant for display.
    public init(instant: Date) {
        let weekday = Self.formatter(pattern: "EEE").string(from: instant).prefix(2)
        let dayMonth = Self.formatter(pattern: "dd MMM").string(from: instant)

        self.time = Self.formatter(pattern: "HH:mm").string(from: instant)
        self.date = "\(weekday) \(dayMonth)".uppercased()
    }

    /// The current reading.
    public static var now: ClockReading {
        ClockReading(instant: Date())
    }

    // MARK: - Formatters

    /// The locale every formatter below is pinned to.
    ///
    /// A fixed POSIX locale keeps the format symbols stable regardless of the
    /// device's region, which is what makes `HH` genuinely 24-hour rather than
    /// silently falling back to a 12-hour clock.
    private static let displayLocale = Locale(identifier: "en_US_POSIX")

    /// A formatter for `pattern`, pinned to the display locale and the device's
    /// current time zone.
    ///
    /// Built per reading rather than cached in a `static`: a reading is taken
    /// once a minute, so the allocation is irrelevant, and a fresh instance
    /// cannot be mutated from two threads or hold a stale time zone.
    ///
    /// Patterns in use: `HH:mm` for the time; `EEE` for the weekday, trimmed to
    /// two letters by the caller so the result does not depend on the shorter
    /// `EEEEEE` symbol; `dd MMM` for the date, zero-padded so the line keeps a
    /// constant width and the centred layout does not shift on single-digit days.
    private static func formatter(pattern: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = displayLocale
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = pattern
        return formatter
    }
}
