import Foundation
import Testing

@Suite("Inference Network Architecture")
struct InferenceNetworkArchitectureTests {
    @Test func endpointPayloadMediaAndPolicyHaveFocusedOwners() throws {
        let endpoint = try networkSource(
            "Endpoints/MerianNetworkClient+Inference.swift"
        )
        let builder = try networkSource("Inference/InferencePayloadBuilder.swift")
        let media = try networkSource("Inference/InferenceMediaPolicy.swift")
        let models = try networkSource("Inference/InferenceRequestModels.swift")
        let policy = try networkSource("Inference/InferenceRequestPolicy.swift")
        let client = try networkSource("MerianNetworkClient.swift")

        for contents in [endpoint, builder, media, models, policy] {
            #expect(
                contents.split(separator: "\n", omittingEmptySubsequences: false).count <= 600
            )
        }
        for method in [
            "prewarmInferenceEndpoint", "buildIdentifyRequest", "analyzeSubject",
            "buildMultiModalRequest", "identifyMultiModal"
        ] {
            #expect(endpoint.contains("func \(method)("))
            #expect(!client.contains("func \(method)("))
        }
        #expect(endpoint.contains("static func buildMultiModalRequestBody("))
        #expect(!client.contains("static func buildMultiModalRequestBody("))
        #expect(builder.contains("enum InferencePayloadBuilder"))
        #expect(media.contains("enum InferenceMediaPolicy"))
        #expect(models.contains("struct InferencePayloadContext: Sendable"))
        #expect(models.contains("struct AuthenticatedInferenceRequest: Sendable"))
        #expect(policy.contains("enum InferenceRequestPolicy"))

        for contents in [builder, media, models, policy] {
            for token in [
                "URLSession", "SupabaseManager", "ConsentManager", "AppDIContainer",
                "Task {", "Task.detached", "static let shared"
            ] {
                #expect(!contents.contains(token), "Stateless inference owners must not acquire \(token)")
            }
        }
        for token in [
            "URLSession.shared", "URLSession(configuration:", "SupabaseManager",
            "activeSession", "endpointURL(",
            "makeAuthenticatedJSONRequest(", "performAuthenticatedRequest(",
            "Task.detached"
        ] {
            #expect(!endpoint.contains(token), "Inference endpoint must not acquire \(token)")
        }
        #expect(
            endpoint.components(separatedBy: "DetachedWork.value(").count - 1 == 3
        )
        #expect(
            endpoint.components(
                separatedBy: "category: .inferenceRequestPreparation"
            ).count - 1 == 3
        )
        #expect(!models.contains("var "))
        #expect(!builder.contains("var context"))
        #expect(!media.contains("imageBase64s + audioBase64s"))
    }

    @Test func narrowBridgesKeepSessionAuthAndRetryImplementationPrivate() throws {
        let client = try networkSource("MerianNetworkClient.swift")
        let dispatcher = try networkSource(
            "Transport/AuthenticatedTransportDispatcher.swift"
        )
        for declaration in [
            "private let sessionTransport: PinnedNetworkTransport",
            "private let authenticatedTransport: AuthenticatedTransportDispatcher",
            "private func endpointURL(",
            "private func performAuthenticatedRequest("
        ] {
            #expect(client.contains(declaration), "Transport boundary widened: \(declaration)")
        }
        for declaration in [
            "func makeAuthenticatedJSONRequest(",
            "func requestPayloadAuthUserID(",
            "private func acquireAccountWorkLeaseIfRequired(",
            "private func applyingAuthHeaders("
        ] {
            #expect(
                dispatcher.contains(declaration),
                "Authenticated dispatcher lost \(declaration)"
            )
        }

        let bridges = [
            "authenticatedUserIDForInferenceRequest": [
                "authenticatedTransport.requestPayloadAuthUserID()"
            ],
            "performInferenceTransportPrewarm": [
                "endpointURL(\"identify-multimodal\")",
                "sessionTransport.data(for: request)"
            ],
            "makeAuthenticatedInferenceURLRequest": [
                "endpointURL(function)",
                "authenticatedTransport.makeAuthenticatedJSONRequest("
            ],
            "performAuthenticatedInferenceJSONPost": [
                "endpointURL(function)", "performAuthenticatedRequest("
            ],
            "performAuthenticatedInferenceRequest": [
                "authenticatedRequest.expectedAuthUserID", "performAuthenticatedRequest("
            ]
        ]
        for (name, requiredTokens) in bridges {
            let contents = try method(name, in: client)
            for token in requiredTokens {
                #expect(contents.contains(token), "\(name) must retain \(token)")
            }
            for token in ["catch", "Task.detached", "Task {", "JSONDecoder"] {
                #expect(!contents.contains(token), "Inference bridge must not add \(token)")
            }
        }
    }

    @Test func focusedTestsReplaceTheAggregateInferenceInventory() throws {
        let aggregate = try source(
            "apps/ios/MerianTests/Core/Network/MerianNetworkClientTests.swift"
        )
        let inventories = [
            (
                "apps/ios/MerianTests/Core/Network/Endpoints/InferenceEndpointTransportTests.swift",
                [
                    "testInferencePrewarmUsesPinnedClientSessionAndOptionsRoute",
                    "testIdentifyMultiModalSignalsWhenInlineRequestBodyIsSent",
                    "queueBackedIdentifyReturnsFirstTransportFailureWithoutInlineReplay",
                    "queueLessIdentifyRetainsOneReviewedInlineTransportReplay",
                    "testIdentifyMultiModalStopsBeforeDispatchWhenConsentIsMissing",
                    "testIdentifyMultiModalMapsServerConsentRejectionToDisclosureError",
                    "testAnalyzeSubjectSuccessfullyConstructsPayloadAndParsesJSON",
                    "testAnalyzeSubjectRejectsOversizedInlineImagePayloadBeforeNetwork"
                ]
            ),
            (
                "apps/ios/MerianTests/Core/Network/Inference/InferenceRequestPolicyTests.swift",
                [
                    "authenticatedInferenceRequestRemainsBoundToOriginalAuthSession",
                    "inferenceObjectKeysMustBelongToExactRequestAccount",
                    "testRecoverableInferenceConflictRequiresKnown409Code"
                ]
            ),
            (
                "apps/ios/MerianTests/Core/Network/Inference/InferencePayloadBuilderTests.swift",
                [
                    "multimodalRequestBodyUsesActiveCamelCaseTelemetryContract",
                    "multimodalRequestBodyIncludesPublicLocationLabelWhenDerivable",
                    "multimodalRequestBodyCarriesStagedAudioR2KeysWithoutInlineAudio",
                    "multimodalRequestBodyCarriesCanonicalAudioDescriptionTimeline",
                    "multimodalRequestBodyCarriesVideoKeysAndOrderedFrameCount",
                    "multimodalRequestBodyCarriesVideoAudioMetadata",
                    "multimodalRequestBodyCarriesStillImageFocusWithoutAdditionalMedia"
                ]
            ),
            (
                "apps/ios/MerianTests/Core/Network/Inference/InferenceMediaPolicyTests.swift",
                [
                    "budgetValidationPassesWhenUnderLimit",
                    "budgetValidationPassesWhenBothArraysEmpty",
                    "budgetValidationPassesAtExactLimit",
                    "budgetValidationThrowsOneByteOverLimit",
                    "budgetValidationThrowsWhenImagesAloneExceedLimit",
                    "budgetValidationThrowsWhenCombinedImagesAndAudioExceedLimit",
                    "budgetValidationAccumulatesAcrossMultipleImages",
                    "inlineAudioBudgetValidationRejectsOversizedFileBeforeEncoding"
                ]
            )
        ]

        for (path, names) in inventories {
            let focused = try source(path)
            for name in names {
                #expect(focused.contains("func \(name)("))
                #expect(!aggregate.contains("func \(name)("))
            }
        }
    }

    private func method(_ name: String, in contents: String) throws -> String {
        let start = try #require(contents.range(of: "    func \(name)("))
        let end = try #require(
            contents.range(of: "\n    }", range: start.upperBound..<contents.endIndex)
        )
        return String(contents[start.lowerBound..<end.upperBound])
    }

    private func networkSource(_ path: String) throws -> String {
        try source("apps/ios/Merian/Core/Network/\(path)")
    }

    private func source(_ path: String) throws -> String {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
            directory.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
