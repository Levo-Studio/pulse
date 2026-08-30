import CoreLocation
import Foundation

/// The result of asking for a coarse fix.
///
/// The two failure cases are kept apart because they call for different
/// behaviour, not different copy: a refusal is permanent for as long as the app
/// runs and there is no point asking again, while an absent fix is worth retrying
/// on the next refresh. Neither is ever shown to the user.
nonisolated public enum CoarseLocationOutcome: Equatable, Sendable {

    /// A usable fix.
    case coordinate(Coordinate)

    /// The user declined, or a restriction such as parental controls forbids it.
    case denied

    /// Authorisation exists but no fix arrived — no signal, airplane mode, or the
    /// request timed out.
    case unavailable
}

/// Something that can supply a coarse coordinate for the weather lookup.
///
/// The clock screen depends on this rather than on `CoreLocationProvider`
/// directly, so the denied and no-fix paths can be exercised in tests without a
/// device, a prompt, or a real fix.
public protocol CoarseLocationProviding {

    /// A single coarse fix, requesting when-in-use authorisation first if the user
    /// has not been asked yet.
    func coarseCoordinate() async -> CoarseLocationOutcome
}

/// A one-shot CoreLocation source for the clock's temperature lookup.
///
/// Three deliberate choices:
///
/// - **When-in-use authorisation only**, requested the first time the clock screen
///   actually needs a coordinate. Nothing is requested at launch.
/// - **Reduced accuracy.** `desiredAccuracy` is `kCLLocationAccuracyReduced`, so
///   the system delivers a deliberately fuzzed fix. A temperature to the nearest
///   degree does not need a precise one, and asking for less is the right default.
/// - **One fix at a time, with a deadline.** `requestLocation` is used rather than
///   continuous updates, and a watchdog closes the request if nothing arrives, so
///   the location hardware is never held open behind an ambient display.
///
/// The coordinate is handed to the caller and dropped. It is never logged and
/// never persisted.
@MainActor
public final class CoreLocationProvider: NSObject, CoarseLocationProviding {

    /// How long to wait for a fix before giving up on it.
    ///
    /// `requestLocation` does eventually fail on its own, but not promptly, and a
    /// pending request would otherwise outlive the screen that asked for it.
    private static let fixDeadline: Duration = .seconds(15)

    private let manager: CLLocationManager
    private var pending: CheckedContinuation<CoarseLocationOutcome, Never>?
    private var watchdog: Task<Void, Never>?

    /// Creates a provider. No authorisation is requested until the first call to
    /// `coarseCoordinate()`.
    public override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    /// A single coarse fix.
    ///
    /// Requests when-in-use authorisation if the user has not been asked yet, then
    /// waits for one location. Returns `.denied` without asking again once the user
    /// has refused.
    public func coarseCoordinate() async -> CoarseLocationOutcome {
        // One request at a time. A second caller arriving while a fix is in flight
        // is told there is nothing available rather than displacing the first.
        guard pending == nil else { return .unavailable }

        switch manager.authorizationStatus {
        case .notDetermined:
            // The prompt is raised here, the first time the clock screen needs a
            // coordinate — never at launch. The status change arrives on the
            // delegate, which starts the fix.
            break
        case .denied, .restricted:
            return .denied
        case .authorizedWhenInUse, .authorizedAlways:
            break
        @unknown default:
            return .unavailable
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pending = continuation
                startWatchdog()

                if manager.authorizationStatus == .notDetermined {
                    manager.requestWhenInUseAuthorization()
                } else {
                    manager.requestLocation()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(with: .unavailable)
            }
        }
    }

    // MARK: - Request lifecycle

    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.fixDeadline)
            guard !Task.isCancelled else { return }
            self?.finish(with: .unavailable)
        }
    }

    /// Resumes the waiting caller exactly once and releases the hardware.
    private func finish(with outcome: CoarseLocationOutcome) {
        guard let continuation = pending else { return }
        pending = nil
        watchdog?.cancel()
        watchdog = nil
        manager.stopUpdatingLocation()
        continuation.resume(returning: outcome)
    }
}

// MARK: - CLLocationManagerDelegate

extension CoreLocationProvider: CLLocationManagerDelegate {

    /// Starts the fix once the user has answered the prompt, or reports the refusal.
    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self, pending != nil else { return }

            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.manager.requestLocation()
            case .denied, .restricted:
                finish(with: .denied)
            case .notDetermined:
                // The prompt is still on screen; the watchdog closes the request if
                // the user never answers it.
                break
            @unknown default:
                finish(with: .unavailable)
            }
        }
    }

    /// Reports the fix. Only the coordinate is read — no timestamp, speed, course
    /// or altitude is taken, and nothing is written anywhere.
    public nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        let raw = locations.last?.coordinate
        Task { @MainActor [weak self] in
            guard let raw, let coordinate = Coordinate(latitude: raw.latitude, longitude: raw.longitude) else {
                self?.finish(with: .unavailable)
                return
            }
            self?.finish(with: .coordinate(coordinate))
        }
    }

    /// Reports a failed fix. The error is not logged: it can name the user's
    /// region and carries nothing the display would act on differently.
    public nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        let isRefusal = (error as? CLError)?.code == .denied
        Task { @MainActor [weak self] in
            self?.finish(with: isRefusal ? .denied : .unavailable)
        }
    }
}
