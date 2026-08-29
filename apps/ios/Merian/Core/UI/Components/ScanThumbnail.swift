import SwiftUI
import UIKit

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

    private let loader: ScanThumbnailLoader

    // MARK: - Rendering State

    @State private var thumbnail: UIImage?
    @State private var hasFailedToLoad = false

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
        onReferenceImageNeeded: (@MainActor () -> Void)? = nil,
        loadingDependencies: ScanThumbnailLoadingDependencies = .live
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
        loader = ScanThumbnailLoader(dependencies: loadingDependencies)
    }

    init(
        record: LocalScanRecord,
        isOnline: Bool,
        maxDimension: Int = 600,
        prefersReferenceForAudio: Bool = false,
        showsAudioBadge: Bool = false,
        mediaBadgeAlignment: Alignment = .bottomTrailing,
        onReferenceImageNeeded: (@MainActor () -> Void)? = nil,
        loadingDependencies: ScanThumbnailLoadingDependencies = .live
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
            onReferenceImageNeeded: onReferenceImageNeeded,
            loadingDependencies: loadingDependencies
        )
    }

    // MARK: - Visual Hierarchy

    var body: some View {
        Color.clear
            .aspectRatio(1.0, contentMode: .fit)
            .overlay(
                Group {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
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
                if hasVideo || (hasAudio && showsAudioBadge),
                   thumbnail != nil {
                    Image(systemName: hasVideo ? "play.fill" : "waveform")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.black.opacity(0.62))
                        .clipShape(Circle())
                        .padding(8)
                        .accessibilityLabel(
                            hasVideo ? "Video" : "Audio recording"
                        )
                }
            }
            .task(id: loadTaskID) {
                await reloadThumbnail()
            }
    }

    private var loadTaskID: ScanThumbnailLoadTaskID {
        ScanThumbnailLoadTaskID(
            request: loadRequest,
            placeholderKey: placeholderStyle.taskKey,
            remoteAvailability: (
                hasRemoteVisualSource || supportsReferenceImageRecovery
            ) ? isOnline : nil
        )
    }

    private var hasRemoteVisualSource: Bool {
        [imagePath, fallbackImageUrl]
            .compactMap {
                $0?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            }
            .contains {
                $0.hasPrefix("http://") || $0.hasPrefix("https://")
            }
    }

    private var supportsReferenceImageRecovery: Bool {
        guard onReferenceImageNeeded != nil,
              fallbackImageUrl?.trimmedNonEmptyValue == nil else {
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

    private var loadRequest: ScanThumbnailLoadRequest {
        ScanThumbnailLoadRequest(
            imagePath: imagePath,
            fallbackImageURL: fallbackImageUrl,
            audioPath: audioPath,
            prefersReferenceForAudio: prefersReferenceForAudio,
            maxDimension: maxDimension
        )
    }

    @MainActor
    private func reloadThumbnail() async {
        thumbnail = nil
        hasFailedToLoad = false

        guard let result = await loader.load(loadRequest),
              !Task.isCancelled else {
            return
        }

        switch result {
        case .loaded(let image):
            thumbnail = image
            hasFailedToLoad = false
        case .noVisualSource:
            hasFailedToLoad = false
            requestReferenceImageIfNeeded()
        case .failed:
            hasFailedToLoad = true
            requestReferenceImageIfNeeded()
        }
    }

    @MainActor
    private func requestReferenceImageIfNeeded() {
        guard !Task.isCancelled,
              supportsReferenceImageRecovery,
              isOnline,
              let onReferenceImageNeeded else {
            return
        }
        onReferenceImageNeeded()
    }
}

private struct ScanThumbnailLoadTaskID: Hashable, Sendable {
    let request: ScanThumbnailLoadRequest
    let placeholderKey: String
    let remoteAvailability: Bool?
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
                Image(systemName: mediaKind.thumbnailIconName)
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
    var thumbnailIconName: String {
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
