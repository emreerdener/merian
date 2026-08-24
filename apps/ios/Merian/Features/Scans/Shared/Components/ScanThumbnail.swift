import SwiftUI
import UIKit

enum ScanThumbnailPlaceholderStyle: Sendable, Equatable {
    case archived
    case pendingReference(CapturedMediaKind)
    case unavailableReference(CapturedMediaKind)
}

struct ScanThumbnailPresentation: Sendable, Equatable {
    let imagePath: String?
    let fallbackImageUrl: String?
    let audioPath: String?
    let hasVideo: Bool
    let hasAudio: Bool
    let placeholderStyle: ScanThumbnailPlaceholderStyle
}

struct ScanThumbnailBackfillCandidate: Sendable, Equatable {
    let scanId: String
    let scientificName: String
    let gbifTaxonKey: Int?

    init?(record: LocalScanRecord) {
        guard record.canResolveReferenceThumbnail,
              !record.hasStoredVisualThumbnail,
              record.referenceImageUrl?.trimmedNonEmpty == nil,
              let identity = Self.referenceIdentity(for: record) else {
            return nil
        }

        self.scanId = record.id
        self.scientificName = identity.scientificName
        self.gbifTaxonKey = identity.gbifTaxonKey
    }

    /// Builds a reference-image request for a map thumbnail whose stored owner
    /// media is absent or unreadable. Unlike the library-wide non-visual
    /// backfill, this path may recover archived or stale visual records because
    /// the caller has already established that no captured bitmap can render.
    init?(missingVisualFallbackFor record: LocalScanRecord) {
        guard record.isBiological,
              record.referenceImageUrl?.trimmedNonEmpty == nil,
              let identity = Self.referenceIdentity(for: record) else {
            return nil
        }

        self.scanId = record.id
        self.scientificName = identity.scientificName
        self.gbifTaxonKey = identity.gbifTaxonKey
    }

    private static func referenceIdentity(
        for record: LocalScanRecord
    ) -> (scientificName: String, gbifTaxonKey: Int?)? {
        guard record.hasResolvedBiologicalIdentification else { return nil }

        let override = record.userIdentificationOverride?.trimmedNonEmpty
        guard let scientificName = override
            ?? record.scientificName.trimmedNonEmpty,
            !ReferenceImageVisibilityPolicy.shouldSuppress(
                isHumanSubject: record.isHumanSubject,
                scientificName: scientificName
            ) else {
            return nil
        }

        return (
            scientificName: scientificName,
            gbifTaxonKey: override == nil ? record.gbifTaxonKey : nil
        )
    }
}

enum ScanThumbnailProjection {
    static func presentation(
        isBiological: Bool,
        isLocallyArchived: Bool,
        scientificName: String,
        coverImagePath: String?,
        referenceImageUrl: String?,
        mediaSnapshot: CapturedMediaSnapshot,
        canResolveReferenceImage: Bool? = nil
    ) -> ScanThumbnailPresentation {
        let fallbackUrl = referenceImageUrl?.trimmedNonEmpty
        let mediaSummary = mediaSnapshot.summary
        let preferredVisualPath = coverImagePath?.trimmedNonEmpty
            ?? mediaSnapshot.primaryImagePath?.trimmedNonEmpty
        let hasStoredVisual = preferredVisualPath != nil || mediaSummary.hasImage
        let normalizedScientificName = scientificName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let inferredReferenceEligibility = isBiological
            && !isLocallyArchived
            && !normalizedScientificName.isEmpty
            && normalizedScientificName != "taxonomy unavailable"
            && normalizedScientificName != "unknown subject"
            && !hasStoredVisual
        let canResolveReference = canResolveReferenceImage
            ?? inferredReferenceEligibility
        let mediaKind = mediaSummary.preferredThumbnailKind ?? .other

        if hasStoredVisual {
            return ScanThumbnailPresentation(
                imagePath: preferredVisualPath,
                fallbackImageUrl: fallbackUrl,
                audioPath: nil,
                hasVideo: mediaSummary.hasVideo,
                hasAudio: mediaSummary.hasAudio,
                placeholderStyle: .archived
            )
        }

        let preferredAudioPath: String? = if mediaSummary.hasAudio,
                                             !mediaSummary.hasImage,
                                             !mediaSummary.hasDescription {
            mediaSnapshot.audioPaths.first?.trimmedNonEmpty
        } else {
            nil
        }
        if let preferredAudioPath {
            return ScanThumbnailPresentation(
                imagePath: nil,
                fallbackImageUrl: fallbackUrl,
                audioPath: preferredAudioPath,
                hasVideo: false,
                hasAudio: true,
                placeholderStyle: fallbackUrl != nil || canResolveReference
                    ? .pendingReference(mediaKind)
                    : .unavailableReference(mediaKind)
            )
        }

        if fallbackUrl != nil {
            return ScanThumbnailPresentation(
                imagePath: nil,
                fallbackImageUrl: fallbackUrl,
                audioPath: nil,
                hasVideo: mediaSummary.hasVideo,
                hasAudio: mediaSummary.hasAudio,
                placeholderStyle: .pendingReference(mediaKind)
            )
        }

        if canResolveReference {
            return ScanThumbnailPresentation(
                imagePath: nil,
                fallbackImageUrl: nil,
                audioPath: nil,
                hasVideo: mediaSummary.hasVideo,
                hasAudio: mediaSummary.hasAudio,
                placeholderStyle: .pendingReference(mediaKind)
            )
        }

        let hasNonVisualOnlyMedia = !hasStoredVisual
            && (mediaSummary.hasNonVisualMedia || coverImagePath?.trimmedNonEmpty == nil)
        if hasNonVisualOnlyMedia || coverImagePath?.trimmedNonEmpty == nil {
            return ScanThumbnailPresentation(
                imagePath: nil,
                fallbackImageUrl: nil,
                audioPath: nil,
                hasVideo: mediaSummary.hasVideo,
                hasAudio: mediaSummary.hasAudio,
                placeholderStyle: .unavailableReference(mediaKind)
            )
        }

        return ScanThumbnailPresentation(
            imagePath: preferredVisualPath,
            fallbackImageUrl: fallbackUrl,
            audioPath: nil,
            hasVideo: mediaSummary.hasVideo,
            hasAudio: mediaSummary.hasAudio,
            placeholderStyle: .archived
        )
    }
}

extension LocalScanRecord {
    var scanThumbnailPresentation: ScanThumbnailPresentation {
        scanThumbnailPresentation(capturedMediaSnapshot: capturedMediaSnapshot)
    }

    func scanThumbnailPresentation(
        capturedMediaSnapshot mediaSnapshot: CapturedMediaSnapshot
    ) -> ScanThumbnailPresentation {
        ScanThumbnailProjection.presentation(
            isBiological: isBiological,
            isLocallyArchived: isLocallyArchived,
            scientificName: userIdentificationOverride?.trimmedNonEmpty
                ?? scientificName,
            coverImagePath: coverImagePath,
            referenceImageUrl: referenceImageUrl,
            mediaSnapshot: mediaSnapshot,
            canResolveReferenceImage: canResolveReferenceThumbnail
        )
    }

    var hasStoredVisualThumbnail: Bool {
        preferredVisualThumbnailPath != nil || capturedMediaSummary.hasImage
    }

    var canResolveReferenceThumbnail: Bool {
        guard isBiological,
              !isLocallyArchived,
              !hasStoredVisualThumbnail,
              hasResolvedBiologicalIdentification else {
            return false
        }

        let effectiveScientificName = userIdentificationOverride?.trimmedNonEmpty
            ?? scientificName
        return !ReferenceImageVisibilityPolicy.shouldSuppress(
            isHumanSubject: isHumanSubject,
            scientificName: effectiveScientificName
        )
    }

    private var capturedMediaSummary: CapturedMediaSummary {
        capturedMediaSnapshot.summary
    }

    private var preferredVisualThumbnailPath: String? {
        if let coverImagePath = coverImagePath?.trimmedNonEmpty {
            return coverImagePath
        }

        return capturedMediaSnapshot.primaryImagePath?.trimmedNonEmpty
    }

}

struct ScanThumbnail: View {
    // MARK: - Asset Dependencies
    let isOnline: Bool
    let imagePath: String?
    let fallbackImageUrl: String?
    let audioPath: String?
    let hasVideo: Bool
    let hasAudio: Bool
    let prefersReferenceForAudio: Bool
    let showsAudioBadge: Bool
    let mediaBadgeAlignment: Alignment
    let maxDimension: Int
    let placeholderStyle: ScanThumbnailPlaceholderStyle
    let isArchivedVisual: Bool
    let onReferenceImageNeeded: (@MainActor () -> Void)?

    // MARK: - Rendering State
    @State private var thumbnail: UIImage?
    @State private var hasFailedToLoad: Bool = false

    init(
        isOnline: Bool,
        imagePath: String?,
        fallbackImageUrl: String? = nil,
        audioPath: String? = nil,
        hasVideo: Bool = false,
        hasAudio: Bool = false,
        prefersReferenceForAudio: Bool = false,
        showsAudioBadge: Bool = false,
        mediaBadgeAlignment: Alignment = .bottomTrailing,
        maxDimension: Int = 600,
        placeholderStyle: ScanThumbnailPlaceholderStyle = .archived,
        isArchivedVisual: Bool = false,
        onReferenceImageNeeded: (@MainActor () -> Void)? = nil
    ) {
        self.isOnline = isOnline
        self.imagePath = imagePath
        self.fallbackImageUrl = fallbackImageUrl
        self.audioPath = audioPath
        self.hasVideo = hasVideo
        self.hasAudio = hasAudio
        self.prefersReferenceForAudio = prefersReferenceForAudio
        self.showsAudioBadge = showsAudioBadge
        self.mediaBadgeAlignment = mediaBadgeAlignment
        self.maxDimension = maxDimension
        self.placeholderStyle = placeholderStyle
        self.isArchivedVisual = isArchivedVisual
        self.onReferenceImageNeeded = onReferenceImageNeeded
    }

    init(
        record: LocalScanRecord,
        isOnline: Bool,
        maxDimension: Int = 600,
        prefersReferenceForAudio: Bool = false,
        showsAudioBadge: Bool = false,
        mediaBadgeAlignment: Alignment = .bottomTrailing,
        onReferenceImageNeeded: (@MainActor () -> Void)? = nil
    ) {
        let presentation = record.scanThumbnailPresentation
        self.init(
            isOnline: isOnline,
            imagePath: presentation.imagePath,
            fallbackImageUrl: presentation.fallbackImageUrl,
            audioPath: presentation.audioPath,
            hasVideo: presentation.hasVideo,
            hasAudio: presentation.hasAudio,
            prefersReferenceForAudio: prefersReferenceForAudio,
            showsAudioBadge: showsAudioBadge,
            mediaBadgeAlignment: mediaBadgeAlignment,
            maxDimension: maxDimension,
            placeholderStyle: presentation.placeholderStyle,
            isArchivedVisual: record.isLocallyArchived,
            onReferenceImageNeeded: onReferenceImageNeeded
        )
    }

    // MARK: - Visual Hierarchy
    var body: some View {
        Color.clear
            .aspectRatio(1.0, contentMode: .fit)
            .overlay(
                Group {
                    if let uiImage = thumbnail {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                    } else if hasFailedToLoad {
                        failureView
                    } else {
                        loadingView
                    }
                }
            )
            .clipped()
            .overlay(alignment: mediaBadgeAlignment) {
                if hasVideo || (hasAudio && showsAudioBadge), thumbnail != nil {
                    Image(systemName: hasVideo ? "play.fill" : "waveform")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.black.opacity(0.62))
                        .clipShape(Circle())
                        .padding(8)
                        .accessibilityLabel(hasVideo ? "Video" : "Audio recording")
                }
            }
        .task(id: loadTaskID) {
            await MainActor.run {
                thumbnail = nil
                hasFailedToLoad = false
            }
            await loadThumbnail()
        }
    }

    private var loadTaskID: String {
        "\(imagePath ?? "no_image_path")|\(fallbackImageUrl ?? "no_fallback_url")|\(audioPath ?? "no_audio_path")|\(placeholderStyle.taskKey)|\(remoteRetryTaskKey)"
    }

    private var remoteRetryTaskKey: String {
        guard hasRemoteVisualSource || supportsReferenceImageRecovery else {
            return "local_media"
        }
        return isOnline ? "remote_online" : "remote_offline"
    }

    private var hasRemoteVisualSource: Bool {
        [imagePath, fallbackImageUrl]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .contains { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
    }

    private var supportsReferenceImageRecovery: Bool {
        guard onReferenceImageNeeded != nil,
              fallbackImageUrl?.trimmedNonEmpty == nil else {
            return false
        }
        if case .unavailableReference = placeholderStyle { return false }
        return true
    }

    @ViewBuilder
    private var loadingView: some View {
        if prefersReferenceForAudio, hasAudio {
            GlowPulsingSkeletonView(cornerRadius: 0, style: .raisedGrid)
                .accessibilityHidden(true)
        } else {
            loadingPlaceholderByStyle
        }
    }

    @ViewBuilder
    private var loadingPlaceholderByStyle: some View {
        switch placeholderStyle {
        case .pendingReference(let mediaKind):
            ScanThumbnailPlaceholderView(
                mediaKind: mediaKind,
                title: "Reference pending",
                subtitle: "Fetching fallback image"
            )
        case .unavailableReference(let mediaKind):
            ScanThumbnailPlaceholderView(
                mediaKind: mediaKind,
                title: "Non-visual scan",
                subtitle: "No reference photo yet"
            )
        case .archived:
            if imagePath == nil && fallbackImageUrl == nil {
                ArchivedVisualsView()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
        }
    }

    @ViewBuilder
    private var failureView: some View {
        switch placeholderStyle {
        case .pendingReference(let mediaKind):
            ScanThumbnailPlaceholderView(
                mediaKind: mediaKind,
                title: "Reference unavailable",
                subtitle: nil
            )
        case .unavailableReference(let mediaKind):
            ScanThumbnailPlaceholderView(
                mediaKind: mediaKind,
                title: "Non-visual scan",
                subtitle: "No reference photo"
            )
        case .archived:
            if isArchivedVisual {
                ArchivedVisualsView()
            } else {
                UnavailableVisualsView(isOffline: !isOnline)
            }
        }
    }

    private func loadThumbnail() async {
        if let audioPath, !prefersReferenceForAudio {
            let spectrogramImage = await AudioSpectrogramThumbnailLoader.shared.loadImage(
                fromPath: audioPath,
                maxDimension: maxDimension
            )
            if let spectrogramImage {
                await MainActor.run {
                    thumbnail = spectrogramImage
                    hasFailedToLoad = false
                }
                return
            }
        }

        guard imagePath != nil || fallbackImageUrl != nil else {
            await MainActor.run {
                hasFailedToLoad = false
            }
            await requestReferenceImageIfNeeded()
            return
        }

        let loadedImage = await LocalImageLoader.shared.loadImage(
            fromPath: imagePath,
            fallbackUrl: fallbackImageUrl,
            maxDimension: maxDimension
        )
        guard !Task.isCancelled else { return }

        await MainActor.run {
            if let loadedImage {
                thumbnail = loadedImage
                hasFailedToLoad = false
            } else {
                hasFailedToLoad = true
            }
        }
        if loadedImage == nil {
            await requestReferenceImageIfNeeded()
        }
    }

    private func requestReferenceImageIfNeeded() async {
        guard !Task.isCancelled,
              supportsReferenceImageRecovery,
              isOnline,
              let onReferenceImageNeeded else {
            return
        }
        await MainActor.run {
            onReferenceImageNeeded()
        }
    }
}

actor AudioSpectrogramThumbnailLoader {
    static let shared = AudioSpectrogramThumbnailLoader()

    private var activeTasks: [String: Task<UIImage?, Never>] = [:]

    func loadImage(fromPath audioPath: String, maxDimension: Int = 1024) async -> UIImage? {
        let cacheKey = "audio_spectrogram_\(audioPath)_\(maxDimension)"

        if let cached = ImageCache.shared.get(forKey: cacheKey) {
            return cached
        }

        if let existingTask = activeTasks[cacheKey] {
            return await existingTask.value
        }

        let fetchTask = Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let resolvedAudio = await Self.resolveAudioURL(from: audioPath) else {
                return nil
            }
            defer {
                if resolvedAudio.shouldDeleteAfterRendering {
                    try? FileManager.default.removeItem(at: resolvedAudio.url)
                }
            }

            let columns = await AudioSpectrogramDecoder.decodeColumns(fromFilePath: resolvedAudio.url.path)
            guard !columns.isEmpty,
                  let image = Self.renderThumbnail(columns: columns, maxDimension: maxDimension) else {
                return nil
            }

            ImageCache.shared.set(image, forKey: cacheKey)
            return image
        }

        activeTasks[cacheKey] = fetchTask

        defer {
            if activeTasks[cacheKey] == fetchTask {
                activeTasks.removeValue(forKey: cacheKey)
            }
        }

        return await fetchTask.value
    }

    nonisolated func prefetch(audioPaths: [String], maxDimension: Int) {
        guard !audioPaths.isEmpty else { return }

        Task(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                var inFlight = 0
                for audioPath in audioPaths {
                    if inFlight >= 2 {
                        await group.next()
                        inFlight -= 1
                    }

                    group.addTask(priority: .utility) {
                        _ = await self.loadImage(fromPath: audioPath, maxDimension: maxDimension)
                    }
                    inFlight += 1
                }
            }
        }
    }

    private struct ResolvedAudioURL: Sendable {
        let url: URL
        let shouldDeleteAfterRendering: Bool
    }

    private static nonisolated func resolveAudioURL(from audioPath: String) async -> ResolvedAudioURL? {
        if let remoteURL = SecureTransportPolicy.httpsURL(from: audioPath) {
            var request = URLRequest(url: remoteURL)
            request.timeoutInterval = 30

            do {
                let (temporaryURL, response) = try await URLSession.shared.download(for: request)
                guard let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode),
                      response.expectedContentLength <= Int64(MerianConfig.audioPayloadMaxBytes) else {
                    return nil
                }

                let byteSize = try temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard byteSize <= MerianConfig.audioPayloadMaxBytes else { return nil }

                let renderURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("explore-spectrogram-\(UUID().uuidString).wav")
                try FileManager.default.moveItem(at: temporaryURL, to: renderURL)
                return ResolvedAudioURL(url: renderURL, shouldDeleteAfterRendering: true)
            } catch {
                return nil
            }
        }

        if audioPath.starts(with: "file://"), let url = URL(string: audioPath) {
            return ResolvedAudioURL(url: url, shouldDeleteAfterRendering: false)
        }

        if audioPath.starts(with: "/") {
            return ResolvedAudioURL(
                url: URL(fileURLWithPath: audioPath),
                shouldDeleteAfterRendering: false
            )
        }

        let documentsURL = URL.documentsDirectory.appendingPathComponent(audioPath)
        if FileManager.default.fileExists(atPath: documentsURL.path) {
            return ResolvedAudioURL(url: documentsURL, shouldDeleteAfterRendering: false)
        }

        return ResolvedAudioURL(
            url: FileManager.default.temporaryDirectory.appendingPathComponent(audioPath),
            shouldDeleteAfterRendering: false
        )
    }

    private static nonisolated func renderThumbnail(
        columns: [SpectrogramColumn],
        maxDimension: Int
    ) -> UIImage? {
        guard !columns.isEmpty else { return nil }

        let dimension = max(64, maxDimension)
        let size = CGSize(width: dimension, height: dimension)
        return SpectrogramRenderer.image(
            columns: columns,
            layout: .fitToData,
            targetSize: size,
            scale: 1
        )
    }
}

private struct ScanThumbnailPlaceholderView: View {
    let mediaKind: CapturedMediaKind
    let title: String
    let subtitle: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(uiColor: .secondarySystemFill),
                    Color(uiColor: .tertiarySystemFill)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 6) {
                Image(systemName: mediaKind.iconName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.72))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .padding(12)
        }
    }
}

private extension CapturedMediaKind {
    var iconName: String {
        switch self {
        case .audio:
            return "waveform"
        case .video:
            return "play.rectangle"
        case .describe:
            return "text.bubble"
        case .audioAndDescribe:
            return "waveform.and.mic"
        case .other:
            return "sparkles.rectangle.stack"
        }
    }
}

private extension ScanThumbnailPlaceholderStyle {
    var taskKey: String {
        switch self {
        case .archived:
            return "archived"
        case .pendingReference(let mediaKind):
            return "pending_\(mediaKind.rawValue)"
        case .unavailableReference(let mediaKind):
            return "unavailable_\(mediaKind.rawValue)"
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
