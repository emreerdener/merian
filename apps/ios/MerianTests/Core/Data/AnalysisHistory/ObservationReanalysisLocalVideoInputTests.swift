import Darwin
import Foundation
@testable import Merian
import os
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationReanalysisLocalVideoInputTests {
    @MainActor struct Seed {
        let root: URL
        let documents: URL
        let temporary: URL
        let container: ModelContainer
        let source: ObservationReanalysisSource
        let startup: NativeReleaseStartupAdmission
        var files: FileIOActor { .init(documents: documents, temporaryDirectory: temporary) }
        func remove() { try? FileManager.default.removeItem(at: root) }
        func parent(_ context: ModelContext) throws -> LocalScanRecord {
            try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        }
        func choice() throws -> ObservationReanalysisLocalVideoInput.Choice {
            try #require(ObservationReanalysisLocalVideoInput.choices(source: source, container: container).first)
        }
    }
    func seed(reference: StoredMediaReference = .documents("chosen.mp4")) throws -> Seed {
        let root = try ObservationReanalysisFileStoreTests().directory()
        let documents = root.appendingPathComponent("Documents"), temporary = root.appendingPathComponent("tmp")
        for url in [documents, temporary] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        let outcome = ModelContainerBootstrapper.fixtureBootstrap {
            try PersistentStoreBootstrapSession.fixture(schema: Schema(versionedSchema: CurrentSchema.self),
                storeURL: root.appendingPathComponent("library.sqlite"), anchor: root)
        }
        let container = try #require(outcome.container), startup = try #require(outcome.nativeReleaseAdmission)
        let fixture = ObservationReanalysisSourceTests(), history = try fixture.seed(version: 3, in: container)
        let context = ModelContext(history.container)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        parent.capturedMediaJSON = CapturedMediaSnapshot(items: [.video(.init(video: reference))]).jsonString
        try context.save()
        let source = try ObservationReanalysisSource.captureForVideo(observationID: history.observationID,
            ownerID: fixture.fixture.owner, container: history.container)
        try Data(repeating: 7, count: 150_001).write(to: documents.appendingPathComponent("chosen.mp4"))
        return Seed(root: root, documents: documents, temporary: temporary, container: history.container, source: source, startup: startup)
    }

    @Test(arguments: ["remote", "absolute", "nested", "empty", "native", "damaged"])
    func unsupportedAttachmentsNeverBecomeChoices(reason: String) throws {
        let reference: StoredMediaReference
        switch reason {
        case "remote": reference = .remoteURL("https://example.invalid/clip.mp4")
        case "absolute": reference = .absolutePath("/tmp/clip.mp4")
        case "nested": reference = .documents("ReanalysisQueue/clip.mp4")
        case "empty": reference = .documents("")
        default: reference = .documents("chosen.mp4")
        }
        let seed = try seed(reference: reference); defer { seed.remove() }
        let context = ModelContext(seed.container), parent = try seed.parent(context)
        if reason == "native" { parent.mediaAuthorityRaw = "native" }
        if reason == "damaged" { parent.capturedMediaJSON = "{" }
        try context.save()
        do {
            #expect(try ObservationReanalysisLocalVideoInput.choices(source: seed.source, container: seed.container).isEmpty)
        } catch { #expect(reason == "native") }
    }

    @Test(arguments: ["descriptor", "owner", "deletion", "source", "account", "generation"], [false, true])
    func freezeRejectsChangedAuthorityBeforeAndAfterCopy(reason: String, afterCopy: Bool) async throws {
        let seed = try seed(); defer { seed.remove() }
        let choice = try seed.choice()
        let wrote = OSAllocatedUnfairLock(initialState: false)
        var io = FileIOActor.CopyIO.live
        io.write = { fd, bytes in
            let count = Darwin.write(fd, bytes.baseAddress, bytes.count)
            if count > 0 { wrote.withLock { $0 = true } }
            return count
        }
        let files = FileIOActor(documents: seed.documents, temporaryDirectory: seed.temporary, copyIO: io)
        var mutated = false, current = true, finished = 0
        var retained: ObservationReanalysisLocalVideoInput?
        let account = ObservationReanalysisProducerTests().account(current: { current }, finish: { finished += 1 })
        let validate: @MainActor @Sendable () -> Bool = {
            if !mutated && (!afterCopy || wrote.withLock({ $0 })) {
                mutated = true
                if reason == "account" { current = false } else if reason == "generation" { return false } else {
                    do {
                        let context = ModelContext(seed.container), parent = try seed.parent(context)
                        switch reason {
                        case "descriptor": parent.capturedMediaJSON = CapturedMediaSnapshot(items: [.video(.init(video: .documents("other.mp4")))]).jsonString
                        case "owner": parent.analysisOwnerAccountID = UUID().uuidString.lowercased()
                        case "deletion": context.insert(PendingCloudDeletionTask(scanId: parent.id))
                        default:
                            let row = try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)
                            context.delete(row)
                        }
                        try context.save()
                    } catch { Issue.record(error) }
                }
            }
            return true
        }
        await #expect(throws: (any Error).self) {
            try await ObservationReanalysisLocalVideoInput.freeze(choice, descriptions: [], container: seed.container,
                files: files, account: account, startup: seed.startup,
                store: ObservationReanalysisFileStore(documents: seed.documents), ownership: .init(), owning: { retained = $0 }, isCurrent: validate)
        }
        #expect(finished == 1)
        if let retained { #expect(await retained.discardCopiedInput()) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: seed.temporary.path).isEmpty)
        #expect(try Data(contentsOf: seed.documents.appendingPathComponent("chosen.mp4")) == Data(repeating: 7, count: 150_001))
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
    }

    @Test(arguments: ["beforeStage", "afterStage", "afterReady"])
    func interruptedPreparationRetainsExactCohortAndChild(boundary: String) async throws {
        let seed = try seed(); defer { seed.remove() }
        let media = try await VideoAudioFixture(channels: 1); defer { media.remove() }
        let original = seed.documents.appendingPathComponent("chosen.mp4")
        try FileManager.default.removeItem(at: original)
        try FileManager.default.copyItem(at: media.videoURL, to: original)
        let account = ObservationReanalysisProducerTests().account()
        let input = try await ObservationReanalysisLocalVideoInput.freeze(seed.choice(), descriptions: ["Exact context"],
            container: seed.container, files: seed.files, account: account, startup: seed.startup,
            store: ObservationReanalysisFileStore(documents: seed.documents), ownership: .init(), owning: { _ in }, isCurrent: { true })
        var interrupted = account, begins = 0, triggered = false
        interrupted.begin = { owner in
            begins += 1
            if boundary == "beforeStage", begins == 2 {
                triggered = true
                throw ObservationHistoryError.accountChanged
            }
            return try account.begin(owner)
        }
        interrupted.isCurrent = { lease in
            if triggered { return false }
            let rows = (try? ModelContext(seed.container).fetch(FetchDescriptor<OfflineJobRecord>())) ?? []
            if let decoded = rows.compactMap({ row in
                row.metadataJSON.flatMap { try? ObservationVideoPreparation.decode(Data($0.utf8)) }
            }).first,
               (boundary == "afterStage" && decoded.phase == .pending) ||
                (boundary == "afterReady" && decoded.phase == .ready) {
                triggered = true
                return false
            }
            return account.isCurrent(lease)
        }
        let store = ObservationReanalysisFileStore(documents: seed.documents)
        let failedProducer = ObservationVideoPreparationProducer(files: store, ownership: .init(), account: interrupted)
        await #expect(throws: (any Error).self) {
            try await input.prepare(container: seed.container, account: interrupted, producer: failedProducer,
                temporaryDirectory: media.outputDirectory, isCurrent: { true })
        }
        #expect(triggered)
        let preparation = try #require(input.preparation)
        #expect(preparation.identity.analysisID == input.analysisID)
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == (boundary == "beforeStage" ? 0 : 1))
        // No original clip remains usable for a new derivation. Retry must retain the exact cohort.
        try Data([9]).write(to: original, options: .atomic)
        let receipt = try #require(try ObservationReanalysisInputPersistence.read(child: input.analysisID, container: seed.container))
        let copies = [seed.documents.appendingPathComponent("ReanalysisInputs/\(receipt.slot)/input.mp4")]
        for copy in copies { try Data([8]).write(to: copy, options: .atomic) }
        let producer = ObservationVideoPreparationProducer(files: store, ownership: .init(), account: account)
        _ = try await input.prepare(container: seed.container, account: account, producer: producer,
            temporaryDirectory: media.outputDirectory, isCurrent: { true })
        #expect(input.preparation?.request == preparation.request)
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(try await store.readVideo(preparation: preparation, validateBeforeRead: {}, validateBeforeReturn: {}).count == 7)
        #expect(await input.discardCopiedInput() == false) // A replaced input cannot be erased by its old token.
        for copy in copies { #expect(try Data(contentsOf: copy) == Data([8])) }
    }

    @Test(arguments: [false, true])
    func chosenClipAndTextStayFrozenThroughPreparationAndRecovery(withText: Bool) async throws {
        let seed = try seed(); defer { seed.remove() }
        let media = try await VideoAudioFixture(channels: 1); defer { media.remove() }
        let originalURL = seed.documents.appendingPathComponent("chosen.mp4")
        try FileManager.default.removeItem(at: originalURL)
        try FileManager.default.copyItem(at: media.videoURL, to: originalURL)
        let original = try Data(contentsOf: originalURL)
        let account = ObservationReanalysisProducerTests().account(), files = seed.files
        let descriptions = withText ? ["  New e\u{301} 🐾\n", "After\n"] : []
        let input = try await ObservationReanalysisLocalVideoInput.freeze(seed.choice(), descriptions: descriptions,
            container: seed.container, files: files, account: account, startup: seed.startup,
                store: ObservationReanalysisFileStore(documents: seed.documents), ownership: .init(), owning: { _ in }, isCurrent: { true })
        #expect(try Data(contentsOf: originalURL) == original)
        // Current attachment and selection may subsequently change; frozen input/source do not.
        try Data([9]).write(to: originalURL, options: .atomic)
        let context = ModelContext(seed.container), parent = try seed.parent(context)
        parent.capturedMediaJSON = nil
        parent.selectedAnalysisID = UUID().uuidString.lowercased()
        try context.save()
        let selected = parent.selectedAnalysisID
        let store = ObservationReanalysisFileStore(documents: seed.documents)
        let producer = ObservationVideoPreparationProducer(files: store, ownership: .init(), account: account)
        _ = try await input.prepare(container: seed.container, account: account, producer: producer,
            temporaryDirectory: media.outputDirectory, isCurrent: { true })
        let preparation = try #require(input.preparation)
        let retained = try await store.readVideo(preparation: preparation, validateBeforeRead: {}, validateBeforeReturn: {})
        #expect(retained.count == 7 && preparation.identity.analysisID == input.analysisID)
        #expect(preparation.request.manifest.descriptions == descriptions)
        _ = try await input.prepare(container: seed.container, account: account, producer: producer,
            temporaryDirectory: media.outputDirectory, isCurrent: { true })
        #expect(input.preparation?.request == preparation.request)
        #expect(try await store.readVideo(preparation: preparation, validateBeforeRead: {}, validateBeforeReturn: {}) == retained)
        let fresh = ModelContext(seed.container)
        #expect(try seed.parent(fresh).selectedAnalysisID == selected)
        #expect(try fresh.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(try fresh.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 1)
        #expect(await input.discardCopiedInput())
        #expect(try Data(contentsOf: originalURL) == Data([9]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: seed.temporary.path).isEmpty)
        await #expect(throws: (any Error).self) {
            try await input.prepare(container: seed.container, account: account, producer: producer,
                temporaryDirectory: media.outputDirectory, isCurrent: { true })
        }
    }
}
