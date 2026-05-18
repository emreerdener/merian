import Foundation

private struct ShareImportUploadURLRequestBody: Encodable {
    let files: [ShareImportStagingUploadFile]
}

private struct ShareImportStagingUploadFile: Encodable {
    let fileName: String
    let mediaKind: String
    let contentType: String
    let sizeBytes: Int
}

private struct ShareImportPresignedURLResponse: Decodable {
    let urls: [ShareImportPresignedURL]
}

private struct ShareImportPresignedURL: Decodable {
    let fileName: String
    let signedUrl: String
    let objectKey: String
}

private struct ShareImportQueueRequest: Encodable {
    let scanId: String
    let r2ObjectKey: String
    let mimeType: String
    let timestamp: String?
    let gpsLatitude: Double?
    let gpsLongitude: Double?
    let gpsElevation: Double?
    let deviceLocale: String
    let deviceTimeZone: String
    let deviceRegion: String?

    enum CodingKeys: String, CodingKey {
        case scanId = "scan_id"
        case r2ObjectKey
        case mimeType
        case timestamp
        case gpsLatitude
        case gpsLongitude
        case gpsElevation
        case deviceLocale
        case deviceTimeZone
        case deviceRegion
    }
}

private struct ShareImportQueueResponse: Decodable {
    let success: Bool
    let scanId: String

    enum CodingKeys: String, CodingKey {
        case success
        case scanId = "scan_id"
    }
}

enum ShareImportNetworkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case uploadRejected(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Merian could not build the upload URL."
        case .invalidResponse:
            return "Merian received an unexpected upload response."
        case .uploadRejected:
            return "Merian could not queue this image for identification."
        }
    }
}

struct ShareImportNetworkClient {
    var session: URLSession = .shared

    func uploadAndQueue(_ preparedImage: ShareImportPreparedImage) async throws -> String {
        let presignedURL = try await generateUploadURL(for: preparedImage)
        try await upload(preparedImage.imageData, to: presignedURL.signedUrl, contentType: preparedImage.contentType)
        return try await queueImport(preparedImage, objectKey: presignedURL.objectKey)
    }

    private func generateUploadURL(for preparedImage: ShareImportPreparedImage) async throws -> ShareImportPresignedURL {
        let body = ShareImportUploadURLRequestBody(files: [
            ShareImportStagingUploadFile(
                fileName: preparedImage.stagingFileName,
                mediaKind: "image",
                contentType: preparedImage.contentType,
                sizeBytes: preparedImage.imageData.count
            )
        ])

        let response: ShareImportPresignedURLResponse = try await postJSON(
            function: "generate-upload-urls",
            body: body
        )
        guard let url = response.urls.first else {
            throw ShareImportNetworkError.invalidResponse
        }
        return url
    }

    private func upload(_ data: Data, to signedURLString: String, contentType: String) async throws {
        guard let url = URL(string: signedURLString) else {
            throw ShareImportNetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (responseData, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ShareImportNetworkError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            _ = String(data: responseData, encoding: .utf8)
            throw ShareImportNetworkError.uploadRejected(httpResponse.statusCode)
        }
    }

    private func queueImport(_ preparedImage: ShareImportPreparedImage, objectKey: String) async throws -> String {
        let request = ShareImportQueueRequest(
            scanId: preparedImage.scanId,
            r2ObjectKey: objectKey,
            mimeType: preparedImage.contentType,
            timestamp: preparedImage.telemetry.timestamp,
            gpsLatitude: preparedImage.telemetry.gpsLatitude,
            gpsLongitude: preparedImage.telemetry.gpsLongitude,
            gpsElevation: preparedImage.telemetry.gpsElevation,
            deviceLocale: Locale.current.language.languageCode?.identifier ?? "en",
            deviceTimeZone: TimeZone.current.identifier,
            deviceRegion: Locale.current.region?.identifier
        )

        let response: ShareImportQueueResponse = try await postJSON(
            function: "share-import-scan",
            body: request
        )
        guard response.success else {
            throw ShareImportNetworkError.invalidResponse
        }
        return response.scanId
    }

    private func postJSON<Body: Encodable, Response: Decodable>(
        function: String,
        body: Body
    ) async throws -> Response {
        guard MerianEnvironment.isSupabaseConfigured,
              let url = URL(string: "\(MerianEnvironment.supabaseUrl)/functions/v1/\(function)") else {
            throw ShareImportNetworkError.invalidURL
        }

        let accessToken = try await ShareImportAuthStore.validAccessToken()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(MerianEnvironment.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ShareImportNetworkError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            _ = String(data: data, encoding: .utf8)
            throw ShareImportNetworkError.uploadRejected(httpResponse.statusCode)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
