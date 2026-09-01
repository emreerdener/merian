import CoreLocation
import Foundation

@MainActor
final class LocationPermissionDelegate: NSObject, CLLocationManagerDelegate {
    // MARK: - Core Dependencies
    private let locationManager: CLLocationManager
    private var authorizationCompletion: OnboardingPermissionCompletion?

    // MARK: - Initialization Engine
    init(locationManager: CLLocationManager = CLLocationManager()) {
        self.locationManager = locationManager
        super.init()
        locationManager.delegate = self
    }

    // MARK: - Permission Handlers
    func requestWhenInUse(
        onAuthorizationDetermined: @escaping OnboardingPermissionCompletion
    ) {
        authorizationCompletion = onAuthorizationDetermined
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else {
            Task { @MainActor [weak self] in
                self?.completeAuthorizationRequest()
            }
        }
    }

    // MARK: - CLLocationManagerDelegate Events
    nonisolated func locationManagerDidChangeAuthorization(
        _: CLLocationManager
    ) {
        Task { @MainActor [weak self] in
            guard let self,
                  self.locationManager.authorizationStatus != .notDetermined
            else { return }
            self.completeAuthorizationRequest()
        }
    }

    private func completeAuthorizationRequest() {
        let completion = authorizationCompletion
        authorizationCompletion = nil
        completion?()
    }
}
