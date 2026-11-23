import CryptoKit
import Foundation
@testable import Merian
import SwiftData
import Testing
import UIKit

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct CaptureWorkspaceVideoReanalysisTests {
    @Test(arguments: [false, true], [2, 3, 4, 5])
    func workspaceClipUsesDurableVideoOwnerAndRetryKeepsOneChild(cancelAfterSave: Bool, sourceVersion: Int) async throws {
        let seed = try ObservationReanalysisLocalVideoInputTests().seed(sourceVersion: sourceVersion); defer { seed.remove() }
        let media = try await VideoAudioFixture(channels: 1); defer { media.remove() }
        let clip = seed.documents.appendingPathComponent("workspace.mp4")
        try FileManager.default.copyItem(at: media.videoURL, to: clip)
        let context = ModelContext(seed.container), parent = try seed.parent(context)
        // The workspace must not need a legacy current-attachment descriptor.
        parent.capturedMediaJSON = nil; try context.save()
        let session = CaptureVideoReanalysisSession(source: seed.source, generation: UUID(), container: seed.container)
        let account = ObservationReanalysisProducerTests().account(), files = seed.files
        let store = ObservationReanalysisFileStore(documents: seed.documents)
        let producer = ObservationVideoPreparationProducer(files: store, ownership: .init(), account: account)
        var admitted = false, starts = 0, delay = cancelAfterSave
        let entered = AsyncStream<Void>.makeStream(); defer { entered.continuation.finish() }
        var release: CheckedContinuation<Void, Never>?
        var opened = CaptureVideoReanalysisAccess.Opened(session: session, choices: [], isCurrent: { true }, submit: { presented in
            let result = try await session.submit(generation: session.generation, files: files, temporaryDirectory: seed.temporary,
                startup: seed.startup, producer: producer, isCurrentAccount: { true }, isCurrentPresentation: presented,
                start: { ready in
                    #expect(ready.proof.preparation.identity.sourceAnalysisID == seed.source.analysisID)
                    #expect(ready.proof.preparation.files.allSatisfy { !seed.source.artifactIDs.contains($0.artifact.mediaID) })
                    #expect(ready.proof.preparation.sourceSnapshotSHA256 == SHA256.hash(data: seed.source.snapshot).map { String(format: "%02x", $0) }.joined())
                    starts += 1
                    return admitted ? .started : .unavailable
                })
            if delay { await withCheckedContinuation { release = $0; entered.continuation.yield(()) } }
            return result
        })
        opened.workspaceInput = { path, owned in
            try await ObservationReanalysisLocalVideoInput.workspaceChoice(source: seed.source, path: path,
                ownedPaths: owned, files: files, container: seed.container, isCurrent: { true })
        }
        let host = CaptureVideoReanalysisHost(opened: opened)
        let adapter = CaptureWorkspaceVideoReanalysis(source: try .capture(observationID: seed.source.observationID,
            analysisID: seed.source.analysisID, ownerID: seed.source.ownerID, container: seed.container),
            container: seed.container, loader: .init(account: account), files: files, makeHost: { _, _ in host }, current: { true })
        var capture = StagedCapture()
        capture.videos = [.init(filePath: "workspace.mp4", sampledImages: [], addedAt: Date(timeIntervalSince1970: 0))]
        capture.observationContexts = [.init(context: .init(freeText: "Keep this note"), addedAt: Date(timeIntervalSince1970: 1))]
        if cancelAfterSave {
            let submitted = capture
            let caller = Task { try await adapter.submit(submitted, ownedPaths: ["workspace.mp4"]) }
            for await _ in entered.stream { break }
            caller.cancel(); release?.resume()
            await #expect(throws: CancellationError.self) { try await caller.value }
            delay = false
        } else {
            await #expect(throws: ObservationHistoryError.unavailable) { try await adapter.submit(capture, ownedPaths: ["workspace.mp4"]) }
        }
        let child = try #require(host.analysisID)
        #expect(adapter.isFrozen && starts == 1 && session.plan?.descriptions == ["Keep this note"])
        #expect(FileManager.default.fileExists(atPath: clip.path))
        try FileManager.default.removeItem(at: clip)
        admitted = true
        #expect(try await adapter.submit(capture, ownedPaths: ["workspace.mp4"]) == child)
        #expect(starts == 2 && host.analysisID == child)
        #expect(!seed.source.artifactIDs.contains(child))
        try seed.source.validate(container: seed.container)
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(await host.invalidateAndAwait())
    }

    @Test func replacedStagedClipCannotBeCopiedUnderItsEarlierChoice() async throws {
        let seed = try ObservationReanalysisLocalVideoInputTests().seed(); defer { seed.remove() }
        let files = seed.files
        let choice = try await ObservationReanalysisLocalVideoInput.workspaceChoice(source: seed.source, path: "chosen.mp4",
            ownedPaths: ["chosen.mp4"], files: files, container: seed.container, isCurrent: { true })
        let original = seed.documents.appendingPathComponent("chosen.mp4")
        try Data(repeating: 8, count: 150_001).write(to: original, options: .atomic)
        var retained: ObservationReanalysisLocalVideoInput?
        await #expect(throws: (any Error).self) {
            try await ObservationReanalysisLocalVideoInput.freeze(choice, descriptions: [], container: seed.container,
                files: files, account: ObservationReanalysisProducerTests().account(), startup: seed.startup,
                store: ObservationReanalysisFileStore(documents: seed.documents), ownership: .init(), owning: { retained = $0 }, isCurrent: { true })
        }
        if let retained { #expect(await retained.discardCopiedInput()) }
        #expect(try Data(contentsOf: original) == Data(repeating: 8, count: 150_001))
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        await #expect(throws: ObservationHistoryError.unavailable) {
            try await ObservationReanalysisLocalVideoInput.workspaceChoice(source: seed.source, path: "chosen.mp4",
                ownedPaths: [], files: files, container: seed.container, isCurrent: { true })
        }
    }
}

extension CaptureWorkspaceVideoReanalysisTests {
    @Test(arguments: [-1, 2, 6])
    func originalVideoLoadsAsOneItemAndPartialFailureCleansOnlyNewStaging(failAt: Int) async throws {
        let seed = try ObservationReanalysisSourceTests().seed(version: 5)
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sentinel = root.appendingPathComponent("existing.mp4")
        try Data([9]).write(to: sentinel)
        let context = ModelContext(seed.container)
        let record = try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let fixture = try videoLoadFixture(seed.result.bytes)
        let replacement = try LocalAnalysisRecord(analysisID: seed.result.analysisID, observationID: record.observationID,
            ownerAccountID: ObservationPublicationPersistenceTests().owner, completedAt: record.completedAt,
            snapshotVersion: 5, resultSnapshotData: fixture.snapshot)
        context.delete(record); try context.save()
        context.insert(replacement); parent.analysisRecords = [replacement]; try context.save()
        let source = try ObservationCompositionSource.capture(observationID: seed.observationID, analysisID: seed.result.analysisID,
            ownerID: ObservationPublicationPersistenceTests().owner, container: seed.container)
        let payloads = fixture.payloads
        var calls = 0
        let loader = ObservationHistoryMediaLoader(account: ObservationReanalysisProducerTests().account(), resolve: { request in
            defer { calls += 1 }
            if calls == failAt { throw ObservationHistoryError.unavailable }
            let artifact = try #require(source.artifacts.first { $0.mediaID.uuidString.lowercased() == request.media_id })
            let row: [String: Any] = [
                "schema_version": 1, "owner_id": source.ownerID.uuidString.lowercased(),
                "observation_id": request.observation_id, "analysis_id": request.analysis_id, "media_id": request.media_id,
                "content_type": artifact.contentType, "byte_count": artifact.byteCount, "sha256": artifact.sha256,
                "url": "https://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.r2.cloudflarestorage.com/private/synthetic",
                "expires_at_ms": Int64(Date().addingTimeInterval(30).timeIntervalSince1970 * 1000)
            ]
            return try JSONDecoder().decode(ObservationHistoryMediaTicket.self, from: JSONSerialization.data(withJSONObject: row))
        }, download: { ticket in try #require(payloads[ticket.media_id]) })
        let files = FileIOActor(documents: root, temporaryDirectory: root)
        let adapter = CaptureWorkspaceVideoReanalysis(source: source, container: seed.container, loader: loader, files: files,
            makeHost: { _, _ in Issue.record("Loading must not open a submission owner"); throw ObservationHistoryError.unavailable }, current: { true })
        if failAt < 0 {
            let capture = try await adapter.load()
            #expect(capture.physicalItemCount == 1 && capture.images.isEmpty && capture.audios.isEmpty)
            let video = try #require(capture.videos.first)
            #expect(video.sampledImages.count == 5 && video.audioFilePath != nil && calls == 7)
            #expect(capture.observationContexts.map(\.context.freeText) == source.nodes.compactMap {
                if case let .description(text) = $0 { return text }; return nil
            })
            #expect(capture.discardableLocalMediaFilePaths.count == 2)
            await adapter.discardStaging(capture)
        } else {
            await #expect(throws: ObservationHistoryError.unavailable) { try await adapter.load() }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["existing.mp4"])
        #expect(try Data(contentsOf: sentinel) == Data([9]))
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        try source.validate(container: seed.container)
    }

    private func videoLoadFixture(_ snapshot: Data) throws -> (snapshot: Data, payloads: [String: Data]) {
        var row = try #require(JSONSerialization.jsonObject(with: snapshot) as? [String: Any])
        var manifest = try #require(row["evidence_manifest"] as? [String: Any])
        var graph = try #require(manifest["provenance"] as? [String: Any])
        var payloads: [String: Data] = [:]
        func artifact(_ value: Any?, bytes: Data, type: String) throws -> [String: Any] {
            var artifact = try #require(value as? [String: Any])
            let id = try #require(artifact["media_id"] as? String)
            artifact["content_type"] = type; artifact["byte_count"] = bytes.count
            artifact["sha256"] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            payloads[id] = bytes
            return artifact
        }
        // The resolver/loader validates immutable membership and exact bytes; the
        // server's retained-container verification is covered by its own suite.
        graph["source"] = try artifact(graph["source"], bytes: Data([1, 2, 3]), type: "video/mp4")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let jpeg = try #require(image.jpegData(compressionQuality: 0.8))
        graph["frames"] = try #require(graph["frames"] as? [[String: Any]]).map { value in
            var frame = value; frame["artifact"] = try artifact(frame["artifact"], bytes: jpeg, type: "image/jpeg"); return frame
        }
        var audio = try #require(graph["audio"] as? [String: Any])
        let samples = try #require(audio["sample_count"] as? Int)
        let wav = makeInferenceTestPCM16WAVData(sampleRate: 44_100, frameCount: samples, sampleAt: { _ in 0 })
        audio["artifact"] = try artifact(audio["artifact"], bytes: wav, type: "audio/wav"); graph["audio"] = audio
        manifest["provenance"] = graph; row["evidence_manifest"] = manifest
        return (try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]), payloads)
    }
}
