import Foundation
import SwiftData

enum MediaStorageLocation: String, Codable, Sendable, Equatable {
    case documents
    case remoteURL
    case absolutePath
}

/// Canonical persisted reference to a captured media asset.
///
/// New payloads encode both the path and how it should be resolved. The custom decoder
/// also accepts the legacy single-string representation so older scans continue to load.
struct StoredMediaReference: Codable, Equatable, Sendable {
    let storage: MediaStorageLocation
    let path: String
    /// Stable ordinal from the original standalone-media submission.
    ///
    /// This is intentionally optional: legacy manifests and compatibility URL
    /// arrays do not prove which original clip a durable URL represents.
    let sourceIndex: Int?

    init(
        storage: MediaStorageLocation,
        path: String,
        sourceIndex: Int? = nil
    ) {
        self.storage = storage
        self.path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sourceIndex = sourceIndex.flatMap { $0 >= 0 ? $0 : nil }
    }

    init(legacyPath: String) {
        let normalizedPath = legacyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedPath.starts(with: "http://") || normalizedPath.starts(with: "https://") {
            self.init(storage: .remoteURL, path: normalizedPath)
        } else if normalizedPath.hasPrefix("/") || normalizedPath.starts(with: "file://") {
            self.init(storage: .absolutePath, path: normalizedPath)
        } else {
            self.init(storage: .documents, path: normalizedPath)
        }
    }

    static func documents(_ path: String, sourceIndex: Int? = nil) -> Self {
        Self(storage: .documents, path: path, sourceIndex: sourceIndex)
    }

    static func remoteURL(_ path: String, sourceIndex: Int? = nil) -> Self {
        Self(storage: .remoteURL, path: path, sourceIndex: sourceIndex)
    }

    static func absolutePath(_ path: String, sourceIndex: Int? = nil) -> Self {
        Self(storage: .absolutePath, path: path, sourceIndex: sourceIndex)
    }

    var serializedPath: String {
        path
    }

    var isRemote: Bool {
        storage == .remoteURL
    }

    var resolvedURL: URL? {
        switch storage {
        case .documents:
            return URL.documentsDirectory.appendingPathComponent(path)
        case .remoteURL:
            return SecureTransportPolicy.httpsURL(from: path)
        case .absolutePath:
            if path.starts(with: "file://") {
                return URL(string: path)
            }
            return URL(fileURLWithPath: path)
        }
    }

    var resolvedLocalPath: String? {
        switch storage {
        case .documents:
            let documentsPath = URL.documentsDirectory.appendingPathComponent(path).path
            if FileManager.default.fileExists(atPath: documentsPath) {
                return documentsPath
            }
            return FileManager.default.temporaryDirectory.appendingPathComponent(path).path
        case .absolutePath:
            return resolvedURL?.path
        case .remoteURL:
            return nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case storage
        case path
        case sourceIndex
        case sourceIndexSnake = "source_index"
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let legacyPath = try? container.decode(String.self) {
            self.init(legacyPath: legacyPath)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storage = try container.decode(MediaStorageLocation.self, forKey: .storage)
        let path = try container.decode(String.self, forKey: .path)
        let sourceIndex = (try? container.decode(Int.self, forKey: .sourceIndex))
            ?? (try? container.decode(Int.self, forKey: .sourceIndexSnake))
        self.init(storage: storage, path: path, sourceIndex: sourceIndex)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(storage, forKey: .storage)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(sourceIndex, forKey: .sourceIndex)
    }
}

extension StoredMediaReference: ExpressibleByStringLiteral {
    init(stringLiteral value: StringLiteralType) {
        self.init(legacyPath: value)
    }
}

extension StoredMediaReference {
    static func == (lhs: StoredMediaReference, rhs: String) -> Bool {
        lhs.serializedPath == rhs
    }

    static func == (lhs: String, rhs: StoredMediaReference) -> Bool {
        lhs == rhs.serializedPath
    }
}

struct StoredVideoMediaReference: Codable, Equatable, Sendable {
    let video: StoredMediaReference
    let thumbnail: StoredMediaReference?
    let audio: StoredMediaReference?

    init(
        video: StoredMediaReference,
        thumbnail: StoredMediaReference? = nil,
        audio: StoredMediaReference? = nil
    ) {
        self.video = video
        self.thumbnail = thumbnail
        self.audio = audio
    }

    init(
        _ legacyReference: StoredMediaReference,
        thumbnail: StoredMediaReference? = nil,
        audio: StoredMediaReference? = nil
    ) {
        self.init(video: legacyReference, thumbnail: thumbnail, audio: audio)
    }

    var serializedPath: String {
        video.serializedPath
    }

    var resolvedLocalPath: String? {
        video.resolvedLocalPath
    }

    var thumbnailPath: String? {
        thumbnail?.serializedPath
    }

    var resolvedThumbnailPath: String? {
        thumbnail?.resolvedLocalPath ?? thumbnail?.serializedPath
    }

    var audioPath: String? {
        audio?.serializedPath
    }

    var resolvedAudioPath: String? {
        audio?.resolvedLocalPath ?? audio?.serializedPath
    }

    private enum CodingKeys: String, CodingKey {
        case video
        case thumbnail
        case audio
    }

    init(from decoder: Decoder) throws {
        if let legacyReference = try? StoredMediaReference(from: decoder) {
            self.init(legacyReference)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let video = try container.decode(StoredMediaReference.self, forKey: .video)
        let thumbnail = try container.decodeIfPresent(StoredMediaReference.self, forKey: .thumbnail)
        let audio = try container.decodeIfPresent(StoredMediaReference.self, forKey: .audio)
        self.init(video: video, thumbnail: thumbnail, audio: audio)
    }
}

/// A serializable representation of captured media elements, preserving chronological order
/// across image, audio, and textual modalities for persistent storage.
enum SerializedMediaItem: Codable, Equatable, Sendable {
    case image(StoredMediaReference)
    case audio(StoredMediaReference)
    case video(StoredVideoMediaReference)
    case description(ObservationContext)
}

struct CapturedMediaSnapshot: Equatable, Sendable {
    let items: [SerializedMediaItem]
    private static let sampledVideoFrameCount = 5

    init(items: [SerializedMediaItem] = []) {
        self.items = items
    }

    init(jsonString: String?) {
        guard let jsonString,
              let items = MediaJSONParser.serializedItems(jsonString: jsonString) else {
            self.items = []
            return
        }
        self.items = items
    }

    var jsonString: String? {
        MediaJSONParser.jsonString(from: items)
    }

    var imageReferences: [StoredMediaReference] {
        items.compactMap { item in
            guard case .image(let reference) = item else { return nil }
            return reference
        }
    }

    var audioReferences: [StoredMediaReference] {
        items.compactMap { item in
            guard case .audio(let reference) = item else { return nil }
            return reference
        }
    }

    var videoAudioReferences: [StoredMediaReference] {
        videoMediaReferences.compactMap(\.audio)
    }

    /// Audio candidates that can seed a historical refinement, in the same
    /// precedence order as the original capture surface. Standalone recordings
    /// win; legacy extracted video companions remain a compatibility fallback.
    var refinementAudioReferences: [StoredMediaReference] {
        var seenReferences = Set<String>()
        return (audioReferences + videoAudioReferences).filter { reference in
            let identity = "\(reference.storage.rawValue)\u{0}\(reference.path)"
            return seenReferences.insert(identity).inserted
        }
    }

    /// Local compressed-audio references written by builds that predate the
    /// WAV-only inference contract. They must be materialized as queue-owned
    /// WAV files before signing or replaying a staged inference manifest.
    var legacyQueuedAudioReferences: [StoredMediaReference] {
        var seenReferences = Set<String>()
        return refinementAudioReferences.filter { reference in
            guard !reference.isRemote else { return false }
            let fileExtension = URL(fileURLWithPath: reference.path)
                .pathExtension
                .lowercased()
            guard fileExtension == "m4a" || fileExtension == "mp4" else {
                return false
            }
            let identity = "\(reference.storage.rawValue)\u{0}\(reference.path)"
            return seenReferences.insert(identity).inserted
        }
    }

    var videoReferences: [StoredMediaReference] {
        items.compactMap { item in
            guard case .video(let reference) = item else { return nil }
            return reference.video
        }
    }

    var videoMediaReferences: [StoredVideoMediaReference] {
        items.compactMap { item in
            guard case .video(let reference) = item else { return nil }
            return reference
        }
    }

    var videoThumbnailReferences: [StoredMediaReference] {
        videoMediaReferences.compactMap(\.thumbnail)
    }

    var observationContexts: [ObservationContext] {
        items.compactMap { item in
            guard case .description(let context) = item else { return nil }
            return context
        }
    }

    var submissionMediaProjection: CaptureSubmissionMediaProjection {
        items.map { item in
            switch item {
            case .image:
                return CaptureSubmissionProjectionItem.image
            case .audio(let reference):
                return .audio(
                    reference.serializedPath,
                    sourceIndex: reference.sourceIndex
                )
            case .video(let reference):
                return .video(
                    reference.video.serializedPath,
                    audioFilePath: reference.audio?.serializedPath
                )
            case .description(let context):
                return .description(context)
            }
        }.submissionMediaProjection
    }

    var imagePaths: [String] {
        imageReferences.map(\.serializedPath)
    }

    var thumbnailImagePaths: [String] {
        var paths = imagePaths
        for thumbnailPath in videoThumbnailReferences.map(\.serializedPath) where !paths.contains(thumbnailPath) {
            paths.append(thumbnailPath)
        }
        return paths
    }

    var audioPaths: [String] {
        submissionMediaProjection.audioFilePaths
    }

    var videoPaths: [String] {
        videoReferences.map(\.serializedPath)
    }

    var observationContextsJSON: [String]? {
        let encoded = observationContexts.compactMap { context in
            (try? JSONEncoder().encode(context)).flatMap { String(data: $0, encoding: .utf8) }
        }
        return encoded.isEmpty ? nil : encoded
    }

    var primaryImagePath: String? {
        thumbnailImagePaths.first
    }

    var hasCloudImage: Bool {
        imageReferences.contains { $0.isRemote } || videoThumbnailReferences.contains { $0.isRemote }
    }

    var descriptionText: String? {
        observationContexts.first(where: { !$0.isEmpty })?.serialized()
    }

    var summary: CapturedMediaSummary {
        var hasImage = false
        var hasAudio = false
        var hasVideo = false
        var hasDescription = false

        for item in items {
            switch item {
            case .image:
                hasImage = true
            case .audio:
                hasAudio = true
            case .video(let reference):
                hasVideo = true
                if reference.audio != nil {
                    hasAudio = true
                }
            case .description:
                hasDescription = true
            }
        }

        return CapturedMediaSummary(
            hasImage: hasImage,
            hasAudio: hasAudio,
            hasVideo: hasVideo,
            hasDescription: hasDescription
        )
    }

    var activeScanMedia: ActiveScanMedia {
        let resolvedItems: [MediaItem] = items.compactMap { serialized in
            switch serialized {
            case .image(let reference):
                return .image(reference.serializedPath)
            case .audio(let reference):
                return .audio(reference.resolvedLocalPath ?? reference.serializedPath)
            case .video(let reference):
                let fallbackImage = reference.resolvedThumbnailPath.map {
                    VideoFallbackImageSource.imagePath($0)
                }
                return .video(
                    reference.resolvedLocalPath ?? reference.serializedPath,
                    fallbackImage: fallbackImage
                )
            case .description(let context):
                return .description(context)
            }
        }

        return ActiveScanMedia(items: resolvedItems)
    }

    static func cloudHydratedItems(
        capturedMediaItems: [SerializedMediaItem]?,
        imageStorageURLs: [String]?,
        videoStorageURLs: [String]?,
        audioStorageURLs: [String]? = nil,
        observationContext: ObservationContext? = nil
    ) -> [SerializedMediaItem] {
        let imageURLs = (imageStorageURLs ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let videoURLs = (videoStorageURLs ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let resolvedCapturedMediaItems = addingCloudNonVisualFallbacks(
            to: capturedMediaItems ?? [],
            audioStorageURLs: audioStorageURLs,
            observationContext: observationContext
        )
        let hasUsableManifestVisual = resolvedCapturedMediaItems.contains { item in
            switch item {
            case .image, .video:
                return true
            case .audio, .description:
                return false
            }
        }

        if let capturedMediaItems,
           !capturedMediaItems.isEmpty,
           hasUsableManifestVisual {
            let snapshot = CapturedMediaSnapshot(items: resolvedCapturedMediaItems)
            if snapshot.summary.hasVideo {
                if videoStorageURLs != nil, videoURLs.isEmpty {
                    return demotingUnavailableVideos(
                        in: resolvedCapturedMediaItems,
                        imageURLs: imageURLs,
                        imageAvailabilityIsExplicit: imageStorageURLs != nil
                    )
                }
                return addingMissingVideoFallbacks(
                    to: resolvedCapturedMediaItems,
                    imageURLs: imageURLs,
                    imageAvailabilityIsExplicit: imageStorageURLs != nil
                )
            }
            if videoURLs.isEmpty {
                if imageStorageURLs != nil, imageURLs.isEmpty {
                    return resolvedCapturedMediaItems.filter { item in
                        switch item {
                        case .audio, .description:
                            return true
                        case .image, .video:
                            return false
                        }
                    }
                }
                return middleFrameFallbackItems(from: resolvedCapturedMediaItems)
                    ?? resolvedCapturedMediaItems
            }
        }

        guard !videoURLs.isEmpty else {
            if let middleFrame = middleFrameFallbackURL(from: imageURLs) {
                return [.image(.remoteURL(middleFrame))] + resolvedCapturedMediaItems
            }
            return imageURLs.map { .image(.remoteURL($0)) }
                + resolvedCapturedMediaItems
        }

        let manifestImageURLs = resolvedCapturedMediaItems
            .compactMap { item -> String? in
                guard case .image(let reference) = item else { return nil }
                let path = reference.serializedPath.trimmingCharacters(in: .whitespacesAndNewlines)
                return path.isEmpty ? nil : path
            }
        let availableImageURLs = imageURLs.isEmpty ? manifestImageURLs : imageURLs
        let preservedManifestItems = resolvedCapturedMediaItems
            .filter { item in
                switch item {
                case .audio, .description:
                    return true
                case .image, .video:
                    return false
                }
            }

        let expectedVideoFrameCount = videoURLs.count * sampledVideoFrameCount
        let standaloneImageCount = max(availableImageURLs.count - expectedVideoFrameCount, 0)
        let standaloneImages = availableImageURLs.prefix(standaloneImageCount).map { SerializedMediaItem.image(.remoteURL($0)) }
        let videoFrameURLs = Array(availableImageURLs.dropFirst(standaloneImageCount))
        let fallbackThumbnailURL = middleReference(in: videoFrameURLs) ?? middleReference(in: availableImageURLs)

        let videos = videoURLs.enumerated().map { index, videoURL in
            let thumbnailIndex = index * sampledVideoFrameCount + sampledVideoFrameCount / 2
            let thumbnailURL = videoFrameURLs.indices.contains(thumbnailIndex)
                ? videoFrameURLs[thumbnailIndex]
                : fallbackThumbnailURL
            return SerializedMediaItem.video(StoredVideoMediaReference(
                .remoteURL(videoURL),
                thumbnail: thumbnailURL.map { .remoteURL($0) }
            ))
        }

        return standaloneImages + videos + preservedManifestItems
    }

    /// Retains nonvisual provenance that an incomplete historical projection cannot
    /// authoritatively replace. A cloud audio reference replaces an existing clip only
    /// when their exact paths or unique durable source indexes match. Unindexed legacy
    /// references are merged conservatively because ordinal inference can delete the
    /// wrong clip when a multi-audio projection is partial. The scan row stores only one
    /// observation context, so unmatched local descriptions are always preserved.
    static func preservingExistingNonVisualItems(
        in hydratedItems: [SerializedMediaItem],
        from existing: CapturedMediaSnapshot
    ) -> [SerializedMediaItem] {
        var resolvedItems = hydratedItems
        let hydratedSnapshot = CapturedMediaSnapshot(items: hydratedItems)
        let hydratedAudioPaths = hydratedSnapshot.audioReferences.map {
            $0.serializedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var representedAudioPaths = Set(hydratedAudioPaths)
        let existingSourceIndexCounts = sourceIndexCounts(in: existing.audioReferences)
        let hydratedSourceIndexCounts = sourceIndexCounts(in: hydratedSnapshot.audioReferences)
        let uniquelyMatchedSourceIndexes = Set(existingSourceIndexCounts.compactMap { sourceIndex, count in
            count == 1 && hydratedSourceIndexCounts[sourceIndex] == 1 ? sourceIndex : nil
        })
        var representedDescriptionTexts = Set(
            hydratedSnapshot.observationContexts.map(\.trimmedFreeText)
        )

        for (existingIndex, item) in existing.items.enumerated() {
            let shouldPreserve: Bool
            switch item {
            case .audio(let reference):
                let path = reference.serializedPath
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if representedAudioPaths.contains(path) {
                    shouldPreserve = false
                } else if reference.sourceIndex.map(
                    uniquelyMatchedSourceIndexes.contains
                ) == true {
                    shouldPreserve = false
                } else {
                    shouldPreserve = representedAudioPaths.insert(path).inserted
                }
            case .description(let context):
                shouldPreserve = representedDescriptionTexts
                    .insert(context.trimmedFreeText).inserted
            case .image, .video:
                shouldPreserve = false
            }

            if shouldPreserve {
                resolvedItems.insert(item, at: min(existingIndex, resolvedItems.count))
            }
        }

        return resolvedItems
    }

    private static func sourceIndexCounts(
        in references: [StoredMediaReference]
    ) -> [Int: Int] {
        references.reduce(into: [:]) { counts, reference in
            guard let sourceIndex = reference.sourceIndex else { return }
            counts[sourceIndex, default: 0] += 1
        }
    }

    private static func addingCloudNonVisualFallbacks(
        to items: [SerializedMediaItem],
        audioStorageURLs: [String]?,
        observationContext: ObservationContext?
    ) -> [SerializedMediaItem] {
        let supplementalAudioURLs = (audioStorageURLs ?? []).compactMap { value -> String? in
            let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizedValue.isEmpty ? nil : normalizedValue
        }
        var resolvedItems = items
        var representedAudioPaths = Set(
            CapturedMediaSnapshot(items: resolvedItems).audioReferences.map {
                $0.serializedPath.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )

        for normalizedURL in supplementalAudioURLs {
            guard representedAudioPaths.insert(normalizedURL).inserted else {
                continue
            }
            resolvedItems.append(.audio(.remoteURL(normalizedURL)))
        }

        if let observationContext, !observationContext.isEmpty {
            let alreadyRepresented = resolvedItems.contains { item in
                guard case .description(let existingContext) = item else { return false }
                return existingContext.trimmedFreeText == observationContext.trimmedFreeText
            }
            if !alreadyRepresented {
                resolvedItems.append(.description(observationContext))
            }
        }

        return resolvedItems
    }

    /// Replaces each unavailable video in its original timeline position with one image.
    /// A persisted poster is authoritative; sampled inference frames are only consulted
    /// when no poster was retained. Sampled frames are never emitted as independent pages.
    private static func demotingUnavailableVideos(
        in items: [SerializedMediaItem],
        imageURLs: [String],
        imageAvailabilityIsExplicit: Bool
    ) -> [SerializedMediaItem] {
        let videoCount = items.reduce(into: 0) { count, item in
            if case .video = item { count += 1 }
        }
        let manifestImages = items.compactMap { item -> StoredMediaReference? in
            guard case .image(let reference) = item else { return nil }
            return reference
        }
        let manifestSampledFrames = videoFrameSuffix(in: manifestImages, videoCount: videoCount)
        let remoteImages = imageURLs.map { StoredMediaReference.remoteURL($0) }
        let sampledFrames: [StoredMediaReference]
        if !remoteImages.isEmpty {
            sampledFrames = videoFrameSuffix(in: remoteImages, videoCount: videoCount)
        } else if imageAvailabilityIsExplicit {
            sampledFrames = []
        } else {
            sampledFrames = manifestSampledFrames
        }
        let sampledFramePaths = Set(
            (manifestSampledFrames + sampledFrames).map(\.serializedPath)
        )

        var videoIndex = 0
        return items.flatMap { item -> [SerializedMediaItem] in
            switch item {
            case .video(let reference):
                defer { videoIndex += 1 }
                let fallback = reference.thumbnail
                    ?? middleSampledFrame(in: sampledFrames, videoIndex: videoIndex)
                return fallback.map { [.image($0)] } ?? []
            case .image(let reference) where sampledFramePaths.contains(reference.serializedPath):
                return []
            case .image, .audio, .description:
                return [item]
            }
        }
    }

    /// Ensures a playable video also has the same single-image runtime fallback used
    /// during cloud demotion. Existing posters are preserved unchanged.
    private static func addingMissingVideoFallbacks(
        to items: [SerializedMediaItem],
        imageURLs: [String],
        imageAvailabilityIsExplicit: Bool
    ) -> [SerializedMediaItem] {
        let videoCount = items.reduce(into: 0) { count, item in
            if case .video = item { count += 1 }
        }
        let manifestImages = items.compactMap { item -> StoredMediaReference? in
            guard case .image(let reference) = item else { return nil }
            return reference
        }
        let manifestSampledFrames = videoFrameSuffix(in: manifestImages, videoCount: videoCount)
        let remoteImages = imageURLs.map { StoredMediaReference.remoteURL($0) }
        let sampledFrames: [StoredMediaReference]
        if !remoteImages.isEmpty {
            sampledFrames = videoFrameSuffix(in: remoteImages, videoCount: videoCount)
        } else if imageAvailabilityIsExplicit {
            sampledFrames = []
        } else {
            sampledFrames = manifestSampledFrames
        }
        let sampledFramePaths = Set(
            (manifestSampledFrames + sampledFrames).map(\.serializedPath)
        )

        var videoIndex = 0
        return items.flatMap { item -> [SerializedMediaItem] in
            if case .image(let reference) = item,
               sampledFramePaths.contains(reference.serializedPath) {
                return []
            }
            guard case .video(let reference) = item else { return [item] }
            defer { videoIndex += 1 }
            let fallback = reference.thumbnail
                ?? middleSampledFrame(in: sampledFrames, videoIndex: videoIndex)
            return [.video(StoredVideoMediaReference(
                video: reference.video,
                thumbnail: fallback,
                audio: reference.audio
            ))]
        }
    }

    private static func videoFrameSuffix<T>(in values: [T], videoCount: Int) -> [T] {
        let expectedFrameCount = videoCount * sampledVideoFrameCount
        guard expectedFrameCount > 0, values.count >= expectedFrameCount else { return [] }
        return Array(values.suffix(expectedFrameCount))
    }

    private static func middleSampledFrame(
        in frames: [StoredMediaReference],
        videoIndex: Int
    ) -> StoredMediaReference? {
        let index = videoIndex * sampledVideoFrameCount + sampledVideoFrameCount / 2
        return frames.indices.contains(index) ? frames[index] : middleReference(in: frames)
    }

    private static func middleReference<T>(in values: [T]) -> T? {
        guard !values.isEmpty else { return nil }
        return values[values.count / 2]
    }

    private static func middleFrameFallbackItems(from items: [SerializedMediaItem]) -> [SerializedMediaItem]? {
        var imageReferences: [StoredMediaReference] = []
        var preservedItems: [SerializedMediaItem] = []

        for item in items {
            switch item {
            case .image(let reference):
                imageReferences.append(reference)
            case .audio, .description:
                preservedItems.append(item)
            case .video:
                return nil
            }
        }

        guard imageReferences.count == sampledVideoFrameCount else { return nil }
        return [.image(imageReferences[sampledVideoFrameCount / 2])] + preservedItems
    }

    private static func middleFrameFallbackURL(from imageURLs: [String]) -> String? {
        guard imageURLs.count == sampledVideoFrameCount else { return nil }
        return imageURLs[sampledVideoFrameCount / 2]
    }
}

enum CloudMediaReplacementPolicy {
    static func shouldReplace(
        existing: CapturedMediaSnapshot,
        hydratedItems: [SerializedMediaItem],
        imageStorageURLs: [String]?,
        videoStorageURLs: [String]?
    ) -> Bool {
        guard existing.items != hydratedItems else { return false }

        let hydrated = CapturedMediaSnapshot(items: hydratedItems)
        let existingVisualReferences = existing.imageReferences
            + existing.videoReferences
            + existing.videoThumbnailReferences
        let hasRemoteVisual = existingVisualReferences.contains(where: \.isRemote)
        let hasRemoteVideo = existing.videoReferences.contains(where: \.isRemote)
        let onlyLocalOrMissingVisuals = existingVisualReferences.isEmpty || !hasRemoteVisual
        let repairsMissingVideo = !existing.summary.hasVideo && hydrated.summary.hasVideo
        let existingAudioPaths = Set(existing.audioReferences.map {
            $0.serializedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        })
        let repairsMissingAudio = hydrated.audioReferences.contains { reference in
            !existingAudioPaths.contains(
                reference.serializedPath.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        let existingAudioByPath = Dictionary(
            existing.audioReferences.map {
                ($0.serializedPath.trimmingCharacters(in: .whitespacesAndNewlines), $0)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let repairsMissingAudioIdentity = hydrated.audioReferences.contains { reference in
            guard let sourceIndex = reference.sourceIndex,
                  let existingReference = existingAudioByPath[
                    reference.serializedPath.trimmingCharacters(in: .whitespacesAndNewlines)
                  ] else {
                return false
            }
            return existingReference.sourceIndex != sourceIndex
        }
        let existingDescriptionTexts = Set(existing.observationContexts.map(\.trimmedFreeText))
        let repairsMissingDescription = hydrated.observationContexts.contains { context in
            !existingDescriptionTexts.contains(context.trimmedFreeText)
        }
        let repairsMissingNonVisualMedia = repairsMissingAudio
            || repairsMissingAudioIdentity
            || repairsMissingDescription
        let explicitlyRemovedRemoteVideo = videoStorageURLs != nil
            && normalizedURLs(videoStorageURLs).isEmpty
            && hasRemoteVideo
            && !hydrated.summary.hasVideo
        let explicitlyRemovedAllRemoteVisuals = imageStorageURLs != nil
            && videoStorageURLs != nil
            && normalizedURLs(imageStorageURLs).isEmpty
            && normalizedURLs(videoStorageURLs).isEmpty
            && hasRemoteVisual
            && !hydrated.summary.hasImage
            && !hydrated.summary.hasVideo

        if hydratedItems.isEmpty {
            return explicitlyRemovedRemoteVideo || explicitlyRemovedAllRemoteVisuals
        }
        return onlyLocalOrMissingVisuals
            || repairsMissingVideo
            || repairsMissingNonVisualMedia
            || explicitlyRemovedRemoteVideo
            || explicitlyRemovedAllRemoteVisuals
    }

    private static func normalizedURLs(_ values: [String]?) -> [String] {
        (values ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

enum PersistedCapturedMediaKind: String, Codable, Sendable {
    case image
    case audio
    case video
    case description
}

@Model
public final class CapturedMediaEntry {
    @Attribute(.unique) public var id: String
    public var orderIndex: Int
    public var kindRaw: String
    public var storageRaw: String
    public var mediaPath: String
    public var observationContextJSON: String

    init(
        id: String = UUID().uuidString,
        orderIndex: Int,
        item: SerializedMediaItem
    ) {
        self.id = id
        self.orderIndex = orderIndex

        switch item {
        case .image(let reference):
            self.kindRaw = PersistedCapturedMediaKind.image.rawValue
            self.storageRaw = reference.storage.rawValue
            self.mediaPath = reference.serializedPath
            self.observationContextJSON = ""
        case .audio(let reference):
            self.kindRaw = PersistedCapturedMediaKind.audio.rawValue
            self.storageRaw = reference.storage.rawValue
            self.mediaPath = reference.serializedPath
            self.observationContextJSON = ""
        case .video(let reference):
            self.kindRaw = PersistedCapturedMediaKind.video.rawValue
            self.storageRaw = reference.video.storage.rawValue
            self.mediaPath = reference.serializedPath
            self.observationContextJSON = ""
        case .description(let context):
            self.kindRaw = PersistedCapturedMediaKind.description.rawValue
            self.storageRaw = ""
            self.mediaPath = ""
            let contextData = try? JSONEncoder().encode(context)
            self.observationContextJSON = contextData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
    }

    var kind: PersistedCapturedMediaKind? {
        PersistedCapturedMediaKind(rawValue: kindRaw)
    }

    var serializedItem: SerializedMediaItem? {
        switch kind {
        case .image:
            guard let storage = MediaStorageLocation(rawValue: storageRaw), !mediaPath.isEmpty else {
                return nil
            }
            return .image(StoredMediaReference(storage: storage, path: mediaPath))
        case .audio:
            guard let storage = MediaStorageLocation(rawValue: storageRaw), !mediaPath.isEmpty else {
                return nil
            }
            return .audio(StoredMediaReference(storage: storage, path: mediaPath))
        case .video:
            guard let storage = MediaStorageLocation(rawValue: storageRaw), !mediaPath.isEmpty else {
                return nil
            }
            return .video(StoredVideoMediaReference(StoredMediaReference(storage: storage, path: mediaPath)))
        case .description:
            guard let contextData = observationContextJSON.data(using: .utf8),
                  let context = try? JSONDecoder().decode(ObservationContext.self, from: contextData) else {
                return nil
            }
            return .description(context)
        case .none:
            return nil
        }
    }
}

extension CapturedMediaEntry {
    static func makeEntries(from items: [SerializedMediaItem]) -> [CapturedMediaEntry] {
        items.enumerated().map { index, item in
            CapturedMediaEntry(orderIndex: index, item: item)
        }
    }

    static func serializedItems(from entries: [CapturedMediaEntry]) -> [SerializedMediaItem] {
        entries
            .sorted { lhs, rhs in
                if lhs.orderIndex == rhs.orderIndex {
                    return lhs.id < rhs.id
                }
                return lhs.orderIndex < rhs.orderIndex
            }
            .compactMap(\.serializedItem)
    }
}

enum CapturedMediaKind: String, Sendable, Equatable {
    case audio
    case video
    case describe
    case audioAndDescribe
    case other
}

struct CapturedMediaSummary: Sendable, Equatable {
    let hasImage: Bool
    let hasAudio: Bool
    let hasVideo: Bool
    let hasDescription: Bool

    static let empty = CapturedMediaSummary(hasImage: false, hasAudio: false, hasVideo: false, hasDescription: false)

    var hasNonVisualMedia: Bool {
        hasAudio || hasDescription
    }

    var isNonVisualOnly: Bool {
        !hasImage && hasNonVisualMedia
    }

    var preferredThumbnailKind: CapturedMediaKind? {
        if hasVideo { return .video }

        switch (hasAudio, hasDescription) {
        case (true, true):
            return .audioAndDescribe
        case (true, false):
            return .audio
        case (false, true):
            return .describe
        case (false, false):
            return nil
        }
    }
}

/// Canonical decoder for persisted media JSON shared by live and historic scan flows.
enum MediaJSONParser {
    static func jsonString(from items: [SerializedMediaItem]) -> String? {
        guard !items.isEmpty,
              let data = try? JSONEncoder().encode(items) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func serializedItems(jsonString: String) -> [SerializedMediaItem]? {
        guard let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode([SerializedMediaItem].self, from: jsonData)
    }

    static func imagePaths(jsonString: String) -> [String] {
        CapturedMediaSnapshot(jsonString: jsonString).imagePaths
    }

    static func primaryImagePath(jsonString: String) -> String? {
        CapturedMediaSnapshot(jsonString: jsonString).primaryImagePath
    }

    static func imageReferences(jsonString: String) -> [StoredMediaReference] {
        CapturedMediaSnapshot(jsonString: jsonString).imageReferences
    }

    static func audioPaths(jsonString: String) -> [String] {
        CapturedMediaSnapshot(jsonString: jsonString).audioPaths
    }

    static func audioReferences(jsonString: String) -> [StoredMediaReference] {
        CapturedMediaSnapshot(jsonString: jsonString).audioReferences
    }

    static func videoPaths(jsonString: String) -> [String] {
        CapturedMediaSnapshot(jsonString: jsonString).videoPaths
    }

    static func videoReferences(jsonString: String) -> [StoredMediaReference] {
        CapturedMediaSnapshot(jsonString: jsonString).videoReferences
    }

    static func observationContexts(jsonString: String) -> [ObservationContext] {
        CapturedMediaSnapshot(jsonString: jsonString).observationContexts
    }

    static func hasCloudImage(jsonString: String) -> Bool {
        CapturedMediaSnapshot(jsonString: jsonString).hasCloudImage
    }

    static func modalitySummary(jsonString: String) -> CapturedMediaSummary {
        CapturedMediaSnapshot(jsonString: jsonString).summary
    }

    static func parse(jsonString: String) -> ActiveScanMedia? {
        let snapshot = CapturedMediaSnapshot(jsonString: jsonString)
        guard !snapshot.items.isEmpty else {
            return nil
        }
        return snapshot.activeScanMedia
    }
}

private func firstThumbnailImagePath(in items: [SerializedMediaItem]) -> String? {
    CapturedMediaSnapshot(items: items).primaryImagePath
}

private func replaceCapturedMediaEntries(
    on record: LocalScanRecord,
    items: [SerializedMediaItem]
) {
    let newEntries = CapturedMediaEntry.makeEntries(from: items)

    if let context = record.modelContext {
        for existingEntry in record.capturedMediaEntries ?? [] {
            context.delete(existingEntry)
        }
    }

    record.capturedMediaEntries = newEntries
}

private func replaceCapturedMediaEntries(
    on queuedScan: OfflineQueuedScan,
    items: [SerializedMediaItem]
) {
    let newEntries = CapturedMediaEntry.makeEntries(from: items)

    if let context = queuedScan.modelContext {
        for existingEntry in queuedScan.capturedMediaEntries ?? [] {
            context.delete(existingEntry)
        }
    }

    queuedScan.capturedMediaEntries = newEntries
}

private func resolvedSerializedMediaItems(
    capturedMediaJSON: String?,
    capturedMediaEntries: @autoclosure () -> [CapturedMediaEntry]?
) -> [SerializedMediaItem] {
    // Prefer scalar JSON so SwiftUI read paths do not fault relationship rows during layout.
    if let capturedMediaJSON,
       let jsonItems = MediaJSONParser.serializedItems(jsonString: capturedMediaJSON) {
        return jsonItems
    }

    let capturedMediaEntries = capturedMediaEntries()
    if let capturedMediaEntries, !capturedMediaEntries.isEmpty {
        return CapturedMediaEntry.serializedItems(from: capturedMediaEntries)
    }

    return []
}

extension LocalScanRecord {
    var capturedMediaSnapshot: CapturedMediaSnapshot {
        CapturedMediaSnapshot(items: serializedCapturedMediaItems)
    }

    var serializedCapturedMediaItems: [SerializedMediaItem] {
        resolvedSerializedMediaItems(
            capturedMediaJSON: capturedMediaJSON,
            capturedMediaEntries: capturedMediaEntries
        )
    }

    func replaceCapturedMedia(with items: [SerializedMediaItem]) {
        capturedMediaJSON = MediaJSONParser.jsonString(from: items)
        coverImagePath = firstThumbnailImagePath(in: items)
        replaceCapturedMediaEntries(on: self, items: items)
    }
}

extension OfflineQueuedScan {
    var capturedMediaSnapshot: CapturedMediaSnapshot {
        CapturedMediaSnapshot(items: serializedCapturedMediaItems)
    }

    var serializedCapturedMediaItems: [SerializedMediaItem] {
        resolvedSerializedMediaItems(
            capturedMediaJSON: capturedMediaJSON,
            capturedMediaEntries: capturedMediaEntries
        )
    }

    func replaceCapturedMedia(with items: [SerializedMediaItem]) {
        capturedMediaJSON = MediaJSONParser.jsonString(from: items)
        coverImagePath = firstThumbnailImagePath(in: items)
        replaceCapturedMediaEntries(on: self, items: items)
    }
}
