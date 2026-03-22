import Foundation
import CoreLocation
import SwiftUI

@Observable class LocationPermissionDelegate: NSObject, CLLocationManagerDelegate {
    // MARK: - Core Dependencies
    @ObservationIgnored var locationManager = CLLocationManager()
    
    // MARK: - State
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @ObservationIgnored var onAuthorizationDetermined: (() -> Void)?
    
    // MARK: - Initialization Engine
    override init() {
        super.init()
        locationManager.delegate = self
        // Initialize authorizationStatus with the current status
        self.authorizationStatus = locationManager.authorizationStatus
    }
    
    // MARK: - Permission Handlers
    func requestWhenInUse() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else {
            DispatchQueue.main.async {
                self.onAuthorizationDetermined?()
            }
        }
    }
    
    // MARK: - CLLocationManagerDelegate Events
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus != .notDetermined {
            DispatchQueue.main.async {
                self.onAuthorizationDetermined?()
            }
        }
    }
}
