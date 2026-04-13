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
            self?.authorizationStatus = manager.authorizationStatus
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
