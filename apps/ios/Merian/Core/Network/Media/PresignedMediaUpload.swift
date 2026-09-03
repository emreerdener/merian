import Foundation
import os

/// Existing signed-header and HTTP-success policy shared by data and file PUTs.
enum PresignedMediaUpload {
    static func makeRequest(
        uploadURL: PreSignedURL,
        contentType: String,
        contentLength: Int
    ) throws -> URLRequest {
        guard let signedURL = SecureTransportPolicy.httpsURL(
            from: uploadURL.signedUrl
        ) else {
            throw MerianError.invalidURL
        }
        guard uploadURL.requiredHeaders.count == 2,
              uploadURL.requiredHeaders["Content-Type"] == contentType,
              uploadURL.requiredHeaders["Content-Length"] == String(contentLength),
              MediaStagingContract.signedHeaders(from: signedURL)
                == "content-length;content-type;host" else {
            throw MerianError.invalidResponse
        }

        var request = URLRequest(url: signedURL)
        request.httpMethod = "PUT"
        for (field, value) in uploadURL.requiredHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }

    static func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MerianError.uploadFailed
        }

        if httpResponse.statusCode != 200 {
            MerianLog.network.debug(
                "R2 upload failed; status=\(httpResponse.statusCode, privacy: .public)."
            )
            throw MerianError.uploadFailed
        }
    }
}
