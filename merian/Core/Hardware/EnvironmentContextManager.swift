import Foundation
import CoreLocation
import WeatherKit
import Combine
import CoreMotion
import MapKit
import Observation

// MARK: - Environmental Telemetry Payload
/// A data model representing the unified environmental payload extracted at the exact moment of a scan.
struct EnvironmentContext {
    let location: CLLocation?
    var locationName: String? = nil
    var weatherCondition: String? = nil
    var weatherTemperature: Double? = nil
}

// MARK: - Core Contextual Hardware Engine
/// A centralized singleton that lazily retrieves GPS locations and WeatherKit payloads only when explicitly triggered.
/// Adheres to the "Deferred Context Fetch" philosophy to prevent battery drain.
@MainActor
@Observable final class EnvironmentContextManager: NSObject, CLLocationManagerDelegate {
    // MARK: - Singleton Architecture
    static let shared = EnvironmentContextManager()
    
    // MARK: - Hardware Controllers
    private let locationManager = CLLocationManager()
    private let weatherService = WeatherService.shared
    private let motionManager = CMMotionManager()
    
    // MARK: - State Management
    var isAuthorized: Bool = false
    
    // MARK: - Cache Maps
    
    private var activeContinuations: [CheckedContinuation<CLLocation?, Never>] = []
    private var timeoutTask: Task<Void, Never>?
    private(set) var cachedLocation: CLLocation?
    private var fallbackInaccurateLocation: CLLocation?
    
    private var geocodeCache: [String: String] = [:]
    private var geocodeKeys: [String] = []
    private let geocodeCacheLimit = 200
    private var activeGeocodeTasks: [String: Task<String?, Never>] = [:]
    
    // MARK: - Hardware Initialization
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
    
    // MARK: - Live Location Tracking
    func startLiveLocationTracking() {
        guard isAuthorized else { return }
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        
        if motionManager.isDeviceMotionAvailable {
            motionManager.startDeviceMotionUpdates()
        }
    }
    
    func stopLiveLocationTracking() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        
        if motionManager.isDeviceMotionAvailable {
            motionManager.stopDeviceMotionUpdates()
        }
    }
    
    // MARK: - Deferred Inference Triggers
    /// Executes the "Deferred Context Fetch", locking the location pinpoint to the exact time of the shutter press
    func fetchDeferredContext(preLockedLocation: CLLocation? = nil) async -> EnvironmentContext {
        // If not authorized, gracefully degrade and return empty context
        guard isAuthorized else {
            return EnvironmentContext(location: preLockedLocation)
        }
        
        let validLocation: CLLocation
        if let pre = preLockedLocation {
            validLocation = pre
        } else if let dynamicLocation = await requestSingleLocation() {
            validLocation = dynamicLocation
            self.cachedLocation = validLocation
        } else if let cached = self.cachedLocation {
            validLocation = cached
        } else {
            return EnvironmentContext(location: nil)
        }
        
        let locationName = await reverseGeocode(location: validLocation)
        
        // Attempt WeatherKit data if a location is returned
        do {
            let weather = try await weatherService.weather(for: validLocation)
            let condition = weather.currentWeather.condition.description
            let tempF = weather.currentWeather.temperature.converted(to: .fahrenheit).value
            
            return EnvironmentContext(
                location: validLocation,
                locationName: locationName,
                weatherCondition: condition,
                weatherTemperature: tempF
            )
        } catch {
            return EnvironmentContext(location: validLocation, locationName: locationName)
        }
    }
    
    /// Executes a clean historical environment fetch for library imports explicitly pinned to the creation date.
    func fetchHistoricalContext(location: CLLocation, date: Date) async -> EnvironmentContext {
        let locationName = await reverseGeocode(location: location)
        
        do {
            // WeatherKit supports historical dates implicitly via standard queries by passing temporal ranges
            let weatherData = try await weatherService.weather(for: location, including: .hourly(startDate: date, endDate: date.addingTimeInterval(3600)))
            
            if let targetHour = weatherData.first {
                return EnvironmentContext(
                    location: location,
                    locationName: locationName,
                    weatherCondition: targetHour.condition.description,
                    weatherTemperature: targetHour.temperature.converted(to: .fahrenheit).value
                )
            } else {
                return EnvironmentContext(location: location, locationName: locationName)
            }
        } catch {
            return EnvironmentContext(location: location, locationName: locationName)
        }
    }
    
    // MARK: - Context Resolvers
    private func reverseGeocode(location: CLLocation) async -> String? {
        let key = String(format: "%.3f,%.3f", location.coordinate.latitude, location.coordinate.longitude)
        if let cached = geocodeCache[key] {
            return cached
        }
        
        // CRITICAL SEC FIX: Prevent the "Thundering Herd" API crash by explicitly coalescing concurrent fetches natively
        if let existingTask = activeGeocodeTasks[key] {
            return await existingTask.value
        }
        
        let task = Task { @MainActor [weak self] () -> String? in
            guard let self = self else { return nil }
            let geocoder = CLGeocoder()
            let generatedString: String? = await withCheckedContinuation { continuation in
                geocoder.reverseGeocodeLocation(location) { placemarks, error in
                    if error != nil {
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    if let placemark = placemarks?.first {
                        if let city = placemark.locality, let adminArea = placemark.administrativeArea {
                            continuation.resume(returning: "\(city), \(adminArea)")
                        } else if let city = placemark.locality {
                            continuation.resume(returning: city)
                        } else if let name = placemark.name {
                            continuation.resume(returning: name)
                        } else {
                            continuation.resume(returning: nil)
                        }
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
            
            if let validString = generatedString {
                if self.geocodeKeys.count >= self.geocodeCacheLimit {
                    let oldest = self.geocodeKeys.removeFirst()
                    self.geocodeCache.removeValue(forKey: oldest)
                }
                self.geocodeKeys.append(key)
                self.geocodeCache[key] = validString
            }
            
            self.activeGeocodeTasks.removeValue(forKey: key)
            return generatedString
        }
        
        activeGeocodeTasks[key] = task
        return await task.value
    }
    
    private func requestSingleLocation() async -> CLLocation? {
        // Only set timeoutTask if it's currently nil
        
        return await withCheckedContinuation { continuation in
            self.activeContinuations.append(continuation)
            self.locationManager.requestLocation()
            
            // Anti-Deadlock timeout: Force-resume after 2.0s if hardware fails to lock satellites
            if self.timeoutTask == nil {
                self.timeoutTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    
                    guard !Task.isCancelled, let self = self else { return }
                    
                    // Fallback Resolution:
                    // If we never got a highly accurate <30m location in those 2 seconds, 
                    // gracefully degrade to whatever loose lock the antenna managed to find (e.g., 500m cellular bounds),
                    // to ensure they have at least *some* macro-region environment data.
                    let bestAvailableFallback = self.cachedLocation ?? self.fallbackInaccurateLocation
                    _ = self.resolvePendingContinuations(with: bestAvailableFallback)
                }
            }
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.checkAuthorization()
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            // Prioritize reliable outdoor coordinate locks (< 30m accuracy)
            let isAccurate = location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 30
            
            if isAccurate {
                self.cachedLocation = location
                // End the search early because we hit our gold standard accuracy!
                _ = self.resolvePendingContinuations(with: location)
            } else {
                // Not accurate enough. Store it as a safety net in case we hit the 2.0s timeout limit 
                // and never find a strong precision lock.
                self.fallbackInaccurateLocation = location
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            _ = self.resolvePendingContinuations(with: nil)
        }
    }
    
    private func resolvePendingContinuations(with location: CLLocation?) -> Bool {
        self.timeoutTask?.cancel()
        self.timeoutTask = nil
        
        let pending = self.activeContinuations
        self.activeContinuations.removeAll()
        
        for continuation in pending {
            continuation.resume(returning: location)
        }
        
        return pending.isEmpty
    }
}
