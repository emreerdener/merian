import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite("Queue Work Qualification", .sharedProcessState(.offlineQueueManager))
struct QueueWorkQualificationTests {
    private let parent = "00000000-0000-4000-8000-000000000701"
    private let source = "00000000-0000-4000-8000-000000000702"
    private let owner = "00000000-0000-4000-8000-000000000703"

    private func held(_ mode: Int, state: ScanQueueState) -> OfflineQueuedScan {
        let row = OfflineQueuedScan(id: UUID().uuidString.lowercased(), capturedMediaJSON: "[]", scanState: state)
        row.workKindRaw = "reanalysis"
        row.parentObservationID = parent
        row.sourceAnalysisID = source
        row.reanalysisOwnerAccountID = owner
        switch mode {
        case 1: row.workKindRaw = "future-kind"
        case 2: row.sourceAnalysisID = nil
        case 3: row.workKindRaw = "ordinary"
        case 4: row.reanalysisOwnerAccountID = "invalid"
        case 5: row.sourceAnalysisID = parent
        default: break
        }
        return row
    }

    @Test func classifierRequiresCompleteCanonicalDistinctLinkage() {
        let ordinary = OfflineQueuedScan(id: "legacy-non-uuid")
        #expect(ordinary.work == .ordinary)
        #expect(held(0, state: .pending).work != .invalid)
        for mode in 1...5 { #expect(held(mode, state: .pending).work == .invalid) }
        let row = held(0, state: .pending)
        row.sourceAnalysisID = row.id
        #expect(row.work == .invalid)
        row.sourceAnalysisID = "00000000-0000-4000-8000-000000000ABC"
        #expect(row.work == .invalid)
    }

    @Test func qualifiedAndDamagedRowsCannotEnterLegacyUploadOrInference() async throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        let context = ModelContext(container)
        let rows = (0...5).flatMap { mode in
            [held(mode, state: .pending), held(mode, state: .uploading), held(mode, state: .staged)]
        }
        for row in rows { context.insert(row) }
        let ordinary = OfflineQueuedScan(capturedMediaJSON: "[]", scanState: .pending)
        context.insert(ordinary)
        try context.save()
        let actor = BackgroundDatabaseActor(modelContainer: container)
        let candidates = await actor.fetchPendingScans(limit: 50)
        #expect(candidates.map(\.id) == [ordinary.id])
        let claimed = await actor.markScansAsUploading(scanIds: rows.map(\.id) + [ordinary.id])
        #expect(claimed == [ordinary.id])
        for row in rows {
            #expect(await actor.markScanAsStaged(scanId: row.id, r2Keys: ["synthetic/key"]) == .discarded)
            #expect(await actor.tryClaimForInference(scanId: row.id) == false)
        }
        let fresh = ModelContext(container)
        let saved = try fresh.fetch(FetchDescriptor<OfflineQueuedScan>()).filter { $0.id != ordinary.id }
        #expect(saved.count == rows.count)
        #expect(saved.allSatisfy { !$0.permitsOrdinaryInference && $0.stagedR2Keys == nil })
        #expect(try fresh.fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)
    }

    @Test func ordinaryCountTraversesPagesWithoutCountingHeldChildren() throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        let context = ModelContext(container)
        for _ in 0..<105 { context.insert(OfflineQueuedScan()) }
        for mode in 0...5 { context.insert(held(mode, state: .pending)) }
        try context.save()
        let manager = OfflineQueueManager.shared
        let previousContext = manager.modelContext
        let previousCount = manager.unsyncedItemsCount
        defer {
            manager.modelContext = previousContext
            manager.unsyncedItemsCount = previousCount
        }
        manager.modelContext = context
        manager.updateUnsyncedItemCount()
        #expect(manager.unsyncedItemsCount == 105)
    }

    @Test func lateCompletionAndGenerationAdoptionCannotCreateIndependentScan() async throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        let context = ModelContext(container)
        let rows = (0...5).map { held($0, state: .inferencing) }
        for row in rows {
            context.insert(row)
            context.insert(OfflineJobRecord(id: "scan-ingestion:" + row.id, kind: .scanIngestion,
                subjectId: row.id, metadataJSON: "{}"))
        }
        try context.save()
        let actor = BackgroundDatabaseActor(modelContainer: container)
        let ownership = BackgroundAccountWorkOwnership(ownerUserID: UUID(uuidString: owner)!, generation: UUID(), phase: .inference)
        for row in rows {
            #expect(await actor.activateBackgroundAccountWork(scanId: row.id, ownership: ownership) == false)
            #expect(await actor.backgroundAccountWorkIsCurrent(scanId: row.id, ownership: ownership) == false)
            #expect(await actor.retireBackgroundAccountWork(scanId: row.id, expectedOwnerUserID: ownership.ownerUserID,
                expectedGeneration: ownership.generation, phase: .inference))
            #expect(await actor.validateOrAdoptInferenceGenerationAssumingPersistenceLock(
                scanId: row.id, expectedGeneration: UUID()) == false)
            let value = SpeciesData(scanId: row.id, commonName: "Fixture", scientificName: "Synthetic fixture",
                insightData: InsightData(aiReasoning: "Synthetic", hazardType: "none"),
                confidenceScore: 0.9, isBiological: true, isLiveCapture: false)
            let result = await actor.persistOfflineScanResultAssumingPersistenceLock(mappedData: value,
                originalImagePaths: [], scanId: row.id, originalTimestamp: Date(), observationContextsJSON: nil,
                audioFilePaths: nil, videoFilePaths: nil, capturedMediaJSON: nil)
            #expect(!result.wasCleaned)
            #expect(await actor.scheduleInferenceRetry(id: row.id, expectedGeneration: nil,
                code: "synthetic", message: nil, delay: 1) == nil)
        }
        let fresh = ModelContext(container)
        #expect(try fresh.fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)
        let retained = try fresh.fetch(FetchDescriptor<OfflineQueuedScan>())
        #expect(retained.count == rows.count && retained.allSatisfy { $0.queueState == .inferencing })
        #expect(try fresh.fetch(FetchDescriptor<OfflineJobRecord>()).allSatisfy { $0.metadataJSON == "{}" })
        #expect(await actor.fetchServerOwnedInferencingScanIds(excludingScanIds: [], observedThrough: .distantFuture).isEmpty)
    }
}
