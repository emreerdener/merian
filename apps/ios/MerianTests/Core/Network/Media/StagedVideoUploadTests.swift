import Foundation
import Testing

@testable import Merian

@Suite("Staged Video Uploads")
@MainActor
struct StagedVideoUploadTests {
    @Test func testUploadStagedVideoFilesFallsBackToMovedDocumentsFile() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let fileName = "moved_video_\(UUID().uuidString)_playback.mp4"
        let documentsURL = URL.documentsDirectory.appendingPathComponent(fileName)
        let staleTemporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try FileManager.default.createDirectory(
            at: URL.documentsDirectory,
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: staleTemporaryURL)
        try Data("video-bytes".utf8).write(to: documentsURL, options: .atomic)
        defer {
            try? FileManager.default.removeItem(at: documentsURL)
        }

        let testData = Data("""
        {
            "urls": [
                {
                    "fileName": "scan-video-fallback_\(fileName)",
                    "signedUrl": "https://example.com/put/moved-video?X-Amz-SignedHeaders=content-length%3Bcontent-type%3Bhost",
                    "objectKey": "staging/test-user/scan-video-fallback_\(fileName)",
                    "requiredHeaders": {
                        "Content-Type": "video/mp4",
                        "Content-Length": "11"
                    }
                }
            ]
        }
        """.utf8)
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        fixture.transport.register(path: "/generate-upload-urls") { request in
            let bodyData = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            let files = try #require(payload["files"] as? [[String: Any]])
            #expect(files.count == 1)
            #expect(files[0]["fileName"] as? String == "scan-video-fallback_\(fileName)")
            #expect(files[0]["mediaKind"] as? String == "video")
            #expect(files[0]["contentType"] as? String == "video/mp4")
            #expect(files[0]["sizeBytes"] as? Int == 11)
            return (mockResponse, testData)
        }
        fixture.transport.register(path: "/put/moved-video") { request in
            #expect(request.httpMethod == "PUT")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "video/mp4")
            #expect(request.value(forHTTPHeaderField: "Content-Length") == "11")
            return (mockResponse, Data())
        }

        let objectKeys = try await fixture.client.uploadStagedVideoFiles(
            videoFilePaths: [staleTemporaryURL.path],
            scanId: "scan-video-fallback"
        )

        #expect(objectKeys == ["staging/test-user/scan-video-fallback_\(fileName)"])
    }

    @Test func testUploadStagedVideoFilesThrowsWhenAnyRequestedVideoIsMissing() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let existingFileName = "existing_video_\(UUID().uuidString)_playback.mp4"
        let existingURL = URL.documentsDirectory.appendingPathComponent(existingFileName)
        try FileManager.default.createDirectory(
            at: URL.documentsDirectory,
            withIntermediateDirectories: true
        )
        try Data("video-bytes".utf8).write(to: existingURL, options: .atomic)
        defer {
            try? FileManager.default.removeItem(at: existingURL)
        }

        fixture.transport.register(path: "/generate-upload-urls") { _ in
            Issue.record("Partial video restore should fail before requesting upload URLs")
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        do {
            _ = try await fixture.client.uploadStagedVideoFiles(
                videoFilePaths: [
                    existingURL.path,
                    FileManager.default.temporaryDirectory
                        .appendingPathComponent("missing_\(existingFileName)")
                        .path
                ],
                scanId: "scan-video-partial"
            )
            Issue.record("Expected missing video upload to throw")
        } catch {
            #expect((error as NSError).domain == NSCocoaErrorDomain)
        }
    }

    @Test func testUploadStagedVideoFilesRejectsEmptyFileBeforeSigning() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let fileName = "empty_video_\(UUID().uuidString)_playback.mp4"
        let fileURL = URL.documentsDirectory.appendingPathComponent(fileName)
        try FileManager.default.createDirectory(
            at: URL.documentsDirectory,
            withIntermediateDirectories: true
        )
        try Data().write(to: fileURL, options: .atomic)
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        fixture.transport.register(path: "/generate-upload-urls") { _ in
            Issue.record("Empty video should fail before requesting upload URLs")
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        await #expect(throws: MerianError.payloadTooLarge) {
            _ = try await fixture.client.uploadStagedVideoFiles(
                videoFilePaths: [fileURL.path],
                scanId: "scan-video-empty"
            )
        }
    }

    @Test(arguments: [0, 2])
    func signingCountMismatchStopsBeforeAnyPUT(responseCount: Int) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let files = try NetworkMediaFileFixture()
        defer { files.close() }
        let file = try files.write()
        fixture.transport.register(path: "/generate-upload-urls") { request in
            let json = try MediaUploadTestFixtures.signingResponse(
                Array(repeating: MediaUploadTestFixtures.presignedURL(), count: responseCount)
            )
            return try NetworkEndpointTestSupport.response(to: request, json: json)
        }
        await confirmation("No PUT on partial or extra signing response", expectedCount: 0) { sent in
            fixture.transport.register(path: "/put/media") { request in
                sent()
                return try NetworkEndpointTestSupport.response(to: request, json: "")
            }
            await #expect(throws: MerianError.invalidResponse) {
                _ = try await fixture.client.uploadStagedVideoFiles(videoFilePaths: [file.path], scanId: "synthetic")
            }
        }
    }

    @Test(arguments: [0, 1, 2])
    func missingOversizedAndOverCountInputsNeverReachSigning(kind: Int) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let files = try NetworkMediaFileFixture()
        defer { files.close() }
        let file = try files.sizedFile(kind == 1 ? MerianConfig.videoPayloadMaxBytes + 1 : 1)
        let paths = kind == 0 ? [] : Array(
            repeating: file.path, count: kind == 2 ? MerianConfig.mediaStagingMaxVideoFilesPerRequest + 1 : 1
        )
        await confirmation("No signing on invalid local plan", expectedCount: 0) { sent in
            fixture.transport.register(path: "/generate-upload-urls") { request in
                sent()
                return try NetworkEndpointTestSupport.response(to: request, json: #"{"urls":[]}"#)
            }
            do {
                _ = try await fixture.client.uploadStagedVideoFiles(videoFilePaths: paths, scanId: "synthetic")
                Issue.record("Invalid local plan must fail")
            } catch MerianError.payloadTooLarge {
                #expect(kind != 0)
            } catch let error as CocoaError {
                #expect(kind == 0 && error.code == .fileNoSuchFile)
            } catch {
                Issue.record("Unexpected error type: \(type(of: error))")
            }
        }
    }

    @Test func fileChangedDuringSigningCannotUseStaleSignedLength() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let files = try NetworkMediaFileFixture()
        defer { files.close() }
        let file = try files.write()
        fixture.transport.register(path: "/generate-upload-urls") { request in
            try Data([0]).write(to: file, options: .atomic)
            return try NetworkEndpointTestSupport.response(
                to: request, json: MediaUploadTestFixtures.signingResponse([MediaUploadTestFixtures.presignedURL()])
            )
        }
        await confirmation("No stale-length video PUT", expectedCount: 0) { sent in
            fixture.transport.register(path: "/put/media") { request in
                sent()
                return try NetworkEndpointTestSupport.response(to: request, json: "")
            }
            await #expect(throws: MerianError.invalidResponse) {
                _ = try await fixture.client.uploadStagedVideoFiles(videoFilePaths: [file.path], scanId: "synthetic")
            }
        }
    }

    @Test func uploadFailureDoesNotReturnAnObjectKey() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let files = try NetworkMediaFileFixture()
        defer { files.close() }
        let file = try files.write()
        fixture.transport.register(path: "/generate-upload-urls") { request in
            try NetworkEndpointTestSupport.response(
                to: request, json: MediaUploadTestFixtures.signingResponse([MediaUploadTestFixtures.presignedURL()])
            )
        }
        await confirmation("One failed video PUT") { sent in
            fixture.transport.register(path: "/put/media") { request in
                sent()
                return try NetworkEndpointTestSupport.response(to: request, status: 503, json: "")
            }
            await #expect(throws: MerianError.uploadFailed) {
                _ = try await fixture.client.uploadStagedVideoFiles(videoFilePaths: [file.path], scanId: "synthetic")
            }
        }
    }
}
