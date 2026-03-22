import Foundation
import CoreLocation

class LocationPermissionDelegate: NSObject, ObservableObject, CLLocationManagerDelegate {
    // MARK: - Core Dependencies
    let manager = CLLocationManager()
    
    // MARK: - State Callbacks
    var onAuthorizationDetermined: (() -> Void)?
    
    // MARK: - Initialization Engine
    override init() {
        super.init()
        manager.delegate = self
    }
    
    // MARK: - Permission Handlers
    func requestWhenInUse() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
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
