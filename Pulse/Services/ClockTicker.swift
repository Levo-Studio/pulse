import Foundation
import Observation
import UIKit

/// How often the clock has to wake to stay correct.
///
/// The display shows either `HH:mm` or `HH:mm:ss`, and the ticker's cadence
/// follows whichever is on screen: there is no reason to wake once a second for a
/// readout that only changes once a minute, and no way to stay correct at one
/// wake a minute for a readout that changes every second.
nonisolated public enum ClockGranularity: Equatable, Sendable {

    /// The readout is `HH:mm`; wake on the wall-clock minute.
    case minute

    /// The readout is `HH:mm:ss`; wake on the wall-clock second.
    case second

    /// The wall-clock boundary the next wake-up is scheduled onto, in seconds.
    public var period: TimeInterval {
        switch self {
        case .minute: 60
        case .second: 1
        }
    }

    /// How much slack the timer is given, so the system can coalesce the wake-up
    /// with other work. A quarter second is invisible on a minute readout; a
    /// second readout can only afford a fraction of that.
    public var tolerance: TimeInterval {
        switch self {
        case .minute: 0.25
        case .second: 0.02
        }
    }
}

/// Keeps a `ClockReading` current while the clock screen is on screen.
///
/// The ticker is deliberately cheap: at its default granularity it wakes once a
/// minute rather than once a second, because the display shows `HH:mm`. Each
/// wake-up is scheduled onto the next wall-clock boundary of the current
/// `granularity` and the reading is recomputed from `Date()`, so the tick never
/// accumulates drift — a late or coalesced fire still renders the correct time.
///
/// Revealing seconds moves the ticker to `.second`, and hiding them moves it back
/// to `.minute`. A 1 Hz timer is never left running behind an `HH:mm` readout.
///
/// Nothing runs while the ticker is stopped. The clock screen stops it whenever
/// it is paged away or the app leaves the foreground.
@MainActor
@Observable
public final class ClockTicker {

    /// The reading currently on display.
    public private(set) var reading: ClockReading

    /// Whether a tick is scheduled.
    public var isRunning: Bool { timer != nil }

    /// When the next tick will fire, or `nil` when the ticker is stopped.
    ///
    /// Exposed so the scheduling can be verified rather than assumed: the whole
    /// point of the granularity is which boundary this lands on.
    public var nextTick: Date? { timer?.fireDate }

    /// How often the ticker wakes.
    ///
    /// Changing this while the ticker is running reschedules it immediately, so
    /// revealing seconds does not wait out the rest of the current minute before
    /// the readout starts moving.
    public var granularity: ClockGranularity = .minute {
        didSet {
            guard granularity != oldValue, isRunning else { return }
            start()
        }
    }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var timeChangeObserver: NSObjectProtocol?

    /// Creates a stopped ticker holding the reading for the current instant.
    public init() {
        self.reading = .now
    }

    deinit {
        // The observer outlives the ticker unless it is removed explicitly.
        if let timeChangeObserver {
            NotificationCenter.default.removeObserver(timeChangeObserver)
        }
    }

    /// Refreshes the reading and begins ticking.
    ///
    /// Safe to call when already running; the existing tick is replaced.
    public func start() {
        stop()
        reading = .now
        observeSignificantTimeChanges()
        scheduleNextTick()
    }

    /// Cancels the pending tick and stops observing system time changes.
    public func stop() {
        timer?.invalidate()
        timer = nil

        if let timeChangeObserver {
            NotificationCenter.default.removeObserver(timeChangeObserver)
            self.timeChangeObserver = nil
        }
    }

    // MARK: - Scheduling

    private func scheduleNextTick() {
        let now = Date()
        let period = granularity.period
        let secondsIntoPeriod = now.timeIntervalSince1970.truncatingRemainder(dividingBy: period)
        let secondsToBoundary = period - secondsIntoPeriod

        let timer = Timer(fire: now.addingTimeInterval(secondsToBoundary), interval: 0, repeats: false) { [weak self] _ in
            // The timer is scheduled on the main run loop, so this closure is
            // already running on the main actor; the reading is recomputed from
            // the clock rather than advanced, so a coalesced fire stays correct.
            MainActor.assumeIsolated {
                self?.tick()
            }
        }

        // A little slack lets the system coalesce the wake-up with other work.
        timer.tolerance = granularity.tolerance

        // Common mode so the tick is not suspended while the user drags between
        // screens.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        reading = .now
        scheduleNextTick()
    }

    /// Reacts to the clock being set, the time zone changing, and midnight — all
    /// of which change the displayed strings outside the normal minute rhythm.
    private func observeSignificantTimeChanges() {
        timeChangeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.significantTimeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRunning else { return }
                self.timer?.invalidate()
                self.timer = nil
                self.tick()
            }
        }
    }
}
