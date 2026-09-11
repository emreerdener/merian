import CoreLocation
import Foundation

/// Owns Apple reverse-geocoding requests, bounded coordinate caching, and
/// same-coordinate request coalescing for every environment-context consumer.
@MainActor
final class EnvironmentGeocodingService {
    struct Dependencies {
        let resolvePlacemark:
            @MainActor (_ location: CLLocation) async -> EnvironmentPlacemark?

        static var live: Self {
            Self(
                resolvePlacemark: { location in
                    let geocoder = CLGeocoder()
                    return await withTaskCancellationHandler {
                        await withCheckedContinuation { continuation in
                            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                                guard error == nil,
                                      let placemark = placemarks?.first else {
                                    continuation.resume(returning: nil)
                                    return
                                }
                                continuation.resume(
                                    returning: EnvironmentPlacemark(
                                        locality: placemark.locality,
                                        administrativeArea:
                                            placemark.administrativeArea,
                                        regionIdentifier:
                                            placemark.isoCountryCode
                                    )
                                )
                            }
                        }
                    } onCancel: {
                        geocoder.cancelGeocode()
                    }
                }
            )
        }
    }

    private struct ActiveRequest {
        let id: UUID
        let task: Task<EnvironmentPlacemark?, Never>
    }

    private let dependencies: Dependencies
    private let cacheLimit: Int
    private var cache: [String: EnvironmentPlacemark] = [:]
    private var cacheKeys: [String] = []
    private var activeRequests: [String: ActiveRequest] = [:]

    convenience init() {
        self.init(
            dependencies: .live,
            cacheLimit: EnvironmentLocationPolicy.geocodeCacheLimit
        )
    }

    init(dependencies: Dependencies, cacheLimit: Int) {
        self.dependencies = dependencies
        self.cacheLimit = max(1, cacheLimit)
    }

    func locationName(for location: CLLocation) async -> String? {
        EnvironmentLocationPolicy.locationName(
            from: await placemark(for: location)
        )
    }

    func regionIdentifier(for location: CLLocation) async -> String? {
        EnvironmentLocationPolicy.normalizedRegionIdentifier(
            await placemark(for: location)?.regionIdentifier
        )
    }

    private func placemark(
        for location: CLLocation
    ) async -> EnvironmentPlacemark? {
        let key = EnvironmentLocationPolicy.geocodeCacheKey(for: location)
        if let cached = cache[key] {
            return cached
        }
        if let activeRequest = activeRequests[key] {
            return await activeRequest.task.value
        }

        let requestID = UUID()
        let resolvePlacemark = dependencies.resolvePlacemark
        let task = Task { @MainActor in
            await resolvePlacemark(location)
        }
        activeRequests[key] = ActiveRequest(id: requestID, task: task)
        let result = await task.value

        guard activeRequests[key]?.id == requestID else { return result }
        activeRequests.removeValue(forKey: key)
        if let result,
           EnvironmentLocationPolicy.hasUsableProjection(result) {
            insert(result, forKey: key)
        }
        return result
    }

    private func insert(_ placemark: EnvironmentPlacemark, forKey key: String) {
        if cache.count >= cacheLimit,
           let oldestKey = cacheKeys.first {
            cacheKeys.removeFirst()
            cache.removeValue(forKey: oldestKey)
        }
        cacheKeys.append(key)
        cache[key] = placemark
    }
}
