import Foundation
import SwiftData

@MainActor
struct CollectionMutationService {
    enum MembershipOutcome: Equatable {
        case added
        case removed
        case unchanged
        case failed

        var didCommit: Bool {
            self == .added || self == .removed
        }
    }

    private let dependencies: CollectionsDependencies

    init(dependencies: CollectionsDependencies? = nil) {
        self.dependencies = dependencies ?? .live
    }

    func create(
        name input: String,
        relatedRecordID: String? = nil,
        in modelContext: ModelContext
    ) -> ScanCollection? {
        guard let name = validatedName(
            input,
            allowUntitledFallback: true,
            excludingCollectionID: nil,
            in: modelContext
        ) else { return nil }

        let collection = ScanCollection(name: name)
        modelContext.insert(collection)

        let record = relatedRecordID.flatMap {
            relatedRecord(
                id: $0,
                in: modelContext
            )
        }
        let originalCollections = record?.collections
        if let record {
            var collections = originalCollections ?? []
            collections.append(collection)
            record.collections = collections
        }

        guard commit(
            in: modelContext,
            operation: "creating collection",
            restoring: {
                record?.collections = originalCollections
            }
        ) else { return nil }

        dependencies.enqueueCollectionSync()
        dependencies.triggerSuccessFeedback()
        return collection
    }

    func rename(
        _ collection: ScanCollection,
        to input: String,
        in modelContext: ModelContext
    ) -> Bool {
        guard canMutateSystemCollection(
            collection,
            operation: "rename"
        ) else { return false }
        guard let name = validatedName(
            input,
            allowUntitledFallback: false,
            excludingCollectionID: collection.id,
            in: modelContext
        ) else { return false }
        guard collection.name != name else { return false }

        let originalName = collection.name
        collection.name = name
        guard commit(
            in: modelContext,
            operation: "renaming collection",
            restoring: {
                collection.name = originalName
            }
        ) else { return false }

        dependencies.enqueueCollectionSync()
        dependencies.triggerSuccessFeedback()
        return true
    }

    func delete(
        _ collection: ScanCollection,
        in modelContext: ModelContext
    ) -> Bool {
        guard canMutateSystemCollection(
            collection,
            operation: "delete"
        ) else { return false }
        guard !collection.isPendingDeletion else { return false }

        let wasPendingDeletion = collection.isPendingDeletion
        collection.isPendingDeletion = true
        guard commit(
            in: modelContext,
            operation: "deleting collection",
            restoring: {
                collection.isPendingDeletion = wasPendingDeletion
            }
        ) else { return false }

        dependencies.enqueueCollectionSync()
        return true
    }

    func remove(
        _ scan: LocalScanRecord,
        from collection: ScanCollection,
        in modelContext: ModelContext
    ) -> MembershipOutcome {
        let originalCollections = scan.collections
        var collections = originalCollections ?? []
        let originalCount = collections.count
        collections.removeAll { $0.id == collection.id }
        guard collections.count != originalCount else { return .unchanged }

        scan.collections = collections
        guard commit(
            in: modelContext,
            operation: "removing scan from collection",
            restoring: {
                scan.collections = originalCollections
            }
        ) else { return .failed }

        publishMembershipCommit()
        return .removed
    }

    func toggle(
        _ scan: LocalScanRecord,
        in collection: ScanCollection,
        in modelContext: ModelContext
    ) -> MembershipOutcome {
        let originalCollections = scan.collections
        var collections = originalCollections ?? []
        let outcome: MembershipOutcome

        if collections.contains(where: { $0.id == collection.id }) {
            collections.removeAll { $0.id == collection.id }
            outcome = .removed
        } else {
            collections.append(collection)
            outcome = .added
        }
        scan.collections = collections

        guard commit(
            in: modelContext,
            operation: "updating collection membership",
            restoring: {
                scan.collections = originalCollections
            }
        ) else {
            dependencies.triggerErrorFeedback()
            return .failed
        }

        publishMembershipCommit()
        return outcome
    }

    func triggerDestructiveFeedback() {
        dependencies.triggerErrorFeedback()
    }

    private func publishMembershipCommit() {
        dependencies.sendLibraryChanged()
        dependencies.enqueueCollectionSync()
    }

    private func commit(
        in modelContext: ModelContext,
        operation: String,
        restoring restoreChanges: () -> Void = {}
    ) -> Bool {
        do {
            try dependencies.save(modelContext)
            return true
        } catch {
            restoreChanges()
            dependencies.rollback(modelContext)
            MerianLog.data.error(
                "CollectionMutationService: failed \(operation, privacy: .public): \(error, privacy: .private)"
            )
            return false
        }
    }

    private func validatedName(
        _ input: String,
        allowUntitledFallback: Bool,
        excludingCollectionID: String?,
        in modelContext: ModelContext
    ) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty && allowUntitledFallback
            ? "Untitled"
            : trimmed

        guard !name.isEmpty else {
            dependencies.triggerErrorFeedback()
            return nil
        }

        guard !isReservedName(name) else {
            dependencies.triggerErrorFeedback()
            MerianLog.data.debug(
                "CollectionMutationService: blocked reserved collection name Favorites"
            )
            return nil
        }

        var descriptor = FetchDescriptor<ScanCollection>(
            predicate: #Predicate { !$0.isPendingDeletion }
        )
        descriptor.fetchLimit = 500
        let existingCollections = (try? modelContext.fetch(descriptor)) ?? []
        let hasDuplicate = existingCollections.contains { existing in
            guard existing.id != excludingCollectionID else { return false }
            return existing.name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(
                    name,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) == .orderedSame
        }

        guard !hasDuplicate else {
            dependencies.triggerErrorFeedback()
            MerianLog.data.debug(
                "CollectionMutationService: blocked duplicate collection name \(name, privacy: .private)"
            )
            return nil
        }

        return name
    }

    private func canMutateSystemCollection(
        _ collection: ScanCollection,
        operation: String
    ) -> Bool {
        guard !isReservedName(collection.name) else {
            dependencies.triggerErrorFeedback()
            MerianLog.data.debug(
                "CollectionMutationService: blocked \(operation, privacy: .public) of protected Favorites collection"
            )
            return false
        }
        return true
    }

    private func isReservedName(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).compare(
            "Favorites",
            options: [.caseInsensitive, .diacriticInsensitive]
        ) == .orderedSame
    }

    private func relatedRecord(
        id recordID: String,
        in modelContext: ModelContext
    ) -> LocalScanRecord? {
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == recordID }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }
}
