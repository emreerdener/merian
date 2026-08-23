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

/// A crash-safe claim for upgrading compressed audio persisted by an older
/// queue build. The row is fenced from upload/replay before this value leaves
/// the database actor.
struct LegacyQueuedAudioRepairCandidate: Sendable, Equatable {
    let scanId: String
    let references: [StoredMediaReference]
    let retainedAudioFileNames: Set<String>
}

struct LegacyQueuedAudioRepairReplacement: Sendable, Equatable {
    let sourceStorage: MediaStorageLocation
    let sourcePath: String
    let replacementFileName: String
}

enum LegacyQueuedAudioRepairState {
    /// Persisted before transcoding starts. Upload/inference claims must ignore
    /// the row until the replacement manifest commits.
    static let inProgressGeneration = -1
    static let completedGeneration = 2
}

struct LegacyQueuedAudioRepairResult: Sendable, Equatable {
    var repairedScanIds = Set<String>()
    var failedScanIds = Set<String>()
    var claimedScanIds = Set<String>()

    var didMutate: Bool {
        !claimedScanIds.isEmpty
    }
}

typealias LegacyQueuedAudioFilePreparer =
    @Sendable (URL, String) async throws -> URL

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

struct InferenceURLSessionTaskIdentity: Sendable, Equatable {
    let scanId: String
    let generation: UUID?
    /// Auth user whose JWT authorized the inference request. `nil` is accepted
    /// only for legacy task parsing and is treated as unknown/fail-closed at an
    /// account transition boundary.
    let ownerUserID: UUID?

    init(
        scanId: String,
        generation: UUID?,
        ownerUserID: UUID? = nil
    ) {
        self.scanId = scanId
        self.generation = generation
        self.ownerUserID = ownerUserID
    }
}

/// Optional guard used by queue deletion paths that originate from inference work.
///
/// The wrapper is itself optional so `nil` can continue to mean "explicit,
/// unguarded deletion", while `InferenceGenerationExpectation(generation: nil)`
/// means "delete only while this scan still has no in-process generation".
struct InferenceGenerationExpectation: Sendable, Equatable {
    let generation: UUID?
}

/// Guard used when queue cleanup originates from a foreground inference attempt.
///
/// Foreground inference begins before recovery media necessarily reaches R2, so it
/// cannot use the background-only `.inferencing` state as its ownership fence. Its
/// generation is instead persisted on the scan-ingestion job in the same transaction
/// that creates the queued scan and compared again before persistence or deletion.
struct ForegroundInferenceGenerationExpectation: Sendable, Equatable {
    let generation: UUID
}

/// Durable ownership supplied to live-result persistence.
struct LiveInferencePersistenceFence: Sendable, Equatable {
    let scanId: String
    let generation: UUID
}

/// Separates a successful save from the valid "not a new discovery" result.
///
/// The previous Boolean return value conflated those states, allowing queue cleanup
/// to continue after persistence was rejected or failed.
struct LiveInferencePersistenceResult: Sendable, Equatable {
    let wasSaved: Bool
    let isNewDiscovery: Bool

    static let notSaved = LiveInferencePersistenceResult(
        wasSaved: false,
        isNewDiscovery: false
    )
}

enum InferenceGenerationMetadataContract {
    static func json(for generation: UUID) -> String {
        #"{"inference_generation":""# +
            generation.uuidString.lowercased() +
            #""}"#
    }

    static func generation(in metadataJSON: String?) -> UUID? {
        guard let value = OfflineScanJobMetadataContract.object(
            from: metadataJSON
        )["inference_generation"] as? String else {
            return nil
        }
        return UUID(uuidString: value)
    }

    static func matches(_ generation: UUID, in metadataJSON: String?) -> Bool {
        self.generation(in: metadataJSON) == generation
    }

    static func setting(
        _ generation: UUID,
        in metadataJSON: String?
    ) -> String {
        var object = OfflineScanJobMetadataContract.object(from: metadataJSON)
        object["inference_generation"] = generation.uuidString.lowercased()
        return OfflineScanJobMetadataContract.json(from: object) ?? json(
            for: generation
        )
    }

    /// Removes only the generation property and preserves funding and any
    /// future metadata fields. Returns nil when no properties remain.
    static func removing(
        _ generation: UUID,
        from metadataJSON: String?
    ) -> String? {
        var object = OfflineScanJobMetadataContract.object(from: metadataJSON)
        guard let value = object["inference_generation"] as? String,
              UUID(uuidString: value) == generation else {
            return metadataJSON
        }
        object.removeValue(forKey: "inference_generation")
        return OfflineScanJobMetadataContract.json(from: object)
    }
}

enum ScanFundingSource: String, Codable, Sendable, Equatable {
    case paidPro = "paid_pro"
    case complimentaryPro = "complimentary_pro"
    case immediateFlash = "immediate_flash"
    case deferredFlash = "deferred_flash"
}

/// Idempotent local admission decision tied to one account and stable scan ID.
struct ScanFundingReservation: Codable, Sendable, Equatable {
    let accountId: UUID
    let scanId: String
    var source: ScanFundingSource
    var blockerScanIds: [String]
    let createdAt: Date

    init(
        accountId: UUID,
        scanId: String,
        source: ScanFundingSource,
        blockerScanIds: [String] = [],
        createdAt: Date = Date()
    ) {
        self.accountId = accountId
        self.scanId = scanId.lowercased()
        self.source = source
        self.blockerScanIds = blockerScanIds.map { $0.lowercased() }
        self.createdAt = createdAt
    }

    var allowsDispatch: Bool { source != .deferredFlash }
    var allowsForegroundInference: Bool { source != .deferredFlash }

    private enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case scanId = "scan_id"
        case source
        case blockerScanIds = "blocker_scan_ids"
        case createdAt = "created_at"
    }
}

enum OfflineScanJobMetadataContract {
    private static let fundingReservationKey = "funding_reservation"
    private static let fundingReleasedKey = "funding_reservation_released"
    private static let backgroundAccountWorkKey = "background_account_work"

    static func object(from metadataJSON: String?) -> [String: Any] {
        guard let metadataJSON,
              let data = metadataJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return [:]
        }
        return dictionary
    }

    static func json(from object: [String: Any]) -> String? {
        guard !object.isEmpty,
              JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.sortedKeys]
              ) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func funding(in metadataJSON: String?) -> ScanFundingReservation? {
        let object = object(from: metadataJSON)
        guard let rawFunding = object[fundingReservationKey],
              JSONSerialization.isValidJSONObject(rawFunding),
              let data = try? JSONSerialization.data(withJSONObject: rawFunding),
              let funding = try? JSONDecoder().decode(
                  ScanFundingReservation.self,
                  from: data
              ),
              !funding.scanId.isEmpty else {
            return nil
        }
        return funding
    }

    static func settingFunding(
        _ funding: ScanFundingReservation,
        in metadataJSON: String?
    ) -> String? {
        var object = object(from: metadataJSON)
        guard let data = try? JSONEncoder().encode(funding),
              let rawFunding = try? JSONSerialization.jsonObject(with: data) else {
            return metadataJSON
        }
        object[fundingReservationKey] = rawFunding
        object.removeValue(forKey: fundingReleasedKey)
        return json(from: object)
    }

    static func fundingWasReleased(in metadataJSON: String?) -> Bool {
        object(from: metadataJSON)[fundingReleasedKey] as? Bool == true
    }

    /// Persists proof that no provider dispatch occurred. The marker prevents a
    /// pre-protocol-3 job with no funding payload from being restored as an
    /// unknown complimentary blocker after relaunch.
    static func markingFundingReleased(in metadataJSON: String?) -> String? {
        var object = object(from: metadataJSON)
        object.removeValue(forKey: fundingReservationKey)
        object[fundingReleasedKey] = true
        return json(from: object)
    }

    static func backgroundAccountWork(
        in metadataJSON: String?
    ) -> BackgroundAccountWorkOwnership? {
        let object = object(from: metadataJSON)
        guard let rawValue = object[backgroundAccountWorkKey],
              JSONSerialization.isValidJSONObject(rawValue),
              let data = try? JSONSerialization.data(withJSONObject: rawValue)
        else {
            return nil
        }
        return try? JSONDecoder().decode(
            BackgroundAccountWorkOwnership.self,
            from: data
        )
    }

    static func settingBackgroundAccountWork(
        _ ownership: BackgroundAccountWorkOwnership,
        in metadataJSON: String?
    ) -> String? {
        var object = object(from: metadataJSON)
        guard let data = try? JSONEncoder().encode(ownership),
              let rawValue = try? JSONSerialization.jsonObject(with: data)
        else {
            return metadataJSON
        }
        object[backgroundAccountWorkKey] = rawValue
        return json(from: object)
    }

    static func clearingBackgroundAccountWork(
        in metadataJSON: String?
    ) -> String? {
        var object = object(from: metadataJSON)
        object.removeValue(forKey: backgroundAccountWorkKey)
        return json(from: object)
    }

    static func json(
        generation: UUID?,
        funding: ScanFundingReservation
    ) -> String? {
        var metadata = settingFunding(funding, in: nil)
        if let generation {
            metadata = InferenceGenerationMetadataContract.setting(
                generation,
                in: metadata
            )
        }
        return metadata
    }
}

enum BackgroundAccountWorkPhase: String, Codable, Sendable, Equatable {
    case upload
    case inference
}

/// Durable account/generation owner for a background URLSession operation.
///
/// URLSession tasks can outlive both the creating process and its Auth
/// session. This record is the local write fence: a callback must match it and
/// the queue state before it may stage media, persist inference, or delete
/// queued work.
struct BackgroundAccountWorkOwnership: Codable, Sendable, Equatable {
    let ownerUserID: UUID
    let generation: UUID
    let phase: BackgroundAccountWorkPhase

    private enum CodingKeys: String, CodingKey {
        case ownerUserID = "owner_user_id"
        case generation
        case phase
    }
}

struct BackgroundAccountWorkCandidate: Sendable, Equatable {
    let scanId: String
    let ownership: BackgroundAccountWorkOwnership
}

enum InferenceURLSessionTaskContract {
    private static let currentPrefix = "inference_v3"
    private static let generationOnlyPrefix = "inference_v2"
    private static let legacyPrefix = "inference_"

    static func taskDescription(
        scanId: String,
        generation: UUID,
        ownerUserID: UUID
    ) -> String {
        "\(currentPrefix)|\(ownerUserID.uuidString.lowercased())|\(generation.uuidString.lowercased())|\(scanId)"
    }

    static func parse(_ description: String?) -> InferenceURLSessionTaskIdentity? {
        guard let description else { return nil }

        if description.hasPrefix("\(currentPrefix)|") {
            let parts = description.split(
                separator: "|",
                maxSplits: 3,
                omittingEmptySubsequences: false
            )
            guard parts.count == 4,
                  String(parts[0]) == currentPrefix,
                  let ownerUserID = UUID(uuidString: String(parts[1])),
                  let generation = UUID(uuidString: String(parts[2])),
                  !parts[3].isEmpty else {
                return nil
            }
            return InferenceURLSessionTaskIdentity(
                scanId: String(parts[3]),
                generation: generation,
                ownerUserID: ownerUserID
            )
        }

        if description.hasPrefix("\(generationOnlyPrefix)|") {
            let parts = description.split(
                separator: "|",
                maxSplits: 2,
                omittingEmptySubsequences: false
            )
            guard parts.count == 3,
                  String(parts[0]) == generationOnlyPrefix,
                  let generation = UUID(uuidString: String(parts[1])),
                  !parts[2].isEmpty else {
                return nil
            }
            return InferenceURLSessionTaskIdentity(
                scanId: String(parts[2]),
                generation: generation,
                ownerUserID: nil
            )
        }

        guard description.hasPrefix(legacyPrefix) else { return nil }
        let scanId = String(description.dropFirst(legacyPrefix.count))
        guard !scanId.isEmpty else { return nil }
        return InferenceURLSessionTaskIdentity(
            scanId: scanId,
            generation: nil,
            ownerUserID: nil
        )
    }
}

/// Main-actor task registry with compare-before-clear ownership.
///
/// Cancelling a Swift task is cooperative. A replaced task may therefore resume
/// after its successor has occupied the same key. Every task receives a unique
/// token and must still own that token before clearing the slot or performing
/// delayed work.
@MainActor
final class GenerationTaskRegistry<Key: Hashable> {
    private struct Entry {
        let token: UUID
        let ownerGeneration: UUID?
        let task: Task<Void, Never>
    }

    private var entries: [Key: Entry] = [:]

    var keys: Set<Key> {
        Set(entries.keys)
    }

    var count: Int {
        entries.count
    }

    @discardableResult
    func replace(
        for key: Key,
        ownerGeneration: UUID?,
        makeTask: (UUID) -> Task<Void, Never>
    ) -> UUID {
        let previous = entries.removeValue(forKey: key)
        previous?.task.cancel()

        let token = UUID()
        let task = makeTask(token)
        entries[key] = Entry(
            token: token,
            ownerGeneration: ownerGeneration,
            task: task
        )
        return token
    }

    func isCurrent(
        _ key: Key,
        token: UUID,
        ownerGeneration: UUID? = nil
    ) -> Bool {
        guard let entry = entries[key], entry.token == token else { return false }
        return ownerGeneration == nil || entry.ownerGeneration == ownerGeneration
    }

    func isOwned(_ key: Key, by ownerGeneration: UUID) -> Bool {
        entries[key]?.ownerGeneration == ownerGeneration
    }

    @discardableResult
    func clearIfCurrent(
        _ key: Key,
        token: UUID,
        cancel: Bool = false
    ) -> Bool {
        guard let entry = entries[key], entry.token == token else { return false }
        entries[key] = nil
        if cancel {
            entry.task.cancel()
        }
        return true
    }

    func cancel(_ key: Key) {
        let entry = entries.removeValue(forKey: key)
        entry?.task.cancel()
    }

    func cancel(_ key: Key, ifOwnedBy ownerGeneration: UUID) {
        guard entries[key]?.ownerGeneration == ownerGeneration else { return }
        cancel(key)
    }

    func cancelAll() {
        let tasks = entries.values.map(\.task)
        entries.removeAll()
        tasks.forEach { $0.cancel() }
    }
}

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

enum MediaStagingContract {
    static let maxUploadItemsPerRequest = MerianConfig.mediaStagingMaxFilesPerRequest
    private static let uploadTaskPrefix = "upload"
    private static let accountOwnedUploadTaskPrefix = "upload_v2"

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

    static func preferredOwnerId(
        sessionUserId: String?,
        hydratedUserId: String?,
        deviceId: String
    ) -> String {
        (sessionUserId ?? hydratedUserId ?? deviceId).lowercased()
    }

    static func isCanonicalObjectKey(_ objectKey: String, fileName: String) -> Bool {
        let parts = objectKey.split(separator: "/", omittingEmptySubsequences: false)
        let owner = parts.count == 3 ? String(parts[1]) : ""
        guard parts.count == 3,
              parts[0] == "staging",
              let ownerId = UUID(uuidString: owner),
              ownerId.uuidString.lowercased() == owner,
              sanitizedFileName(fileName) == fileName,
              parts[2] == Substring(fileName) else {
            return false
        }
        return true
    }

    static func objectKey(fromPresignedURLPath path: String?) -> String? {
        guard let path else { return nil }
        let decodedPath = path.removingPercentEncoding ?? path
        let parts = decodedPath.split(separator: "/")
        guard let stagingIndex = parts.lastIndex(of: "staging"),
              parts.count - stagingIndex == 3 else {
            return nil
        }
        let objectKey = parts[stagingIndex...].joined(separator: "/")
        let fileName = String(parts[stagingIndex + 2])
        return isCanonicalObjectKey(objectKey, fileName: fileName)
            ? objectKey
            : nil
    }

    static func ownerId(fromObjectKey objectKey: String) -> String? {
        let parts = objectKey.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3,
              isCanonicalObjectKey(objectKey, fileName: String(parts[2])) else {
            return nil
        }
        return String(parts[1])
    }

    static func presignedUploadManifestIsValid(
        uploadItems: [ScanUploadItem],
        presignedURLs: [PreSignedURL]
    ) -> Bool {
        guard !uploadItems.isEmpty,
              uploadItems.count == presignedURLs.count else {
            return false
        }

        var owners = Set<String>()
        var uploadOrigins = Set<String>()
        var objectKeys = Set<String>()
        var fileNames = Set<String>()
        for (item, presignedURL) in zip(uploadItems, presignedURLs) {
            guard presignedURL.fileName == item.fileName,
                  presignedURL.objectKey == item.objectKey,
                  isCanonicalObjectKey(
                    presignedURL.objectKey,
                    fileName: item.fileName
                  ),
                  let owner = ownerId(fromObjectKey: presignedURL.objectKey),
                  let remoteURL = URL(string: presignedURL.signedUrl),
                  remoteURL.scheme?.lowercased() == "https",
                  let host = remoteURL.host?.lowercased(),
                  !host.isEmpty,
                  remoteURL.user == nil,
                  remoteURL.password == nil,
                  remoteURL.fragment == nil,
                  presignedURL.requiredHeaders.count == 2,
                  presignedURL.requiredHeaders["Content-Type"]
                    == item.contentType,
                  presignedURL.requiredHeaders["Content-Length"]
                    == String(item.sizeBytes),
                  signedHeaders(from: remoteURL)
                    == "content-length;content-type;host",
                  objectKey(fromPresignedURLPath: remoteURL.path)
                    == presignedURL.objectKey,
                  objectKeys.insert(presignedURL.objectKey).inserted,
                  fileNames.insert(presignedURL.fileName).inserted else {
                return false
            }
            owners.insert(owner)
            uploadOrigins.insert(
                "https://\(host):\(remoteURL.port ?? 443)"
            )
        }
        return owners.count == 1 && uploadOrigins.count == 1
    }

    static func signedHeaders(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: {
                $0.name.caseInsensitiveCompare("X-Amz-SignedHeaders")
                    == .orderedSame
            })?
            .value
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
                objectKey: objectKey(userId: userId, fileName: fileName),
                sizeBytes: fileSizeBytesIfPresent(
                    at: documentsDirectory.appendingPathComponent(localPath)
                )
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

        var fileNames = Set<String>()
        var objectKeys = Set<String>()
        var totalImageBytes = 0
        var imageItemCount = 0
        var audioItemCount = 0
        var videoItemCount = 0
        for item in items {
            guard fileNames.insert(item.fileName).inserted,
                  objectKeys.insert(item.objectKey).inserted else {
                throw MerianError.invalidResponse
            }
            let size = item.sizeBytes
            guard size > 0,
                  size <= item.mediaKind.maxStagedBytes else {
                throw MerianError.payloadTooLarge
            }

            if item.mediaKind == .image {
                imageItemCount += 1
                guard imageItemCount <= MerianConfig.mediaStagingMaxImageFilesPerRequest else {
                    throw MerianError.payloadTooLarge
                }
                totalImageBytes += size
                guard totalImageBytes <= MerianConfig.stagedImagePayloadMaxBytes else {
                    throw MerianError.payloadTooLarge
                }
            } else if item.mediaKind == .audio {
                audioItemCount += 1
                guard audioItemCount <= MerianConfig.mediaStagingMaxAudioFilesPerRequest else {
                    throw MerianError.payloadTooLarge
                }
                guard item.contentType == "audio/wav",
                      item.fileURL.pathExtension.lowercased() == "wav",
                      InferenceAudioPreparer.isEdgeCompatibleWAV(
                          at: item.fileURL
                      ) else {
                    throw MerianError.invalidResponse
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
        items.map { item in
            StagingUploadFile(
                fileName: item.fileName,
                mediaKind: item.mediaKind,
                contentType: item.contentType,
                sizeBytes: item.sizeBytes,
                clientScanId: item.scanId,
                mediaRole: item.mediaKind.defaultScanMediaRole
            )
        }
    }

    static func uploadTaskDescription(
        scanId: String,
        uploadIndex: Int,
        syncGeneration: UUID? = nil,
        objectKey: String? = nil,
        ownerUserID: UUID? = nil
    ) -> String {
        if let syncGeneration, let objectKey, let ownerUserID {
            return "\(accountOwnedUploadTaskPrefix)|\(ownerUserID.uuidString.lowercased())|\(scanId)|\(uploadIndex)|\(syncGeneration.uuidString.lowercased())|\(objectKey)"
        }
        if let syncGeneration {
            let prefix =
                "\(uploadTaskPrefix)|\(scanId)|\(uploadIndex)|\(syncGeneration.uuidString.lowercased())"
            if let objectKey {
                return "\(prefix)|\(objectKey)"
            }
            return prefix
        }
        return "\(uploadTaskPrefix)|\(scanId)|\(uploadIndex)"
    }

    static func parseUploadTaskDescription(_ description: String?) -> MediaStagingUploadTaskIdentity? {
        guard let description, !description.hasPrefix("inference_") else { return nil }

        let parts = description.split(separator: "|", omittingEmptySubsequences: false)
        if parts.count == 6,
           String(parts[0]) == accountOwnedUploadTaskPrefix,
           let ownerUserID = UUID(uuidString: String(parts[1])),
           let uploadIndex = Int(parts[3]),
           let syncGeneration = UUID(uuidString: String(parts[4])) {
            let objectKey = String(parts[5])
            guard ownerId(fromObjectKey: objectKey)?.caseInsensitiveCompare(
                ownerUserID.uuidString
            ) == .orderedSame else {
                return nil
            }
            return MediaStagingUploadTaskIdentity(
                scanId: String(parts[2]),
                uploadIndex: uploadIndex,
                syncGeneration: syncGeneration,
                objectKey: objectKey,
                ownerUserID: ownerUserID
            )
        }
        if parts.count == 3 || parts.count == 4 || parts.count == 5,
           String(parts[0]) == uploadTaskPrefix {
            let syncGeneration = parts.count >= 4
                ? UUID(uuidString: String(parts[3]))
                : nil
            if parts.count >= 4, syncGeneration == nil {
                return nil
            }
            let objectKey = parts.count == 5 ? String(parts[4]) : nil
            if let objectKey,
               ownerId(fromObjectKey: objectKey) == nil {
                return nil
            }
            return MediaStagingUploadTaskIdentity(
                scanId: String(parts[1]),
                uploadIndex: Int(parts[2]),
                syncGeneration: syncGeneration,
                objectKey: objectKey,
                ownerUserID: objectKey
                    .flatMap { ownerId(fromObjectKey: $0) }
                    .flatMap { UUID(uuidString: $0) }
            )
        }

        let legacyParts = description.components(separatedBy: "_")
        guard let legacyScanId = legacyParts.first, !legacyScanId.isEmpty else { return nil }
        return MediaStagingUploadTaskIdentity(
            scanId: legacyScanId,
            uploadIndex: legacyParts.dropFirst().first.flatMap(Int.init),
            syncGeneration: nil,
            ownerUserID: nil
        )
    }

    static func uploadTaskDescription(_ description: String?, belongsTo scanId: String) -> Bool {
        guard let identity = parseUploadTaskDescription(description) else { return false }
        return identity.scanId == scanId
    }

    static func fileSizeBytes(at url: URL) throws -> Int {
        try fileSize(at: url)
    }

    static func fileSizeMatchesSigningSnapshot(_ item: ScanUploadItem) -> Bool {
        (try? fileSize(at: item.fileURL)) == item.sizeBytes
    }

    private static func fileSizeBytesIfPresent(at url: URL) -> Int {
        (try? fileSize(at: url)) ?? 0
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
    /// File size captured immediately before requesting the presigned URL.
    let sizeBytes: Int
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
    /// Durable live-Capture preference carried through foreground and background completion.
    let preferredGoal: FieldTripPreferredGoal?

    var capturedMediaSnapshot: CapturedMediaSnapshot {
        CapturedMediaSnapshot(items: capturedMediaItems)
    }

    var submissionMediaProjection: CaptureSubmissionMediaProjection {
        capturedMediaSnapshot.submissionMediaProjection
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

    /// Audio inference paths in the exact same order as `audioMediaItems`.
    ///
    /// This order must come from one shared projection. Grouping standalone audio
    /// ahead of video-extracted audio can make the Edge Function promote and delete
    /// the opposite clips when the mixed-media timeline is interleaved.
    var audioFilePaths: [String]? {
        let paths = submissionMediaProjection.audioFilePaths
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
        let items = submissionMediaProjection.audioMediaItems
        return items.isEmpty ? nil : items
    }

    var ownerMediaTimeline: [IdentifyOwnerMediaTimelineItem]? {
        let projection = submissionMediaProjection
        let timeline = projection.ownerMediaTimeline
        guard !timeline.isEmpty else { return nil }

        // Persisted standalone-audio identities can be sparse after a partial legacy
        // repair. Preserve those descriptors, but do not claim a new authoritative
        // timeline unless the durable source identities are complete zero-based ordinals.
        let standaloneAudioSourceIndexes = projection.audioMediaItems.compactMap { item in
            item.kind == .audio ? item.sourceIndex : nil
        }
        guard standaloneAudioSourceIndexes.sorted()
                == Array(0..<standaloneAudioSourceIndexes.count) else {
            return nil
        }

        let ownerImageIndexes = timeline.compactMap { item in
            item.kind == .image ? item.sourceIndex : nil
        }
        let ownerVideoIndexes = timeline.compactMap { item in
            item.kind == .video ? item.clipIndex : nil
        }
        guard !ownerImageIndexes.isEmpty || !ownerVideoIndexes.isEmpty else {
            return timeline
        }

        // Older queued visual records predate persisted visual descriptors. Sending a
        // reconstructed timeline for them would turn a safe legacy replay into a strict
        // validation failure, so only opt into the new contract when every visual input
        // and owner-visible source can be proven locally.
        guard let visualMediaItems,
              visualMediaItems.count == localImagePaths.count,
              ownerImageIndexes.sorted() == Array(0..<ownerImageIndexes.count),
              ownerVideoIndexes.sorted() == Array(0..<ownerVideoIndexes.count),
              ownerVideoIndexes.count == (videoFilePaths?.count ?? 0) else {
            return nil
        }
        let visualImageIndexes = visualMediaItems.compactMap { item in
            item.kind == .image ? item.sourceIndex : nil
        }
        let videoFrameClipIndexes = visualMediaItems.compactMap { item in
            item.kind == .videoFrame ? item.clipIndex : nil
        }
        let ownerVideoIndexSet = Set(ownerVideoIndexes)
        guard visualImageIndexes.sorted() == ownerImageIndexes.sorted(),
              videoFrameClipIndexes.allSatisfy(ownerVideoIndexSet.contains),
              ownerVideoIndexSet.isSubset(of: Set(videoFrameClipIndexes)) else {
            return nil
        }
        return timeline
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
