import Foundation
@testable import Merian
import Testing
import UIKit

@MainActor
struct CaptureInitialEvidencePreparationTests {
    @Test func mixedObservationPreservesOriginalSelectionAndOrderedNotes() async throws {
        let identity = identity(), bytes = try photo()
        let image = source(identity, bytes: bytes)
        let audio = source(identity, bytes: Data(repeating: 0, count: 64), role: .sourceAudio)
        let selection = NormalizedImageFocusRegion(x: 0.4, y: 0.2, width: 0.2, height: 0.4, source: .userSelection)
        let recipe = SharedMediaNativePreparationRecipe(format: .selectedStillImage, isPro: true,
            cropDisplaySize: 100, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0, sourceSelection: selection)
        let result = try await CaptureInitialEvidencePreparation().prepare(identity: identity,
            items: [.photo(image, recipe), .description("  Synthetic observation  "), .audio(audio)]) { input in
                #expect(input == image)
                return bytes
            }
        #expect(result.plan.items.count == 3)
        #expect(result.derivatives.count == 1)
        guard case let .image(original, prepared, focus, preparation) = result.plan.items[0],
              case let .description(note) = result.plan.items[1],
              case let .audio(recording) = result.plan.items[2] else { Issue.record("Lost mixed-media order"); return }
        #expect(original.mediaID == image.mediaID && original.sha256 == image.sha256)
        #expect(preparation.sourceSelection == selection)
        let mapped = try #require(focus)
        #expect(mapped.source == .userSelection)
        #expect(abs(mapped.x - 0.3) < 0.01 && abs(mapped.width - 0.4) < 0.01)
        #expect(note == "  Synthetic observation  ")
        #expect(recording.source.mediaID == audio.mediaID)
        #expect(result.derivatives[recording.preparedMediaID] == nil)
        let output = try #require(result.derivatives[prepared.mediaID])
        #expect(output.count == prepared.byteCount)
        #expect(SharedMediaAcquisitionEncoding.digest(output) == prepared.sha256)
        let raster = try #require(UIImage(data: output)?.cgImage)
        #expect(raster.width == raster.height)
        #expect(try CaptureInitialEvidencePlan(ownerID: identity.ownerID, data: result.plan.encoded()) == result.plan)
    }

    @Test func refusesChangedOriginalAndForeignDraftBeforeRendering() async throws {
        let identity = identity(), bytes = try photo(), worker = CaptureInitialEvidencePreparation()
        let input = source(identity, bytes: bytes)
        let recipe = SharedMediaNativePreparationRecipe(format: .stillImage, isPro: false,
            cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0)
        await #expect(throws: (any Error).self) {
            try await worker.prepare(identity: identity, items: [.photo(input, recipe)]) { _ in Data([1, 2, 3]) }
        }
        let foreign = source(self.identity(), bytes: bytes)
        await #expect(throws: (any Error).self) {
            try await worker.prepare(identity: identity, items: [.photo(foreign, recipe)]) { _ in
                Issue.record("A foreign source must fail before reading"); return bytes
            }
        }
    }

    @Test func fullFrameAndCameraFramingUseDifferentOriginalGeometry() async throws {
        let bytes = try photo()
        let full = SharedMediaNativePreparationRecipe(format: .stillImage, isPro: false,
            cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0)
        let camera = SharedMediaNativePreparationRecipe(format: .cameraStill, isPro: false,
            cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0, cameraVerticalCenter: 0.5)
        let fullOutput = try await OriginalPhotoRenderer.render(.bytes(bytes), recipe: full)
        let cameraOutput = try await OriginalPhotoRenderer.render(.bytes(bytes), recipe: camera)
        let fullRaster = try #require(UIImage(data: fullOutput.inference)?.cgImage)
        let cameraRaster = try #require(UIImage(data: cameraOutput.inference)?.cgImage)
        #expect(fullRaster.width == 2 * fullRaster.height)
        #expect(cameraRaster.width == cameraRaster.height)
        #expect(fullOutput.manualFocus == nil && cameraOutput.manualFocus == nil)
    }

    private func identity() -> CaptureInitialDraftSession.Identity {
        .init(ownerID: UUID(), scanID: UUID(), generation: UUID())
    }

    private func source(_ identity: CaptureInitialDraftSession.Identity, bytes: Data,
                        role: SharedMediaCaptureArtifactRequest.Role = .sourceImage) -> SharedMediaCaptureDraftSourceInput {
        .init(id: UUID(), scanID: identity.scanID, submissionGeneration: identity.generation, mediaID: UUID(),
            itemIndex: role == .sourceImage ? 0 : 1, role: role, contentType: role == .sourceImage ? "image/jpeg" : "audio/wav",
            byteCount: Int64(bytes.count), sha256: SharedMediaAcquisitionEncoding.digest(bytes),
            context: .init(origin: role == .sourceImage ? .imported : .microphone, cameraVerticalCenter: nil))
    }

    private func photo() throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return try #require(UIGraphicsImageRenderer(size: .init(width: 400, height: 200), format: format).image { context in
            UIColor.green.setFill(); context.fill(.init(x: 0, y: 0, width: 400, height: 200))
            UIColor.blue.setFill(); context.fill(.init(x: 200, y: 0, width: 200, height: 200))
        }.jpegData(compressionQuality: 0.9))
    }
}
