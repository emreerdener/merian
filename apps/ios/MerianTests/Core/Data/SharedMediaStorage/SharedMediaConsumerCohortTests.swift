import CryptoKit
import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite(.serialized)
@MainActor
struct SharedMediaConsumerCohortTests {
    @Test func digestMatchesFixedContractVector() throws {
        func id(_ suffix: Int) -> UUID {
            UUID(uuidString: "00000000-0000-0000-0000-" + String(format: "%012x", suffix))!
        }
        let context = Data("[]".utf8)
        let cohort = SharedMediaConsumerCohort(version: 1, inventoryID: id(1), inventoryGeneration: id(2),
            ownerID: id(3), packageID: id(4), draftGeneration: id(5), packageRevision: 1,
            contextSHA256: SHA256.hash(data: context).map { String(format: "%02x", $0) }.joined(),
            entries: ["original", "aiInput", "display"].enumerated().map { index, role in
                .init(role: role, ordinal: 0, referenceID: id(10 + index), referenceRevision: 0,
                    assetID: id(20 + index), assetGeneration: id(30 + index), pairID: id(40),
                    workID: index == 0 ? nil : id(50 + index), byteCount: 1, sha256: String(repeating: "a", count: 64),
                    contentType: "image/jpeg", physicalIdentity: "fixture-" + role)
            })
        // Independently calculated with big-endian UInt64 framing and Int64 fields.
        #expect(try cohort.digest(context: context) == "e289b93b7f4255c7cb0030467cab1b8b876638d6c6cd04c05a05811d62f1b8dc")
    }

    @Test func metadataIsCanonicalBoundedAndSharesOneAllowance() throws {
        let id = UUID()
        let valid = try SharedMediaMembership(groups: [.init(kind: .asset, ids: [id])])
        #expect(try SharedMediaMembership.decode(valid.encoded()) == valid)
        #expect(throws: SharedMediaStorageFailure.conflict) {
            try SharedMediaMembership(groups: [.init(kind: .asset, ids: [id, id])])
        }
        #expect(throws: SharedMediaStorageFailure.conflict) {
            try SharedMediaMembership(groups: [.init(kind: .asset, ids: [])])
        }
        #expect(throws: SharedMediaStorageFailure.conflict) {
            try SharedMediaMembership(groups: [.init(kind: .asset, ids: [id]), .init(kind: .asset, ids: [UUID()])])
        }
        #expect(throws: SharedMediaStorageFailure.conflict) {
            try SharedMediaMembership.decode(Data(" ".utf8) + valid.encoded())
        }
        #expect(throws: SharedMediaStorageFailure.capacity) {
            try SharedMediaMembership.decode(Data(count: Int(PhotoPreparationPolicy.metadata) + 1))
        }
        let context = Data(count: Int(PhotoPreparationPolicy.metadata) - 2)
        try SharedMediaMembership.requireMetadataBudget(context: context, membership: Data(count: 1), cohort: Data(count: 1))
        #expect(throws: SharedMediaStorageFailure.capacity) {
            try SharedMediaMembership.requireMetadataBudget(context: context, membership: Data(count: 2), cohort: Data(count: 1))
        }
    }

    @Test func cohortRejectsUnknownVersionsOrderingAndAggregateOverflow() throws {
        let fixture = try Fixture()
        let cohort = fixture.cohort
        #expect(try SharedMediaConsumerCohort.decode(cohort.encoded()) == cohort)
        var object = try #require(JSONSerialization.jsonObject(with: cohort.encoded()) as? [String: Any])
        object["version"] = 2
        #expect(throws: SharedMediaStorageFailure.conflict) { try Self.decode(object) }
        object["version"] = 1
        var entries = try #require(object["entries"] as? [[String: Any]])
        entries.swapAt(0, 1); object["entries"] = entries
        #expect(throws: SharedMediaStorageFailure.conflict) { try Self.decode(object) }
        entries.swapAt(0, 1)
        entries[1]["byteCount"] = PhotoPreparationPolicy.aiCohort + 1
        object["entries"] = entries
        #expect(throws: SharedMediaStorageFailure.conflict) { try Self.decode(object) }
        // Digest includes ordered bytes, inode assertion, and immutable context.
        entries[1]["byteCount"] = 17
        entries[1]["physicalIdentity"] = "synthetic-different-inode"
        object["entries"] = entries
        #expect(try Self.decode(object).digest(context: fixture.supporting) != cohort.digest(context: fixture.supporting))
        object["contextSHA256"] = String(repeating: "b", count: 64)
        #expect(throws: SharedMediaStorageFailure.conflict) { try Self.decode(object).digest(context: fixture.supporting) }
    }

    @Test func diskCohortJoinsSurviveReopenAndRejectSubstitution() throws {
        let fixture = try Fixture()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("consumer-cohort-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Preserve the synthetic SQLite store through process exit for Core Data WAL handles.
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let configuration = ModelConfiguration(schema: schema, url: root.appendingPathComponent("fixture.store"))
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container); context.autosaveEnabled = false
            try fixture.insert(context)
            try context.save()
        }
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container); context.autosaveEnabled = false
        let consumer = try #require(try SharedMediaConsumerLookup.one(context, packageID: fixture.cohort.packageID))
        #expect(try SharedMediaConsumerCohortLookup.validate(consumer, context: context) == fixture.cohort)
        for kind in ["scan", "unknown", "queue"] {
            consumer.kindRaw = kind
            #expect(throws: SharedMediaStorageFailure.conflict) { try SharedMediaConsumerCohortLookup.validate(consumer, context: context) }
        }
        consumer.kindRaw = "localScan"
        let assets = try context.fetch(FetchDescriptor<PhotoPreparationAsset>())
        let asset = try #require(assets.first)
        let oldHash = asset.sha256
        asset.sha256 = String(repeating: "c", count: 64)
        #expect(throws: SharedMediaStorageFailure.conflict) { try SharedMediaConsumerCohortLookup.validate(consumer, context: context) }
        asset.sha256 = oldHash
        let counter = try #require(context.fetch(FetchDescriptor<SharedMediaAssetReferenceCountRecord>()).first)
        counter.liveCount = 0
        #expect(throws: SharedMediaStorageFailure.conflict) { try SharedMediaConsumerCohortLookup.validate(consumer, context: context) }
        counter.liveCount = 1
        let extra = PhotoPreparationReference(id: UUID(), packageID: fixture.cohort.packageID,
            assetID: asset.id, ownerID: fixture.cohort.ownerID, roleRaw: "original", ordinal: 1, revision: 0, isLive: true)
        context.insert(extra)
        #expect(throws: SharedMediaStorageFailure.conflict) { try SharedMediaConsumerCohortLookup.validate(consumer, context: context) }
        context.delete(extra)
        let bootstrap = try #require(context.fetch(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()).first)
        context.delete(bootstrap)
        #expect(throws: SharedMediaStorageFailure.conflict) { try SharedMediaConsumerCohortLookup.validate(consumer, context: context) }
    }

    @Test func orphanMembershipMetadataBlocksLegacyCleanup() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let row = SharedMediaMembershipBootstrapRecord(inventoryID: UUID(), inventoryGeneration: UUID())
        context.insert(row); try context.save()
        #expect(try SharedMediaStorageRepository.hasLiabilities(in: context))
        #expect(throws: SharedMediaStorageFailure.inUse) { try SharedMediaPurgeState.requireEmptyGraph(context) }
        #expect(throws: PhotoPreparationFailure.unsupportedComposition) { _ = try PhotoPreparationRepository(container: container) }
    }

    @Test func pendingCohortRequiresEveryApplicableMemberAndRejectsExtras() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container); context.autosaveEnabled = false
        let fixture = try Fixture(); try fixture.insert(context)
        let package = try #require(context.fetch(FetchDescriptor<PhotoPreparationRecord>()).first)
        package.accountingTierRaw = "pending"
        let consumer = try #require(try SharedMediaConsumerLookup.one(context, packageID: package.id))
        consumer.kindRaw = "queue"
        let c = fixture.cohort
        func group(_ kind: SharedMediaMembership.Kind, _ ids: [UUID]) -> SharedMediaMembership.Group {
            .init(kind: kind, ids: Array(Set(ids)).sorted { $0.uuidString < $1.uuidString })
        }
        let groups = [group(.allocation, c.entries.map(\.assetID)), group(.asset, c.entries.map(\.assetID)),
            group(.derivative, c.entries.compactMap(\.workID)), group(.edge, c.entries.map(\.referenceID)),
            group(.lease, try context.fetch(FetchDescriptor<SharedMediaLeaseRecord>()).map(\.id)),
            group(.pair, c.entries.map(\.pairID)), group(.reference, c.entries.map(\.referenceID))]
        let member = SharedMediaPendingMembershipRecord(packageID: c.packageID, inventoryID: c.inventoryID,
            inventoryGeneration: c.inventoryGeneration, ownerID: c.ownerID, draftGeneration: c.draftGeneration,
            membersData: try SharedMediaMembership(groups: groups).encoded())
        context.insert(member); try context.save()
        #expect(try SharedMediaConsumerCohortLookup.validate(consumer, context: context) == c)
        for omitted in [SharedMediaMembership.Kind.allocation, .edge, .lease] {
            member.membersData = try SharedMediaMembership(groups: groups.filter { $0.kind != omitted }).encoded()
            #expect(throws: SharedMediaStorageFailure.conflict) { try SharedMediaConsumerCohortLookup.validate(consumer, context: context) }
        }
        member.membersData = try SharedMediaMembership(groups: groups + [group(.source, [UUID()])]).encoded()
        #expect(throws: SharedMediaStorageFailure.conflict) { try SharedMediaConsumerCohortLookup.validate(consumer, context: context) }
        let wrongLease = groups.map { $0.kind == .lease ? group(.lease, [UUID()]) : $0 }
        member.membersData = try SharedMediaMembership(groups: wrongLease).encoded()
        #expect(throws: SharedMediaStorageFailure.conflict) { try SharedMediaConsumerCohortLookup.validate(consumer, context: context) }
    }

    private static func decode(_ object: [String: Any]) throws -> SharedMediaConsumerCohort {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
        // Canonicalize using the production encoder so this tests semantic validation.
        let value = try JSONDecoder().decode(SharedMediaConsumerCohort.self, from: data)
        return try SharedMediaConsumerCohort.decode(value.encoded())
    }

    @MainActor
    private struct Fixture {
        let cohort: SharedMediaConsumerCohort
        let supporting: Data
        init() throws {
            supporting = try PhotoPreparationPolicy.encodeDraft(contexts: [])
            let pairID = UUID()
            cohort = .init(version: 1, inventoryID: UUID(), inventoryGeneration: UUID(), ownerID: UUID(),
                packageID: UUID(), draftGeneration: UUID(), packageRevision: 3,
                contextSHA256: SHA256.hash(data: supporting).map { String(format: "%02x", $0) }.joined(),
                entries: ["original", "aiInput", "display"].map { role in
                    .init(role: role, ordinal: 0, referenceID: UUID(), referenceRevision: 0, assetID: UUID(),
                        assetGeneration: UUID(), pairID: pairID, workID: role == "original" ? nil : UUID(),
                        byteCount: 17, sha256: String(repeating: "a", count: 64), contentType: "image/jpeg",
                        physicalIdentity: "synthetic-identity-" + role)
                })
        }

        func insert(_ context: ModelContext) throws {
            context.insert(SharedMediaInventoryRecord(id: cohort.inventoryID, rootIdentity: "synthetic-root", storeIdentity: "synthetic-store",
                generation: cohort.inventoryGeneration, revision: 0, modeRaw: "p1InboxQualification", phaseRaw: "readyP1", cursor: ""))
            context.insert(SharedMediaMembershipBootstrapRecord(inventoryID: cohort.inventoryID, inventoryGeneration: cohort.inventoryGeneration))
            let package = PhotoPreparationRecord(id: cohort.packageID, ownerID: cohort.ownerID, contractVersion: PhotoPreparationPolicy.contract,
                draftID: cohort.packageID, draftGeneration: cohort.draftGeneration, revision: cohort.packageRevision, phaseRaw: "preparedHeld",
                supportingContextData: supporting, allocatedByteCount: 51, retirementRequested: false)
            package.accountingTierRaw = "retained"; context.insert(package)
            let consumer = SharedMediaConsumerRecord(id: UUID(), kindRaw: "localScan", consumerID: "synthetic-scan", originQueueID: "synthetic-scan",
                observationID: "synthetic-scan", inventoryID: cohort.inventoryID, inventoryGeneration: cohort.inventoryGeneration,
                ownerID: cohort.ownerID, packageID: cohort.packageID, draftGeneration: cohort.draftGeneration,
                frozenPackageRevision: cohort.packageRevision, contractVersion: PhotoPreparationPolicy.contract, digestVersion: 1,
                cohortSHA256: try cohort.digest(context: supporting), executionKindRaw: "ordinaryV1", inferenceGeneration: UUID())
            consumer.cohortData = try cohort.encoded(); context.insert(consumer)
            let original = cohort.entries[0], ai = cohort.entries[1], display = cohort.entries[2]
            let pair = SharedMediaDerivativePairRecord(id: original.pairID, nonce: UUID(), inventoryID: cohort.inventoryID,
                inventoryGeneration: cohort.inventoryGeneration, expectedInventoryRevision: 0, ownerID: cohort.ownerID,
                packageID: cohort.packageID, draftGeneration: cohort.draftGeneration, originalReferenceID: original.referenceID,
                originalReferenceRevision: original.referenceRevision, originalAssetID: original.assetID,
                originalAssetGeneration: original.assetGeneration, ordinal: 0, expectedPackageRevision: 0,
                aiWorkID: try #require(ai.workID), displayWorkID: try #require(display.workID))
            pair.phaseRaw = "ready"; pair.publishedRevision = 2; context.insert(pair)
            for entry in cohort.entries {
                let token = cohort.ownerID.uuidString.lowercased() + "/" + cohort.packageID.uuidString.lowercased() + "/" + entry.assetID.uuidString.lowercased()
                let epoch = UUID(), leaseID = UUID()
                context.insert(PhotoPreparationAsset(id: entry.assetID, ownerID: cohort.ownerID, generation: entry.assetGeneration,
                    fileToken: token, contentType: entry.contentType, byteCount: entry.byteCount, sha256: entry.sha256,
                    acquisitionKindRaw: "synthetic", cleanupStateRaw: "ready"))
                context.insert(PhotoPreparationReference(id: entry.referenceID, packageID: cohort.packageID, assetID: entry.assetID,
                    ownerID: cohort.ownerID, roleRaw: entry.role, ordinal: entry.ordinal, revision: 0, isLive: true))
                context.insert(SharedMediaReferenceRecord(id: entry.referenceID, allocationID: entry.assetID, accountID: cohort.ownerID,
                    ownerID: entry.referenceID.uuidString.lowercased(), roleRaw: SharedMediaPhotoLedger.namespace, stateRaw: "live", revision: 0))
                context.insert(SharedMediaAllocationRecord(id: entry.assetID, inventoryID: cohort.inventoryID, accountID: cohort.ownerID,
                    packageID: cohort.packageID, namespaceRaw: SharedMediaPhotoLedger.namespace, fileToken: token, poolRaw: "durable",
                    stateRaw: entry.role == "original" ? "p1Materialized" : "p1DerivativeMaterialized",
                    materializedBytes: entry.byteCount, reservedBytes: 0, physicalIdentity: entry.physicalIdentity))
                context.insert(SharedMediaAssetReferenceCountRecord(assetID: entry.assetID, assetGeneration: entry.assetGeneration,
                    inventoryID: cohort.inventoryID, inventoryGeneration: cohort.inventoryGeneration, ownerID: cohort.ownerID, liveCount: 1))
                context.insert(SharedMediaLeaseRecord(id: leaseID, allocationID: entry.assetID, processEpoch: epoch,
                    purposeRaw: entry.role == "original" ? "p1AcquireV1" : "p1DerivativeV1", stateRaw: "closed"))
                if let workID = entry.workID {
                    let work = SharedMediaDerivativeWorkRecord(id: workID, pairID: entry.pairID, roleRaw: entry.role,
                        assetID: entry.assetID, assetGeneration: entry.assetGeneration, referenceID: entry.referenceID,
                        leaseID: leaseID, writerEpoch: epoch, byteCount: entry.byteCount, sha256: entry.sha256, contentType: entry.contentType)
                    work.phaseRaw = "completed"; work.writerStateRaw = "closed"; work.finalIdentity = entry.physicalIdentity
                    context.insert(work)
                }
            }
        }
    }
}
