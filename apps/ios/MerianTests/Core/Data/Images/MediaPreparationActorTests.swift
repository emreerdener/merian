import Foundation
import Testing
import UIKit

@testable import Merian

@MainActor
@Suite("Media Preparation Actor", .serialized)
struct MediaPreparationActorTests {
    private func makeLargeJPEGData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4_000, height: 3_000))
        let image = renderer.image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4_000, height: 3_000))
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 600, y: 400, width: 2_000, height: 1_200))
        }
        guard let data = image.jpegData(compressionQuality: 0.96) else {
            fatalError("Failed to build large JPEG fixture")
        }
        return data
    }

    private func writeTemporaryImage(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-prep-\(UUID().uuidString).jpg")
        try data.write(to: url)
        return url
    }

    @Test func prepareStillImageReturnsOnlyBoundedPayloads() async throws {
        let sourceData = makeLargeJPEGData()
        let url = try writeTemporaryImage(sourceData)
        defer { try? FileManager.default.removeItem(at: url) }

        let prepared = try await MediaPreparationActor.shared.prepareStillImage(
            fileURL: url,
            isPro: false
        )

        #expect(prepared.metrics.isWithinImageBudgets)
        #expect(prepared.metrics.largestInferenceDimension <= Int(MerianConfig.flashInferenceImageMaxSize))
        #expect(prepared.metrics.largestDisplayDimension <= Int(MerianConfig.displayImageMaxSize))
        #expect(prepared.metrics.inferenceByteCount == prepared.inferenceData.count)
        #expect(prepared.metrics.displayByteCount == prepared.displayData.count)
        #expect(prepared.metrics.inferenceByteCount <= MerianConfig.stagedImagePayloadMaxBytes)
        #expect(prepared.metrics.displayByteCount <= MerianConfig.stagedImagePayloadMaxBytes)
        #expect(max(prepared.previewImage.cgImage.width, prepared.previewImage.cgImage.height) <= Int(MerianConfig.flashInferenceImageMaxSize))
    }

    @Test func preparePreviewImageReturnsBoundedSendablePreview() async throws {
        let sourceData = makeLargeJPEGData()
        let url = try writeTemporaryImage(sourceData)
        defer { try? FileManager.default.removeItem(at: url) }

        let preview = try await MediaPreparationActor.shared.preparePreviewImage(
            fileURL: url,
            maxSize: 512
        )

        #expect(max(preview.cgImage.width, preview.cgImage.height) <= 512)
    }

    @Test func prepareStillImageRejectsNonImageFilesBeforeStaging() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-prep-invalid-\(UUID().uuidString).txt")
        try Data("not an image".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try await MediaPreparationActor.shared.prepareStillImage(
                fileURL: url,
                isPro: true
            )
            Issue.record("Invalid image bytes must not produce staged media")
        } catch MediaPreparationError.unreadableImage {
            #expect(true)
        } catch {
            Issue.record("Expected unreadableImage, got \(error)")
        }
    }
}
