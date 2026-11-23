import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite("Whole capture submission receipt", .serialized)
@MainActor
struct SharedMediaCaptureSubmissionTests {
    private func fixture(_ name: String = "photo_audio") throws -> SharedMediaCaptureSubmission {
        let source = try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/capture-plans-v1.json")
        let fixtures = try #require(JSONSerialization.jsonObject(with: Data(source.utf8)) as? [[String: Any]])
        let raw = try #require(fixtures.first { $0["name"] as? String == name })
        let owner = try ObservationHistoryPage.uuid(raw["owner_id"])
        let plan = try CaptureInitialEvidencePlan(ownerID: owner,
            data: JSONSerialization.data(withJSONObject: #require(raw["plan"]), options: [.sortedKeys, .withoutEscapingSlashes]))
        let profile = SharedMediaNativeAppProfile(ownerID: owner, inventoryID: UUID(), generation: UUID(),
            storeIdentity: UUID().uuidString, physicalBinding: String(repeating: "a", count: 64),
            receiptDigest: String(repeating: "b", count: 64), physicalBindingFormat: .physicalRootsV1)
        return try .init(plan: plan, context: SharedMediaCaptureSubmissionContextTests.context(plan), profile: profile, writerEpoch: UUID(), inventoryRevision: 4,
            rootBindingSHA256: String(repeating: "c", count: 64), eventID: UUID(), artifactIDs: plan.uploads.map { _ in UUID() })
    }

    @Test(arguments: ["two_photos", "two_audio", "photo_audio", "video_audio"])
    func canonicalRoundTripPreservesWholePlanAndLocalRoles(_ name: String) throws {
        let value = try fixture(name), data = try value.encoded()
        #expect(try SharedMediaCaptureSubmission.decode(data, sha256: SharedMediaAcquisitionEncoding.digest(data)) == value)
        let plan = try value.plan()
        #expect(value.members.map(\.mediaID) == plan.uploads.map(\.artifact.mediaID))
        #expect(value.observation.bytes == (try plan.encoded()))
        for (member, upload) in zip(value.members, plan.uploads) {
            let input = try value.artifact(mediaID: member.mediaID)
            #expect(input.id == member.artifactID && input.mediaID == upload.artifact.mediaID)
            #expect(input.planSHA256 == value.observation.sha256 && input.itemIndex == upload.itemIndex)
            #expect(input.role.rawValue == upload.role.rawValue && input.frameIndex == upload.frameIndex)
        }
        #expect(throws: (any Error).self) { try SharedMediaOrdinarySubmission.decode(data, sha256: SharedMediaAcquisitionEncoding.digest(data)) }
    }

    @Test(arguments: ["reorder", "duplicate", "unknown", "digest", "root", "oversize", "missing"])
    func rejectsChangedOrNoncanonicalEnvelope(_ mutation: String) throws {
        let value = try fixture(), original = try value.encoded()
        var raw = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
        var members = try #require(raw["members"] as? [[String: Any]])
        switch mutation {
        case "reorder": members.reverse(); raw["members"] = members
        case "duplicate": members[1] = members[0]; raw["members"] = members
        case "unknown": raw["extra"] = true
        case "root": raw["rootBindingSHA256"] = "invalid"
        case "missing": members.removeLast(); raw["members"] = members
        default: break
        }
        var bytes = try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys, .withoutEscapingSlashes])
        if mutation == "oversize" { bytes = Data(repeating: 32, count: Int(PhotoPreparationPolicy.metadata) + 1) }
        let digest = mutation == "digest" ? String(repeating: "f", count: 64) : SharedMediaAcquisitionEncoding.digest(bytes)
        #expect(throws: (any Error).self) { try SharedMediaCaptureSubmission.decode(bytes, sha256: digest) }
    }

    @MainActor private struct Store {
        let container: ModelContainer, context: ModelContext
        let row: SharedMediaOrdinarySubmissionRecord
        init(_ submission: SharedMediaCaptureSubmission) throws {
            let schema = Schema([SharedMediaOrdinarySubmissionRecord.self, SharedMediaOrdinaryArtifactRecord.self])
            container = try ModelContainer(for: schema, configurations: [.init(schema: schema, isStoredInMemoryOnly: true)])
            context = ModelContext(container); context.autosaveEnabled = false
            let data = try submission.encoded(), profile = submission.profile
            row = .init(inventoryID: profile.inventoryID, inventoryGeneration: profile.generation,
                ownerID: profile.ownerID, recipientScanID: submission.scanID, submissionGeneration: submission.generation,
                jobID: submission.jobID, eventID: submission.eventID, writerEpoch: submission.writerEpoch,
                formatRaw: submission.format.rawValue, requestData: data,
                requestSHA256: SharedMediaAcquisitionEncoding.digest(data), observationSHA256: submission.observation.sha256)
            context.insert(row); try context.save()
        }
        func child(_ value: SharedMediaCaptureSubmission, index: Int,
                   phase: SharedMediaCaptureArtifactLedger.Phase = .reserved, mutation: String? = nil) throws -> SharedMediaOrdinaryArtifactRecord {
            let input = try value.artifact(mediaID: value.members[index].mediaID)
            let profile = mutation == "profile" ? SharedMediaNativeAppProfile(ownerID: value.profile.ownerID,
                inventoryID: value.profile.inventoryID, generation: value.profile.generation,
                storeIdentity: value.profile.storeIdentity, physicalBinding: String(repeating: "e", count: 64),
                receiptDigest: value.profile.receiptDigest, physicalBindingFormat: .physicalRootsV1) : value.profile
            let request = try SharedMediaCaptureArtifactRequest(id: mutation == "artifact" ? UUID() : input.id, profile: profile, writerEpoch: UUID(),
                scanID: input.scanID, submissionGeneration: input.submissionGeneration, planSHA256: mutation == "plan" ? String(repeating: "f", count: 64) : input.planSHA256,
                rootBindingSHA256: mutation == "root" ? String(repeating: "f", count: 64) : value.rootBindingSHA256,
                inventoryRevision: value.inventoryRevision + (mutation == "revision" ? 0 : 1),
                mediaID: mutation == "media" ? UUID() : input.mediaID, itemIndex: input.itemIndex, role: input.role, frameIndex: input.frameIndex,
                contentType: input.contentType, byteCount: input.byteCount, sha256: input.sha256,
                allocationID: UUID(), referenceID: UUID(), leaseID: UUID())
            let row = SharedMediaOrdinaryArtifactRecord(id: request.id, inventoryID: value.profile.inventoryID,
                inventoryGeneration: value.profile.generation, ownerID: value.profile.ownerID,
                recipientScanID: value.scanID, submissionGeneration: value.generation, mediaID: request.mediaID,
                itemIndex: input.itemIndex, roleRaw: input.role.rawValue, frameIndex: input.frameIndex,
                allocationID: request.allocationID, referenceID: request.referenceID, leaseID: request.leaseID,
                writerEpoch: request.writerEpoch, requestData: try request.encoded(), requestSHA256: try request.digest)
            if phase != .reserved {
                let stage = try SharedMediaCaptureArtifactStage(request: request, inventoryRevision: request.inventoryRevision + 3,
                    partialIdentity: "1:20:0:100:1:100:1", finalIdentity: phase == .ready ? "1:20:\(input.byteCount):101:1:101:1" : nil)
                row.phaseRaw = phase.rawValue; row.revision = phase == .ready ? 2 : 1
                row.stageReceiptData = try stage.encoded(request: request)
                row.stageReceiptSHA256 = SharedMediaAcquisitionEncoding.digest(try stage.encoded(request: request))
            }
            context.insert(row); try context.save(); return row
        }
        func read() throws -> SharedMediaCaptureSubmissionReceipt.Snapshot {
            try SharedMediaCaptureSubmissionReceipt.read(row, in: context)
        }
    }

    @Test func reservedParentDescribesMissingPartialAndReadyChildrenWithoutDoubleCharging() throws {
        let value = try fixture(), store = try Store(value)
        #expect(try store.read().artifacts.isEmpty)
        _ = try store.child(value, index: 2, phase: .ready)
        _ = try store.child(value, index: 0, phase: .writing)
        _ = try store.child(value, index: 1)
        let receipt = try store.read()
        #expect(receipt.artifacts.map(\.request.id) == value.members.map(\.artifactID))
        #expect(receipt.artifacts.map(\.phase) == [.writing, .reserved, .ready])
        #expect(receipt.metadataBytes == Int64(try value.encoded().count + 64))
        let fresh = ModelContext(store.container); fresh.autosaveEnabled = false
        let row = try #require(try fresh.fetch(FetchDescriptor<SharedMediaOrdinarySubmissionRecord>()).first)
        #expect(try SharedMediaCaptureSubmissionReceipt.read(row, in: fresh) == receipt)
    }

    @Test func preboundOutputRequiresExactImmutableReadyProof() throws {
        let base = try fixture(), store = try Store(base), plan = try base.plan()
        let index = try #require(plan.uploads.firstIndex { $0.role.rawValue == "prepared_image" })
        let row = try store.child(base, index: index, phase: .ready)
        let artifact = try SharedMediaCaptureArtifactLedger.receipt(row)
        func parent(retained: Bool) throws -> SharedMediaCaptureSubmission {
            try .init(plan: plan, context: base.context, profile: base.profile, writerEpoch: UUID(),
                inventoryRevision: 9, rootBindingSHA256: base.rootBindingSHA256, eventID: UUID(),
                artifactIDs: base.members.map(\.artifactID), retainedArtifacts: retained ? [artifact] : [])
        }
        #expect(throws: (any Error).self) { try parent(retained: false).requireMember(artifact) }
        let bound = try parent(retained: true)
        try bound.requireMember(artifact)
        var raw = try #require(JSONSerialization.jsonObject(with: bound.encoded()) as? [String: Any])
        var members = try #require(raw["members"] as? [[String: Any]])
        members[index]["retainedStageSHA256"] = String(repeating: "f", count: 64)
        raw["members"] = members
        let bytes = try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys, .withoutEscapingSlashes])
        let changed = try SharedMediaCaptureSubmission.decode(bytes, sha256: SharedMediaAcquisitionEncoding.digest(bytes))
        #expect(throws: (any Error).self) { try changed.requireMember(artifact) }
        members[index].removeValue(forKey: "retainedRequestSHA256"); raw["members"] = members
        let incomplete = try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys, .withoutEscapingSlashes])
        #expect(throws: (any Error).self) {
            try SharedMediaCaptureSubmission.decode(incomplete, sha256: SharedMediaAcquisitionEncoding.digest(incomplete))
        }
    }

    @Test(arguments: ["profile", "plan", "root", "revision", "media", "artifact"])
    func rejectsCoherentChildrenOutsideTheFrozenParent(_ mutation: String) throws {
        let value = try fixture(), store = try Store(value)
        _ = try store.child(value, index: 0, mutation: mutation)
        #expect(throws: (any Error).self) { try store.read() }
    }

    @Test func acceptanceRequiresEveryReadyMemberAndBindsItsExactStage() throws {
        let value = try fixture(), store = try Store(value)
        _ = try store.child(value, index: 0, phase: .ready)
        #expect(throws: (any Error).self) {
            try SharedMediaCaptureSubmissionAcceptance(submission: value, artifacts: store.read().artifacts, inventoryRevision: 9)
        }
        _ = try store.child(value, index: 1, phase: .ready)
        _ = try store.child(value, index: 2, phase: .ready)
        let complete = try store.read().artifacts
        #expect(throws: (any Error).self) {
            try SharedMediaCaptureSubmissionAcceptance(submission: value, artifacts: complete.reversed(), inventoryRevision: 9)
        }
        #expect(throws: (any Error).self) {
            try SharedMediaCaptureSubmissionAcceptance(submission: value, artifacts: complete, inventoryRevision: 8)
        }
        let acceptance = try SharedMediaCaptureSubmissionAcceptance(submission: value, artifacts: complete, inventoryRevision: 9)
        let bytes = try acceptance.encoded(submission: value, artifacts: complete)
        store.row.phaseRaw = "accepted"; store.row.revision = 1
        store.row.acceptanceData = bytes; store.row.acceptanceSHA256 = SharedMediaAcquisitionEncoding.digest(bytes)
        try store.context.save()
        let receipt = try store.read()
        #expect(receipt.state == .accepted(acceptance))
        #expect(receipt.metadataBytes == Int64(try value.encoded().count + bytes.count + 128))
        var raw = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var members = try #require(raw["members"] as? [[String: Any]])
        members[0]["stageSHA256"] = String(repeating: "f", count: 64); raw["members"] = members
        let changed = try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys, .withoutEscapingSlashes])
        store.row.acceptanceData = changed; store.row.acceptanceSHA256 = SharedMediaAcquisitionEncoding.digest(changed)
        try store.context.save()
        #expect(throws: (any Error).self) { try store.read() }
    }

    @Test(arguments: ["owner", "generation", "format", "observation", "accepted", "extra", "childRole", "childGeneration"])
    func rejectsScalarDriftAndExtraOrChangedChildren(_ mutation: String) throws {
        let value = try fixture(), store = try Store(value)
        let child = try store.child(value, index: 0)
        switch mutation {
        case "owner": store.row.ownerID = UUID()
        case "generation": store.row.submissionGeneration = UUID()
        case "format": store.row.formatRaw = "ordinaryPhotoSubmissionV1"
        case "observation": store.row.observationSHA256 = String(repeating: "f", count: 64)
        case "accepted": store.row.phaseRaw = "accepted"; store.row.revision = 1
        case "extra":
            let other = try fixture("two_audio")
            let extra = try store.child(other, index: 0); extra.recipientScanID = value.scanID
        case "childRole": child.roleRaw = "source_audio"
        case "childGeneration": child.submissionGeneration = UUID()
        default: Issue.record("Unknown mutation")
        }
        try store.context.save()
        #expect(throws: (any Error).self) { try store.read() }
    }
}
