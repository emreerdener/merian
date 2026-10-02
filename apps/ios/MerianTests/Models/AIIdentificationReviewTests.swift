import Foundation
import SwiftData
import Testing
@testable import Merian

@MainActor
@Suite("Identification rejection")
struct AIIdentificationReviewTests {
    let scanID = "00000000-0000-4000-8000-000000000001"
    let ownerID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!

    @Test func rejectingPersistsIntentAndOutboxTogetherWithoutChangingEvidence() throws {
        let container = try ModelContainer(for: Schema(versionedSchema: CurrentSchema.self), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let scan = LocalScanRecord(id: scanID, speciesId: "species", scientificName: "Fixtureus species", commonName: "Fixture")
        scan.userConfirmedIdentification = true
        scan.customTags = ["garden"]
        scan.fieldNotes = "Synthetic note"
        context.insert(scan); try context.save()
        let service = IdentificationReviewSyncService(dependencies: .init(ownerID: { ownerID }))
        let state = try service.enqueue(scanID: scanID, action: .reject, context: context)
        #expect(state.isUnresolved)
        #expect(state.authority == nil)
        let fresh = ModelContext(container)
        let restored = try IdentificationReviewSyncService.record(scanID, context: fresh)
        let saved = try #require(restored)
        #expect(saved.localAIIdentificationReview.pending?.action == .reject)
        #expect(!saved.userConfirmedIdentification)
        #expect(!saved.hasSpeciesLevelIdentification)
        #expect(saved.effectiveSpeciesNameForStatistics == nil)
        #expect(saved.scientificName == "Fixtureus species")
        #expect(saved.customTags == ["garden"])
        #expect(saved.fieldNotes == "Synthetic note")
        #expect(try fresh.fetch(FetchDescriptor<OfflineJobRecord>()).count == 1)
        let undone = try service.enqueue(scanID: scanID, action: .undo, context: fresh)
        #expect(!undone.isUnresolved)
        let restoredAfterUndo = try IdentificationReviewSyncService.record(scanID, context: ModelContext(container))
        let afterUndo = try #require(restoredAfterUndo)
        #expect(!afterUndo.userConfirmedIdentification)
        #expect(undone.pending?.expectedRevision == 1)
        #expect(try ModelContext(container).fetch(FetchDescriptor<OfflineJobRecord>()).count == 2)
    }

    @Test func rejectionCanBeRepeatedAfterUndoBeforeEitherOperationSyncs() throws {
        let container = try ModelContainer(for: Schema(versionedSchema: CurrentSchema.self), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        context.insert(LocalScanRecord(id: scanID, speciesId: "species", scientificName: "Fixtureus species", commonName: "Fixture"))
        try context.save()
        let service = IdentificationReviewSyncService(dependencies: .init(ownerID: { ownerID }))
        var species = SpeciesData(scanId: scanID, commonName: "Fixture", scientificName: "Fixtureus species",
            insightData: InsightData(aiReasoning: "Synthetic observation", hazardType: "none"),
            confidenceScore: 0.8, isBiological: true)
        #expect(species.canMarkIdentificationIncorrect)
        species.aiReview = try service.enqueue(scanID: scanID, action: .reject, context: context)
        #expect(!species.canMarkIdentificationIncorrect)
        #expect(species.canUndoIncorrectIdentification)
        _ = try service.enqueue(scanID: scanID, action: .undo, context: context)
        let restored = try IdentificationReviewSyncService.record(scanID, context: ModelContext(container))
        let saved = try #require(restored)
        species.aiReview = saved.localAIIdentificationReview
        #expect(species.aiReview.pending?.action == .undo)
        #expect(species.canMarkIdentificationIncorrect)
        #expect(!species.canUndoIncorrectIdentification)
        #expect(!saved.userConfirmedIdentification)
        species.aiReview = try service.enqueue(scanID: scanID, action: .reject, context: context)
        #expect(species.aiReview.pending?.expectedRevision == 2)
        #expect(!species.canMarkIdentificationIncorrect)
        #expect(species.canUndoIncorrectIdentification)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 3)
    }

    @Test func legacyPresentationDoesNotClearStoredRejection() {
        var species = SpeciesData(scanId: scanID, commonName: "Fixture", scientificName: "Fixtureus species",
            insightData: InsightData(aiReasoning: "Synthetic observation", hazardType: "none"),
            confidenceScore: 0.8, isBiological: true)
        species.aiReview = .init(optimisticState: .aiRejected)
        #expect(species.legacyIdentificationPresentation.hasSpeciesLevelIdentification)
        #expect(species.presentationConfidenceScore == 0.8)
        #expect(species.subjectDisplayName(isAudioOnlyObservation: true) == "Fixture")
        #expect(species.aiReview.isUnresolved)
        #expect(!species.hasSpeciesLevelIdentification)
    }

    @Test func serverReviewRoundTripsAndRejectsEqualRevisionConflicts() throws {
        let original = AIIdentificationReview(revision: 1, state: .aiRejected, originScanID: scanID,
            originIdentification: .init(scientificName: "Fixtureus species", commonName: nil))
        #expect(try AIIdentificationReview.restoring(original.storedData()) == original)
        let competing = AIIdentificationReview(revision: 1, state: .clear, originScanID: scanID, originIdentification: nil)
        #expect(throws: ConfirmedSpeciesReview.IntegrityError.self) { try AIIdentificationReview.merging(stored: original, incoming: competing) }
        #expect(LocalAIIdentificationReview.restoring(Data("invalid".utf8)).isUnresolved)
    }

    @Test func reanalysisStagesProposalAndDurableCarryBeforeSourceDeletion() throws {
        let container = try ModelContainer(for: Schema(versionedSchema: CurrentSchema.self), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let source = LocalScanRecord(id: scanID, speciesId: "species", scientificName: "Fixtureus species", commonName: "Fixture")
        source.aiIdentificationReviewData = try LocalAIIdentificationReview(authority: .init(revision: 2, state: .aiRejected, originScanID: scanID, originIdentification: nil)).storedData()
        let replacement = LocalScanRecord(id: "00000000-0000-4000-8000-000000000003", speciesId: "new", scientificName: "Fixtureus proposal", commonName: "Proposal")
        context.insert(source); context.insert(replacement); try context.save()
        let service = IdentificationReviewSyncService(dependencies: .init(ownerID: { ownerID }))
        try service.carryRejection(from: source, to: replacement, context: context); try context.save()
        #expect(replacement.localAIIdentificationReview.state == .awaitingAcceptance)
        #expect(replacement.localAIIdentificationReview.authority == nil)
        #expect(replacement.localAIIdentificationReview.pending?.sourceRevision == 2)
        #expect(!replacement.hasSpeciesLevelIdentification)
        #expect(try context.fetchCount(FetchDescriptor<LocalScanRecord>()) == 2)
    }
    @Test func delayedPredecessorPreventsSuccessorDispatch() async throws {
        let container = try ModelContainer(for: Schema(versionedSchema: CurrentSchema.self), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        context.insert(LocalScanRecord(id: scanID, speciesId: "species", scientificName: "Fixtureus species", commonName: "Fixture"))
        try context.save()
        var calls = 0
        var dependencies = IdentificationReviewSyncService.Dependencies(ownerID: { ownerID }, submit: { _ in
            calls += 1; throw ConfirmedSpeciesReview.IntegrityError.invalidRequest
        })
        dependencies.beginWork = { AccountBoundWorkLease(id: UUID(), session: AuthTransitionSession(userID: ownerID, isAnonymous: false)) }
        dependencies.finishWork = { _ in }; dependencies.isWorkCurrent = { _ in true }
        dependencies.didAccept = { _ in }; dependencies.retireSource = { _, _ in }
        let service = IdentificationReviewSyncService(dependencies: dependencies)
        let first = try service.enqueue(scanID: scanID, action: .reject, context: context)
        _ = try service.enqueue(scanID: scanID, action: .undo, context: context)
        let write = ModelContext(container)
        let operation = try #require(first.pending?.operationID)
        let loaded = try write.fetchOfflineJob(id: "identification-review:\(operation)")
        let job = try #require(loaded)
        job.nextRunAt = Date().addingTimeInterval(600); job.status = .waiting
        try write.save()
        await service.drain(context: context)
        #expect(calls == 0)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 2)
    }

    @Test func unreadableOutboxPreservesIntentAndNeverDispatches() async throws {
        let container = try ModelContainer(for: Schema(versionedSchema: CurrentSchema.self), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        context.insert(LocalScanRecord(id: scanID, speciesId: "species", scientificName: "Fixtureus species", commonName: "Fixture"))
        try context.save()
        var calls = 0
        var dependencies = IdentificationReviewSyncService.Dependencies(ownerID: { ownerID }, submit: { _ in
            calls += 1
            throw ConfirmedSpeciesReview.IntegrityError.invalidRequest
        })
        dependencies.loadPendingJobs = { _, _ in throw CocoaError(.fileReadUnknown) }
        let service = IdentificationReviewSyncService(dependencies: dependencies)
        let queued = try service.enqueue(scanID: scanID, action: .reject, context: context)
        await service.drain(context: context)
        let verification = ModelContext(container)
        #expect(calls == 0)
        #expect(try verification.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 1)
        #expect(try IdentificationReviewSyncService.record(scanID, context: verification)?.localAIIdentificationReview.pending == queued.pending)
    }

    @Test(arguments: [false, true])
    func historicalReviewMergePreservesRevisionAndPrimaryAuthority(hasPrimary: Bool) throws {
        let record = LocalScanRecord(id: scanID, speciesId: "species", scientificName: "Fixtureus species", commonName: "Fixture")
        record.userIdentificationOverride = "Fixtureus local"
        if hasPrimary {
            record.primaryIdentificationData = try PrimaryIdentification(snapshot: .init(resolution: .species, scientificName: "Fixtureus species", commonName: nil)).data
        }
        func response(revision: Int, state: AIIdentificationReview.State) throws -> HistoricalScanResponse {
            let review = AIIdentificationReview(revision: revision, state: state, originScanID: scanID, originIdentification: nil)
            let payload: [String: Any] = ["id": scanID,
                "ai_identification_review": try JSONSerialization.jsonObject(with: review.storedData()),
                "user_identification_override": "Fixtureus remote"]
            return try JSONDecoder().decode(HistoricalScanResponse.self, from: JSONSerialization.data(withJSONObject: payload))
        }
        #expect(try HistoricalPrimaryIdentification.mergeAIIdentificationReview(response(revision: 2, state: .aiRejected), into: record))
        #expect(record.localAIIdentificationReview.authority?.revision == 2)
        #expect(record.userIdentificationOverride == (hasPrimary ? "Fixtureus local" : "Fixtureus remote"))
        let stored = record.localAIIdentificationReview
        #expect(throws: ConfirmedSpeciesReview.IntegrityError.self) {
            try HistoricalPrimaryIdentification.mergeAIIdentificationReview(response(revision: 2, state: .clear), into: record)
        }
        #expect(record.localAIIdentificationReview == stored)
        _ = try HistoricalPrimaryIdentification.mergeAIIdentificationReview(response(revision: 1, state: .clear), into: record)
        #expect(record.localAIIdentificationReview == stored)
    }

}
