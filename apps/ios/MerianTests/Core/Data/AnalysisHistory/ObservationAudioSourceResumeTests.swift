import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationAudioSourceResumeTests {
    typealias Store = ObservationAudioSourceResumeStore
    typealias Reader = ObservationAudioSourceResumeReader
    let fixture = ObservationAudioSourceSubmissionTests()

    @Test(arguments: ["staged", "running", "unknown", "reserved", "held", "unavailable", "conflict"])
    func exactSourceRecoveryNeedsNoFileAndNeverChangesMetadata(_ state: String) async throws {
        let seed = try await fixture.fixture.fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let original = try fixture.state(state, seed: seed)
        try FileManager.default.removeItem(at: seed.file)
        let saved = try await Store().read(original.identity, container: seed.container, isCurrent: { true })
        #expect(saved.snapshot == original && saved.source == seed.source && saved.proof.preparation == seed.preparation)
        #expect(try ObservationSourceReservationStore.read(original.identity, container: seed.container, isCurrent: { true }) == original)
        await #expect(throws: (any Error).self) {
            try await ObservationAudioResumeStore.read(original.identity, container: seed.container, isCurrent: { true })
        }
        #expect(!FileManager.default.fileExists(atPath: seed.file.path))
    }

    @Test(arguments: ["account", "owner", "parent", "child", "source", "metadata", "partial", "row", "bound", "preparation"])
    func invalidOrLegacyWorkCannotBecomeSourceRecovery(_ damage: String) async throws {
        let seed = try await fixture.fixture.fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        if damage == "bound" { _ = try fixture.fixture.fixture.bind(seed) }
        if damage != "bound" && damage != "preparation" { _ = try fixture.state("staged", seed: seed) }
        let identity = seed.preparation.identity, context = ModelContext(seed.container)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        if damage == "metadata" { job.metadataJSON = "{}" }
        if damage == "partial" { context.delete(job) }
        if damage == "row" { try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first).queueAttemptCount = 1 }
        try context.save()
        let target = OfflineQueueWork.Reanalysis(observationID: damage == "parent" ? UUID() : identity.observationID,
            sourceAnalysisID: damage == "source" ? UUID() : identity.sourceAnalysisID,
            analysisID: damage == "child" ? UUID() : identity.analysisID, ownerID: damage == "owner" ? UUID() : identity.ownerID)
        await #expect(throws: (any Error).self) {
            try await Store().read(target, container: seed.container, isCurrent: { damage != "account" })
        }
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
    }

    @Test(arguments: ["account", "delete", "cas", "proof"])
    func verificationAwaitCannotReturnStaleOrForgedProof(_ change: String) async throws {
        let seed = try await fixture.fixture.fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let entry = try fixture.state("staged", seed: seed), original = Store().verify
        var current = true
        let store = Store(verify: { data, identity, source in
            let proof = try await original(data, identity, source)
            if change == "account" { current = false }
            if change == "delete" {
                let context = ModelContext(seed.container)
                context.delete(try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)); try context.save()
            }
            if change == "cas" {
                _ = try ObservationSourceReservationStore.claim(entry, admission: .initial, proof: .audio(proof),
                    container: seed.container, isCurrent: { true })
            }
            if change == "proof" {
                let other = try ObservationAudioPreparationTests().seed(action: .submit)
                defer { try? FileManager.default.removeItem(at: other.root) }
                return try other.proof
            }
            return proof
        })
        await #expect(throws: (any Error).self) {
            try await store.read(entry.identity, container: seed.container, isCurrent: { current })
        }
    }

    @Test func cancellationRetainsLeaseAndSlotUntilVerifierExits() async throws {
        let seed = try await fixture.fixture.fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let entry = try fixture.state("staged", seed: seed), owner = ObservationReanalysisPreparationOwner()
        let entered = AsyncStream<Void>.makeStream(), release = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish(); release.continuation.finish() }
        var finishes = 0
        let account = fixture.fixture.fixture.fixture.fixture.account(finish: {
            #expect(owner.contains(entry.identity.analysisID)); finishes += 1
        })
        let original = Store().verify
        let reader = Reader(ownership: owner, account: account, store: .init(verify: { data, identity, source in
            let proof = try await original(data, identity, source)
            entered.continuation.yield(())
            // A continuation models verification that does not complete just because its waiter cancels.
            await withCheckedContinuation { continuation in
                Task { @MainActor in
                    for await _ in release.stream { break }
                    continuation.resume()
                }
            }
            return proof
        }))
        let task = Task { try await reader.read(entry.identity, container: seed.container, isCurrent: { true }) }
        for await _ in entered.stream { break }
        await #expect(throws: (any Error).self) {
            try await reader.read(entry.identity, container: seed.container, isCurrent: { true })
        }
        owner.cancelAll()
        #expect(owner.contains(entry.identity.analysisID) && finishes == 0)
        release.continuation.yield(())
        await #expect(throws: (any Error).self) { try await task.value }
        await owner.cancelAndAwaitAll()
        #expect(!owner.contains(entry.identity.analysisID) && finishes == 1)
        #expect(try ObservationSourceReservationStore.read(entry.identity, container: seed.container, isCurrent: { true }) == entry)
    }

    @Test func foreignLeaseCannotReadAndAlwaysReleasesOwnership() async throws {
        let seed = try await fixture.fixture.fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let entry = try fixture.state("staged", seed: seed), owner = ObservationReanalysisPreparationOwner()
        var finishes = 0
        var account = ObservationReanalysisProducerTests().account(finish: {
            #expect(owner.contains(entry.identity.analysisID)); finishes += 1
        })
        account.begin = { requested in
            #expect(requested == entry.identity.ownerID)
            return .init(id: UUID(), session: .init(userID: UUID(), isAnonymous: false))
        }
        account.isCurrent = { _ in true }
        let reader = Reader(ownership: owner, account: account, store: .init(verify: { _, _, _ in
            Issue.record("Foreign lease reached private proof verification")
            throw MerianError.invalidResponse
        }))
        await #expect(throws: (any Error).self) {
            try await reader.read(entry.identity, container: seed.container, isCurrent: { true })
        }
        #expect(finishes == 1 && !owner.contains(entry.identity.analysisID))
        #expect(try ObservationSourceReservationStore.read(entry.identity, container: seed.container, isCurrent: { true }) == entry)
    }

    @Test(arguments: [3, 4])
    func reopenedDiskStoreRetainsExactSourceAndRequest(sourceVersion: Int) async throws {
        let root = try ObservationReanalysisFileStoreTests().directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("history.store")
        let expected: ObservationSourceReservationStore.Snapshot = try await {
            let seed = try ObservationAudioPreparationTests().seed(action: .submit, sourceVersion: sourceVersion, url: url)
            defer { try? FileManager.default.removeItem(at: seed.root) }
            _ = try await ObservationAudioPreparationTests().producer(seed).prepare(seed.preparation, source: seed.source,
                bytes: seed.bytes, container: seed.container, isCurrent: { true })
            return try fixture.state("unknown", seed: seed)
        }()
        let container = try ObservationPublicationPersistenceTests().container(url: url, seed: false)
        let owner = ObservationReanalysisPreparationOwner()
        let reader = Reader(ownership: owner, account: ObservationReanalysisProducerTests().account())
        let saved = try await reader.read(expected.identity, container: container, isCurrent: { true })
        #expect(saved.snapshot.metadata == expected.metadata && saved.snapshot.work == expected.work)
        #expect(saved.snapshot.containerID == ObjectIdentifier(container) && !owner.contains(expected.identity.analysisID))
    }
}
