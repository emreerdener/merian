import Foundation
import Testing

@testable import Merian

@MainActor
struct QueuedContentViewModelTests {
    @Test func successfulRetryIsSingleFlightUntilItsRefreshCompletes() throws {
        var retriedScanIDs: [String] = []
        var selectionFeedbackCount = 0
        var errorFeedbackCount = 0
        let viewModel = QueuedContentViewModel(
            dependencies: QueuedContentDependencies(
                retryQueuedScanNow: { _, scanID in
                    retriedScanIDs.append(scanID)
                    return true
                },
                selectionFeedback: { selectionFeedbackCount += 1 },
                errorFeedback: { errorFeedbackCount += 1 }
            )
        )

        let result = viewModel.startRetry(
            scanID: "queued-retry",
            generation: 7,
            queueManager: .shared
        )
        guard case .started(let request) = result else {
            Issue.record("Expected retry to start")
            return
        }

        #expect(request.scanID == "queued-retry")
        #expect(request.generation == 7)
        #expect(viewModel.retryRefreshRequest == request)
        #expect(viewModel.isRetrying(scanID: "QUEUED-RETRY"))
        #expect(retriedScanIDs == ["queued-retry"])
        #expect(selectionFeedbackCount == 1)
        #expect(errorFeedbackCount == 0)

        #expect(viewModel.startRetry(
            scanID: "queued-retry",
            generation: 7,
            queueManager: .shared
        ) == .ignored)
        #expect(retriedScanIDs == ["queued-retry"])

        viewModel.completeRefresh(request)

        #expect(viewModel.retryRefreshRequest == nil)
        #expect(!viewModel.isRetrying(scanID: "queued-retry"))
    }

    @Test func failedRetryClearsSingleFlightAndReportsOnlyErrorFeedback() {
        var selectionFeedbackCount = 0
        var errorFeedbackCount = 0
        let viewModel = QueuedContentViewModel(
            dependencies: QueuedContentDependencies(
                retryQueuedScanNow: { _, _ in false },
                selectionFeedback: { selectionFeedbackCount += 1 },
                errorFeedback: { errorFeedbackCount += 1 }
            )
        )

        #expect(viewModel.startRetry(
            scanID: "failed-retry",
            generation: 2,
            queueManager: .shared
        ) == .failed)
        #expect(!viewModel.isRetrying(scanID: "failed-retry"))
        #expect(viewModel.retryRefreshRequest == nil)
        #expect(selectionFeedbackCount == 0)
        #expect(errorFeedbackCount == 1)
    }

    @Test func staleRefreshCompletionCannotClearNewerRetry() throws {
        let viewModel = QueuedContentViewModel(
            dependencies: QueuedContentDependencies(
                retryQueuedScanNow: { _, _ in true }
            )
        )
        let firstResult = viewModel.startRetry(
            scanID: "first-scan",
            generation: 1,
            queueManager: .shared
        )
        guard case .started(let firstRequest) = firstResult else {
            Issue.record("Expected first retry to start")
            return
        }
        viewModel.completeRefresh(firstRequest)

        let secondResult = viewModel.startRetry(
            scanID: "second-scan",
            generation: 2,
            queueManager: .shared
        )
        guard case .started(let secondRequest) = secondResult else {
            Issue.record("Expected second retry to start")
            return
        }

        viewModel.completeRefresh(firstRequest)

        #expect(viewModel.retryRefreshRequest == secondRequest)
        #expect(viewModel.isRetrying(scanID: "second-scan"))
    }

    @Test func schedulerAndCompletionEventsUseInjectedBoundaries() {
        var scheduled = false
        var published = false
        let viewModel = QueuedContentViewModel(
            dependencies: QueuedContentDependencies(
                scheduleNextPersistedWake: { _ in scheduled = true },
                publishScanLibraryChanged: { published = true }
            )
        )

        viewModel.scheduleNextPersistedWake(using: .shared)
        viewModel.publishSeededHandoffCompletion()

        #expect(scheduled)
        #expect(published)
    }
}
