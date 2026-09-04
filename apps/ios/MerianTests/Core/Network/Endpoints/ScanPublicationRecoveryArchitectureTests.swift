import Foundation
import Testing

@Suite("Scan Publication and Recovery Architecture")
struct ScanPublicationRecoveryArchitectureTests {
    @Test func directEndpointsOwnOnlyRequestMappingAndResponseValidation() throws {
        let endpoint = try networkSource(
            "Endpoints/MerianNetworkClient+ScanPublication.swift"
        )
        let client = try networkSource("MerianNetworkClient.swift")
        let declarations = try methodNames(in: endpoint)

        #expect(declarations == [
            "shareScanToExplore", "requestCommunityIdentification"
        ])
        #expect(endpoint.split(separator: "\n", omittingEmptySubsequences: false).count <= 600)
        #expect(endpoint.components(separatedBy: "performAuthenticatedJSONPost(").count == 3)
        #expect(endpoint.components(separatedBy: "validateEndpointConfiguration(").count == 3)
        #expect(endpoint.components(separatedBy: "decodingFailure: .invalidResponse").count == 3)
        #expect(!client.contains("func shareScanToExplore("))
        #expect(!client.contains("func requestCommunityIdentification("))
        for token in [
            "URLSession", "SupabaseManager", "AppDIContainer", "Task {",
            "Task.detached", "FileManager", "performAuthenticatedRequest(",
            "endpointURL(", "uploadToR2("
        ] {
            #expect(!endpoint.contains(token), "Endpoint owner must not acquire \(token)")
        }
    }

    @Test func recoveryOwnerContainsOrchestrationAndKeepsItsHelpersPrivate() throws {
        let recovery = try networkSource(
            "Recovery/MerianNetworkClient+OwnedScanRecovery.swift"
        )
        let client = try networkSource("MerianNetworkClient.swift")
        let declarations = try methodNames(in: recovery)
        let persistenceWait = try method(
            "private func waitForScanPersistence(",
            in: recovery
        )

        #expect(declarations == [
            "shareScanToExplore", "requestCommunityIdentification",
            "ensureCloudScanAvailableForFieldChat"
        ])
        #expect(recovery.split(separator: "\n", omittingEmptySubsequences: false).count <= 600)
        #expect(recovery.contains("private struct ScanPublicationSnapshot"))
        #expect(recovery.contains("private enum ScanPersistenceProbeResult"))
        #expect(recovery.contains("private struct ExploreCloudSpeciesIdRow"))
        #expect(
            recovery.contains(
                ") async throws -> ScanPersistenceProbeResult"
            )
        )
        #expect(
            recovery.components(
                separatedBy: "switch try await waitForScanPersistence"
            ).count == 4
        )
        #expect(
            persistenceWait.components(
                separatedBy: "try Task.checkCancellation()"
            ).count == 5
        )
        #expect(persistenceWait.contains("try await Task.sleep(nanoseconds: delay)"))
        #expect(!persistenceWait.contains("try? await Task.sleep(nanoseconds: delay)"))
        #expect(
            persistenceWait.contains(
                "\n            try Task.checkCancellation()\n            if status.isFound {"
            )
        )
        for helper in [
            "waitForScanPersistence", "recoverMissingOwnedCloudScan",
            "makeOwnedScanRecoveryPayload", "resolveCloudSpeciesId",
            "normalizedScanGeoprivacy", "normalizedEcologyType",
            "normalizedInferenceTier", "normalizedConfidence",
            "normalizedUserReviewState"
        ] {
            #expect(recovery.contains("private func \(helper)("))
            #expect(!client.contains("func \(helper)("))
        }
        for token in [
            "URLSession", "performAuthenticatedRequest(", "endpointURL(",
            "generateUploadURLs(", "uploadToR2(", "FileManager"
        ] {
            #expect(!recovery.contains(token), "Recovery owner must not acquire \(token)")
        }
    }

    @Test func mediaRestoreHasOneImmutableBoundaryAndPrivateMechanics() throws {
        let restorer = try networkSource(
            "Media/ScanPublicationMediaRestorer.swift"
        )
        let policy = try networkSource(
            "Media/ScanPublicationMediaRestorePolicy.swift"
        )
        let client = try networkSource("MerianNetworkClient.swift")

        #expect(restorer.split(separator: "\n", omittingEmptySubsequences: false).count <= 600)
        #expect(policy.split(separator: "\n", omittingEmptySubsequences: false).count <= 600)
        #expect(restorer.contains("struct PreparedScanPublicationMediaRestore"))
        #expect(restorer.contains("fileprivate let source:"))
        #expect(restorer.contains("fileprivate let plan:"))
        #expect(restorer.contains("private struct ScanPublicationMediaRestorePlan"))
        #expect(restorer.contains("private let client: MerianNetworkClient"))
        for helper in [
            "restoreImageObjectKeys", "restoreVideoObjectKeys",
            "restoreAudioObjectKeys", "resolveRestorableImagePaths",
            "resolveRestorableVideoPaths", "resolveRestorableAudioPaths",
            "existingUniquePaths", "localFileURL", "imageMimeType"
        ] {
            #expect(restorer.contains("private func \(helper)("))
        }
        for oldGlobal in [
            "func validateExploreRestoreMediaBudget(",
            "func validateExploreRestoreMediaPayload(",
            "func makeScanShareRestoreUploadFile("
        ] {
            #expect(!client.contains(oldGlobal))
            #expect(!restorer.contains(oldGlobal))
        }
        #expect(policy.contains("enum ScanPublicationMediaRestorePolicy"))
        for method in [
            "shouldAttemptRestore", "shouldRestoreImages", "validateBudget",
            "validatePayload", "makeUploadFile"
        ] {
            #expect(policy.contains("static func \(method)("))
        }
    }

    @Test func recoveryPayloadPolicyAndAuthBridgeHaveNarrowOwners() throws {
        let payload = try networkSource(
            "Recovery/OwnedScanRecoveryPayload.swift"
        )
        let policy = try networkSource(
            "Recovery/OwnedScanRecoveryPolicy.swift"
        )
        let client = try networkSource("MerianNetworkClient.swift")

        #expect(payload.contains("struct OwnedScanRecoveryPayload: Encodable, Sendable"))
        #expect(payload.contains("case userId = \"user_id\""))
        #expect(policy.contains("enum MissingScanRecoveryAction"))
        #expect(policy.contains("enum OwnedScanRecoveryPolicy"))
        #expect(policy.contains("static func action("))
        #expect(!client.contains("struct OwnedScanRecoveryPayload"))
        #expect(!client.contains("enum MissingScanRecoveryAction"))

        let bridge = try method(
            "func authenticatedUserIDForOwnedScanRecovery()",
            in: client
        )
        #expect(bridge.contains("async throws -> UUID"))
        #expect(
            bridge.contains(
                "try await authenticatedTransport.requestPayloadAuthUserID()"
            )
        )
        for token in [
            "SupabaseManager", "URLSession", "Task", "@escaping", "catch",
            "performAuthenticatedRequest("
        ] {
            #expect(!bridge.contains(token), "Auth value bridge must not acquire \(token)")
        }
        #expect(
            client.contains(
                "private let authenticatedTransport: AuthenticatedTransportDispatcher"
            )
        )
    }

    @Test func publicationTestsFollowTheirProductionOwners() throws {
        let aggregate = try testSource("MerianNetworkClientTests.swift")
        let endpoint = try testSource(
            "Endpoints/ScanPublicationEndpointTests.swift"
        )
        let transport = try testSource(
            "Endpoints/ScanPublicationEndpointTransportTests.swift"
        )
        let recovery = try testSource(
            "Recovery/OwnedScanRecoveryPolicyTests.swift"
        )
        let media = try testSource(
            "Media/ScanPublicationMediaRestorePolicyTests.swift"
        )
        let ownership = [
            (endpoint, [
                "testExploreShareSendsStableAIIdempotencyKey",
                "testExploreShareRejectsContradictorySuccessResponses",
                "testExploreShareSendsMissingScanRecoveryPayload",
                "testCommunityRequestSendsStableAIIdempotencyKey",
                "testCommunityRequestRejectsUnconfirmedSuccessResponse"
            ]),
            (transport, [
                "testExploreShareRetriesPlatformFunctionRouteNotFound",
                "testCancelledExploreShareUsesCanonicalCancellationAndDoesNotReplay",
                "testExploreShareDoesNotRetryHandlerOwnedNotFound",
                "testCancelledPersistencePollPropagatesWithoutAnotherStatusRequest"
            ]),
            (recovery, [
                "testExploreCloudScanRestoreUsesStableNotFoundCodeWithLegacyFallback",
                "testFieldChatCloudPreflightRejectsMismatchedRecordIdentity",
                "testMissingScanRecoveryNeverRacesActiveOrRetryableIngestion"
            ]),
            (media, [
                "testExploreRestoreMediaBudgetRejectsPartialStagingBeforeUpload"
            ])
        ]
        for (owner, tests) in ownership {
            for test in tests {
                #expect(owner.contains("func \(test)("))
                #expect(!aggregate.contains("func \(test)("))
            }
        }
        for owner in [endpoint, transport] {
            #expect(owner.contains("NetworkEndpointFixture()"))
            #expect(!owner.contains("MerianNetworkClient.shared"))
            #expect(!owner.contains("MockURLProtocol.mockEndpoints"))
        }
    }

    private func methodNames(in source: String) throws -> [String] {
        let regex = try NSRegularExpression(
            pattern: #"(?m)^    func ([A-Za-z0-9_]+)\("#
        )
        return try regex.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).map { match in
            String(source[try #require(Range(match.range(at: 1), in: source))])
        }
    }

    private func method(_ declaration: String, in source: String) throws -> String {
        let start = try #require(source.range(of: "    \(declaration)"))
        let end = try #require(
            source.range(of: "\n    }", range: start.upperBound..<source.endIndex)
        )
        return String(source[start.lowerBound..<end.upperBound])
    }

    private func networkSource(_ path: String) throws -> String {
        try source("apps/ios/Merian/Core/Network/\(path)")
    }

    private func testSource(_ path: String) throws -> String {
        try source("apps/ios/MerianTests/Core/Network/\(path)")
    }

    private func source(_ path: String) throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private func repositoryRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        while directory.path != "/" {
            if FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("project.yml").path
            ) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
