import Foundation

extension CapturedMediaSnapshot {
    private static let sampledVideoFrameCount = 5

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
