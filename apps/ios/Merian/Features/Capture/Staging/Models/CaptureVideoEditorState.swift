import AVFoundation
import Observation
import UIKit

/// Ephemeral controls over an immutable draft source. Only Shell can commit
/// a complete replacement artifact set; preview never changes submitted bytes.
@MainActor @Observable
final class CaptureVideoEditorState {
    let videoID: UUID
    let sourcePath: String
    let sourceURL: URL
    let duration: TimeInterval
    let crop: CapturePhotoEditorState

    private init(video: StagedVideo, sourceURL: URL, duration: TimeInterval, image: UIImage) {
        videoID = video.id
        sourcePath = video.originalFilePath ?? video.filePath
        self.sourceURL = sourceURL
        self.duration = duration
        var original = IdentifiableImage(image: image, initialCameraVerticalCenter: video.composingCenter)
        original.allowsReframing = video.allowsReframing
        if let framing = video.framing {
            original.lastCropScale = framing.scale
            original.lastCropOffset = framing.offset
            original.lastCropQuarterTurns = framing.quarterTurns
            original.lastCropDisplaySize = framing.displaySize
        }
        crop = CapturePhotoEditorState(original: original)
    }

    static func load(video: StagedVideo) async throws -> CaptureVideoEditorState {
        let source = StagedVideo.localURL(for: video.originalFilePath ?? video.filePath)
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1600, height: 1600)
        let frame = try await generator.image(at: .zero).image
        try Task.checkCancellation()
        return .init(video: video, sourceURL: source, duration: duration, image: UIImage(cgImage: frame))
    }

    var framing: CaptureVideoFraming {
        .init(scale: crop.scale, offset: crop.offset, displaySize: crop.displaySize, quarterTurns: crop.quarterTurns)
    }
}
