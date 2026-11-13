import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class QueuedContentViewModel {
    enum ObservationState: Equatable {
        case idle, checking, unavailable
        case observed(ScanObservationResponse)
    }
    private(set) var observationState: ObservationState = .idle
    var hasObservationAction: Bool { dependencies.readObservation != nil }
    var canCheckObservation: Bool { observationVisible && hasObservationAction && observationTask == nil && observationCleanup == nil }
    struct ObservationTicket { fileprivate let generation: UUID }
    private var observationVisible = false
    func setObservationVisible(_ visible: Bool) {
        observationVisible = visible
        if !visible { closeObservation() }
    }
    func observationTicket() -> ObservationTicket? {
        canCheckObservation ? ObservationTicket(generation: observationGeneration) : nil
    }
    private var observationTask: Task<Void, Never>?
    private var observationCleanup: Task<Void, Never>?
    @ObservationIgnored private var observed: QueuedContentDependencies.Observation?
    @ObservationIgnored private var observationGeneration = UUID()

    func checkObservation(scanID: String, queueManager: OfflineQueueManager, ticket: ObservationTicket,
                          isCurrent: @escaping @MainActor () -> Bool) async {
        guard canCheckObservation, ticket.generation == observationGeneration, isCurrent(), let read = dependencies.readObservation else { return }
        let generation = UUID(); observationGeneration = generation
        observed = nil; observationState = .checking
        let task = Task { [self] in
            let current = { self.observationVisible && self.observationGeneration == generation && isCurrent() }
            do {
                try Task.checkCancellation()
                let result = try await read(queueManager, scanID, current)
                try Task.checkCancellation(); try result.validate()
                guard current() else { return }
                observed = result; observationState = .observed(result.value)
            } catch {
                if current() { observationState = .unavailable }
            }
        }
        observationTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if observationGeneration == generation { observationTask = nil }
    }

    func validateObservation() {
        guard let observed else { return }
        do { try observed.validate() } catch { self.observed = nil; observationState = .unavailable }
    }

    func closeObservation() {
        observationGeneration = UUID(); observed = nil; observationState = .idle
        guard let task = observationTask else { return }
        task.cancel(); observationTask = nil
        let previous = observationCleanup
        observationCleanup = Task { [self] in
            await previous?.value; await task.value; observationCleanup = nil
        }
    }

    func closeObservationAndWait() async {
        closeObservation(); await observationCleanup?.value
    }

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
