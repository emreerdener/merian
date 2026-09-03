import Foundation
import os

extension MerianNetworkClient {
    func uploadToR2(
        uploadURL: PreSignedURL,
        data: Data,
        contentType: String
    ) async throws {
        let request = try PresignedMediaUpload.makeRequest(
            uploadURL: uploadURL,
            contentType: contentType,
            contentLength: data.count
        )
        var bodyRequest = request
        bodyRequest.httpBody = data

        let uploadStart = CFAbsoluteTimeGetCurrent()
        let (_, response) = try await performPresignedUpload(request: bodyRequest)
        MerianLog.network.debug("R2 upload completed in \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - uploadStart), privacy: .public)s.")
        try PresignedMediaUpload.validateResponse(response)
    }

    func uploadToR2(
        uploadURL: PreSignedURL,
        fileURL: URL,
        contentType: String
    ) async throws {
        let currentSize = try MediaStagingContract.fileSizeBytes(at: fileURL)
        let request = try PresignedMediaUpload.makeRequest(
            uploadURL: uploadURL,
            contentType: contentType,
            contentLength: currentSize
        )

        let uploadStart = CFAbsoluteTimeGetCurrent()
        let (_, response) = try await performPresignedUpload(request: request, fileURL: fileURL)
        MerianLog.network.debug("R2 file upload completed in \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - uploadStart), privacy: .public)s.")
        try PresignedMediaUpload.validateResponse(response)
    }

    func uploadStagedVideoFiles(videoFilePaths: [String], scanId: String) async throws -> [String] {
        let plan = try StagedVideoUploadPlan.make(videoFilePaths: videoFilePaths, scanId: scanId)
        let uploadURLs = try await generateUploadURLs(uploadFiles: plan.uploadFiles)
        guard uploadURLs.count == plan.fileURLs.count else {
            throw MerianError.invalidResponse
        }

        for (fileURL, uploadURL) in zip(plan.fileURLs, uploadURLs) {
            try await uploadToR2(
                uploadURL: uploadURL,
                fileURL: fileURL,
                contentType: StagedMediaKind.video.contentType(for: fileURL.path)
            )
        }

        return uploadURLs.map(\.objectKey)
    }
}
