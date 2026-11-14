import CryptoKit
import Foundation
@testable import Merian
import Testing

@Suite(.serialized)
struct ObservationVideoCohortPreparerTests {
    @Test(arguments: [false, true])
    func completeCohortBindsEveryFileAndReplaysExactRequest(audio: Bool) async throws {
        let fixture = try await VideoAudioFixture(channels: audio ? 2 : nil)
        defer { fixture.remove() }
        let input = try Data(contentsOf: fixture.videoURL)
        let cohort = try await prepare(ObservationVideoCohortPreparer(), fixture)
        let request = cohort.request
        let graph = request.manifest.provenance
        #expect(try ObservationVideoReanalysisRequest(savedBody: request.body) == request)
        #expect(request.manifest.descriptions == ["synthetic cohort"])
        #expect(graph.frames.count == 5)
        #expect((graph.audio != nil) == audio)
        let artifacts = [graph.source] + graph.frames.map(\.artifact) + (graph.audio.map { [$0.artifact] } ?? [])
        let files = try Self.files(in: fixture.outputDirectory)
        #expect(files.count == artifacts.count)
        #expect(Set(artifacts.map(\.mediaID)).count == (audio ? 7 : 6))
        #expect(Set(artifacts.map(\.mediaID)).isDisjoint(with: [request.observationID, request.analysisID, request.sourceAnalysisID]))
        for artifact in artifacts {
            let file = try #require(files.first { artifact == graph.source ? $0.lastPathComponent == "retained.mp4" : $0.deletingPathExtension().lastPathComponent == artifact.mediaID.uuidString.lowercased() })
            let bytes = try Data(contentsOf: file)
            #expect(bytes.count == artifact.byteCount)
            #expect(hash(bytes) == artifact.sha256)
        }
        #expect(try fixture.outputFiles().count == 1)
        #expect(try Data(contentsOf: fixture.videoURL) == input)
    }

    @Test(arguments: [ObservationVideoCohortPhase.retained, .frames, .audio, .beforeHandoff])
    func interruptionAtEveryBoundaryRemovesWholeGeneration(phase: ObservationVideoCohortPhase) async throws {
        let fixture = try await VideoAudioFixture(channels: 1)
        defer { fixture.remove() }
        let preparer = ObservationVideoCohortPreparer { current in
            if current == phase { throw CancellationError() }
        }
        do { _ = try await prepare(preparer, fixture); Issue.record("Interrupted cohort escaped") } catch is CancellationError {}
        #expect(try fixture.outputFiles().isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.videoURL.path))
    }

    @Test(arguments: [ObservationVideoCohortPhase.retained, .frames, .audio, .beforeHandoff])
    func changedSourceCannotBecomeCohort(phase: ObservationVideoCohortPhase) async throws {
        let fixture = try await VideoAudioFixture(channels: 1)
        defer { fixture.remove() }
        let preparer = ObservationVideoCohortPreparer { current in
            if current == phase {
                let source = try #require(Self.files(in: fixture.outputDirectory).first { $0.lastPathComponent == "retained.mp4" })
                let handle = try FileHandle(forWritingTo: source)
                defer { try? handle.close() }
                try handle.seekToEnd(); try handle.write(contentsOf: Data([0]))
            }
        }
        do { _ = try await prepare(preparer, fixture); Issue.record("Changed source accepted") } catch ObservationVideoCohortError.changedArtifact {}
        #expect(try fixture.outputFiles().isEmpty)
    }

    @Test func changedFrameFailsFinalVerification() async throws {
        let fixture = try await VideoAudioFixture(channels: 1)
        defer { fixture.remove() }
        let preparer = ObservationVideoCohortPreparer { phase in
            guard phase == .beforeHandoff else { return }
            let source = try #require(Self.files(in: fixture.outputDirectory).first { $0.lastPathComponent == "retained.mp4" })
            let root = source.deletingLastPathComponent().deletingLastPathComponent()
            let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            let frames = try #require(folders.first { $0.lastPathComponent.hasPrefix("video-frames-") })
            let file = try #require(FileManager.default.contentsOfDirectory(at: frames, includingPropertiesForKeys: nil).first)
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd(); try handle.write(contentsOf: Data([0]))
        }
        do { _ = try await prepare(preparer, fixture); Issue.record("Changed derivative accepted") } catch ObservationVideoCohortError.changedArtifact {}
        #expect(try fixture.outputFiles().isEmpty)
    }

    @Test func cancellationJoinsAndAllowsReuse() async throws {
        let fixture = try await VideoAudioFixture(channels: 1)
        defer { fixture.remove() }
        let checkpoint = VideoCohortCheckpoint()
        let preparer = ObservationVideoCohortPreparer { phase in
            if phase == .frames, await checkpoint.first() { try await Task.sleep(for: .seconds(30)) }
        }
        let task = Task { try await prepare(preparer, fixture) }
        let deadline = ContinuousClock.now + .seconds(10)
        while !(await checkpoint.entered), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(await checkpoint.entered)
        do { _ = try await prepare(preparer, fixture); Issue.record("Occupied preparer accepted work") } catch ObservationVideoCohortError.busy {}
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled worker escaped") } catch is CancellationError {}
        #expect(try fixture.outputFiles().isEmpty)
        let result = try await prepare(preparer, fixture)
        #expect(result.request.manifest.provenance.audio != nil)
    }

    @Test func droppingCohortRemovesSourceAndAllDerivatives() async throws {
        let fixture = try await VideoAudioFixture(channels: 1)
        defer { fixture.remove() }
        var cohort: ObservationVideoCohort? = try await prepare(ObservationVideoCohortPreparer(), fixture)
        #expect(cohort != nil)
        let files = try Self.files(in: fixture.outputDirectory)
        cohort = nil
        #expect(try fixture.outputFiles().isEmpty)
        #expect(files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        #expect(FileManager.default.fileExists(atPath: fixture.videoURL.path))
    }

    @Test func invalidScopeAndDescriptionsFailBeforeMediaWork() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        do {
            _ = try await ObservationVideoCohortPreparer().prepare(source: directory.appendingPathComponent("absent.mp4"), directory: directory,
                                                                  observationID: id, analysisID: id, sourceAnalysisID: UUID(), descriptions: [],
                                                                  cropCenterBasisPoints: 5000, inferenceLongEdge: 768)
            Issue.record("Aliased scope accepted")
        } catch ObservationVideoCohortError.invalidScope {}
        do {
            _ = try await ObservationVideoCohortPreparer().prepare(source: directory.appendingPathComponent("absent.mp4"), directory: directory,
                                                                  observationID: UUID(), analysisID: UUID(), sourceAnalysisID: UUID(), descriptions: [String(repeating: "a", count: 8193)],
                                                                  cropCenterBasisPoints: 5000, inferenceLongEdge: 768)
            Issue.record("Oversized description accepted")
        } catch ObservationHistoryError.invalidSnapshot {}
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    private static func files(in directory: URL) throws -> [URL] {
        let enumerator = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
        let urls = try #require(enumerator.allObjects as? [URL])
        return urls.filter { ["mp4", "wav", "webp", "jpg"].contains($0.pathExtension) }
    }

    private func prepare(_ preparer: ObservationVideoCohortPreparer, _ fixture: VideoAudioFixture) async throws -> ObservationVideoCohort {
        try await preparer.prepare(source: fixture.videoURL, directory: fixture.outputDirectory,
                                   observationID: UUID(), analysisID: UUID(), sourceAnalysisID: UUID(), descriptions: ["synthetic cohort"],
                                   cropCenterBasisPoints: 5000, inferenceLongEdge: 768)
    }
    private func hash(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
}

private actor VideoCohortCheckpoint {
    private(set) var entered = false
    func first() -> Bool {
        guard !entered else { return false }
        entered = true
        return true
    }
}
