import Foundation
import CoreLocation
import WeatherKit
import Combine
import CoreMotion
import MapKit

/// A data model representing the unified environmental payload extracted at the exact moment of a scan.
struct EnvironmentContext {
    let location: CLLocation?
    var locationName: String? = nil
    var weatherCondition: String? = nil
    var weatherTemperature: Double? = nil
    var cameraPitchDegrees: Double? = nil
    var compassHeading: Double? = nil
    var relativeHumidity: Double? = nil
    var uvIndex: Int? = nil
}

/// A centralized singleton that lazily retrieves GPS locations and WeatherKit payloads only when explicitly triggered.
/// Adheres to the "Deferred Context Fetch" philosophy to prevent battery drain.
@MainActor
final class EnvironmentContextManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = EnvironmentContextManager()
    
    private let locationManager = CLLocationManager()
    private let weatherService = WeatherService.shared
    private let motionManager = CMMotionManager()
    
    @Published var isAuthorized: Bool = false
    
    private var activeContinuations: [CheckedContinuation<CLLocation?, Never>] = []
    private var timeoutTask: Task<Void, Never>?
    private(set) var cachedLocation: CLLocation?
    
    private var geocodeCache: [String: String] = [:]
    private var geocodeKeys: [String] = []
    private let geocodeCacheLimit = 200
    private var activeGeocodeTasks: [String: Task<String?, Never>] = [:]
    
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
        
        var capturedPitch: Double? = nil
        if motionManager.isDeviceMotionAvailable, let pitch = motionManager.deviceMotion?.attitude.pitch {
            capturedPitch = pitch * 180 / .pi
        }
        
        var capturedHeading: Double? = nil
        if let trueHeading = locationManager.heading?.trueHeading, trueHeading >= 0 {
            capturedHeading = trueHeading
        }
        
        // Attempt WeatherKit data if a location is returned
        do {
            let weather = try await weatherService.weather(for: validLocation)
            let condition = weather.currentWeather.condition.description
            let tempF = weather.currentWeather.temperature.converted(to: .fahrenheit).value
            let humidity = weather.currentWeather.humidity
            let uvIndex = weather.currentWeather.uvIndex.value
            
            return EnvironmentContext(
                location: validLocation,
                locationName: locationName,
                weatherCondition: condition,
                weatherTemperature: tempF,
                cameraPitchDegrees: capturedPitch,
                compassHeading: capturedHeading,
                relativeHumidity: humidity,
                uvIndex: uvIndex
            )
        } catch {
            return EnvironmentContext(location: validLocation, locationName: locationName, cameraPitchDegrees: capturedPitch, compassHeading: capturedHeading)
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
                    weatherTemperature: targetHour.temperature.converted(to: .fahrenheit).value,
                    relativeHumidity: targetHour.humidity,
                    uvIndex: targetHour.uvIndex.value
                )
            } else {
                return EnvironmentContext(location: location, locationName: locationName)
            }
        } catch {
            return EnvironmentContext(location: location, locationName: locationName)
        }
    }
    
    private func reverseGeocode(location: CLLocation) async -> String? {
        let key = String(format: "%.3f,%.3f", location.coordinate.latitude, location.coordinate.longitude)
        if let cached = geocodeCache[key] {
            return cached
        }
        
        // CRITICAL SEC FIX: Prevent the "Thundering Herd" API crash by explicitly coalescing concurrent fetches natively
        if let existingTask = activeGeocodeTasks[key] {
            return await existingTask.value
        }
        
        let task = Task { @MainActor () -> String? in
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
        timeoutTask?.cancel()
        
        return await withCheckedContinuation { continuation in
            self.activeContinuations.append(continuation)
            self.locationManager.requestLocation()
            
            // Anti-Deadlock timeout: Force-resume after 2.0s if hardware fails to lock satellites
            self.timeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                
                guard !Task.isCancelled else { return }
                
                let pending = self.activeContinuations
                self.activeContinuations.removeAll()
                for active in pending {
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
            self.timeoutTask?.cancel()
            
            let pending = self.activeContinuations
            self.activeContinuations.removeAll()
            
            for continuation in pending {
                continuation.resume(returning: location)
            }
            
            if pending.isEmpty {
                 self.cachedLocation = location
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.timeoutTask?.cancel()
            
            let pending = self.activeContinuations
            self.activeContinuations.removeAll()
            
            for continuation in pending {
                continuation.resume(returning: nil)
            }
        }
    }
}
