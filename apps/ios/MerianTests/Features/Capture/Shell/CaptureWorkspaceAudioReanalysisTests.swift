import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct CaptureWorkspaceAudioReanalysisTests {
    let fixture = ObservationAudioPreparationTests()

    @Test(arguments: [2, 3, 4, 5])
    func workspaceSubmissionPreservesOrderedNotesAndRetriesOneChild(sourceVersion: Int) async throws {
        let seed = try fixture.seed(sourceVersion: sourceVersion)
        defer { try? FileManager.default.removeItem(at: seed.root) }
        let session = CaptureAudioReanalysisSession(source: seed.source, generation: UUID(), container: seed.container)
        let service = ObservationAudioSourcePreparation(producer: fixture.producer(seed))
        var admitted = false, starts: [UUID] = [], opened = 0
        let host = CaptureAudioReanalysisHost(source: .init(session: session, isCurrent: { true }, submit: { current in
            try await session.submitSource(generation: session.generation, preparation: service,
                isCurrentAccount: { true }, isCurrentPresentation: current, start: { saved, proof in
                    #expect(!seed.source.artifactIDs.contains(proof.preparation.audio.mediaID))
                    guard case let .source(snapshot) = saved else { Issue.record("Wrong execution route"); return .unavailable }
                    #expect(snapshot.identity.sourceAnalysisID == seed.source.analysisID)
                    #expect(!seed.source.artifactIDs.contains(snapshot.identity.analysisID))
                    starts.append(snapshot.identity.analysisID)
                    return admitted ? .started : .unavailable
                })
        }))
        let files = FileIOActor(documents: seed.root, temporaryDirectory: seed.root)
        let path = try #require(await files.stageHistoryAudio(seed.bytes))
        var capture = StagedCapture()
        capture.observationContexts = [.init(context: .init(freeText: "Before"), addedAt: Date(timeIntervalSince1970: 0)),
            .init(context: .init(freeText: "After"), addedAt: Date(timeIntervalSince1970: 2))]
        capture.audios = [.init(filePath: path, addedAt: Date(timeIntervalSince1970: 1))]
        let adapter = CaptureWorkspaceAudioReanalysis(source: try .capture(observationID: seed.source.observationID,
            analysisID: seed.source.analysisID, ownerID: seed.source.ownerID, container: seed.container),
            container: seed.container, loader: .init(account: fixture.fixture.account()), files: files, documents: seed.root,
            makeHost: { _, _ in opened += 1; return host }, current: { true })
        await #expect(throws: ObservationHistoryError.unavailable) { try await adapter.submit(capture, ownedPaths: [path]) }
        let plan = try #require(session.plan), child = plan.analysisID
        #expect(adapter.isFrozen && opened == 1)
        #expect(plan.choices.count == 3)
        #expect(plan.choices.first == .description("Before") && plan.choices.last == .description("After"))
        // Staging may disappear after the durable request was created. A retry
        // must use the original frozen bytes and child, without reopening files.
        await files.deleteFiles(at: [path])
        admitted = true
        #expect(try await adapter.submit(capture, ownedPaths: [path]) == child)
        #expect(starts == [child, child] && opened == 1)
        try seed.source.validate(container: seed.container)
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
    }

    @Test func unownedAudioCannotOpenTheSubmissionOwner() async throws {
        let seed = try fixture.seed()
        defer { try? FileManager.default.removeItem(at: seed.root) }
        let files = FileIOActor(documents: seed.root, temporaryDirectory: seed.root)
        let path = try #require(await files.stageHistoryAudio(seed.bytes))
        var capture = StagedCapture(); capture.audios = [.init(filePath: path)]
        let adapter = CaptureWorkspaceAudioReanalysis(source: try .capture(observationID: seed.source.observationID,
            analysisID: seed.source.analysisID, ownerID: seed.source.ownerID, container: seed.container),
            container: seed.container, loader: .init(account: fixture.fixture.account()), files: files, documents: seed.root,
            makeHost: { _, _ in Issue.record("Unowned file opened submission"); throw ObservationHistoryError.unavailable }, current: { true })
        await #expect(throws: ObservationHistoryError.unavailable) { try await adapter.submit(capture, ownedPaths: []) }
        #expect(!adapter.isFrozen)
        #expect(FileManager.default.fileExists(atPath: seed.root.appendingPathComponent(path).path))
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
    }
}
