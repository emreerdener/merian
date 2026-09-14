import Foundation

/// Normalizes live inference media once for provider submission and Insight UI.
///
/// This owner performs no networking, persistence, task creation, or observable
/// mutation. File-system and secure-URL policy are supplied as narrow values so
/// path compatibility remains deterministic in focused tests.
struct InferenceLiveMediaProjector {
    struct Dependencies: Sendable {
        let documentsDirectory: URL
        let temporaryDirectory: URL
        let fileExists: @Sendable (String) -> Bool
        let secureRemoteURL: @Sendable (String) -> URL?

        static var live: Self {
            Self(
                documentsDirectory: URL.documentsDirectory,
                temporaryDirectory: FileManager.default.temporaryDirectory,
                fileExists: { FileManager.default.fileExists(atPath: $0) },
                secureRemoteURL: { SecureTransportPolicy.httpsURL(from: $0) }
            )
        }
    }

    struct Projection: Equatable {
        let mediaTimeline: [CaptureSubmissionMediaItem]
        let submission: CaptureSubmissionMediaProjection
        let ownerMediaTimeline: [IdentifyOwnerMediaTimelineItem]?
        let activeMedia: ActiveScanMedia
    }

    struct NonVisualProjection: Equatable {
        let media: Projection
        /// Preserves the existing modality decision based on the legacy audio
        /// argument, independently of an explicitly supplied media timeline.
        let hasAudioInput: Bool
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    static var live: Self {
        Self(dependencies: .live)
    }

    func projectVisual(
        imageDatas: [Data],
        displayDatas: [Data],
        audioFilePaths: [String]?,
        videoFilePaths: [String]?,
        observationContexts: [ObservationContext],
        mediaTimeline: [CaptureSubmissionMediaItem]?,
        visualMediaItems: [IdentifyVisualMediaItem]?
    ) -> Projection {
        let presentationImages = displayDatas.isEmpty
            ? imageDatas
            : displayDatas
        let filteredContexts = observationContexts.filter { !$0.isEmpty }
        let timeline = mediaTimeline
            ?? CaptureSubmissionMediaItem.defaultTimeline(
                imageCount: presentationImages.count,
                observationContexts: filteredContexts,
                audioFilePaths: audioFilePaths ?? [],
                videoFilePaths: videoFilePaths ?? []
            )

        return projection(
            timeline: timeline,
            timelineWasExplicit: mediaTimeline != nil,
            liveImageDatas: presentationImages,
            persistedImagePaths: nil,
            focusRegionsBySourceIndex:
                visualMediaItems?.focusRegionsBySourceIndex ?? [:]
        )
    }

    func projectNonVisual(
        audioFilePaths: [String]?,
        videoFilePaths: [String]?,
        observationContexts: [ObservationContext],
        mediaTimeline: [CaptureSubmissionMediaItem]?
    ) -> NonVisualProjection {
        let filteredAudioPaths = (audioFilePaths ?? []).filter { !$0.isEmpty }
        let filteredVideoPaths = (videoFilePaths ?? []).filter { !$0.isEmpty }
        let filteredContexts = observationContexts.filter { !$0.isEmpty }
        let timeline = mediaTimeline
            ?? CaptureSubmissionMediaItem.defaultTimeline(
                imageCount: 0,
                observationContexts: filteredContexts,
                audioFilePaths: filteredAudioPaths,
                videoFilePaths: filteredVideoPaths
            )

        return NonVisualProjection(
            media: projection(
                timeline: timeline,
                timelineWasExplicit: mediaTimeline != nil,
                liveImageDatas: nil,
                persistedImagePaths: nil,
                focusRegionsBySourceIndex: [:]
            ),
            hasAudioInput: !filteredAudioPaths.isEmpty
        )
    }

    func persistedMediaItems(
        from mediaTimeline: [CaptureSubmissionMediaItem],
        imagePaths: [String]
    ) -> [MediaItem] {
        mediaItems(
            from: mediaTimeline,
            liveImageDatas: nil,
            persistedImagePaths: imagePaths
        )
    }

    private func projection(
        timeline: [CaptureSubmissionMediaItem],
        timelineWasExplicit: Bool,
        liveImageDatas: [Data]?,
        persistedImagePaths: [String]?,
        focusRegionsBySourceIndex:
            [Int: NormalizedImageFocusRegion]
    ) -> Projection {
        let submission = timeline.submissionMediaProjection
        return Projection(
            mediaTimeline: timeline,
            submission: submission,
            ownerMediaTimeline: timelineWasExplicit
                ? submission.ownerMediaTimeline
                : nil,
            activeMedia: ActiveScanMedia(
                items: mediaItems(
                    from: timeline,
                    liveImageDatas: liveImageDatas,
                    persistedImagePaths: persistedImagePaths
                ),
                focusRegionsBySourceIndex: focusRegionsBySourceIndex
            )
        )
    }

    private func mediaItems(
        from mediaTimeline: [CaptureSubmissionMediaItem],
        liveImageDatas: [Data]?,
        persistedImagePaths: [String]?
    ) -> [MediaItem] {
        var items: [MediaItem] = []

        for (timelineIndex, item) in mediaTimeline.enumerated() {
            switch item {
            case .image(let imageIndex):
                // Only an explicitly matching video poster is fallback
                // content. A distinct staged still immediately before a video
                // remains its own carousel page.
                if mediaTimeline.indices.contains(timelineIndex + 1),
                   case .video(_, let posterImageIndex, _) =
                       mediaTimeline[timelineIndex + 1],
                   posterImageIndex == imageIndex {
                    continue
                }
                if let liveImageDatas,
                   liveImageDatas.indices.contains(imageIndex) {
                    items.append(.liveImage(liveImageDatas[imageIndex]))
                } else if let persistedImagePaths,
                          persistedImagePaths.indices.contains(imageIndex) {
                    items.append(.image(persistedImagePaths[imageIndex]))
                }

            case .audio(let audioFilePath):
                items.append(.audio(resolvedLocalPath(for: audioFilePath)))

            case .video(let videoFilePath, let posterImageIndex, _):
                let fallbackImage = posterImageIndex.flatMap {
                    videoFallbackImage(
                        at: $0,
                        liveImageDatas: liveImageDatas,
                        persistedImagePaths: persistedImagePaths
                    )
                }
                if let videoPath = resolvedVideoPath(for: videoFilePath) {
                    items.append(.video(
                        videoPath,
                        fallbackImage: fallbackImage
                    ))
                } else if let fallbackImage {
                    switch fallbackImage {
                    case .liveImage(let data):
                        items.append(.liveImage(data))
                    case .imagePath(let path):
                        items.append(.image(path))
                    }
                }

            case .description(let context):
                guard !context.isEmpty else { continue }
                items.append(.description(context))
            }
        }

        return items
    }

    private func videoFallbackImage(
        at imageIndex: Int,
        liveImageDatas: [Data]?,
        persistedImagePaths: [String]?
    ) -> VideoFallbackImageSource? {
        if let liveImageDatas,
           liveImageDatas.indices.contains(imageIndex) {
            return .liveImage(liveImageDatas[imageIndex])
        }
        if let persistedImagePaths,
           persistedImagePaths.indices.contains(imageIndex) {
            return .imagePath(persistedImagePaths[imageIndex])
        }
        return nil
    }

    private func resolvedVideoPath(for rawPath: String) -> String? {
        let normalizedPath = normalized(rawPath)
        if normalizedPath.hasPrefix("http://")
            || normalizedPath.hasPrefix("https://") {
            return dependencies.secureRemoteURL(normalizedPath)?.absoluteString
        }
        return resolvedLocalPath(for: normalizedPath)
    }

    private func resolvedLocalPath(for rawPath: String) -> String {
        let normalizedPath = normalized(rawPath)
        if normalizedPath.hasPrefix("/") {
            if dependencies.fileExists(normalizedPath) {
                return normalizedPath
            }
            let filename = URL(fileURLWithPath: normalizedPath)
                .lastPathComponent
            let documentsPath = dependencies.documentsDirectory
                .appendingPathComponent(filename)
                .path
            return dependencies.fileExists(documentsPath)
                ? documentsPath
                : normalizedPath
        }

        let documentsPath = dependencies.documentsDirectory
            .appendingPathComponent(normalizedPath)
            .path
        let temporaryPath = dependencies.temporaryDirectory
            .appendingPathComponent(normalizedPath)
            .path
        return dependencies.fileExists(documentsPath)
            ? documentsPath
            : temporaryPath
    }

    private func normalized(_ path: String) -> String {
        path.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
