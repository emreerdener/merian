import CoreLocation
import Foundation

@MainActor
struct EnvironmentLocationHardware {
    let authorizationStatus: @MainActor () -> CLAuthorizationStatus
    let configure:
        @MainActor (_ delegate: any CLLocationManagerDelegate) -> Void
    let requestWhenInUseAuthorization: @MainActor () -> Void
    let requestLocation: @MainActor () -> Void
    let startUpdatingLocation: @MainActor () -> Void
    let stopUpdatingLocation: @MainActor () -> Void
    let applyProfile:
        @MainActor (
            _ desiredAccuracy: CLLocationAccuracy,
            _ distanceFilter: CLLocationDistance
        ) -> Void

    static var live: Self {
        let manager = CLLocationManager()
        return Self(
            authorizationStatus: { manager.authorizationStatus },
            configure: { delegate in
                manager.delegate = delegate
                manager.desiredAccuracy =
                    EnvironmentLocationPolicy.composingAccuracy
                manager.distanceFilter =
                    EnvironmentLocationPolicy.composingDistanceFilter
                manager.pausesLocationUpdatesAutomatically = true
            },
            requestWhenInUseAuthorization: {
                manager.requestWhenInUseAuthorization()
            },
            requestLocation: { manager.requestLocation() },
            startUpdatingLocation: { manager.startUpdatingLocation() },
            stopUpdatingLocation: { manager.stopUpdatingLocation() },
            applyProfile: { desiredAccuracy, distanceFilter in
                manager.desiredAccuracy = desiredAccuracy
                manager.distanceFilter = distanceFilter
            }
        )
    }
}

/// Owns Core Location delegate, authorization, one-shot request, and tracking
/// lifecycle. Every timeout carries an exact generation so a cancelled wait
/// that completes non-cooperatively cannot resolve a replacement request.
@MainActor
final class EnvironmentLocationController: NSObject,
    CLLocationManagerDelegate {
    struct Dependencies {
        let hardware: EnvironmentLocationHardware
        let waitForLocationTimeout: @MainActor () async -> Void

        @MainActor static var live: Self {
            Self(
                hardware: .live,
                waitForLocationTimeout: {
                    try? await Task.sleep(
                        nanoseconds:
                        EnvironmentLocationPolicy.locationTimeoutNanoseconds
                    )
                }
            )
        }
    }

    typealias SnapshotHandler = @MainActor (EnvironmentLocationSnapshot) -> Void

    private let dependencies: Dependencies
    private var authorizationStatus: CLAuthorizationStatus
    private var cachedLocation: CLLocation?
    private var fallbackInaccurateLocation: CLLocation?
    private var activeLocationContinuations:
        [UUID: CheckedContinuation<CLLocation?, Never>] = [:]
    private var activeAuthorizationContinuations:
        [UUID: CheckedContinuation<CLAuthorizationStatus, Never>] = [:]
    private var timeoutTask: Task<Void, Never>?
    private var timeoutGeneration: UUID?
    private var isLiveLocationTracking = false
    private var snapshotHandler: SnapshotHandler?

    override convenience init() {
        self.init(dependencies: .live)
    }

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        authorizationStatus = dependencies.hardware.authorizationStatus()
        super.init()
        dependencies.hardware.configure(self)
    }

    var snapshot: EnvironmentLocationSnapshot {
        EnvironmentLocationSnapshot(
            authorizationStatus: authorizationStatus,
            cachedLocation: cachedLocation,
            fallbackInaccurateLocation: fallbackInaccurateLocation
        )
    }

    func setSnapshotHandler(_ handler: @escaping SnapshotHandler) {
        snapshotHandler = handler
        handler(snapshot)
    }

    func validatePermissions(suppressesPrompt: Bool) {
        synchronizeAuthorizationStatus()
        guard EnvironmentLocationPolicy.shouldRequestAuthorization(
            for: authorizationStatus,
            suppressesPrompt: suppressesPrompt
        ) else { return }
        dependencies.hardware.requestWhenInUseAuthorization()
    }

    func requestAuthorizationIfNeeded(
        suppressesPrompt: Bool
    ) async -> CLAuthorizationStatus {
        synchronizeAuthorizationStatus()
        guard !Task.isCancelled else { return authorizationStatus }
        guard EnvironmentLocationPolicy.shouldRequestAuthorization(
            for: authorizationStatus,
            suppressesPrompt: suppressesPrompt
        ) else { return authorizationStatus }

        let requestID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                activeAuthorizationContinuations[requestID] = continuation
                if activeAuthorizationContinuations.count == 1 {
                    dependencies.hardware.requestWhenInUseAuthorization()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self,
                      let continuation = activeAuthorizationContinuations
                      .removeValue(forKey: requestID) else { return }
                continuation.resume(returning: authorizationStatus)
            }
        }
    }

    func requestCurrentLocation(
        suppressesPrompt: Bool
    ) async -> CLLocation? {
        let status = await requestAuthorizationIfNeeded(
            suppressesPrompt: suppressesPrompt
        )
        guard !Task.isCancelled,
              EnvironmentLocationPolicy.isAuthorized(status) else { return nil }

        let location = await requestSingleLocation()
        guard !Task.isCancelled,
              EnvironmentLocationPolicy.isAuthorized(authorizationStatus) else {
            return nil
        }
        return location ?? snapshot.lastKnownLocation
    }

    func currentAuthorizedLocation() async -> CLLocation? {
        synchronizeAuthorizationStatus()
        guard !Task.isCancelled,
              EnvironmentLocationPolicy.isAuthorized(authorizationStatus) else {
            return nil
        }
        if let lastKnownLocation = snapshot.lastKnownLocation {
            return lastKnownLocation
        }
        let location = await requestSingleLocation()
        guard !Task.isCancelled,
              EnvironmentLocationPolicy.isAuthorized(authorizationStatus) else {
            return nil
        }
        return location
    }

    func startLiveLocationTracking() {
        isLiveLocationTracking = true
        guard EnvironmentLocationPolicy.isAuthorized(authorizationStatus) else {
            return
        }
        startComposingLocationUpdates()
    }

    func stopLiveLocationTracking() {
        isLiveLocationTracking = false
        dependencies.hardware.stopUpdatingLocation()
        dependencies.hardware.applyProfile(
            EnvironmentLocationPolicy.composingAccuracy,
            EnvironmentLocationPolicy.composingDistanceFilter
        )
    }

    func requestSingleLocation() async -> CLLocation? {
        guard !Task.isCancelled else { return nil }
        let requestID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                activeLocationContinuations[requestID] = continuation
                dependencies.hardware.applyProfile(
                    EnvironmentLocationPolicy.shutterAccuracy,
                    EnvironmentLocationPolicy.shutterDistanceFilter
                )
                dependencies.hardware.requestLocation()
                startTimeoutIfNeeded()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let continuation = activeLocationContinuations
                    .removeValue(forKey: requestID) {
                    continuation.resume(returning: nil)
                }
                if activeLocationContinuations.isEmpty {
                    invalidateTimeout()
                    restoreComposingLocationProfileIfNeeded()
                }
            }
        }
    }

    func receiveAuthorizationStatus(_ status: CLAuthorizationStatus) {
        authorizationStatus = status
        publishSnapshot()

        if status != .notDetermined {
            resolveAuthorizationContinuations(with: status)
        }

        if EnvironmentLocationPolicy.isAuthorized(status),
           isLiveLocationTracking {
            startComposingLocationUpdates()
        } else if !EnvironmentLocationPolicy.isAuthorized(status) {
            dependencies.hardware.stopUpdatingLocation()
            if !activeLocationContinuations.isEmpty {
                resolveLocationContinuations(with: nil)
            }
        }
    }

    func receiveLocations(_ locations: [CLLocation]) {
        guard let location = locations.last else { return }
        guard EnvironmentLocationPolicy.isUsable(location) else { return }
        if EnvironmentLocationPolicy.isAccurate(location) {
            cachedLocation = location
            publishSnapshot()
            resolveLocationContinuations(with: location)
        } else {
            fallbackInaccurateLocation = location
            publishSnapshot()
        }
    }

    func receiveLocationFailure() {
        resolveLocationContinuations(with: nil)
    }

    nonisolated func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            self?.receiveAuthorizationStatus(status)
        }
    }

    nonisolated func locationManager(
        _: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in
            self?.receiveLocations([location])
        }
    }

    nonisolated func locationManager(
        _: CLLocationManager,
        didFailWithError _: Error
    ) {
        Task { @MainActor [weak self] in
            self?.receiveLocationFailure()
        }
    }

    private func synchronizeAuthorizationStatus() {
        let currentStatus = dependencies.hardware.authorizationStatus()
        guard currentStatus != authorizationStatus else { return }
        receiveAuthorizationStatus(currentStatus)
    }

    private func startTimeoutIfNeeded() {
        guard timeoutTask == nil else { return }
        let generation = UUID()
        let waitForLocationTimeout = dependencies.waitForLocationTimeout
        timeoutGeneration = generation
        timeoutTask = Task { @MainActor [weak self] in
            await waitForLocationTimeout()
            guard let self,
                  !Task.isCancelled,
                  timeoutGeneration == generation else { return }
            resolveLocationContinuations(
                with: snapshot.lastKnownLocation
            )
        }
    }

    private func resolveLocationContinuations(with location: CLLocation?) {
        invalidateTimeout()
        let pending = Array(activeLocationContinuations.values)
        activeLocationContinuations.removeAll()
        restoreComposingLocationProfileIfNeeded()
        for continuation in pending {
            continuation.resume(returning: location)
        }
    }

    private func invalidateTimeout() {
        timeoutGeneration = nil
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    private func restoreComposingLocationProfileIfNeeded() {
        guard activeLocationContinuations.isEmpty else { return }
        dependencies.hardware.applyProfile(
            EnvironmentLocationPolicy.composingAccuracy,
            EnvironmentLocationPolicy.composingDistanceFilter
        )
    }

    private func startComposingLocationUpdates() {
        dependencies.hardware.applyProfile(
            EnvironmentLocationPolicy.composingAccuracy,
            EnvironmentLocationPolicy.composingDistanceFilter
        )
        dependencies.hardware.startUpdatingLocation()
    }

    private func resolveAuthorizationContinuations(
        with status: CLAuthorizationStatus
    ) {
        let pending = Array(activeAuthorizationContinuations.values)
        activeAuthorizationContinuations.removeAll()
        for continuation in pending {
            continuation.resume(returning: status)
        }
    }

    private func publishSnapshot() {
        snapshotHandler?(snapshot)
    }
}
