import CoreLocation
import Testing

@testable import Merian

@Suite("Environment location controller")
@MainActor
struct EnvironmentLocationControllerTests {
    @Test("Authorization requests coalesce and resolve every waiter")
    func authorizationRequestsCoalesce() async throws {
        let probe = EnvironmentLocationHardwareProbe(
            authorizationStatus: .notDetermined
        )
        let controller = makeController(probe: probe)

        let first = Task {
            await controller.requestAuthorizationIfNeeded(
                suppressesPrompt: false
            )
        }
        try await waitForEnvironmentCondition {
            probe.authorizationRequestCount == 1
        }
        let second = Task {
            await controller.requestAuthorizationIfNeeded(
                suppressesPrompt: false
            )
        }
        await Task.yield()

        probe.authorizationStatus = .authorizedWhenInUse
        controller.receiveAuthorizationStatus(.authorizedWhenInUse)

        #expect(await first.value == .authorizedWhenInUse)
        #expect(await second.value == .authorizedWhenInUse)
        #expect(probe.authorizationRequestCount == 1)
        #expect(controller.snapshot.isAuthorized)
    }

    @Test("Suppressed permission requests return without touching hardware")
    func suppressedAuthorizationReturnsImmediately() async {
        let probe = EnvironmentLocationHardwareProbe(
            authorizationStatus: .notDetermined
        )
        let controller = makeController(probe: probe)

        controller.validatePermissions(suppressesPrompt: true)
        let status = await controller.requestAuthorizationIfNeeded(
            suppressesPrompt: true
        )

        #expect(status == .notDetermined)
        #expect(probe.authorizationRequestCount == 0)
    }

    @Test("Accurate updates resolve overlapping requests and restore tracking")
    func accurateLocationResolvesOverlappingRequests() async throws {
        let probe = EnvironmentLocationHardwareProbe(
            authorizationStatus: .authorizedWhenInUse
        )
        let timeoutGate = EnvironmentContextWaitGate()
        let controller = makeController(
            probe: probe,
            timeoutGate: timeoutGate
        )
        controller.startLiveLocationTracking()

        let first = Task { await controller.requestSingleLocation() }
        let second = Task { await controller.requestSingleLocation() }
        try await waitForEnvironmentCondition {
            let timeoutWaiterCount = await timeoutGate.waiterCount
            return probe.locationRequestCount == 2 && timeoutWaiterCount == 1
        }
        let location = syntheticEnvironmentLocation(horizontalAccuracy: 30)
        controller.receiveLocations([location])

        #expect(environmentLocationsMatch(await first.value, location))
        #expect(environmentLocationsMatch(await second.value, location))
        #expect(controller.snapshot.cachedLocation === location)
        #expect(probe.startUpdatingCount == 1)
        #expect(
            probe.profiles.last?.0 ==
                EnvironmentLocationPolicy.composingAccuracy
        )
        #expect(
            probe.profiles.last?.1 ==
                EnvironmentLocationPolicy.composingDistanceFilter
        )
        await timeoutGate.releaseAll()
    }

    @Test("Timeout returns coarse fallback without promoting it to accurate cache")
    func timeoutReturnsFallbackWithoutPromotingIt() async throws {
        let probe = EnvironmentLocationHardwareProbe(
            authorizationStatus: .authorizedAlways
        )
        let timeoutGate = EnvironmentContextWaitGate()
        let controller = makeController(
            probe: probe,
            timeoutGate: timeoutGate
        )
        let request = Task {
            await controller.requestCurrentLocation(suppressesPrompt: false)
        }
        try await waitForEnvironmentCondition {
            await timeoutGate.waiterCount == 1
        }
        let fallback = syntheticEnvironmentLocation(horizontalAccuracy: 80)
        controller.receiveLocations([fallback])
        await timeoutGate.releaseFirst()

        #expect(environmentLocationsMatch(await request.value, fallback))
        #expect(controller.snapshot.cachedLocation == nil)
        #expect(controller.snapshot.fallbackInaccurateLocation === fallback)
    }

    @Test("Invalid accuracy is never retained as a location fallback")
    func invalidAccuracyIsIgnored() async throws {
        let probe = EnvironmentLocationHardwareProbe(
            authorizationStatus: .authorizedAlways
        )
        let timeoutGate = EnvironmentContextWaitGate()
        let controller = makeController(
            probe: probe,
            timeoutGate: timeoutGate
        )
        let request = Task { await controller.requestSingleLocation() }
        try await waitForEnvironmentCondition {
            await timeoutGate.waiterCount == 1
        }

        controller.receiveLocations([
            syntheticEnvironmentLocation(horizontalAccuracy: -1)
        ])
        #expect(controller.snapshot.lastKnownLocation == nil)
        await timeoutGate.releaseFirst()

        #expect(await request.value == nil)
        #expect(controller.snapshot.fallbackInaccurateLocation == nil)
    }

    @Test("Authorization revocation retires an in-flight location request")
    func revocationRetiresLocationRequest() async throws {
        let probe = EnvironmentLocationHardwareProbe(
            authorizationStatus: .authorizedWhenInUse
        )
        let timeoutGate = EnvironmentContextWaitGate()
        let controller = makeController(
            probe: probe,
            timeoutGate: timeoutGate
        )
        let cachedLocation = syntheticEnvironmentLocation()
        controller.receiveLocations([cachedLocation])

        let request = Task {
            await controller.requestCurrentLocation(suppressesPrompt: false)
        }
        try await waitForEnvironmentCondition {
            let timeoutWaiterCount = await timeoutGate.waiterCount
            return probe.locationRequestCount == 1 && timeoutWaiterCount == 1
        }

        probe.authorizationStatus = .denied
        controller.receiveAuthorizationStatus(.denied)

        #expect(await request.value == nil)
        #expect(controller.snapshot.cachedLocation === cachedLocation)
        await timeoutGate.releaseAll()
    }

    @Test("Cancellation cannot escape through the cached-location fallback")
    func cancelledCurrentRequestReturnsNil() async throws {
        let probe = EnvironmentLocationHardwareProbe(
            authorizationStatus: .authorizedWhenInUse
        )
        let timeoutGate = EnvironmentContextWaitGate()
        let controller = makeController(
            probe: probe,
            timeoutGate: timeoutGate
        )
        controller.receiveLocations([syntheticEnvironmentLocation()])

        let request = Task {
            await controller.requestCurrentLocation(suppressesPrompt: false)
        }
        try await waitForEnvironmentCondition {
            let timeoutWaiterCount = await timeoutGate.waiterCount
            return probe.locationRequestCount == 1 && timeoutWaiterCount == 1
        }
        request.cancel()

        #expect(await request.value == nil)
        await timeoutGate.releaseAll()
    }

    @Test("Cancelling one request does not retire an overlapping request")
    func cancellationIsRequestScoped() async throws {
        let probe = EnvironmentLocationHardwareProbe(
            authorizationStatus: .authorizedWhenInUse
        )
        let timeoutGate = EnvironmentContextWaitGate()
        let controller = makeController(
            probe: probe,
            timeoutGate: timeoutGate
        )
        let cancelled = Task { await controller.requestSingleLocation() }
        let survivor = Task { await controller.requestSingleLocation() }
        try await waitForEnvironmentCondition {
            let timeoutWaiterCount = await timeoutGate.waiterCount
            return probe.locationRequestCount == 2 && timeoutWaiterCount == 1
        }

        cancelled.cancel()
        #expect(await cancelled.value == nil)
        #expect(
            probe.profiles.last?.0 ==
                EnvironmentLocationPolicy.shutterAccuracy
        )

        let location = syntheticEnvironmentLocation(
            latitude: 11,
            longitude: 21
        )
        controller.receiveLocations([location])
        #expect(environmentLocationsMatch(await survivor.value, location))
        await timeoutGate.releaseAll()
    }

    @Test("A cancelled timeout cannot resolve a replacement request")
    func staleTimeoutCannotResolveReplacement() async throws {
        let probe = EnvironmentLocationHardwareProbe(
            authorizationStatus: .authorizedWhenInUse
        )
        let timeoutGate = EnvironmentContextWaitGate()
        let controller = makeController(
            probe: probe,
            timeoutGate: timeoutGate
        )

        let firstRequest = Task { await controller.requestSingleLocation() }
        try await waitForEnvironmentCondition {
            await timeoutGate.waiterCount == 1
        }
        let firstLocation = syntheticEnvironmentLocation()
        controller.receiveLocations([firstLocation])
        #expect(
            environmentLocationsMatch(await firstRequest.value, firstLocation)
        )

        let secondRequest = Task { await controller.requestSingleLocation() }
        try await waitForEnvironmentCondition {
            await timeoutGate.waiterCount == 2
        }
        await timeoutGate.releaseFirst()
        for _ in 0..<10 { await Task.yield() }

        let secondLocation = syntheticEnvironmentLocation(
            latitude: 12,
            longitude: 22
        )
        controller.receiveLocations([secondLocation])
        #expect(
            environmentLocationsMatch(
                await secondRequest.value,
                secondLocation
            )
        )
        await timeoutGate.releaseAll()
    }

    @Test("Tracking begins after a pending authorization becomes allowed")
    func authorizationChangeStartsPendingTracking() {
        let probe = EnvironmentLocationHardwareProbe(
            authorizationStatus: .notDetermined
        )
        let controller = makeController(probe: probe)

        controller.startLiveLocationTracking()
        #expect(probe.startUpdatingCount == 0)

        probe.authorizationStatus = .authorizedWhenInUse
        controller.receiveAuthorizationStatus(.authorizedWhenInUse)
        #expect(probe.startUpdatingCount == 1)

        controller.stopLiveLocationTracking()
        #expect(probe.stopUpdatingCount == 1)
    }

    private func makeController(
        probe: EnvironmentLocationHardwareProbe,
        timeoutGate: EnvironmentContextWaitGate? = nil
    ) -> EnvironmentLocationController {
        EnvironmentLocationController(
            dependencies: .init(
                hardware: probe.hardware(),
                waitForLocationTimeout: {
                    if let timeoutGate {
                        await timeoutGate.wait()
                    } else {
                        try? await Task.sleep(for: .seconds(60))
                    }
                }
            )
        )
    }
}
