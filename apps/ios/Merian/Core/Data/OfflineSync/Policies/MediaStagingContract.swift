import Foundation

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
