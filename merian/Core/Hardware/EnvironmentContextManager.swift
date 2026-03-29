import CoreLocation
import Foundation
import MapKit
import Observation
import WeatherKit

// MARK: - Environment Context Manager

/// Lazily retrieves GPS and WeatherKit data only when triggered by a scan.
/// Follows a "deferred context fetch" model to minimize battery impact.
@MainActor
@Observable final class EnvironmentContextManager: NSObject, CLLocationManagerDelegate {
    // MARK: - Singleton Architecture
    static let shared = EnvironmentContextManager()

    // MARK: - Hardware
    private let locationManager = CLLocationManager()
    private let weatherService = WeatherService.shared

    // MARK: - State
    var isAuthorized: Bool = false

    var locationAuthorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }

    // MARK: - Cache
    private var activeContinuations: [UUID: CheckedContinuation<CLLocation?, Never>] = [:]
    private var timeoutTask: Task<Void, Never>?
    private(set) var cachedLocation: CLLocation?
    private var fallbackInaccurateLocation: CLLocation?

    private var geocodeCache: [String: String] = [:]
    private var geocodeKeys: [String] = []
    private let geocodeCacheLimit = 200
    private var activeGeocodeTasks: [String: Task<String?, Never>] = [:]

    // MARK: - Initialization
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
    }

    func stopLiveLocationTracking() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
    }

    // MARK: - Deferred Context Fetch

    /// Fetches environment context pinned to the moment of the shutter press.
    func fetchDeferredContext(preLockedLocation: CLLocation? = nil) async -> EnvironmentContext {
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

        // Run geocoding and weather fetch concurrently — they are independent I/O operations.
        async let locationName = reverseGeocode(location: validLocation)

        do {
            let weather = try await weatherService.weather(for: validLocation)
            let condition = weather.currentWeather.condition.description
            let tempF = weather.currentWeather.temperature.converted(to: .fahrenheit).value

            return EnvironmentContext(
                location: validLocation,
                locationName: await locationName,
                weatherCondition: condition,
                weatherTemperature: tempF
            )
        } catch {
            return EnvironmentContext(location: validLocation, locationName: await locationName)
        }
    }

    /// Fetches historical environment context for a gallery image, pinned to its creation date.
    func fetchHistoricalContext(location: CLLocation, date: Date) async -> EnvironmentContext {
        let locationName = await reverseGeocode(location: location)

        do {
            // WeatherKit supports historical queries via hourly time ranges.
            let weatherData = try await weatherService.weather(for: location, including: .hourly(startDate: date, endDate: date.addingTimeInterval(3600)))

            if let targetHour = weatherData.first {
                return EnvironmentContext(
                    location: location,
                    locationName: locationName,
                    weatherCondition: targetHour.condition.description,
                    weatherTemperature: targetHour.temperature.converted(to: .fahrenheit).value,
                    captureDate: date
                )
            } else {
                return EnvironmentContext(location: location, locationName: locationName, captureDate: date)
            }
        } catch {
            return EnvironmentContext(location: location, locationName: locationName, captureDate: date)
        }
    }

    // MARK: - Private Resolvers

    private func reverseGeocode(location: CLLocation) async -> String? {
        let key = String(format: "%.3f,%.3f", location.coordinate.latitude, location.coordinate.longitude)
        if let cached = geocodeCache[key] {
            return cached
        }

        // Coalesce concurrent geocode requests for the same coordinate to avoid API flooding.
        if let existingTask = activeGeocodeTasks[key] {
            return await existingTask.value
        }

        let task = Task { @MainActor [weak self] () -> String? in
            guard let self = self else { return nil }
            let geocoder = CLGeocoder()
            // withTaskCancellationHandler ensures that if the parent task is cancelled,
            // cancelGeocode() resumes the continuation immediately via CLError.geocodeCanceled.
            let generatedString: String? = await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
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
            } onCancel: {
                geocoder.cancelGeocode()
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
        let taskID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.activeContinuations[taskID] = continuation
                self.locationManager.requestLocation()

                // Timeout: force-resume after 2 seconds if the hardware fails to lock satellites.
                // Degrades to the best available loose lock (e.g., cellular-range accuracy)
                // so the scan still receives some macro-region context.
                if self.timeoutTask == nil {
                    self.timeoutTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 2_000_000_000)

                        guard !Task.isCancelled, let self = self else { return }

                        let bestAvailableFallback = self.cachedLocation ?? self.fallbackInaccurateLocation
                        _ = self.resolvePendingContinuations(with: bestAvailableFallback)
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in
                if let continuation = self.activeContinuations.removeValue(forKey: taskID) {
                    continuation.resume(returning: nil)
                }
                if self.activeContinuations.isEmpty {
                    self.timeoutTask?.cancel()
                    self.timeoutTask = nil
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

            // Prioritize high-accuracy outdoor locks (≤ 30m horizontal accuracy).
            let isAccurate = location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 30

            if isAccurate {
                self.cachedLocation = location
                _ = self.resolvePendingContinuations(with: location)
            } else {
                // Store as a safety net in case the 2-second timeout fires before a strong lock.
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

        let pending = Array(self.activeContinuations.values)
        self.activeContinuations.removeAll()

        for continuation in pending {
            continuation.resume(returning: location)
        }

        return pending.isEmpty
    }
}
