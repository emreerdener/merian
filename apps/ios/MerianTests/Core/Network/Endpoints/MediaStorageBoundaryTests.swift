import Foundation
import Testing

@Suite("Media Storage Architecture")
struct MediaStorageBoundaryTests {
    @Test func endpointsAndUploadsHaveFocusedStatelessOwners() throws {
        let client = try networkSource("MerianNetworkClient.swift")
        let owners = [
            "Endpoints/MerianNetworkClient+MediaStorage.swift":
                ["generateUploadURLs", "inspectScanImageCloudStatus", "repairScanImageCloudReference"],
            "Media/MerianNetworkClient+MediaUploads.swift":
                ["uploadToR2", "uploadToR2", "uploadStagedVideoFiles"]
        ]
        for (path, expected) in owners {
            let source = try networkSource(path)
            let regex = try NSRegularExpression(pattern: #"(?m)^    func ([A-Za-z0-9_]+)\("#)
            let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
            let names = try matches.map { String(source[try #require(Range($0.range(at: 1), in: source))]) }
            #expect(names.sorted() == expected.sorted())
            #expect(source.split(separator: "\n", omittingEmptySubsequences: false).count <= 600)
            for name in expected { #expect(!client.contains("func \(name)(")) }
            for token in ["URLSession", "SupabaseManager", "endpointURL(", "performAuthenticatedRequest(",
                          "activeSession", "Task", "static let shared", "FileManager", "Data(contentsOf:", "catch"] {
                #expect(!source.contains(token), "Owner must not acquire \(token)")
            }
        }
        for token in [
            "private let sessionTransport: PinnedNetworkTransport",
            "private let authenticatedTransport: AuthenticatedTransportDispatcher",
            "private func endpointURL(",
            "private func performAuthenticatedRequest("
        ] {
            #expect(client.contains(token))
        }
        let dispatcher = try networkSource(
            "Transport/AuthenticatedTransportDispatcher.swift"
        )
        #expect(
            dispatcher.contains("private func acquireAccountWorkLeaseIfRequired(")
        )
        let recovery = try networkSource(
            "Recovery/MerianNetworkClient+OwnedScanRecovery.swift"
        )
        for method in [
            "shareScanToExplore", "requestCommunityIdentification",
            "ensureCloudScanAvailableForFieldChat", "recoverMissingOwnedCloudScan"
        ] {
            #expect(recovery.contains("func \(method)("))
            #expect(!client.contains("func \(method)("))
        }
        let inference = try networkSource(
            "Endpoints/MerianNetworkClient+Inference.swift"
        )
        #expect(inference.contains("func identifyMultiModal("))
        #expect(!client.contains("func identifyMultiModal("))
        #expect(
            try networkSource("Media/ScanPublicationMediaRestorer.swift")
                .contains("func restore(")
        )
    }

    @Test func accountBoundEncodingPreservesConfigurationIdentityAndTransportOrder() throws {
        let client = try networkSource("MerianNetworkClient.swift")
        let bridge = try method("func performAccountBoundEncodedJSONPost<", in: client)
        try expectOrder([
            "try endpointURL(function)", "if let expectedAuthUserID", "authUserID = expectedAuthUserID",
            "authUserID = try await authenticatedTransport", ".requestPayloadAuthUserID()",
            "try JSONEncoder().encode(body(authUserID))",
            "try await performAuthenticatedRequest(", "body: bodyData", "expectedAuthUserID: authUserID", "return data"
        ], in: bridge)
        #expect(bridge.contains("body: (UUID) -> Body"))
        #expect(bridge.components(separatedBy: "performAuthenticatedRequest(").count == 2)
        for token in ["@escaping", "catch", "Task", "URLSession", "SupabaseManager", "idempotencyKey",
                      "timeoutInterval:", "isRetry:", "await body"] {
            #expect(!bridge.contains(token), "Account bridge must not add \(token)")
        }
        let endpoint = try networkSource("Endpoints/MerianNetworkClient+MediaStorage.swift")
        let signing = try method("func generateUploadURLs(", in: endpoint)
        try expectOrder(["performAccountBoundEncodedJSONPost(", #"function: "generate-upload-urls""#,
                         "expectedAuthUserID: expectedAuthUserID", "UploadURLRequestBody(",
                         "userId: authUserID.uuidString.lowercased()", "JSONDecoder().decode(PreSignedURLResponse.self"],
                        in: signing)
        #expect(endpoint.contains("private struct UploadURLRequestBody: Encodable"))
        #expect(endpoint.contains(#"case userId = "user_id""#))
    }

    @Test func signedRequestAndResponsePoliciesDoNotWidenSuccessOrRetry() throws {
        let policy = try networkSource("Media/PresignedMediaUpload.swift")
        try expectOrder(["SecureTransportPolicy.httpsURL(", "throw MerianError.invalidURL",
                         "uploadURL.requiredHeaders.count == 2", #"uploadURL.requiredHeaders["Content-Type"] == contentType"#,
                         #"uploadURL.requiredHeaders["Content-Length"] == String(contentLength)"#,
                         "MediaStagingContract.signedHeaders(from: signedURL)", #""content-length;content-type;host""#,
                         "throw MerianError.invalidResponse", "URLRequest(url: signedURL)", #"request.httpMethod = "PUT""#,
                         "for (field, value) in uploadURL.requiredHeaders", "request.setValue(value, forHTTPHeaderField: field)"],
                        in: policy)
        let response = try method("static func validateResponse(", in: policy)
        #expect(response.contains("as? HTTPURLResponse") && response.contains("httpResponse.statusCode != 200"))
        #expect(!response.contains("JSONDecoder") && !response.contains("responseData"))

        let client = try networkSource("MerianNetworkClient.swift")
        let data = try method("func performPresignedUpload(request: URLRequest)", in: client)
        let file = try method("func performPresignedUpload(request: URLRequest, fileURL:", in: client)
        #expect(data.contains("try await sessionTransport.data(for: request)"))
        #expect(
            file.contains(
                "try await sessionTransport.upload(for: request, fromFile: fileURL)"
            )
        )
        for bridge in [data, file] {
            #expect(bridge.contains("-> (Data, URLResponse)"))
            for token in ["catch", "Task", "Auth", "retry", "JSON", "Data(contentsOf:", "URLSession("] {
                #expect(!bridge.contains(token), "Raw upload bridge must not add \(token)")
            }
        }
    }

    @Test func videoPlanningAndFileRestatStayAheadOfSigningAndPUT() throws {
        let plan = try networkSource("Media/StagedVideoUploadPlan.swift")
        try expectOrder(["for videoFilePath in videoFilePaths", "guard !videoFileURLs.isEmpty",
                         "if !missingVideoPaths.isEmpty", "let uploadFiles = try videoFileURLs.map",
                         "try MediaStagingContract.fileSizeBytes", "uploadFiles.count <= MerianConfig.mediaStagingMaxVideoFilesPerRequest",
                         "uploadFiles.count <= MerianConfig.mediaStagingMaxFilesPerRequest", "for uploadFile in uploadFiles",
                         "uploadFile.sizeBytes > 0", "uploadFile.sizeBytes <= MerianConfig.videoPayloadMaxBytes",
                         "return Self(fileURLs: videoFileURLs, uploadFiles: uploadFiles)"],
                        in: plan)
        #expect(plan.contains("private init("))
        #expect(plan.contains("private static func resolvedLocalMediaURL("))
        #expect(plan.contains("private static func existingLocalMediaURL("))
        try expectOrder(["URL.documentsDirectory.appendingPathComponent(fileName)",
                         "FileManager.default.temporaryDirectory.appendingPathComponent(fileName)"], in: plan)
        let uploads = try networkSource("Media/MerianNetworkClient+MediaUploads.swift")
        let video = try method("func uploadStagedVideoFiles(", in: uploads)
        try expectOrder(["StagedVideoUploadPlan.make(", "generateUploadURLs(uploadFiles: plan.uploadFiles)",
                         "guard uploadURLs.count == plan.fileURLs.count", "throw MerianError.invalidResponse",
                         "for (fileURL, uploadURL) in zip(plan.fileURLs, uploadURLs)", "try await uploadToR2(",
                         "return uploadURLs.map(\\.objectKey)"], in: video)
        let fileStart = try #require(uploads.range(of: "        let currentSize ="))
        try expectOrder(["MediaStagingContract.fileSizeBytes(at: fileURL)", "PresignedMediaUpload.makeRequest(",
                         "contentLength: currentSize", "performPresignedUpload(request: request, fileURL: fileURL)",
                         "PresignedMediaUpload.validateResponse(response)"], in: String(uploads[fileStart.lowerBound...]))
    }

    @Test func wireModelsAndInspectionProjectionKeepTheirOriginalSemantics() throws {
        let client = try networkSource("MerianNetworkClient.swift")
        let models = try networkSource("MediaStorageAPIModels.swift")
        for type in ["struct PreSignedURLResponse:", "struct PreSignedURL:", "enum ScanImageCloudStatus:",
                     "struct ScanImageCloudInspection:"] {
            #expect(models.contains(type) && !client.contains(type))
        }
        #expect(models.contains("let mediaAssetId: String?") && models.contains("let mediaSessionId: String?"))
        #expect(models.contains("decodeIfPresent(Int.self, forKey: .updatedScanCount) ?? 0"))
        #expect(models.contains("decodeIfPresent(Int.self, forKey: .updatedPostMediaCount) ?? 0"))
        let endpoint = try networkSource("Endpoints/MerianNetworkClient+MediaStorage.swift")
        #expect(endpoint.contains("private struct ScanImageCloudInspectionResponse: Decodable"))
        let inspection = try method("private func scanImageCloudRequest(", in: endpoint)
        try expectOrder([#"["source_url": sourceUrl]"#, "if let restoredObjectKey",
                         #"payload["restored_object_key"] = restoredObjectKey"#, "performAuthenticatedJSONDataPost(",
                         #"function: "repair-scan-image""#, "JSONDecoder()", ".decode(ScanImageCloudInspectionResponse.self"],
                        in: inspection)
        for token in ["trimmingCharacters", "URL(", "idempotencyKey", "status ==", "catch", "keyDecodingStrategy"] {
            #expect(!inspection.contains(token), "Inspection primitive must not add \(token)")
        }
    }

    @Test func rehomesKeepCallerTestsAndRequireTheNewCriticalSuite() throws {
        let aggregate = try source("apps/ios/MerianTests/Core/Network/MerianNetworkClientTests.swift")
        let owners = [
            "Endpoints/MediaStorageEndpointTests.swift": ["testGenerateUploadURLsUsesStructuredMediaManifest"],
            "Endpoints/ScanImageCloudEndpointTests.swift": ["testScanImageCloudInspectionSendsSourceAndParsesMissingStatus",
                                                          "testScanImageCloudRepairSendsStagedKeyAndParsesCounts"],
            "Media/StagedVideoUploadTests.swift": ["testUploadStagedVideoFilesFallsBackToMovedDocumentsFile",
                                                 "testUploadStagedVideoFilesThrowsWhenAnyRequestedVideoIsMissing",
                                                 "testUploadStagedVideoFilesRejectsEmptyFileBeforeSigning"]
        ]
        for (path, names) in owners {
            let test = try source("apps/ios/MerianTests/Core/Network/\(path)")
            #expect(test.contains("NetworkEndpointFixture()"))
            #expect(!test.contains("MerianNetworkClient.shared") && !test.contains("MockURLProtocol.mockEndpoints"))
            for name in names { #expect(test.contains("func \(name)(") && !aggregate.contains("func \(name)(")) }
        }
        let restore = try source(
            "apps/ios/MerianTests/Core/Network/Media/ScanPublicationMediaRestorePolicyTests.swift"
        )
        let recovery = try source(
            "apps/ios/MerianTests/Core/Network/Recovery/OwnedScanRecoveryPolicyTests.swift"
        )
        #expect(restore.contains("func testExploreRestoreMediaBudgetRejectsPartialStagingBeforeUpload("))
        #expect(recovery.contains("func testFieldChatCloudPreflightRejectsMismatchedRecordIdentity("))
        #expect(!aggregate.contains("func testExploreRestoreMediaBudgetRejectsPartialStagingBeforeUpload("))
        #expect(!aggregate.contains("func testFieldChatCloudPreflightRejectsMismatchedRecordIdentity("))
        let validator = try source("scripts/validate-ios-critical-test-results.sh")
        try expectOrder([#""Foreground video empty-file rejection""#, #""StagedVideoUploadTests""#,
                         #""Staged Video Uploads""#, #""testUploadStagedVideoFilesRejectsEmptyFileBeforeSigning""#], in: validator)
    }

    private func method(_ declaration: String, in source: String) throws -> String {
        let start = try #require(source.range(of: "    \(declaration)"))
        let end = try #require(source.range(of: "\n    }", range: start.upperBound..<source.endIndex))
        return String(source[start.lowerBound..<end.upperBound])
    }

    private func expectOrder(_ tokens: [String], in source: String) throws {
        var position = source.startIndex
        for token in tokens {
            let match = try #require(source.range(of: token, range: position..<source.endIndex))
            position = match.upperBound
        }
    }

    private func networkSource(_ path: String) throws -> String {
        try source("apps/ios/Merian/Core/Network/\(path)")
    }

    private func source(_ path: String) throws -> String {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("project.yml").path) {
                return try String(contentsOf: directory.appendingPathComponent(path), encoding: .utf8)
            }
            directory.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
