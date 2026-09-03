import Foundation
import Testing

@testable import Merian

@Suite("Media Storage Endpoints")
@MainActor
struct MediaStorageEndpointTests {
    @Test func testGenerateUploadURLsUsesStructuredMediaManifest() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let testData = Data("""
        {
            "urls": [
                {
                    "fileName": "image_1",
                    "signedUrl": "https://example.com/put/image_1?X-Amz-SignedHeaders=content-length%3Bcontent-type%3Bhost",
                    "objectKey": "merian/user/image_1.webp",
                    "requiredHeaders": {
                        "Content-Type": "image/webp",
                        "Content-Length": "1024"
                    },
                    "mediaAssetId": "asset-123",
                    "mediaSessionId": "session-456"
                }
            ]
        }
        """.utf8)
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        fixture.transport.register(path: "/generate-upload-urls") { request in
            #expect(request.url?.path.hasSuffix("/generate-upload-urls") == true)
            #expect(request.httpMethod == "POST")
            let bodyData = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            #expect(payload["fileNames"] == nil)
            let files = try #require(payload["files"] as? [[String: Any]])
            #expect(files.count == 1)
            #expect(files[0]["fileName"] as? String == "image_1")
            #expect(files[0]["mediaKind"] as? String == "image")
            #expect(files[0]["contentType"] as? String == "image/webp")
            #expect(files[0]["sizeBytes"] as? Int == 1024)
            #expect(files[0]["clientScanId"] as? String == "00000000-0000-0000-0000-000000000001")
            #expect(files[0]["mediaRole"] as? String == "display")
            return (mockResponse, testData)
        }

        let urls = try await fixture.client.generateUploadURLs(
            uploadFiles: [
                StagingUploadFile(
                    fileName: "image_1",
                    mediaKind: .image,
                    contentType: "image/webp",
                    sizeBytes: 1024,
                    clientScanId: "00000000-0000-0000-0000-000000000001",
                    mediaRole: "display"
                )
            ]
        )
        #expect(urls.count == 1)
        #expect(urls[0].signedUrl.contains("/put/image_1"))
        #expect(urls[0].requiredHeaders["Content-Length"] == "1024")
        #expect(urls[0].mediaAssetId == "asset-123")
        #expect(urls[0].mediaSessionId == "session-456")
    }

    @Test(arguments: [false, true])
    func signingSerializesTheLowercaseExplicitOrResolvedOwner(useExplicitOwner: Bool) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let ownerID = MediaStorageRequestCase.ownerID
        // DEBUG transport bypasses live Auth leases; this proves payload selection only.
        fixture.client.overridingAuthUserID = useExplicitOwner ? UUID() : ownerID
        let manifest = StagingUploadFile(
            fileName: " raw file ", mediaKind: .audio, contentType: "audio/mp4", sizeBytes: 3,
            clientScanId: " raw scan ", mediaRole: " audio ",
            uploadPurpose: StagingUploadPurpose(rawValue: "scan_share_restore")
        )
        let json = """
        {"user_id":"\(ownerID.uuidString.lowercased())","files":[{
          "fileName":" raw file ","mediaKind":"audio","contentType":"audio/mp4","sizeBytes":3,
          "clientScanId":" raw scan ","mediaRole":" audio ","uploadPurpose":"scan_share_restore"
        }]}
        """
        try await confirmation("One signing request with the selected payload owner") { sent in
            fixture.transport.register(path: "/generate-upload-urls") { request in
                sent()
                try NetworkEndpointTestSupport.expectPOST(request, function: "generate-upload-urls", json: json)
                return try NetworkEndpointTestSupport.response(to: request, json: #"{"success":false,"urls":[]}"#)
            }
            let urls = try await fixture.client.generateUploadURLs(
                uploadFiles: [manifest], expectedAuthUserID: useExplicitOwner ? ownerID : nil
            )
            #expect(urls.isEmpty)
        }
    }

    @Test func anExplicitAccountDoesNotBypassCurrentSessionResolution() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        fixture.client.overridingAuthUserID = nil
        await confirmation("No signing request without a current account", expectedCount: 0) { sent in
            fixture.transport.register(path: "/generate-upload-urls") { request in
                sent()
                return try NetworkEndpointTestSupport.response(to: request, json: #"{"urls":[]}"#)
            }
            await #expect(throws: SupabaseAuthTransitionError.signOutSessionChanged) {
                _ = try await fixture.client.generateUploadURLs(
                    uploadFiles: [], expectedAuthUserID: MediaStorageRequestCase.ownerID
                )
            }
        }
    }

    @Test(arguments: [0, 7])
    func rawManifestCountsAreForwardedWithoutAddingServerValidation(count: Int) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let manifest = StagingUploadFile(fileName: "raw", mediaKind: .image, contentType: "raw", sizeBytes: 0)
        try await confirmation("One raw manifest request") { sent in
            fixture.transport.register(path: "/generate-upload-urls") { request in
                sent()
                let bytes = try #require(MockURLProtocol.bodyData(for: request))
                let payload = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
                let files = try #require(payload["files"] as? [[String: Any]])
                #expect(files.count == count)
                #expect(payload["fileNames"] == nil)
                for file in files {
                    #expect(file["clientScanId"] == nil && file["mediaRole"] == nil && file["uploadPurpose"] == nil)
                }
                return try NetworkEndpointTestSupport.response(to: request, json: #"{"urls":[]}"#)
            }
            _ = try await fixture.client.generateUploadURLs(uploadFiles: Array(repeating: manifest, count: count))
        }
    }

    @Test(arguments: ["", "null", "[]", "{}", #"{"urls":null}"#, #"{"urls":[{}]}"#])
    func malformedSigningResponsesRemainDecodingErrors(json: String) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        fixture.transport.register(path: "/generate-upload-urls") { request in
            try NetworkEndpointTestSupport.response(to: request, json: json)
        }
        await #expect(throws: DecodingError.self) {
            _ = try await fixture.client.generateUploadURLs(uploadFiles: [])
        }
    }

    @Test func unresolvedAccountFailsBeforeTheBodyBuilder() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        fixture.client.overridingAuthUserID = nil
        await #expect(throws: SupabaseAuthTransitionError.self) {
            _ = try await fixture.client.performAccountBoundEncodedJSONPost(function: "generate-upload-urls") { _ in
                Issue.record("Body construction must not precede account resolution")
                return MediaStorageThrowingBody()
            }
        }
    }

    @Test(arguments: [false, true])
    func encodingErrorPrecedesTransportAndTaskCancellation(cancelled: Bool) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        await confirmation("No request on encoding failure", expectedCount: 0) { sent in
            fixture.transport.register(path: "/generate-upload-urls") { request in
                sent()
                return try NetworkEndpointTestSupport.response(to: request, json: #"{"urls":[]}"#)
            }
            let task = Task { @MainActor in
                if cancelled { withUnsafeCurrentTask { $0?.cancel() } }
                return try await fixture.client.performAccountBoundEncodedJSONPost(
                    function: "generate-upload-urls", expectedAuthUserID: MediaStorageRequestCase.ownerID
                ) { ownerID in
                    #expect(ownerID == MediaStorageRequestCase.ownerID)
                    return MediaStorageThrowingBody()
                }
            }
            await #expect(throws: MediaStorageEncodingFailure.self) { _ = try await task.value }
        }
    }
}

private enum MediaStorageEncodingFailure: Error { case synthetic }

private struct MediaStorageThrowingBody: Encodable {
    func encode(to _: Encoder) throws { throw MediaStorageEncodingFailure.synthetic }
}
