import Foundation
import SwiftData

/// Bounded pending facts captured only after the operation's complete audit.
/// Values never authorize mutation. Retained consumers are not enumerated here.
struct SharedMediaNativeAppMetadataFacts: Equatable, Sendable {
    struct Package: Codable, Equatable, Sendable {
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
        private init(_ old: Self, envelope: Data, revision: Int64, phase: String, allocated: Int64) {
            id = old.id; ownerID = old.ownerID; draftID = old.draftID; generation = old.generation
            contract = old.contract; tier = old.tier; self.phase = phase; self.allocated = allocated
            retiring = old.retiring; self.envelope = envelope; self.revision = revision
        }
        func successor(_ bytes: Data, phase: String? = nil, allocated: Int64? = nil) throws -> Self {
            .init(self, envelope: bytes, revision: try SharedMediaStoragePolicy.add(revision, 1), phase: phase ?? self.phase, allocated: allocated ?? self.allocated)
        }
    }
    struct Member: Codable, Equatable, Sendable {
        let id: UUID, inventoryID: UUID, inventoryGeneration: UUID, ownerID: UUID, draftGeneration: UUID
        let revision: Int64
        let bytes: Data
        @MainActor init(_ row: SharedMediaPendingMembershipRecord) {
            id = row.id; inventoryID = row.inventoryID; inventoryGeneration = row.inventoryGeneration
            ownerID = row.ownerID; draftGeneration = row.draftGeneration; revision = row.revision; bytes = row.membersData
        }
        private init(_ old: Self, bytes: Data, revision: Int64) {
            id = old.id; inventoryID = old.inventoryID; inventoryGeneration = old.inventoryGeneration
            ownerID = old.ownerID; draftGeneration = old.draftGeneration; self.bytes = bytes; self.revision = revision
        }
        func successor(_ bytes: Data) throws -> Self {
            .init(self, bytes: bytes, revision: try SharedMediaStoragePolicy.add(revision, 1))
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
    let intents: [UUID: SharedMediaNativeReceivingIntentGraph.Row]

    func requireMutable(_ packageID: UUID) throws {
        guard intents[packageID] == nil else { throw SharedMediaStorageFailure.closed }
    }

    @MainActor static func capture(_ context: ModelContext, profile: SharedMediaNativeAppProfile) throws -> Self {
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        return try read(context, profile: profile)
    }
    @MainActor static func acquisitionPoststate(_ context: ModelContext, inventory: SharedMediaInventoryRecord,
                                                proof: SharedMediaNativeAppAcquisitionPoststate) throws -> Self {
        try proof.validate(context: context, inventory: inventory)
        return try read(context, profile: proof.profile)
    }
    @MainActor static func preparationPoststate(_ context: ModelContext, inventory: SharedMediaInventoryRecord,
                                                proof: SharedMediaNativeAppPreparationPoststate) throws -> Self {
        try proof.validate(context: context, inventory: inventory)
        return try read(context, profile: proof.profile)
    }
    @MainActor func validatePreparation(_ context: ModelContext, package: Package) throws {
        try requireMutable(package.id)
        let current = try Self.read(context, profile: profile)
        guard current.intents == intents else { throw SharedMediaStorageFailure.conflict }
        var expected = packages
        guard expected[package.id] != nil, consumers[package.id] == nil else { throw SharedMediaStorageFailure.closed }
        expected[package.id] = package
        guard current.bootstrapRevision == bootstrapRevision, current.members == members,
              current.packages == expected, current.consumers == consumers else { throw SharedMediaStorageFailure.conflict }
    }
    @MainActor static func pairPlanPoststate(_ context: ModelContext, inventory: SharedMediaInventoryRecord,
                                            proof: SharedMediaNativeAppPairPlanPoststate) throws -> Self {
        try proof.validate(context: context, inventory: inventory)
        return try read(context, profile: proof.profile)
    }
    @MainActor func validatePairPlan(_ context: ModelContext, package: Package, member: Member) throws {
        try requireMutable(package.id)
        let current = try Self.read(context, profile: profile)
        guard current.intents == intents else { throw SharedMediaStorageFailure.conflict }
        var nextPackages = packages, nextMembers = members
        guard packages[package.id] != nil, members[package.id] != nil, member.id == package.id,
              consumers[package.id] == nil else { throw SharedMediaStorageFailure.closed }
        nextPackages[package.id] = package; nextMembers[package.id] = member
        guard current.bootstrapRevision == bootstrapRevision, current.consumers == consumers,
              current.packages == nextPackages, current.members == nextMembers else { throw SharedMediaStorageFailure.conflict }
    }
    @MainActor func validateReceiving(_ context: ModelContext, request: SharedMediaNativeAppReceivingRequest) throws {
        try requireMutable(request.package.id)
        let current = try Self.read(context, profile: profile)
        guard current.intents == intents else { throw SharedMediaStorageFailure.conflict }
        var expectedPackages = packages, expectedConsumers = consumers
        guard request.profile == profile, packages[request.package.id] == request.package,
              members[request.package.id] == request.member, consumers[request.package.id] == nil,
              let row = try SharedMediaConsumerLookup.one(context, packageID: request.package.id),
              let rows = try SharedMediaNativeReceivingRows.read(request, in: context, absent: false),
              rows.consumer.persistentModelID == row.persistentModelID else { throw SharedMediaStorageFailure.conflict }
        expectedPackages[request.package.id] = try request.frozenPackage()
        expectedConsumers[request.package.id] = Consumer(row)
        guard current.bootstrapRevision == bootstrapRevision, current.members == members,
              current.packages == expectedPackages, current.consumers == expectedConsumers else { throw SharedMediaStorageFailure.conflict }
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
        return .init(profile: profile, bootstrapRevision: bootstrap.revision, packages: packages, members: members, consumers: consumers,
            intents: try SharedMediaNativeReceivingIntentGraph.snapshots(context))
    }
    @MainActor func validate(_ context: ModelContext, replacing request: SharedMediaNativeAppMetadataRequest) throws {
        try requireMutable(request.package.id)
        let current = try Self.read(context, profile: profile)
        guard current.intents == intents else { throw SharedMediaStorageFailure.conflict }
        var expectedPackages = packages
        guard request.profile == profile, packages[request.package.id] == request.package,
              members[request.package.id] == request.member, consumers[request.package.id] == nil else { throw SharedMediaStorageFailure.conflict }
        expectedPackages[request.package.id] = try request.package.successor(request.envelope)
        guard current.bootstrapRevision == bootstrapRevision, current.members == members,
              current.packages == expectedPackages, current.consumers == consumers else { throw SharedMediaStorageFailure.conflict }
    }
    /// Acquisition may change one package and its member. Every other pending
    /// row and every receiving consumer remains byte-for-byte equal.
    @MainActor func validateAcquisition(_ context: ModelContext, packageID: UUID, hasMember: Bool) throws {
        try requireMutable(packageID)
        let current = try Self.read(context, profile: profile)
        guard current.intents == intents else { throw SharedMediaStorageFailure.conflict }
        guard current.bootstrapRevision == bootstrapRevision, current.consumers == consumers,
              consumers[packageID] == nil,
              current.packages.filter({ $0.key != packageID }) == packages.filter({ $0.key != packageID }),
              current.members.filter({ $0.key != packageID }) == members.filter({ $0.key != packageID }),
              (current.members[packageID] != nil) == hasMember else { throw SharedMediaStorageFailure.conflict }
    }
    @MainActor func validateStaging(_ context: ModelContext, adding row: SharedMediaNativeReceivingIntentGraph.Row) throws {
        try requireMutable(row.id)
        let current = try Self.read(context, profile: profile)
        var expected = intents
        expected[row.id] = row
        guard current.profile == profile, current.bootstrapRevision == bootstrapRevision,
              current.packages == packages, current.members == members, current.consumers == consumers,
              current.intents == expected else { throw SharedMediaStorageFailure.conflict }
    }
    @MainActor func receivingBytes(_ consumer: SharedMediaConsumerRecord) throws -> Int64 {
        guard consumers[consumer.packageID] == Consumer(consumer) else { throw SharedMediaStorageFailure.conflict }
        return Int64(consumer.cohortData.count)
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
