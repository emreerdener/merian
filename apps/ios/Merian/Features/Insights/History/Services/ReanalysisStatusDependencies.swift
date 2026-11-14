import Foundation
import SwiftData

@MainActor
struct ReanalysisStatusAccess {
    struct RetirementConfiguration {
        let ownership: ObservationReanalysisPreparationOwner
        let fetch: (ObservationAnalysisExecutionLookup, UUID, @escaping ObservationReanalysisExecutor.Validator) async throws -> ObservationAnalysisExecutionStatus
        let wake: () -> Void
        var generation: () -> UInt64 = { 0 }
        var recover: ((ObservationReanalysisIntent, @escaping ObservationReanalysisExecutor.Validator) async throws -> Data?)?
        var completionAttempted: () -> Void = {}
        var documents: () throws -> URL = {
            try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        }
    }
    var available: (String, ModelContainer) -> Bool
    var open: (String, ModelContainer) throws -> ReanalysisStatusDependencies

    /// Prepared only; ordinary Shell access remains nil.
    static var prepared: Self {
        prepared(session: { try IdentificationHistorySession(observation: $0, container: $1) })
    }
    static func prepared(session: @escaping (String, ModelContainer) throws -> IdentificationHistorySession,
                         retirement: RetirementConfiguration? = nil) -> Self {
        Self(available: { id, container in
            guard let session = try? session(id, container) else { return false }
            defer { session.close() }
            guard let page = try? session.operationStatusPage(after: nil) else { return false }
            return offersPage(page)
        }, open: { id, container in
            try session(id, container).operationStatusDependencies(retirement: retirement)
        })
    }
    static func offersPage(_ page: ObservationReanalysisOperationStatus.Page) -> Bool {
        // Omitted corrupt rows must not hide valid work on later bounded pages.
        !page.items.isEmpty || page.next != nil
    }
}

@MainActor
struct ReanalysisStatusDependencies {
    var page: (ObservationReanalysisOperationStatus.Cursor?) async throws -> ObservationReanalysisOperationStatus.Page
    var validate: () throws -> Void
    var isCurrent: () -> Bool
    var close: () -> Void
    var generation: () -> UInt64 = { 0 }
    var recovery: ((ObservationReanalysisOperationStatus.Summary) throws -> AnalysisRecoveryCheckingModel.Access)?
    var photo: ((ObservationReanalysisOperationStatus.Summary, Int, @escaping @MainActor @Sendable () -> Bool) async throws -> ReanalysisSavedPhotoAccess.Preview)?
    var retire: ((ObservationReanalysisOperationStatus.Summary, UUID) async throws -> ObservationReanalysisRetirementAction.Outcome)?
}

extension IdentificationHistorySession {
    func operationStatusPage(after cursor: ObservationReanalysisOperationStatus.Cursor?) throws -> ObservationReanalysisOperationStatus.Page {
        try check()
        let result = try ObservationReanalysisOperationStatus(account: cloud).page(
            observationID: ObservationHistoryPage.uuid(observation), ownerID: session.userID, after: cursor,
            container: container, isCurrent: { [self] in isCurrent() })
        try check()
        return result
    }
    var operationStatusDependencies: ReanalysisStatusDependencies { operationStatusDependencies(retirement: nil) }

    func operationStatusDependencies(retirement: ReanalysisStatusAccess.RetirementConfiguration?) -> ReanalysisStatusDependencies {
        var dependencies = ReanalysisStatusDependencies(page: { [self] cursor in try operationStatusPage(after: cursor) },
            validate: { [self] in try check() }, isCurrent: { [self] in isCurrent() }, close: { [self] in close() })
        if let retirement {
            dependencies.generation = retirement.generation
            dependencies.photo = { [self] row, index, presented in
                try check()
                let identity = OfflineQueueWork.Reanalysis(observationID: try ObservationHistoryPage.uuid(observation),
                    sourceAnalysisID: row.sourceAnalysisID, analysisID: row.id, ownerID: session.userID)
                return try await ReanalysisSavedPhotoAccess.read(identity: identity, index: index, container: container,
                    files: ObservationReanalysisFileStore(documents: retirement.documents()), ownership: retirement.ownership,
                    account: cloud, isCurrent: { [self] in isCurrent() && presented() })
            }
            if let recover = retirement.recover {
                dependencies.recovery = { [self] row in
                    try check()
                    guard row.canCheckOutcome else { throw ObservationHistoryError.unavailable }
                    let identity = OfflineQueueWork.Reanalysis(observationID: try ObservationHistoryPage.uuid(observation),
                        sourceAnalysisID: row.sourceAnalysisID, analysisID: row.id, ownerID: session.userID)
                    let current: @MainActor @Sendable () -> Bool = { [self] in commonEnvironmentIsCurrent() }
                    return .prepared(identity: identity, container: container, isCurrent: current, validateOperation: { [self] in
                        let saved = try ObservationReanalysisExecutionStore.read(identity, container: container, isCurrent: current)
                        guard ObservationReanalysisExecutionStore.canRecoverHeldOutcome(saved) else { throw ObservationHistoryError.unavailable }
                    }, check: { [self] in
                        try await ObservationReanalysisOutcomeAction(ownership: retirement.ownership, account: cloud,
                            recover: recover, completionAttempted: retirement.completionAttempted).perform(identity,
                                container: container, isCurrent: current)
                    })
                }
            }
            dependencies.retire = { [self] row, operation in
                try check()
                guard row.retirement != nil else { return .unavailable }
                let identity = OfflineQueueWork.Reanalysis(observationID: try ObservationHistoryPage.uuid(observation),
                    sourceAnalysisID: row.sourceAnalysisID, analysisID: row.id, ownerID: session.userID)
                return try await ObservationReanalysisRetirementAction(ownership: retirement.ownership, account: cloud,
                    fetch: retirement.fetch, wake: retirement.wake).perform(identity, operationID: operation,
                        container: container, isCurrent: { [self] in commonEnvironmentIsCurrent() })
            }
        }
        return dependencies
    }
}
