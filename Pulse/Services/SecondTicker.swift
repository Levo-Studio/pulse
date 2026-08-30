import Foundation
import Observation
import UIKit

/// Publishes the current instant once a second while a screen that shows seconds is
/// on screen.
///
/// The same shape as `ClockTicker`, one order of magnitude faster: each wake-up is
/// scheduled onto the next wall-clock second boundary and the value is recomputed from
/// `Date()` rather than advanced, so a late, coalesced or post-suspension fire still
/// renders the correct second instead of accumulating drift.
///
/// Nothing runs while the ticker is stopped, and a 1 Hz timer is worth stopping: the
/// GitHub screen stops it whenever it is paged away or the app leaves the foreground.
@MainActor
@Observable
public final class SecondTicker {

    /// The instant currently on display.
    public private(set) var now: Date

    /// Whether a tick is scheduled.
    public var isRunning: Bool { timer != nil }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var timeChangeObserver: NSObjectProtocol?

    /// Creates a stopped ticker holding the current instant.
    public init(now: Date = Date()) {
        self.now = now
    }

    deinit {
        // The observer outlives the ticker unless it is removed explicitly.
        if let timeChangeObserver {
            NotificationCenter.default.removeObserver(timeChangeObserver)
        }
    }

    /// Refreshes the instant and begins ticking.
    ///
    /// Safe to call when already running; the existing tick is replaced.
    public func start() {
        stop()
        now = Date()
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
        let instant = Date()
        let intoSecond = instant.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)
        let toBoundary = 1 - intoSecond

        let timer = Timer(
            fire: instant.addingTimeInterval(toBoundary),
            interval: 0,
            repeats: false
        ) { [weak self] _ in
            // The timer is scheduled on the main run loop, so this closure already
            // runs on the main actor.
            MainActor.assumeIsolated {
                self?.tick()
            }
        }

        // Enough slack for the system to coalesce the wake-up, far short of the
        // second it would take to show a stale readout.
        timer.tolerance = 0.05

        // Common mode, so the readout does not freeze while the user drags between
        // screens.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        now = Date()
        scheduleNextTick()
    }

    /// Reacts to the clock being set and to the time zone changing, both of which move
    /// the readout outside the normal rhythm.
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
