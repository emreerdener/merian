import XCTest

@testable import Merian

@MainActor
final class CaptureWorkspaceOperationStateTests: XCTestCase {
    func testTimeoutProtectionIsConsumedExactlyOnce() {
        let state = CaptureWorkspaceOperationState()
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        state.protectExternalRoute(
            fromTimeoutUntil: now.addingTimeInterval(5)
        )

        XCTAssertTrue(
            state.consumeExternalRouteTimeoutProtection(
                now: now.addingTimeInterval(4)
            )
        )
        XCTAssertFalse(
            state.consumeExternalRouteTimeoutProtection(
                now: now.addingTimeInterval(4)
            )
        )
    }

    func testExpiredTimeoutProtectionIsCleared() {
        let state = CaptureWorkspaceOperationState()
        let now = Date(timeIntervalSinceReferenceDate: 2_000)
        state.protectExternalRoute(
            fromTimeoutUntil: now.addingTimeInterval(-1)
        )

        XCTAssertFalse(
            state.consumeExternalRouteTimeoutProtection(now: now)
        )
        XCTAssertFalse(
            state.consumeExternalRouteTimeoutProtection(now: now)
        )
    }

    func testPendingRouteAndSheetAreTakeOnceValues() {
        let state = CaptureWorkspaceOperationState()
        let routeID = UUID()
        state.deferRoute(requestID: routeID)
        state.queueLocalSheet(.profile)
        state.queueLocalSheet(.scans)

        XCTAssertEqual(state.takeDeferredRouteRequestID(), routeID)
        XCTAssertNil(state.takeDeferredRouteRequestID())
        XCTAssertEqual(state.takePendingLocalSheet(), .scans)
        XCTAssertNil(state.takePendingLocalSheet())
    }

    func testRequiredGalleryCropStateIsEncapsulatedAndOrdered() {
        let state = CaptureWorkspaceOperationState()
        let first = UUID()
        let second = UUID()
        state.appendRequiredGalleryCrop(imageID: first)
        state.appendRequiredGalleryCrop(imageID: second)

        XCTAssertEqual(state.firstRequiredGalleryCropImageID(), first)
        XCTAssertTrue(state.containsRequiredGalleryCrop(imageID: second))

        state.removeRequiredGalleryCrop(imageID: first)
        XCTAssertEqual(state.firstRequiredGalleryCropImageID(), second)
        state.removeAllRequiredGalleryCrops()
        XCTAssertNil(state.firstRequiredGalleryCropImageID())
    }

    func testOverlappingExternalImportRequestsCoalesceIntoRetry() async {
        let state = CaptureWorkspaceOperationState()
        let firstIterationStarted = expectation(
            description: "first external-import iteration started"
        )
        let retryIterationStarted = expectation(
            description: "coalesced external-import retry started"
        )
        var firstIterationContinuation: CheckedContinuation<Void, Never>?
        var retryIterationContinuation: CheckedContinuation<Void, Never>?
        var iterationCount = 0

        XCTAssertTrue(
            state.beginExternalImageImport {
                iterationCount += 1
                if iterationCount == 1 {
                    await withCheckedContinuation { continuation in
                        firstIterationContinuation = continuation
                        firstIterationStarted.fulfill()
                    }
                } else if iterationCount == 2 {
                    await withCheckedContinuation { continuation in
                        retryIterationContinuation = continuation
                        retryIterationStarted.fulfill()
                    }
                }
            }
        )
        await fulfillment(of: [firstIterationStarted], timeout: 1)
        XCTAssertNotNil(firstIterationContinuation)
        XCTAssertFalse(
            state.beginExternalImageImport {}
        )

        firstIterationContinuation?.resume()
        await fulfillment(of: [retryIterationStarted], timeout: 1)

        XCTAssertEqual(iterationCount, 2)
        XCTAssertNotNil(retryIterationContinuation)
        retryIterationContinuation?.resume()
        await Task.yield()
    }

    func testExternalImportSheetResumeRequestIsTakeOnce() {
        let state = CaptureWorkspaceOperationState()
        state.deferExternalImageImportUntilSheetDismissal()

        XCTAssertFalse(state.beginExternalImageImport {})
        XCTAssertTrue(state.takeExternalImageImportResumeRequest())
        XCTAssertFalse(state.takeExternalImageImportResumeRequest())
    }

    func testSheetDismissalResumeBeforeTaskReleaseRunsQueuedIteration() async {
        let state = CaptureWorkspaceOperationState()
        let queuedIterationStarted = expectation(
            description: "sheet-dismissal retry iteration started"
        )
        var iterationCount = 0

        XCTAssertTrue(
            state.beginExternalImageImport {
                iterationCount += 1
                if iterationCount == 1 {
                    state.deferExternalImageImportUntilSheetDismissal()
                    XCTAssertTrue(
                        state.takeExternalImageImportResumeRequest()
                    )
                    XCTAssertFalse(state.beginExternalImageImport {})
                } else {
                    queuedIterationStarted.fulfill()
                }
            }
        )

        await fulfillment(of: [queuedIterationStarted], timeout: 1)
        XCTAssertEqual(iterationCount, 2)
    }

    func testExternalImportPresentationFeedbackIsIdempotentPerReceipt() {
        let state = CaptureWorkspaceOperationState()
        let importID = UUID()

        XCTAssertTrue(state.markExternalImportSlotBlockIfNeeded(for: importID))
        XCTAssertFalse(state.markExternalImportSlotBlockIfNeeded(for: importID))
        XCTAssertTrue(state.markExternalImportPaywallIfNeeded(for: importID))
        XCTAssertFalse(state.markExternalImportPaywallIfNeeded(for: importID))

        state.clearExternalImportPresentationHistory(for: importID)
        XCTAssertTrue(state.markExternalImportSlotBlockIfNeeded(for: importID))
        XCTAssertTrue(state.markExternalImportPaywallIfNeeded(for: importID))
    }
}
