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

        if hasStoredVisualThumbnail {
            return ScanThumbnailPresentation(
                imagePath: preferredVisualThumbnailPath,
                fallbackImageUrl: fallbackUrl,
                audioPath: nil,
                placeholderStyle: .archived
            )
        }

        if let audioPath = preferredAudioSpectrogramPath {
            return ScanThumbnailPresentation(
                imagePath: nil,
                fallbackImageUrl: fallbackUrl,
                audioPath: audioPath,
                placeholderStyle: nonVisualPlaceholderStyle(fallbackUrl: fallbackUrl)
            )
        }

        let mediaKind = capturedMediaKindForThumbnail
        if fallbackUrl != nil {
            return ScanThumbnailPresentation(
                imagePath: nil,
                fallbackImageUrl: fallbackUrl,
                audioPath: nil,
                placeholderStyle: .pendingReference(mediaKind)
            )
        }

        if canResolveReferenceThumbnail {
            return ScanThumbnailPresentation(
                imagePath: nil,
                fallbackImageUrl: nil,
                audioPath: nil,
                placeholderStyle: .pendingReference(mediaKind)
            )
        }

        if hasNonVisualOnlyMedia || coverImagePath?.trimmedNonEmpty == nil {
            return ScanThumbnailPresentation(
                imagePath: nil,
                fallbackImageUrl: nil,
                audioPath: nil,
                placeholderStyle: .unavailableReference(mediaKind)
            )
        }

        return ScanThumbnailPresentation(
            imagePath: preferredVisualThumbnailPath,
            fallbackImageUrl: fallbackUrl,
            audioPath: nil,
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

    private var preferredAudioSpectrogramPath: String? {
        guard capturedMediaSummary.hasAudio,
              !capturedMediaSummary.hasImage,
              !capturedMediaSummary.hasDescription,
              let json = capturedMediaJSON else {
            return nil
        }

        return MediaJSONParser.audioPaths(jsonString: json).first?.trimmedNonEmpty
    }

    private var capturedMediaKindForThumbnail: CapturedMediaKind {
        capturedMediaSummary.preferredThumbnailKind ?? .other
    }

    private func nonVisualPlaceholderStyle(fallbackUrl: String?) -> ScanThumbnailPlaceholderStyle {
        let mediaKind = capturedMediaKindForThumbnail
        if fallbackUrl != nil || canResolveReferenceThumbnail {
            return .pendingReference(mediaKind)
        }
        return .unavailableReference(mediaKind)
    }
}

struct ScanThumbnail: View {
    // MARK: - Asset Dependencies
    let imagePath: String?
    let fallbackImageUrl: String?
    let audioPath: String?
    let maxDimension: Int
    let placeholderStyle: ScanThumbnailPlaceholderStyle

    // MARK: - Rendering State
    @State private var thumbnail: UIImage?
    @State private var hasFailedToLoad: Bool = false

    init(
        imagePath: String?,
        fallbackImageUrl: String? = nil,
        audioPath: String? = nil,
        maxDimension: Int = 600,
        placeholderStyle: ScanThumbnailPlaceholderStyle = .archived
    ) {
        self.imagePath = imagePath
        self.fallbackImageUrl = fallbackImageUrl
        self.audioPath = audioPath
        self.maxDimension = maxDimension
        self.placeholderStyle = placeholderStyle
    }

    init(record: LocalScanRecord, maxDimension: Int = 600) {
        let presentation = record.scanThumbnailPresentation
        self.init(
            imagePath: presentation.imagePath,
            fallbackImageUrl: presentation.fallbackImageUrl,
            audioPath: presentation.audioPath,
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
        "\(imagePath ?? "no_image_path")|\(fallbackImageUrl ?? "no_fallback_url")|\(audioPath ?? "no_audio_path")|\(placeholderStyle.taskKey)"
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
        if let audioPath {
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
            guard let resolvedURL = Self.resolveAudioURL(from: audioPath) else {
                return nil
            }

            let columns = await AudioSpectrogramDecoder.decodeColumns(fromFilePath: resolvedURL.path)
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

    private static nonisolated func resolveAudioURL(from audioPath: String) -> URL? {
        if audioPath.starts(with: "file://"), let url = URL(string: audioPath) {
            return url
        }

        if audioPath.starts(with: "/") {
            return URL(fileURLWithPath: audioPath)
        }

        let documentsURL = URL.documentsDirectory.appendingPathComponent(audioPath)
        if FileManager.default.fileExists(atPath: documentsURL.path) {
            return documentsURL
        }

        return FileManager.default.temporaryDirectory.appendingPathComponent(audioPath)
    }

    private static nonisolated func renderThumbnail(
        columns: [SpectrogramColumn],
        maxDimension: Int
    ) -> UIImage? {
        guard !columns.isEmpty else { return nil }

        let dimension = max(64, maxDimension)
        let size = CGSize(width: dimension, height: dimension)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1

        return UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            let context = rendererContext.cgContext
            context.setFillColor(SpectrogramPalette.backgroundUIColor.cgColor)
            context.fill(CGRect(origin: .zero, size: size))

            let columnWidth = size.width / CGFloat(columns.count)
            let binHeight = size.height / CGFloat(SpectrogramActor.outputBinCount)

            for (columnIndex, column) in columns.enumerated() {
                let x = CGFloat(columnIndex) * columnWidth
                for (binIndex, magnitude) in column.magnitudes.enumerated() {
                    let y = size.height - CGFloat(binIndex + 1) * binHeight
                    context.setFillColor(SpectrogramPalette.uiColor(for: magnitude).cgColor)
                    context.fill(CGRect(x: x, y: y, width: columnWidth + 0.5, height: binHeight + 0.5))
                }
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
