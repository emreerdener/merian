import Foundation

struct CaptureSubmissionAdmissionSnapshot: Equatable {
    let imageIDs: [UUID]
    let imagePayloads: [Data]
    let audioFilePaths: [String]
    let audioAddedAt: [Date]
    let videoFilePaths: [String]
    let videoAddedAt: [Date]
    let observationContexts: [ObservationContext]
    let observationAddedAt: [Date]

    init(_ stagedCapture: StagedCapture) {
        imageIDs = stagedCapture.images.map(\.original.id)
        imagePayloads = stagedCapture.images.map(\.compressedData)
        audioFilePaths = stagedCapture.audios.map(\.filePath)
        audioAddedAt = stagedCapture.audios.map(\.addedAt)
        videoFilePaths = stagedCapture.videos.map(\.filePath)
        videoAddedAt = stagedCapture.videos.map(\.addedAt)
        observationContexts = stagedCapture.observationContexts.map(\.context)
        observationAddedAt = stagedCapture.observationContexts.map(\.addedAt)
    }
}

struct CaptureSubmissionPayload {
    let mediaTimeline: [CaptureSubmissionMediaItem]
    let displayImages: [StagedImage]
    let inferenceImages: [StagedImage]
    let visualMediaItems: [IdentifyVisualMediaItem]
    let hasCameraStillImage: Bool
    let hasGalleryStillImage: Bool

    init(nodes: [StagedCaptureNode]) {
        var mediaTimeline: [CaptureSubmissionMediaItem] = []
        var displayImages: [StagedImage] = []
        var inferenceImages: [StagedImage] = []
        var visualMediaItems: [IdentifyVisualMediaItem] = []
        var stillImageSourceIndex = 0
        var videoClipIndex = 0
        var hasCameraStillImage = false
        var hasGalleryStillImage = false

        for node in nodes {
            switch node {
            case .image(_, let stagedImage):
                let imageIndex = displayImages.count
                displayImages.append(stagedImage)
                inferenceImages.append(stagedImage)
                let isGalleryImage = stagedImage.original.isFromGallery
                hasGalleryStillImage = hasGalleryStillImage || isGalleryImage
                hasCameraStillImage = hasCameraStillImage || !isGalleryImage
                visualMediaItems.append(.image(
                    sourceIndex: stillImageSourceIndex,
                    focusRegion: stagedImage.focusRegion,
                    captureSource: isGalleryImage ? .gallery : .camera,
                    hasEmbeddedCaptureDate: isGalleryImage
                        ? stagedImage.original.environmentContext?.captureDate != nil
                        : nil
                ))
                stillImageSourceIndex += 1
                mediaTimeline.append(.image(index: imageIndex))
            case .video(_, let stagedVideo):
                var posterImageIndex: Int?
                if let coverImage = stagedVideo.coverImage {
                    let imageIndex = displayImages.count
                    displayImages.append(coverImage)
                    posterImageIndex = imageIndex
                }
                inferenceImages.append(contentsOf: stagedVideo.sampledImages)
                for frameIndex in stagedVideo.sampledImages.indices {
                    visualMediaItems.append(.videoFrame(
                        clipIndex: videoClipIndex,
                        frameIndex: frameIndex
                    ))
                }
                videoClipIndex += 1
                mediaTimeline.append(.video(
                    stagedVideo.filePath,
                    posterImageIndex: posterImageIndex,
                    audioFilePath: stagedVideo.audioFilePath
                ))
            case .audio(_, let stagedAudio):
                mediaTimeline.append(.audio(stagedAudio.filePath))
            case .description(_, let stagedObservationContext):
                mediaTimeline.append(.description(stagedObservationContext.context))
            }
        }

        self.mediaTimeline = mediaTimeline
        self.displayImages = displayImages
        self.inferenceImages = inferenceImages
        self.visualMediaItems = visualMediaItems
        self.hasCameraStillImage = hasCameraStillImage
        self.hasGalleryStillImage = hasGalleryStillImage
    }

    var stillImageCount: Int {
        visualMediaItems.lazy.filter { $0.kind == .image }.count
    }
}
