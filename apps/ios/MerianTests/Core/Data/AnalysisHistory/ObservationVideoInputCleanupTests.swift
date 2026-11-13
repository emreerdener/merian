import Darwin
import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationVideoInputCleanupTests {
    @Test func responsibilityPrecedesBootstrapAndForeignStartupCannotCopy() async throws {
        let seed = try ObservationReanalysisLocalVideoInputTests().seed(); defer { seed.remove() }
        let foreign = try ObservationReanalysisLocalVideoInputTests().seed(); defer { foreign.remove() }
        var retained: ObservationReanalysisLocalVideoInput?
        await #expect(throws: (any Error).self) {
            try await ObservationReanalysisLocalVideoInput.freeze(seed.choice(), descriptions: [], container: seed.container,
                files: seed.files, account: ObservationReanalysisProducerTests().account(), startup: foreign.startup,
                store: ObservationReanalysisFileStore(documents: seed.documents), ownership: .init(), owning: {
                    retained = $0
                    #expect(!FileManager.default.fileExists(atPath: seed.documents.appendingPathComponent("ReanalysisInputs").path))
                }, isCurrent: { true })
        }
        let input = try #require(retained)
        #expect(await input.discardCopiedInput())
        #expect(try ObservationReanalysisInputPersistence.read(child: input.analysisID, container: seed.container) == nil)
        #expect(!FileManager.default.fileExists(atPath: seed.documents.appendingPathComponent("ReanalysisInputs").path))
    }

    @Test(arguments: [false, true])
    func missingReceiptAfterAttemptNeverRepeatsCopy(afterCopy: Bool) async throws {
        let seed = try ObservationReanalysisLocalVideoInputTests().seed(); defer { seed.remove() }
        let namespace = seed.documents.appendingPathComponent("ReanalysisInputs")
        if !afterCopy { try FileManager.default.createDirectory(at: namespace, withIntermediateDirectories: false) }
        let account = ObservationReanalysisProducerTests().account(), store = ObservationReanalysisFileStore(documents: seed.documents)
        let producer = ObservationVideoPreparationProducer(files: store, ownership: .init(), account: account)
        var retained: ObservationReanalysisLocalVideoInput?
        do {
            _ = try await ObservationReanalysisLocalVideoInput.freeze(seed.choice(), descriptions: [], container: seed.container,
                files: seed.files, account: account, startup: seed.startup, store: store, ownership: producer.ownership,
                owning: { retained = $0 }, isCurrent: { true })
            #expect(afterCopy)
        } catch { #expect(!afterCopy) }
        let input = try #require(retained)
        var copiedURL: URL?, original: Data?
        if afterCopy {
            let receipt = try #require(try ObservationReanalysisInputPersistence.read(child: input.analysisID, container: seed.container))
            let url = namespace.appendingPathComponent("\(receipt.slot)/input.mp4")
            copiedURL = url; original = try Data(contentsOf: url)
            let context = ModelContext(seed.container)
            let row = try #require(try context.fetchOfflineJob(id: receipt.jobID))
            context.delete(row); try context.save()
        }
        // Even a different original cannot supply replacement bytes.
        try Data([99]).write(to: seed.documents.appendingPathComponent("chosen.mp4"), options: .atomic)
        for _ in 0..<2 {
            await #expect(throws: (any Error).self) {
                try await input.prepare(container: seed.container, account: account, producer: producer,
                    temporaryDirectory: seed.temporary, isCurrent: { true })
            }
        }
        #expect(await input.discardCopiedInput() == false)
        #expect(await input.discardCopiedInput() == false)
        #expect(try ObservationReanalysisInputPersistence.read(child: input.analysisID, container: seed.container) == nil)
        if let copiedURL { #expect(try Data(contentsOf: copiedURL) == original) }
        else { #expect(try FileManager.default.contentsOfDirectory(atPath: namespace.path).isEmpty) }
        // The hold is durable storage, not a leaked startup fence.
        let fence = try seed.startup.acquireFence(container: seed.container)
        try seed.startup.require(container: seed.container, fence: fence)
    }

    @Test func cleanupDuringSuspendedCohortKeepsDescriptorsUntilActualExit() async throws {
        let seed = try ObservationReanalysisLocalVideoInputTests().seed(); defer { seed.remove() }
        let media = try await VideoAudioFixture(channels: 1); defer { media.remove() }
        let original = seed.documents.appendingPathComponent("chosen.mp4")
        try FileManager.default.removeItem(at: original)
        try FileManager.default.copyItem(at: media.videoURL, to: original)
        let account = ObservationReanalysisProducerTests().account(), store = ObservationReanalysisFileStore(documents: seed.documents)
        let producer = ObservationVideoPreparationProducer(files: store, ownership: .init(), account: account)
        let input = try await ObservationReanalysisLocalVideoInput.freeze(seed.choice(), descriptions: [], container: seed.container,
            files: seed.files, account: account, startup: seed.startup, store: store, ownership: producer.ownership,
            owning: { _ in }, isCurrent: { true })
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        input.inputPhaseCheckpoint = { phase in
            if phase == .frames { await entered.open(); await release.wait() }
        }
        let consuming = Task { @MainActor in
            defer { Task { await entered.open() } }
            return try await input.prepare(container: seed.container, account: account, producer: producer,
                temporaryDirectory: media.outputDirectory, isCurrent: { true })
        }
        await entered.wait()
        #expect(await input.discardCopiedInput() == false)
        #expect(!canLockExclusively(seed.documents))
        #expect(throws: (any Error).self) { _ = try seed.startup.acquireFence(container: seed.container) }
        await release.open()
        await #expect(throws: (any Error).self) { _ = try await consuming.value }
        #expect(await input.discardCopiedInput())
        #expect(canLockExclusively(seed.documents))
    }

    @Test func replacedStartupFenceDeniesPreparationAndKeepsStorageHold() async throws {
        let seed = try ObservationReanalysisLocalVideoInputTests().seed(); defer { seed.remove() }
        let account = ObservationReanalysisProducerTests().account(), store = ObservationReanalysisFileStore(documents: seed.documents)
        let producer = ObservationVideoPreparationProducer(files: store, ownership: .init(), account: account)
        let input = try await ObservationReanalysisLocalVideoInput.freeze(seed.choice(), descriptions: [], container: seed.container,
            files: seed.files, account: account, startup: seed.startup, store: store, ownership: producer.ownership,
            owning: { _ in }, isCurrent: { true })
        let receipt = try #require(try ObservationReanalysisInputPersistence.read(child: input.analysisID, container: seed.container))
        let path = seed.documents.appendingPathComponent("ReanalysisInputs/\(receipt.slot)/input.mp4")
        let bytes = try Data(contentsOf: path)
        let original = seed.root.appendingPathComponent(SharedMediaStoreReadFence.name), moved = original.appendingPathExtension("retained")
        try FileManager.default.moveItem(at: original, to: moved)
        try Data().write(to: original)
        #expect(!canLockExclusively(moved))
        await #expect(throws: (any Error).self) {
            try await input.prepare(container: seed.container, account: account, producer: producer,
                temporaryDirectory: seed.temporary, isCurrent: { true })
        }
        #expect(await input.discardCopiedInput() == false)
        #expect(canLockExclusively(moved) && canLockExclusively(seed.documents))
        #expect(try ObservationReanalysisInputPersistence.read(child: input.analysisID, container: seed.container) == receipt)
        #expect(try Data(contentsOf: path) == bytes)
    }

    @Test func digestPreservesTextOrderAndExactUTF8() async throws {
        let child = UUID()
        var digests: [String] = []
        var captured: String?
        for texts in [["First", "Second"], ["Second", "First"], ["é"], ["e\u{301}"], ["First", "Second"]] {
            let seed = try ObservationReanalysisLocalVideoInputTests().seed(); defer { seed.remove() }
            let context = ModelContext(seed.container), parent = try seed.parent(context)
            if let captured { parent.capturedMediaJSON = captured; try context.save() }
            else { captured = parent.capturedMediaJSON }
            let input = try await ObservationReanalysisLocalVideoInput.freeze(seed.choice(), descriptions: texts,
                container: seed.container, files: seed.files, account: ObservationReanalysisProducerTests().account(),
                startup: seed.startup, store: ObservationReanalysisFileStore(documents: seed.documents), ownership: .init(),
                analysisID: child, owning: { _ in }, isCurrent: { true })
            let receipt = try #require(try ObservationReanalysisInputPersistence.read(child: child, container: seed.container))
            digests.append(receipt.planDigest)
            #expect(await input.discardCopiedInput())
        }
        #expect(digests.first == digests.last)
        #expect(Set(digests.prefix(4)).count == 4)
    }

    private func canLockExclusively(_ url: URL) -> Bool {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return false }
        defer { Darwin.close(descriptor) }
        return flock(descriptor, LOCK_EX | LOCK_NB) == 0
    }

    @Test(arguments: [false, true])
    func postCopyFailureTransfersOriginalTokenBeforeThrow(replace: Bool) async throws {
        let seed = try ObservationReanalysisLocalVideoInputTests().seed(); defer { seed.remove() }
        let id = UUID(), files = seed.files
        var retained: ObservationReanalysisLocalVideoInput?, copied = false, replacement: URL?
        await #expect(throws: (any Error).self) {
            try await ObservationReanalysisLocalVideoInput.freeze(seed.choice(), descriptions: ["Exact context"],
                container: seed.container, files: files, account: ObservationReanalysisProducerTests().account(),
                startup: seed.startup, store: ObservationReanalysisFileStore(documents: seed.documents), ownership: .init(),
                analysisID: id, owning: { retained = $0 }, retaining: { _ in copied = true }, isCurrent: {
                    if copied {
                        #expect(retained?.analysisID == id)
                        if replace {
                            do {
                                let receipt = try #require(try ObservationReanalysisInputPersistence.read(child: id, container: seed.container))
                                let copy = seed.documents.appendingPathComponent("ReanalysisInputs/\(receipt.slot)/input.mp4")
                                try Data([9]).write(to: copy, options: .atomic); replacement = copy
                            } catch { Issue.record(error) }
                        }
                        return false
                    }
                    return true
                })
        }
        let input = try #require(retained)
        #expect(input.analysisID == id && input.descriptions == ["Exact context"])
        #expect(await input.discardCopiedInput() == !replace)
        if let replacement { #expect(try Data(contentsOf: replacement) == Data([9])) }
        else { #expect(try FileManager.default.contentsOfDirectory(atPath: seed.temporary.path).isEmpty) }
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
    }
    @Test func cancellationAfterTokenRetentionCanPrepareSameInputAndChild() async throws {
        let seed = try ObservationReanalysisLocalVideoInputTests().seed(); defer { seed.remove() }
        let media = try await VideoAudioFixture(channels: 1); defer { media.remove() }
        let original = seed.documents.appendingPathComponent("chosen.mp4")
        try FileManager.default.removeItem(at: original)
        try FileManager.default.copyItem(at: media.videoURL, to: original)
        let account = ObservationReanalysisProducerTests().account(), id = UUID()
        var retained: ObservationReanalysisLocalVideoInput?
        let copying = Task { @MainActor in
            try await ObservationReanalysisLocalVideoInput.freeze(seed.choice(), descriptions: ["Original text"],
                container: seed.container, files: seed.files, account: account,
                startup: seed.startup, store: ObservationReanalysisFileStore(documents: seed.documents), ownership: .init(), analysisID: id,
                owning: { retained = $0 }, retaining: { _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                }, isCurrent: { true })
        }
        await #expect(throws: CancellationError.self) { _ = try await copying.value }
        let input = try #require(retained)
        let receipt = try #require(try ObservationReanalysisInputPersistence.read(child: id, container: seed.container))
        #expect(receipt.phase == .copied)
        let snapshot = seed.documents.appendingPathComponent("ReanalysisInputs/\(receipt.slot)/input.mp4")
        let bytes = try Data(contentsOf: snapshot)
        let producer = ObservationVideoPreparationProducer(files: .init(documents: seed.documents),
            ownership: .init(), account: account)
        let result = try await input.prepare(container: seed.container, account: account, producer: producer,
            temporaryDirectory: media.outputDirectory, isCurrent: { true })
        #expect(result.preparation.identity.analysisID == id)
        #expect(result.preparation.request.manifest.descriptions == ["Original text"])
        #expect(try Data(contentsOf: snapshot) == bytes)
        #expect(await input.discardCopiedInput())
        #expect(await input.discardCopiedInput())
        #expect(try FileManager.default.contentsOfDirectory(atPath: seed.temporary.path).isEmpty)
    }

}
