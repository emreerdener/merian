import Foundation
@testable import Merian
import SwiftData
import Testing

private actor CollectionSyncFenceRecorder {
    private var gateResults: [Bool]
    private(set) var invocationCount = 0

    init(gateResults: [Bool]) {
        self.gateResults = gateResults
    }

    func nextGateResult() -> Bool {
        guard !gateResults.isEmpty else { return false }
        return gateResults.removeFirst()
    }

    func recordInvocation() {
        invocationCount += 1
    }
}

@MainActor
struct BackgroundDatabaseActorTests {

    private enum ExpectedSerializedMedia {
        case image(String)
        case audio
        case description(String)
    }
    
    // Helper to create an isolated SwiftData container caching out to disk due to iOS 18 simulator array appending bugs.
    @MainActor
    private func createIsolatedContainer() throws -> ModelContainer {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let modelConfiguration = ModelConfiguration(schema: schema, url: tempURL)
        return try ModelContainer(for: schema, configurations: [modelConfiguration])
    }

    private func makeTempAudioFilename(prefix: String = "test_audio") throws -> String {
        let filename = "\(prefix)_\(UUID().uuidString).wav"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try Data(repeating: 0x55, count: 128).write(to: url)
        return filename
    }

    private func assertSerializedItems(
        _ items: [SerializedMediaItem],
        match expected: [ExpectedSerializedMedia]
    ) {
        #expect(items.count == expected.count)

        for (actual, expectation) in zip(items, expected) {
            switch (actual, expectation) {
            case (.image(let reference), .image(let expectedPath)):
                #expect(reference == expectedPath)
            case (.audio(let reference), .audio):
                #expect(reference.serializedPath.hasSuffix(".wav"))
                #expect(
                    FileManager.default.fileExists(
                        atPath: URL.documentsDirectory.appendingPathComponent(reference.serializedPath).path
                    )
                )
            case (.description(let context), .description(let expectedText)):
                #expect(context.freeText == expectedText)
            default:
                Issue.record("Serialized media kind mismatch: \(String(describing: actual))")
            }
        }
    }

    private func cleanupSerializedItems(_ items: [SerializedMediaItem]) {
        for item in items {
            switch item {
            case .image(let reference), .audio(let reference):
                try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(reference.serializedPath))
            case .video(let reference):
                for mediaReference in [reference.video, reference.thumbnail, reference.audio].compactMap({ $0 }) {
                    try? FileManager.default.removeItem(
                        at: URL.documentsDirectory.appendingPathComponent(mediaReference.serializedPath)
                    )
                }
            case .description:
                break
            }
        }
    }

    @Test func testBackgroundActorIsolatesSendablePayloadsDynamically() async throws {
        // Arrange
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let queuedScan = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("isolation_1.jpg"), SerializedMediaItem.image("isolation_2.jpg")]), encoding: .utf8))
        context.insert(queuedScan)
        try context.save()

        // Act: Invoke the actor entirely abstracted off the @MainActor through Task.detached
        let payloads = await Task.detached {
            let actor = BackgroundDatabaseActor(modelContainer: container)
            return await actor.fetchPendingScans(limit: 5)
        }.value

        // Assert: Ensure execution directly mapped Offline queues into Sendable structs correctly preventing Main Thread locks
        #expect(payloads.count == 1, "Background actor MUST safely extract database references natively")
        #expect(payloads.first?.localImagePaths.count == 2, "Actor isolation boundary MUST preserve deeply nested Array metadata cleanly")
        #expect(payloads.first?.id == queuedScan.id, "Sendable Payload struct MUST explicitly carry the offline scan UUID")
    }

    @Test func staleLiveGenerationCannotPersistOverReplacementAttempt() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let actor = BackgroundDatabaseActor(modelContainer: container)
        let manager = OfflineQueueManager.shared
        let scanId = "live_generation_fence_\(UUID().uuidString.lowercased())"
        let staleGeneration = UUID()
        let replacementGeneration = UUID()
        defer {
            manager.foregroundInferenceRetirementTasks.cancel(scanId)
            manager.startedForegroundInferenceGenerations.removeValue(
                forKey: scanId
            )
            manager.foregroundInferenceGenerations.removeValue(
                forKey: scanId
            )
        }

        context.insert(OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            scanState: .pending
        ))
        context.insert(OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .running,
            metadataJSON:
                InferenceGenerationMetadataContract.json(
                    for: replacementGeneration
                )
        ))
        try context.save()
        manager.foregroundInferenceGenerations[scanId] =
            staleGeneration
        manager.startedForegroundInferenceGenerations[scanId] =
            staleGeneration

        let staleSpecies = SpeciesData(
            scanId: scanId,
            commonName: "Stale Attempt",
            scientificName: "Attemptus stale",
            insightData: InsightData(
                aiReasoning: "Late provider response.",
                hazardType: "none"
            ),
            confidenceScore: 0.92,
            isBiological: true,
            isLiveCapture: false,
            isInvasive: false,
            ecologyType: "wild"
        )
        let replacementSpecies = SpeciesData(
            scanId: scanId,
            commonName: "Replacement Attempt",
            scientificName: "Attemptus current",
            insightData: InsightData(
                aiReasoning: "Current provider response.",
                hazardType: "none"
            ),
            confidenceScore: 0.96,
            isBiological: true,
            isLiveCapture: false,
            isInvasive: false,
            ecologyType: "wild"
        )

        let staleResult = await actor.saveNonVisualRecord(
            mappedData: staleSpecies,
            persistenceFence: LiveInferencePersistenceFence(
                scanId: scanId,
                generation: staleGeneration
            )
        )
        manager.foregroundInferenceGenerations[scanId] =
            replacementGeneration
        manager.startedForegroundInferenceGenerations[scanId] =
            replacementGeneration
        let mismatchedSpecies = SpeciesData(
            scanId: "\(scanId)-mismatched",
            commonName: "Mismatched Attempt",
            scientificName: "Attemptus mismatched",
            insightData: InsightData(
                aiReasoning: "Wrong scan identity.",
                hazardType: "none"
            ),
            confidenceScore: 0.96,
            isBiological: true,
            isLiveCapture: false,
            isInvasive: false,
            ecologyType: "wild"
        )
        let mismatchedResult = await actor.saveNonVisualRecord(
            mappedData: mismatchedSpecies,
            persistenceFence: LiveInferencePersistenceFence(
                scanId: scanId,
                generation: replacementGeneration
            )
        )
        manager.foregroundInferenceRetirementTasks.replace(
            for: scanId,
            ownerGeneration: replacementGeneration
        ) { _ in Task {} }
        let retiringResult = await actor.saveNonVisualRecord(
            mappedData: replacementSpecies,
            persistenceFence: LiveInferencePersistenceFence(
                scanId: scanId,
                generation: replacementGeneration
            )
        )
        manager.foregroundInferenceRetirementTasks.cancel(scanId)
        let replacementResult = await actor.saveNonVisualRecord(
            mappedData: replacementSpecies,
            persistenceFence: LiveInferencePersistenceFence(
                scanId: scanId,
                generation: replacementGeneration
            )
        )

        let verificationContext = ModelContext(container)
        let descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        let record = try #require(
            verificationContext.fetch(descriptor).first
        )
        #expect(!staleResult.wasSaved)
        #expect(!mismatchedResult.wasSaved)
        #expect(
            !retiringResult.wasSaved,
            "Retirement must fence persistence before durable handoff clears the raw generation"
        )
        #expect(replacementResult.wasSaved)
        #expect(record.commonName == "Replacement Attempt")
    }

    @Test func testCollectionSyncPayloadsReadDirectRelationshipsAndExcludeUnrelatedScans() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let firstMember = LocalScanRecord(
            id: "collection_member_b",
            speciesId: "species_b",
            scientificName: "Quercus alba",
            commonName: "White Oak"
        )
        let secondMember = LocalScanRecord(
            id: "collection_member_a",
            speciesId: "species_a",
            scientificName: "Danaus plexippus",
            commonName: "Monarch"
        )
        let unrelated = LocalScanRecord(
            id: "collection_unrelated",
            speciesId: "species_unrelated",
            scientificName: "Turdus migratorius",
            commonName: "American Robin"
        )
        let collection = ScanCollection(
            id: "collection_direct_members",
            name: "Field Notes",
            createdAt: Date(timeIntervalSince1970: 100),
            scans: [firstMember, secondMember]
        )
        let favorites = ScanCollection(
            id: "collection_favorites",
            name: "Favorites",
            createdAt: Date(timeIntervalSince1970: 50),
            scans: [unrelated]
        )

        context.insert(firstMember)
        context.insert(secondMember)
        context.insert(unrelated)
        context.insert(collection)
        context.insert(favorites)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let payloads = await actor.collectionSyncPayloads()

        #expect(payloads?.count == 1)
        #expect(payloads?.first?.id == collection.id)
        #expect(payloads?.first?.scan_ids == [secondMember.id, firstMember.id])
        #expect(payloads?.first?.scan_ids.contains(unrelated.id) == false)
    }

    @Test func collectionSyncDoesNotInvokeDuringAuthTransition() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let tombstone = ScanCollection(
            id: "collection_auth_transition_preflight",
            name: "Removed Collection",
            isPendingDeletion: true
        )
        context.insert(tombstone)
        try context.save()

        let fence = CollectionSyncFenceRecorder(gateResults: [false])
        let dbActor = BackgroundDatabaseActor(modelContainer: container)
        let result = await dbActor.pushCollectionsToEdge(
            accountWorkAllowed: { await fence.nextGateResult() },
            invoke: { _ in await fence.recordInvocation() }
        )

        let verificationContext = ModelContext(container)
        let tombstoneID = tombstone.id
        let descriptor = FetchDescriptor<ScanCollection>(
            predicate: #Predicate { $0.id == tombstoneID }
        )
        #expect(!result)
        #expect(await fence.invocationCount == 0)
        #expect(try verificationContext.fetch(descriptor).count == 1)
    }

    @Test func collectionSyncRetainsTombstoneWhenTransitionStartsInFlight() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let tombstone = ScanCollection(
            id: "collection_auth_transition_in_flight",
            name: "Removed Collection",
            isPendingDeletion: true
        )
        context.insert(tombstone)
        try context.save()

        // Dispatch is allowed under the stable source session. The second gate
        // models an Auth transition beginning while the Edge call is suspended.
        let fence = CollectionSyncFenceRecorder(gateResults: [true, false])
        let dbActor = BackgroundDatabaseActor(modelContainer: container)
        let result = await dbActor.pushCollectionsToEdge(
            accountWorkAllowed: { await fence.nextGateResult() },
            invoke: { _ in await fence.recordInvocation() }
        )

        let verificationContext = ModelContext(container)
        let tombstoneID = tombstone.id
        let descriptor = FetchDescriptor<ScanCollection>(
            predicate: #Predicate { $0.id == tombstoneID }
        )
        #expect(!result)
        #expect(await fence.invocationCount == 1)
        #expect(try verificationContext.fetch(descriptor).count == 1)
    }

    @Test func accountBoundBackgroundWorkRetiresBeforeTransportCancellation() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scanId = "background_auth_owner_\(UUID().uuidString.lowercased())"
        let ownerUserID = UUID()
        let generation = UUID()
        let scan = OfflineQueuedScan(
            id: scanId,
            scanState: .uploading,
            stagedR2Keys: ["staging/\(ownerUserID.uuidString.lowercased())/queued.webp"]
        )
        let job = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .running
        )
        context.insert(scan)
        context.insert(job)
        try context.save()

        let ownership = BackgroundAccountWorkOwnership(
            ownerUserID: ownerUserID,
            generation: generation,
            phase: .upload
        )
        let actor = BackgroundDatabaseActor(modelContainer: container)
        #expect(
            await actor.activateBackgroundAccountWork(
                scanId: scanId,
                ownership: ownership
            )
        )
        #expect(
            await actor.backgroundAccountWorkIsCurrent(
                scanId: scanId,
                ownership: ownership
            )
        )
        #expect(
            await actor.backgroundAccountWorkCandidates(
                ownerUserID: ownerUserID
            ) == [
                BackgroundAccountWorkCandidate(
                    scanId: scanId,
                    ownership: ownership
                )
            ]
        )
        #expect(
            await actor.retireBackgroundAccountWork(
                scanId: scanId,
                expectedOwnerUserID: ownerUserID,
                expectedGeneration: UUID(),
                phase: .upload
            )
        )
        #expect(
            await actor.backgroundAccountWorkIsCurrent(
                scanId: scanId,
                ownership: ownership
            )
        )
        #expect(
            await actor.retireBackgroundAccountWork(
                scanId: scanId,
                expectedOwnerUserID: ownerUserID,
                expectedGeneration: generation,
                phase: .upload
            )
        )

        let verificationContext = ModelContext(container)
        var scanDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        scanDescriptor.fetchLimit = 1
        let persistedScan = try #require(
            verificationContext.fetch(scanDescriptor).first
        )
        let expectedJobId = OfflineQueueManager.scanIngestionJobId(
            scanId: scanId
        )
        var jobDescriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == expectedJobId }
        )
        jobDescriptor.fetchLimit = 1
        let persistedJob = try #require(
            verificationContext.fetch(jobDescriptor).first
        )
        #expect(persistedScan.queueState == .pending)
        #expect(persistedScan.stagedR2Keys == nil)
        #expect(persistedJob.status == .pending)
        #expect(
            OfflineScanJobMetadataContract.backgroundAccountWork(
                in: persistedJob.metadataJSON
            ) == nil
        )
        #expect(
            await actor.backgroundAccountWorkCandidates(
                ownerUserID: ownerUserID
            )?.isEmpty == true
        )
        #expect(
            !(await actor.backgroundAccountWorkIsCurrent(
                scanId: scanId,
                ownership: ownership
            ))
        )
    }

    @Test func rejectedInferenceDispatchDurablyRequeuesBeforeCancellation() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scanId = "rejected_inference_dispatch_\(UUID().uuidString.lowercased())"
        let ownerUserID = UUID()
        let generation = UUID()
        let scan = OfflineQueuedScan(
            id: scanId,
            scanState: .inferencing,
            stagedR2Keys: [
                "staging/\(ownerUserID.uuidString.lowercased())/queued.webp"
            ]
        )
        let job = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .running,
            metadataJSON: InferenceGenerationMetadataContract.json(
                for: generation
            )
        )
        context.insert(scan)
        context.insert(job)
        try context.save()

        let ownership = BackgroundAccountWorkOwnership(
            ownerUserID: ownerUserID,
            generation: generation,
            phase: .inference
        )
        let actor = BackgroundDatabaseActor(modelContainer: container)
        #expect(
            await actor.activateBackgroundAccountWork(
                scanId: scanId,
                ownership: ownership
            )
        )
        #expect(
            await actor.backgroundAccountWorkCandidates(
                ownerUserID: ownerUserID
            ) == [
                BackgroundAccountWorkCandidate(
                    scanId: scanId,
                    ownership: ownership
                )
            ]
        )
        #expect(
            await actor.retireBackgroundAccountWork(
                scanId: scanId,
                expectedOwnerUserID: ownerUserID,
                expectedGeneration: generation,
                phase: .inference
            )
        )

        let verificationContext = ModelContext(container)
        var scanDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        scanDescriptor.fetchLimit = 1
        let persistedScan = try #require(
            verificationContext.fetch(scanDescriptor).first
        )
        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        var jobDescriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        jobDescriptor.fetchLimit = 1
        let persistedJob = try #require(
            verificationContext.fetch(jobDescriptor).first
        )
        #expect(persistedScan.queueState == .pending)
        #expect(persistedScan.stagedR2Keys == nil)
        #expect(persistedJob.status == .pending)
        #expect(
            OfflineScanJobMetadataContract.backgroundAccountWork(
                in: persistedJob.metadataJSON
            ) == nil
        )
        #expect(
            await actor.backgroundAccountWorkCandidates(
                ownerUserID: ownerUserID
            )?.isEmpty == true
        )
        #expect(
            !(await actor.backgroundAccountWorkIsCurrent(
                scanId: scanId,
                ownership: ownership
            ))
        )
    }

    @Test func exactUploadOwnerRetiresStagedCallbackRace() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scanId = "staged_upload_retirement_\(UUID().uuidString.lowercased())"
        let ownerUserID = UUID()
        let generation = UUID()
        let sourceObjectKey =
            "staging/\(ownerUserID.uuidString.lowercased())/queued.webp"
        let scan = OfflineQueuedScan(
            id: scanId,
            scanState: .uploading,
            stagedR2Keys: [sourceObjectKey]
        )
        let job = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .running
        )
        context.insert(scan)
        context.insert(job)
        try context.save()

        let ownership = BackgroundAccountWorkOwnership(
            ownerUserID: ownerUserID,
            generation: generation,
            phase: .upload
        )
        let actor = BackgroundDatabaseActor(modelContainer: container)
        #expect(
            await actor.activateBackgroundAccountWork(
                scanId: scanId,
                ownership: ownership
            )
        )

        // Model the upload callback winning the actor immediately before the
        // Auth-transition quiescer. Its exact durable owner must still reset
        // the advanced row instead of merely clearing the ownership marker.
        #expect(
            await actor.markScanAsStaged(
                scanId: scanId,
                r2Keys: [sourceObjectKey]
            ) == .staged
        )

        #expect(
            await actor.retireBackgroundAccountWork(
                scanId: scanId,
                expectedOwnerUserID: ownerUserID,
                expectedGeneration: generation,
                phase: .upload
            )
        )

        let verificationContext = ModelContext(container)
        var verificationDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        verificationDescriptor.fetchLimit = 1
        let persistedScan = try #require(
            verificationContext.fetch(verificationDescriptor).first
        )
        #expect(persistedScan.queueState == .pending)
        #expect(persistedScan.stagedR2Keys == nil)
        #expect(
            await actor.backgroundAccountWorkCandidates(
                ownerUserID: ownerUserID
            )?.isEmpty == true
        )
    }

    @Test func staleSpeciesMetadataCannotOverwriteReplacementIdentification() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scanId = "metadata_generation_fence_\(UUID().uuidString.lowercased())"
        context.insert(LocalScanRecord(
            id: scanId,
            speciesId: "replacement-species",
            scientificName: "Danaus plexippus",
            commonName: "Monarch",
            isBiological: true,
            isLiveCapture: false
        ))
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let didApplyStaleWikipedia = await actor.updateScanWithWikipedia(
            scanId: scanId,
            extract: "Stale metadata",
            url: "https://example.invalid/stale",
            imageUrl: nil,
            expectedScientificName: "Papilio glaucus"
        )
        #expect(!didApplyStaleWikipedia)
        await actor.updateScanWithEnrichment(
            scanId: scanId,
            habitatDescription: "Stale habitat",
            gbifTaxonKey: 999,
            similarSpeciesJsonData: nil,
            taxonomy: nil,
            expectedScientificName: "Papilio glaucus"
        )

        let verificationContext = ModelContext(container)
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        let persisted = try #require(
            verificationContext.fetch(descriptor).first
        )
        #expect(persisted.wikipediaOverview == nil)
        #expect(persisted.wikipediaUrl == nil)
        #expect(persisted.habitatDescription == nil)
        #expect(persisted.gbifTaxonKey == nil)
    }

    @Test func wikipediaUpdateUsesEffectiveIdentificationAndReportsChanges() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scanId = "reference_fallback_\(UUID().uuidString.lowercased())"
        let record = LocalScanRecord(
            id: scanId,
            speciesId: "original-species",
            scientificName: "Lagerstroemia speciosa",
            commonName: "Queen's crape myrtle",
            isBiological: true,
            isLiveCapture: false
        )
        record.userIdentificationOverride = "Lagerstroemia indica"
        context.insert(record)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let rejectedOriginal = await actor.updateScanWithWikipedia(
            scanId: scanId,
            extract: nil,
            url: nil,
            imageUrl: "https://images.example.org/stale.webp",
            expectedScientificName: "Lagerstroemia speciosa"
        )
        #expect(!rejectedOriginal)

        let appliedOverride = await actor.updateScanWithWikipedia(
            scanId: scanId,
            extract: nil,
            url: nil,
            imageUrl: "https://images.example.org/reference.webp",
            expectedScientificName: "Lagerstroemia indica"
        )
        #expect(appliedOverride)

        let repeatedNoOp = await actor.updateScanWithWikipedia(
            scanId: scanId,
            extract: nil,
            url: nil,
            imageUrl: "https://images.example.org/reference.webp",
            expectedScientificName: "Lagerstroemia indica"
        )
        #expect(!repeatedNoOp)

        let verificationContext = ModelContext(container)
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        let persisted = try #require(
            verificationContext.fetch(descriptor).first
        )
        #expect(
            persisted.referenceImageUrl
                == "https://images.example.org/reference.webp"
        )
    }

    @Test func testClearAllLocalLookalikesCacheClearsBiologicalRecordsAcrossBatchesOnly() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let actor = BackgroundDatabaseActor(modelContainer: container)
        let lookalikeBlob = Data(#"[{"scientificName":"Danaus gilippus"}]"#.utf8)

        for index in 0..<250 {
            context.insert(
                LocalScanRecord(
                    id: "lookalike_batch_\(index)",
                    speciesId: "species_\(index)",
                    scientificName: "Species \(index)",
                    commonName: "Species \(index)",
                    timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                    isBiological: true,
                    similarSpecies: ["Danaus gilippus"],
                    lookalikesData: lookalikeBlob
                )
            )
        }

        context.insert(
            LocalScanRecord(
                id: "lookalike_nonbiological_control",
                speciesId: "nonbio",
                scientificName: "Concrete",
                commonName: "Concrete",
                isBiological: false,
                similarSpecies: ["Should remain"],
                lookalikesData: lookalikeBlob
            )
        )
        try context.save()

        await actor.clearAllLocalLookalikesCache()

        let verificationContext = ModelContext(container)
        let biologicalDescriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.isBiological == true }
        )
        let biologicalRecords = try verificationContext.fetch(biologicalDescriptor)
        #expect(biologicalRecords.count == 250)
        #expect(biologicalRecords.allSatisfy { $0.lookalikesData == nil })
        #expect(biologicalRecords.allSatisfy { $0.similarSpecies == nil })

        let controlID = "lookalike_nonbiological_control"
        let controlDescriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == controlID }
        )
        let control = try #require(verificationContext.fetch(controlDescriptor).first)
        #expect(control.lookalikesData == lookalikeBlob)
        #expect(control.similarSpecies == ["Should remain"])
    }

    @Test func testProcessAndCleanupOfflineScanPreservesOriginalTimestamp() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let actor = BackgroundDatabaseActor(modelContainer: container)

        let originalTimestamp = Date(timeIntervalSince1970: 1_712_345_678)
        let resultData = Data(
            """
            {
              "success": true,
              "data": {
                "scan_id": "offline_scan_001",
                "is_biological_subject": true,
                "is_live_capture": true,
                "ecology_type": "wild",
                "is_invasive": false,
                "scientific_name": "Danaus plexippus",
                "common_name": "Monarch Butterfly",
                "confidence_score": 0.98,
                "taxonomy": {
                  "kingdom": "Animalia",
                  "class": "Insecta",
                  "order": "Lepidoptera",
                  "family": "Nymphalidae",
                  "genus": "Danaus"
                },
                "insight_data": {
                  "hazard_type": "none",
                  "ai_reasoning": "Migratory butterfly with orange and black wings."
                }
              }
            }
            """.utf8
        )

        let processingResult = await actor.processAndCleanupOfflineScan(
            resultData: resultData,
            originalImagePaths: ["offline_monarch.webp"],
            scanId: "offline_queue_001",
            originalTimestamp: originalTimestamp
        )

        #expect(processingResult.finalScanId == "offline_scan_001")

        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == "offline_scan_001" })
        let record = try #require(context.fetch(descriptor).first)
        #expect(record.timestamp == originalTimestamp, "Offline scan timestamp must preserve capture chronology")
        #expect(record.captureDate == originalTimestamp, "captureDate must remain the original capture time")
    }

    @Test func testOfflineFinalizationRechecksExistingRecordAfterWaitingForSameScanLock() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let actor = BackgroundDatabaseActor(modelContainer: container)
        let scanId = "finalization_race_scan_001"

        let resultData = Data(
            """
            {
              "success": true,
              "data": {
                "scan_id": "\(scanId)",
                "is_biological_subject": true,
                "is_live_capture": true,
                "ecology_type": "wild",
                "is_invasive": false,
                "scientific_name": "Danaus plexippus",
                "common_name": "Monarch Butterfly",
                "confidence_score": 0.98,
                "insight_data": {
                  "hazard_type": "none",
                  "ai_reasoning": "Migratory butterfly with orange and black wings."
                }
              }
            }
            """.utf8
        )

        await ScanFinalizationCoordinator.shared.acquire(scanId: scanId)
        let offlineTask = Task {
            await actor.processAndCleanupOfflineScan(
                resultData: resultData,
                originalImagePaths: ["offline_race.webp"],
                scanId: scanId,
                originalTimestamp: Date(timeIntervalSince1970: 1_700_000_000)
            )
        }

        context.insert(
            LocalScanRecord(
                id: scanId,
                speciesId: "live-species-id",
                scientificName: "Danaus plexippus",
                commonName: "Live Monarch",
                capturedMediaJSON: String(
                    data: try JSONEncoder().encode([SerializedMediaItem.image("live_race.webp")]),
                    encoding: .utf8
                ),
                coverImagePath: "live_race.webp",
                isBiological: true,
                isLiveCapture: true
            )
        )
        try context.save()

        await ScanFinalizationCoordinator.shared.release(scanId: scanId)
        _ = await offlineTask.value

        let verificationContext = ModelContext(container)
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        let records = try verificationContext.fetch(descriptor)
        let record = try #require(records.first)

        #expect(records.count == 1, "Offline finalization must not insert a duplicate after another path saves the same scan id")
        #expect(record.commonName == "Live Monarch")
        #expect(record.coverImagePath == "live_race.webp")
    }

    @Test func generatedBackgroundResultRejectsWrongScanId() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let actor = BackgroundDatabaseActor(modelContainer: container)
        let scanId =
            "background-result-owner-\(UUID().uuidString.lowercased())"
        let generation = UUID()

        context.insert(OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            scanState: .inferencing
        ))
        context.insert(OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .running,
            metadataJSON:
                InferenceGenerationMetadataContract.json(for: generation)
        ))
        try context.save()

        let resultData = Data(
            """
            {
              "success": true,
              "data": {
                "scan_id": "stale-background-result",
                "is_biological_subject": true,
                "scientific_name": "Resultus stale",
                "common_name": "Stale Result",
                "confidence_score": 0.95
              }
            }
            """.utf8
        )

        let result = await actor.processAndCleanupOfflineScan(
            resultData: resultData,
            originalImagePaths: [],
            scanId: scanId,
            originalTimestamp: Date(),
            expectedGeneration: generation
        )

        #expect(!result.wasCleaned)
        let recordDescriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate {
                $0.id == "stale-background-result"
            }
        )
        #expect(try context.fetch(recordDescriptor).isEmpty)
    }

    @Test func generatedBackgroundResultRejectsMalformedSuccessBody() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let actor = BackgroundDatabaseActor(modelContainer: container)
        let scanId =
            "background-malformed-response-\(UUID().uuidString.lowercased())"
        let generation = UUID()

        context.insert(OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            scanState: .inferencing
        ))
        context.insert(OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .running,
            metadataJSON:
                InferenceGenerationMetadataContract.json(for: generation)
        ))
        try context.save()

        for invalidResultData in [
            Data(#"{"success":true,"data":"truncated"}"#.utf8),
            Data(
                #"{"success":false,"data":{"scan_id":"\#(scanId)","confidence_score":0}}"#.utf8
            ),
            Data(
                #"{"success":true,"data":{"scan_id":"\#(scanId)"}}"#.utf8
            )
        ] {
            let result = await actor.processAndCleanupOfflineScan(
                resultData: invalidResultData,
                originalImagePaths: [],
                scanId: scanId,
                originalTimestamp: Date(),
                expectedGeneration: generation
            )
            #expect(!result.wasCleaned)
        }
        let queueDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        #expect(try context.fetch(queueDescriptor).count == 1)
        #expect(try context.fetch(FetchDescriptor<LocalScanRecord>()).isEmpty)
    }

    @Test func generatedConfidenceZeroBackgroundResultIsTerminal() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let actor = BackgroundDatabaseActor(modelContainer: container)
        let scanId =
            "background-confidence-zero-\(UUID().uuidString.lowercased())"
        let generation = UUID()
        let sourceImageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(scanId).webp")
        try Data(repeating: 0x55, count: 128).write(to: sourceImageURL)
        defer { try? FileManager.default.removeItem(at: sourceImageURL) }

        context.insert(OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            scanState: .inferencing
        ))
        context.insert(OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .running,
            metadataJSON:
                InferenceGenerationMetadataContract.json(for: generation)
        ))
        try context.save()

        let result = await actor.processAndCleanupOfflineScan(
            resultData: Data(
                """
                {
                  "success": true,
                  "data": {
                    "scan_id": "\(scanId)",
                    "is_biological_subject": false,
                    "common_name": "No identification",
                    "confidence_score": 0
                  }
                }
                """.utf8
            ),
            originalImagePaths: [sourceImageURL.path],
            scanId: scanId,
            originalTimestamp: Date(),
            expectedGeneration: generation
        )

        #expect(result.wasCleaned)
        #expect(result.finalScanId == nil)
        #expect(try context.fetch(FetchDescriptor<LocalScanRecord>()).isEmpty)
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(FileManager.default.fileExists(atPath: sourceImageURL.path))
    }

    @Test func testSaveLiveScanRecordReplacesCollisionPreservingFieldNotesAndSpeciesId() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let actor = BackgroundDatabaseActor(modelContainer: container)
        let scanId = "live_collision_scan_001"

        context.insert(
            LocalScanRecord(
                id: scanId,
                speciesId: "stable-species-id",
                scientificName: "Cardinalis cardinalis",
                commonName: "Older Cardinal",
                timestamp: Date(timeIntervalSince1970: 100),
                capturedMediaJSON: String(
                    data: try JSONEncoder().encode([SerializedMediaItem.image("old_capture.webp")]),
                    encoding: .utf8
                ),
                coverImagePath: "old_capture.webp",
                isBiological: true,
                isLiveCapture: true,
                fieldNotes: "  feeder call notes  "
            )
        )
        try context.save()

        let mappedData = SpeciesData(
            scanId: scanId,
            commonName: "Northern Cardinal",
            scientificName: "Cardinalis cardinalis",
            insightData: InsightData(aiReasoning: "Fresh visual result.", hazardType: "none"),
            confidenceScore: 0.96,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )

        let persistenceResult = await actor.saveLiveScanRecord(
            mappedData: mappedData,
            localImagePaths: ["new_capture.webp"]
        )

        let verificationContext = ModelContext(container)
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        let records = try verificationContext.fetch(descriptor)
        let record = try #require(records.first)

        #expect(persistenceResult.wasSaved)
        #expect(
            persistenceResult.isNewDiscovery == false,
            "Replacing a same-species collision must not count as a new discovery"
        )
        #expect(records.count == 1, "Collision replacement must leave exactly one LocalScanRecord for the scan ID")
        #expect(record.speciesId == "stable-species-id", "Shared species lookup must preserve the existing species UUID")
        #expect(record.commonName == "Northern Cardinal")
        #expect(record.fieldNotes == "feeder call notes", "Collision replacement must preserve trimmed user field notes")
        #expect(record.coverImagePath == "new_capture.webp")
    }

    @Test func testSaveLiveScanRecordKeepsExistingDocumentsAudio() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let actor = BackgroundDatabaseActor(modelContainer: container)

        let audioFilename = "live_audio_\(UUID().uuidString).wav"
        let audioURL = URL.documentsDirectory.appendingPathComponent(audioFilename)
        try Data(repeating: 0x33, count: 128).write(to: audioURL)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
        }

        let mappedData = SpeciesData(
            scanId: "live_audio_scan_001",
            commonName: "Northern Cardinal",
            scientificName: "Cardinalis cardinalis",
            insightData: InsightData(aiReasoning: "Clear cardinal vocalization.", hazardType: "none"),
            confidenceScore: 0.94,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )

        _ = await actor.saveLiveScanRecord(
            mappedData: mappedData,
            localImagePaths: ["primary_capture.webp"],
            audioFilePaths: [audioFilename]
        )

        let descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == "live_audio_scan_001" }
        )
        let record = try #require(context.fetch(descriptor).first)
        let capturedMediaJSON = try #require(record.capturedMediaJSON)
        let items = try #require(MediaJSONParser.serializedItems(jsonString: capturedMediaJSON))

        #expect(items.contains(where: {
            if case .audio(let path) = $0 { return path == audioFilename }
            return false
        }), "Live saved scans must retain their already-persisted audio filename in capturedMediaJSON")
        #expect(record.capturedMediaEntries?.count == items.count)
        #expect(record.serializedCapturedMediaItems == items)
        #expect(FileManager.default.fileExists(atPath: audioURL.path) == true, "Audio already stored in Documents must not be deleted during saveLiveScanRecord")
    }

    @Test func testSaveLiveScanRecordPreservesAudioBeforeImageTimeline() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let actor = BackgroundDatabaseActor(modelContainer: container)

        let audioFilename = "ordered_live_audio_\(UUID().uuidString).wav"
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent(audioFilename)
        try Data(repeating: 0x44, count: 128).write(to: audioURL)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(audioFilename))
        }

        let mappedData = SpeciesData(
            scanId: "live_ordered_scan_001",
            commonName: "American Robin",
            scientificName: "Turdus migratorius",
            insightData: InsightData(aiReasoning: "Songbird call with matching plumage context.", hazardType: "none"),
            confidenceScore: 0.93,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )

        _ = await actor.saveLiveScanRecord(
            mappedData: mappedData,
            localImagePaths: ["ordered_capture.webp"],
            audioFilePaths: [audioFilename],
            mediaTimeline: [.audio(audioFilename), .image(index: 0)]
        )

        let descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == "live_ordered_scan_001" }
        )
        let record = try #require(context.fetch(descriptor).first)
        let capturedMediaJSON = try #require(record.capturedMediaJSON)
        let items = try #require(MediaJSONParser.serializedItems(jsonString: capturedMediaJSON))

        #expect(items.count == 2)
        #expect(record.capturedMediaEntries?.count == items.count)
        #expect(record.serializedCapturedMediaItems == items)

        if case .audio(let reference) = items[0] {
            #expect(reference.serializedPath.hasSuffix(".wav"))
            #expect(
                FileManager.default.fileExists(
                    atPath: URL.documentsDirectory.appendingPathComponent(reference.serializedPath).path
                )
            )
            try? FileManager.default.removeItem(
                at: URL.documentsDirectory.appendingPathComponent(reference.serializedPath)
            )
        } else {
            Issue.record("Live save must preserve the audio-first timeline order")
        }

        if case .image(let reference) = items[1] {
            #expect(reference == "ordered_capture.webp")
        } else {
            Issue.record("Live save must preserve the image second in the timeline")
        }
    }

    @Test func testSaveNonVisualRecordPreservesMultipleDescriptionsInOrder() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let actor = BackgroundDatabaseActor(modelContainer: container)

        let firstContext = ObservationContext(freeText: "Small bird at the waterline")
        let secondContext = ObservationContext(freeText: "Repeated sharp chip calls")
        let firstContextJSON = try #require(
            String(data: JSONEncoder().encode(firstContext), encoding: .utf8)
        )
        let secondContextJSON = try #require(
            String(data: JSONEncoder().encode(secondContext), encoding: .utf8)
        )

        let mappedData = SpeciesData(
            scanId: "describe_ordered_scan_001",
            commonName: "Spotted Sandpiper",
            scientificName: "Actitis macularius",
            insightData: InsightData(aiReasoning: "The repeated shoreline behavior and call match a sandpiper.", hazardType: "none"),
            confidenceScore: 0.91,
            isBiological: true,
            isLiveCapture: false,
            isInvasive: false,
            ecologyType: "wild"
        )

        _ = await actor.saveNonVisualRecord(
            mappedData: mappedData,
            observationContextsJSON: [firstContextJSON, secondContextJSON],
            mediaTimeline: [.description(firstContext), .description(secondContext)]
        )

        let descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == "describe_ordered_scan_001" }
        )
        let record = try #require(context.fetch(descriptor).first)
        let capturedMediaJSON = try #require(record.capturedMediaJSON)
        let items = try #require(MediaJSONParser.serializedItems(jsonString: capturedMediaJSON))

        #expect(items.count == 2)

        if case .description(let context) = items[0] {
            #expect(context.freeText == firstContext.freeText)
        } else {
            Issue.record("Describe save must preserve the first staged description")
        }

        if case .description(let context) = items[1] {
            #expect(context.freeText == secondContext.freeText)
        } else {
            Issue.record("Describe save must preserve the second staged description")
        }
    }

    @Test func testSaveNonVisualRecordSupportsAllowedCombinationMatrix() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let actor = BackgroundDatabaseActor(modelContainer: container)

        let loneDescription = ObservationContext(freeText: "single description")
        let pairedDescription = ObservationContext(freeText: "paired description")

        struct Scenario {
            let scanId: String
            let commonName: String
            let scientificName: String
            let audioFilePaths: [String]
            let observationContexts: [ObservationContext]
            let mediaTimeline: [CaptureSubmissionMediaItem]
            let expected: [ExpectedSerializedMedia]
        }

        let audioOnly = try makeTempAudioFilename(prefix: "audio_only")
        let firstAudio = try makeTempAudioFilename(prefix: "audio_pair_1")
        let secondAudio = try makeTempAudioFilename(prefix: "audio_pair_2")
        let audioWithDescription = try makeTempAudioFilename(prefix: "audio_and_description")

        let scenarios: [Scenario] = [
            .init(
                scanId: "nonvisual_audio_only",
                commonName: "Audio Only",
                scientificName: "Audio only",
                audioFilePaths: [audioOnly],
                observationContexts: [],
                mediaTimeline: [.audio(audioOnly)],
                expected: [.audio]
            ),
            .init(
                scanId: "nonvisual_audio_audio",
                commonName: "Audio Pair",
                scientificName: "Audio pair",
                audioFilePaths: [firstAudio, secondAudio],
                observationContexts: [],
                mediaTimeline: [.audio(firstAudio), .audio(secondAudio)],
                expected: [.audio, .audio]
            ),
            .init(
                scanId: "nonvisual_audio_description",
                commonName: "Audio With Description",
                scientificName: "Audio description",
                audioFilePaths: [audioWithDescription],
                observationContexts: [pairedDescription],
                mediaTimeline: [.audio(audioWithDescription), .description(pairedDescription)],
                expected: [.audio, .description(pairedDescription.freeText)]
            ),
            .init(
                scanId: "nonvisual_description_only",
                commonName: "Description Only",
                scientificName: "Description only",
                audioFilePaths: [],
                observationContexts: [loneDescription],
                mediaTimeline: [.description(loneDescription)],
                expected: [.description(loneDescription.freeText)]
            ),
            .init(
                scanId: "nonvisual_description_description",
                commonName: "Description Pair",
                scientificName: "Description pair",
                audioFilePaths: [],
                observationContexts: [loneDescription, pairedDescription],
                mediaTimeline: [.description(loneDescription), .description(pairedDescription)],
                expected: [.description(loneDescription.freeText), .description(pairedDescription.freeText)]
            )
        ]

        for scenario in scenarios {
            let observationContextsJSON = try scenario.observationContexts.map {
                try #require(
                    String(
                        bytes: try JSONEncoder().encode($0),
                        encoding: .utf8
                    )
                )
            }

            let mappedData = SpeciesData(
                scanId: scenario.scanId,
                commonName: scenario.commonName,
                scientificName: scenario.scientificName,
                insightData: InsightData(aiReasoning: "matrix", hazardType: "none"),
                confidenceScore: 0.91,
                isBiological: true,
                isLiveCapture: false,
                isInvasive: false,
                ecologyType: "wild"
            )

            _ = await actor.saveNonVisualRecord(
                mappedData: mappedData,
                observationContextsJSON: observationContextsJSON,
                audioFilePaths: scenario.audioFilePaths.isEmpty ? nil : scenario.audioFilePaths,
                mediaTimeline: scenario.mediaTimeline
            )

            let scanId = scenario.scanId
            let descriptor = FetchDescriptor<LocalScanRecord>(
                predicate: #Predicate { $0.id == scanId }
            )
            let record = try #require(context.fetch(descriptor).first)
            let capturedMediaJSON = try #require(record.capturedMediaJSON)
            let items = try #require(MediaJSONParser.serializedItems(jsonString: capturedMediaJSON))

            assertSerializedItems(items, match: scenario.expected)
            let audioSourceIndices = items.compactMap { item -> Int? in
                guard case .audio(let reference) = item else { return nil }
                return reference.sourceIndex
            }
            let expectedAudioCount = scenario.expected.reduce(into: 0) { count, item in
                if case .audio = item { count += 1 }
            }
            #expect(audioSourceIndices == Array(0..<expectedAudioCount))
            cleanupSerializedItems(items)
        }
    }

    @Test func testSaveLiveScanRecordSupportsAllowedVisualCombinationMatrix() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let actor = BackgroundDatabaseActor(modelContainer: container)

        let stagedDescription = ObservationContext(freeText: "image companion description")
        let descriptionJSON = try #require(
            String(data: JSONEncoder().encode(stagedDescription), encoding: .utf8)
        )
        let stagedAudio = try makeTempAudioFilename(prefix: "image_audio")

        struct Scenario {
            let scanId: String
            let commonName: String
            let scientificName: String
            let localImagePaths: [String]
            let observationContextsJSON: [String]?
            let audioFilePaths: [String]?
            let mediaTimeline: [CaptureSubmissionMediaItem]
            let expected: [ExpectedSerializedMedia]
        }

        let scenarios: [Scenario] = [
            .init(
                scanId: "visual_image_only",
                commonName: "Image Only",
                scientificName: "Image only",
                localImagePaths: ["image_only.webp"],
                observationContextsJSON: nil,
                audioFilePaths: nil,
                mediaTimeline: [.image(index: 0)],
                expected: [.image("image_only.webp")]
            ),
            .init(
                scanId: "visual_image_image",
                commonName: "Image Pair",
                scientificName: "Image pair",
                localImagePaths: ["image_one.webp", "image_two.webp"],
                observationContextsJSON: nil,
                audioFilePaths: nil,
                mediaTimeline: [.image(index: 0), .image(index: 1)],
                expected: [.image("image_one.webp"), .image("image_two.webp")]
            ),
            .init(
                scanId: "visual_description_image",
                commonName: "Description Image",
                scientificName: "Description image",
                localImagePaths: ["description_image.webp"],
                observationContextsJSON: [descriptionJSON],
                audioFilePaths: nil,
                mediaTimeline: [.description(stagedDescription), .image(index: 0)],
                expected: [.description(stagedDescription.freeText), .image("description_image.webp")]
            ),
            .init(
                scanId: "visual_audio_image",
                commonName: "Audio Image",
                scientificName: "Audio image",
                localImagePaths: ["audio_image.webp"],
                observationContextsJSON: nil,
                audioFilePaths: [stagedAudio],
                mediaTimeline: [.audio(stagedAudio), .image(index: 0)],
                expected: [.audio, .image("audio_image.webp")]
            )
        ]

        for scenario in scenarios {
            let mappedData = SpeciesData(
                scanId: scenario.scanId,
                commonName: scenario.commonName,
                scientificName: scenario.scientificName,
                insightData: InsightData(aiReasoning: "matrix", hazardType: "none"),
                confidenceScore: 0.93,
                isBiological: true,
                isLiveCapture: true,
                isInvasive: false,
                ecologyType: "wild"
            )

            _ = await actor.saveLiveScanRecord(
                mappedData: mappedData,
                localImagePaths: scenario.localImagePaths,
                observationContextsJSON: scenario.observationContextsJSON,
                audioFilePaths: scenario.audioFilePaths,
                mediaTimeline: scenario.mediaTimeline
            )

            let scanId = scenario.scanId
            let descriptor = FetchDescriptor<LocalScanRecord>(
                predicate: #Predicate { $0.id == scanId }
            )
            let record = try #require(context.fetch(descriptor).first)
            let capturedMediaJSON = try #require(record.capturedMediaJSON)
            let items = try #require(MediaJSONParser.serializedItems(jsonString: capturedMediaJSON))

            assertSerializedItems(items, match: scenario.expected)
            cleanupSerializedItems(items)
        }
    }

    @Test func testBulkDeleteNonBiologicalScansCommitsBeforeReturningPaths() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scan = LocalScanRecord(
            id: "nonbio_delete_001",
            speciesId: "nonbio_species",
            scientificName: "Concrete slab",
            commonName: "Concrete slab",
            timestamp: Date(),
            isBiological: false,
            isLiveCapture: false,
            ecologyType: "unknown"
        )
        context.insert(scan)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let deletedPaths = try await actor.bulkDeleteNonBiologicalScans(payloads: [
            .init(id: scan.id, imagePaths: ["nonbio_001.webp", "https://merian.app/cloud.webp"])
        ])

        let recordDescriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == "nonbio_delete_001" })
        let taskDescriptor = FetchDescriptor<PendingCloudDeletionTask>(predicate: #Predicate { $0.scanId == "nonbio_delete_001" })
        #expect(try context.fetch(recordDescriptor).isEmpty, "Record should be deleted once the actor returns success")
        #expect(try context.fetch(taskDescriptor).count == 1, "Cloud deletion task must be committed atomically with the delete")
        #expect(deletedPaths == ["nonbio_001.webp"], "Only local file paths should be returned for post-commit deletion")
    }

    @Test func testBulkDeleteNonBiologicalScansReusesExistingPendingCloudDeletionTask() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scanId = "nonbio_conflict_001"

        let scan = LocalScanRecord(
            id: scanId,
            speciesId: "nonbio_species_conflict",
            scientificName: "Parking cone",
            commonName: "Parking cone",
            timestamp: Date(),
            isBiological: false,
            isLiveCapture: false,
            ecologyType: "unknown"
        )
        context.insert(scan)
        context.insert(PendingCloudDeletionTask(scanId: scanId))
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let deletedPaths = try await actor.bulkDeleteNonBiologicalScans(payloads: [
            .init(id: scanId, imagePaths: ["should_not_delete.webp"])
        ])

        let recordDescriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        let taskDescriptor = FetchDescriptor<PendingCloudDeletionTask>(predicate: #Predicate { $0.scanId == scanId })

        #expect(try context.fetch(recordDescriptor).isEmpty, "Delete should still succeed when a cloud deletion task already exists")
        #expect(try context.fetch(taskDescriptor).count == 1, "Re-queueing must remain idempotent and preserve a single cloud deletion task")
        #expect(deletedPaths == ["should_not_delete.webp"], "Committed local file paths should still be returned for cleanup")
    }

    @Test func testPurgeExpiredNonBiologicalScansDeletesOnlyExpiredNonBioRecords() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let cutoffDate = referenceDate.addingTimeInterval(TimeInterval(-MerianConfig.nonBiologicalRetentionDays * 24 * 60 * 60))
        let mediaJSON = try #require(CapturedMediaSnapshot(items: [
            .image(.documents("expired_nonbio.webp")),
            .audio(.documents("expired_nonbio.wav")),
            .image(.remoteURL("https://merian.example/nonbio.webp"))
        ]).jsonString)

        let expiredNonBio = LocalScanRecord(
            id: "expired_nonbio",
            speciesId: "nonbio_species",
            scientificName: "Notebook",
            commonName: "Notebook",
            timestamp: cutoffDate.addingTimeInterval(-60),
            capturedMediaJSON: mediaJSON,
            isBiological: false,
            isLiveCapture: false,
            ecologyType: "unknown"
        )
        let freshNonBio = LocalScanRecord(
            id: "fresh_nonbio",
            speciesId: "nonbio_species_fresh",
            scientificName: "Desk",
            commonName: "Desk",
            timestamp: cutoffDate.addingTimeInterval(60),
            isBiological: false,
            isLiveCapture: false,
            ecologyType: "unknown"
        )
        let expiredBiological = LocalScanRecord(
            id: "expired_bio",
            speciesId: "bio_species",
            scientificName: "Quercus alba",
            commonName: "White Oak",
            timestamp: cutoffDate.addingTimeInterval(-60),
            isBiological: true,
            isLiveCapture: false,
            ecologyType: "wild"
        )
        context.insert(expiredNonBio)
        context.insert(freshNonBio)
        context.insert(expiredBiological)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let result = try await actor.purgeExpiredNonBiologicalScans(cutoffDate: cutoffDate)

        let recordDescriptor = FetchDescriptor<LocalScanRecord>()
        let remainingIds = try context.fetch(recordDescriptor).map(\.id)
        let taskDescriptor = FetchDescriptor<PendingCloudDeletionTask>(
            predicate: #Predicate { $0.scanId == "expired_nonbio" }
        )

        #expect(!remainingIds.contains("expired_nonbio"), "Expired non-biological records should be removed locally")
        #expect(remainingIds.contains("fresh_nonbio"), "Fresh non-biological records should remain")
        #expect(remainingIds.contains("expired_bio"), "Biological records should not be affected by the nonbio purge")
        #expect(try context.fetch(taskDescriptor).count == 1, "Expired local purge should queue cloud deletion idempotently")
        #expect(result.deletedRecordCount == 1, "The purge result should report deleted records even when media paths are empty")
        #expect(result.localMediaPaths == ["expired_nonbio.webp", "expired_nonbio.wav"], "Only local media paths should be returned for file cleanup")
    }

    // MARK: - updateScanWithOverride: V29 identification review persistence

    @Test func testUpdateScanWithOverrideSetsOverrideString() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let record = LocalScanRecord(
            speciesId: "override-actor-test",
            scientificName: "Procyon lotor",
            commonName: "Raccoon"
        )
        context.insert(record)
        try context.save()
        let scanId = record.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.updateScanWithOverride(
            scanId: scanId,
            override: "Procyon cancrivorus",
            confirmed: false,
            newConfirmedSpeciesId: "mock-uuid-overridden",
            userReviewState: .userOverridden
        )

        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.userIdentificationOverride == "Procyon cancrivorus", "updateScanWithOverride must persist the override name")
        #expect(fetched?.userConfirmedIdentification == false, "confirmed must be false when only override is set")
        #expect(fetched?.confirmedSpeciesId == "mock-uuid-overridden", "new confirmedSpeciesId must be persisted")
        #expect(fetched?.userReviewStateRaw == "user_overridden", "userReviewStateRaw must be 'user_overridden'")
    }

    @Test func testUpdateScanWithOverrideClearsWithNil() async throws {
        // Simulate resetting a previously-overridden scan.
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let record = LocalScanRecord(
            speciesId: "clear-override-test",
            scientificName: "Procyon cancrivorus",
            commonName: "Crab-eating Raccoon",
            userIdentificationOverride: "Procyon cancrivorus"
        )
        context.insert(record)
        try context.save()
        let scanId = record.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.updateScanWithOverride(
            scanId: scanId,
            override: nil,
            confirmed: false,
            newConfirmedSpeciesId: nil,
            userReviewState: .unreviewed
        )

        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.userIdentificationOverride == nil, "updateScanWithOverride(override: nil) must clear the override column")
        #expect(fetched?.userConfirmedIdentification == false)
        #expect(fetched?.confirmedSpeciesId == nil, "confirmedSpeciesId must be cleared on reset")
        #expect(fetched?.userReviewStateRaw == "unreviewed", "userReviewStateRaw must revert to unreviewed")
    }

    @Test func testUpdateScanWithOverrideSetsConfirmedTrue() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let record = LocalScanRecord(
            speciesId: "confirmed-actor-test",
            scientificName: "Procyon lotor",
            commonName: "Raccoon"
        )
        context.insert(record)
        try context.save()
        let scanId = record.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.updateScanWithOverride(
            scanId: scanId,
            override: nil,
            confirmed: true,
            newConfirmedSpeciesId: "mock-uuid-confirmed",
            userReviewState: .aiConfirmed
        )

        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.userConfirmedIdentification == true, "updateScanWithOverride must persist confirmed=true")
        #expect(fetched?.userIdentificationOverride == nil, "override must remain nil on a confirm-only action")
        #expect(fetched?.confirmedSpeciesId == "mock-uuid-confirmed", "confirmedSpeciesId must be explicitly persisted on confirmation")
        #expect(fetched?.userReviewStateRaw == "ai_confirmed", "userReviewStateRaw must be 'ai_confirmed'")
    }

    // MARK: - updateScanAsFlagged / updateScanAsUnflagged: V31 moderation review persistence

    // MARK: - fetchPendingScans: non-pending exclusion (V33)

    @Test func testFetchPendingScansExcludesNonPendingScans() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        // Only .pending scans should be fetched for upload dispatch.
        let pending    = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("pending.webp")]), encoding: .utf8), scanState: .pending)
        let uploading  = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("uploading.webp")]), encoding: .utf8), scanState: .uploading)
        let staged     = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("staged.webp")]), encoding: .utf8), scanState: .staged)
        let inferencing = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("inferencing.webp")]), encoding: .utf8), scanState: .inferencing)
        let failed     = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("failed.webp")]), encoding: .utf8), scanState: .failed)

        for scan in [pending, uploading, staged, inferencing, failed] {
            context.insert(scan)
        }
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let payloads = await actor.fetchPendingScans(limit: 10)

        #expect(payloads.count == 1, "fetchPendingScans must return only .pending scans")
        #expect(payloads.first?.id == pending.id, "Only the .pending scan must be returned")
    }

    @Test func pendingFetchPagesPastDelayedAndLocallyBlockedRowsWithoutStarvingRunnableWork() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let baseDate = Date().addingTimeInterval(-3_600)
        let retryAt = Date().addingTimeInterval(600)

        // More than one fetch page of older pending rows is delayed. A bounded
        // fetch followed by in-memory filtering would never see the ready row.
        for index in 0..<51 {
            context.insert(OfflineQueuedScan(
                id: String(format: "delayed-%03d", index),
                timestamp: baseDate.addingTimeInterval(Double(index)),
                scanState: .pending,
                queueNextRetryAt: retryAt
            ))
        }
        let deferred = OfflineQueuedScan(
            id: "deferred-behind-delayed-page",
            timestamp: baseDate.addingTimeInterval(52),
            scanState: .pending
        )
        let blockedVideo = OfflineQueuedScan(
            id: "video-behind-delayed-page",
            timestamp: baseDate.addingTimeInterval(53),
            capturedMediaJSON: CapturedMediaSnapshot(items: [
                .video(StoredVideoMediaReference(
                    .documents("blocked-video.mp4")
                ))
            ]).jsonString,
            scanState: .pending
        )
        // Media-less legacy rows are quarantine candidates, not runnable upload
        // work. More than the fetch limit must not let them consume the result
        // budget and hide a valid row behind them.
        for index in 0..<51 {
            context.insert(OfflineQueuedScan(
                id: String(format: "empty-%03d", index),
                timestamp: baseDate.addingTimeInterval(54 + Double(index)),
                scanState: .pending
            ))
        }
        let ready = OfflineQueuedScan(
            id: "ready-behind-delayed-page",
            timestamp: baseDate.addingTimeInterval(106),
            capturedMediaJSON: CapturedMediaSnapshot(items: [
                .image(.documents("ready-image.webp"))
            ]).jsonString,
            scanState: .pending
        )
        context.insert(deferred)
        context.insert(blockedVideo)
        context.insert(ready)
        context.insert(OfflineQueuedScan(
            id: "attention-row",
            timestamp: baseDate.addingTimeInterval(-1),
            scanState: .pending,
            queueNeedsAttention: true
        ))
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let payloads = await actor.fetchPendingScans(
            limit: 2,
            excludingScanIds: [deferred.id],
            allowsVideoUploads: false
        )
        let forcedPayloads = await actor.fetchPendingScans(
            limit: 2,
            excludingScanIds: [deferred.id],
            allowsVideoUploads: false,
            forcedVideoUploadScanIds: [blockedVideo.id]
        )

        #expect(
            payloads.filter { !$0.localUploadPaths.isEmpty }.map(\.id)
                == [ready.id]
        )
        #expect(
            forcedPayloads.filter { !$0.localUploadPaths.isEmpty }.map(\.id)
                == [blockedVideo.id, ready.id]
        )
        #expect(payloads.filter { $0.localUploadPaths.isEmpty }.count == 2)
        #expect(forcedPayloads.filter { $0.localUploadPaths.isEmpty }.count == 2)
    }

    @Test func emptyPendingQuarantineIsAtomicAndStateBound() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let emptyPending = OfflineQueuedScan(scanState: .pending)
        let mediaPending = OfflineQueuedScan(
            capturedMediaJSON: CapturedMediaSnapshot(items: [
                .image(.documents("retained-image.webp"))
            ]).jsonString,
            scanState: .pending
        )
        let advancedEmpty = OfflineQueuedScan(scanState: .staged)
        let attentionEmpty = OfflineQueuedScan(
            scanState: .pending,
            queueNeedsAttention: true
        )
        for scan in [
            emptyPending,
            mediaPending,
            advancedEmpty,
            attentionEmpty
        ] {
            context.insert(scan)
        }
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let quarantined = await actor.quarantineEmptyPendingScans(
            scanIds: [
                emptyPending.id,
                mediaPending.id,
                advancedEmpty.id,
                attentionEmpty.id
            ]
        )

        let readContext = ModelContext(container)
        let rows = try readContext.fetch(FetchDescriptor<OfflineQueuedScan>())
        let stateById = Dictionary(uniqueKeysWithValues: rows.map {
            ($0.id, ($0.queueState, $0.queueNeedsAttention))
        })
        #expect(quarantined == Set([emptyPending.id]))
        #expect(stateById[emptyPending.id]?.0 == .failed)
        #expect(stateById[emptyPending.id]?.1 == true)
        #expect(stateById[mediaPending.id]?.0 == .pending)
        #expect(stateById[advancedEmpty.id]?.0 == .staged)
        #expect(stateById[attentionEmpty.id]?.0 == .pending)
    }

    // MARK: - updateScanAsFlagged / updateScanAsUnflagged: V31 moderation review persistence

    @Test func testUpdateScanAsFlaggedSetsFlag() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let record = LocalScanRecord(
            speciesId: "flag-actor-test",
            scientificName: "Aedes aegypti",
            commonName: "Yellow Fever Mosquito",
            isFlagged: false
        )
        context.insert(record)
        try context.save()
        let scanId = record.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.updateScanAsFlagged(scanId: scanId)

        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.isFlagged == true, "updateScanAsFlagged must persist isFlagged=true")
    }

    @Test func testUpdateScanAsUnflaggedRemovesFlag() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let record = LocalScanRecord(
            speciesId: "unflag-actor-test",
            scientificName: "Aedes aegypti",
            commonName: "Yellow Fever Mosquito",
            isFlagged: true
        )
        context.insert(record)
        try context.save()
        let scanId = record.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.updateScanAsUnflagged(scanId: scanId)

        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.isFlagged == false, "updateScanAsUnflagged must persist isFlagged=false")
    }

    // MARK: - tryClaimForInference: distributed lock (V33)

    @Test func testTryClaimForInferenceSucceedsOnStagedScan() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        // A persisted deadline may remain on a staged row after a relaunch, but
        // only an elapsed deadline is runnable. Future deadlines are covered by
        // pausedScansCannotBeClaimedOrReconciled().
        let retryAt = Date().addingTimeInterval(-600)
        let generation = UUID()
        let scan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([
                    SerializedMediaItem.image("claim.webp")
                ]),
                encoding: .utf8
            ),
            scanState: .staged,
            queueNextRetryAt: retryAt
        )
        context.insert(scan)
        context.insert(OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scan.id),
            kind: .scanIngestion,
            subjectId: scan.id,
            status: .waiting,
            nextRunAt: retryAt
        ))
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let claimed = await actor.tryClaimForInference(
            scanId: scanId,
            generation: generation
        )

        #expect(
            claimed == true,
            "tryClaimForInference must claim an eligible .staged scan after its retry deadline"
        )
        let verificationContext = ModelContext(container)
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        let fetched = try verificationContext.fetch(descriptor).first
        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        var jobDescriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        jobDescriptor.fetchLimit = 1
        let fetchedJob = try verificationContext.fetch(jobDescriptor).first
        #expect(fetched?.scanStateRaw == ScanQueueState.inferencing.rawValue,
                "scan must be .inferencing after a successful claim")
        #expect(fetched?.queueNextRetryAt == nil,
                "an active inference claim must clear its scheduled-retry label")
        #expect(fetchedJob?.status == .running)
        #expect(fetchedJob?.nextRunAt == nil)
        #expect(
            fetchedJob?.metadataJSON ==
                InferenceGenerationMetadataContract.json(for: generation)
        )
    }

    @Test func testTryClaimForInferenceFailsWhenAlreadyInferencing() async throws {
        // Guards the double-pipeline race: if replayInferenceForUploadedScans and
        // processUploadCompletion both see the scan in .staged and race to claim it,
        // only one can win. The second call must return false.
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("already.webp")]), encoding: .utf8), scanState: .inferencing)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let claimed = await actor.tryClaimForInference(scanId: scanId)

        #expect(claimed == false, "tryClaimForInference must return false when scan is already .inferencing")
        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.scanStateRaw == ScanQueueState.inferencing.rawValue,
                "state must remain .inferencing — not regressed by a failed claim")
    }

    @Test func testTryClaimForInferenceFailsWhenPending() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("pending.webp")]), encoding: .utf8), scanState: .pending)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let claimed = await actor.tryClaimForInference(scanId: scanId)

        #expect(claimed == false, "tryClaimForInference must return false for non-.staged scans")
        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.scanStateRaw == ScanQueueState.pending.rawValue,
                "state must remain .pending after a failed claim")
    }

    @Test func testTryClaimForInferenceRejectsLegacyCompressedAudio() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scan = OfflineQueuedScan(
            capturedMediaJSON: MediaJSONParser.jsonString(from: [
                .audio(.documents("pre-upgrade-recording.m4a"))
            ]),
            scanState: .staged,
            stagedR2Keys: [
                "staging/owner/pre-upgrade-recording.m4a"
            ]
        )
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let claimed = await actor.tryClaimForInference(scanId: scanId)

        #expect(!claimed)
        let verificationContext = ModelContext(container)
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        let persisted = try #require(
            verificationContext.fetch(descriptor).first
        )
        #expect(persisted.queueState == .staged)
        #expect(persisted.stagedR2Keys == [
            "staging/owner/pre-upgrade-recording.m4a"
        ])
        #expect(
            await actor.legacyQueuedAudioRepairCandidateIds()
                .contains(scanId)
        )
    }

    @Test func testTryClaimForInferenceDoesNotResurrectTombstone() async throws {
        // A .failed tombstone must never enter the inference pipeline.
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("dead.webp")]), encoding: .utf8), scanState: .failed)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let claimed = await actor.tryClaimForInference(scanId: scanId)

        #expect(claimed == false, "tryClaimForInference must not resurrect a tombstoned scan")
        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.scanStateRaw == ScanQueueState.failed.rawValue,
                "tombstoned scan must remain .failed after a claim attempt")
    }

    @Test func testTryClaimForInferenceSecondCallReturnsFalse() async throws {
        // Simulate processUploadCompletion winning the claim, then replayInference trying again.
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("race.webp")]), encoding: .utf8), scanState: .staged)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let firstClaim  = await actor.tryClaimForInference(scanId: scanId)
        let secondClaim = await actor.tryClaimForInference(scanId: scanId)

        #expect(firstClaim == true, "First claim on a .staged scan must succeed")
        #expect(secondClaim == false, "Second claim on the same scan must fail — pipeline already in progress")
    }

    // MARK: - transitionScanToStaged: tombstone resurrection guard (V33)

    @Test func testTransitionScanToStagedSucceedsFromInferencing() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("retry.webp")]), encoding: .utf8), scanState: .inferencing)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.transitionScanToStaged(id: scanId)

        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.scanStateRaw == ScanQueueState.staged.rawValue,
                "transitionScanToStaged must retreat .inferencing → .staged on transient failure")
    }

    @Test func testTransitionScanToStagedRejectsOlderPersistedGeneration() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([
                    SerializedMediaItem.image("generation-race.webp")
                ]),
                encoding: .utf8
            ),
            scanState: .staged
        )
        context.insert(scan)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let firstGeneration = UUID()
        let secondGeneration = UUID()
        #expect(
            await actor.tryClaimForInference(
                scanId: scan.id,
                generation: firstGeneration
            )
        )
        #expect(
            await actor.transitionScanToStaged(
                id: scan.id,
                expectedGeneration: firstGeneration
            )
        )
        #expect(
            await actor.tryClaimForInference(
                scanId: scan.id,
                generation: secondGeneration
            )
        )

        let staleTransition = await actor.transitionScanToStaged(
            id: scan.id,
            expectedGeneration: firstGeneration
        )
        #expect(staleTransition == false)

        let verificationContext = ModelContext(container)
        let expectedScanId = scan.id
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == expectedScanId }
        )
        descriptor.fetchLimit = 1
        #expect(
            try verificationContext.fetch(descriptor).first?.scanStateRaw ==
                ScanQueueState.inferencing.rawValue
        )
    }

    @Test func testScheduleInferenceRetryRejectsOlderPersistedGeneration() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([
                    SerializedMediaItem.image("retry-generation-race.webp")
                ]),
                encoding: .utf8
            ),
            scanState: .staged
        )
        context.insert(scan)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let firstGeneration = UUID()
        let secondGeneration = UUID()
        #expect(
            await actor.tryClaimForInference(
                scanId: scan.id,
                generation: firstGeneration
            )
        )
        #expect(
            await actor.transitionScanToStaged(
                id: scan.id,
                expectedGeneration: firstGeneration
            )
        )
        #expect(
            await actor.tryClaimForInference(
                scanId: scan.id,
                generation: secondGeneration
            )
        )

        let staleAttempt = await actor.scheduleInferenceRetry(
            id: scan.id,
            expectedGeneration: firstGeneration,
            code: "stale_retry",
            message: "late callback",
            delay: 30
        )
        #expect(staleAttempt == nil)

        let currentAttempt = await actor.scheduleInferenceRetry(
            id: scan.id,
            expectedGeneration: secondGeneration,
            code: "current_retry",
            message: "current callback",
            delay: 30
        )
        #expect(currentAttempt == 1)

        let verificationContext = ModelContext(container)
        let expectedScanId = scan.id
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == expectedScanId }
        )
        descriptor.fetchLimit = 1
        let persisted = try verificationContext.fetch(descriptor).first
        #expect(persisted?.scanStateRaw == ScanQueueState.staged.rawValue)
        #expect(persisted?.queueAttemptCount == 1)
        #expect(persisted?.queueLastErrorCode == "current_retry")
    }

    @Test func testPersistenceRetryRestagesLocalMediaInsteadOfDeadObjectKeys() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let staleKey = "staging/owner/queued.webp"
        let scan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([
                    SerializedMediaItem.image("queued.webp")
                ]),
                encoding: .utf8
            ),
            scanState: .staged,
            stagedR2Keys: [staleKey]
        )
        context.insert(scan)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let generation = UUID()
        #expect(
            await actor.tryClaimForInference(
                scanId: scan.id,
                generation: generation
            )
        )
        #expect(
            await actor.scheduleInferenceRetry(
                id: scan.id,
                expectedGeneration: generation,
                code: "scan_persistence_failed",
                message: "Scan insert failed.",
                delay: 5,
                resetMediaUploads: true
            ) == 1
        )

        let verificationContext = ModelContext(container)
        let expectedScanId = scan.id
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == expectedScanId }
        )
        descriptor.fetchLimit = 1
        let persisted = try verificationContext.fetch(descriptor).first
        #expect(persisted?.queueState == .pending)
        #expect(persisted?.stagedR2Keys == nil)
    }

    @Test func legacyQueuedAudioRepairAtomicallyRewritesTimelineAndClearsStaging() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scanId = "legacy-audio-repair-\(UUID().uuidString.lowercased())"
        let generation = UUID()
        let standalone = StoredMediaReference.documents(
            "standalone-legacy.m4a",
            sourceIndex: 3
        )
        let companion = StoredMediaReference.documents(
            "video-companion-legacy.m4a"
        )
        let originalItems: [SerializedMediaItem] = [
            .description(ObservationContext(freeText: "Heard after dusk.")),
            .audio(standalone),
            .video(StoredVideoMediaReference(
                video: .documents("legacy-video.mp4"),
                thumbnail: .documents("legacy-poster.webp"),
                audio: companion
            ))
        ]
        let scan = OfflineQueuedScan(
            id: scanId,
            capturedMediaJSON: MediaJSONParser.jsonString(from: originalItems),
            scanState: .staged,
            stagedR2Keys: [
                "staging/owner/\(scanId)_standalone-legacy.m4a",
                "staging/owner/\(scanId)_video-companion-legacy.m4a"
            ]
        )
        let job = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .waiting,
            metadataJSON: InferenceGenerationMetadataContract.json(
                for: generation
            )
        )
        context.insert(scan)
        context.insert(job)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        #expect(
            await actor.legacyQueuedAudioRepairCandidateIds().contains(scanId)
        )
        let candidate = try #require(
            await actor.claimLegacyQueuedAudioRepair(scanId: scanId)
        )
        #expect(candidate.references == [standalone, companion])

        var verificationContext = ModelContext(container)
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        var persisted = try #require(
            verificationContext.fetch(descriptor).first
        )
        #expect(persisted.queueState == .pending)
        #expect(persisted.stagedR2Keys == nil)
        #expect(
            persisted.queueSchemaRepairGeneration ==
                LegacyQueuedAudioRepairState.inProgressGeneration
        )

        #expect(await actor.commitLegacyQueuedAudioRepair(
            scanId: scanId,
            replacements: [
                LegacyQueuedAudioRepairReplacement(
                    sourceStorage: standalone.storage,
                    sourcePath: standalone.path,
                    replacementFileName: "standalone-upgraded.wav"
                ),
                LegacyQueuedAudioRepairReplacement(
                    sourceStorage: companion.storage,
                    sourcePath: companion.path,
                    replacementFileName: "companion-upgraded.wav"
                )
            ]
        ))

        verificationContext = ModelContext(container)
        persisted = try #require(
            verificationContext.fetch(descriptor).first
        )
        #expect(persisted.queueState == .pending)
        #expect(persisted.stagedR2Keys == nil)
        #expect(
            persisted.queueSchemaRepairGeneration ==
                LegacyQueuedAudioRepairState.completedGeneration
        )
        #expect(persisted.serializedCapturedMediaItems.count == 3)
        guard case .description(let contextItem) =
                persisted.serializedCapturedMediaItems[0],
              case .audio(let upgradedStandalone) =
                persisted.serializedCapturedMediaItems[1],
              case .video(let upgradedVideo) =
                persisted.serializedCapturedMediaItems[2] else {
            Issue.record("Legacy audio repair changed media timeline ordering.")
            return
        }
        #expect(contextItem.freeText == "Heard after dusk.")
        #expect(upgradedStandalone.path == "standalone-upgraded.wav")
        #expect(upgradedStandalone.sourceIndex == 3)
        #expect(upgradedVideo.audio?.path == "companion-upgraded.wav")
        #expect(upgradedVideo.video.path == "legacy-video.mp4")
        #expect(upgradedVideo.thumbnail?.path == "legacy-poster.webp")
        #expect(persisted.capturedMediaEntries?.count == 3)

        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        var jobDescriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        jobDescriptor.fetchLimit = 1
        let persistedJob = try #require(
            verificationContext.fetch(jobDescriptor).first
        )
        #expect(persistedJob.status == .pending)
        #expect(
            InferenceGenerationMetadataContract.generation(
                in: persistedJob.metadataJSON
            ) == nil
        )
        #expect(
            !(await actor.legacyQueuedAudioRepairCandidateIds().contains(scanId))
        )
    }

    @Test func completedCloudResultVetoesLegacyQueuedAudioRepair() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scanId = "cloud-owned-legacy-audio-\(UUID().uuidString.lowercased())"
        let staleKey = "staging/owner/\(scanId)_legacy.m4a"
        let scan = OfflineQueuedScan(
            id: scanId,
            capturedMediaJSON: MediaJSONParser.jsonString(from: [
                .audio(.documents("cloud-owned-legacy.m4a"))
            ]),
            scanState: .staged,
            stagedR2Keys: [staleKey],
            queueLastErrorCode:
                OfflineQueueManager.completedServerResultRecoveryCode
        )
        context.insert(scan)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        #expect(
            !(await actor.legacyQueuedAudioRepairCandidateIds().contains(scanId))
        )
        #expect(
            await actor.claimLegacyQueuedAudioRepair(scanId: scanId) == nil
        )

        let verificationContext = ModelContext(container)
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        let persisted = try #require(
            verificationContext.fetch(descriptor).first
        )
        #expect(persisted.queueState == .staged)
        #expect(persisted.stagedR2Keys == [staleKey])
    }

    @Test func testScheduleInferenceRetryUsesMonotonicMirroredAttempt() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scan = OfflineQueuedScan(
            id: UUID().uuidString.lowercased(),
            scanState: .inferencing,
            queueAttemptCount: 0
        )
        let job = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scan.id),
            kind: .scanIngestion,
            subjectId: scan.id,
            status: .running,
            attemptCount: 4,
            lastErrorCode:
                OfflineQueueManager.serverRetryableFailureCode
        )
        context.insert(scan)
        context.insert(job)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        #expect(
            await actor.scheduleInferenceRetry(
                id: scan.id,
                expectedGeneration: nil,
                code: OfflineQueueManager.serverRetryableFailureCode,
                message: "Advance the surviving durable retry counter.",
                delay: 1
            ) == 5
        )

        let verificationContext = ModelContext(container)
        let scanId = scan.id
        var scanDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        scanDescriptor.fetchLimit = 1
        let persistedScan = try #require(
            verificationContext.fetch(scanDescriptor).first
        )
        let jobId =
            OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        var jobDescriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        jobDescriptor.fetchLimit = 1
        let persistedJob = try #require(
            verificationContext.fetch(jobDescriptor).first
        )
        #expect(persistedScan.queueAttemptCount == 5)
        #expect(persistedJob.attemptCount == 5)
        #expect(
            persistedScan.queueLastErrorCode
                == OfflineQueueManager.serverRetryableFailureCode
        )
    }

    @Test func testInferenceRetryCannotOverrideCompletedCloudOwnership() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scan = OfflineQueuedScan(
            id: UUID().uuidString.lowercased(),
            scanState: .inferencing
        )
        let job = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scan.id),
            kind: .scanIngestion,
            subjectId: scan.id,
            status: .running,
            attemptCount: 2,
            lastErrorCode:
                OfflineQueueManager.completedServerResultRecoveryCode
        )
        context.insert(scan)
        context.insert(job)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        #expect(
            await actor.scheduleInferenceRetry(
                id: scan.id,
                expectedGeneration: nil,
                code: OfflineQueueManager.serverRetryableFailureCode,
                message: "This must not replace cloud-complete ownership.",
                delay: 1
            ) == nil
        )

        let verificationContext = ModelContext(container)
        let scanId = scan.id
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        let persisted = try #require(
            verificationContext.fetch(descriptor).first
        )
        #expect(persisted.queueState == .inferencing)
        #expect(
            persisted.queueLastErrorCode
                == OfflineQueueManager.completedServerResultRecoveryCode
        )
    }

    @Test func testServerResultRecoveryRetryPreservesCloudOwnershipEvidence() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([
                    SerializedMediaItem.image("server-result.webp")
                ]),
                encoding: .utf8
            ),
            scanState: .staged
        )
        let retryAfter = Date().addingTimeInterval(30)
        scan.queueLastServerStatus = "complete"
        scan.queueLastServerStage = "media_finalization_complete"
        scan.queueLastServerRetryAfter = retryAfter
        let job = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scan.id),
            kind: .scanIngestion,
            subjectId: scan.id,
            status: .running
        )
        job.serverStatus = "complete"
        job.serverStage = "media_finalization_complete"
        job.serverRetryAfter = retryAfter
        context.insert(scan)
        context.insert(job)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let generation = UUID()
        #expect(
            await actor.tryClaimForInference(
                scanId: scan.id,
                generation: generation
            )
        )
        #expect(
            await actor.scheduleServerResultRecoveryRetry(
                id: scan.id,
                expectedGeneration: generation,
                code: "server_result_local_recovery_pending",
                message: "Local hydration failed.",
                delay: 30
            ) == 1
        )

        let verificationContext = ModelContext(container)
        let expectedScanId = scan.id
        var scanDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == expectedScanId }
        )
        scanDescriptor.fetchLimit = 1
        let persistedScan = try verificationContext.fetch(scanDescriptor).first
        let expectedJobId =
            OfflineQueueManager.scanIngestionJobId(scanId: scan.id)
        var jobDescriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == expectedJobId }
        )
        jobDescriptor.fetchLimit = 1
        let persistedJob = try verificationContext.fetch(jobDescriptor).first

        #expect(persistedScan?.queueState == .inferencing)
        #expect(persistedScan?.queueAttemptCount == 1)
        #expect(
            persistedScan?.queueLastErrorCode ==
                "server_result_local_recovery_pending"
        )
        #expect(persistedScan?.queueLastServerStatus == "complete")
        #expect(
            persistedScan?.queueLastServerStage ==
                "media_finalization_complete"
        )
        #expect(persistedScan?.queueLastServerRetryAfter == retryAfter)
        #expect(persistedJob?.serverStatus == "complete")
        #expect(persistedJob?.serverStage == "media_finalization_complete")
        #expect(persistedJob?.serverRetryAfter == retryAfter)
        #expect(
            persistedJob?.lastErrorCode ==
                "server_result_local_recovery_pending"
        )
    }

    @Test func testOfflineFinalizationRejectsOlderPersistedGeneration() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([
                    SerializedMediaItem.image("stale-finalization.webp")
                ]),
                encoding: .utf8
            ),
            scanState: .staged
        )
        context.insert(scan)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let firstGeneration = UUID()
        let secondGeneration = UUID()
        #expect(
            await actor.tryClaimForInference(
                scanId: scan.id,
                generation: firstGeneration
            )
        )
        #expect(
            await actor.transitionScanToStaged(
                id: scan.id,
                expectedGeneration: firstGeneration
            )
        )
        #expect(
            await actor.tryClaimForInference(
                scanId: scan.id,
                generation: secondGeneration
            )
        )

        let staleResult = await actor.processAndCleanupOfflineScan(
            resultData: Data("{}".utf8),
            originalImagePaths: [],
            scanId: scan.id,
            originalTimestamp: Date(),
            expectedGeneration: firstGeneration
        )

        #expect(staleResult.wasCleaned == false)
        await ScanInferencePersistenceCoordinator.shared.acquire(
            scanId: scan.id
        )
        let secondGenerationStillOwnsPersistence =
            await actor.inferenceGenerationIsCurrentAssumingPersistenceLock(
                scanId: scan.id,
                expectedGeneration: secondGeneration
            )
        await ScanInferencePersistenceCoordinator.shared.release(
            scanId: scan.id
        )
        #expect(secondGenerationStillOwnsPersistence)
    }

    @Test func absentQueueRequiresExactCompletedGenerationForInferenceDeletion() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scanId = "guarded-completion-replay-\(UUID().uuidString)"
        let generation = UUID()
        let otherGeneration = UUID()
        let job = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .running,
            metadataJSON:
                InferenceGenerationMetadataContract.json(for: generation)
        )
        context.insert(job)
        try context.save()

        func durableGenerationIsCurrent() async -> Bool {
            await ScanInferencePersistenceCoordinator.shared.acquire(
                scanId: scanId
            )
            let actor = BackgroundDatabaseActor(modelContainer: container)
            let isCurrent =
                await actor
                    .inferenceGenerationIsCurrentAssumingPersistenceLock(
                        scanId: scanId,
                        expectedGeneration: generation
                    )
            await ScanInferencePersistenceCoordinator.shared.release(
                scanId: scanId
            )
            return isCurrent
        }

        #expect(!(await durableGenerationIsCurrent()))

        job.status = .complete
        job.metadataJSON =
            InferenceGenerationMetadataContract.json(for: otherGeneration)
        try context.save()
        #expect(!(await durableGenerationIsCurrent()))

        job.metadataJSON =
            InferenceGenerationMetadataContract.json(for: generation)
        try context.save()
        #expect(await durableGenerationIsCurrent())
    }

    @Test func testTransitionScanToStagedDoesNotResurrectTombstone() async throws {
        // The critical guard: a MainActor softDeleteQueuedScan wins the race and sets .failed.
        // The background actor must not overwrite it when its transitionScanToStaged runs later.
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("tombstoned.webp")]), encoding: .utf8), scanState: .failed)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.transitionScanToStaged(id: scanId)

        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.scanStateRaw == ScanQueueState.failed.rawValue,
                "transitionScanToStaged must not overwrite a .failed tombstone — last-writer-wins guard")
    }

    @Test func testTransitionScanToStagedIsNoOpFromPending() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("pending.webp")]), encoding: .utf8), scanState: .pending)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.transitionScanToStaged(id: scanId)

        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.scanStateRaw == ScanQueueState.pending.rawValue,
                "transitionScanToStaged must be a no-op for non-.inferencing scans")
    }

    // MARK: - markScanAsStaged: source-state guard and R2 key persistence (V33)

    @Test func testMarkScanAsStagedPersistsR2Keys() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("img.webp")]), encoding: .utf8), scanState: .uploading)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let r2Keys = ["staging/user123/\(scanId)_img.webp"]
        let actor = BackgroundDatabaseActor(modelContainer: container)
        let outcome = await actor.markScanAsStaged(
            scanId: scanId,
            r2Keys: r2Keys
        )

        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(outcome == .staged)
        #expect(fetched?.scanStateRaw == ScanQueueState.staged.rawValue,
                "markScanAsStaged must transition .uploading → .staged")
        #expect(fetched?.stagedR2Keys == r2Keys,
                "markScanAsStaged must persist R2 keys so inference can use them without auth reconstruction")
    }

    @Test func testMarkScanAsStagedPreservesScheduledServerFailureRetry() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([
                    SerializedMediaItem.image("server-retry.webp")
                ]),
                encoding: .utf8
            ),
            scanState: .staged,
            stagedR2Keys: ["staging/user/server-retry-consumed.webp"]
        )
        context.insert(scan)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let firstGeneration = UUID()
        #expect(
            await actor.tryClaimForInference(
                scanId: scan.id,
                generation: firstGeneration
            )
        )
        #expect(
            await actor.scheduleInferenceRetry(
                id: scan.id,
                expectedGeneration: firstGeneration,
                code: OfflineQueueManager.serverRetryableFailureCode,
                message: "Exact server retry is ready.",
                delay: 1,
                resetMediaUploads: true
            ) == 1
        )
        // Simulate a migrated store whose queue-row snapshot lost the marker
        // and counter while the job-row mirror remained durable.
        let driftContext = ModelContext(container)
        let driftedScanId = scan.id
        var driftDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == driftedScanId }
        )
        driftDescriptor.fetchLimit = 1
        let driftedScan = try #require(
            driftContext.fetch(driftDescriptor).first
        )
        let driftedJobId =
            OfflineQueueManager.scanIngestionJobId(scanId: driftedScanId)
        var driftedJobDescriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == driftedJobId }
        )
        driftedJobDescriptor.fetchLimit = 1
        let driftedJob = try #require(
            driftContext.fetch(driftedJobDescriptor).first
        )
        driftedScan.queueLastErrorCode = nil
        driftedScan.queueAttemptCount = 0
        // Advance the fixture to the scheduled wake. The transition under test
        // is preservation of the surviving retry marker during re-upload, not
        // an attempt to bypass durable backoff.
        let scheduledWake = Date().addingTimeInterval(-1)
        driftedScan.queueNextRetryAt = scheduledWake
        driftedJob.nextRunAt = scheduledWake
        try driftContext.save()

        let stagingActor =
            BackgroundDatabaseActor(modelContainer: container)
        #expect(
            await stagingActor.markScansAsUploading(scanIds: [scan.id]) ==
                Set([scan.id])
        )
        let outcome = await stagingActor.markScanAsStaged(
            scanId: scan.id,
            r2Keys: ["staging/user/\(scan.id)_server-retry.webp"]
        )

        let verificationContext = ModelContext(container)
        let scanId = scan.id
        var scanDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        scanDescriptor.fetchLimit = 1
        let persistedScan = try #require(
            verificationContext.fetch(scanDescriptor).first
        )
        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        var jobDescriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        jobDescriptor.fetchLimit = 1
        let persistedJob = try #require(
            verificationContext.fetch(jobDescriptor).first
        )

        #expect(outcome == .staged)
        #expect(persistedScan.queueState == .staged)
        #expect(persistedScan.queueAttemptCount == 1)
        #expect(
            persistedScan.queueLastErrorCode
                == OfflineQueueManager.serverRetryableFailureCode
        )
        #expect(persistedScan.queueNextRetryAt == nil)
        #expect(persistedJob.attemptCount == 1)
        #expect(
            persistedJob.lastErrorCode
                == OfflineQueueManager.serverRetryableFailureCode
        )
    }

    @Test func testMarkScanAsStagedDoesNotResurrectTombstone() async throws {
        // Prevents a late-arriving HTTP 200 for a partially-uploaded scan from
        // resurrecting it into the inference pipeline after it was tombstoned.
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("dead.webp")]), encoding: .utf8), scanState: .failed)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let outcome = await actor.markScanAsStaged(
            scanId: scanId,
            r2Keys: ["staging/user/\(scanId)_dead.webp"]
        )

        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(outcome == .discarded)
        #expect(fetched?.scanStateRaw == ScanQueueState.failed.rawValue,
                "markScanAsStaged must not resurrect .failed tombstones")
        #expect(fetched?.stagedR2Keys == nil,
                "R2 keys must not be written to a tombstoned scan")
    }

    @Test func testMarkScanAsStagedIsNoOpFromPending() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("pending.webp")]), encoding: .utf8), scanState: .pending)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let outcome = await actor.markScanAsStaged(
            scanId: scanId,
            r2Keys: ["staging/user/\(scanId)_pending.webp"]
        )

        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(outcome == .retryRequired)
        #expect(fetched?.scanStateRaw == ScanQueueState.pending.rawValue,
                "markScanAsStaged must be a no-op for non-.uploading scans — prevents skipping the upload state")
        #expect(fetched?.stagedR2Keys == nil)
    }

    @Test func testMarkScanAsStagedReportsSerializedAdvance() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([
                    SerializedMediaItem.image("advanced.webp")
                ]),
                encoding: .utf8
            ),
            scanState: .staged
        )
        let r2Keys = ["staging/user/\(scan.id)_advanced.webp"]
        scan.stagedR2Keys = r2Keys
        context.insert(scan)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let outcome = await actor.markScanAsStaged(
            scanId: scan.id,
            r2Keys: r2Keys
        )

        #expect(outcome == .alreadyAdvanced)
    }

    @Test func testMarkScanAsStagedRejectsMismatchedAdvancedManifest() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([
                    SerializedMediaItem.image("persisted.webp")
                ]),
                encoding: .utf8
            ),
            scanState: .staged
        )
        let scanId = scan.id
        let persistedKeys = ["staging/user/\(scanId)_persisted.webp"]
        scan.stagedR2Keys = persistedKeys
        context.insert(scan)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let outcome = await actor.markScanAsStaged(
            scanId: scanId,
            r2Keys: ["staging/user/\(scanId)_stale-callback.webp"]
        )

        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        #expect(outcome == .retryRequired)
        #expect(try context.fetch(descriptor).first?.stagedR2Keys == persistedKeys)
    }

    // MARK: - markScansAsUploading: source-state guard (V33)

    @Test func testMarkScansAsUploadingOnlyTransitionsPendingScans() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let pending    = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("p.webp")]), encoding: .utf8), scanState: .pending)
        let uploading  = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("u.webp")]), encoding: .utf8), scanState: .uploading)
        let staged     = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("s.webp")]), encoding: .utf8), scanState: .staged)
        let failed     = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("f.webp")]), encoding: .utf8), scanState: .failed)

        for scan in [pending, uploading, staged, failed] { context.insert(scan) }
        try context.save()

        // Pass all four IDs — only the .pending one must advance.
        let actor = BackgroundDatabaseActor(modelContainer: container)
        let claimedIds = await actor.markScansAsUploading(scanIds: [pending.id, uploading.id, staged.id, failed.id])
        #expect(claimedIds == Set([pending.id]), "only pending scans should be claimed for upload dispatch")

        let allDescriptor = FetchDescriptor<OfflineQueuedScan>()
        let all = try context.fetch(allDescriptor)
        let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.scanStateRaw) })

        #expect(byId[pending.id]   == ScanQueueState.uploading.rawValue, ".pending must advance to .uploading")
        #expect(byId[uploading.id] == ScanQueueState.uploading.rawValue, "already-.uploading must stay .uploading")
        #expect(byId[staged.id]    == ScanQueueState.staged.rawValue, ".staged must not be regressed")
        #expect(byId[failed.id]    == ScanQueueState.failed.rawValue, ".failed tombstone must not be touched")
    }

    // MARK: - reconcileOrphanedUploadingScans: startup recovery (V33)

    @Test func pausedScansCannotBeClaimedOrReconciled() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let retryAt = Date().addingTimeInterval(600)
        let pending = OfflineQueuedScan(
            scanState: .pending,
            queueNeedsAttention: true
        )
        let uploading = OfflineQueuedScan(
            scanState: .uploading,
            queueNeedsAttention: true
        )
        let staged = OfflineQueuedScan(
            scanState: .staged,
            queueNeedsAttention: true
        )
        let inferencing = OfflineQueuedScan(
            scanState: .inferencing,
            queueNeedsAttention: true
        )
        let delayedPending = OfflineQueuedScan(
            scanState: .pending,
            queueNextRetryAt: retryAt
        )
        let delayedStaged = OfflineQueuedScan(
            scanState: .staged,
            queueNextRetryAt: retryAt
        )
        for scan in [
            pending,
            uploading,
            staged,
            inferencing,
            delayedPending,
            delayedStaged
        ] {
            context.insert(scan)
        }
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let claimedUploads = await actor.markScansAsUploading(
            scanIds: [pending.id, delayedPending.id]
        )
        let claimedAttentionInference = await actor.tryClaimForInference(
            scanId: staged.id
        )
        let claimedDelayedInference = await actor.tryClaimForInference(
            scanId: delayedStaged.id
        )
        let resetUploads = await actor.reconcileOrphanedUploadingScans(
            activeScanIds: []
        )
        await actor.reconcileOrphanedInferencingScans(
            activeInferenceScanIds: []
        )
        let serverOwnedInferenceIds =
            await actor.fetchServerOwnedInferencingScanIds(
                excludingScanIds: [],
                observedThrough: Date().addingTimeInterval(1)
            )

        let readContext = ModelContext(container)
        let rows = try readContext.fetch(FetchDescriptor<OfflineQueuedScan>())
        let stateById = Dictionary(uniqueKeysWithValues: rows.map {
            ($0.id, $0.queueState)
        })

        #expect(claimedUploads.isEmpty)
        #expect(!claimedAttentionInference)
        #expect(!claimedDelayedInference)
        #expect(!resetUploads)
        #expect(serverOwnedInferenceIds.isEmpty)
        #expect(stateById[pending.id] == .pending)
        #expect(stateById[uploading.id] == .uploading)
        #expect(stateById[staged.id] == .staged)
        #expect(stateById[inferencing.id] == .inferencing)
        #expect(stateById[delayedPending.id] == .pending)
        #expect(stateById[delayedStaged.id] == .staged)
    }

    @Test func testReconcileOrphanedUploadingScansResetsOrphansKeepsActive() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let orphan = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("orphan.webp")]), encoding: .utf8), scanState: .uploading)
        let active = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("active.webp")]), encoding: .utf8), scanState: .uploading)
        let pending = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("pending.webp")]), encoding: .utf8), scanState: .pending)
        let orphanJob = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: orphan.id),
            kind: .scanIngestion,
            subjectId: orphan.id,
            status: .running
        )
        let activeJob = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: active.id),
            kind: .scanIngestion,
            subjectId: active.id,
            status: .running
        )

        for scan in [orphan, active, pending] { context.insert(scan) }
        context.insert(orphanJob)
        context.insert(activeJob)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        // Only `active` has a live URLSession task.
        let hadOrphans = await actor.reconcileOrphanedUploadingScans(
            activeScanIds: Set([active.id])
        )

        let allDescriptor = FetchDescriptor<OfflineQueuedScan>()
        let all = try context.fetch(allDescriptor)
        let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.scanStateRaw) })

        #expect(byId[orphan.id]  == ScanQueueState.pending.rawValue, "orphaned .uploading scan must reset to .pending")
        #expect(byId[active.id]  == ScanQueueState.uploading.rawValue, ".uploading scan with active task must stay .uploading")
        #expect(byId[pending.id] == ScanQueueState.pending.rawValue, ".pending scan must be unaffected")
        #expect(hadOrphans, "callers must be told to restart signing after a reset")

        let jobReadContext = ModelContext(container)
        let jobs = try jobReadContext.fetch(
            FetchDescriptor<OfflineJobRecord>()
        )
        let jobStatusById = Dictionary(uniqueKeysWithValues: jobs.map {
            ($0.id, $0.status)
        })
        #expect(
            jobStatusById[orphanJob.id] == .pending,
            "orphan recovery must atomically release the durable running job"
        )
        #expect(
            jobStatusById[activeJob.id] == .running,
            "a live task must retain its durable running job"
        )
    }

    @Test func testReconcileOrphanedUploadingScansWithEmptyActiveSet() async throws {
        // Process died mid-dispatch — no URLSession tasks survived. All .uploading → .pending.
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan1 = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("a.webp")]), encoding: .utf8), scanState: .uploading)
        let scan2 = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("b.webp")]), encoding: .utf8), scanState: .uploading)

        context.insert(scan1)
        context.insert(scan2)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let hadOrphans = await actor.reconcileOrphanedUploadingScans(
            activeScanIds: Set()
        )

        let allDescriptor = FetchDescriptor<OfflineQueuedScan>()
        let all = try context.fetch(allDescriptor)
        for scan in all {
            #expect(scan.scanStateRaw == ScanQueueState.pending.rawValue,
                    "all .uploading scans must be reset when no active tasks exist")
        }
        #expect(hadOrphans)
    }

    @Test func testUploadReconciliationDoesNotResetWorkNewerThanSnapshot() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let observedThrough = Date()
        let oldScan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([SerializedMediaItem.image("old.webp")]),
                encoding: .utf8
            ),
            scanState: .uploading,
            queueUpdatedAt: observedThrough.addingTimeInterval(-10)
        )
        let replacementScan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([SerializedMediaItem.image("replacement.webp")]),
                encoding: .utf8
            ),
            scanState: .uploading,
            queueUpdatedAt: observedThrough.addingTimeInterval(10)
        )
        let unrelatedScan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([SerializedMediaItem.image("unrelated.webp")]),
                encoding: .utf8
            ),
            scanState: .uploading,
            queueUpdatedAt: observedThrough.addingTimeInterval(-10)
        )
        context.insert(oldScan)
        context.insert(replacementScan)
        context.insert(unrelatedScan)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.reconcileOrphanedUploadingScans(
            activeScanIds: [],
            candidateScanIds: Set([oldScan.id, replacementScan.id]),
            observedThrough: observedThrough
        )

        let all = try context.fetch(FetchDescriptor<OfflineQueuedScan>())
        let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.scanStateRaw) })
        #expect(byId[oldScan.id] == ScanQueueState.pending.rawValue)
        #expect(byId[replacementScan.id] == ScanQueueState.uploading.rawValue)
        #expect(
            byId[unrelatedScan.id] == ScanQueueState.uploading.rawValue,
            "an exact post-claim release must not reset unrelated work"
        )
    }

    // MARK: - reconcileOrphanedInferencingScans

    @Test func testReconcileOrphanedInferencingScansResetsAllToStaged() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let inf1   = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("i1.webp")]), encoding: .utf8), scanState: .inferencing)
        let inf2   = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("i2.webp")]), encoding: .utf8), scanState: .inferencing)
        let staged = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("s.webp")]), encoding: .utf8), scanState: .staged)
        let failed = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("f.webp")]), encoding: .utf8), scanState: .failed)
        let inferenceJob1 = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: inf1.id),
            kind: .scanIngestion,
            subjectId: inf1.id,
            status: .running
        )
        let inferenceJob2 = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: inf2.id),
            kind: .scanIngestion,
            subjectId: inf2.id,
            status: .running
        )

        for scan in [inf1, inf2, staged, failed] { context.insert(scan) }
        context.insert(inferenceJob1)
        context.insert(inferenceJob2)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.reconcileOrphanedInferencingScans(activeInferenceScanIds: [])

        let allDescriptor = FetchDescriptor<OfflineQueuedScan>()
        let all = try context.fetch(allDescriptor)
        let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.scanStateRaw) })

        #expect(byId[inf1.id]   == ScanQueueState.staged.rawValue, ".inferencing must reset to .staged")
        #expect(byId[inf2.id]   == ScanQueueState.staged.rawValue, "all .inferencing scans must reset")
        #expect(byId[staged.id] == ScanQueueState.staged.rawValue, ".staged must be unaffected")
        #expect(byId[failed.id] == ScanQueueState.failed.rawValue, ".failed tombstone must be unaffected")

        let jobReadContext = ModelContext(container)
        let jobs = try jobReadContext.fetch(
            FetchDescriptor<OfflineJobRecord>()
        )
        let jobStatusById = Dictionary(uniqueKeysWithValues: jobs.map {
            ($0.id, $0.status)
        })
        #expect(jobStatusById[inferenceJob1.id] == .pending)
        #expect(jobStatusById[inferenceJob2.id] == .pending)
    }

    @Test func testInferenceReconciliationDoesNotResetWorkNewerThanSnapshot() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let observedThrough = Date()
        let oldScan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([SerializedMediaItem.image("old-inference.webp")]),
                encoding: .utf8
            ),
            scanState: .inferencing,
            queueUpdatedAt: observedThrough.addingTimeInterval(-10)
        )
        let replacementScan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([SerializedMediaItem.image("replacement-inference.webp")]),
                encoding: .utf8
            ),
            scanState: .inferencing,
            queueUpdatedAt: observedThrough.addingTimeInterval(10)
        )
        context.insert(oldScan)
        context.insert(replacementScan)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.reconcileOrphanedInferencingScans(
            activeInferenceScanIds: [],
            observedThrough: observedThrough
        )

        let all = try context.fetch(FetchDescriptor<OfflineQueuedScan>())
        let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.scanStateRaw) })
        #expect(byId[oldScan.id] == ScanQueueState.staged.rawValue)
        #expect(byId[replacementScan.id] == ScanQueueState.inferencing.rawValue)
    }

    // MARK: - Full state machine lifecycle (V33)

    @Test func testFullStateMachineLifecycle() async throws {
        // Walks a single scan through every forward state transition, then validates
        // the transient-retry path, then re-claims and verifies the second claim is blocked.
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("lifecycle.webp")]), encoding: .utf8), scanState: .pending)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)

        func fetchState() throws -> Int {
            var d = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
            d.fetchLimit = 1
            return (try context.fetch(d).first?.scanStateRaw) ?? -1
        }

        // .pending → .uploading
        let claimedIds = await actor.markScansAsUploading(scanIds: [scanId])
        #expect(claimedIds == Set([scanId]), "pending scan should be claimed before upload dispatch")
        #expect(try fetchState() == ScanQueueState.uploading.rawValue, ".pending must advance to .uploading")

        // .uploading → .staged (with R2 keys persisted)
        let r2Keys = ["staging/user/\(scanId)_lifecycle.webp"]
        await actor.markScanAsStaged(scanId: scanId, r2Keys: r2Keys)
        #expect(try fetchState() == ScanQueueState.staged.rawValue, ".uploading must advance to .staged")
        var d = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        d.fetchLimit = 1
        #expect(try context.fetch(d).first?.stagedR2Keys == r2Keys, "R2 keys must be persisted at staging")

        // .staged → .inferencing (claim)
        let firstClaim = await actor.tryClaimForInference(scanId: scanId)
        #expect(firstClaim == true, ".staged scan must be claimable for inference")
        #expect(try fetchState() == ScanQueueState.inferencing.rawValue, "claimed scan must be .inferencing")

        // Concurrent second claim is blocked
        let secondClaim = await actor.tryClaimForInference(scanId: scanId)
        #expect(secondClaim == false, "second claim on .inferencing scan must fail")

        // Transient failure → retreat to .staged
        await actor.transitionScanToStaged(id: scanId)
        #expect(try fetchState() == ScanQueueState.staged.rawValue, "transient failure must retreat to .staged")

        // Re-claim after retry
        let retryClaim = await actor.tryClaimForInference(scanId: scanId)
        #expect(retryClaim == true, "re-claim on .staged scan must succeed after retry")
        #expect(try fetchState() == ScanQueueState.inferencing.rawValue, "retried scan must be .inferencing again")
    }
}
