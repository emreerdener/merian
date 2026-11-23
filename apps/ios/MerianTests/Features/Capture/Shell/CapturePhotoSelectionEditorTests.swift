import Testing
import UIKit
@testable import Merian

@MainActor @Suite("Photo selection editor ownership")
struct CapturePhotoSelectionEditorTests {
    @Test func selectionDoesNotMarkPixelsEditedAndCornerTouchDoesNotJump() throws {
        let editor = make()
        editor.select(at: CGPoint(x: 100, y: 100))
        let original = try #require(editor.selectedSourceRect)
        #expect(editor.hasSelectionEdits)
        #expect(!editor.hasEdits)
        editor.dragSelection(corner: .topLeft, translation: .zero, ended: false)
        #expect(editor.selectedSourceRect == original)
        editor.dragSelection(corner: .topLeft, translation: .init(width: -10, height: -10), ended: true)
        let rect = try #require(editor.selectionViewportRect)
        #expect(abs(rect.minX - 50) < 0.000001)
        #expect(abs(rect.maxX - 140) < 0.000001)
    }

    @Test func selectionTracksSourceAcrossResizeRotationAndCropExclusion() throws {
        let editor = make()
        editor.select(at: CGPoint(x: 70, y: 100))
        let source = try #require(editor.selectedSourceRect)
        editor.resize(to: 400)
        #expect(editor.selectedSourceRect == source)
        editor.rotate(clockwise: true)
        #expect(editor.selectedSourceRect == source)
        editor.magnify(4, ended: true)
        #expect(editor.selectedSourceRect == nil)
        #expect(editor.hasSelectionEdits)
    }

    @Test func lateCandidatesCannotReplaceManualSelectionOrEnterNewTransform() throws {
        let editor = make()
        let revision = editor.candidateRevision
        editor.select(at: CGPoint(x: 100, y: 100))
        let manual = try #require(editor.selectedSourceRect)
        editor.acceptCandidates([CGRect(x: 0, y: 0.25, width: 1, height: 0.5)], revision: revision)
        #expect(editor.selectedSourceRect == manual)
        #expect(editor.candidates.count == 1)
        editor.rotate(clockwise: true)
        editor.acceptCandidates([CGRect(x: 0, y: 0.25, width: 1, height: 0.5)], revision: revision)
        #expect(editor.candidates.isEmpty)
        editor.clearSelection()
        #expect(editor.selectedSourceRect == nil)
    }

    @Test func unsupportedSubmissionOwnerCannotExposeSelection() {
        let editor = make(enabled: false)
        editor.select(at: CGPoint(x: 100, y: 100))
        #expect(editor.selectedSourceRect == nil)
        #expect(!editor.hasSelectionEdits)
    }

    @Test func acceptedPixelsWithoutSourceTransformAllowSelectionButNeverRecrop() async throws {
        var original = make().original
        original.allowsReframing = false
        let editor = CapturePhotoEditorState(original: original, allowsManualSelection: true)
        editor.resize(to: 200)
        editor.select(at: CGPoint(x: 100, y: 100))
        let selected = try #require(editor.selectedSourceRect)
        editor.magnify(2, ended: true)
        editor.drag(.init(width: 20, height: 20), ended: true)
        editor.rotate(clockwise: true)
        #expect(editor.scale == 1 && editor.offset == .zero && editor.quarterTurns == 0)
        #expect(editor.selectedSourceRect == selected && editor.hasSelectionEdits && !editor.hasEdits)
        #expect(await editor.generateCrop().isEmpty)
    }

    private func make(enabled: Bool = true) -> CapturePhotoEditorState {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 200)).image { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
        }
        let editor = CapturePhotoEditorState(original: IdentifiableImage(image: image), allowsManualSelection: enabled)
        editor.resize(to: 200)
        return editor
    }

    @Test func fittedSelectionUsesPreparedPixelsAndRejectsLetterbox() throws {
        let image = UIGraphicsImageRenderer(size: .init(width: 400, height: 200)).image { context in
            UIColor.green.setFill(); context.fill(.init(x: 0, y: 0, width: 400, height: 200))
        }
        let bytes = try #require(image.jpegData(compressionQuality: 0.8))
        let original = IdentifiableImage(image: image, allowsReframing: false)
        let staged = StagedImage(compressedData: bytes, displayData: bytes, uiImage: image, original: original,
            reviewBasis: .preparedArtifact(sha256: SharedMediaAcquisitionEncoding.digest(bytes)))
        #expect(staged.hasPreparedReviewIdentity && staged.startsWithFullAspectReview)
        let editor = CapturePhotoEditorState(original: original, allowsManualSelection: true,
            selectedSourceRect: .init(x: 0.4, y: 0.2, width: 0.1, height: 0.4), usesFullAspect: true)
        editor.resize(to: 400)
        let source = try #require(editor.selectedSourceRect)
        #expect(editor.selectionViewportRect == CGRect(x: 160, y: 140, width: 40, height: 80))
        #expect(editor.selectionGeometry.finalCropRect(for: source) == source)
        editor.select(at: .init(x: 200, y: 20))
        #expect(editor.selectedSourceRect == source && !editor.hasSelectionEdits)
        editor.select(at: .init(x: 20, y: 200))
        #expect(try #require(editor.selectedSourceRect).minX == 0)
        #expect(!editor.hasEdits)
        #expect(!staged.replacing(compressedData: Data([1])).hasPreparedReviewIdentity)
        var reframed = original; reframed.lastCropDisplaySize = 400
        #expect(!staged.replacing(original: reframed).hasPreparedReviewIdentity)
        let unproven = StagedImage(compressedData: bytes, displayData: bytes, uiImage: image, original: original)
        #expect(!unproven.hasPreparedReviewIdentity && !unproven.startsWithFullAspectReview)
    }

    @Test func fullAspectSelectionRendererPreservesAspectAndFocus() async throws {
        let image = UIGraphicsImageRenderer(size: .init(width: 400, height: 200)).image { context in
            UIColor.green.setFill(); context.fill(.init(x: 0, y: 0, width: 400, height: 200))
        }
        let bytes = try #require(image.jpegData(compressionQuality: 0.8))
        let focus = NormalizedImageFocusRegion(x: 0.4, y: 0.2, width: 0.1, height: 0.4, source: .userSelection)
        let recipe = SharedMediaNativePreparationRecipe(format: .selectedStillImage, isPro: false,
            cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0, sourceSelection: focus)
        let output = try await OriginalPhotoRenderer.render(.bytes(bytes), recipe: recipe)
        #expect(output.manualFocus == focus)
        let raster = try #require(UIImage(data: output.inference))
        #expect(abs(raster.size.width / raster.size.height - 2) < 0.01)
        let staged = StagedImage(compressedData: output.inference, displayData: output.display,
            uiImage: image, original: .init(image: image), reviewBasis: .nativeOriginal(recipe))
        #expect(staged.startsWithFullAspectReview && !staged.hasPreparedReviewIdentity)
    }
}
