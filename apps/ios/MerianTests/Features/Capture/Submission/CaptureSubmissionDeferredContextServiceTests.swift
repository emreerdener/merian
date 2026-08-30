import Foundation
import XCTest

@testable import Merian

@MainActor
final class CaptureSubmissionDeferredContextServiceTests: XCTestCase {
    func testSuccessfulUpdateDoesNotWaitOrRetry() async {
        let probe = DeferredContextProbe(outcomes: [.success(())])
        let service = makeService(probe: probe)

        await service.apply(
            scanId: "scan-success",
            telemetry: makeTelemetry()
        )

        XCTAssertEqual(probe.scanIDs, ["scan-success"])
        XCTAssertEqual(probe.waitCount, 0)
        XCTAssertEqual(probe.events, [
            "local:scan-success",
            "remote:scan-success"
        ])
    }

    func testFirstFailureWaitsAndRetriesExactlyOnce() async {
        let probe = DeferredContextProbe(outcomes: [
            .failure(DeferredContextTestError.rejected),
            .success(())
        ])
        let service = makeService(probe: probe)

        await service.apply(
            scanId: "scan-retry",
            telemetry: makeTelemetry()
        )

        XCTAssertEqual(probe.scanIDs, ["scan-retry", "scan-retry"])
        XCTAssertEqual(probe.waitCount, 1)
        XCTAssertEqual(probe.events, [
            "local:scan-retry",
            "remote:scan-retry",
            "wait",
            "remote:scan-retry"
        ])
    }

    func testSecondFailureStopsAfterSingleRetry() async {
        let probe = DeferredContextProbe(outcomes: [
            .failure(DeferredContextTestError.rejected),
            .failure(DeferredContextTestError.rejected)
        ])
        let service = makeService(probe: probe)

        await service.apply(
            scanId: "scan-fails",
            telemetry: makeTelemetry()
        )

        XCTAssertEqual(probe.scanIDs, ["scan-fails", "scan-fails"])
        XCTAssertEqual(probe.waitCount, 1)
    }

    func testCancellationErrorFromFirstEndpointDoesNotWaitOrRetry() async {
        let probe = DeferredContextProbe(outcomes: [
            .failure(CancellationError())
        ])
        let service = makeService(probe: probe)

        await service.apply(
            scanId: "scan-endpoint-cancelled",
            telemetry: makeTelemetry()
        )

        XCTAssertEqual(probe.scanIDs, ["scan-endpoint-cancelled"])
        XCTAssertEqual(probe.waitCount, 0)
        XCTAssertEqual(probe.events, [
            "local:scan-endpoint-cancelled",
            "remote:scan-endpoint-cancelled"
        ])
    }

    func testCancelledTransportFromFirstEndpointDoesNotWaitOrRetry() async {
        let probe = DeferredContextProbe(outcomes: [
            .failure(URLError(.cancelled))
        ])
        let service = makeService(probe: probe)

        await service.apply(
            scanId: "scan-transport-cancelled",
            telemetry: makeTelemetry()
        )

        XCTAssertEqual(probe.scanIDs, ["scan-transport-cancelled"])
        XCTAssertEqual(probe.waitCount, 0)
    }

    func testCancelledRetryDelayDoesNotInvokeEndpointAgain() async {
        let probe = DeferredContextProbe(
            outcomes: [.failure(DeferredContextTestError.rejected)],
            waitError: CancellationError()
        )
        let service = makeService(probe: probe)

        await service.apply(
            scanId: "scan-cancelled",
            telemetry: makeTelemetry()
        )

        XCTAssertEqual(probe.scanIDs, ["scan-cancelled"])
        XCTAssertEqual(probe.waitCount, 1)
    }

    func testCancellationAfterRetryDelayDoesNotInvokeEndpointAgain() async {
        let probe = DeferredContextProbe(
            outcomes: [.failure(DeferredContextTestError.rejected)],
            cancelAfterWait: true
        )
        let service = makeService(probe: probe)

        let operation = Task { @MainActor in
            await service.apply(
                scanId: "scan-cancelled-after-wait",
                telemetry: makeTelemetry()
            )
        }
        await operation.value

        XCTAssertEqual(probe.scanIDs, ["scan-cancelled-after-wait"])
        XCTAssertEqual(probe.waitCount, 1)
    }

    private func makeService(
        probe: DeferredContextProbe
    ) -> CaptureSubmissionDeferredContextService {
        CaptureSubmissionDeferredContextService(
            persistLocally: { scanId, _ in
                probe.persistLocally(scanId: scanId)
            },
            endpoint: CaptureSubmissionDeferredContextEndpoint(
                update: { scanId, _ in
                    try probe.update(scanId: scanId)
                }
            ),
            waitBeforeRetry: {
                try probe.waitBeforeRetry()
            }
        )
    }

    private func makeTelemetry() -> CaptureTelemetry {
        CaptureTelemetry(
            subjectDistanceInMeters: nil,
            gpsLatitude: nil,
            gpsLongitude: nil,
            gpsElevation: 42,
            locationName: "Park",
            weatherCondition: "Clear",
            weatherTemperatureF: 72,
            timeOfDay: nil,
            timestamp: nil,
            zoomFactor: nil,
            estimatedSizeCm: nil
        )
    }
}

@MainActor
private final class DeferredContextProbe {
    private var outcomes: [Result<Void, Error>]
    private let waitError: Error?
    private let cancelAfterWait: Bool
    private(set) var scanIDs: [String] = []
    private(set) var waitCount = 0
    private(set) var events: [String] = []

    init(
        outcomes: [Result<Void, Error>],
        waitError: Error? = nil,
        cancelAfterWait: Bool = false
    ) {
        self.outcomes = outcomes
        self.waitError = waitError
        self.cancelAfterWait = cancelAfterWait
    }

    func persistLocally(scanId: String) {
        events.append("local:\(scanId)")
    }

    func update(scanId: String) throws {
        scanIDs.append(scanId)
        events.append("remote:\(scanId)")
        guard !outcomes.isEmpty else {
            XCTFail("Deferred-context endpoint called more than expected")
            return
        }
        try outcomes.removeFirst().get()
    }

    func waitBeforeRetry() throws {
        waitCount += 1
        events.append("wait")
        if cancelAfterWait {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
        }
        if let waitError {
            throw waitError
        }
    }
}

private enum DeferredContextTestError: Error {
    case rejected
}
