import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite("Capture artifact ledger", .serialized)
@MainActor
struct SharedMediaCaptureArtifactLedgerTests {
    @MainActor final class Store {
        let directory: URL, container: ModelContainer, context: ModelContext
        let request: SharedMediaCaptureArtifactRequest
        let row: SharedMediaOrdinaryArtifactRecord
        let allocation: SharedMediaAllocationRecord, lease: SharedMediaLeaseRecord, reference: SharedMediaReferenceRecord
        let inventory: SharedMediaInventoryRecord
        init(phase: SharedMediaCaptureArtifactLedger.Phase = .reserved, request supplied: SharedMediaCaptureArtifactRequest? = nil,
             fullSchema: Bool = false) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let schema = fullSchema ? Schema(versionedSchema: CurrentSchema.self) : Schema([SharedMediaOrdinaryArtifactRecord.self, SharedMediaInventoryRecord.self,
                SharedMediaAllocationRecord.self, SharedMediaLeaseRecord.self, SharedMediaReferenceRecord.self, SharedMediaCaptureDraftJournalRecord.self,
                SharedMediaMembershipBootstrapRecord.self, PhotoPreparationAsset.self,
                SharedMediaAssetReferenceCountRecord.self, SharedMediaAcquisitionReceiptRecord.self,
                PhotoPreparationLease.self, PhotoPreparationReference.self, SharedMediaDerivativeWorkRecord.self])
            container = try ModelContainer(for: schema, configurations: [.init(schema: schema,
                url: directory.appendingPathComponent("capture.store"), cloudKitDatabase: .none)])
            context = ModelContext(container); context.autosaveEnabled = false
            let profile = supplied?.profile ?? SharedMediaNativeAppProfile(ownerID: UUID(), inventoryID: UUID(), generation: UUID(),
                storeIdentity: UUID().uuidString, physicalBinding: String(repeating: "a", count: 64),
                receiptDigest: String(repeating: "b", count: 64), physicalBindingFormat: .physicalRootsV1)
            request = try supplied ?? .init(id: UUID(), profile: profile, writerEpoch: UUID(), scanID: UUID(), submissionGeneration: UUID(),
                planSHA256: String(repeating: "c", count: 64), rootBindingSHA256: String(repeating: "d", count: 64),
                inventoryRevision: 4, mediaID: UUID(), itemIndex: 0, role: .sourceAudio, frameIndex: nil,
                contentType: "audio/wav", byteCount: 48, sha256: String(repeating: "e", count: 64),
                allocationID: UUID(), referenceID: UUID(), leaseID: UUID())
            row = .init(id: request.id, inventoryID: profile.inventoryID, inventoryGeneration: profile.generation,
                ownerID: profile.ownerID, recipientScanID: request.scanID, submissionGeneration: request.submissionGeneration,
                mediaID: request.mediaID, itemIndex: request.itemIndex, roleRaw: request.role.rawValue,
                frameIndex: nil, allocationID: request.allocationID, referenceID: request.referenceID,
                leaseID: request.leaseID, writerEpoch: request.writerEpoch, requestData: try request.encoded(), requestSHA256: try request.digest)
            inventory = .init(id: profile.inventoryID, rootIdentity: try profile.rootIdentity, storeIdentity: profile.storeIdentity,
                generation: profile.generation, revision: 5, modeRaw: SharedMediaNativeAppProfile.mode,
                phaseRaw: SharedMediaNativeAppProfile.phase, cursor: "")
            allocation = .init(id: request.allocationID, inventoryID: profile.inventoryID, accountID: profile.ownerID,
                packageID: request.scanID, namespaceRaw: SharedMediaCaptureRootJournal.namespace, fileToken: request.finalName,
                poolRaw: "durable", stateRaw: "reserved", materializedBytes: 0, reservedBytes: 48, physicalIdentity: nil)
            lease = .init(id: request.leaseID, allocationID: request.allocationID, processEpoch: request.writerEpoch,
                purposeRaw: SharedMediaCaptureArtifactLedger.leasePurpose, stateRaw: "open")
            reference = .init(id: request.referenceID, allocationID: request.allocationID, accountID: profile.ownerID,
                ownerID: request.id.uuidString.lowercased(), roleRaw: SharedMediaCaptureRootJournal.namespace, stateRaw: "held", revision: 0)
            context.insert(inventory); context.insert(row); context.insert(allocation); context.insert(lease); context.insert(reference)
            let bootstrap = SharedMediaMembershipBootstrapRecord(inventoryID: profile.inventoryID, inventoryGeneration: profile.generation)
            bootstrap.contractVersion = 2
            context.insert(bootstrap)
            if phase != .reserved {
                let ready = phase == .ready
                inventory.revision = ready ? 7 : 6
                let stage = try SharedMediaCaptureArtifactStage(request: request, inventoryRevision: inventory.revision,
                    partialIdentity: "1:20:0:100:1:100:1", finalIdentity: ready ? "1:20:48:101:1:101:1" : nil)
                row.phaseRaw = phase.rawValue; row.revision = ready ? 2 : 1
                row.stageReceiptData = try stage.encoded(request: request)
                row.stageReceiptSHA256 = SharedMediaAcquisitionEncoding.digest(try stage.encoded(request: request))
                allocation.stateRaw = phase.rawValue
                allocation.physicalIdentity = ready ? stage.finalIdentity : stage.partialIdentity
                if ready { allocation.reservedBytes = 0; allocation.materializedBytes = 48; lease.stateRaw = "closed" }
            }
            try context.save()
        }
        deinit { try? FileManager.default.removeItem(at: directory) }
        func read(context supplied: ModelContext? = nil) throws -> SharedMediaCaptureArtifactLedger.Snapshot {
            try SharedMediaCaptureArtifactLedger.read(id: request.id, profile: request.profile,
                rootBindingSHA256: request.rootBindingSHA256, context: supplied ?? context)
        }
    }

    @Test(arguments: [SharedMediaCaptureArtifactLedger.Phase.reserved, .writing, .ready])
    func savedPhasesRequireExactFreshJoins(_ phase: SharedMediaCaptureArtifactLedger.Phase) throws {
        let store = try Store(phase: phase), value = try store.read()
        #expect(value.phase == phase && value.request == store.request && value.metadataBytes > 0)
        let fresh = ModelContext(store.container); fresh.autosaveEnabled = false
        #expect(try store.read(context: fresh) == value)
        #expect(!fresh.hasChanges)
        #expect(throws: (any Error).self) { try SharedMediaStorageLookup.requireNoUnqualifiedCaptureArtifacts(fresh) }
    }

    @Test(arguments: ["role", "generation", "epoch", "stageHalf", "acceptance", "unknownPhase", "requestDigest", "revision"])
    func receiptRejectsScalarAndEnvelopeDrift(_ mutation: String) throws {
        let store = try Store()
        switch mutation {
        case "role": store.row.roleRaw = "source_video"
        case "generation": store.row.submissionGeneration = UUID()
        case "epoch": store.row.writerEpoch = UUID()
        case "stageHalf": store.row.stageReceiptSHA256 = String(repeating: "f", count: 64)
        case "acceptance": store.row.acceptanceData = Data([1])
        case "unknownPhase": store.row.phaseRaw = "accepted"
        case "requestDigest": store.row.requestSHA256 = String(repeating: "f", count: 64)
        case "revision": store.row.revision = 1
        default: Issue.record("Unknown mutation")
        }
        #expect(throws: (any Error).self) { _ = try SharedMediaCaptureArtifactLedger.receipt(store.row) }
    }

    @Test(arguments: ["allocation", "namespace", "fileToken", "owner", "epoch", "openLease", "reference", "inventory", "extraAllocation", "extraLease", "extraReference", "extraArtifact"])
    func readyArtifactRejectsIncompleteOrAliasedOwnership(_ mutation: String) throws {
        let store = try Store(phase: .ready)
        switch mutation {
        case "allocation": store.allocation.materializedBytes = 47
        case "namespace": store.allocation.namespaceRaw = SharedMediaPhotoLedger.namespace
        case "fileToken": store.allocation.fileToken = "../other"
        case "owner": store.reference.accountID = UUID()
        case "epoch": store.lease.processEpoch = UUID()
        case "openLease": store.lease.stateRaw = "open"
        case "reference": store.reference.stateRaw = "retired"
        case "inventory": store.inventory.revision = 6
        case "extraAllocation": store.context.insert(SharedMediaAllocationRecord(id: UUID(),
            inventoryID: store.request.profile.inventoryID, accountID: store.request.profile.ownerID,
            packageID: store.request.scanID, namespaceRaw: SharedMediaCaptureRootJournal.namespace,
            fileToken: store.request.finalName, poolRaw: "durable", stateRaw: "ready",
            materializedBytes: 48, reservedBytes: 0, physicalIdentity: store.allocation.physicalIdentity))
        case "extraLease": store.context.insert(SharedMediaLeaseRecord(id: UUID(), allocationID: store.request.allocationID,
            processEpoch: store.request.writerEpoch, purposeRaw: SharedMediaCaptureArtifactLedger.leasePurpose, stateRaw: "closed"))
        case "extraReference": store.context.insert(SharedMediaReferenceRecord(id: UUID(), allocationID: store.request.allocationID,
            accountID: store.request.profile.ownerID, ownerID: "other", roleRaw: SharedMediaCaptureRootJournal.namespace, stateRaw: "held", revision: 0))
        case "extraArtifact":
            let other = try Store()
            let row = other.row
            let extra = SharedMediaOrdinaryArtifactRecord(id: UUID(), inventoryID: row.inventoryID,
                inventoryGeneration: row.inventoryGeneration, ownerID: row.ownerID, recipientScanID: row.recipientScanID,
                submissionGeneration: row.submissionGeneration, mediaID: row.mediaID, itemIndex: row.itemIndex,
                roleRaw: row.roleRaw, frameIndex: nil, allocationID: store.request.allocationID,
                referenceID: row.referenceID, leaseID: row.leaseID, writerEpoch: row.writerEpoch,
                requestData: row.requestData, requestSHA256: row.requestSHA256)
            store.context.insert(extra)
        default: Issue.record("Unknown mutation")
        }
        #expect(throws: (any Error).self) { _ = try store.read() }
        try store.context.save()
        #expect(throws: (any Error).self) { _ = try store.read() }
    }

    @Test(arguments: ["1:21:48:101:1:101:1", "1:20:49:101:1:101:1", "1:20:48:101:1000000000:101:1", "1:020:48:101:1:101:1"])
    func completedDescriptorMustRetainTheReservedInode(_ descriptor: String) throws {
        let store = try Store()
        #expect(throws: (any Error).self) {
            _ = try SharedMediaCaptureArtifactStage(request: store.request, inventoryRevision: 7,
                partialIdentity: "1:20:0:100:1:100:1", finalIdentity: descriptor)
        }
    }

    @Test(arguments: ["trailing", "unknownKey", "partialChanged", "digest", "oversized"])
    func stageRejectsNoncanonicalOrChangedEvidence(_ mutation: String) throws {
        let store = try Store(phase: .ready)
        var data = try #require(store.row.stageReceiptData)
        var digest = try #require(store.row.stageReceiptSHA256)
        switch mutation {
        case "trailing": data.append(32)
        case "unknownKey", "partialChanged":
            var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            if mutation == "unknownKey" { object["path"] = "untrusted" } else {
                object["partialIdentity"] = "1:21:0:100:1:100:1"
            }
            data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        case "digest": digest = String(repeating: "f", count: 64)
        case "oversized": data = Data(repeating: 32, count: SharedMediaCaptureArtifactRequest.maximumEnvelopeBytes + 1)
        default: Issue.record("Unknown mutation")
        }
        if mutation != "digest" { digest = SharedMediaAcquisitionEncoding.digest(data) }
        #expect(throws: (any Error).self) {
            _ = try SharedMediaCaptureArtifactStage.decode(data, sha256: digest, request: store.request)
        }
    }
}
