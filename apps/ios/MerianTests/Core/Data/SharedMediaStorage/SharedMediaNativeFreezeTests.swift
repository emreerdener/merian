import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native exact freeze", .serialized)
@MainActor
struct SharedMediaNativeFreezeTests {
    private typealias Harness = SharedMediaNativePreparationTests.Harness
    private enum Fault: Error { case injected }
    private static let recipe = SharedMediaNativePreparationRecipe(format: .stillImage, isPro: false,
        cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0)

    private struct LegacyFrozenCohort: Encodable {
        let format: String
        let packageID: UUID
        let ownerID: UUID
        let draftGeneration: UUID
        let supportingBytes: Data
        let entries: [SharedMediaNativeFrozenEntry]
    }

    @Test func initialNotesCodecPreservesOldBytesAndRejectsChangedSeed() async throws {
        let fixture = try await SharedMediaNativeReceivingTestFixture.load(count: 1)
        let source = try SharedMediaNativeFrozenCohort.decode(fixture.request.freeze.commit.cohort.bytes)
        // Independent pre-successor shape retained from ac8f1737: this encoder
        // has no initialFieldNotes key and cannot silently follow the new type.
        let oldBytes = try SharedMediaNativeDraftEnvelope.bytes(LegacyFrozenCohort(
            format: "nativeConsumerV2", packageID: source.packageID, ownerID: source.ownerID,
            draftGeneration: source.draftGeneration, supportingBytes: source.supportingBytes, entries: source.entries))
        let old = try SharedMediaNativeFrozenCohort.decode(oldBytes)
        #expect(try old.encoded() == oldBytes)
        #expect(!String(decoding: oldBytes, as: UTF8.self).contains("initialFieldNotes"))
        let supporting: SharedMediaNativeFrozenSupporting = try SharedMediaAcquisitionEncoding.decode(old.supportingBytes,
            maximum: Int(PhotoPreparationPolicy.metadata))
        let notes = InitialFieldNotesSeed.make(contexts: supporting.contexts)
        let current = SharedMediaNativeFrozenCohort(format: .initialNotes, packageID: old.packageID, ownerID: old.ownerID,
            draftGeneration: old.draftGeneration, supportingBytes: old.supportingBytes, entries: old.entries, initialFieldNotes: notes)
        let encoded = try current.encoded()
        #expect(try SharedMediaNativeFrozenCohort.decode(encoded).initialFieldNotes == notes)
        #expect(current.supportingBytes == old.supportingBytes)
        let bad = try SharedMediaNativeReceivingTestFixture.copy(current, changes: ["initialFieldNotes": "tampered"])
        #expect(throws: (any Error).self) { _ = try bad.encoded() }
        #expect(throws: (any Error).self) {
            _ = try SharedMediaNativeFrozenCohort.decode(SharedMediaNativeDraftEnvelope.bytes(bad))
        }
        let oldWithSeed = try SharedMediaNativeReceivingTestFixture.copy(current, changes: ["format": "nativeConsumerV2"])
        #expect(throws: (any Error).self) { _ = try oldWithSeed.encoded() }
    }

    @Test func orderedTwoOriginalFreezePreservesSupportingBytesAndReplaysAfterReopen() async throws {
        let h = try Harness(), owner = try await h.open(), first = try await h.acquire(owner), second = try await h.acquire(owner, ordinal: 1)
        let contexts = [ObservationContext(freeText: "  exact submitted details\n ")]
        _ = try await owner.saveMetadata(owner.prepareMetadata(packageID: h.packageID, draftGeneration: h.draft, contexts: contexts))
        let a = try await owner.qualifyPreparedFiles(original: first, recipe: Self.recipe)
        let b = try await owner.qualifyPreparedFiles(original: second, recipe: Self.recipe)
        let ids = try [b.intent().pairID, a.intent().pairID], before = try h.state()
        let request = try await owner.prepareFreeze(packageID: h.packageID, pairIDs: ids, operationID: UUID())
        let saved = try await owner.freeze(request), cohort = try SharedMediaNativeFrozenCohort.decode(saved.cohort.bytes)
        #expect(try cohort.entries.map { try SharedMediaNativeDerivativeIntent.decode($0.intent.bytes).pairID } == ids)
        #expect(cohort.supportingBytes == (try SharedMediaNativeFrozenSupporting(contexts: contexts, presentation: []).encoded()))
        let frozen = try h.state()
        #expect(frozen.phase == "preparedHeld" && frozen.package == before.package + 1 && frozen.inventory == before.inventory + 1)
        #expect(frozen.members == before.members && frozen.memberRevision == before.memberRevision)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaConsumerRecord>()) == 0)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try await owner.freeze(request) == saved)
        await #expect(throws: (any Error).self) { try await owner.prepareMetadata(packageID: h.packageID, draftGeneration: h.draft, contexts: []) }
        await #expect(throws: (any Error).self) { try await owner.retirePreparedFiles(owner.preparedFileState(packageID: h.packageID, pairID: ids[0])) }
        #expect(try h.state() == frozen)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await h.open()
        #expect(try await cold.freeze(request) == saved)
        #expect(try h.state() == frozen)
        #expect(try Data(contentsOf: h.file(first)) == h.bytes && Data(contentsOf: h.file(second)) == h.bytes)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func frozenPackageAllowsIndependentDraftAndKeepsExactReceipts() async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let firstPair = try await owner.qualifyPreparedFiles(original: original, recipe: Self.recipe)
        let first = try await owner.prepareFreeze(packageID: h.packageID, pairIDs: [firstPair.intent().pairID], operationID: UUID())
        _ = try await owner.freeze(first)
        let frozen = try h.state(), otherID = UUID(), otherDraft = UUID()
        let acquisition = try await owner.prepareOriginal(packageID: otherID, draftGeneration: otherDraft, ordinal: 0, kind: .picker)
        let bytes = h.bytes
        let acquired = try await owner.acquireOriginal(acquisition) { bytes }
        let other = PhotoOriginalReference(ownerID: h.ownerID, packageID: otherID, referenceID: acquisition.referenceID,
            assetID: acquisition.assetID, assetGeneration: acquisition.assetGeneration, draftGeneration: otherDraft,
            referenceRevision: acquired.referenceRevision)
        let otherPair = try await owner.qualifyPreparedFiles(original: other, recipe: Self.recipe)
        let second = try await owner.prepareFreeze(packageID: otherID, pairIDs: [otherPair.intent().pairID], operationID: UUID())
        #expect(try await owner.freeze(second) == second.commit)
        #expect(try await owner.freeze(first) == first.commit)
        await #expect(throws: (any Error).self) { try await owner.prepareMetadata(packageID: h.packageID, draftGeneration: h.draft, contexts: []) }
        await #expect(throws: (any Error).self) { try await owner.retirePreparedFiles(owner.preparedFileState(packageID: h.packageID, pairID: firstPair.intent().pairID)) }
        let after = try h.state()
        #expect(after.inventory > frozen.inventory)
        #expect(after.package == frozen.package && after.memberRevision == frozen.memberRevision)
        #expect(after.members == frozen.members && after.envelope == frozen.envelope && after.phase == frozen.phase)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await h.open()
        #expect(try await cold.freeze(first) == first.commit)
        #expect(try await cold.freeze(second) == second.commit)
        #expect(try h.state() == after)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [SharedMediaNativePreparationBoundary.beforeFreezeSave, .afterFreezeSave])
    func saveAcknowledgementUsesExactReceipt(_ boundary: SharedMediaNativePreparationBoundary) async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let ready = try await owner.qualifyPreparedFiles(original: original, recipe: Self.recipe)
        let request = try await owner.prepareFreeze(packageID: h.packageID, pairIDs: [ready.intent().pairID], operationID: UUID()), before = try h.state()
        try owner.setPreparationFault { if $0 == boundary { throw Fault.injected } }
        if boundary == .beforeFreezeSave {
            await #expect(throws: Fault.self) { try await owner.freeze(request) }
            #expect(try h.state() == before)
            try owner.setPreparationFault(nil)
        }
        #expect(try await owner.freeze(request) == request.commit)
        #expect(try await owner.freeze(request) == request.commit)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func lostReadbackReopensWithoutRepeatingPreparationOrFreeze() async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let ready = try await owner.qualifyPreparedFiles(original: original, recipe: Self.recipe)
        let request = try await owner.prepareFreeze(packageID: h.packageID, pairIDs: [ready.intent().pairID], operationID: UUID())
        var unavailable = false
        try owner.setPreparationFault {
            if $0 == .afterFreezeSave { unavailable = true; throw Fault.injected }
            if unavailable && $0 == .beforeReadback { throw Fault.injected }
        }
        // The mutation's fresh exact readback can settle an acknowledgement even
        // when the outer operation boundary has become unavailable.
        #expect(try await owner.freeze(request) == request.commit)
        let frozen = try h.state()
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await h.open()
        #expect(try await cold.freeze(request) == request.commit)
        #expect(try h.state() == frozen)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func incompleteDuplicateAndStaleCohortsPreserveDraft() async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let ready = try await owner.qualifyPreparedFiles(original: original, recipe: Self.recipe), id = try ready.intent().pairID
        let stale = try await owner.prepareFreeze(packageID: h.packageID, pairIDs: [id], operationID: UUID())
        _ = try await h.acquire(owner, ordinal: 1)
        let before = try h.state()
        await #expect(throws: (any Error).self) { try await owner.freeze(stale) }
        for ids in [[], [id], [id, id], [UUID()]] {
            await #expect(throws: (any Error).self) { try await owner.prepareFreeze(packageID: h.packageID, pairIDs: ids, operationID: UUID()) }
        }
        #expect(try h.state() == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [false, true])
    func missingMediaBeforeFreezePreservesDraft(output: Bool) async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let ready = try await owner.qualifyPreparedFiles(original: original, recipe: Self.recipe)
        let request = try await owner.prepareFreeze(packageID: h.packageID, pairIDs: [ready.intent().pairID], operationID: UUID()), before = try h.state()
        let path = output ? try outputPath(h, ready) : h.file(original)
        try FileManager.default.removeItem(at: path)
        await #expect(throws: (any Error).self) { try await owner.freeze(request) }
        #expect(try h.state() == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func historicalReplayDoesNotPromiseCurrentMediaAvailability() async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let ready = try await owner.qualifyPreparedFiles(original: original, recipe: Self.recipe)
        let request = try await owner.prepareFreeze(packageID: h.packageID, pairIDs: [ready.intent().pairID], operationID: UUID())
        _ = try await owner.freeze(request)
        try FileManager.default.removeItem(at: outputPath(h, ready))
        #expect(try await owner.freeze(request) == request.commit)
        await #expect(throws: (any Error).self) { try await owner.snapshot() }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        await #expect(throws: (any Error).self) { try await h.open() }
    }

    @Test func capacityDenialPreservesReadyFilesAndMetadata() async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let ready = try await owner.qualifyPreparedFiles(original: original, recipe: Self.recipe)
        let request = try await owner.prepareFreeze(packageID: h.packageID, pairIDs: [ready.intent().pairID], operationID: UUID()), before = try h.state()
        let bytes = try Data(contentsOf: outputPath(h, ready))
        try owner.setPreparationFault(nil, availableBytes: 0)
        await #expect(throws: SharedMediaStorageFailure.capacity) { try await owner.freeze(request) }
        #expect(try h.state() == before)
        #expect(try Data(contentsOf: outputPath(h, ready)) == bytes)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func changedOperationOrPreimageCannotReplay() async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let ready = try await owner.qualifyPreparedFiles(original: original, recipe: Self.recipe)
        let request = try await owner.prepareFreeze(packageID: h.packageID, pairIDs: [ready.intent().pairID], operationID: UUID())
        let other = try await owner.prepareFreeze(packageID: h.packageID, pairIDs: [ready.intent().pairID], operationID: UUID())
        _ = try await owner.freeze(request)
        let before = try h.state()
        await #expect(throws: (any Error).self) { try await owner.freeze(other) }
        let changed = SharedMediaNativeFreezeRequest(commit: request.commit, previousEnvelope: Data(), membership: request.membership)
        await #expect(throws: (any Error).self) { try await owner.freeze(changed) }
        #expect(try h.state() == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [false, true], [false, true])
    func replacementAtSaveBoundaryCannotFreeze(output: Bool, inPlace: Bool) async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let ready = try await owner.qualifyPreparedFiles(original: original, recipe: Self.recipe)
        let request = try await owner.prepareFreeze(packageID: h.packageID, pairIDs: [ready.intent().pairID], operationID: UUID()), before = try h.state()
        let path = output ? try outputPath(h, ready) : h.file(original), bytes = try Data(contentsOf: path)
        try owner.setPreparationFault {
            if $0 == .beforeFreezeSave {
                if inPlace { try Data(repeating: 0, count: bytes.count).write(to: path) }
                else {
                    try FileManager.default.removeItem(at: path)
                    try bytes.write(to: path, options: .atomic)
                }
            }
        }
        await #expect(throws: (any Error).self) { try await owner.freeze(request) }
        #expect(try h.state() == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func sharedOriginalUsesItsOwnParentIdentity() async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let share = try await owner.prepareShare(original, packageID: UUID(), draftGeneration: UUID())
        let shared = try await owner.share(share)
        let ready = try await owner.qualifyPreparedFiles(original: shared, recipe: Self.recipe)
        let request = try await owner.prepareFreeze(packageID: shared.packageID, pairIDs: [ready.intent().pairID], operationID: UUID())
        let cohort = try SharedMediaNativeFrozenCohort.decode(request.commit.cohort.bytes)
        let entry = try #require(cohort.entries.first), intent = try ready.intent()
        #expect(entry.aiDescriptor.parent != intent.preparation.original.descriptor.parent)
        #expect(try await owner.freeze(request) == request.commit)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await h.open()
        #expect(try await cold.freeze(request) == request.commit)
        #expect(try Data(contentsOf: h.file(original)) == h.bytes)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func differentOrderingAndSupportingBytesCannotReplayReceipt() async throws {
        let h = try Harness(), owner = try await h.open(), first = try await h.acquire(owner), second = try await h.acquire(owner, ordinal: 1)
        let a = try await owner.qualifyPreparedFiles(original: first, recipe: Self.recipe)
        let b = try await owner.qualifyPreparedFiles(original: second, recipe: Self.recipe), operation = UUID()
        let ordered = try await owner.prepareFreeze(packageID: h.packageID, pairIDs: [a.intent().pairID, b.intent().pairID], operationID: operation)
        let reversed = try await owner.prepareFreeze(packageID: h.packageID, pairIDs: [b.intent().pairID, a.intent().pairID], operationID: operation)
        _ = try await owner.freeze(ordered)
        await #expect(throws: (any Error).self) { try await owner.freeze(reversed) }
        let altered = try altering(ordered.commit, field: "supporting")
        let request = SharedMediaNativeFreezeRequest(commit: altered, previousEnvelope: ordered.previousEnvelope, membership: ordered.membership)
        await #expect(throws: (any Error).self) { try await owner.freeze(request) }
        #expect(try await owner.freeze(ordered) == ordered.commit)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["previousEnvelopeSHA256", "membershipSHA256", "parent", "namespace"])
    func corruptedPersistedFreezeCannotReopen(_ field: String) async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let ready = try await owner.qualifyPreparedFiles(original: original, recipe: Self.recipe)
        let request = try await owner.prepareFreeze(packageID: h.packageID, pairIDs: [ready.intent().pairID], operationID: UUID())
        _ = try await owner.freeze(request)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let context = ModelContext(h.container), id = h.packageID
        let row = try #require(context.fetch(FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id })).first)
        guard case .preparation(let value) = try SharedMediaNativeDraftEnvelope.decode(row.supportingContextData) else { throw Fault.injected }
        let altered = try altering(request.commit, field: field)
        row.supportingContextData = try SharedMediaNativeDraftEnvelope.V2(version: 2, contexts: value.contexts,
            presentation: value.presentation, sequence: value.sequence, attempt: nil, intents: value.intents,
            frozen: .init(bytes: altered.encoded())).encoded()
        try context.save()
        await #expect(throws: (any Error).self) { try await h.open() }
    }

    @Test func oversizedEncodedFreezePreservesReadyDraft() async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let ready = try await owner.qualifyPreparedFiles(original: original, recipe: Self.recipe)
        let contexts = (0..<4).map { _ in ObservationContext(freeText: String(repeating: "\u{0001}", count: 8_000)) }
        _ = try await owner.saveMetadata(owner.prepareMetadata(packageID: h.packageID, draftGeneration: h.draft, contexts: contexts))
        let before = try h.state()
        await #expect(throws: SharedMediaStorageFailure.capacity) {
            let request = try await owner.prepareFreeze(packageID: h.packageID, pairIDs: [ready.intent().pairID], operationID: UUID())
            _ = try await owner.freeze(request)
        }
        #expect(try h.state() == before)
        #expect(try SharedMediaNativeDraftEnvelope.decode(before.envelope).contexts == contexts)
        #expect(try Data(contentsOf: h.file(original)) == h.bytes)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    private func altering(_ commit: SharedMediaNativeFreezeCommit, field: String) throws -> SharedMediaNativeFreezeCommit {
        var value = try #require(JSONSerialization.jsonObject(with: commit.encoded()) as? [String: Any])
        if field.hasSuffix("SHA256") { value[field] = String(repeating: "0", count: 64) }
        else {
            var cohort = try #require(JSONSerialization.jsonObject(with: commit.cohort.bytes) as? [String: Any])
            if field == "supporting" {
                cohort["supportingBytes"] = try SharedMediaNativeFrozenSupporting(contexts: [.init(freeText: "changed")], presentation: []).encoded().base64EncodedString()
            } else {
                var entries = try #require(cohort["entries"] as? [[String: Any]])
                var descriptor = try #require(entries[0]["aiDescriptor"] as? [String: Any])
                descriptor[field] = "different-directory"
                entries[0]["aiDescriptor"] = descriptor; cohort["entries"] = entries
            }
            let decoded = try JSONDecoder().decode(SharedMediaNativeFrozenCohort.self, from: JSONSerialization.data(withJSONObject: cohort))
            let blob = SharedMediaNativePreparationBlob(bytes: try decoded.encoded())
            value["cohort"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(blob))
        }
        let decoded = try JSONDecoder().decode(SharedMediaNativeFreezeCommit.self, from: JSONSerialization.data(withJSONObject: value))
        return try .decode(decoded.encoded())
    }

    private func outputPath(_ h: Harness, _ state: SharedMediaNativePairFileState) throws -> URL {
        h.base.appendingPathComponent("photo/PhotoPreparation/" + (try state.file(state.intent().ai.id).token))
    }
}
