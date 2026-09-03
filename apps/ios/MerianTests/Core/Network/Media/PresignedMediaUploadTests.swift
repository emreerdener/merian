import Foundation
import Testing

@testable import Merian

@Suite("Presigned Media Upload Policy")
struct PresignedMediaUploadTests {
    @Test func requestUsesOnlyTheDeclaredHeadersAndPUT() throws {
        let upload = MediaUploadTestFixtures.presignedURL()
        let request = try PresignedMediaUpload.makeRequest(uploadURL: upload, contentType: "video/mp4", contentLength: 4)
        #expect(request.url?.absoluteString == upload.signedUrl)
        #expect(request.httpMethod == "PUT")
        #expect(request.allHTTPHeaderFields == upload.requiredHeaders)
        #expect(request.httpBody == nil && request.httpBodyStream == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "apikey") == nil)
    }

    @Test(arguments: ["", "   ", "http://storage.example/put", "file:///tmp/media", "/put/media", "https://user@storage.example/put"])
    func insecureOrCredentialBearingURLFailsBeforeHeaderValidation(url: String) {
        let upload = MediaUploadTestFixtures.presignedURL(signedURL: url, headers: [:])
        #expect(throws: MerianError.invalidURL) {
            try PresignedMediaUpload.makeRequest(uploadURL: upload, contentType: "video/mp4", contentLength: 4)
        }
    }

    @Test(arguments: [
        [:],
        ["Content-Type": "video/mp4"],
        ["Content-Length": "4"],
        ["Content-Type": "image/webp", "Content-Length": "4"],
        ["Content-Type": "video/mp4", "Content-Length": "5"],
        ["Content-Type": "video/mp4", "Content-Length": "04"],
        ["content-type": "video/mp4", "content-length": "4"],
        ["Content-Type": "video/mp4", "Content-Length": "4", "Extra": "value"]
    ])
    func onlyTheExactTwoSignedHeaderValuesAreAccepted(headers: [String: String]) {
        let upload = MediaUploadTestFixtures.presignedURL(headers: headers)
        #expect(throws: MerianError.invalidResponse) {
            try PresignedMediaUpload.makeRequest(uploadURL: upload, contentType: "video/mp4", contentLength: 4)
        }
    }

    @Test(arguments: ["", "?X-Amz-SignedHeaders=host", "?X-Amz-SignedHeaders=content-type%3Bcontent-length%3Bhost",
                      "?X-Amz-SignedHeaders=Content-Length%3Bcontent-type%3Bhost"])
    func signedHeaderSetMustMatchExactly(query: String) {
        let upload = MediaUploadTestFixtures.presignedURL(signedURL: "https://storage.example/put/media\(query)")
        #expect(throws: MerianError.invalidResponse) {
            try PresignedMediaUpload.makeRequest(uploadURL: upload, contentType: "video/mp4", contentLength: 4)
        }
    }

    @Test func sharedURLNormalizationAndQueryKeyCaseRemainAccepted() throws {
        let upload = MediaUploadTestFixtures.presignedURL(
            signedURL: " \nHTTPS://storage.example/put/media?x-amz-signedheaders=content-length%3Bcontent-type%3Bhost\n"
        )
        let request = try PresignedMediaUpload.makeRequest(uploadURL: upload, contentType: "video/mp4", contentLength: 4)
        #expect(request.url?.scheme == "https")
        #expect(request.url?.path == "/put/media")
    }

    @Test func matchingZeroLengthDoesNotAddAStagingPolicyToTheRawRequestBuilder() throws {
        let upload = MediaUploadTestFixtures.presignedURL(size: 0)
        let request = try PresignedMediaUpload.makeRequest(uploadURL: upload, contentType: "video/mp4", contentLength: 0)
        #expect(request.value(forHTTPHeaderField: "Content-Length") == "0")
    }

    @Test(arguments: [200, 201, 202, 204, 206, 299, 301, 400, 401, 403, 404, 500, 503])
    func onlyHTTP200IsUploadSuccess(status: Int) throws {
        let url = try #require(URL(string: "https://storage.example/put/media"))
        let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
        if status == 200 {
            try PresignedMediaUpload.validateResponse(response)
        } else {
            #expect(throws: MerianError.uploadFailed) { try PresignedMediaUpload.validateResponse(response) }
        }
    }

    @Test func nonHTTPResponseIsNotUploadSuccess() throws {
        let url = try #require(URL(string: "https://storage.example/put/media"))
        let response = URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        #expect(throws: MerianError.uploadFailed) { try PresignedMediaUpload.validateResponse(response) }
    }
}
