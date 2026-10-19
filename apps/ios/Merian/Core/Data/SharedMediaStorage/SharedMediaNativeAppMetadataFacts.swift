import Foundation
import SwiftData

/// Bounded pending facts captured only after the operation's complete audit.
/// Values never authorize mutation. Retained consumers are not enumerated here.
struct SharedMediaNativeAppMetadataFacts: Equatable, Sendable {
    struct Package: Equatable, Sendable {
        let id: UUID, ownerID: UUID, draftID: UUID, generation: UUID
        let contract: String, tier: String, phase: String
        let revision: Int64, allocated: Int64
        let retiring: Bool
        let envelope: Data
        @MainActor init(_ row: PhotoPreparationRecord) {
            id = row.id; ownerID = row.ownerID; draftID = row.draftID; generation = row.draftGeneration
            contract = row.contractVersion; tier = row.accountingTierRaw; phase = row.phaseRaw
            revision = row.revision; allocated = row.allocatedByteCount; retiring = row.retirementRequested
            envelope = row.supportingContextData
        }
        private init(_ old: Self, envelope: Data, revision: Int64) {
            id = old.id; ownerID = old.ownerID; draftID = old.draftID; generation = old.generation
            contract = old.contract; tier = old.tier; phase = old.phase; allocated = old.allocated
            retiring = old.retiring; self.envelope = envelope; self.revision = revision
        }
        func successor(_ bytes: Data) throws -> Self {
            .init(self, envelope: bytes, revision: try SharedMediaStoragePolicy.add(revision, 1))
        }
    }
    struct Member: Equatable, Sendable {
        let id: UUID, inventoryID: UUID, inventoryGeneration: UUID, ownerID: UUID, draftGeneration: UUID
        let revision: Int64
        let bytes: Data
        @MainActor init(_ row: SharedMediaPendingMembershipRecord) {
            id = row.id; inventoryID = row.inventoryID; inventoryGeneration = row.inventoryGeneration
            ownerID = row.ownerID; draftGeneration = row.draftGeneration; revision = row.revision; bytes = row.membersData
        }
    }
    struct Consumer: Equatable, Sendable {
        // Include every scalar field and the exact cohort bytes, not just a hash.
        let fields: [String]
        let cohort: Data
        @MainActor init(_ row: SharedMediaConsumerRecord) {
            fields = [row.id.uuidString, row.cursorKey, row.kindRaw, row.consumerID, row.originQueueID, row.observationID,
                row.inventoryID.uuidString, row.inventoryGeneration.uuidString, row.ownerID.uuidString, row.packageID.uuidString,
                row.draftGeneration.uuidString, String(row.frozenPackageRevision), row.contractVersion, String(row.digestVersion),
                row.cohortSHA256, row.executionKindRaw, row.inferenceGeneration?.uuidString ?? "", row.retirementID?.uuidString ?? "",
                row.lifecycleRaw, String(row.revision)]
            cohort = row.cohortData
        }
    }
    let profile: SharedMediaNativeAppProfile
    let bootstrapRevision: Int64
    let packages: [UUID: Package]
    let members: [UUID: Member]
    let consumers: [UUID: Consumer]

    @MainActor static func capture(_ context: ModelContext, profile: SharedMediaNativeAppProfile) throws -> Self {
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        return try read(context, profile: profile)
    }
    @MainActor private static func read(_ context: ModelContext, profile: SharedMediaNativeAppProfile) throws -> Self {
        let inventoryID = profile.inventoryID
        var query = FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.inventoryID == inventoryID })
        query.fetchLimit = PhotoPreparationPolicy.maximumPackages + 1; query.includePendingChanges = true
        let rows = try context.fetch(query)
        guard rows.count <= PhotoPreparationPolicy.maximumPackages else { throw SharedMediaStorageFailure.capacity }
        let bootstrap = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaMembershipBootstrapRecord>(predicate: #Predicate { $0.id == inventoryID }))
        guard bootstrap.inventoryGeneration == profile.generation, bootstrap.contractVersion == 2, bootstrap.revision >= 0 else { throw SharedMediaStorageFailure.conflict }
        var packages: [UUID: Package] = [:], members: [UUID: Member] = [:], consumers: [UUID: Consumer] = [:]
        for row in rows {
            let id = row.id
            var packageQuery = FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id })
            packageQuery.fetchLimit = 2; packageQuery.includePendingChanges = true
            let values = try context.fetch(packageQuery)
            guard values.count == 1, let package = values.first, packages[id] == nil,
                  row.inventoryGeneration == profile.generation, row.ownerID == profile.ownerID,
                  package.ownerID == profile.ownerID, package.draftGeneration == row.draftGeneration,
                  package.accountingTierRaw == "pending", row.revision >= 0 else { throw SharedMediaStorageFailure.conflict }
            packages[id] = Package(package); members[id] = Member(row)
            if let consumer = try SharedMediaConsumerLookup.one(context, packageID: id) {
                guard consumer.kindRaw == "queue", consumer.ownerID == profile.ownerID,
                      consumer.inventoryID == inventoryID, consumer.inventoryGeneration == profile.generation else { throw SharedMediaStorageFailure.conflict }
                consumers[id] = Consumer(consumer)
            }
        }
        return .init(profile: profile, bootstrapRevision: bootstrap.revision, packages: packages, members: members, consumers: consumers)
    }
    @MainActor func validate(_ context: ModelContext, replacing request: SharedMediaNativeAppMetadataRequest) throws {
        let current = try Self.read(context, profile: profile)
        var expectedPackages = packages
        guard request.profile == profile, packages[request.package.id] == request.package,
              members[request.package.id] == request.member, consumers[request.package.id] == nil else { throw SharedMediaStorageFailure.conflict }
        expectedPackages[request.package.id] = try request.package.successor(request.envelope)
        guard current.bootstrapRevision == bootstrapRevision, current.members == members,
              current.packages == expectedPackages, current.consumers == consumers else { throw SharedMediaStorageFailure.conflict }
    }
    @MainActor static func requireWriteSet(_ context: ModelContext, inventory: PersistentIdentifier, package: PersistentIdentifier) throws {
        let changed = context.changedModelsArray.map(\.persistentModelID)
        guard context.insertedModelsArray.isEmpty, context.deletedModelsArray.isEmpty, changed.count == 2,
              Set(changed) == Set([inventory, package]) else { throw SharedMediaStorageFailure.conflict }
    }
    static func successor(_ old: SharedMediaNativeAppEligibility.Header) throws -> SharedMediaNativeAppEligibility.Header {
        .init(inventory: .init(generation: old.inventory.generation,
            revision: try SharedMediaStoragePolicy.add(old.inventory.revision, 1), phase: old.inventory.phase, cursor: old.inventory.cursor),
            bootstrapID: old.bootstrapID, bootstrapGeneration: old.bootstrapGeneration,
            bootstrapContract: old.bootstrapContract, bootstrapRevision: old.bootstrapRevision)
    }
}
