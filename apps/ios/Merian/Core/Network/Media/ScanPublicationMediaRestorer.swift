import Foundation

/// Immutable local media required to plan a publication repair.
struct ScanPublicationMediaSource {
    let scanId: String
    let imagePaths: [String]
    let videoPaths: [String]
    let audioPaths: [String]
    let coverImagePath: String?
    let fallbackImageData: Data?
}

struct ScanPublicationRestoredObjectKeys {
    let imageObjectKeys: [String]
    let videoObjectKeys: [String]
    let audioObjectKeys: [String]

    var isEmpty: Bool {
        imageObjectKeys.isEmpty && videoObjectKeys.isEmpty && audioObjectKeys.isEmpty
    }
}

struct PreparedScanPublicationMediaRestore {
    fileprivate let source: ScanPublicationMediaSource
    fileprivate let plan: ScanPublicationMediaRestorePlan

    var isEmpty: Bool { plan.isEmpty }
}

private struct ScanPublicationMediaRestorePlan {
    let imagePaths: [String]
    let videoPaths: [String]
    let audioPaths: [String]
    let usesFallbackImageData: Bool

    var isEmpty: Bool {
        imagePaths.isEmpty
            && videoPaths.isEmpty
            && audioPaths.isEmpty
            && !usesFallbackImageData
    }
}

/// Plans and uploads only the surviving local media used by scan publication
/// recovery. All filesystem resolution and upload mechanics remain contained
/// behind the immutable prepared plan.
struct ScanPublicationMediaRestorer {
    private let client: MerianNetworkClient

    init(client: MerianNetworkClient) {
        self.client = client
    }

    func prepare(
        source: ScanPublicationMediaSource,
        includeImages: Bool = true,
        includeAudio: Bool = false
    ) throws -> PreparedScanPublicationMediaRestore {
        let restorableImagePaths = includeImages
            ? resolveRestorableImagePaths(for: source)
            : []
        let restorableVideoPaths = resolveRestorableVideoPaths(for: source)
        let restorableAudioPaths = includeAudio
            ? resolveRestorableAudioPaths(for: source)
            : []
        let imageSizes: [Int]
        if restorableImagePaths.isEmpty,
           includeImages,
           source.fallbackImageData?.isEmpty == false {
            imageSizes = [source.fallbackImageData?.count ?? 0]
        } else {
            imageSizes = try restorableImagePaths.map {
                try MediaStagingContract.fileSizeBytes(
                    at: localFileURL(for: $0)
                )
            }
        }
        let videoSizes = try restorableVideoPaths.map {
            try MediaStagingContract.fileSizeBytes(
                at: localFileURL(for: $0)
            )
        }
        let audioSizes = try restorableAudioPaths.map {
            try MediaStagingContract.fileSizeBytes(
                at: localFileURL(for: $0)
            )
        }
        try ScanPublicationMediaRestorePolicy.validatePayload(
            imageSizes: imageSizes,
            videoSizes: videoSizes,
            audioSizes: audioSizes
        )

        return PreparedScanPublicationMediaRestore(
            source: source,
            plan: ScanPublicationMediaRestorePlan(
                imagePaths: restorableImagePaths,
                videoPaths: restorableVideoPaths,
                audioPaths: restorableAudioPaths,
                usesFallbackImageData:
                    restorableImagePaths.isEmpty
                        && includeImages
                        && source.fallbackImageData?.isEmpty == false
            )
        )
    }

    func restore(
        _ prepared: PreparedScanPublicationMediaRestore
    ) async throws -> ScanPublicationRestoredObjectKeys {
        let source = prepared.source
        let plan = prepared.plan
        guard !plan.isEmpty else {
            return ScanPublicationRestoredObjectKeys(
                imageObjectKeys: [],
                videoObjectKeys: [],
                audioObjectKeys: []
            )
        }

        let imageObjectKeys = !plan.imagePaths.isEmpty
            || plan.usesFallbackImageData
            ? try await restoreImageObjectKeys(
                for: source,
                localImagePaths: plan.imagePaths
            )
            : []
        let videoObjectKeys = try await restoreVideoObjectKeys(
            for: source,
            localVideoPaths: plan.videoPaths
        )
        let audioObjectKeys = !plan.audioPaths.isEmpty
            ? try await restoreAudioObjectKeys(
                for: source,
                localAudioPaths: plan.audioPaths
            )
            : []
        return ScanPublicationRestoredObjectKeys(
            imageObjectKeys: imageObjectKeys,
            videoObjectKeys: videoObjectKeys,
            audioObjectKeys: audioObjectKeys
        )
    }

    private func restoreImageObjectKeys(
        for source: ScanPublicationMediaSource,
        localImagePaths: [String]
    ) async throws -> [String] {
        if localImagePaths.isEmpty {
            guard let fallbackImageData = source.fallbackImageData,
                  !fallbackImageData.isEmpty else {
                return []
            }

            let fileName = MediaStagingContract.sanitizedFileName(
                "\(source.scanId)_explore_restore_live.webp"
            )
            let uploadFiles = [
                ScanPublicationMediaRestorePolicy.makeUploadFile(
                    fileName: fileName,
                    mediaKind: .image,
                    contentType: "image/webp",
                    sizeBytes: fallbackImageData.count,
                    scanId: source.scanId
                )
            ]
            let uploadURLs = try await client.generateUploadURLs(
                uploadFiles: uploadFiles
            )
            guard let uploadURL = uploadURLs.first else {
                throw MerianError.invalidResponse
            }
            try await client.uploadToR2(
                uploadURL: uploadURL,
                data: fallbackImageData,
                contentType: "image/webp"
            )
            return [uploadURL.objectKey]
        }

        let fileNames = localImagePaths.enumerated().map { index, path in
            let ext = URL(fileURLWithPath: path).pathExtension
            let normalizedExtension = ext.isEmpty ? "webp" : ext
            return MediaStagingContract.sanitizedFileName(
                "\(source.scanId)_explore_restore_\(index).\(normalizedExtension)"
            )
        }

        let uploadFiles = try zip(localImagePaths, fileNames).map { path, fileName in
            let fileURL = localFileURL(for: path)
            return ScanPublicationMediaRestorePolicy.makeUploadFile(
                fileName: fileName,
                mediaKind: .image,
                contentType: imageMimeType(for: fileURL),
                sizeBytes: try MediaStagingContract.fileSizeBytes(at: fileURL),
                scanId: source.scanId
            )
        }

        let uploadURLs = try await client.generateUploadURLs(
            uploadFiles: uploadFiles
        )
        guard uploadURLs.count == localImagePaths.count else {
            throw MerianError.invalidResponse
        }

        let uploadPairs = Array(zip(localImagePaths, uploadURLs))
        let maxConcurrentUploads = 2

        try await withThrowingTaskGroup(of: Void.self) { group in
            var iterator = uploadPairs.makeIterator()
            var inFlight = 0

            func enqueueNext() {
                while inFlight < maxConcurrentUploads,
                      let (path, uploadURL) = iterator.next() {
                    inFlight += 1
                    group.addTask { [self] in
                        let fileURL = localFileURL(for: path)
                        try await client.uploadToR2(
                            uploadURL: uploadURL,
                            fileURL: fileURL,
                            contentType: imageMimeType(for: fileURL)
                        )
                    }
                }
            }

            enqueueNext()
            while try await group.next() != nil {
                inFlight -= 1
                enqueueNext()
            }
        }

        return uploadURLs.map(\.objectKey)
    }

    private func restoreVideoObjectKeys(
        for source: ScanPublicationMediaSource,
        localVideoPaths: [String]
    ) async throws -> [String] {
        guard !localVideoPaths.isEmpty else { return [] }
        guard localVideoPaths.count
                <= MerianConfig.mediaStagingMaxVideoFilesPerRequest,
              localVideoPaths.count
                <= MerianConfig.mediaStagingMaxFilesPerRequest else {
            throw MerianError.payloadTooLarge
        }

        let uploadFiles = try localVideoPaths.enumerated().map { index, path in
            let fileURL = localFileURL(for: path)
            let fileExtension = fileURL.pathExtension.isEmpty
                ? "mp4"
                : fileURL.pathExtension
            let fileName = MediaStagingContract.sanitizedFileName(
                "\(source.scanId)_explore_restore_video_\(index).\(fileExtension)"
            )
            let sizeBytes = try MediaStagingContract.fileSizeBytes(at: fileURL)
            guard sizeBytes <= MerianConfig.videoPayloadMaxBytes else {
                throw MerianError.payloadTooLarge
            }
            return ScanPublicationMediaRestorePolicy.makeUploadFile(
                fileName: fileName,
                mediaKind: .video,
                contentType: StagedMediaKind.video.contentType(for: fileURL.path),
                sizeBytes: sizeBytes,
                scanId: source.scanId
            )
        }

        let uploadURLs = try await client.generateUploadURLs(
            uploadFiles: uploadFiles
        )
        guard uploadURLs.count == localVideoPaths.count else {
            throw MerianError.invalidResponse
        }

        for (path, uploadURL) in zip(localVideoPaths, uploadURLs) {
            let fileURL = localFileURL(for: path)
            try await client.uploadToR2(
                uploadURL: uploadURL,
                fileURL: fileURL,
                contentType: StagedMediaKind.video.contentType(for: fileURL.path)
            )
        }

        return uploadURLs.map(\.objectKey)
    }

    private func restoreAudioObjectKeys(
        for source: ScanPublicationMediaSource,
        localAudioPaths: [String]
    ) async throws -> [String] {
        guard !localAudioPaths.isEmpty else { return [] }

        var sources: [(fileURL: URL, contentType: String)] = []
        for path in localAudioPaths {
            let fileURL = localFileURL(for: path)
            guard let contentType = await InferenceAudioPreparer
                .durableStorageContentType(at: fileURL) else {
                continue
            }
            sources.append((fileURL, contentType))
        }
        guard !sources.isEmpty else { return [] }
        guard sources.count
                <= MerianConfig.mediaStagingMaxAudioFilesPerRequest,
              sources.count
                <= MerianConfig.mediaStagingMaxFilesPerRequest else {
            throw MerianError.payloadTooLarge
        }

        let uploadFiles = try sources.enumerated().map { index, sourceFile in
            let fileExtension = sourceFile.contentType == "audio/mp4"
                ? "m4a"
                : "wav"
            let fileName = MediaStagingContract.sanitizedFileName(
                "\(source.scanId)_explore_restore_audio_\(index).\(fileExtension)"
            )
            let sizeBytes = try MediaStagingContract.fileSizeBytes(
                at: sourceFile.fileURL
            )
            guard sizeBytes <= MerianConfig.audioPayloadMaxBytes else {
                throw MerianError.payloadTooLarge
            }
            return ScanPublicationMediaRestorePolicy.makeUploadFile(
                fileName: fileName,
                mediaKind: .audio,
                contentType: sourceFile.contentType,
                sizeBytes: sizeBytes,
                scanId: source.scanId
            )
        }

        let uploadURLs = try await client.generateUploadURLs(
            uploadFiles: uploadFiles
        )
        guard uploadURLs.count == sources.count else {
            throw MerianError.invalidResponse
        }

        for (sourceFile, uploadURL) in zip(sources, uploadURLs) {
            try await client.uploadToR2(
                uploadURL: uploadURL,
                fileURL: sourceFile.fileURL,
                contentType: sourceFile.contentType
            )
        }

        return uploadURLs.map(\.objectKey)
    }

    private func resolveRestorableImagePaths(
        for source: ScanPublicationMediaSource
    ) -> [String] {
        var candidatePaths = source.imagePaths

        if candidatePaths.isEmpty, let coverImagePath = source.coverImagePath {
            candidatePaths.append(coverImagePath)
        }

        return existingUniquePaths(candidatePaths)
    }

    private func resolveRestorableVideoPaths(
        for source: ScanPublicationMediaSource
    ) -> [String] {
        existingUniquePaths(source.videoPaths)
    }

    private func resolveRestorableAudioPaths(
        for source: ScanPublicationMediaSource
    ) -> [String] {
        existingUniquePaths(source.audioPaths) { fileURL in
            let fileExtension = fileURL.pathExtension.lowercased()
            return fileExtension == "wav" || fileExtension == "m4a"
        }
    }

    private func existingUniquePaths(
        _ paths: [String],
        accepts: (URL) -> Bool = { _ in true }
    ) -> [String] {
        var resolved: [String] = []
        for path in paths where !path.starts(with: "http") {
            let fileURL = localFileURL(for: path)
            if accepts(fileURL),
               FileManager.default.fileExists(atPath: fileURL.path),
               !resolved.contains(path) {
                resolved.append(path)
            }
        }
        return resolved
    }

    private func localFileURL(for path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        if let url = URL(string: path), url.isFileURL {
            return url
        }
        return URL.documentsDirectory.appendingPathComponent(path)
    }

    private func imageMimeType(for fileURL: URL) -> String {
        let fileExtension = fileURL.pathExtension.lowercased()
        if fileExtension == "jpg" || fileExtension == "jpeg" {
            return "image/jpeg"
        }
        if fileExtension == "png" {
            return "image/png"
        }
        if fileExtension == "heic" || fileExtension == "heif" {
            return "image/heic"
        }

        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return "image/webp"
        }
        defer { try? handle.close() }

        let prefixData: Data
        do {
            guard let readData = try handle.read(upToCount: 12) else {
                return "image/webp"
            }
            prefixData = readData
        } catch {
            return "image/webp"
        }
        let prefix = [UInt8](prefixData)
        if prefix.count >= 3,
           prefix[0] == 0xFF, prefix[1] == 0xD8, prefix[2] == 0xFF {
            return "image/jpeg"
        }
        if prefix.count >= 8,
           prefix[0] == 0x89, prefix[1] == 0x50,
           prefix[2] == 0x4E, prefix[3] == 0x47,
           prefix[4] == 0x0D, prefix[5] == 0x0A,
           prefix[6] == 0x1A, prefix[7] == 0x0A {
            return "image/png"
        }
        if prefix.count >= 12,
           prefix[0] == 0x52, prefix[1] == 0x49,
           prefix[2] == 0x46, prefix[3] == 0x46,
           prefix[8] == 0x57, prefix[9] == 0x45,
           prefix[10] == 0x42, prefix[11] == 0x50 {
            return "image/webp"
        }
        return "image/webp"
    }
}
