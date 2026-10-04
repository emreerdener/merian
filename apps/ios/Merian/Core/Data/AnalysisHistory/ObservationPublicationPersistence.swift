import Foundation
import SwiftData

/// Durable consent and receipts. Network dispatch belongs to the delivery service.
enum ObservationPublicationPersistence {
    static let prefix = "observation-publication:"
    enum IntegrityError: Error { case conflict, unavailable, accountChanged }
    static func observationPrefix(_ observationID: UUID) -> String { prefix + observationID.uuidString.lowercased() + ":" }
    static func jobID(_ operationID: UUID, observationID: UUID) -> String {
        observationPrefix(observationID) + operationID.uuidString.lowercased()
    }

    @MainActor
    static func stage(_ request: ObservationPublicationRequest, ownerID: UUID, container: ModelContainer,
                      isCurrent: () -> Bool, validateNew: (ModelContext) throws -> Void = { _ in },
                      save: (ModelContext) throws -> Void = { try $0.save() }) throws -> ObservationPublicationIntent {
        let candidate = try ObservationPublicationIntent(request: request, ownerID: ownerID)
        return try transaction(candidate, container: container, isCurrent: isCurrent, save: save) { context in
            // Backend operation UUIDs are globally unique, even though local keys
            // also include observation identity for metadata-independent erasure.
            let suffix = ":" + request.operationID.uuidString.lowercased()
            let existingJobs = try context.fetch(FetchDescriptor<OfflineJobRecord>()).filter {
                $0.id.hasPrefix(prefix) && $0.id.hasSuffix(suffix)
            }
            guard existingJobs.count <= 1 else { throw IntegrityError.conflict }
            if let existing = existingJobs.first {
                let saved = try restore(existing)
                guard saved.ownerID == ownerID, saved.identity == request.statusRequest,
                      saved.requestSHA256 == candidate.requestSHA256 else { throw IntegrityError.conflict }
                return saved
            }
            // Exact replay remains recoverable after authority advances. Only
            // newly accepted consent must still match the foreground preview.
            try validateNew(context)
            guard let text = String(bytes: try candidate.storedData(), encoding: .utf8) else { throw IntegrityError.conflict }
            context.insert(OfflineJobRecord(id: jobID(request.operationID, observationID: request.observationID), kind: .observationPublicationSync,
                subjectId: request.observationID.uuidString.lowercased(), priority: 65,
                metadataJSON: text))
            return candidate
        }
    }

    /// Compare-and-save prevents a stale response replacing a newer or deleted job.
    @MainActor
    static func acknowledge(_ receipt: ObservationPublicationReceipt, expected: ObservationPublicationIntent,
                            at date: Date, container: ModelContainer, isCurrent: () -> Bool,
                            claim: Claim? = nil, save: (ModelContext) throws -> Void = { try $0.save() }) throws -> ObservationPublicationIntent {
        try transaction(expected, container: container, isCurrent: isCurrent, save: save) { context in
            guard let job = try context.fetchOfflineJob(id: jobID(expected.identity.operationID, observationID: expected.identity.observationID)) else {
                throw IntegrityError.unavailable
            }
            if let claim { try validate(claim, job: job) } else if job.status == .running { throw IntegrityError.conflict }
            let saved = try restore(job)
            guard try saved.storedData() == expected.storedData() else { throw IntegrityError.conflict }
            let next = try saved.accepting(receipt, at: date)
            if saved.isTerminal { return next }
            guard let text = String(bytes: try next.storedData(), encoding: .utf8) else { throw IntegrityError.conflict }
            job.metadataJSON = text
            job.status = next.isTerminal ? .complete : .waiting
            job.nextRunAt = next.isTerminal ? nil : date.addingTimeInterval(30)
            job.lastErrorCode = nil; job.lastErrorMessage = nil; job.lastHTTPStatus = nil
            job.updatedAt = date
            return next
        }
    }

    static func restore(_ job: OfflineJobRecord) throws -> ObservationPublicationIntent {
        guard job.kindRaw == OfflineJobKind.observationPublicationSync.rawValue,
              let text = job.metadataJSON else { throw IntegrityError.conflict }
        let saved = try ObservationPublicationIntent.decode(Data(text.utf8))
        guard job.id == jobID(saved.identity.operationID, observationID: saved.identity.observationID),
              job.subjectId == saved.identity.observationID.uuidString.lowercased() else { throw IntegrityError.conflict }
        if saved.isTerminal {
            guard job.statusRaw == OfflineJobStatus.complete.rawValue, job.nextRunAt == nil else { throw IntegrityError.conflict }
        } else {
            guard [OfflineJobStatus.pending.rawValue, OfflineJobStatus.running.rawValue, OfflineJobStatus.waiting.rawValue, OfflineJobStatus.needsAttention.rawValue]
                .contains(job.statusRaw) else { throw IntegrityError.conflict }
        }
        return saved
    }

    /// Caller owns the deletion transaction/save. Erases even malformed local consent.
    /// Cloud-confirmation fallback requires exact owner; ambiguous ownership keeps deletion retryable.
    static func removeForDeletion(_ scanID: String, context: ModelContext, ownerID: UUID? = nil) throws {
        guard let observationID = UUID(uuidString: scanID) else { return }
        let scope = observationPrefix(observationID)
        // The primary key is the independent erasure index. Never trust damaged
        // subject metadata to select another observation's namespace.
        for job in try context.fetch(FetchDescriptor<OfflineJobRecord>()) where job.id.hasPrefix(scope) {
            if let ownerID {
                guard let text = job.metadataJSON else { throw IntegrityError.conflict }
                let intent = try ObservationPublicationIntent.decode(Data(text.utf8))
                guard job.id == jobID(intent.identity.operationID, observationID: intent.identity.observationID) else {
                    throw IntegrityError.conflict
                }
                guard intent.ownerID == ownerID else { continue }
            }
            context.delete(job)
        }
    }

    @MainActor
    static func transaction<T>(
        _ intent: ObservationPublicationIntent, container: ModelContainer,
        isCurrent: () -> Bool, save: (ModelContext) throws -> Void = { try $0.save() },
        body: (ModelContext) throws -> T
    ) throws -> T {
        try ConfirmedSpeciesReviewPersistence.transaction {
            guard isCurrent() else { throw IntegrityError.accountChanged }
            let context = ModelContext(container); context.autosaveEnabled = false
            do {
                let scan = try ObservationHistorySyncService.enrolledScan(intent.identity.observationID.uuidString, context: context)
                guard scan.analysisOwnerAccountID == intent.ownerID.uuidString.lowercased(),
                      !(try ObservationHistoryEnrollmentIntent.holds(scan.id, context: context)) else { throw IntegrityError.unavailable }
                let id = intent.identity.analysisID.uuidString.lowercased()
                var query = FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == id })
                query.fetchLimit = 1
                guard let analysis = try context.fetch(query).first,
                      analysis.ownerAccountID == scan.analysisOwnerAccountID,
                      analysis.observationID == scan.id else { throw IntegrityError.unavailable }
                let result = try body(context)
                try Task.checkCancellation()
                guard isCurrent() else { throw IntegrityError.accountChanged }
                if context.hasChanges { try save(context) }
                return result
            } catch { context.rollback(); throw error }
        }
    }
}
