import CryptoKit
import Darwin
import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationReanalysisRecoveryTests {
    let sourceFixture = ObservationReanalysisSourceTests()
    let producerFixture = ObservationReanalysisProducerTests()

    struct Seed {
        let container: ModelContainer
        let root: URL
        let pending: ObservationReanalysisPreparationIntent
        let source: ObservationReanalysisSource
        let bytes: Data
        var file: URL { root.appendingPathComponent(pending.draft.photoPaths[0]) }
    }

    func seed(action: ObservationReanalysisPreparationIntent.Action = .hold, url: URL? = nil) throws -> Seed {
        let seed = try sourceFixture.seed(version: 3, url: url)
        let source = try producerFixture.source(seed), bytes = try producerFixture.image()
        let photo = ObservationEvidenceUpload.Reference(mediaID: UUID(), contentType: "image/png", byteCount: bytes.count,
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
        let draft = try ObservationReanalysisDraft(identity: .init(observationID: source.observationID, sourceAnalysisID: source.analysisID,
            analysisID: UUID(), ownerID: source.ownerID), evidence: [.description("Before"), .image(photo), .description("After")])
        let pending = try ObservationReanalysisPreparationIntent(draft: draft, source: source, action: action)
        _ = try ObservationReanalysisPersistence.beginPreparation(pending.verified(source: source), container: seed.container, isCurrent: { true })
        return Seed(container: seed.container, root: try ObservationReanalysisFileStoreTests().directory(), pending: pending, source: source, bytes: bytes)
    }

    func publish(_ seed: Seed) async throws {
        // Models a crash after canonical files reached disk, before the ready CAS.
        try await ObservationReanalysisFileStore(documents: seed.root).persist(draft: seed.pending.draft, photos: [seed.bytes]) {}
    }

    func recover(_ seed: Seed, current: @escaping @MainActor @Sendable () -> Bool = { true }) async throws -> ObservationReanalysisPersistence.DraftState {
        try await ObservationReanalysisPreparationRecovery(files: .init(documents: seed.root), ownership: .init(), account: producerFixture.account())
            .recover(seed.pending.draft.identity, container: seed.container, isCurrent: current)
    }

    func expectPending(_ seed: Seed) throws {
        guard case let .pending(pending) = try ObservationReanalysisPersistence.preparation(seed.pending.draft.identity,
            container: seed.container, isCurrent: { true }) else { Issue.record("Pending preparation was replaced"); return }
        #expect(pending == seed.pending)
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
    }

    @Test func completedCohortRecoversSameChildAndPreservesSelectionAndTerminalReplay() async throws {
        let seed = try seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        try await publish(seed)
        let inode = try FileManager.default.attributesOfItem(atPath: seed.file.path)[.systemFileNumber] as? NSNumber
        guard case let .draft(draft) = try await recover(seed) else { Issue.record("Recovery failed to produce held draft"); return }
        #expect(draft == seed.pending.draft)
        #expect(try FileManager.default.attributesOfItem(atPath: seed.file.path)[.systemFileNumber] as? NSNumber == inode)
        let context = ModelContext(seed.container), parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(parent.selectedAnalysisID == seed.source.analysisID.uuidString.lowercased() && parent.observationStateRevision == 10)
        let bound = try ObservationReanalysisPersistence.bindDraft(draft, processor: .gemini, container: seed.container, isCurrent: { true })
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        job.status = .complete; job.attemptCount = 2; try context.save()
        try FileManager.default.removeItem(at: seed.file)
        guard case let .bound(replay) = try await recover(seed) else { Issue.record("Terminal state was revived"); return }
        #expect(replay.intent == bound.intent && replay.isTerminal)
        #expect(!FileManager.default.fileExists(atPath: seed.file.path))
    }

    @Test(arguments: ["missing-directory", "missing-photo", "extra", "temporary", "digest", "symlink", "fifo"])
    func incompleteOrChangedCohortStaysHeldWithoutRepair(reason: String) async throws {
        let seed = try seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        if reason != "missing-directory" { try await publish(seed) }
        switch reason {
        case "missing-photo": try FileManager.default.removeItem(at: seed.file)
        case "extra", "temporary":
            let name = reason == "extra" ? "extra.png" : ".interrupted.preparing"
            try Data([9]).write(to: seed.file.deletingLastPathComponent().appendingPathComponent(name))
        case "digest": try Data(repeating: 0, count: seed.bytes.count).write(to: seed.file)
        case "symlink":
            let target = seed.root.appendingPathComponent("retained.png"); try seed.bytes.write(to: target)
            try FileManager.default.removeItem(at: seed.file)
            try FileManager.default.createSymbolicLink(at: seed.file, withDestinationURL: target)
        case "fifo":
            try FileManager.default.removeItem(at: seed.file); #expect(mkfifo(seed.file.path, 0o600) == 0)
        default: break
        }
        await #expect(throws: (any Error).self) { try await recover(seed) }
        try expectPending(seed)
        if reason == "missing-directory" { #expect(try FileManager.default.contentsOfDirectory(atPath: seed.root.path).isEmpty) }
        if reason == "missing-photo" { #expect(!FileManager.default.fileExists(atPath: seed.file.path)) }
    }

    @Test func accountChangeAndChangedSourceCannotAdoptFiles() async throws {
        let seed = try seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        try await publish(seed)
        await #expect(throws: ObservationHistoryError.accountChanged) { try await recover(seed, current: { false }) }
        let context = ModelContext(seed.container), record = try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let replacement = try LocalAnalysisRecord(analysisID: seed.source.analysisID, observationID: parent.id, ownerAccountID: seed.source.ownerID,
            completedAt: record.completedAt, snapshotVersion: record.snapshotVersion,
            resultSnapshotData: JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: record.resultSnapshotData), options: [.prettyPrinted, .sortedKeys]))
        context.delete(record); try context.save(); context.insert(replacement); parent.analysisRecords = [replacement]; try context.save()
        await #expect(throws: (any Error).self) { try await recover(seed) }
        try expectPending(seed)
        #expect(try Data(contentsOf: seed.file) == seed.bytes)
    }

    @Test func accountLossAfterCommitWithholdsResultButRetainsReadyDraft() async throws {
        let seed = try seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        try await publish(seed)
        var finished = 0
        let account = producerFixture.account(current: {
            // A fresh context sees only durable state. Lose the lease as soon as ready commits.
            let context = ModelContext(seed.container)
            guard let job = try? context.fetch(FetchDescriptor<OfflineJobRecord>()).first,
                  let text = job.metadataJSON else { return false }
            return (try? ObservationReanalysisPreparationIntent.decode(Data(text.utf8))) != nil
        }, finish: { finished += 1 })
        await #expect(throws: ObservationHistoryError.accountChanged) {
            try await ObservationReanalysisPreparationRecovery(files: .init(documents: seed.root), ownership: .init(), account: account)
                .recover(seed.pending.draft.identity, container: seed.container, isCurrent: { true })
        }
        #expect(finished == 1)
        guard case let .ready(.draft(draft)) = try ObservationReanalysisPersistence.preparation(seed.pending.draft.identity,
            container: seed.container, isCurrent: { true }) else { Issue.record("Committed draft was lost"); return }
        #expect(draft == seed.pending.draft)
        #expect(try Data(contentsOf: seed.file) == seed.bytes)
    }

    @Test func lateDeletionAndFailedSaveNeverReinsertOrDeleteRecoveryFiles() async throws {
        for deleting in [false, true] {
            let seed = try seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
            try await publish(seed)
            let proof = try seed.pending.verified(source: seed.source)
            await #expect(throws: (any Error).self) {
                try await ObservationReanalysisFileStore(documents: seed.root).recover(draft: seed.pending.draft, validateBeforeRead: {
                    try ObservationReanalysisPersistence.validatePreparation(proof, container: seed.container, isCurrent: { true })
                }) {
                    if deleting {
                        let context = ModelContext(seed.container)
                        _ = try ObservationReanalysisErasure.removeChildren(of: seed.source.observationID.uuidString, context: context)
                        try context.save()
                    }
                    try ObservationReanalysisPersistence.validatePreparation(proof, container: seed.container, isCurrent: { true }, makeReady: true,
                        save: { _ in throw CocoaError(.fileWriteUnknown) })
                }
            }
            #expect(try Data(contentsOf: seed.file) == seed.bytes)
            if !deleting { try expectPending(seed) }
            #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == (deleting ? 0 : 1))
        }
    }
}
