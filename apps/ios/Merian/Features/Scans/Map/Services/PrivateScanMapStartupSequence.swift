import CoreLocation
import Foundation

enum PrivateScanMapStartupSequence {
    @MainActor
    static func run(
        refresh: @MainActor () async -> Void,
        updateSnapshot: @MainActor () -> Void,
        needsInitialCamera: @MainActor () -> Bool,
        isCurrent: @MainActor () -> Bool,
        requestCurrentLocation: @MainActor () async -> CLLocation?,
        setInitialCamera: @MainActor (CLLocation?) -> Void
    ) async {
        await refresh()
        guard !Task.isCancelled, isCurrent() else { return }

        updateSnapshot()
        guard !Task.isCancelled,
              isCurrent(),
              needsInitialCamera() else {
            return
        }

        let currentLocation = await requestCurrentLocation()
        guard !Task.isCancelled, isCurrent() else { return }
        setInitialCamera(currentLocation)
    }
}

enum PrivateScanMapLocationRequestResult {
    case location(CLLocation)
    case unavailable
    case invalidated
}

enum PrivateScanMapLocationRequestSequence {
    @MainActor
    static func run(
        isCurrent: @MainActor () -> Bool,
        requestCurrentLocation: @MainActor () async -> CLLocation?
    ) async -> PrivateScanMapLocationRequestResult {
        let location = await requestCurrentLocation()
        guard !Task.isCancelled, isCurrent() else { return .invalidated }
        guard let location else { return .unavailable }
        return .location(location)
    }
}
