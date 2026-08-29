import SwiftData
import XCTest

@testable import Merian

@MainActor
final class CollectionMutationServiceTests: XCTestCase {
    func testCreateUsesDurableSyncBoundary() throws {
        let context = try makeContext()
        let record = makeRecord(id: "record")
        context.insert(record)
        try context.save()

        let effects = CollectionEffectsRecorder()
        let service = CollectionMutationService(
            dependencies: dependencies(effects: effects)
        )

        let collection = try XCTUnwrap(
            service.create(
                name: "   ",
                relatedRecordID: record.id,
                in: context
            )
        )
        XCTAssertEqual(collection.name, "Untitled")
        XCTAssertEqual(record.collections?.map(\.id), [collection.id])
        XCTAssertEqual(effects.values, ["save", "sync", "success"])
    }

    func testRenameUsesDurableSyncBoundary() throws {
        let context = try makeContext()
        let collection = ScanCollection(name: "Untitled")
        context.insert(collection)
        try context.save()

        let effects = CollectionEffectsRecorder()
        let service = CollectionMutationService(
            dependencies: dependencies(effects: effects)
        )

        XCTAssertTrue(
            service.rename(
                collection,
                to: "  Trail Finds  ",
                in: context
            )
        )
        XCTAssertEqual(collection.name, "Trail Finds")
        XCTAssertEqual(effects.values, ["save", "sync", "success"])
    }

    func testDeleteUsesDurableSyncBoundary() throws {
        let context = try makeContext()
        let collection = ScanCollection(name: "Wetlands")
        context.insert(collection)
        try context.save()

        let effects = CollectionEffectsRecorder()
        let service = CollectionMutationService(
            dependencies: dependencies(effects: effects)
        )

        XCTAssertTrue(service.delete(collection, in: context))
        XCTAssertTrue(collection.isPendingDeletion)
        XCTAssertEqual(effects.values, ["save", "sync"])
    }

    func testReservedAndDuplicateNamesAreRejectedBeforeSave() throws {
        let context = try makeContext()
        let birds = ScanCollection(name: "Birds")
        let other = ScanCollection(name: "Other")
        context.insert(birds)
        context.insert(other)
        try context.save()

        let effects = CollectionEffectsRecorder()
        let service = CollectionMutationService(
            dependencies: dependencies(effects: effects)
        )

        XCTAssertNil(
            service.create(name: " favorites ", in: context)
        )
        XCTAssertFalse(
            service.rename(other, to: " bÍrds ", in: context)
        )
        XCTAssertEqual(other.name, "Other")
        XCTAssertEqual(effects.values, ["error", "error"])
    }

    func testFavoritesCannotBeRenamedOrDeleted() throws {
        let context = try makeContext()
        let favorites = ScanCollection(name: "Favorites")
        context.insert(favorites)
        try context.save()

        let effects = CollectionEffectsRecorder()
        let service = CollectionMutationService(
            dependencies: dependencies(effects: effects)
        )

        XCTAssertFalse(
            service.rename(
                favorites,
                to: "Renamed Favorites",
                in: context
            )
        )
        XCTAssertFalse(service.delete(favorites, in: context))
        XCTAssertEqual(favorites.name, "Favorites")
        XCTAssertFalse(favorites.isPendingDeletion)
        XCTAssertEqual(effects.values, ["error", "error"])
    }

    func testFailedCreateRestoresRelatedRecordBeforeRollback() throws {
        let context = try makeContext()
        let record = makeRecord(id: "record")
        context.insert(record)
        try context.save()

        let effects = CollectionEffectsRecorder()
        let service = CollectionMutationService(
            dependencies: failingDependencies(effects: effects)
        )

        XCTAssertNil(
            service.create(
                name: "Wetlands",
                relatedRecordID: record.id,
                in: context
            )
        )
        XCTAssertTrue(record.collections?.isEmpty ?? true)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ScanCollection>()).isEmpty)
        XCTAssertEqual(effects.values, ["save", "rollback"])
    }

    func testFailedRenameRestoresOriginalNameBeforeRollback() throws {
        let context = try makeContext()
        let collection = ScanCollection(name: "Wetlands")
        context.insert(collection)
        try context.save()

        let effects = CollectionEffectsRecorder()
        let service = CollectionMutationService(
            dependencies: failingDependencies(effects: effects)
        )

        XCTAssertFalse(
            service.rename(
                collection,
                to: "Prairie",
                in: context
            )
        )
        XCTAssertEqual(collection.name, "Wetlands")
        XCTAssertEqual(effects.values, ["save", "rollback"])
    }

    func testFailedDeleteRestoresTombstoneBeforeRollback() throws {
        let context = try makeContext()
        let collection = ScanCollection(name: "Wetlands")
        context.insert(collection)
        try context.save()

        let effects = CollectionEffectsRecorder()
        let service = CollectionMutationService(
            dependencies: failingDependencies(effects: effects)
        )

        XCTAssertFalse(service.delete(collection, in: context))
        XCTAssertFalse(collection.isPendingDeletion)
        XCTAssertEqual(effects.values, ["save", "rollback"])
    }

    func testMembershipCommitsSaveThenInvalidateThenEnqueue() throws {
        let context = try makeContext()
        let collection = ScanCollection(name: "Wetlands")
        let record = makeRecord(id: "record")
        context.insert(collection)
        context.insert(record)
        try context.save()

        let effects = CollectionEffectsRecorder()
        let service = CollectionMutationService(
            dependencies: dependencies(effects: effects)
        )

        XCTAssertEqual(
            service.toggle(record, in: collection, in: context),
            .added
        )
        XCTAssertEqual(record.collections?.map(\.id), [collection.id])
        XCTAssertEqual(effects.values, ["save", "event", "sync"])

        effects.values.removeAll()
        XCTAssertEqual(
            service.remove(record, from: collection, in: context),
            .removed
        )
        XCTAssertEqual(record.collections, [])
        XCTAssertEqual(effects.values, ["save", "event", "sync"])

        effects.values.removeAll()
        XCTAssertEqual(
            service.remove(record, from: collection, in: context),
            .unchanged
        )
        XCTAssertTrue(effects.values.isEmpty)
    }

    func testFailedMembershipSaveRollsBackWithoutInvalidationOrSync() throws {
        let context = try makeContext()
        let collection = ScanCollection(name: "Wetlands")
        let record = makeRecord(id: "record")
        context.insert(collection)
        context.insert(record)
        try context.save()

        let effects = CollectionEffectsRecorder()
        let service = CollectionMutationService(
            dependencies: failingDependencies(effects: effects)
        )

        XCTAssertEqual(
            service.toggle(record, in: collection, in: context),
            .failed
        )
        XCTAssertEqual(effects.values, ["save", "rollback", "error"])
        XCTAssertFalse(
            record.collections?.contains { $0.id == collection.id } == true
        )
    }

    func testFailedRemovalRestoresMembershipWithoutInvalidationOrSync() throws {
        let context = try makeContext()
        let collection = ScanCollection(name: "Wetlands")
        let record = makeRecord(id: "record")
        record.collections = [collection]
        context.insert(collection)
        context.insert(record)
        try context.save()

        let effects = CollectionEffectsRecorder()
        let service = CollectionMutationService(
            dependencies: failingDependencies(effects: effects)
        )

        XCTAssertEqual(
            service.remove(record, from: collection, in: context),
            .failed
        )
        XCTAssertEqual(effects.values, ["save", "rollback"])
        XCTAssertTrue(
            record.collections?.contains { $0.id == collection.id } == true
        )
    }

    private func failingDependencies(
        effects: CollectionEffectsRecorder
    ) -> CollectionsDependencies {
        CollectionsDependencies(
            save: { _ in
                effects.values.append("save")
                throw ExpectedSaveFailure.expected
            },
            rollback: { modelContext in
                effects.values.append("rollback")
                modelContext.rollback()
            },
            sendLibraryChanged: {
                effects.values.append("event")
            },
            enqueueCollectionSync: {
                effects.values.append("sync")
            },
            triggerSuccessFeedback: {
                effects.values.append("success")
            },
            triggerErrorFeedback: {
                effects.values.append("error")
            }
        )
    }

    private func dependencies(
        effects: CollectionEffectsRecorder
    ) -> CollectionsDependencies {
        CollectionsDependencies(
            save: { modelContext in
                effects.values.append("save")
                try modelContext.save()
            },
            rollback: { modelContext in
                effects.values.append("rollback")
                modelContext.rollback()
            },
            sendLibraryChanged: {
                effects.values.append("event")
            },
            enqueueCollectionSync: {
                effects.values.append("sync")
            },
            triggerSuccessFeedback: {
                effects.values.append("success")
            },
            triggerErrorFeedback: {
                effects.values.append("error")
            }
        )
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        return ModelContext(container)
    }

    private func makeRecord(id: String) -> LocalScanRecord {
        LocalScanRecord(
            id: id,
            speciesId: "species-\(id)",
            scientificName: "Species \(id)",
            commonName: "Species \(id)",
            timestamp: Date(timeIntervalSinceReferenceDate: 1),
            isBiological: true
        )
    }
}

private enum ExpectedSaveFailure: Error {
    case expected
}

@MainActor
final class CollectionEffectsRecorder {
    var values: [String] = []
}
