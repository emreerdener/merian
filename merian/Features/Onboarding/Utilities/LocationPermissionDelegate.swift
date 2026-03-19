import Foundation
import CoreLocation

class LocationPermissionDelegate: NSObject, ObservableObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    var onAuthorizationDetermined: (() -> Void)?
    
    override init() {
        super.init()
        manager.delegate = self
    }
    
    func requestWhenInUse() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            DispatchQueue.main.async {
                self.onAuthorizationDetermined?()
            }
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus != .notDetermined {
            DispatchQueue.main.async {
                self.onAuthorizationDetermined?()
            }
        }
    }
}
