import Foundation
@testable import Merian
import Testing

@Suite("Ordinary photo hold submission binding", .serialized)
@MainActor
struct SharedMediaOrdinaryPhotoHoldBindingTests {
    typealias Fixture = SharedMediaNativeReceivingTestFixture

    @Test(arguments: [1, 2])
    func exactExistingSubmissionBytesPreserveMediaOrderAndPerSourceRecipes(_ count: Int) async throws {
        let (store, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture(count: count)
        let fixture = try Fixture.capture(store, request: request)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let submission = fixture.request.freeze.commit.cohort
        let frozen = try SharedMediaNativeFrozenCohort.decode(submission.bytes)
        let generation = UUID(), eventID = UUID(), epoch = UUID(), scanID = UUID()
        // Intentionally reverse UUID membership ordering relative to media.
        let ids = (0..<count).map { _ in UUID() }.sorted { $0.uuidString > $1.uuidString }
        let requests = try frozen.entries.enumerated().map { index, entry in
            let intent = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes)
            let reference = intent.preparation.original.reference
            let receipt = try #require(fixture.receipts.first { $0.0.assetID == reference.assetID })
            return try SharedMediaOrdinaryHoldRequest(id: ids[index], profile: fixture.request.profile, writerEpoch: epoch,
                source: reference, acquisition: receipt.0, completion: receipt.1,
                recipient: .init(scanID: scanID, submissionGeneration: generation, eventID: eventID,
                    observationSHA256: submission.sha256, preparationSHA256: entry.intent.sha256),
                inventoryRevision: fixture.request.header.inventory.revision,
                sourcePackageRevision: fixture.request.package.revision, sourceMembershipRevision: fixture.request.member.revision,
                liveCount: 1, countRevision: 0)
        }
        let holds = try SharedMediaOrdinaryHoldCohort(requests)
        let binding = try SharedMediaOrdinaryPhotoHoldBinding(holds: holds, submission: submission)
        #expect(binding.submission == submission)
        #expect(binding.orderedRequests == requests)
        let durable = try SharedMediaOrdinarySubmission(binding: binding)
        let bytes = try durable.encoded()
        let decoded = try SharedMediaOrdinarySubmission.decode(bytes, sha256: SharedMediaAcquisitionEncoding.digest(bytes))
        #expect(decoded == durable && decoded.observation == submission)
        #expect(decoded.members.map(\.holdID) == ids)
        try decoded.validate(holds: holds)
        try SharedMediaSubmissionReceiptTests.check(binding)
        try await SharedMediaOrdinaryAccountingTests.check(binding, container: store.container, detachedFixtureID: store.ordinaryID) {
            let cold = try await SharedMediaNativeReceivingStagingTests().reopen(store)
            #expect(try await cold.inspectApp().pendingPackages == 1)
            await #expect(throws: (any Error).self) { _ = try await cold.prepareAppOriginalRemoval(requests[0].source) }
            #expect(await cold.invalidateAndAwaitForAccountTransition())
            try SharedMediaNativeAppReceivingTests().seedLegacyReceived(store, request)
            let received = try await SharedMediaNativeReceivingStagingTests().reopen(store)
            #expect(try await received.inspectApp().consumers == 1)
            await #expect(throws: (any Error).self) { _ = try await received.prepareAppOriginalRemoval(requests[0].source) }
            #expect(await received.invalidateAndAwaitForAccountTransition())
        }
        let damaged: SharedMediaOrdinarySubmission.Member = try Fixture.copy(durable.members[0],
            changes: ["requestSHA256": String(repeating: "0", count: 64)])
        let unequal: SharedMediaOrdinarySubmission = try Fixture.copy(durable,
            changes: ["members": ([damaged] + durable.members.dropFirst()).map(Fixture.object)])
        #expect(throws: (any Error).self) { try unequal.validate(holds: holds) }
        #expect(throws: (any Error).self) {
            _ = try SharedMediaOrdinarySubmission.decode(bytes + Data([0]), sha256: SharedMediaAcquisitionEncoding.digest(bytes))
        }
        if count == 2 {
            let reordered: SharedMediaOrdinarySubmission = try Fixture.copy(durable,
                changes: ["members": durable.members.reversed().map(Fixture.object)])
            #expect(throws: (any Error).self) { _ = try reordered.encoded() }
        }
        if count == 2 {
            #expect(holds.requests.map(\.id) != binding.orderedRequests.map(\.id))
            #expect(requests[0].recipient.preparationSHA256 != requests[1].recipient.preparationSHA256)
            #expect(throws: (any Error).self) {
                _ = try SharedMediaOrdinaryPhotoHoldBinding(holds: .init([requests[0]]), submission: submission)
            }
        }
        // Valid descriptive hashes cannot stand in for the exact frozen body.
        let first = try #require(requests.first)
        let wrongPreparation: SharedMediaOrdinaryHoldRequest.Recipient = .init(scanID: scanID,
            submissionGeneration: generation, eventID: eventID, observationSHA256: submission.sha256,
            preparationSHA256: String(repeating: "0", count: 64))
        let changed: SharedMediaOrdinaryHoldRequest = try Fixture.copy(first,
            changes: ["recipient": Fixture.object(wrongPreparation)])
        let wrong = try SharedMediaOrdinaryHoldCohort([changed] + requests.dropFirst())
        #expect(throws: (any Error).self) { _ = try SharedMediaOrdinaryPhotoHoldBinding(holds: wrong, submission: submission) }

        let changedCompletion: SharedMediaAcquisitionResult = try Fixture.copy(first.completion,
            changes: ["sha256": String(repeating: "0", count: 64)])
        let wrongOriginal: SharedMediaOrdinaryHoldRequest = try Fixture.copy(first,
            changes: ["completion": Fixture.object(changedCompletion)])
        let rebound = try SharedMediaOrdinaryHoldCohort([wrongOriginal] + requests.dropFirst())
        #expect(throws: (any Error).self) { _ = try SharedMediaOrdinaryPhotoHoldBinding(holds: rebound, submission: submission) }

        // Rehashing a self-consistent foreign/future preparation does not make
        // it belong to the current original owner or source revision.
        let firstEntry = try #require(frozen.entries.first)
        let firstIntent = try SharedMediaNativeDerivativeIntent.decode(firstEntry.intent.bytes)
        let drifts: [String: Any] = ["inventoryID": UUID().uuidString, "inventoryGeneration": UUID().uuidString,
            "inventoryRevision": first.inventoryRevision + 1, "packageRevision": first.sourcePackageRevision + 1,
            "membershipRevision": first.sourceMembershipRevision + 1]
        for (key, value) in drifts {
            let preparation: SharedMediaNativePreparedIdentity = try Fixture.copy(firstIntent.preparation, changes: [key: value])
            let foreignIntent: SharedMediaNativeDerivativeIntent = try Fixture.copy(firstIntent,
                changes: ["preparation": Fixture.object(preparation)])
            let foreignEntry: SharedMediaNativeFrozenEntry = try Fixture.copy(firstEntry,
                changes: ["intent": Fixture.object(SharedMediaNativePreparationBlob(bytes: foreignIntent.encoded()))])
            let entries = [foreignEntry] + frozen.entries.dropFirst()
            let foreign: SharedMediaNativeFrozenCohort = try Fixture.copy(frozen, changes: ["entries": entries.map(Fixture.object)])
            let body = try SharedMediaNativePreparationBlob(bytes: foreign.encoded())
            let resigned = try requests.enumerated().map { index, request -> SharedMediaOrdinaryHoldRequest in
                let recipient = SharedMediaOrdinaryHoldRequest.Recipient(scanID: scanID, submissionGeneration: generation,
                    eventID: eventID, observationSHA256: body.sha256, preparationSHA256: entries[index].intent.sha256)
                return try Fixture.copy(request, changes: ["recipient": Fixture.object(recipient)])
            }
            #expect(throws: (any Error).self) {
                _ = try SharedMediaOrdinaryPhotoHoldBinding(holds: .init(resigned), submission: body)
            }
        }

        let otherContext = try fixture.context("A changed synthetic observation")
        #expect(throws: (any Error).self) {
            _ = try SharedMediaOrdinaryPhotoHoldBinding(holds: holds, submission: otherContext.request.freeze.commit.cohort)
        }
        var extra = requests
        let unrelated: SharedMediaOrdinaryHoldRequest = try Fixture.copy(first, changes: ["id": UUID().uuidString])
        extra.append(unrelated)
        #expect(throws: (any Error).self) { _ = try SharedMediaOrdinaryHoldCohort(extra) }
    }
}
