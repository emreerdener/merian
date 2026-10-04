import Foundation
import SwiftData
import Testing

@testable import Merian

extension ScanRepositoryTests {
    @Test(arguments: [false, true])
    func restorationStagesLegacyNotesBeforeAcceptingEmptyCloudBaseline(targeted: Bool) async throws {
        let context = try ScanRepositoryTestSupport.makeContext()
        let record = LocalScanRecord(speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture")
        context.insert(record)
        try context.save()
        FieldNotesStore.setFieldNotes("Legacy private note", for: record.id)
        defer { FieldNotesStore.setFieldNotes(nil, for: record.id) }
        let manager = OfflineQueueManager.shared
        let originalContext = manager.modelContext
        manager.modelContext = context
        defer { manager.modelContext = originalContext }
        let lease = AccountBoundWorkLease(id: UUID(), session: AuthTransitionSession(userID: UUID(), isAnonymous: false))
        let fetch: @MainActor () throws -> Data = {
            let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
            #expect(job.status == .pending)
            #expect(record.fieldNotes == "Legacy private note")
            return Data("""
            [{"id":"\(record.id)","explore_posts":null,"library_details":{"owner_id":"\(lease.session.userID)","field_notes":null,"is_favorite":false}}]
            """.utf8)
        }
        let client = HistoricalSyncCloudClient(
            beginAccountWork: { lease }, finishAccountWork: { _ in }, isAccountWorkCurrent: { $0 == lease },
            fetchScanPage: { _ in try fetch() }, fetchScan: { _ in try fetch() }, fetchCollectionPage: { _ in [] }
        )
        let repository = ScanRepository(historicalCloudClient: client)
        if targeted {
            #expect(await repository.syncHistoricalScanDown(scanId: record.id, modelContext: context) == .reconciled)
        } else {
            await repository.syncHistoricalScansDown(modelContext: context)
            #expect(repository.libraryRestoration.status == .complete)
        }
        let verification = ModelContext(context.container)
        #expect(try verification.fetch(FetchDescriptor<LocalScanRecord>()).first?.fieldNotes == "Legacy private note")
        #expect(try verification.fetch(FetchDescriptor<OfflineJobRecord>()).first?.status == .pending)
    }

    @Test func privateDetailsRestoreSurvivesReservedRemoteCollection() async throws {
        let context = try ScanRepositoryTestSupport.makeContext()
        let scanID = UUID().uuidString.lowercased()
        let remoteID = UUID().uuidString.lowercased()
        let owner = UUID()
        context.insert(LocalScanRecord(id: scanID, speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture"))
        try context.save()
        let actor = HistoricalDatabaseActor(modelContainer: context.container)
        var response = try JSONDecoder().decode(HistoricalScanResponse.self, from: Data("{\"id\":\"\(scanID)\",\"custom_tags\":[\"cloud-tag\"]}".utf8))
        response.library_details = HistoricalLibraryDetails(owner_id: owner, field_notes: "Restored private note", is_favorite: true)
        try await actor.reconcileScanPage(responses: [response])
        let remote = try JSONDecoder().decode(CloudCollectionResponse.self, from: Data("""
        {"id":"\(remoteID)","name":"Favorites","created_at":"2026-01-01T00:00:00Z","collection_scans":[{"scan_id":"\(scanID)"}]}
        """.utf8))
        try await actor.syncCollectionsDown(remoteCollections: [remote])
        try await actor.syncCollectionsDown(remoteCollections: [remote])
        let verification = ModelContext(context.container)
        let record = try #require(verification.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(record.fieldNotes == "Restored private note")
        #expect(record.customTags == ["cloud-tag"])
        #expect(record.collections?.filter { $0.name == "Favorites" }.count == 1)
        #expect(record.collections?.contains { $0.id == remoteID && $0.name != "Favorites" } == true)
        let outbound = try await BackgroundDatabaseActor(modelContainer: context.container).collectionSyncSnapshots()
        #expect(outbound.count == 1)
        #expect(outbound.first?.id == remoteID)
        #expect(outbound.first?.name == "Favorites (restored \(remoteID))")
        #expect(outbound.first?.scanIDs == [scanID])
    }

    @Test(arguments: [false, true])
    func existingReservedRemoteCollectionKeepsPrivateFavoriteOnReconciliation(hasSystemFolder: Bool) async throws {
        let context = try ScanRepositoryTestSupport.makeContext()
        let record = LocalScanRecord(speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture")
        let collision = ScanCollection(name: "Favorites", scans: [record])
        context.insert(record)
        context.insert(collision)
        record.collections = [collision]
        if hasSystemFolder { context.insert(ScanCollection(name: "Favorites")) }
        try context.save()
        let actor = HistoricalDatabaseActor(modelContainer: context.container)
        var response = try JSONDecoder().decode(HistoricalScanResponse.self, from: Data("{\"id\":\"\(record.id)\"}".utf8))
        response.library_details = HistoricalLibraryDetails(owner_id: UUID(), field_notes: "Restored note", is_favorite: true)
        try await actor.reconcileScanPage(responses: [response])
        let remote = try JSONDecoder().decode(CloudCollectionResponse.self, from: Data("""
        {"id":"\(collision.id)","name":"fávORites","created_at":"2026-01-01T00:00:00Z","collection_scans":[]}
        """.utf8))
        try await actor.syncCollectionsDown(remoteCollections: [remote])
        let verification = ModelContext(context.container)
        let restored = try #require(verification.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(restored.collections?.filter { $0.name == "Favorites" }.count == 1)
        #expect(restored.collections?.contains { $0.id == collision.id } == false)
        #expect(try verification.fetchCount(FetchDescriptor<ScanCollection>()) == 2)
    }

    @Test(arguments: [false, true])
    func ordinaryLegacyFavoritesMembershipDoesNotBecomePrivateFavorite(hasCancelledNewerEvidence: Bool) async throws {
        let context = try ScanRepositoryTestSupport.makeContext()
        let record = LocalScanRecord(speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture")
        let collection = ScanCollection(name: "Favorites", scans: [record])
        context.insert(record)
        context.insert(collection)
        record.collections = [collection]
        if hasCancelledNewerEvidence {
            let owner = UUID()
            try LibraryDetailsSyncService.stage(record, ownerID: owner, context: context)
            let old = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
            old.status = .complete
            old.updatedAt = Date(timeIntervalSince1970: 10)
            record.collections = []
            try LibraryDetailsSyncService.stage(record, ownerID: owner, context: context)
            let cancelled = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first { $0.id != old.id })
            cancelled.status = .cancelled
            cancelled.updatedAt = Date(timeIntervalSince1970: 20)
            record.collections = [collection]
        }
        try context.save()
        let remote = try JSONDecoder().decode(CloudCollectionResponse.self, from: Data("""
        {"id":"\(collection.id)","name":"Favorites","created_at":"2026-01-01T00:00:00Z","collection_scans":[{"scan_id":"\(record.id)"}]}
        """.utf8))
        try await HistoricalDatabaseActor(modelContainer: context.container).syncCollectionsDown(remoteCollections: [remote])
        let restored = try #require(ModelContext(context.container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(restored.collections?.contains { $0.name == "Favorites" } == false)
        #expect(restored.collections?.map(\.id) == [collection.id])
    }

    @Test func pendingPrivateDetailsWinOverStaleRestoration() async throws {
        let context = try ScanRepositoryTestSupport.makeContext()
        let owner = UUID()
        let record = LocalScanRecord(speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture", fieldNotes: "Local edit")
        record.customTags = ["local-tag"]
        let favorites = ScanCollection(name: "Favorites", scans: [record])
        context.insert(record)
        context.insert(favorites)
        record.collections = [favorites]
        try LibraryDetailsSyncService.stage(record, ownerID: owner, context: context)
        try context.save()
        var response = try JSONDecoder().decode(HistoricalScanResponse.self, from: Data("{\"id\":\"\(record.id)\",\"custom_tags\":[\"old-tag\"]}".utf8))
        response.library_details = HistoricalLibraryDetails(owner_id: owner, field_notes: nil, is_favorite: false)
        try await HistoricalDatabaseActor(modelContainer: context.container).reconcileScanPage(responses: [response])
        let verification = ModelContext(context.container)
        let restored = try #require(verification.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(restored.fieldNotes == "Local edit")
        #expect(restored.customTags == ["local-tag"])
        #expect(restored.collections?.contains { $0.name == "Favorites" } == true)
        #expect(try verification.fetch(FetchDescriptor<OfflineJobRecord>()).first?.status == .pending)
    }

    @Test func cancelledCollectionReconciliationPreservesLocalRows() async throws {
        let context = try ScanRepositoryTestSupport.makeContext()
        let retainedCollection = ScanCollection(name: "Retained Collection")
        context.insert(retainedCollection)
        try context.save()
        let retainedId = retainedCollection.id

        let actor = HistoricalDatabaseActor(
            modelContainer: context.container
        )
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await actor.syncCollectionsDown(remoteCollections: [])
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        let verificationContext = ModelContext(context.container)
        let collections = try verificationContext.fetch(
            FetchDescriptor<ScanCollection>()
        )
        #expect(collections.map(\.id) == [retainedId])
    }

}
