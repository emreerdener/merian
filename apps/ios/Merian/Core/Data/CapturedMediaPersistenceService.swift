import Foundation

/// Converts a capture timeline into the durable captured-media representation.
///
/// File adoption is injected so SwiftData actors do not own filesystem work and
/// tests can exercise ordering without touching Documents storage.
struct CapturedMediaPersistenceService: Sendable {
    struct Dependencies: Sendable {
        let persistAudioFile: @Sendable (String) async -> String?
        let persistVideoFile: @Sendable (String) async -> String?
    }

    struct Request: Sendable {
        let localImagePaths: [String]
        let observationContextsJSON: [String]
        let audioFilePaths: [String]
        let videoFilePaths: [String]
        let mediaTimeline: [CaptureSubmissionMediaItem]?

        init(
            localImagePaths: [String] = [],
            observationContextsJSON: [String] = [],
            audioFilePaths: [String] = [],
            videoFilePaths: [String] = [],
            mediaTimeline: [CaptureSubmissionMediaItem]? = nil
        ) {
            self.localImagePaths = localImagePaths
            self.observationContextsJSON = observationContextsJSON
            self.audioFilePaths = audioFilePaths
            self.videoFilePaths = videoFilePaths
            self.mediaTimeline = mediaTimeline
        }
    }

    static let live = CapturedMediaPersistenceService(
        dependencies: Dependencies(
            persistAudioFile: { path in
                await FileIOActor.shared.persistAudioFile(tempPath: path)
            },
            persistVideoFile: { path in
                await FileIOActor.shared.persistVideoFile(tempPath: path)
            }
        )
    )

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func makeCapturedMediaJSON(for request: Request) async -> String? {
        let observationContexts = decodedObservationContexts(
            from: request.observationContextsJSON
        )
        let timeline = request.mediaTimeline ??
            CaptureSubmissionMediaItem.defaultTimeline(
                imageCount: request.localImagePaths.count,
                observationContexts: observationContexts,
                audioFilePaths: request.audioFilePaths,
                videoFilePaths: request.videoFilePaths
            )

        var mediaItems: [SerializedMediaItem] = []
        var standaloneAudioSourceIndex = 0

        for item in timeline {
            switch item {
            case .image(let index):
                guard request.localImagePaths.indices.contains(index) else {
                    continue
                }
                mediaItems.append(.image(StoredMediaReference(
                    legacyPath: request.localImagePaths[index]
                )))
            case .description(let context):
                guard !context.isEmpty else { continue }
                mediaItems.append(.description(context))
            case .audio(let sourcePath):
                defer { standaloneAudioSourceIndex += 1 }
                if let persistedPath = await dependencies.persistAudioFile(
                    sourcePath
                ) {
                    mediaItems.append(.audio(.documents(
                        persistedPath,
                        sourceIndex: standaloneAudioSourceIndex
                    )))
                }
            case .video(
                let sourcePath,
                let posterImageIndex,
                let audioFilePath
            ):
                guard let persistedPath = await dependencies.persistVideoFile(
                    sourcePath
                ) else {
                    continue
                }
                let thumbnail = posterImageIndex.flatMap { index in
                    request.localImagePaths.indices.contains(index)
                        ? StoredMediaReference(
                            legacyPath: request.localImagePaths[index]
                        )
                        : nil
                }
                let audio: StoredMediaReference?
                if let audioFilePath,
                   let persistedAudioPath = await dependencies.persistAudioFile(
                       audioFilePath
                   ) {
                    audio = .documents(persistedAudioPath)
                } else {
                    audio = nil
                }
                mediaItems.append(.video(StoredVideoMediaReference(
                    video: .documents(persistedPath),
                    thumbnail: thumbnail,
                    audio: audio
                )))
            }
        }

        guard !mediaItems.isEmpty,
              let data = try? JSONEncoder().encode(mediaItems) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func decodedObservationContexts(
        from observationContextsJSON: [String]
    ) -> [ObservationContext] {
        observationContextsJSON.compactMap { contextJSON in
            guard let data = contextJSON.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(ObservationContext.self, from: data)
        }
    }
}
