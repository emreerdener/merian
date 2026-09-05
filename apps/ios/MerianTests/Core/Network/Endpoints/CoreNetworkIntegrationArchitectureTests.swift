import Foundation
import Testing

@Suite("Core Network Integration Architecture")
struct CoreNetworkIntegrationArchitectureTests {
    @Test func endpointOwnerInventoryIsCompleteAndNonOverlapping() throws {
        let endpointRoot = try networkRoot().appendingPathComponent("Endpoints")
        let actualFilenames = try Set(
            FileManager.default.contentsOfDirectory(
                at: endpointRoot,
                includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension == "swift" }
            .map(\.lastPathComponent)
        )

        #expect(actualFilenames == Self.endpointOwnerFilenames)

        let aggregate = try networkSource("MerianNetworkClient.swift")
        var ownersByMethod: [String: Set<String>] = [:]
        for filename in actualFilenames {
            let owner = try networkSource("Endpoints/\(filename)")
            #expect(owner.contains("extension MerianNetworkClient"))

            for method in try endpointEntryPointNames(in: owner) {
                ownersByMethod[method, default: []].insert(filename)
                #expect(
                    !aggregate.contains("func \(method)("),
                    "\(method) must have one production owner outside the transport aggregate"
                )
            }
        }
        #expect(
            ownersByMethod.values.allSatisfy { $0.count == 1 },
            "An endpoint method name appears in more than one endpoint owner"
        )
    }

    @Test func extractedOwnersStayBelowTheReviewCeiling() throws {
        let root = try networkRoot()
        for directoryName in [
            "Endpoints", "Inference", "Media", "Recovery", "Transport"
        ] {
            let directory = root.appendingPathComponent(directoryName)
            for file in try swiftFiles(below: directory) {
                let source = try String(contentsOf: file, encoding: .utf8)
                #expect(
                    lineCount(source) <= 600,
                    "\(file.lastPathComponent) exceeded the Core Network review ceiling"
                )
            }
        }

        let aggregate = try networkSource("MerianNetworkClient.swift")
        #expect(
            lineCount(aggregate) <= 600,
            "The Core Network facade exceeded the shared review ceiling"
        )
    }

    @Test func transportAndLiveDependenciesKeepTheirReviewedOwners() throws {
        let sources = try networkSources()

        expectOwners(
            containing: "URLSession(",
            in: sources,
            equal: ["Transport/PinnedNetworkTransport.swift"]
        )
        expectOwners(
            containing: "PinnedNetworkTransport()",
            in: sources,
            equal: ["MerianNetworkClient.swift"]
        )
        expectOwners(
            containing: "private final class MerianTLSDelegate",
            in: sources,
            equal: ["Transport/PinnedNetworkTransport.swift"]
        )
        expectOwners(
            containing: "private final class MerianRequestUploadDelegate",
            in: sources,
            equal: ["Transport/AuthenticatedTransportDispatcher.swift"]
        )
        expectOwners(
            containing: "performAuthenticatedRequest(",
            in: sources,
            equal: ["MerianNetworkClient.swift"]
        )
        expectOwners(
            containing: "/functions/v1/",
            in: sources,
            equal: ["Transport/EdgeFunctionRoutePolicy.swift"]
        )
        expectOwners(
            containing:
                "AuthenticatedRequestRetryPolicy.canReplayAfterAmbiguousFailure(",
            in: sources,
            equal: ["Transport/AuthenticatedRequestExecutor.swift"]
        )
        expectOwners(
            containing: "private func endpointURL(",
            in: sources,
            equal: ["MerianNetworkClient.swift"]
        )
        expectOwners(
            containing: "SupabaseManager.shared",
            in: sources,
            equal: [
                "Inference/InferenceIdentificationReviewService.swift",
                "Recovery/MerianNetworkClient+OwnedScanRecovery.swift",
                "Transport/AuthenticatedRequestExecutor.swift",
                "Transport/AuthenticatedTransportDispatcher.swift"
            ]
        )
        expectOwners(
            containing: "AppDIContainer.shared",
            in: sources,
            equal: [
                "Endpoints/MerianNetworkClient+Inference.swift",
                "Recovery/MerianNetworkClient+OwnedScanRecovery.swift",
                "SupabaseManager.swift"
            ]
        )
        expectOwners(
            containing: "ConsentManager.shared",
            in: sources,
            equal: [
                "Endpoints/MerianNetworkClient+Inference.swift",
                "Transport/AuthenticatedRequestExecutor.swift",
                "SupabaseManager.swift"
            ]
        )
        expectOwners(
            containing: ".from(\"",
            in: sources,
            equal: [
                "Inference/InferenceIdentificationReviewService.swift",
                "Recovery/MerianNetworkClient+OwnedScanRecovery.swift",
                "SupabaseManager.swift"
            ]
        )
        expectOwners(
            containing: ".rpc(",
            in: sources,
            equal: ["Inference/InferenceIdentificationReviewService.swift"]
        )
        expectOwners(
            containing: "DetachedWork.value(",
            in: sources,
            equal: ["Endpoints/MerianNetworkClient+Inference.swift"]
        )
        #expect(sources.values.allSatisfy { !$0.contains("Task.detached") })
    }

    @Test func ambiguousReplayPolicyIsExplicitAndDisjoint() throws {
        let retryPolicy = try networkSource(
            "Transport/AuthenticatedRequestRetryPolicy.swift"
        )
        let safeReads = try stringSet(
            named: "safelyReplayableReadFunctionNames",
            in: retryPolicy
        )
        let idempotencyAware = try stringSet(
            named: "idempotencyAwareFunctionNames",
            in: retryPolicy
        )

        #expect(safeReads == Self.safelyReplayableReadFunctionNames)
        #expect(idempotencyAware == Self.idempotencyAwareFunctionNames)
        #expect(safeReads.isDisjoint(with: idempotencyAware))
        #expect((safeReads.union(idempotencyAware)).allSatisfy {
            $0.range(of: #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#, options: .regularExpression) != nil
        })

        let endpointSources = try networkSources().filter {
            $0.key.hasPrefix("Endpoints/")
        }
        for functionName in safeReads.union(idempotencyAware) {
            let owners = Set(endpointSources.compactMap { path, source in
                source.contains("\"\(functionName)\"") ? path : nil
            })
            #expect(
                owners.count == 1,
                "Replay policy route \(functionName) must have exactly one endpoint owner; found \(owners.sorted())"
            )
        }
    }

    @Test func transportOwnersHaveFocusedBoundariesAndRehomedTests() throws {
        let transportRoot = try networkRoot().appendingPathComponent("Transport")
        let actualProductionFiles = try Set(
            FileManager.default.contentsOfDirectory(
                at: transportRoot,
                includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension == "swift" }
            .map(\.lastPathComponent)
        )
        #expect(actualProductionFiles == Self.transportOwnerFilenames)

        let client = try networkSource("MerianNetworkClient.swift")
        let executor = try networkSource(
            "Transport/AuthenticatedRequestExecutor.swift"
        )
        let errorPolicy = try networkSource(
            "Transport/EdgeFunctionErrorPolicy.swift"
        )
        let routePolicy = try networkSource(
            "Transport/EdgeFunctionRoutePolicy.swift"
        )
        let retryPolicy = try networkSource(
            "Transport/AuthenticatedRequestRetryPolicy.swift"
        )
        let dispatcher = try networkSource(
            "Transport/AuthenticatedTransportDispatcher.swift"
        )
        let pinnedTransport = try networkSource(
            "Transport/PinnedNetworkTransport.swift"
        )

        #expect(errorPolicy.contains("enum EdgeFunctionErrorPolicy"))
        #expect(routePolicy.contains("struct EdgeFunctionRouteResponseEvidence"))
        #expect(routePolicy.contains("enum EdgeFunctionRoutePolicy"))
        #expect(retryPolicy.contains("enum AuthenticatedRequestRetryPolicy"))
        #expect(retryPolicy.contains("enum UnauthorizedRefreshTarget"))
        #expect(retryPolicy.contains("static func unauthorizedRefreshTarget("))
        #expect(executor.contains("struct AuthenticatedRequestExecutor"))
        #expect(executor.contains("struct Dependencies"))
        #expect(executor.contains("struct AttemptState"))
        #expect(executor.contains("case .ordinary:"))
        #expect(executor.contains("case let .transitionOwned(owner):"))
        #expect(executor.contains("ownedBy: owner"))
        #expect(dispatcher.contains("final class AuthenticatedTransportDispatcher"))
        #expect(dispatcher.contains("private let sessionTransport: PinnedNetworkTransport"))
        #expect(dispatcher.contains("private func applyingAuthHeaders("))
        #expect(dispatcher.contains("private final class MerianRequestUploadDelegate"))
        #expect(
            pinnedTransport.contains(
                "final class PinnedNetworkTransport: @unchecked Sendable"
            )
        )
        #expect(pinnedTransport.contains("private let sessionLock = NSLock()"))
        #expect(pinnedTransport.contains("private var productionSession: URLSession?"))
        #expect(pinnedTransport.contains("private func resolveProductionSessionLocked()"))
        #expect(!pinnedTransport.contains("lazy var"))
        #expect(pinnedTransport.contains("static func requiresPinning(host: String)"))
        #expect(pinnedTransport.contains("normalizedHost.hasSuffix(\".supabase.co\")"))
        #expect(
            pinnedTransport.contains(
                "let systemTrustIsValid = SecTrustEvaluateWithError(serverTrust, nil)"
            )
        )
        #expect(pinnedTransport.contains("systemTrustIsValid: systemTrustIsValid"))
        #expect(
            pinnedTransport.contains(
                "completionHandler(.cancelAuthenticationChallenge, nil)"
            )
        )
        #expect(
            pinnedTransport.components(
                separatedBy: "completionHandler(.cancelAuthenticationChallenge, nil)"
            ).count == 3
        )
        #expect(pinnedTransport.contains("private final class MerianTLSDelegate"))
        #expect(client.contains("private let sessionTransport: PinnedNetworkTransport"))
        #expect(
            client.contains(
                "private let authenticatedTransport: AuthenticatedTransportDispatcher"
            )
        )
        #expect(client.contains("AuthenticatedRequestExecutor("))
        #expect(client.contains("dependencies: .live("))
        #expect(
            client.components(separatedBy: "PinnedNetworkTransport()").count
                == 2
        )
        #expect(client.contains("self.sessionTransport = sessionTransport"))
        #expect(client.contains("sessionTransport: sessionTransport"))
        #expect(!dispatcher.contains("PinnedNetworkTransport()"))
        #expect(!pinnedTransport.contains("SupabaseManager"))
        for forbiddenToken in [
            "URLSession(configuration:", "URLSession.shared",
            "MerianNetworkClient", "static let shared", "Task.detached"
        ] {
            #expect(
                !executor.contains(forbiddenToken),
                "Authenticated executor acquired \(forbiddenToken)"
            )
        }
        for retiredDeclaration in [
            "struct EdgeFunctionRouteResponseEvidence",
            "private static let functionRouteRetryDelays",
            "private static let safelyReplayableReadFunctionNames",
            "private static let idempotencyAwareFunctionNames",
            "static func stableEdgeErrorCode",
            "performSessionRefreshForUnauthorizedRequest",
            "performPublicGETRequest("
        ] {
            #expect(!client.contains(retiredDeclaration))
        }
        for forbiddenToken in [
            "MerianTLSDelegate", "MerianRequestUploadDelegate",
            "URLSession(configuration:", "getValidAuthHeaders("
        ] {
            #expect(
                !client.contains(forbiddenToken),
                "The facade reacquired transport implementation: \(forbiddenToken)"
            )
        }
        for policy in [errorPolicy, routePolicy, retryPolicy] {
            for forbiddenToken in [
                "URLSession(", "URLSession.shared", "SupabaseManager.shared",
                "KeychainManager.shared", "static let shared", "Task {",
                "Task.detached", "@MainActor", " await ", " async"
            ] {
                #expect(
                    !policy.contains(forbiddenToken),
                    "Stateless transport policy acquired \(forbiddenToken)"
                )
            }
        }

        let aggregateTests = try source(
            "apps/ios/MerianTests/Core/Network/MerianNetworkClientTests.swift"
        )
        let sharedTransportSupport = try source(
            "apps/ios/MerianTests/Core/Network/NetworkTransportTestSupport.swift"
        )
        let inferencePolicyTests = try source(
            "apps/ios/MerianTests/Core/Network/Inference/InferenceRequestPolicyTests.swift"
        )
        let routeTests = try source(
            "apps/ios/MerianTests/Core/Network/Transport/EdgeFunctionRoutePolicyTests.swift"
        )
        let retryTests = try source(
            "apps/ios/MerianTests/Core/Network/Transport/AuthenticatedRequestRetryPolicyTests.swift"
        )
        let executorTests = try source(
            "apps/ios/MerianTests/Core/Network/Transport/AuthenticatedRequestExecutorTests.swift"
        )
        let dispatcherTests = try source(
            "apps/ios/MerianTests/Core/Network/Transport/AuthenticatedTransportDispatcherTests.swift"
        )
        let pinnedTransportTests = try source(
            "apps/ios/MerianTests/Core/Network/Transport/PinnedNetworkTransportTests.swift"
        )
        for declaration in [
            "class MockURLProtocol: URLProtocol",
            "final class ScopedMockURLProtocol: URLProtocol",
            "final class ScopedMockTransport"
        ] {
            #expect(sharedTransportSupport.contains(declaration))
            #expect(!aggregateTests.contains(declaration))
        }
        #expect(sharedTransportSupport.contains("private final class Registry"))
        #expect(sharedTransportSupport.contains("private let lock = NSLock()"))
        for name in [
            "testPlatformFunctionRouteClassifierPreservesGatewayHandlerBoundary"
        ] {
            #expect(routeTests.contains("func \(name)("))
            #expect(!aggregateTests.contains("func \(name)("))
        }
        for name in [
            "testUnauthorizedRecoveryOnlyRegeneratesAuthoritativelyMissingGuestSessions",
            "testUnauthorizedRefreshStaysInsideItsAuthTransitionOwner",
            "testAmbiguousFailureReplayIsLimitedToReadsAndIdempotentRequests"
        ] {
            #expect(retryTests.contains("func \(name)("))
            #expect(!aggregateTests.contains("func \(name)("))
        }
        let accountBindingTest =
            "authenticatedRetryChainNeverAdoptsReplacementAccount"
        #expect(retryTests.contains("func \(accountBindingTest)("))
        #expect(!inferencePolicyTests.contains("func \(accountBindingTest)("))
        for name in [
            "retryKeepsExactBodyAndInitiatingAccountBinding",
            "refreshableUnauthorizedAppliesOrdinaryRefreshAndRetriesOnce",
            "transitionOwnedUnauthorizedUsesItsExactRefreshTarget",
            "unavailableRouteUsesBoundedOneTwoFourSecondSchedule",
            "paymentRequiredRunsEntitlementRecoveryBeforeReturningHTTPError",
            "serverConsentRejectionClosesConsentGateWithoutRetry",
            "missingGuestSessionRegeneratesAndRetriesWithBoundAccount",
            "transientRetryNotifiesBodyReleaseForEachCompletedAttempt",
            "cancelledOwnerStopsBeforeIdentityOrTransportDispatch"
        ] {
            #expect(executorTests.contains("func \(name)("))
        }
        #expect(
            dispatcherTests.contains(
                "func injectedIdentityBuildsExactAuthenticatedPayloadBoundary("
            )
        )
        for name in [
            "productionConfigurationRetainsReviewedBounds",
            "testPinnedHashesAreNonEmptyValidBase64",
            "pinningMatchesOnlyTheSupabaseDomainBoundary",
            "concurrentFirstUseRetainsOneProductionSession",
            "testTLSChainWalkingAcceptsIntermediateCertWhenLeafIsUnknown",
            "testTLSChainWalkingRejectsUnknownChain",
            "injectedSessionOwnsTestDispatch"
        ] {
            #expect(pinnedTransportTests.contains("func \(name)("))
            #expect(!aggregateTests.contains("func \(name)("))
        }
        #expect(pinnedTransportTests.contains("systemTrustIsValid: false"))
    }

    private static let endpointOwnerFilenames: Set<String> = [
        "MerianNetworkClient+AccountDeletion.swift",
        "MerianNetworkClient+CommunityIdentification.swift",
        "MerianNetworkClient+ExploreBrowsing.swift",
        "MerianNetworkClient+ExploreInteractions.swift",
        "MerianNetworkClient+ExplorePostManagement.swift",
        "MerianNetworkClient+Exports.swift",
        "MerianNetworkClient+FieldChat.swift",
        "MerianNetworkClient+FieldTrips.swift",
        "MerianNetworkClient+Inference.swift",
        "MerianNetworkClient+MediaStorage.swift",
        "MerianNetworkClient+Notifications.swift",
        "MerianNetworkClient+ProductFeedback.swift",
        "MerianNetworkClient+PublicProfile.swift",
        "MerianNetworkClient+ScanEnrichment.swift",
        "MerianNetworkClient+ScanLifecycle.swift",
        "MerianNetworkClient+ScanPublication.swift",
        "MerianNetworkClient+SpeciesDictionary.swift"
    ]

    private static let transportOwnerFilenames: Set<String> = [
        "AuthenticatedRequestExecutor.swift",
        "AuthenticatedRequestRetryPolicy.swift",
        "AuthenticatedTransportDispatcher.swift",
        "EdgeFunctionErrorPolicy.swift",
        "EdgeFunctionRoutePolicy.swift",
        "PinnedNetworkTransport.swift"
    ]

    private static let safelyReplayableReadFunctionNames: Set<String> = [
        "check-public-username",
        "check-scan-status",
        "get-community-identification-activity",
        "get-community-identification-detail",
        "get-community-identification-feed",
        "get-explore-author-posts",
        "get-explore-author-profile",
        "get-explore-comment-replies",
        "get-explore-comments",
        "get-explore-composer-media",
        "get-explore-feed",
        "get-explore-hashtag-posts",
        "get-explore-map-points",
        "get-explore-media-incidents",
        "get-explore-mention-suggestions",
        "get-explore-notifications",
        "get-explore-post",
        "get-explore-post-detail",
        "get-explore-species-posts",
        "get-explore-unread-notification-count",
        "get-scan-explore-share-state",
        "search-community-taxa",
        "species-dictionary",
        "species-observation-stats"
    ]

    private static let idempotencyAwareFunctionNames: Set<String> = [
        "enrich-scan",
        "explore-post-chat",
        "identify",
        "identify-multimodal",
        "insight-chat",
        "request-community-identification",
        "share-scan-to-explore",
        "species-dictionary-chat",
        "update-explore-field-notes"
    ]

    private func endpointEntryPointNames(in source: String) throws -> [String] {
        let expression = try NSRegularExpression(
            pattern: #"(?m)^    (?:static )?func ([A-Za-z0-9_]+)\("#
        )
        return try expression.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).map { match in
            let range = try #require(Range(match.range(at: 1), in: source))
            return String(source[range])
        }
    }

    private func stringSet(named name: String, in source: String) throws
        -> Set<String> {
        let declaration = try #require(
            source.range(of: "private static let \(name): Set<String> = [")
        )
        let closingBracket = try #require(
            source.range(
                of: "\n    ]",
                range: declaration.upperBound..<source.endIndex
            )
        )
        let contents = String(
            source[declaration.upperBound..<closingBracket.lowerBound]
        )
        let expression = try NSRegularExpression(pattern: #"\"([^\"]+)\""#)
        return try Set(expression.matches(
            in: contents,
            range: NSRange(contents.startIndex..., in: contents)
        ).map { match in
            let range = try #require(Range(match.range(at: 1), in: contents))
            return String(contents[range])
        })
    }

    private func expectOwners(
        containing token: String,
        in sources: [String: String],
        equal expectedOwners: Set<String>
    ) {
        let actualOwners = Set(
            sources.compactMap { path, source in
                source.contains(token) ? path : nil
            }
        )
        #expect(actualOwners == expectedOwners, "Unexpected owner for \(token)")
    }

    private func networkSources() throws -> [String: String] {
        let root = try networkRoot()
        return try Dictionary(uniqueKeysWithValues: swiftFiles(below: root).map {
            let prefix = root.path + "/"
            let path = String($0.path.dropFirst(prefix.count))
            return (path, try String(contentsOf: $0, encoding: .utf8))
        })
    }

    private func swiftFiles(below root: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys
            )
        )
        var files: [URL] = []
        while let file = enumerator.nextObject() as? URL {
            guard file.pathExtension == "swift",
                  try file.resourceValues(forKeys: Set(keys)).isRegularFile
                    == true else {
                continue
            }
            files.append(file)
        }
        return files.sorted { $0.path < $1.path }
    }

    private func lineCount(_ source: String) -> Int {
        guard !source.isEmpty else { return 0 }
        let newlineDelimitedLines = source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).count
        return newlineDelimitedLines - (source.hasSuffix("\n") ? 1 : 0)
    }

    private func networkSource(_ path: String) throws -> String {
        try String(
            contentsOf: networkRoot().appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private func source(_ path: String) throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private func networkRoot() throws -> URL {
        try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Core/Network"
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
