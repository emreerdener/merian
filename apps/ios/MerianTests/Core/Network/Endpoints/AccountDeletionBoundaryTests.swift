import Foundation
import Testing

@Suite("Account Deletion Architecture")
struct AccountDeletionBoundaryTests {
    @Test func wireOperationsHaveFocusedOwnersWithoutAcquiringWorkflowState() throws {
        let client = try networkSource("MerianNetworkClient.swift")
        let endpoint = try networkSource("Endpoints/MerianNetworkClient+AccountDeletion.swift")
        let names = ["safeDeleteAccount", "prepareAccountDeletionRecoveryV2", "commitPreparedAccountDeletionV2",
                     "recoverAcceptedAccountDeletion", "recoverPreparedAccountDeletionV2", "acknowledgeAccountDeletionRecoveryV2"]
        let regex = try NSRegularExpression(pattern: #"(?m)^    func ([A-Za-z0-9_]+)\("#)
        let matches = regex.matches(in: endpoint, range: NSRange(endpoint.startIndex..., in: endpoint))
        let actual = try matches.map { String(endpoint[try #require(Range($0.range(at: 1), in: endpoint))]) }
        #expect(actual.sorted() == names.sorted())
        for name in names { #expect(!client.contains("func \(name)(")) }
        for token in ["SupabaseManager", "URLSession", "Keychain", "UserDefaults", "ScanRepository", "Task", "catch",
                      "endpointURL(", "performAuthenticatedRequest(", "activeSession", "@escaping", "static let shared"] {
            #expect(!endpoint.contains(token), "Endpoint must not own \(token)")
        }
        for path in ["Endpoints/MerianNetworkClient+AccountDeletion.swift", "AccountDeletionAPIModels.swift",
                     "AccountDeletionRecoveryValidation.swift", "Decoding/AccountDeletionResponseDecoder.swift"] {
            #expect(try networkSource(path).split(separator: "\n", omittingEmptySubsequences: false).count <= 600)
        }
        for declaration in [
            "private let sessionTransport: PinnedNetworkTransport",
            "private let authenticatedTransport: AuthenticatedTransportDispatcher",
            "private func endpointURL(",
            "private func performAuthenticatedRequest(",
            "private func performPublicAccountDeletionRecoveryRequest("
        ] {
            #expect(client.contains(declaration))
        }
    }

    @Test func fixedRouteBridgesPreserveConstructionAndOwnerOrderWithoutExposingTransport() throws {
        let client = try networkSource("MerianNetworkClient.swift")
        let intake = try method("func performAccountDeletionJSONPost(", in: client)
        let recovery = try method("func performAccountDeletionRecoveryJSONPost(", in: client)
        #expect(intake.contains("ownedBy authTransitionOwner: AuthTransitionToken?"))
        #expect(intake.contains("body: () throws -> Data?"))
        try expectOrder([#"endpointURL("safe-delete")"#, "let bodyData = try body()", "performAuthenticatedRequest(",
                         "body: bodyData", "authTransitionOwner: authTransitionOwner", "return (data, response.statusCode)"], in: intake)
        #expect(recovery.contains("body: () throws -> Data"))
        try expectOrder([#"endpointURL("recover-account-deletion")"#, "let bodyData = try body()",
                         "performPublicAccountDeletionRecoveryRequest(", "body: bodyData", "return (data, response.statusCode)"], in: recovery)
        for bridge in [intake, recovery] {
            #expect(bridge.contains("-> (data: Data, statusCode: Int)"))
            for token in ["catch", "Task", "@escaping", "URLSession", "SupabaseManager", "isRetry", "idempotencyKey"] {
                #expect(!bridge.contains(token))
            }
        }
    }

    @Test func legacyAndVersionTwoValidationRetainDifferentFailurePrecedence() throws {
        let endpoint = try networkSource("Endpoints/MerianNetworkClient+AccountDeletion.swift")
        let legacy = try method("func safeDeleteAccount(", in: endpoint)
        try expectOrder(["performAccountDeletionJSONPost(ownedBy: authTransitionOwner)", "if let recoveryCapability",
                         "isValidAccountDeletionRecoveryCapability", "return try recoveryCapability.map",
                         "AccountDeletionIntakePayload", "AccountDeletionResponseDecoder.decode", "Account deletion accepted."], in: legacy)
        let preparation = try method(
            "func prepareAccountDeletionRecoveryV2(",
            in: endpoint
        )
        try expectOrder(
            [
                "isValidAccountDeletionRecoveryCapability",
                "performAccountDeletionJSONPost(ownedBy: authTransitionOwner)",
                "JSONEncoder().encode",
                "AccountDeletionResponseDecoder.decodePreparation"
            ],
            in: preparation
        )
        let commit = try method(
            "func commitPreparedAccountDeletionV2(",
            in: endpoint
        )
        try expectOrder(
            [
                "isValidAccountDeletionRecoveryCapability",
                "performAccountDeletionJSONPost(ownedBy: authTransitionOwner)",
                "JSONEncoder().encode",
                "AccountDeletionResponseDecoder.decode"
            ],
            in: commit
        )
        #expect(endpoint.contains("recoveryCapability != acknowledgementCapability"))
        let legacyRecovery = try method("func recoverAcceptedAccountDeletion(", in: endpoint)
        let recovery = try method("private func performAccountDeletionRecoveryV2(", in: endpoint)
        for operation in [legacyRecovery, recovery] {
            try expectOrder(["isValidAccountDeletionRecoveryCapability", "performAccountDeletionRecoveryJSONPost",
                             "JSONEncoder().encode", "AccountDeletionResponseDecoder.decode"], in: operation)
        }
        #expect(recovery.contains(#"recoveryCapability: operation == "recover" ? capability : nil"#))
        #expect(recovery.contains(#"acknowledgementCapability: operation == "acknowledge" ? capability : nil"#))
    }

    @Test func publicRecoveryRetainsItsPrivateBoundedRetryAndCancellationPolicy() throws {
        let client = try networkSource("MerianNetworkClient.swift")
        let transport = try method("private func performPublicAccountDeletionRecoveryRequest(", in: client)
        try expectOrder(["try Task.checkCancellation()", "cachePolicy: .reloadIgnoringLocalCacheData", "timeoutInterval: 20",
                         #"forHTTPHeaderField: "Content-Type""#, #"forHTTPHeaderField: "Accept""#,
                         #"request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")"#, "request.httpBody = body",
                         "sessionTransport.data(for: request)", "catch let urlError as URLError", "try Task.checkCancellation()",
                         "transientCodes.contains(urlError.code), !isRetry", "Task.sleep(for: .seconds(2))", "isRetry: true",
                         "throw urlError", "try Task.checkCancellation()", "data.count <= 64 * 1024",
                         "response as? HTTPURLResponse", "httpResponse.statusCode == 200", "httpResponse.statusCode >= 500, !isRetry",
                         "Task.sleep(for: .seconds(2))", "isRetry: true", "throw MerianError.httpError"], in: transport)
        for token in [".timedOut", ".networkConnectionLost", ".cannotConnectToHost", ".dnsLookupFailed", ".notConnectedToInternet"] {
            #expect(transport.contains(token))
        }
        for token in ["Authorization", "getValidAuthHeaders", "refresh", "idempotencyKey", "accountWorkLease"] {
            #expect(!transport.contains(token))
        }
    }

    @Test func modelsAndCompatibilityValidationDoNotGainDurableAuthority() throws {
        let client = try networkSource("MerianNetworkClient.swift")
        let endpoint = try networkSource("Endpoints/MerianNetworkClient+AccountDeletion.swift")
        let models = try networkSource("AccountDeletionAPIModels.swift")
        let validation = try networkSource("AccountDeletionRecoveryValidation.swift")
        for type in ["enum AccountDeletionStatus:", "struct AccountDeletionReceipt:",
                     "struct AccountDeletionPreparationReceipt:", "struct AccountDeletionPreparationPayload:",
                     "struct AccountDeletionCommitPayload:"] {
            #expect(models.contains(type) && !client.contains(type))
        }
        #expect(models.contains("let manualProviderRevocationRequired: Bool\n"))
        let preparationReceiptStart = try #require(
            models.range(of: "struct AccountDeletionPreparationReceipt:")
        )
        let preparationPayloadStart = try #require(
            models.range(of: "struct AccountDeletionPreparationPayload:")
        )
        let preparationReceipt = models[
            preparationReceiptStart.lowerBound..<preparationPayloadStart.lowerBound
        ]
        #expect(
            !preparationReceipt.contains(
                "manualProviderRevocationRequired"
            )
        )
        #expect(!models.contains("init(from decoder:"))
        for type in ["AccountDeletionIntakePayload", "AccountDeletionRecoveryPayload", "AccountDeletionRecoveryV2Payload"] {
            #expect(endpoint.contains("private struct \(type): Encodable"))
            #expect(!client.contains("struct \(type):"))
        }
        for suffix in ["Capability", "Expiry", "Timestamp"] {
            #expect(endpoint.contains("static func isValidAccountDeletionRecovery\(suffix)("))
            #expect(endpoint.contains("AccountDeletionRecoveryValidation.isValid\(suffix)(value)"))
        }
        try expectOrder(["guard let date = recoveryDate(value)", "return date > now().addingTimeInterval(-5 * 60)"], in: validation)
        try expectOrder(["value.utf8.count >= 20", "value.utf8.count <= 40", "DateUtilities.iso8601FractionalFormatter",
                         "DateUtilities.iso8601Formatter"], in: validation)
        for path in ["AccountDeletionAPIModels.swift", "AccountDeletionRecoveryValidation.swift", "Decoding/AccountDeletionResponseDecoder.swift"] {
            let pure = try networkSource(path)
            for token in ["Keychain", "UserDefaults", "URLSession", "SupabaseManager", "MerianNetworkClient", "Task"] {
                #expect(!pure.contains(token) || token == "Keychain" && pure.contains("not Keychain"))
            }
        }
    }

    @Test func testRehomesLeaveAuthAndDurableWorkflowSuitesInTheirExistingOwners() throws {
        let aggregate = try source("apps/ios/MerianTests/Core/Network/MerianNetworkClientTests.swift")
        let owners = [
            "Endpoints/AccountDeletionEndpointTests.swift": ["testSafeDeleteAccountEndpoint", "testSafeDeleteBindsExactRecoveryCapability",
                                                             "testSafeDeleteAccountRejectsMissingProviderRevocationDisposition"],
            "Endpoints/AccountDeletionRecoveryEndpointTests.swift": ["testPreparedDeletionRecoverySeparatesRecoveryAndAcknowledgementProofs",
                "testAccountDeletionRecoveryUsesOnlyPublicCapability", "testAcknowledgedDeletionRecoveryRemainsReplayableAfterExpiry",
                "testAccountDeletionRecoveryRejectsMalformedCapabilityBeforeIO"],
            "Decoding/AccountDeletionAPIModelsTests.swift": ["testPreparedAccountDeletionPayloadsUseExactTwoStageProtocol"]
        ]
        for (path, names) in owners {
            let test = try source("apps/ios/MerianTests/Core/Network/\(path)")
            for name in names { #expect(test.contains("func \(name)(") && !aggregate.contains("func \(name)(")) }
            #expect(!test.contains("MerianNetworkClient.shared") && !test.contains("MockURLProtocol.mockEndpoints"))
        }
        let retryPolicy = try source(
            "apps/ios/MerianTests/Core/Network/Transport/AuthenticatedRequestRetryPolicyTests.swift"
        )
        #expect(retryPolicy.contains("func testUnauthorizedRefreshStaysInsideItsAuthTransitionOwner("))
        #expect(!aggregate.contains("func testUnauthorizedRefreshStaysInsideItsAuthTransitionOwner("))
        #expect(aggregate.contains("func testEdgeFunctionSelfHealingRefreshesInvalidSessionBeforeRetry("))
        let manager = try networkSource("SupabaseManager.swift")
        #expect(manager.contains("prepareAccountDeletionRecoveryV2(") && manager.contains("commitPreparedAccountDeletionV2("))
    }

    @Test func recoveryResultsStayBoundToTheExactTransitionSession() throws {
        let manager = try networkSource("SupabaseManager.swift")
        let immediateDeletion = try section(
            beginningWith: "    func deleteCurrentAccount(",
            endingBefore: "\n    /// An account-deletion barrier",
            in: manager
        )
        let versionTwoRecovery = try section(
            beginningWith:
                "    private func resumeCapabilityBackedAccountDeletionV2(",
            endingBefore:
                "\n    private func resumeCapabilityBackedAccountDeletion(",
            in: manager
        )
        let legacyRecovery = try section(
            beginningWith:
                "    private func resumeCapabilityBackedAccountDeletion(",
            endingBefore: "\n    private func performLocalSignOut(",
            in: manager
        )

        for workflow in [
            immediateDeletion,
            versionTwoRecovery,
            legacyRecovery
        ] {
            #expect(!workflow.contains("ownsAuthTransition(transition)"))
        }

        try expectOrder(
            [
                "verifyPreparationContext:",
                "currentSessionMatchesAuthTransition(transition)",
                "verifyCommitContext:",
                "currentSessionMatchesAuthTransition(transition)",
                "verifyResultContext:",
                "currentSessionMatchesAuthTransition(",
                "recoverDeletionV2(",
                "currentSessionMatchesAuthTransition(transition)",
                "acknowledgeRecovery:",
                "currentSessionMatchesAuthTransition(transition)"
            ],
            in: immediateDeletion
        )
        try expectOrder(
            [
                "receipt = try await recoverDeletion(",
                "currentSessionMatchesAuthTransition(transition)",
                "} catch {",
                "currentSessionMatchesAuthTransition(transition)",
                "acknowledgeRecovery:",
                "currentSessionMatchesAuthTransition(transition)"
            ],
            in: versionTwoRecovery
        )
        try expectOrder(
            [
                "receipt = try await requestDeletion(",
                "} catch {",
                "currentSessionMatchesAuthTransition(transition)",
                "receipt = try await recoverDeletion(capability, false)",
                "currentSessionMatchesAuthTransition(transition)",
                "} catch {",
                "currentSessionMatchesAuthTransition(transition)",
                "acknowledgeRecovery:",
                "currentSessionMatchesAuthTransition(transition)"
            ],
            in: legacyRecovery
        )
    }

    @Test func restoredDeletionBarrierCommitsBeforeLifecycleReadiness() throws {
        let manager = try networkSource("SupabaseManager.swift")
        let workflow = try networkSource(
            "Auth/Coordinators/AccountDeletionWorkflow.swift"
        )
        let restoration = try section(
            beginningWith:
                "    private func restoreDeferredCachedSessionAndResolveDeletionBarrier(",
            endingBefore: "\n    /// Resumes the local half",
            in: manager
        )

        #expect(restoration.components(separatedBy: "await ").count == 2)
        #expect(!restoration.contains("ensureTelemetryLinkedWhenSafe"))
        #expect(!restoration.contains("EntitlementManager.shared"))
        try expectOrder(
            [
                "adoptCachedSession:",
                "validateCachedSession:",
                "resolveCleanup:",
                "publishCachedSession:"
            ],
            in: workflow
        )
    }

    private func method(_ declaration: String, in source: String) throws -> String {
        let start = try #require(source.range(of: "    \(declaration)"))
        let end = try #require(source.range(of: "\n    }", range: start.upperBound..<source.endIndex))
        return String(source[start.lowerBound..<end.upperBound])
    }

    private func section(
        beginningWith beginning: String,
        endingBefore ending: String,
        in source: String
    ) throws -> String {
        let start = try #require(source.range(of: beginning))
        let end = try #require(
            source.range(
                of: ending,
                range: start.upperBound..<source.endIndex
            )
        )
        return String(source[start.lowerBound..<end.lowerBound])
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
