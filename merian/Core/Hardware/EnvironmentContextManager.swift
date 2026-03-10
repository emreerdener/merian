import Foundation
import CoreLocation
import WeatherKit
import Combine

/// A data model representing the unified environmental payload extracted at the exact moment of a scan.
struct EnvironmentContext {
    let location: CLLocation?
    let weatherCondition: String?
    let weatherTemperature: Double?
}

/// A centralized singleton that lazily retrieves GPS locations and WeatherKit payloads only when explicitly triggered.
/// Adheres to the "Deferred Context Fetch" philosophy to prevent battery drain.
@MainActor
final class EnvironmentContextManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = EnvironmentContextManager()
    
    private let locationManager = CLLocationManager()
    private let weatherService = WeatherService.shared
    
    @Published var isAuthorized: Bool = false
    
    private var activeContinuationWrapper: CheckedContinuation<CLLocation?, Never>?
    private var cachedLocation: CLLocation?
    
    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        checkAuthorization()
    }
    
    private func checkAuthorization() {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            self.isAuthorized = true
        default:
            self.isAuthorized = false
        }
    }
    
    func validatePermissions() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }
    
    /// Executes the "Deferred Context Fetch", locking the location pinpoint to the exact time of the shutter press
    func fetchDeferredContext() async -> EnvironmentContext {
        // If not authorized, gracefully degrade and return empty context
        guard isAuthorized else {
            return EnvironmentContext(location: nil, weatherCondition: nil, weatherTemperature: nil)
        }
        
        let location = await requestSingleLocation()
        
        guard let validLocation = location else {
            return EnvironmentContext(location: cachedLocation, weatherCondition: nil, weatherTemperature: nil)
        }
        
        self.cachedLocation = validLocation
        
        // Attempt WeatherKit data if a location is returned
        do {
            let weather = try await weatherService.weather(for: validLocation)
            let condition = weather.currentWeather.condition.description
            let tempF = weather.currentWeather.temperature.converted(to: .fahrenheit).value
            
            return EnvironmentContext(
                location: validLocation,
                weatherCondition: condition,
                weatherTemperature: tempF
            )
        } catch {
            print("WeatherKit context dropped: \(error.localizedDescription)")
            return EnvironmentContext(location: validLocation, weatherCondition: nil, weatherTemperature: nil)
        }
    }
    
    private func requestSingleLocation() async -> CLLocation? {
        // If an explicit continuation is still running, clear it gracefully
        if let active = activeContinuationWrapper {
            active.resume(returning: nil)
            activeContinuationWrapper = nil
        }
        
        return await withCheckedContinuation { continuation in
            // Because Swift concurrency with delegate callbacks is tricky, we can use a temporary wrapper 
            // but for simplicity, we trigger the one-off request
            self.activeContinuationWrapper = continuation
            self.locationManager.requestLocation()
        }
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.checkAuthorization()
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            if let continuation = self.activeContinuationWrapper {
                continuation.resume(returning: location)
                self.activeContinuationWrapper = nil
            } else {
                 self.cachedLocation = location
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            print("Deferred Context Fetch completely failed hardware lock: \(error.localizedDescription)")
            if let continuation = self.activeContinuationWrapper {
                continuation.resume(returning: nil)
                self.activeContinuationWrapper = nil
            }
        }
    }
}
