import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite("Ordinary photo hold current selection", .serialized)
@MainActor
struct SharedMediaOrdinaryHoldSelectionTests {
    typealias Fixture = SharedMediaNativeReceivingTestFixture

    @Test
    func wholeCurrentSelectionIsReadOnlyAndRejectsResignedDrift() async throws {
        let (store, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture(count: 2)
        let fixture = try Fixture.capture(store, request: request)
        let submission = request.freeze.commit.cohort
        let frozen = try SharedMediaNativeFrozenCohort.decode(submission.bytes)
        let scanID = UUID(), generation = UUID(), eventID = UUID()
        let ids = [UUID(), UUID()].sorted { $0.uuidString > $1.uuidString }
        func describe(_ blob: SharedMediaNativePreparationBlob, ids: [UUID]) async throws -> SharedMediaOrdinaryPhotoHoldBinding {
            try await owner.describeAppOrdinaryPhotoHolds(submission: blob, holdIDs: ids,
                scanID: scanID, submissionGeneration: generation, eventID: eventID)
        }
        let result = try await describe(submission, ids: ids)
        #expect(result.submission == submission)
        #expect(result.orderedRequests.map(\.id) == ids)
        #expect(result.orderedRequests.allSatisfy { $0.recipient.submissionGeneration == generation })
        let c = store.context()
        let inventory = try #require(try c.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        #expect(inventory.revision == request.header.inventory.revision)
        #expect(try store.package(in: c).phaseRaw == "draftOwned")
        #expect(try c.fetchCount(FetchDescriptor<SharedMediaOrdinaryTransferRecord>()) == 0)
        #expect(try c.fetch(FetchDescriptor<SharedMediaAssetReferenceCountRecord>()).allSatisfy { $0.liveCount == 1 })
        #expect(!c.hasChanges)

        // A fresh digest cannot legitimize notes, intent membership, or
        // derivative identities different from the current prepared graph.
        let changedNotes = try fixture.context("Different synthetic notes").request.freeze.commit.cohort
        let first = frozen.entries[0]
        let changedRevision: SharedMediaNativeFrozenEntry = try Fixture.copy(first,
            changes: ["aiReferenceRevision": first.aiReferenceRevision + 1])
        let changedDescriptor: SharedMediaNativeFrozenEntry = try Fixture.copy(first,
            changes: ["aiDescriptor": Fixture.object(frozen.entries[1].aiDescriptor)])
        var invalid = [changedNotes]
        for entry in [changedRevision, changedDescriptor] {
            let changed: SharedMediaNativeFrozenCohort = try Fixture.copy(frozen,
                changes: ["entries": [entry, frozen.entries[1]].map(Fixture.object)])
            invalid.append(try .init(bytes: changed.encoded()))
        }
        for blob in invalid {
            await #expect(throws: (any Error).self) { _ = try await describe(blob, ids: ids) }
        }
        let subset: SharedMediaNativeFrozenCohort = try Fixture.copy(frozen,
            changes: ["entries": [Fixture.object(first)]])
        await #expect(throws: (any Error).self) {
            _ = try await describe(.init(bytes: subset.encoded()), ids: [ids[0]])
        }
        await #expect(throws: (any Error).self) {
            _ = try await describe(submission, ids: [ids[0], ids[0]])
        }
        // Submission order is explicit. It is neither UUID nor storage order.
        let reversed = try frozen.entries.reversed().enumerated().map { index, entry in
            try Fixture.copy(entry, changes: ["position": index])
        }
        let reordered: SharedMediaNativeFrozenCohort = try Fixture.copy(frozen,
            changes: ["entries": reversed.map(Fixture.object)])
        let ordered = try await describe(.init(bytes: reordered.encoded()), ids: ids)
        #expect(ordered.orderedRequests.map(\.source) == result.orderedRequests.reversed().map(\.source))

        // Even valid old bytes stop matching after a supported metadata edit.
        let metadata = try await owner.prepareAppMetadata(packageID: frozen.packageID,
            draftGeneration: frozen.draftGeneration, contexts: [.init(freeText: "Updated synthetic notes")], presentation: [])
        _ = try await owner.saveAppMetadata(metadata)
        await #expect(throws: (any Error).self) { _ = try await describe(submission, ids: ids) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        await #expect(throws: (any Error).self) { _ = try await describe(submission, ids: ids) }
    }
}
