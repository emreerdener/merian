import Foundation
@testable import Merian
import SwiftData
import Testing
import UIKit

@Suite("Initial Capture editing presentation", .serialized)
@MainActor
struct CaptureInitialDraftPresentationTests {
    @Test(arguments: [false, true])
    func coldVideoUsesOnlyItsRetainedCompanion(hasCompanion: Bool) async throws {
        let store = try await SharedMediaCaptureArtifactWriterTests.Store(), owner = try await store.open()
        let session = CaptureInitialDraftSession(identity: .init(ownerID: store.base.ownerID,
            scanID: store.input.scanID, generation: store.input.submissionGeneration), requireCurrent: {}, resolveOwner: { owner })
        let itemID = UUID(), recordingID = UUID()
        let videoBytes = Data(repeating: 7, count: 96)
        let companionBytes = makeInferenceTestPCM16WAVData(sampleRate: 44_100, sampleAt: { _ in 12 })
        let recordingBytes = makeInferenceTestPCM16WAVData(sampleRate: 44_100, sampleAt: { _ in 24 })
        let extractedBytes = makeInferenceTestPCM16WAVData(sampleRate: 44_100, sampleAt: { _ in 36 })
        let recipe = SharedMediaCaptureDraftJournal.VideoRecipe(duration: 1, isPro: true,
            composingCenter: 0.5, scale: 1, offsetX: 0, offsetY: 0, displaySize: nil, quarterTurns: 0)
        _ = try await session.retain(itemID: itemID, bytes: videoBytes, role: .sourceVideo,
            contentType: "video/mp4", context: .init(origin: .imported, cameraVerticalCenter: nil), review: .video(recipe))
        if hasCompanion {
            _ = try await session.retain(itemID: itemID, bytes: companionBytes, role: .sourceCompanionAudio,
                contentType: "audio/wav", context: .init(origin: .videoAudio, cameraVerticalCenter: nil))
        }
        _ = try await session.retain(itemID: recordingID, bytes: recordingBytes, role: .sourceAudio,
            contentType: "audio/wav", context: .init(origin: .microphone, cameraVerticalCenter: nil))
        let saved = try #require(session.journal)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let coldOwner = try await store.open(); try await coldOwner.resumeAppCaptureRoot()
        let cold = try await CaptureInitialDraftSession.reopen(saved, requireCurrent: {}, resolveOwner: { coldOwner })
        let extractedPath = try #require(await FileIOActor.shared.stageHistoryAudio(extractedBytes))
        let presentation = try await CaptureInitialDraftPresentation.make(journal: saved.value, prepareVideo: { request in
            .init(sampledFrames: [], audioFilePath: extractedPath,
                playback: .init(fileURL: request.videoURL, isCompressed: false,
                    originalBytes: videoBytes.count, playbackBytes: videoBytes.count, preparationDuration: 0))
        }, read: { input in try await cold.read(input) })
        #expect(presentation.capture.orderedNodes.map(\.itemID) == [itemID, recordingID])
        let restoredVideo = try #require(presentation.capture.videos.first)
        if hasCompanion {
            let path = try #require(restoredVideo.audioFilePath)
            #expect(try Data(contentsOf: StagedVideo.localURL(for: path)) == companionBytes)
        } else { #expect(restoredVideo.audioFilePath == nil) }
        let recording = try #require(presentation.capture.audios.first)
        #expect(try Data(contentsOf: StagedVideo.localURL(for: recording.filePath)) == recordingBytes)
        #expect(!FileManager.default.fileExists(atPath: StagedVideo.localURL(for: extractedPath).path))
        #expect(cold.journal == saved && cold.frozenPlan == nil)
        await presentation.discard()
        for path in presentation.ownedPaths {
            #expect(!FileManager.default.fileExists(atPath: StagedVideo.localURL(for: path).path))
        }
        #expect(await coldOwner.invalidateAndAwaitForAccountTransition())
    }

    @Test func coldEditingPreservesIdentityOrderAndSelectionAndRejectsFrozenProjection() async throws {
        let store = try await SharedMediaCaptureArtifactWriterTests.Store(), owner = try await store.open()
        let session = CaptureInitialDraftSession(identity: .init(ownerID: store.base.ownerID,
            scanID: store.input.scanID, generation: store.input.submissionGeneration), requireCurrent: {}, resolveOwner: { owner })
        let image = UIGraphicsImageRenderer(size: .init(width: 32, height: 32)).image { drawing in
            UIColor.green.setFill(); drawing.fill(.init(x: 0, y: 0, width: 32, height: 32))
        }
        let bytes = try #require(image.jpegData(compressionQuality: 0.8))
        let selection = NormalizedImageFocusRegion(x: 0.2, y: 0.2, width: 0.6, height: 0.6, source: .userSelection)
        let recipe = SharedMediaNativePreparationRecipe(format: .selectedStillImage, isPro: false,
            cropDisplaySize: 100, quarterTurns: 1, scale: 1, offsetX: 0, offsetY: 0, sourceSelection: selection)
        let firstID = UUID(), secondID = UUID(), noteID = UUID()
        let first = try await session.retain(itemID: firstID, bytes: bytes, role: .sourceImage,
            contentType: "image/jpeg", context: .init(origin: .imported, cameraVerticalCenter: nil), review: .photo(recipe))
        let second = try await session.retain(itemID: secondID, bytes: bytes, role: .sourceImage,
            contentType: "image/jpeg", context: .init(origin: .imported, cameraVerticalCenter: nil), review: .photo(recipe))
        try await session.updateReview(items: [.photo(id: secondID, source: second.id, recipe: recipe),
            .description(id: noteID, text: "Synthetic editing note"), .photo(id: firstID, source: first.id, recipe: recipe)])
        let saved = try #require(session.journal)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let coldOwner = try await store.open(); try await coldOwner.resumeAppCaptureRoot()
        let cold = try await CaptureInitialDraftSession.reopen(saved, requireCurrent: {}, resolveOwner: { coldOwner })
        let presentation = try await cold.editingPresentation()
        #expect(presentation.capture.orderedNodes.map(\.itemID) == [secondID, noteID, firstID])
        #expect(presentation.capture.images.map(\.original.id) == [secondID, firstID])
        #expect(presentation.capture.images.allSatisfy { $0.original.manualSourceSelection == selection && $0.original.lastCropQuarterTurns == 1 })
        #expect(presentation.capture.images.allSatisfy { $0.original.image.size.width <= 2048 && !$0.displayData.isEmpty })
        #expect(presentation.ownedPaths.isEmpty && cold.journal == saved && cold.frozenPlan == nil)
        let plan = try await cold.prepare(items: [.photo(second, recipe), .description("Synthetic editing note"), .photo(first, recipe)])
        await #expect(throws: (any Error).self) { _ = try await cold.editingPresentation() }
        #expect(cold.frozenPlan == plan)
        // Preparing pixels in memory has not yet frozen a durable request.
        await #expect(throws: (any Error).self) {
            _ = try await cold.reviewPresentation(resources: CaptureDraftPresentationResources())
        }
        try coldOwner.configureCaptureSubmissionWritingForTesting { point in
            if point == .beforeSave { throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) {
            _ = try await cold.accept(context: SharedMediaCaptureSubmissionContextTests.context(plan))
        }
        // The injected submission fault closes dispatch. Read its durable
        // checkpoint through a fresh context, then reopen the root as an app
        // restart would; a closed writer is not a recovery reader.
        let read = ModelContext(store.container); read.autosaveEnabled = false
        let frozenJournal = try #require(try SharedMediaCaptureDraftJournalReceipt.matching(
            scanID: plan.scanID, generation: plan.generation, context: read))
        #expect(frozenJournal.value.phase == .preparing)
        #expect(await coldOwner.invalidateAndAwaitForAccountTransition())
        let recoveryOwner = try await store.open()
        try await recoveryOwner.resumeAppCaptureRoot()
        let frozen = try await CaptureInitialDraftSession.reopen(frozenJournal, requireCurrent: {}, resolveOwner: { recoveryOwner })
        let readOnly = try await frozen.reviewPresentation(resources: CaptureDraftPresentationResources())
        #expect(readOnly.capture.orderedNodes.map(\.itemID) == [secondID, noteID, firstID])
        #expect(readOnly.capture.images.allSatisfy { !$0.original.allowsReframing })
        #expect(readOnly.capture.images.allSatisfy { $0.original.manualSourceSelection == selection })
        #expect(frozen.journal == frozenJournal && frozen.frozenPlan == plan)
        await readOnly.discard()
        await presentation.discard()
        #expect(await recoveryOwner.invalidateAndAwaitForAccountTransition())
    }
}
