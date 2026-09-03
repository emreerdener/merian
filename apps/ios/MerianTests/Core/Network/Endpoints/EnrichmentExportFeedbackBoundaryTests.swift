import Foundation
import Testing

@Suite("Enrichment, Export, and Feedback Architecture")
struct EnrichmentExportFeedbackBoundaryTests {
    @Test func fiveEndpointsHaveSeparateStatelessOwners() throws {
        let client = try networkSource("MerianNetworkClient.swift")
        let inventories = [
            "ScanEnrichment": ["updateDeferredScanContext", "fetchEnrichment"],
            "Exports": ["requestDwcAExport"],
            "ProductFeedback": ["submitFeedbackSurvey", "submitCommunityFeedback"]
        ]
        for (owner, methods) in inventories {
            let contents = try networkSource("Endpoints/MerianNetworkClient+\(owner).swift")
            let expression = try NSRegularExpression(pattern: #"(?m)^    func ([A-Za-z0-9_]+)\("#)
            let matches = expression.matches(in: contents, range: NSRange(contents.startIndex..., in: contents))
            let names = try matches.map { String(contents[try #require(Range($0.range(at: 1), in: contents))]) }
            #expect(names.count == methods.count && Set(names) == Set(methods))
            #expect(contents.split(separator: "\n", omittingEmptySubsequences: false).count <= 600)
            for name in methods { #expect(!client.contains("func \(name)(")) }
            for token in ["URLSession", "SupabaseManager", "Task", "static let shared", "endpointURL(",
                          "performAuthenticatedRequest(", "catch", "@escaping"] {
                #expect(!contents.contains(token), "Endpoint owners must not acquire \(token)")
            }
            #expect(contents.range(
                of: #"(?m)^    (?:private )?(?:static )?(?:let|var)\s"#, options: .regularExpression
            ) == nil)
        }
        for method in ["buildIdentifyRequest", "identifyMultiModal",
                       "shareScanToExplore", "requestCommunityIdentification",
                       "recoverMissingOwnedCloudScan", "restoreExploreMediaObjectKeys"] {
            #expect(client.contains("func \(method)("), "Keep larger workflow ownership unchanged: \(method)")
        }
        let storage = try networkSource("Endpoints/MerianNetworkClient+MediaStorage.swift")
        let uploads = try networkSource("Media/MerianNetworkClient+MediaUploads.swift")
        #expect(storage.contains("func generateUploadURLs(") && !client.contains("func generateUploadURLs("))
        #expect(uploads.contains("func uploadToR2(") && !client.contains("func uploadToR2("))
    }

    @Test func enrichmentKeepsConfigurationSerializationKeyAndDecoderOrder() throws {
        let endpoint = try networkSource("Endpoints/MerianNetworkClient+ScanEnrichment.swift")
        let enrichment = try method("fetchEnrichment", in: endpoint)
        try expectOrder([
            #"try validateEndpointConfiguration("enrich-scan")"#,
            "let payload:", "try Self.validateJSONPayload(payload)",
            "try JSONSerialization.data(withJSONObject: payload)",
            "UUID(uuidString: scanId)?.uuidString.lowercased()", "throw MerianError.invalidResponse",
            "try await performAuthenticatedPreparedJSONPost(", "idempotencyKey: idempotencyKey",
            "try JSONDecoder().decode(EnrichScanResponse.self, from: data)"
        ], in: enrichment)
        for field in ["scan_id", "scientific_name", "confidence_score", "inference_tier", "scope"] {
            #expect(enrichment.contains("\"\(field)\":"))
        }
        #expect(!endpoint.contains("keyDecodingStrategy") && !endpoint.contains("UUID()"))
        let generated = try source("apps/ios/Merian/Core/AI/InferenceEdgeDTOs.swift")
        #expect(generated.contains("struct EnrichScanResponse: Codable"))
        #expect(!endpoint.contains("struct EnrichScanResponse"))
    }

    @Test func contextNoOpAndAllFourOptionalFieldsKeepTheirBoundary() throws {
        let endpoint = try networkSource("Endpoints/MerianNetworkClient+ScanEnrichment.swift")
        let context = try method("updateDeferredScanContext", in: endpoint)
        try expectOrder([
            #"try validateEndpointConfiguration("update-scan-context")"#,
            "var payload:", "guard payload.count > 1 else { return }",
            "try Self.validateJSONPayload(payload)", "try await performAuthenticatedJSONPost(",
            "timeoutInterval: 15"
        ], in: context)
        for field in ["gpsElevation", "weatherCondition", "weatherTemperatureF", "locationName"] {
            #expect(context.contains("telemetry.\(field)"))
        }
        for token in ["gpsLatitude", "gpsLongitude", "trimmingCharacters", "idempotencyKey", "checkCancellation"] {
            #expect(!context.contains(token))
        }
        let caller = try source("apps/ios/Merian/Features/Capture/Submission/Services/CaptureSubmissionDeferredContextService.swift")
        try expectOrder(["persistLocally(scanId, telemetry)", "try await endpoint.update", "try await waitBeforeRetry()"], in: caller)
        #expect(endpoint.contains("JSONSerialization.isValidJSONObject(payload)"))
        #expect(endpoint.contains("throw CocoaError(.propertyListReadCorrupt)"))
    }

    @Test func exportAndFeedbackKeepExistingEncodingAndFeatureModelOwnership() throws {
        let export = try networkSource("Endpoints/MerianNetworkClient+Exports.swift")
        #expect(export.contains(#"scope: String = "personal""#))
        #expect(export.contains(#"["exportScope": scope, "includePreciseCoordinates": true]"#))
        #expect(export.contains("try await performAuthenticatedJSONPost(") && export.contains("timeoutInterval: 15.0"))
        #expect(!export.contains("JSONDecoder") && !export.contains("idempotencyKey"))
        let feedback = try networkSource("Endpoints/MerianNetworkClient+ProductFeedback.swift")
        #expect(feedback.components(separatedBy: "_ = try await performAuthenticatedEncodedJSONPost(").count == 3)
        #expect(feedback.components(separatedBy: "timeoutInterval: 30").count == 3)
        try expectOrder(["let submission = CommunityFeedbackSubmission(feedback: feedback)",
                         "_ = try await performAuthenticatedEncodedJSONPost("],
                        in: method("submitCommunityFeedback", in: feedback))
        #expect(!feedback.contains("trimmingCharacters") && !feedback.contains("JSONDecoder"))
        #expect(!feedback.contains("struct FeedbackSurveySubmission") && !feedback.contains("struct CommunityFeedbackSubmission"))
        let models = try source("apps/ios/Merian/Features/Profile/Settings/Feedback/Models/FeedbackSurveyModels.swift")
        #expect(models.contains("struct FeedbackSurveySubmission: Encodable"))
        #expect(try networkSource("ExploreAPIModels.swift").contains("struct CommunityFeedbackSubmission: Encodable"))
    }

    @Test func preparedBodyBridgeDoesNotWidenTransportOrAddPolicy() throws {
        let client = try networkSource("MerianNetworkClient.swift")
        let bridge = try method("performAuthenticatedPreparedJSONPost", in: client)
        try expectOrder(["try endpointURL(function)", "try await performAuthenticatedRequest(", "body: body",
                         "timeoutInterval: timeoutInterval", "idempotencyKey: idempotencyKey", "return data"], in: bridge)
        #expect(bridge.contains("timeoutInterval: TimeInterval = 30.0") && bridge.contains("idempotencyKey: String? = nil"))
        #expect(bridge.components(separatedBy: "performAuthenticatedRequest(").count == 2)
        for token in ["JSONEncoder", "JSONDecoder", "JSONSerialization", "catch", "Task", "URLSession",
                      "SupabaseManager", "@escaping", "isRetry:", "expectedAuthUserID:"] {
            #expect(!bridge.contains(token), "Prepared-body bridge must not add \(token)")
        }
        for token in ["private var activeSession", "private lazy var session", "private func endpointURL(",
                      "private func performAuthenticatedRequest(", "private func performAuthenticatedTransport(",
                      "private func acquireAccountWorkLeaseIfRequired("] {
            #expect(client.contains(token))
        }
    }

    @Test func rehomedEndpointTestsLeaveFeaturePolicyAndSharedAuthInPlace() throws {
        let aggregate = try source("apps/ios/MerianTests/Core/Network/MerianNetworkClientTests.swift")
        let survey = try source("apps/ios/MerianTests/Features/Profile/Settings/Feedback/FeedbackSurveyTests.swift")
        let inventories = [
            "ScanEnrichmentEndpointTests": ["testDeferredContextUpdateUsesOwnerScanEndpoint",
                                           "testFetchEnrichmentSuccessfullyConstructsPayloadAndParsesJSON",
                                           "testFetchEnrichmentRejectsNonUUIDScanIdInsteadOfMintingANewQuotaKey"],
            "ExportEndpointTests": ["testRequestDwcAExport"],
            "ProductFeedbackEndpointTests": ["submitFeedbackSurveyEncodesSurveyPayload"]
        ]
        for (suite, methods) in inventories {
            let contents = try source("apps/ios/MerianTests/Core/Network/Endpoints/\(suite).swift")
            for name in methods {
                #expect(contents.contains("func \(name)(") && !aggregate.contains("func \(name)(") && !survey.contains("func \(name)("))
            }
            #expect(contents.contains("NetworkEndpointFixture()"))
            #expect(!contents.contains("MerianNetworkClient.shared") && !contents.contains("MockURLProtocol.mockEndpoints"))
        }
        for name in ["promptPolicyRequiresForegroundCompletionOnboardingAndMeaningfulUse",
                     "promptPolicySuppressesDismissedOrSubmittedCampaign", "submittedStateExpiresAfterRepeatSubmissionCooldown"] {
            #expect(survey.contains("func \(name)("))
        }
        #expect(!survey.contains("MerianNetworkClient") && !survey.contains("MockURLProtocol") && !survey.contains("sharedProcessState"))
        #expect(aggregate.contains("func testEdgeFunctionSelfHealingRefreshesInvalidSessionBeforeRetry("))
    }

    private func method(_ name: String, in contents: String) throws -> String {
        let start = try #require(contents.range(of: "    func \(name)("))
        let end = try #require(contents.range(of: "\n    }", range: start.upperBound..<contents.endIndex))
        return String(contents[start.lowerBound..<end.upperBound])
    }

    private func expectOrder(_ tokens: [String], in contents: String) throws {
        var position = contents.startIndex
        for token in tokens {
            let match = try #require(contents.range(of: token, range: position..<contents.endIndex))
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
