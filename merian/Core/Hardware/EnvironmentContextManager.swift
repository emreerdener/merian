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
    
    /// Executes a clean historical environment fetch for library imports explicitly pinned to the creation date.
    func fetchHistoricalContext(location: CLLocation, date: Date) async -> EnvironmentContext {
        do {
            // WeatherKit supports historical dates implicitly via standard queries by passing temporal ranges
            let weatherData = try await weatherService.weather(for: location, including: .hourly(startDate: date, endDate: date.addingTimeInterval(3600)))
            
            if let targetHour = weatherData.first {
                return EnvironmentContext(
                    location: location,
                    weatherCondition: targetHour.condition.description,
                    weatherTemperature: targetHour.temperature.converted(to: .fahrenheit).value
                )
            } else {
                return EnvironmentContext(location: location, weatherCondition: nil, weatherTemperature: nil)
            }
        } catch {
            print("WeatherKit historical context dropped: \(error.localizedDescription)")
            return EnvironmentContext(location: location, weatherCondition: nil, weatherTemperature: nil)
        }
    }
    
    private func requestSingleLocation() async -> CLLocation? {
        if let active = activeContinuationWrapper {
            activeContinuationWrapper = nil
            active.resume(returning: nil)
        }
        
        return await withCheckedContinuation { continuation in
            self.activeContinuationWrapper = continuation
            self.locationManager.requestLocation()
            
            // Anti-Deadlock timeout: Force-resume after 2.0s if hardware fails to lock satellites
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if let active = self.activeContinuationWrapper {
                    print("⚠️ GPS Hardware lock timed out. Proceeding dynamically with cached/nil context.")
                    self.activeContinuationWrapper = nil
                    active.resume(returning: self.cachedLocation)
                }
            }
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
                self.activeContinuationWrapper = nil
                continuation.resume(returning: location)
            } else {
                 self.cachedLocation = location
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            print("Deferred Context Fetch completely failed hardware lock: \(error.localizedDescription)")
            if let continuation = self.activeContinuationWrapper {
                self.activeContinuationWrapper = nil
                continuation.resume(returning: nil)
            }
        }
    }
}
