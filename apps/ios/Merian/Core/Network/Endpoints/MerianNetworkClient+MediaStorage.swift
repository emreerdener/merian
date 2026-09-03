import Foundation

/// Storage wire operations. Callers retain queue, publication, and recovery workflows.
extension MerianNetworkClient {
    func generateUploadURLs(
        uploadFiles: [StagingUploadFile],
        expectedAuthUserID: UUID? = nil
    ) async throws -> [PreSignedURL] {
        let data = try await performAccountBoundEncodedJSONPost(
            function: "generate-upload-urls",
            expectedAuthUserID: expectedAuthUserID
        ) { authUserID in
            UploadURLRequestBody(
                files: uploadFiles,
                userId: authUserID.uuidString.lowercased()
            )
        }
        return try JSONDecoder().decode(PreSignedURLResponse.self, from: data).urls
    }

    func inspectScanImageCloudStatus(sourceUrl: String) async throws -> ScanImageCloudInspection {
        try await scanImageCloudRequest(sourceUrl: sourceUrl, restoredObjectKey: nil)
    }

    func repairScanImageCloudReference(
        sourceUrl: String,
        restoredObjectKey: String
    ) async throws -> ScanImageCloudInspection {
        try await scanImageCloudRequest(
            sourceUrl: sourceUrl,
            restoredObjectKey: restoredObjectKey
        )
    }

    private func scanImageCloudRequest(
        sourceUrl: String,
        restoredObjectKey: String?
    ) async throws -> ScanImageCloudInspection {
        var payload: [String: Any] = ["source_url": sourceUrl]
        if let restoredObjectKey {
            payload["restored_object_key"] = restoredObjectKey
        }
        let data = try await performAuthenticatedJSONDataPost(
            function: "repair-scan-image",
            payload: payload
        )
        return try JSONDecoder()
            .decode(ScanImageCloudInspectionResponse.self, from: data)
            .data
    }
}

private struct UploadURLRequestBody: Encodable {
    let files: [StagingUploadFile]
    let userId: String

    private enum CodingKeys: String, CodingKey {
        case files
        case userId = "user_id"
    }
}

private struct ScanImageCloudInspectionResponse: Decodable {
    let data: ScanImageCloudInspection
}
