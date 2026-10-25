import Foundation
import SwiftData
import Testing
@testable import Merian

/// Captured immutable facts from an audited real ready graph. Synthetic wide
/// variants only exercise serialized accounting; they never modify the store.
@MainActor
struct SharedMediaNativeReceivingTestFixture {
    let request: SharedMediaNativeReceivingIntent.Transaction
    let states: [SharedMediaNativePairFileState]
    let receipts: [(SharedMediaAcquisitionIntent, SharedMediaAcquisitionResult)]
    let auditedMetadata: Int64

    static func load(count: Int) async throws -> Self {
        let (store, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture(count: count)
        let result = try capture(store, request: request)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        return result
    }

    static func capture(_ store: SharedMediaNativeAppMetadataTests.Store,
                        request: SharedMediaNativeAppReceivingRequest) throws -> Self {
        let c = store.context(), packageID = request.package.id
        let inventory = try #require(try c.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        let member = try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        let cohort = try SharedMediaNativeFrozenCohort.decode(request.freeze.commit.cohort.bytes)
        let ids = try cohort.entries.map { try SharedMediaNativeDerivativeIntent.decode($0.intent.bytes).pairID }
        let states = try SharedMediaNativeFreezeFacts.states(context: c, inventory: inventory, package: store.package(in: c), member: member, pairIDs: ids)
        let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory, ownerID: store.ownerID, format: .appV2)
        let rows = try c.fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.packageID == packageID }))
        let receipts = try rows.map { row -> (SharedMediaAcquisitionIntent, SharedMediaAcquisitionResult) in
            guard case .completed(let request, let result) = try SharedMediaAcquisitionReceipt.read(row) else { throw SharedMediaStorageFailure.conflict }
            return (request, result)
        }
        let descriptor = try SharedMediaNativeReceivingIntent.Prepared(request).descriptorForTransaction(header: request.header)
        #expect(try SharedMediaNativeReceivingIntent.canonicalRequest(descriptor) == SharedMediaNativeReceivingIntent.canonicalRequest(request))
        return Self(request: .init(request), states: states, receipts: receipts, auditedMetadata: try #require(budget.metadataByPackage[packageID]))
    }

    func freshP2() throws -> Self {
        let prepared = try Self.copy(SharedMediaNativeReceivingIntent.Prepared(request),
            changes: ["format": "nativeReceivingIntentV2", "version": 2, "intentRevision": 0])
        return .init(request: try prepared.descriptorForTransaction(header: request.header), states: states,
            receipts: receipts, auditedMetadata: auditedMetadata)
    }

    func metadata() throws -> Int64 {
        let membership = try SharedMediaMembership.decode(request.member.bytes)
        var bytes = Int64(request.package.envelope.count)
        bytes += try membership.maximumAcquisitionBytes(pending: [])
        for (intent, result) in receipts { bytes += try SharedMediaAcquisitionReceipt.metadataCharge(request: intent, result: result) }
        for state in states { bytes += try SharedMediaNativePairClosure.maximumStateBytes(state) }
        return bytes
    }

    static func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }
    static func copy<T: Codable>(_ value: T, changes: [String: Any]) throws -> T {
        var json = try object(value)
        for (key, replacement) in changes { json[key] = replacement }
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]))
    }
    static func maximumHeader(_ p: SharedMediaNativeReceivingIntent.Prepared) -> SharedMediaNativeAppEligibility.Header {
        .init(inventory: .init(generation: p.profile.generation, revision: .max - 1, phase: SharedMediaNativeAppProfile.phase, cursor: ""),
            bootstrapID: p.profile.inventoryID, bootstrapGeneration: p.profile.generation, bootstrapContract: 2, bootstrapRevision: .max)
    }
    private static func descriptor(_ old: SharedMediaPhotoRetirementIdentity, bytes: Int64) throws -> SharedMediaPhotoRetirementIdentity {
        var parts = old.file.split(separator: ":").map(String.init)
        guard parts.count == 7 else { throw SharedMediaStorageFailure.conflict }
        parts[2] = String(bytes)
        return try copy(old, changes: ["file": parts.joined(separator: ":")])
    }

    func maximumMedia() throws -> Self {
        let old = try SharedMediaNativeFrozenCohort.decode(request.freeze.commit.cohort.bytes)
        guard old.entries.count == 2 else { throw SharedMediaStorageFailure.conflict }
        var entries: [SharedMediaNativeFrozenEntry] = []
        for e in old.entries {
            let intent = try SharedMediaNativeDerivativeIntent.decode(e.intent.bytes)
            let original = try Self.copy(intent.preparation.original, changes: ["byteCount": PhotoPreparationPolicy.original,
                "descriptor": Self.object(Self.descriptor(intent.preparation.original.descriptor, bytes: PhotoPreparationPolicy.original))])
            let prepared = try Self.copy(intent.preparation, changes: ["original": Self.object(original)])
            let ai = try Self.copy(intent.ai, changes: ["byteCount": PhotoPreparationPolicy.aiCohort / 2])
            let display = try Self.copy(intent.display, changes: ["byteCount": PhotoPreparationPolicy.display])
            let next = SharedMediaNativeDerivativeIntent(format: intent.format, preparation: prepared, pairID: intent.pairID,
                nonce: intent.nonce, previousPairID: intent.previousPairID, ai: ai, display: display, focus: intent.focus)
            entries.append(.init(position: e.position, intent: .init(bytes: try next.encoded()), aiReferenceRevision: e.aiReferenceRevision,
                displayReferenceRevision: e.displayReferenceRevision, aiDescriptor: try Self.descriptor(e.aiDescriptor, bytes: ai.byteCount),
                displayDescriptor: try Self.descriptor(e.displayDescriptor, bytes: display.byteCount)))
        }
        let cohort = try Self.copy(old, changes: ["entries": entries.map(Self.object)])
        let receipts = try self.receipts.map { intent, result in
            (intent, try SharedMediaAcquisitionResult(request: intent, inventoryRevision: result.inventoryRevision,
                packageRevision: result.packageRevision, membershipRevision: result.membershipRevision,
                byteCount: PhotoPreparationPolicy.original, sha256: result.sha256, contentType: result.contentType,
                descriptor: Self.descriptor(result.descriptor, bytes: PhotoPreparationPolicy.original)))
        }
        return try replacing(cohort: cohort, allocated: 77 * 1_024 * 1_024, receipts: receipts)
    }

    func context(_ text: String) throws -> Self { try context([.init(freeText: text)]) }

    func context(_ contexts: [ObservationContext], advancingPackage: Bool = false) throws -> Self {
        let cohort = try SharedMediaNativeFrozenCohort.decode(request.freeze.commit.cohort.bytes)
        let support = try SharedMediaNativeFrozenSupporting(contexts: contexts, presentation: []).encoded()
        return try replacing(cohort: Self.copy(cohort, changes: ["supportingBytes": support.base64EncodedString()]),
            allocated: request.package.allocated, receipts: receipts, advancingPackage: advancingPackage)
    }

    private func replacing(cohort: SharedMediaNativeFrozenCohort, allocated: Int64,
                           receipts: [(SharedMediaAcquisitionIntent, SharedMediaAcquisitionResult)], advancingPackage: Bool = false) throws -> Self {
        guard case .preparation(let envelope) = try SharedMediaNativeDraftEnvelope.decode(request.package.envelope) else {
            throw SharedMediaStorageFailure.conflict
        }
        let support = try JSONDecoder().decode(SharedMediaNativeFrozenSupporting.self, from: cohort.supportingBytes)
        let nextEnvelope = SharedMediaNativeDraftEnvelope.V2(version: 2, contexts: support.contexts, presentation: support.presentation,
            sequence: envelope.sequence, attempt: nil, intents: cohort.entries.map(\.intent), frozen: nil)
        let bytes = try nextEnvelope.encoded()
        let package = try Self.copy(request.package, changes: ["envelope": bytes.base64EncodedString(), "allocated": allocated,
            "revision": request.package.revision + (advancingPackage ? 1 : 0)])
        let p = try Self.copy(SharedMediaNativeReceivingIntent.Prepared(request), changes: [
            "package": Self.object(package), "cohort": Self.object(SharedMediaNativePreparationBlob(bytes: cohort.encoded()))])
        let states = try self.states.map { state in
            let intent = try state.intent()
            let entry = try #require(try cohort.entries.first { try SharedMediaNativeDerivativeIntent.decode($0.intent.bytes).pairID == intent.pairID })
            let plan = try Self.copy(state.plan, changes: ["intent": Self.object(entry.intent), "envelope": bytes.base64EncodedString(),
                "packageRevision": package.revision])
            let work = try state.work.map { item in
                try Self.copy(item, changes: ["finalIdentity": item.id == intent.ai.id ? entry.aiDescriptor.file : entry.displayDescriptor.file])
            }
            return try Self.copy(state, changes: ["plan": Self.object(plan), "allocatedBytes": allocated, "work": work.map(Self.object)])
        }
        return try Self(request: p.descriptorForTransaction(header: request.header), states: states, receipts: receipts, auditedMetadata: 0)
    }

}
