import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationAudioSourceStatusTests {
    typealias Reader = ObservationAudioSourceSavedStatus
    let fixture = ObservationAudioSourceSubmissionTests()

    @Test(arguments: ["staged", "running", "unknown", "reserved", "held", "unavailable", "conflict"])
    func exactStatesAreReadOnlyAndLegacyReaderStaysClosed(_ state: String) async throws {
        let seed = try await fixture.fixture.fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let original = try fixture.state(state, seed: seed)
        try FileManager.default.removeItem(at: seed.file)
        let page = try await Reader().page(ownerID: seed.source.ownerID, observationID: seed.source.observationID, container: seed.container, isCurrent: { true })
        let phases: [String: Reader.Phase] = ["staged": .staged, "running": .checking, "unknown": .unknown,
            "reserved": .reserved, "held": .held, "unavailable": .unavailable, "conflict": .conflict]
        #expect(page.items == [.init(identity: original.identity, phase: try #require(phases[state]))] && page.omittedCount == 0)
        #expect(try ObservationSourceReservationStore.read(original.identity, container: seed.container, isCurrent: { true }) == original)
        let legacy = try await ObservationAudioSavedStatus().page(ownerID: seed.source.ownerID, observationID: seed.source.observationID,
            container: seed.container, isCurrent: { true })
        #expect(legacy.items.isEmpty && legacy.omittedCount == 1 && !FileManager.default.fileExists(atPath: seed.file.path))
    }

    @Test(arguments: ["legacy", "malformed", "partial", "wrongSource"])
    func unsupportedWorkIsAnOmissionWithoutFallback(_ damage: String) async throws {
        let seed = try await fixture.fixture.fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        if damage == "legacy" { _ = try fixture.fixture.fixture.bind(seed) } else { _ = try fixture.state("staged", seed: seed) }
        let context = ModelContext(seed.container), job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        if damage == "malformed" { job.metadataJSON = "{}" }
        if damage == "partial" { context.delete(job) }
        if damage == "wrongSource" { try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first).sourceAnalysisID = UUID().uuidString.lowercased() }
        try context.save()
        let page = try await Reader().page(ownerID: seed.source.ownerID, observationID: seed.source.observationID, container: seed.container, isCurrent: { true })
        #expect(page.items.isEmpty && page.omittedCount == 1 && page.next == nil)
    }

    @Test func boundedCursorAdvancesOmissionsAndCannotCrossRoute() async throws {
        let seed = try await fixture.fixture.fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        _ = try fixture.state("staged", seed: seed)
        let context = ModelContext(seed.container)
        for index in 1...20 {
            let child = try #require(UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 100)))
            try ObservationReanalysisPersistence.insert(.init(observationID: seed.source.observationID, sourceAnalysisID: seed.source.analysisID,
                analysisID: child, ownerID: seed.source.ownerID), paths: [], metadata: Data("{}".utf8), context: context)
        }
        try context.save()
        let first = try await Reader().page(ownerID: seed.source.ownerID, observationID: seed.source.observationID, container: seed.container, isCurrent: { true })
        #expect(first.items.isEmpty && first.omittedCount == 20)
        let cursor = try #require(first.next)
        let second = try await Reader().page(ownerID: seed.source.ownerID, observationID: seed.source.observationID,
            after: cursor, container: seed.container, isCurrent: { true })
        #expect(second.items.map(\.identity) == [seed.preparation.identity] && second.next == nil)
        await #expect(throws: ObservationHistoryError.invalidPage) {
            try await ObservationAudioSavedStatus().page(ownerID: seed.source.ownerID, observationID: seed.source.observationID,
                after: cursor, container: seed.container, isCurrent: { true })
        }
        await #expect(throws: ObservationHistoryError.invalidPage) {
            try await Reader().page(ownerID: UUID(), observationID: seed.source.observationID, after: cursor, container: seed.container, isCurrent: { true })
        }
    }

    @Test(arguments: ["io", "account", "cancel", "delete"])
    func failuresNeverBecomeEmptySuccessfulPages(_ mode: String) async throws {
        let seed = try await fixture.fixture.fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        _ = try fixture.state("staged", seed: seed)
        var current = true
        let reader = Reader(read: { identity, container, valid in
            if mode == "io" { throw CocoaError(.fileReadUnknown) }
            if mode == "cancel" { throw CancellationError() }
            let saved = try await ObservationAudioSourceResumeStore().read(identity, container: container, isCurrent: valid)
            if mode == "account" { current = false }
            if mode == "delete" {
                let context = ModelContext(container)
                context.delete(try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)); try context.save()
            }
            return saved
        })
        await #expect(throws: (any Error).self) {
            try await reader.page(ownerID: seed.source.ownerID, observationID: seed.source.observationID, container: seed.container, isCurrent: { current })
        }
    }
}
