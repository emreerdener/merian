import Foundation
@testable import Merian
import Testing
import UIKit

@MainActor
struct CaptureInitialJournalPreparationTests {
    @Test func realVideoPreparationKeepsRetainedCompanion() async throws {
        let fixture = try await VideoAudioFixture(channels: nil, width: 96, height: 160, frameCount: 15, coordinatePattern: true)
        defer { fixture.remove() }
        let store = try await SharedMediaCaptureArtifactWriterTests.Store(), owner = try await store.open()
        let session = CaptureInitialDraftSession(identity: .init(ownerID: store.base.ownerID,
            scanID: store.input.scanID, generation: store.input.submissionGeneration), requireCurrent: {}, resolveOwner: { owner })
        let itemID = UUID(), bytes = try Data(contentsOf: fixture.videoURL)
        let recipe = SharedMediaCaptureDraftJournal.VideoRecipe(duration: 0.5, isPro: true,
            composingCenter: 0.4, scale: 1.2, offsetX: 2, offsetY: 3, displaySize: 100, quarterTurns: 1)
        let source = try await session.retain(itemID: itemID, bytes: bytes, role: .sourceVideo,
            contentType: "video/mp4", context: .init(origin: .imported, cameraVerticalCenter: nil), review: .video(recipe))
        let companion = try await session.retain(itemID: itemID,
            bytes: makeInferenceTestPCM16WAVData(sampleRate: 44_100, sampleAt: { _ in 12 }), role: .sourceCompanionAudio,
            contentType: "audio/wav", context: .init(origin: .videoAudio, cameraVerticalCenter: nil))
        let plan = try await session.prepareReview()
        guard case let .video(video) = plan.items.first else { Issue.record("Expected retained video"); return }
        #expect(video.source.mediaID == source.mediaID && video.source.sha256 == source.sha256)
        #expect(video.audio?.source.mediaID == companion.mediaID && video.audio?.source.sha256 == companion.sha256)
        #expect(video.frames.count == 5 && video.playback.byteCount > 0)
        #expect(try await session.read(source) == bytes)
        #expect(try await session.prepareReview() == plan)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func identifyPreparesSavedMixedOrderAndRetryKeepsFrozenEvidence() async throws {
        let store = try await SharedMediaCaptureArtifactWriterTests.Store(), owner = try await store.open()
        let session = CaptureInitialDraftSession(identity: .init(ownerID: store.base.ownerID,
            scanID: store.input.scanID, generation: store.input.submissionGeneration), requireCurrent: {}, resolveOwner: { owner })
        let image = UIGraphicsImageRenderer(size: .init(width: 32, height: 32)).image { drawing in
            UIColor.green.setFill(); drawing.fill(.init(x: 0, y: 0, width: 32, height: 32))
        }
        let photoBytes = try #require(image.jpegData(compressionQuality: 0.8))
        let selection = NormalizedImageFocusRegion(x: 0.2, y: 0.2, width: 0.6, height: 0.6, source: .userSelection)
        let recipe = SharedMediaNativePreparationRecipe(format: .selectedStillImage, isPro: true,
            cropDisplaySize: 100, quarterTurns: 1, scale: 1, offsetX: 0, offsetY: 0, sourceSelection: selection)
        let photoID = UUID(), audioID = UUID(), noteID = UUID()
        let photo = try await session.retain(itemID: photoID, bytes: photoBytes, role: .sourceImage,
            contentType: "image/jpeg", context: .init(origin: .imported, cameraVerticalCenter: nil), review: .photo(recipe))
        let audio = try await session.retain(itemID: audioID,
            bytes: makeInferenceTestPCM16WAVData(sampleRate: 44_100), role: .sourceAudio,
            contentType: "audio/wav", context: .init(origin: .microphone, cameraVerticalCenter: nil))
        try await session.updateReview(items: [.audio(id: audioID, source: audio.id),
            .description(id: noteID, text: "Synthetic ordered note"), .photo(id: photoID, source: photo.id, recipe: recipe)])
        let saved = try #require(session.journal)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let coldOwner = try await store.open(); try await coldOwner.resumeAppCaptureRoot()
        let cold = try await CaptureInitialDraftSession.reopen(saved, requireCurrent: {}, resolveOwner: { coldOwner })
        let plan = try await cold.prepareReview()
        guard case let .audio(recording) = plan.items[0], case let .description(text) = plan.items[1],
              case let .image(original, _, _, preparation) = plan.items[2] else {
            Issue.record("Whole saved observation lost its media ordering"); return
        }
        #expect(recording.source.mediaID == audio.mediaID && original.mediaID == photo.mediaID)
        #expect(text == "Synthetic ordered note" && preparation.sourceSelection == selection)
        #expect(try await cold.prepareReview() == plan)
        await #expect(throws: (any Error).self) { try await cold.updateReview(items: saved.value.items) }
        #expect(cold.frozenPlan == plan)
        #expect(await coldOwner.invalidateAndAwaitForAccountTransition())
    }

    @Test func snapshotReadIsBoundedAndRejectsReplacement() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let documents = root.appendingPathComponent("documents"), temporary = root.appendingPathComponent("temporary")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let io = FileIOActor(documents: documents, temporaryDirectory: temporary)
        let bytes = Data(repeating: 7, count: 128)
        let source = temporary.appendingPathComponent("synthetic.mp4")
        try bytes.write(to: source)
        #expect(await io.snapshotVideoFile(filename: source.path) == nil)
        let snapshot = try #require(await io.snapshotCapturePlayback(path: source.path))
        #expect(await io.readVideoSnapshot(snapshot, maximumBytes: 127) == nil)
        #expect(await io.readVideoSnapshot(snapshot, maximumBytes: 128) == bytes)
        try FileManager.default.removeItem(at: snapshot.url)
        try Data(repeating: 8, count: 128).write(to: snapshot.url)
        #expect(await io.readVideoSnapshot(snapshot, maximumBytes: 128) == nil)
        #expect(await io.discardVideoSnapshot(snapshot) == false)
        #expect(try Data(contentsOf: snapshot.url) == Data(repeating: 8, count: 128))
    }
}
