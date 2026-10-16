import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationAudioSavedStatusTests {
    typealias Reader = ObservationAudioSavedStatus
    let fixture = ObservationAudioExecutionStoreTests()

    @Test(arguments: ["pending", "ready", "idle", "running", "consumed", "held", "heldConsumed"])
    func exactPhasesNeverChangeJobsFilesOrSelection(_ mode: String) async throws {
        let seed = try fixture.fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        _ = try fixture.fixture.phase(seed)
        var expected: Reader.Phase = .filesPending
        if mode != "pending" {
            _ = try await fixture.fixture.producer(seed).prepare(seed.preparation, source: seed.source, bytes: seed.bytes,
                container: seed.container, isCurrent: { true })
            expected = .admissionPending
        }
        if mode != "pending" && mode != "ready" {
            let saved = try fixture.bind(seed); expected = .boundIdle
            if mode != "idle" {
                var claim = try ObservationAudioExecutionStore.claim(saved, purpose: .initial, proof: seed.proof,
                    container: seed.container, isCurrent: { true })
                let consumed = mode == "consumed" || mode == "heldConsumed"
                if consumed { claim = try ObservationAudioExecutionStore.consume(claim, proof: seed.proof, container: seed.container, isCurrent: { true }).claim }
                if mode == "held" || mode == "heldConsumed" {
                    try ObservationAudioExecutionStore.hold(claim, proof: seed.proof, container: seed.container, isCurrent: { true })
                    expected = consumed ? .heldConsumed : .heldUnconsumed
                } else { expected = consumed ? .runningConsumed : .runningUnconsumed }
            }
        }
        let context = ModelContext(seed.container), before = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first?.metadataJSON)
        let selected = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first?.selectedAnalysisID)
        let bytes = try? Data(contentsOf: seed.file)
        let page = try await Reader().page(ownerID: seed.source.ownerID, observationID: seed.source.observationID,
            container: seed.container, isCurrent: { true })
        #expect(page.items == [.init(identity: seed.preparation.identity, phase: expected)] && page.next == nil && page.omittedCount == 0)
        let fresh = ModelContext(seed.container)
        #expect(try fresh.fetch(FetchDescriptor<OfflineJobRecord>()).first?.metadataJSON == before)
        #expect(try fresh.fetch(FetchDescriptor<LocalScanRecord>()).first?.selectedAnalysisID == selected)
        #expect((try? Data(contentsOf: seed.file)) == bytes)
    }

    @Test func canonicalPagingAdvancesOverInvalidWorkAndCursorCannotCrossScope() async throws {
        let seed = try fixture.fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        _ = try fixture.fixture.phase(seed)
        let context = ModelContext(seed.container)
        for index in 1...20 {
            let child = try #require(UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 100)))
            let identity = OfflineQueueWork.Reanalysis(observationID: seed.source.observationID,
                sourceAnalysisID: seed.source.analysisID, analysisID: child, ownerID: seed.source.ownerID)
            try ObservationReanalysisPersistence.insert(identity, paths: [], metadata: Data("{}".utf8), context: context)
        }
        try context.save()
        let first = try await Reader().page(ownerID: seed.source.ownerID, observationID: seed.source.observationID,
            limit: 20, container: seed.container, isCurrent: { true })
        #expect(first.items.isEmpty && first.omittedCount == 20)
        let cursor = try #require(first.next)
        let second = try await Reader().page(ownerID: seed.source.ownerID, observationID: seed.source.observationID,
            after: cursor, limit: 20, container: seed.container, isCurrent: { true })
        #expect(second.items.map(\.identity) == [seed.preparation.identity] && second.next == nil)
        await #expect(throws: ObservationHistoryError.invalidPage) {
            try await Reader().page(ownerID: UUID(), observationID: seed.source.observationID,
                after: cursor, container: seed.container, isCurrent: { true })
        }
        await #expect(throws: ObservationHistoryError.invalidPage) {
            try await Reader().page(ownerID: seed.source.ownerID, observationID: UUID(),
                after: cursor, container: seed.container, isCurrent: { true })
        }
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 21)
    }

    @Test(arguments: ["partial", "heldDraft", "source", "invalidLink"])
    func unsupportedOrDamagedWorkIsCountedNotPresentedAsRunnable(_ mode: String) async throws {
        let seed = try fixture.fixture.seed(action: mode == "heldDraft" ? .hold : .submit)
        defer { try? FileManager.default.removeItem(at: seed.root) }
        _ = try fixture.fixture.phase(seed)
        let context = ModelContext(seed.container)
        if mode == "partial" { context.delete(try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)) }
        if mode == "source" { try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first).sourceAnalysisID = UUID().uuidString.lowercased() }
        if mode == "invalidLink" { try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first).sourceAnalysisID = "invalid" }
        try context.save()
        let page = try await Reader().page(ownerID: seed.source.ownerID, observationID: seed.source.observationID,
            container: seed.container, isCurrent: { true })
        #expect(page.items.isEmpty && page.omittedCount == 1 && page.next == nil)
    }

    @Test(arguments: ["io", "account", "cancel", "delete"])
    func failuresAcrossReadNeverBecomeEmptySuccessfulPages(_ mode: String) async throws {
        let seed = try fixture.fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        _ = try fixture.fixture.phase(seed)
        var current = true
        let reader = Reader(read: { identity, container, valid in
            if mode == "io" { throw CocoaError(.fileReadUnknown) }
            if mode == "cancel" { throw CancellationError() }
            let saved = try await ObservationAudioResumeStore.read(identity, container: container, isCurrent: valid)
            if mode == "account" { current = false }
            if mode == "delete" {
                let context = ModelContext(container)
                context.delete(try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)); try context.save()
            }
            return saved
        })
        await #expect(throws: (any Error).self) {
            try await reader.page(ownerID: seed.source.ownerID, observationID: seed.source.observationID,
                container: seed.container, isCurrent: { current })
        }
    }
}
