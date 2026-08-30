import Foundation
import Observation
import UIKit

/// Keeps a `ClockReading` current while the clock screen is on screen.
///
/// The ticker is deliberately cheap: it wakes once a minute rather than once a
/// second, because the display shows `HH:mm`. Each wake-up is scheduled onto the
/// next wall-clock minute boundary and the reading is recomputed from `Date()`,
/// so the tick never accumulates drift — a late or coalesced fire still renders
/// the correct minute.
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
        let secondsIntoMinute = now.timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
        let secondsToBoundary = 60 - secondsIntoMinute

        let timer = Timer(fire: now.addingTimeInterval(secondsToBoundary), interval: 0, repeats: false) { [weak self] _ in
            // The timer is scheduled on the main run loop, so this closure is
            // already running on the main actor; the reading is recomputed from
            // the clock rather than advanced, so a coalesced fire stays correct.
            MainActor.assumeIsolated {
                self?.tick()
            }
        }

        // A little slack lets the system coalesce the wake-up with other work.
        timer.tolerance = 0.25

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
