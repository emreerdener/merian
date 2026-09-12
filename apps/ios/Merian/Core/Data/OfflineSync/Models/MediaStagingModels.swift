import Foundation

// MARK: - Media Staging Models

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
            return ScanMediaPayloadPolicy.maxStagedImageBytes
        case .audio:
            return ScanMediaPayloadPolicy.maxInferenceAudioBytes
        case .video:
            return ScanMediaPayloadPolicy.maxSavedVideoBytes
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

enum StagingUploadPurpose: String, Codable, Sendable, Equatable {
    /// Re-stages surviving local media bound to an exact scan so Explore or
    /// Community publication can repair durable media or guarded owner-row drift.
    case scanShareRestore = "scan_share_restore"
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
    let syncGeneration: UUID?
    let objectKey: String?
    /// Auth user that authorized the signed upload. Modern task descriptions
    /// carry this explicitly so a reattached background task can never be
    /// adopted by a replacement account after an Auth transition.
    let ownerUserID: UUID?

    init(
        scanId: String,
        uploadIndex: Int?,
        syncGeneration: UUID?,
        objectKey: String? = nil,
        ownerUserID: UUID? = nil
    ) {
        self.scanId = scanId
        self.uploadIndex = uploadIndex
        self.syncGeneration = syncGeneration
        self.objectKey = objectKey
        self.ownerUserID = ownerUserID
    }
}

struct MediaStagingUploadCompletionState: Sendable, Equatable {
    let generation: UUID?
    var successfulObjectKeys: Set<String>

    init(generation: UUID?, successfulObjectKeys: Set<String> = []) {
        self.generation = generation
        self.successfulObjectKeys = successfulObjectKeys
    }

    mutating func recordSuccess(objectKey: String) {
        successfulObjectKeys.insert(objectKey)
    }

    func matchesExactly(expectedObjectKeys: [String]) -> Bool {
        let expected = Set(expectedObjectKeys)
        return !expected.isEmpty &&
            expected.count == expectedObjectKeys.count &&
            expected == successfulObjectKeys
    }
}

// MARK: - Upload Requests

struct StagingUploadFile: Codable, Sendable, Equatable {
    let fileName: String
    let mediaKind: StagedMediaKind
    let contentType: String
    let sizeBytes: Int
    let clientScanId: String?
    let mediaRole: String?
    let uploadPurpose: StagingUploadPurpose?

    init(
        fileName: String,
        mediaKind: StagedMediaKind,
        contentType: String,
        sizeBytes: Int,
        clientScanId: String? = nil,
        mediaRole: String? = nil,
        uploadPurpose: StagingUploadPurpose? = nil
    ) {
        self.fileName = fileName
        self.mediaKind = mediaKind
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.clientScanId = clientScanId
        self.mediaRole = mediaRole
        self.uploadPurpose = uploadPurpose
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
    /// File size captured immediately before requesting the presigned URL.
    let sizeBytes: Int
}

struct MediaStagingPreparation: Sendable {
    let uploadItems: [ScanUploadItem]
    let uploadFiles: [StagingUploadFile]
    let rejectedScanIds: [String]
}
