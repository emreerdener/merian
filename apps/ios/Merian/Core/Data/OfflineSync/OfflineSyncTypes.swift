import Foundation
import SwiftData

// MARK: - Offline Sync Data Transfer Objects
//
// Sendable value types shared across the offline sync pipeline:
//   OfflineQueueManager (+Sync, +URLSession, +Queue)
//   BackgroundDatabaseActor
//   InferenceEngine (read-only, result hydration)
//
// Keeping these in one file prevents them from being buried inside actor or
// extension files where unrelated readers wouldn't think to look.

// MARK: - Pending Scan Payload

/// Minimal Sendable snapshot of a pending queued scan, safe to pass across actor boundaries.
///
/// Captured by `BackgroundDatabaseActor.fetchPendingScans` so the caller can build upload
/// items without touching the main-actor-bound `ModelContext` again.
struct PendingScanPayload: Sendable {
    let id: String
    let localImagePaths: [String]
    let localAudioPaths: [String]
    let localVideoPaths: [String]

    var localUploadPaths: [String] {
        localImagePaths + localAudioPaths + localVideoPaths
    }
}

// MARK: - Media Staging Contract

enum StagedMediaKind: String, Codable, Sendable, Equatable {
    case image
    case audio
    case video

    func contentType(for path: String) -> String {
        switch self {
        case .image:
            return "image/webp"
        case .audio:
            return path.lowercased().hasSuffix(".m4a") ? "audio/mp4" : "audio/wav"
        case .video:
            return "video/mp4"
        }
    }

    var maxStagedBytes: Int {
        switch self {
        case .image:
            return MerianConfig.stagedImagePayloadMaxBytes
        case .audio:
            return MerianConfig.audioPayloadMaxBytes
        case .video:
            return MerianConfig.videoPayloadMaxBytes
        }
    }

    var defaultScanMediaRole: String {
        switch self {
        case .image:
            return "display"
        case .audio:
            return "audio"
        case .video:
            return "playback"
        }
    }
}

struct StagedMediaObjectKeys: Sendable, Equatable {
    let imageR2ObjectKeys: [String]
    let audioR2ObjectKeys: [String]
    let videoR2ObjectKeys: [String]

    var all: [String] {
        imageR2ObjectKeys + audioR2ObjectKeys + videoR2ObjectKeys
    }
}

struct MediaStagingUploadTaskIdentity: Sendable, Equatable {
    let scanId: String
    let uploadIndex: Int?
}

struct StagingUploadFile: Codable, Sendable, Equatable {
    let fileName: String
    let mediaKind: StagedMediaKind
    let contentType: String
    let sizeBytes: Int?
    let clientScanId: String?
    let mediaRole: String?

    init(
        fileName: String,
        mediaKind: StagedMediaKind,
        contentType: String,
        sizeBytes: Int?,
        clientScanId: String? = nil,
        mediaRole: String? = nil
    ) {
        self.fileName = fileName
        self.mediaKind = mediaKind
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.clientScanId = clientScanId
        self.mediaRole = mediaRole
    }
}

enum MediaStagingContract {
    static let maxUploadItemsPerRequest = MerianConfig.mediaStagingMaxFilesPerRequest
    private static let uploadTaskPrefix = "upload"

    static func sanitizedFileName(_ rawFileName: String) -> String {
        var sanitized = ""
        sanitized.reserveCapacity(rawFileName.count)

        for scalar in rawFileName.unicodeScalars {
            switch scalar.value {
            case 45, 46, 48...57, 65...90, 95, 97...122:
                sanitized.unicodeScalars.append(scalar)
            default:
                sanitized.append("_")
            }
        }

        return sanitized.isEmpty ? "upload" : sanitized
    }

    static func stagingFileName(scanId: String, localPath: String) -> String {
        sanitizedFileName("\(scanId)_\(localPath)")
    }

    static func objectKey(userId: String, fileName: String) -> String {
        "staging/\(sanitizedFileName(userId.lowercased()))/\(fileName)"
    }

    static func uploadItems(
        for scan: PendingScanPayload,
        userId: String,
        documentsDirectory: URL = .documentsDirectory
    ) -> [ScanUploadItem] {
        var items: [ScanUploadItem] = []
        items.reserveCapacity(scan.localUploadPaths.count)

        func append(kind: StagedMediaKind, localPath: String) {
            let fileName = stagingFileName(scanId: scan.id, localPath: localPath)
            items.append(ScanUploadItem(
                scanId: scan.id,
                uploadIndex: items.count,
                mediaKind: kind,
                localPath: localPath,
                fileName: fileName,
                fileURL: documentsDirectory.appendingPathComponent(localPath),
                contentType: kind.contentType(for: localPath),
                objectKey: objectKey(userId: userId, fileName: fileName)
            ))
        }

        for path in scan.localImagePaths {
            append(kind: .image, localPath: path)
        }
        for path in scan.localAudioPaths {
            append(kind: .audio, localPath: path)
        }
        for path in scan.localVideoPaths {
            append(kind: .video, localPath: path)
        }

        return items
    }

    static func objectKeys(for scan: PendingScanPayload, userId: String) -> StagedMediaObjectKeys {
        let items = uploadItems(for: scan, userId: userId)
        return StagedMediaObjectKeys(
            imageR2ObjectKeys: items.filter { $0.mediaKind == .image }.map(\.objectKey),
            audioR2ObjectKeys: items.filter { $0.mediaKind == .audio }.map(\.objectKey),
            videoR2ObjectKeys: items.filter { $0.mediaKind == .video }.map(\.objectKey)
        )
    }

    static func splitObjectKeys(
        _ objectKeys: [String],
        scanId: String,
        userId: String? = nil,
        localImagePaths: [String],
        localAudioPaths: [String],
        localVideoPaths: [String] = []
    ) -> StagedMediaObjectKeys {
        let keysToSplit: [String]
        if objectKeys.isEmpty, let userId {
            let payload = PendingScanPayload(
                id: scanId,
                localImagePaths: localImagePaths,
                localAudioPaths: localAudioPaths,
                localVideoPaths: localVideoPaths
            )
            keysToSplit = self.objectKeys(for: payload, userId: userId).all
        } else {
            keysToSplit = objectKeys
        }

        let audioFileNames = Set(localAudioPaths.map { stagingFileName(scanId: scanId, localPath: $0) })
        let videoFileNames = Set(localVideoPaths.map { stagingFileName(scanId: scanId, localPath: $0) })
        let audioKeys = keysToSplit.filter { key in
            let fileName = key.split(separator: "/").last.map(String.init) ?? key
            return audioFileNames.contains(fileName) || localAudioPaths.contains { key.hasSuffix("_\($0)") }
        }
        let audioKeySet = Set(audioKeys)
        let videoKeys = keysToSplit.filter { key in
            let fileName = key.split(separator: "/").last.map(String.init) ?? key
            return videoFileNames.contains(fileName) || localVideoPaths.contains { key.hasSuffix("_\($0)") }
        }
        let nonImageKeySet = audioKeySet.union(videoKeys)
        let imageKeys = keysToSplit.filter { !nonImageKeySet.contains($0) }

        return StagedMediaObjectKeys(
            imageR2ObjectKeys: imageKeys,
            audioR2ObjectKeys: audioKeys,
            videoR2ObjectKeys: videoKeys
        )
    }

    static func validateUploadBudget(_ items: [ScanUploadItem]) throws {
        guard items.count <= maxUploadItemsPerRequest else {
            throw MerianError.payloadTooLarge
        }

        var totalImageBytes = 0
        var audioItemCount = 0
        var videoItemCount = 0
        for item in items {
            let size = try fileSize(at: item.fileURL)
            guard size <= item.mediaKind.maxStagedBytes else {
                throw MerianError.payloadTooLarge
            }

            if item.mediaKind == .image {
                totalImageBytes += size
                guard totalImageBytes <= MerianConfig.stagedImagePayloadMaxBytes else {
                    throw MerianError.payloadTooLarge
                }
            } else if item.mediaKind == .audio {
                audioItemCount += 1
                guard audioItemCount <= MerianConfig.mediaStagingMaxAudioFilesPerRequest else {
                    throw MerianError.payloadTooLarge
                }
            } else {
                videoItemCount += 1
                guard videoItemCount <= MerianConfig.mediaStagingMaxVideoFilesPerRequest else {
                    throw MerianError.payloadTooLarge
                }
            }
        }
    }

    static func uploadFiles(for items: [ScanUploadItem]) throws -> [StagingUploadFile] {
        try items.map { item in
            StagingUploadFile(
                fileName: item.fileName,
                mediaKind: item.mediaKind,
                contentType: item.contentType,
                sizeBytes: try fileSizeBytes(at: item.fileURL),
                clientScanId: item.scanId,
                mediaRole: item.mediaKind.defaultScanMediaRole
            )
        }
    }

    static func uploadTaskDescription(scanId: String, uploadIndex: Int) -> String {
        "\(uploadTaskPrefix)|\(scanId)|\(uploadIndex)"
    }

    static func parseUploadTaskDescription(_ description: String?) -> MediaStagingUploadTaskIdentity? {
        guard let description, !description.hasPrefix("inference_") else { return nil }

        let parts = description.split(separator: "|", omittingEmptySubsequences: false)
        if parts.count == 3, String(parts[0]) == uploadTaskPrefix {
            return MediaStagingUploadTaskIdentity(
                scanId: String(parts[1]),
                uploadIndex: Int(parts[2])
            )
        }

        let legacyParts = description.components(separatedBy: "_")
        guard let legacyScanId = legacyParts.first, !legacyScanId.isEmpty else { return nil }
        return MediaStagingUploadTaskIdentity(
            scanId: legacyScanId,
            uploadIndex: legacyParts.dropFirst().first.flatMap(Int.init)
        )
    }

    static func uploadTaskDescription(_ description: String?, belongsTo scanId: String) -> Bool {
        guard let identity = parseUploadTaskDescription(description) else { return false }
        return identity.scanId == scanId
    }

    static func fileSizeBytes(at url: URL) throws -> Int {
        try fileSize(at: url)
    }

    private static func fileSize(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes[.size] as? NSNumber {
            return size.intValue
        }
        throw MerianError.invalidResponse
    }
}

// MARK: - Scan Upload Item

/// Flat representation of a single local media file ready for a presigned R2 PUT.
struct ScanUploadItem: Sendable {
    let scanId: String
    /// Per-scan slot index (0…N-1). Distinct from the flat batch position across all scans.
    let uploadIndex: Int
    let mediaKind: StagedMediaKind
    let localPath: String
    let fileName: String
    let fileURL: URL
    let contentType: String
    let objectKey: String
}

struct MediaStagingPreparation: Sendable {
    let uploadItems: [ScanUploadItem]
    let uploadFiles: [StagingUploadFile]
    let rejectedScanIds: [String]
}

// MARK: - Extracted Scan Data

/// Sendable snapshot of `OfflineQueuedScan` metadata captured on the main actor.
///
/// Passed across the actor boundary into `dispatchInferenceDownloadTask` so that
/// background inference can proceed without touching the main-actor-bound `ModelContext`.
struct ExtractedScanData: Sendable {
    /// Environmental and capture telemetry for the scan, used as Gemini inference context.
    let telemetry: CaptureTelemetry
    /// Confirmed R2 object keys stored at upload time.
    /// Non-empty on the offline queue path; empty on the live inference path.
    let r2Keys: [String]
    /// The model container, used to create a new `BackgroundDatabaseActor` on the inference thread.
    let container: ModelContainer
    let originalTimestamp: Date
    /// Canonical persisted media timeline from the queued scan, preserving mixed-media order.
    let capturedMediaItems: [SerializedMediaItem]
    /// Documents-relative images used for inference replay. New video rows keep sampled frames here
    /// while `capturedMediaItems` keeps only the display/share timeline.
    let inferenceImagePaths: [String]?
    /// Encoded `[IdentifyVisualMediaItem]` aligned to `inferenceImagePaths`.
    let visualMediaItemsJSON: String?

    var capturedMediaSnapshot: CapturedMediaSnapshot {
        CapturedMediaSnapshot(items: capturedMediaItems)
    }

    /// Filenames of local inference images relative to the Documents directory.
    var localImagePaths: [String] {
        if let inferenceImagePaths, !inferenceImagePaths.isEmpty {
            return inferenceImagePaths
        }
        return capturedMediaSnapshot.thumbnailImagePaths
    }

    var localUploadPaths: [String] {
        localImagePaths + (audioFilePaths ?? []) + (videoFilePaths ?? [])
    }

    /// Pre-serialized `ObservationContext` text for combined image+description scans.
    var description: String? {
        capturedMediaSnapshot.descriptionText
    }

    /// Raw `ObservationContext` JSON string forwarded to the edge function as `observation_context`
    /// and persisted in the `scans` table. Separate from `description` (plain-text for Gemini).
    /// `nil` for image-only scans.
    var observationContextsJSON: [String]? {
        capturedMediaSnapshot.observationContextsJSON
    }

    /// Filename of the recorded WAV relative to the Documents directory, for audio-only scans.
    /// `nil` for image and describe scans.
    var audioFilePaths: [String]? {
        let paths = capturedMediaSnapshot.audioPaths
        return paths.isEmpty ? nil : paths
    }

    var videoFilePaths: [String]? {
        let paths = capturedMediaSnapshot.videoPaths
        return paths.isEmpty ? nil : paths
    }

    var visualMediaItems: [IdentifyVisualMediaItem]? {
        guard let visualMediaItemsJSON,
              let data = visualMediaItemsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([IdentifyVisualMediaItem].self, from: data),
              !decoded.isEmpty else {
            return nil
        }
        return decoded
    }

    var audioMediaItems: [IdentifyAudioMediaItem]? {
        var items: [IdentifyAudioMediaItem] = []
        var standaloneAudioIndex = 0
        var videoClipIndex = 0

        for item in capturedMediaItems {
            switch item {
            case .audio:
                items.append(.audio(sourceIndex: standaloneAudioIndex))
                standaloneAudioIndex += 1
            case .video(let reference):
                if reference.audio != nil {
                    items.append(.videoAudio(clipIndex: videoClipIndex))
                }
                videoClipIndex += 1
            case .image, .description:
                continue
            }
        }

        return items.isEmpty ? nil : items
    }

    var capturedMediaJSON: String? {
        capturedMediaSnapshot.jsonString
    }
}

// MARK: - Offline Scan Processing Result

/// Result returned by `BackgroundDatabaseActor.processAndCleanupOfflineScan`.
struct OfflineScanProcessingResult {
    let resolvedSpeciesName: String?
    let isNewDiscovery: Bool
    let finalScanId: String?
    /// The fully-parsed result, present when inference succeeded (confidenceScore > 0).
    /// Passed back to the main actor so the live InferenceEngine can be hydrated directly
    /// when the background path races ahead of the suspended live inference task.
    let speciesData: SpeciesData?
    /// True when the background context's save committed (inserting the `LocalScanRecord` on
    /// success, or a no-op save on a confidence==0 failure). When true, the caller must delete
    /// the `OfflineQueuedScan` through the main actor's queue path.
    ///
    /// The background context intentionally does NOT delete the `OfflineQueuedScan`. Delegating
    /// the deletion to the main actor guarantees the main `ModelContext` always has a real
    /// pending change when it saves — the only reliable way to trigger `@Query` re-evaluation
    /// in a presented sheet (SwiftData platform limitation: background context saves do not
    /// reliably propagate to `@Query` in open sheets via remote change notifications).
    let wasCleaned: Bool
}
