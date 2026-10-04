import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
struct LibraryMutationInventoryTests {
    @Test func upgradeProofCannotAssignSourceLibraryToUnacknowledgedDestination() {
        let source = UUID(), destination = UUID()
        #expect(LibraryAccountOwnershipPolicy.canAdoptUnmarkedLibrary(session: source, pendingSourceIDs: [source.uuidString]))
        #expect(!LibraryAccountOwnershipPolicy.canAdoptUnmarkedLibrary(session: destination, pendingSourceIDs: [source.uuidString]))
        #expect(!LibraryAccountOwnershipPolicy.canAdoptUnmarkedLibrary(session: nil, pendingSourceIDs: [source.uuidString]))
        #expect(!LibraryAccountOwnershipPolicy.canAdoptUnmarkedLibrary(session: source, pendingSourceIDs: ["invalid"]))
        #expect(!LibraryAccountOwnershipPolicy.canAdoptUnmarkedLibrary(session: source, pendingSourceIDs: [source.uuidString, destination.uuidString]))
        #expect(LibraryAccountOwnershipPolicy.canAdoptUnmarkedLibrary(session: destination, pendingSourceIDs: []))
    }

    @Test func firstLaunchFavoritesDoesNotBlockAnonymousBootstrap() throws {
        let harness = try Harness()
        #expect(try LibraryMutationInventory.isEmptyLibrary(in: harness.container, userDefaults: harness.defaults))
        let favorites = ScanCollection(name: "Favorites")
        harness.context.insert(favorites)
        try harness.context.save()
        #expect(try LibraryMutationInventory.isEmptyLibrary(in: harness.container, userDefaults: harness.defaults))
        favorites.isPendingDeletion = true
        try harness.context.save()
        #expect(!(try LibraryMutationInventory.isEmptyLibrary(in: harness.container, userDefaults: harness.defaults)))
        favorites.isPendingDeletion = false
        harness.context.insert(ScanCollection(name: "My collection"))
        try harness.context.save()
        #expect(!(try LibraryMutationInventory.isEmptyLibrary(in: harness.container, userDefaults: harness.defaults)))
    }

    @Test func legacyBridgeNoteOnExistingScanRequiresExactDurableAcknowledgment() throws {
        let harness = try Harness()
        let record = LocalScanRecord(id: UUID().uuidString, speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture")
        harness.context.insert(record)
        try harness.context.save()
        FieldNotesStore.setFieldNotes("Synthetic legacy note", for: record.id, userDefaults: harness.defaults)
        #expect(try harness.inventory().localOnlyChanges == 1)
        try LibraryDetailsSyncService.stageLegacyDetails(context: harness.context, ownerID: harness.owner, userDefaults: harness.defaults)
        #expect(record.fieldNotes == "Synthetic legacy note")
        #expect(!(try harness.inventory()).isReady)
        let job = try #require(harness.context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        job.status = .complete
        try harness.context.save()
        #expect(try harness.inventory().isReady)
    }

    @Test func remoteClearedNotesSupersedeStaleLegacyBridge() throws {
        let harness = try Harness()
        let record = LocalScanRecord(speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture")
        harness.context.insert(record)
        try LibraryDetailsSyncService.stage(record, ownerID: harness.owner, context: harness.context)
        let job = try #require(harness.context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        job.id = "library-details:baseline:\(record.id)"
        job.status = .complete
        try harness.context.save()
        FieldNotesStore.setFieldNotes("Stale bridge note", for: record.id, userDefaults: harness.defaults)
        #expect(try harness.inventory().isReady)
        try LibraryDetailsSyncService.stageLegacyDetails(context: harness.context, ownerID: harness.owner, userDefaults: harness.defaults)
        #expect(record.fieldNotes == nil)
        #expect(try harness.context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 1)
    }

    @Test(arguments: [OfflineJobStatus.pending, .complete])
    func tagOnlyOperationImportsLegacyNoteBeforeAcknowledgment(status: OfflineJobStatus) async throws {
        let harness = try Harness()
        let record = LocalScanRecord(speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture")
        record.customTags = ["tag"]
        harness.context.insert(record)
        try LibraryDetailsSyncService.stage(record, ownerID: harness.owner, context: harness.context)
        let original = try #require(harness.context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        original.status = status
        try harness.context.save()
        FieldNotesStore.setFieldNotes("Legacy note", for: record.id, userDefaults: harness.defaults)
        #expect(!(try harness.inventory()).isReady)
        var sent: [LibraryDetailsSyncService.Mutation] = []
        await LibraryDetailsSyncService.drainPending(
            context: harness.context, ownerID: harness.owner, userDefaults: harness.defaults,
            isCurrent: { true }, send: { sent.append($0) }
        )
        #expect(record.fieldNotes == "Legacy note")
        #expect(sent.last?.fieldNotes == "Legacy note")
        #expect(try harness.inventory().isReady)
        #expect(try harness.context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 2)
        try LibraryDetailsSyncService.stageLegacyDetails(context: harness.context, ownerID: harness.owner, userDefaults: harness.defaults)
        #expect(try harness.context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 2)
    }

    @Test(arguments: [false, true])
    func legacyImportPreservesImmutableDesiredStateDespiteStaleProjection(isFavorite: Bool) async throws {
        let harness = try Harness()
        let record = LocalScanRecord(speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture")
        record.customTags = ["new-tag"]
        harness.context.insert(record)
        if isFavorite {
            let favorites = ScanCollection(name: "Favorites")
            harness.context.insert(favorites)
            record.collections = [favorites]
        }
        try LibraryDetailsSyncService.stage(record, ownerID: harness.owner, context: harness.context)
        record.customTags = ["stale-tag"]
        record.collections = []
        try harness.context.save()
        try LibraryDetailsSyncService.stageLegacyDetails(context: harness.context, ownerID: harness.owner, userDefaults: harness.defaults)
        #expect(try harness.context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 1)
        FieldNotesStore.setFieldNotes("Legacy note", for: record.id, userDefaults: harness.defaults)
        var sent: [LibraryDetailsSyncService.Mutation] = []
        await LibraryDetailsSyncService.drainPending(
            context: harness.context, ownerID: harness.owner, userDefaults: harness.defaults,
            isCurrent: { true }, send: { sent.append($0) }
        )
        #expect(sent.count == 2)
        #expect(sent.allSatisfy { $0.tags == ["new-tag"] })
        #expect(sent.last?.fieldNotes == "Legacy note")
        #expect(sent.allSatisfy { $0.isFavorite == isFavorite })
        #expect(record.customTags == ["new-tag"])
        #expect(try harness.inventory().isReady)
    }

    @Test func drainIncludesEditArrivingDuringServerRequest() async throws {
        let harness = try Harness()
        let record = LocalScanRecord(speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture", fieldNotes: "First")
        harness.context.insert(record)
        try LibraryDetailsSyncService.stage(record, ownerID: harness.owner, context: harness.context)
        try harness.context.save()
        var sent: [LibraryDetailsSyncService.Mutation] = []
        await LibraryDetailsSyncService.drainPending(
            context: harness.context, ownerID: harness.owner, userDefaults: harness.defaults,
            isCurrent: { true }, send: { mutation in
                sent.append(mutation)
                if sent.count == 1 {
                    record.fieldNotes = "Second"
                    try LibraryDetailsSyncService.stage(record, ownerID: harness.owner, context: harness.context)
                    try harness.context.save()
                }
            }
        )
        #expect(sent.map(\.fieldNotes) == ["First", "Second"])
        #expect(Set(sent.map(\.operationID)).count == 2)
        #expect(try harness.inventory().isReady)
    }

    @Test func failedAcknowledgmentSaveRetriesSameImmutableOperation() async throws {
        let harness = try Harness()
        let record = LocalScanRecord(speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture", fieldNotes: "Note")
        harness.context.insert(record)
        try LibraryDetailsSyncService.stage(record, ownerID: harness.owner, context: harness.context)
        try harness.context.save()
        var sent: [UUID] = []
        await LibraryDetailsSyncService.drainPending(
            context: harness.context, ownerID: harness.owner, userDefaults: harness.defaults,
            isCurrent: { true }, send: { sent.append($0.operationID) }, save: { _ in throw FixtureError.unavailable }
        )
        #expect(!(try harness.inventory()).isReady)
        #expect(try harness.context.fetch(FetchDescriptor<OfflineJobRecord>()).first?.status == .pending)
        await LibraryDetailsSyncService.drainPending(
            context: harness.context, ownerID: harness.owner, userDefaults: harness.defaults,
            isCurrent: { true }, send: { sent.append($0.operationID) }
        )
        #expect(sent.count == 2)
        #expect(sent.first == sent.last)
        #expect(try harness.inventory().isReady)
    }

    @Test func cancelledJobIsNotRevivedByLateServerAcknowledgment() async throws {
        let harness = try Harness()
        let record = LocalScanRecord(speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture", fieldNotes: "Note")
        harness.context.insert(record)
        try LibraryDetailsSyncService.stage(record, ownerID: harness.owner, context: harness.context)
        try harness.context.save()
        let job = try #require(harness.context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        await LibraryDetailsSyncService.drainPending(
            context: harness.context, ownerID: harness.owner, userDefaults: harness.defaults,
            isCurrent: { true }, send: { _ in
                job.status = .cancelled
                try harness.context.save()
            }
        )
        #expect(job.status == .cancelled)
    }

    @Test func ambiguousServerResponseRetainsOperationForIdempotentRetry() async throws {
        let harness = try Harness()
        let record = LocalScanRecord(speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture", fieldNotes: "Note")
        harness.context.insert(record)
        try LibraryDetailsSyncService.stage(record, ownerID: harness.owner, context: harness.context)
        try harness.context.save()
        var sent: [UUID] = []
        await LibraryDetailsSyncService.drainPending(
            context: harness.context, ownerID: harness.owner, userDefaults: harness.defaults,
            isCurrent: { true }, send: { mutation in
                sent.append(mutation.operationID)
                throw FixtureError.unavailable
            }
        )
        #expect(!(try harness.inventory()).isReady)
        await LibraryDetailsSyncService.drainPending(
            context: harness.context, ownerID: harness.owner, userDefaults: harness.defaults,
            isCurrent: { true }, send: { sent.append($0.operationID) }
        )
        #expect(sent.count == 2)
        #expect(sent.first == sent.last)
        #expect(try harness.inventory().isReady)
    }

    @Test func cancelledDrainRequestsRetryWithoutSending() async throws {
        let harness = try Harness()
        var retryCount = 0
        var sendCount = 0
        await Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            await LibraryDetailsSyncService.drainPending(
                context: harness.context, ownerID: harness.owner, userDefaults: harness.defaults,
                isCurrent: { true }, requestRetry: { retryCount += 1 }, send: { _ in sendCount += 1 }
            )
        }.value
        #expect(retryCount == 1)
        #expect(sendCount == 0)
    }

    @Test func staleOwnerCannotCommitServerAcknowledgment() async throws {
        let harness = try Harness()
        let record = LocalScanRecord(speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture", fieldNotes: "Note")
        harness.context.insert(record)
        try LibraryDetailsSyncService.stage(record, ownerID: harness.owner, context: harness.context)
        try harness.context.save()
        var current = true
        await LibraryDetailsSyncService.drainPending(
            context: harness.context, ownerID: harness.owner, userDefaults: harness.defaults,
            isCurrent: { current }, send: { _ in current = false }
        )
        #expect(!(try harness.inventory()).isReady)
    }

    private enum FixtureError: Error { case unavailable }

    @Test func ownershipMismatchRequiresRecoveryUnlessStoreIsProvenEmpty() {
        let source = UUID(), other = UUID()
        #expect(LibraryAccountOwnershipPolicy.requiresRecovery(owner: source, session: other, libraryIsEmpty: false))
        #expect(LibraryAccountOwnershipPolicy.requiresRecovery(owner: source, session: nil, libraryIsEmpty: false))
        #expect(!LibraryAccountOwnershipPolicy.requiresRecovery(owner: source, session: other, libraryIsEmpty: true))
        #expect(!LibraryAccountOwnershipPolicy.requiresRecovery(owner: source, session: source, libraryIsEmpty: false))
    }

    @Test func failedAndUnknownJobsCannotAuthorizeCleanup() throws {
        let harness = try Harness()
        let job = OfflineJobRecord(id: "fixture", kind: .future)
        job.status = .needsAttention
        harness.context.insert(job)
        try harness.context.save()
        let inventory = try harness.inventory()
        #expect(!inventory.isReady)
        #expect(inventory.issue == .needsAttention)
        job.statusRaw = "unrecognized-future-state"
        try harness.context.save()
        #expect(!(try harness.inventory()).isReady)
    }

    @Test func detailsRequireAcknowledgmentForExactOwnerAndPayload() throws {
        let harness = try Harness()
        let record = LocalScanRecord(id: UUID().uuidString, speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture")
        record.fieldNotes = "Synthetic private note"
        harness.context.insert(record)
        try LibraryDetailsSyncService.stage(record, ownerID: harness.owner, context: harness.context)
        try harness.context.save()
        #expect(!(try harness.inventory()).isReady)
        let job = try #require(harness.context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        job.status = .complete
        try harness.context.save()
        #expect(try harness.inventory().isReady)
        #expect(!(try LibraryMutationInventory.read(from: harness.container, sourceUserID: UUID(), userDefaults: harness.defaults)).isReady)
        record.fieldNotes = "Changed without acknowledgment"
        try harness.context.save()
        #expect(!(try harness.inventory()).isReady)
    }

    @Test func legacyBridgeOnlyNotesBlockCleanup() throws {
        let harness = try Harness()
        FieldNotesStore.setFieldNotes("Synthetic note", for: "missing-scan", userDefaults: harness.defaults)
        #expect(try harness.inventory().localOnlyChanges == 1)
    }

    @Test func restorationFailureAndStaleCompletionCannotReportComplete() {
        let state = LibraryRestorationState()
        let old = state.begin(accountID: UUID())
        let current = state.begin(accountID: UUID())
        state.finish(generation: old, complete: true)
        #expect(state.status == .restoring)
        state.finish(generation: current, complete: false)
        #expect(state.status == .needsAttention)
    }

    @MainActor private final class Harness {
        let owner = UUID()
        let suite = "merian.tests.library-inventory.\(UUID().uuidString)"
        let container: ModelContainer
        let context: ModelContext
        let defaults: UserDefaults
        init() throws {
            let schema = Schema(CurrentSchema.models)
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
            context = ModelContext(container)
            defaults = UserDefaults(suiteName: suite)!
        }
        deinit { defaults.removePersistentDomain(forName: suite) }
        func inventory() throws -> LibraryMutationInventory {
            try LibraryMutationInventory.read(from: container, sourceUserID: owner, userDefaults: defaults)
        }
    }
}
