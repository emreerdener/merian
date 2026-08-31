import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class QueuedContentViewModel {
    struct RetryRefreshRequest: Equatable {
        let id = UUID()
        let scanID: String
        let generation: UInt64
    }

    enum RetryStartResult: Equatable {
        case ignored
        case failed
        case started(RetryRefreshRequest)
    }

    private(set) var retryingScanID: String?
    private(set) var retryRefreshRequest: RetryRefreshRequest?

    @ObservationIgnored private let dependencies: QueuedContentDependencies

    init(dependencies: QueuedContentDependencies? = nil) {
        self.dependencies = dependencies ?? .live
    }

    func isRetrying(scanID: String) -> Bool {
        retryingScanID?.caseInsensitiveCompare(scanID) == .orderedSame
    }

    func scheduleNextPersistedWake(using queueManager: OfflineQueueManager) {
        dependencies.scheduleNextPersistedWake(queueManager)
    }

    func startRetry(
        scanID: String,
        generation: UInt64,
        queueManager: OfflineQueueManager
    ) -> RetryStartResult {
        guard !isRetrying(scanID: scanID) else { return .ignored }
        retryingScanID = scanID

        guard dependencies.retryQueuedScanNow(queueManager, scanID) else {
            dependencies.errorFeedback()
            retryingScanID = nil
            return .failed
        }

        dependencies.selectionFeedback()
        let request = RetryRefreshRequest(
            scanID: scanID,
            generation: generation
        )
        retryRefreshRequest = request
        return .started(request)
    }

    func refreshedContext(
        scanID: String,
        modelContainer: ModelContainer
    ) -> QueuedScanContext? {
        dependencies.loadQueuedContext(modelContainer, scanID)
    }

    func completeRefresh(_ request: RetryRefreshRequest) {
        guard retryRefreshRequest?.id == request.id else { return }
        if isRetrying(scanID: request.scanID) {
            retryingScanID = nil
        }
        retryRefreshRequest = nil
    }

    func publishSeededHandoffCompletion() {
        dependencies.publishScanLibraryChanged()
    }
}
