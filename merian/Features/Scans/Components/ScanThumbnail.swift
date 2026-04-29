import SwiftUI

enum ScanThumbnailPlaceholderStyle: Sendable, Equatable {
    case archived
    case pendingReference(CapturedMediaKind)
    case unavailableReference(CapturedMediaKind)
}

struct ScanThumbnailPresentation: Sendable, Equatable {
    let imagePath: String?
    let fallbackImageUrl: String?
    let placeholderStyle: ScanThumbnailPlaceholderStyle
}

struct ScanThumbnailBackfillCandidate: Sendable, Equatable {
    let scanId: String
    let scientificName: String
    let gbifTaxonKey: Int?

    init?(record: LocalScanRecord) {
        guard record.canResolveReferenceThumbnail,
              !record.hasStoredVisualThumbnail,
              record.referenceImageUrl?.trimmedNonEmpty == nil else {
            return nil
        }

        self.scanId = record.id
        self.scientificName = record.scientificName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.gbifTaxonKey = record.gbifTaxonKey
    }
}

extension LocalScanRecord {
    var scanThumbnailPresentation: ScanThumbnailPresentation {
        let fallbackUrl = referenceImageUrl?.trimmedNonEmpty

        if isLocallyArchived {
            return ScanThumbnailPresentation(
                imagePath: preferredVisualThumbnailPath,
                fallbackImageUrl: fallbackUrl,
                placeholderStyle: .archived
            )
        }

        if hasStoredVisualThumbnail {
            return ScanThumbnailPresentation(
                imagePath: preferredVisualThumbnailPath,
                fallbackImageUrl: fallbackUrl,
                placeholderStyle: .archived
            )
        }

        let mediaKind = capturedMediaKindForThumbnail
        if fallbackUrl != nil {
            return ScanThumbnailPresentation(
                imagePath: nil,
                fallbackImageUrl: fallbackUrl,
                placeholderStyle: .pendingReference(mediaKind)
            )
        }

        if canResolveReferenceThumbnail {
            return ScanThumbnailPresentation(
                imagePath: nil,
                fallbackImageUrl: nil,
                placeholderStyle: .pendingReference(mediaKind)
            )
        }

        if hasNonVisualOnlyMedia || coverImagePath?.trimmedNonEmpty == nil {
            return ScanThumbnailPresentation(
                imagePath: nil,
                fallbackImageUrl: nil,
                placeholderStyle: .unavailableReference(mediaKind)
            )
        }

        return ScanThumbnailPresentation(
            imagePath: preferredVisualThumbnailPath,
            fallbackImageUrl: fallbackUrl,
            placeholderStyle: .archived
        )
    }

    var hasStoredVisualThumbnail: Bool {
        preferredVisualThumbnailPath != nil || capturedMediaSummary.hasImage
    }

    var hasNonVisualOnlyMedia: Bool {
        !hasStoredVisualThumbnail && (capturedMediaSummary.hasNonVisualMedia || coverImagePath?.trimmedNonEmpty == nil)
    }

    var canResolveReferenceThumbnail: Bool {
        guard isBiological, !isLocallyArchived else { return false }
        let normalizedName = scientificName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedName.isEmpty,
              normalizedName != "taxonomy unavailable",
              normalizedName != "unknown subject" else {
            return false
        }
        return !hasStoredVisualThumbnail
    }

    private var capturedMediaSummary: CapturedMediaSummary {
        capturedMediaJSON.map(MediaJSONParser.modalitySummary(jsonString:)) ?? .empty
    }

    private var preferredVisualThumbnailPath: String? {
        if let coverImagePath = coverImagePath?.trimmedNonEmpty {
            return coverImagePath
        }

        if let json = capturedMediaJSON {
            return MediaJSONParser.primaryImagePath(jsonString: json)?.trimmedNonEmpty
        }

        return nil
    }

    private var capturedMediaKindForThumbnail: CapturedMediaKind {
        capturedMediaSummary.preferredThumbnailKind ?? .other
    }
}

struct ScanThumbnail: View {
    // MARK: - Asset Dependencies
    let imagePath: String?
    let fallbackImageUrl: String?
    let maxDimension: Int
    let placeholderStyle: ScanThumbnailPlaceholderStyle

    // MARK: - Rendering State
    @State private var thumbnail: UIImage?
    @State private var hasFailedToLoad: Bool = false

    init(
        imagePath: String?,
        fallbackImageUrl: String? = nil,
        maxDimension: Int = 600,
        placeholderStyle: ScanThumbnailPlaceholderStyle = .archived
    ) {
        self.imagePath = imagePath
        self.fallbackImageUrl = fallbackImageUrl
        self.maxDimension = maxDimension
        self.placeholderStyle = placeholderStyle
    }

    init(record: LocalScanRecord, maxDimension: Int = 600) {
        let presentation = record.scanThumbnailPresentation
        self.init(
            imagePath: presentation.imagePath,
            fallbackImageUrl: presentation.fallbackImageUrl,
            maxDimension: maxDimension,
            placeholderStyle: presentation.placeholderStyle
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
        .task(id: loadTaskID) {
            await MainActor.run {
                thumbnail = nil
                hasFailedToLoad = false
            }
            await loadThumbnail()
        }
    }

    private var loadTaskID: String {
        "\(imagePath ?? "no_image_path")|\(fallbackImageUrl ?? "no_fallback_url")|\(placeholderStyle.taskKey)"
    }

    @ViewBuilder
    private var loadingView: some View {
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
                subtitle: "Will retry later"
            )
        case .unavailableReference(let mediaKind):
            ScanThumbnailPlaceholderView(
                mediaKind: mediaKind,
                title: "Non-visual scan",
                subtitle: "No reference photo"
            )
        case .archived:
            ArchivedVisualsView()
        }
    }

    private func loadThumbnail() async {
        guard imagePath != nil || fallbackImageUrl != nil else {
            await MainActor.run {
                hasFailedToLoad = false
            }
            return
        }

        let maxAttempts = fallbackImageUrl == nil ? 1 : 3
        var loadedImage: UIImage?

        for attempt in 0..<maxAttempts {
            if Task.isCancelled { return }

            loadedImage = await LocalImageLoader.shared.loadImage(
                fromPath: imagePath,
                fallbackUrl: fallbackImageUrl,
                maxDimension: maxDimension
            )

            if loadedImage != nil {
                break
            }

            guard attempt < maxAttempts - 1 else { continue }
            try? await Task.sleep(for: .milliseconds(350 * (attempt + 1)))
        }

        await MainActor.run {
            if let loadedImage {
                thumbnail = loadedImage
                hasFailedToLoad = false
            } else {
                hasFailedToLoad = true
            }
        }
    }
}

private struct ScanThumbnailPlaceholderView: View {
    let mediaKind: CapturedMediaKind
    let title: String
    let subtitle: String

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
                Text(subtitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
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
