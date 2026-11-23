import Foundation
import SwiftData

/// Capture's first local result commit. The registered owner retains the scan,
/// account and physical-root fences through the final synchronous save.
/// Upload acknowledgements alone can never enter this transition.
@MainActor
enum SharedMediaCaptureResultWriter {
    enum Outcome: Equatable, Sendable { case inserted, retained }

    /// A synchronous, expiring handoff minted only after durable result custody.
    @MainActor
    final class FundingHandoff {
        let settlement: InferenceResponseSettlement
        private let account: InferenceCompletionAccountScope
        private var active = true
        fileprivate init(_ settlement: InferenceResponseSettlement, account: InferenceCompletionAccountScope) {
            self.settlement = settlement; self.account = account
        }
        func validate() throws {
            try account.validate()
            guard active, settlement.accountId == account.ownerID else { throw SharedMediaStorageFailure.stale }
        }
        fileprivate func expire() { active = false }
    }

    static func complete(scanID: UUID, submissionGeneration: UUID, attemptGeneration: UUID,
                         resultData: Data, account: InferenceCompletionAccountScope,
                         container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                         files: SharedMediaCaptureArtifactFiles,
                         availableBytes: () throws -> Int64,
                         funding: SharedMediaCaptureFundingSettlement.Delivery,
                         boundary: (SharedMediaCaptureReservationBoundary) throws -> Void = { _ in }) async throws -> Outcome {
        try account.validate()
        guard account.ownerID == authority.profile.ownerID, resultData.count <= OrdinaryInferenceCompletion.maximumBytes else {
            throw SharedMediaStorageFailure.conflict
        }
        let prepared = try await InferenceResponsePreparationService.live.prepare(resultData: resultData,
            telemetry: nil, audioFilePaths: nil, videoFilePaths: nil, expectedScanId: scanID.uuidString.lowercased())
        try account.validate(); _ = try authority.header(container); try files.check()
        let mappedData = prepared.mappedData
        let completion = try OrdinaryInferenceCompletion.prepare(resultData: resultData, mappedData: mappedData,
            scanID: scanID.uuidString.lowercased(), generation: attemptGeneration,
            account: account, initialEvidence: prepared.initialEvidence)
        try completion.requireInitialSubmission(.init(ownerID: authority.profile.ownerID,
            scanID: scanID, generation: submissionGeneration))
        let before = try authority.header(container)
        let totals = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files)
        try completion.account.validate(); try files.check()
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        let context = ModelContext(container); context.autosaveEnabled = false
        let saved = try SharedMediaCaptureCompletedCustody.read(scanID: scanID,
            generation: submissionGeneration, ownerID: authority.profile.ownerID, context: context)
        guard saved.submission.profile == authority.profile,
              saved.submission.rootBindingSHA256 == files.rootBindingSHA256 else { throw SharedMediaStorageFailure.conflict }
        let job = try SharedMediaCaptureCompletionReadback.job(saved.submission, context: context)
        guard let raw = job.metadataJSON, InferenceGenerationMetadataContract.matches(completion.generation, in: raw),
              job.status != .cancelled else { throw SharedMediaStorageFailure.conflict }
        let fundingReceipt = try SharedMediaCaptureFundingReceipt(scanID: scanID, settlement: prepared.fundingSettlement,
            resolutionSHA256: SharedMediaCaptureFundingResolution.read(raw, submission: saved.submission)?.digest)
        _ = try fundingReceipt.settlement(ownerID: account.ownerID)
        let lower = completion.scanID, upper = scanID.uuidString
        var query = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == lower || $0.id == upper })
        query.fetchLimit = 2
        let existing = try context.fetch(query)
        if !existing.isEmpty {
            guard existing.count == 1, let record = existing.first, record.id == lower,
                  record.mediaAuthorityRaw == SharedMediaCaptureAcceptance.mediaAuthority, record.sharedMediaConsumerID == nil,
                  job.status == .complete, try completion.matchesRetainedMetadata(raw) else {
                throw SharedMediaStorageFailure.conflict
            }
            // Review, selected analysis, privacy and notes may have changed.
            // An exact original result replay must not restore their old values.
            try deliverFunding(saved, incoming: prepared.fundingSettlement, account: account,
                container: container, authority: authority, files: files, settle: funding)
            return .retained
        }
        guard job.status != .complete else { throw SharedMediaStorageFailure.conflict }
        let submitted = saved.submission.context
        let name = mappedData.scientificName
        var species = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.scientificName == name })
        species.fetchLimit = 1; species.propertiesToFetch = [\.speciesId]
        let speciesID = try context.fetch(species).first?.speciesId ?? UUID().uuidString
        let record = LocalScanRecordFactory.makeRecord(from: mappedData, recordId: lower, speciesId: speciesID,
            timestamp: submitted.timestamp, captureDate: submitted.timestamp, capturedMediaJSON: nil,
            coverImagePath: nil, isLiveCapture: mappedData.isLiveCapture, fieldNotes: submitted.initialFieldNotes)
        record.mediaAuthorityRaw = SharedMediaCaptureAcceptance.mediaAuthority
        record.sharedMediaConsumerID = nil
        record.gpsLatitude = submitted.gpsLatitude; record.gpsLongitude = submitted.gpsLongitude
        record.gpsElevation = submitted.gpsElevation; record.locationName = submitted.locationName
        record.weatherCondition = submitted.weatherCondition; record.weatherTemperatureF = submitted.weatherTemperatureF
        record.zoomFactor = submitted.zoomFactor
        // Compute immutable result proof before modifying this clean context.
        let retained = try fundingReceipt.retaining(in: completion.retentionMetadata(on: record, metadata: raw))
        // Result metadata and the library projection are new database copies.
        // Keep the existing media reservations covered while admitting them.
        try totals.checkAvailable(availableBytes(), additionalReservation:
            Int64(retained.utf8.count + 2 * OrdinaryInferenceCompletion.maximumBytes + 8192))
        job.metadataJSON = retained; job.status = .complete; job.nextRunAt = nil
        context.insert(record)
        try boundary(.beforeSave)
        try completion.account.validate(); try files.check()
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        try context.save()
        try boundary(.afterSave)
        try completion.account.validate(); try files.check()
        _ = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files)
        try completion.account.validate()
        let readback = ModelContext(container); readback.autosaveEnabled = false
        let current = try SharedMediaCaptureCompletedCustody.read(scanID: scanID,
            generation: submissionGeneration, ownerID: authority.profile.ownerID, context: readback)
        let committed = try SharedMediaCaptureCompletionReadback.job(current.submission, context: readback)
        guard current == saved, committed.status == .complete, committed.metadataJSON == retained,
              try readback.fetch(query).count == 1 else { throw SharedMediaStorageFailure.conflict }
        try deliverFunding(saved, incoming: prepared.fundingSettlement, account: account,
            container: container, authority: authority, files: files, settle: funding)
        return .inserted
    }

    /// Recover the original committed settlement without reacquiring a provider
    /// response. This never dispatches inference or changes media custody.
    static func recoverFunding(scanID: UUID, generation: UUID, account: InferenceCompletionAccountScope,
                               container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                               files: SharedMediaCaptureArtifactFiles, funding: SharedMediaCaptureFundingSettlement.Delivery) async throws {
        try account.validate()
        guard account.ownerID == authority.profile.ownerID else { throw SharedMediaStorageFailure.conflict }
        let before = try authority.header(container)
        _ = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files)
        try account.validate(); try files.check()
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        let context = ModelContext(container); context.autosaveEnabled = false
        let lower = scanID.uuidString.lowercased(), upper = scanID.uuidString
        var query = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == lower || $0.id == upper })
        query.fetchLimit = 2
        let records = try context.fetch(query)
        guard records.count == 1, let record = records.first, record.id == lower,
              record.mediaAuthorityRaw == SharedMediaCaptureAcceptance.mediaAuthority,
              record.sharedMediaConsumerID == nil else { throw SharedMediaStorageFailure.conflict }
        let saved = try SharedMediaCaptureCompletedCustody.read(scanID: scanID, generation: generation,
            ownerID: account.ownerID, context: context)
        guard saved.submission.profile == authority.profile,
              saved.submission.rootBindingSHA256 == files.rootBindingSHA256 else { throw SharedMediaStorageFailure.conflict }
        let job = try SharedMediaCaptureCompletionReadback.job(saved.submission, context: context)
        guard job.status == .complete, let raw = job.metadataJSON,
              try OrdinaryInferenceCompletion.retainedInitialIdentity(metadata: raw, scanID: scanID, owner: account.ownerID)
                == .init(ownerID: account.ownerID, scanID: scanID, generation: generation) else { throw SharedMediaStorageFailure.conflict }
        try deliverFunding(saved, incoming: nil, account: account, container: container,
            authority: authority, files: files, settle: funding)
    }

    private static func deliverFunding(_ saved: SharedMediaCaptureSubmissionReceipt.Snapshot,
                                       incoming: InferenceResponseSettlement?, account: InferenceCompletionAccountScope,
                                       container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                                       files: SharedMediaCaptureArtifactFiles, settle: SharedMediaCaptureFundingSettlement.Delivery) throws {
        try account.validate(); try files.check()
        let before = try authority.header(container), submission = saved.submission
        let context = ModelContext(container); context.autosaveEnabled = false
        guard try SharedMediaCaptureCompletedCustody.read(scanID: submission.scanID,
            generation: submission.generation, ownerID: account.ownerID, context: context) == saved else {
            throw SharedMediaStorageFailure.stale
        }
        let job = try SharedMediaCaptureCompletionReadback.job(submission, context: context)
        guard job.status == .complete, let raw = job.metadataJSON else { throw SharedMediaStorageFailure.conflict }
        let receipt = try SharedMediaCaptureFundingReceipt.read(raw)
        guard receipt.scanID == submission.scanID else { throw SharedMediaStorageFailure.conflict }
        try receipt.requireReplay(incoming)
        let settlement = try receipt.settlement(ownerID: account.ownerID)
        guard saved.release == nil || receipt.delivered else { throw SharedMediaStorageFailure.closed }
        guard !receipt.delivered else { return }
        guard let settlement else { throw SharedMediaStorageFailure.conflict }
        let handoff = FundingHandoff(settlement, account: account)
        defer { handoff.expire() }
        try handoff.validate(); try settle.apply(handoff); try handoff.validate()
        var delivered = receipt; delivered.delivered = true
        let acknowledged = try delivered.retaining(in: raw, replacing: receipt)
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        try files.check()
        job.metadataJSON = acknowledged
        job.nextRunAt = nil
        try context.save()
        try handoff.validate(); try files.check()
        let readback = ModelContext(container); readback.autosaveEnabled = false
        guard try authority.header(container) == before,
              try SharedMediaCaptureCompletedCustody.read(scanID: submission.scanID,
                generation: submission.generation, ownerID: account.ownerID, context: readback) == saved,
              try SharedMediaCaptureCompletionReadback.job(submission, context: readback).metadataJSON == acknowledged,
              try SharedMediaCaptureCompletionReadback.job(submission, context: readback).nextRunAt == nil else {
            throw SharedMediaStorageFailure.stale
        }
    }
}

/// Persisted custody joins for result replay and explicit History enrollment.
/// These reads confer no filesystem access or original-release permission.
@MainActor
enum SharedMediaCaptureCompletionReadback {
    static func custody(scanID: UUID, generation: UUID, ownerID: UUID,
                        context: ModelContext) throws -> SharedMediaCaptureSubmissionReceipt.Snapshot {
        guard let saved = try SharedMediaCaptureSubmissionReceipt.matching(scanID: scanID, generation: generation, in: context),
              saved.submission.scanID == scanID, saved.submission.generation == generation,
              saved.submission.profile.ownerID == ownerID else { throw SharedMediaStorageFailure.conflict }
        _ = try SharedMediaCaptureUploadReadiness.require(saved)
        try SharedMediaCaptureQueueIdentity.require(saved.submission, in: context)
        return saved
    }

    static func job(_ submission: SharedMediaCaptureSubmission, context: ModelContext) throws -> OfflineJobRecord {
        guard let job = try context.fetchOfflineJob(id: submission.jobID), job.kind == .scanIngestion,
              job.subjectId == submission.scanID.uuidString.lowercased() else { throw SharedMediaStorageFailure.conflict }
        return job
    }

    static func retained(for record: LocalScanRecord, ownerID: UUID, context: ModelContext) throws -> OrdinaryInferenceCompletion.Proof {
        guard record.mediaAuthorityRaw == SharedMediaCaptureAcceptance.mediaAuthority, record.sharedMediaConsumerID == nil,
              let scanID = UUID(uuidString: record.id), record.id == scanID.uuidString.lowercased(),
              let initial = try OrdinaryInferenceCompletion.retainedInitial(for: record, owner: ownerID, context: context),
              let proof = try OrdinaryInferenceCompletion.retainedResultProof(for: record, owner: ownerID, context: context) else {
            throw SharedMediaStorageFailure.conflict
        }
        _ = try custody(scanID: scanID, generation: initial.generation, ownerID: ownerID, context: context)
        return proof
    }
}
