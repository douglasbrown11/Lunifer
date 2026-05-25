import CoreLocation
import Combine

final class LocationManager: NSObject, ObservableObject {

    static let shared = LocationManager()

    private let manager = CLLocationManager()

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// The most recent one-shot coordinate fix, or nil if none has been obtained yet.
    /// Updated each time requestCurrentLocation() produces a result.
    @Published var currentCoordinate: CLLocationCoordinate2D? = nil

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Async version of requestAlwaysAuthorization(). Suspends until the user
    /// responds to the system prompt and the delegate fires, then returns the
    /// resulting CLAuthorizationStatus. Returns immediately if the status is
    /// already determined and no system dialog will be shown.
    func requestAlwaysAuthorizationAsync() async -> CLAuthorizationStatus {
        switch manager.authorizationStatus {
        case .authorizedAlways:
            return .authorizedAlways
        case .denied, .restricted:
            return manager.authorizationStatus
        case .notDetermined, .authorizedWhenInUse:
            break
        @unknown default:
            return manager.authorizationStatus
        }
        return await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestAlwaysAuthorization()
        }
    }

    // Stored continuation for the async authorization path.
    // Bridged from the CLLocationManagerDelegate callback on the main queue.
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    /// Requests a single one-shot location fix. Does nothing if the user
    /// has not granted at least whenInUse authorization. The result is
    /// published on `currentCoordinate` once the fix arrives.
    func requestCurrentLocation() {
        let status = manager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }
        manager.requestLocation()
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.authorizationStatus = manager.authorizationStatus
            // Resume any in-flight async authorization request once the user
            // has made a choice (status is no longer .notDetermined).
            if manager.authorizationStatus != .notDetermined,
               let continuation = self.authorizationContinuation {
                self.authorizationContinuation = nil
                continuation.resume(returning: manager.authorizationStatus)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async { [weak self] in
            self?.currentCoordinate = location.coordinate
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // One-shot fix failed — currentCoordinate stays at its last known value.
        // CommuteManager will fall back to home coordinates automatically.
        print("📍 LocationManager one-shot fix failed: \(error.localizedDescription)")
    }
}
