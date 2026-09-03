import Foundation
import os

/// Resolves every local video and validates the complete batch before signing.
struct StagedVideoUploadPlan {
    let fileURLs: [URL]
    let uploadFiles: [StagingUploadFile]

    private init(fileURLs: [URL], uploadFiles: [StagingUploadFile]) {
        self.fileURLs = fileURLs
        self.uploadFiles = uploadFiles
    }

    static func make(videoFilePaths: [String], scanId: String) throws -> Self {
        var videoFileURLs: [URL] = []
        var missingVideoPaths: [String] = []
        for videoFilePath in videoFilePaths {
            if let fileURL = existingLocalMediaURL(for: videoFilePath) {
                videoFileURLs.append(fileURL)
            } else {
                missingVideoPaths.append(videoFilePath)
            }
        }

        guard !videoFileURLs.isEmpty else {
            MerianLog.network.error("Video staging upload requested but no local video files were found.")
            throw CocoaError(.fileNoSuchFile)
        }
        if !missingVideoPaths.isEmpty {
            MerianLog.network.error(
                "Video staging upload missing \(missingVideoPaths.count, privacy: .public)/\(videoFilePaths.count, privacy: .public) requested local video file(s)."
            )
            throw CocoaError(.fileNoSuchFile)
        }

        let uploadFiles = try videoFileURLs.map { fileURL in
            let sizeBytes = try MediaStagingContract.fileSizeBytes(at: fileURL)
            return StagingUploadFile(
                fileName: MediaStagingContract.stagingFileName(scanId: scanId, localPath: fileURL.lastPathComponent),
                mediaKind: .video,
                contentType: StagedMediaKind.video.contentType(for: fileURL.path),
                sizeBytes: sizeBytes,
                clientScanId: scanId,
                mediaRole: StagedMediaKind.video.defaultScanMediaRole
            )
        }

        guard uploadFiles.count <= MerianConfig.mediaStagingMaxVideoFilesPerRequest,
              uploadFiles.count <= MerianConfig.mediaStagingMaxFilesPerRequest else {
            throw MerianError.payloadTooLarge
        }
        for uploadFile in uploadFiles {
            guard uploadFile.sizeBytes > 0,
                  uploadFile.sizeBytes <= MerianConfig.videoPayloadMaxBytes else {
                throw MerianError.payloadTooLarge
            }
        }

        return Self(fileURLs: videoFileURLs, uploadFiles: uploadFiles)
    }

    private static func resolvedLocalMediaURL(for path: String) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("file://"), let url = URL(string: trimmed), url.isFileURL {
            return url
        }
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }
        return URL.documentsDirectory.appendingPathComponent(trimmed)
    }

    private static func existingLocalMediaURL(for path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let primaryURL = resolvedLocalMediaURL(for: trimmed)
        if FileManager.default.fileExists(atPath: primaryURL.path) {
            return primaryURL
        }

        let fileName = primaryURL.lastPathComponent
        guard !fileName.isEmpty else { return nil }

        let fallbackURLs = [
            URL.documentsDirectory.appendingPathComponent(fileName),
            FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        ]
        return fallbackURLs.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
