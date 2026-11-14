import Foundation
import SwiftData

enum ObservationReanalysisErasurePersistence {
    /// Filesystem owner already holds the child lock. Never wait for I/O inside this transaction.
    @MainActor
    static func validate(_ receipt: ObservationReanalysisErasureReceipt, container: ModelContainer,
                         isCurrent: () -> Bool, complete: Bool = false,
                         save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Bool {
        try ConfirmedSpeciesReviewPersistence.transaction {
            guard isCurrent() else { throw ObservationReanalysisPersistence.IntegrityError.unavailable }
            let context = ModelContext(container); context.autosaveEnabled = false
            do {
                guard let job = try context.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(receipt.childID)),
                      try ObservationReanalysisErasureReceipt.restore(job) == receipt else { throw ObservationReanalysisPersistence.IntegrityError.conflict }
                let lower = receipt.childID.uuidString.lowercased(), upper = receipt.childID.uuidString
                guard try context.fetch(FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == lower || $0.id == upper })).isEmpty else {
                    throw ObservationReanalysisPersistence.IntegrityError.conflict
                }
                let pending = job.statusRaw == OfflineJobStatus.pending.rawValue
                if pending && complete { job.status = .complete }
                try Task.checkCancellation()
                guard isCurrent() else { throw ObservationReanalysisPersistence.IntegrityError.unavailable }
                if context.hasChanges { try save(context) }
                return pending
            } catch { context.rollback(); throw error }
        }
    }
}
