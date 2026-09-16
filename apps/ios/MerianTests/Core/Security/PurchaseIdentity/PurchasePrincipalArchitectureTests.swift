import Foundation
import Testing

@Suite("Purchase Principal Architecture")
struct PurchasePrincipalArchitectureTests {
    @Test func purchaseIdentityOwnersStaySeparated() throws {
        let root = try repositoryRoot()
        let securityRoot = root.appendingPathComponent(
            "apps/ios/Merian/Core/Security"
        )
        let purchaseRoot = securityRoot.appendingPathComponent(
            "PurchaseIdentity"
        )
        let resolver = try source(
            at: securityRoot.appendingPathComponent(
                "PurchasePrincipalResolver.swift"
            )
        )
        let models = try source(
            at: purchaseRoot.appendingPathComponent(
                "Models/PurchasePrincipalModels.swift"
            )
        )
        let sessionModels = try source(
            at: purchaseRoot.appendingPathComponent(
                "Models/PurchaseIdentitySessionModels.swift"
            )
        )
        let wireModels = try source(
            at: purchaseRoot.appendingPathComponent(
                "Models/PurchasePrincipalWireModels.swift"
            )
        )
        let policies = try source(
            at: purchaseRoot.appendingPathComponent(
                "Policies/PurchasePrincipalPolicies.swift"
            )
        )
        let capabilityStore = try source(
            at: purchaseRoot.appendingPathComponent(
                "Stores/PurchasePrincipalCapabilityStore.swift"
            )
        )
        let secureStateStore = try source(
            at: purchaseRoot.appendingPathComponent(
                "Stores/PurchasePrincipalSecureStateStore.swift"
            )
        )
        let secureStore = try source(
            at: purchaseRoot.appendingPathComponent(
                "Stores/PurchasePrincipalSecureStore.swift"
            )
        )
        let remoteService = try source(
            at: purchaseRoot.appendingPathComponent(
                "Services/PurchasePrincipalRemoteService.swift"
            )
        )
        let liveRemoteService = try source(
            at: purchaseRoot.appendingPathComponent(
                "Services/PurchasePrincipalRemoteService+Live.swift"
            )
        )
        let legacyRemoteService = try source(
            at: purchaseRoot.appendingPathComponent(
                "Services/LegacyPurchaseHandoffRemoteService.swift"
            )
        )
        let profileService = try source(
            at: purchaseRoot.appendingPathComponent(
                "Services/LegacyPurchaseIdentityProfileService.swift"
            )
        )
        let liveProfileService = try source(
            at: purchaseRoot.appendingPathComponent(
                "Services/LegacyPurchaseIdentityProfileService+Live.swift"
            )
        )
        let sessionDependencies = try source(
            at: purchaseRoot.appendingPathComponent(
                "Coordinators/PurchaseIdentitySessionCoordinationDependencies.swift"
            )
        )
        let sessionCoordinator = try source(
            at: purchaseRoot.appendingPathComponent(
                "Coordinators/PurchaseIdentitySessionCoordinator.swift"
            )
        )
        let readinessCoordinator = try source(
            at: purchaseRoot.appendingPathComponent(
                "Coordinators/PurchaseIdentityReadinessCoordinator.swift"
            )
        )
        let handoffPreparationCoordinator = try source(
            at: purchaseRoot.appendingPathComponent(
                "Coordinators/PurchaseIdentityHandoffPreparationCoordinator.swift"
            )
        )
        let liveLegacyRemoteService = try source(
            at: purchaseRoot.appendingPathComponent(
                "Services/LegacyPurchaseHandoffRemoteService+Live.swift"
            )
        )
        let secureRandom = try source(
            at: purchaseRoot.appendingPathComponent(
                "Services/PurchasePrincipalSecureRandom.swift"
            )
        )
        let securitySources = try swiftFiles(below: securityRoot).map {
            try source(at: $0)
        }

        let actualPaths = try Set(
            swiftFiles(below: purchaseRoot).map {
                String($0.path.dropFirst(purchaseRoot.path.count + 1))
            }
        )
        #expect(actualPaths == Self.ownerPaths)

        let ownership: [(String, String)] = [
            ("enum PurchasePrincipalResolutionMode", models),
            ("struct PurchasePrincipalBinding", models),
            ("enum PurchasePrincipalResolverError", models),
            ("struct PrincipalRotationPreparation", models),
            ("struct PrincipalRotationCancellation", models),
            ("struct PurchaseIdentitySessionContext", sessionModels),
            ("struct PurchaseIdentitySessionSnapshot", sessionModels),
            ("struct PurchaseIdentityProviderState", sessionModels),
            ("struct PurchaseIdentityAccountWorkLease", sessionModels),
            ("enum PurchasePrincipalProtocol", wireModels),
            ("struct PurchasePrincipalResolveResponse", wireModels),
            ("struct PrincipalRotationPrepareResponse", wireModels),
            ("struct PrincipalRotationClaimResponse", wireModels),
            ("struct PrincipalRotationCancelResponse", wireModels),
            ("enum PurchasePrincipalCapabilityPolicy", policies),
            ("enum PurchasePrincipalBindingIntentPolicy", policies),
            ("enum PurchasePrincipalCompatibilityPolicy", policies),
            ("enum PurchasePrincipalTimestampPolicy", policies),
            ("enum PurchasePrincipalSecretPolicy", policies),
            ("struct PurchasePrincipalCapabilityStore", capabilityStore),
            ("struct PurchasePrincipalSecureStateStore", secureStateStore),
            ("protocol PurchasePrincipalSecureStore", secureStore),
            ("struct PurchasePrincipalRemoteService", remoteService),
            (
                "struct LegacyPurchaseHandoffRemoteService",
                legacyRemoteService
            ),
            (
                "struct LegacyPurchaseIdentityHandoffPreparation",
                legacyRemoteService
            ),
            ("struct LegacyPurchaseIdentityProfile", profileService),
            (
                "struct LegacyPurchaseIdentityProfileService",
                profileService
            ),
            (
                "struct PurchaseIdentitySessionStateBoundary",
                sessionDependencies
            ),
            (
                "struct PurchaseIdentitySessionProviderBoundary",
                sessionDependencies
            ),
            (
                "struct PurchaseIdentitySessionHandoffBoundary",
                sessionDependencies
            ),
            (
                "struct PurchaseIdentityEntitlementBoundary",
                sessionDependencies
            ),
            (
                "struct PurchaseIdentitySessionDependencies",
                sessionDependencies
            ),
            (
                "class PurchaseIdentitySessionCoordinator",
                sessionCoordinator
            ),
            (
                "struct PurchaseIdentityReadinessCoordinator",
                readinessCoordinator
            ),
            (
                "enum PurchaseHandoffPreparationError",
                handoffPreparationCoordinator
            ),
            (
                "struct PurchaseHandoffPreparationJournal",
                handoffPreparationCoordinator
            ),
            (
                "struct PurchaseHandoffPreparationOperations",
                handoffPreparationCoordinator
            ),
            (
                "struct PurchaseHandoffPreparationDependencies",
                handoffPreparationCoordinator
            ),
            (
                "struct PurchaseHandoffPreparationCoordinator",
                handoffPreparationCoordinator
            ),
            ("enum PurchasePrincipalSecureRandom", secureRandom),
            ("class PurchasePrincipalResolver", resolver)
        ]
        for (declaration, owner) in ownership {
            #expect(containsDeclaration(declaration, in: owner))
            #expect(
                securitySources.filter {
                    containsDeclaration(declaration, in: $0)
                }.count == 1
            )
        }

        #expect(!resolver.contains("import Supabase"))
        #expect(!resolver.contains("import Security"))
        #expect(!resolver.contains("functions.invoke"))
        #expect(!resolver.contains("KeychainManager.shared"))
        #expect(liveRemoteService.contains("import Supabase"))
        #expect(liveLegacyRemoteService.contains("import Supabase"))
        #expect(liveProfileService.contains("import Supabase"))
        #expect(!liveProfileService.contains(".shared"))
        #expect(liveProfileService.contains("private struct LegacyPurchaseIdentityProfileDTO"))
        #expect(liveProfileService.contains(".from(\"users\")"))
        #expect(
            liveProfileService.contains(
                "email,public_username,public_author_name,"
            )
        )
        #expect(
            occurrenceCount(
                of: "client.functions.invoke(",
                in: liveRemoteService
            ) == 4
        )
        #expect(
            occurrenceCount(
                of: "\"resolve-purchase-principal\"",
                in: liveRemoteService
            ) == 4
        )
        #expect(
            liveRemoteService.contains(
                "convenience init(\n        client: SupabaseClient,"
            )
        )
        for payload in [
            "PurchasePrincipalResolvePayload",
            "PrincipalRotationPreparePayload",
            "PrincipalRotationClaimPayload",
            "PrincipalRotationCancelPayload"
        ] {
            #expect(
                liveRemoteService.contains("private struct \(payload)")
            )
        }
        #expect(
            occurrenceCount(
                of: "client.functions.invoke(",
                in: liveLegacyRemoteService
            ) == 3
        )
        #expect(
            occurrenceCount(
                of: "\"transfer-signout-purchases\"",
                in: liveLegacyRemoteService
            ) == 3
        )
        for payload in [
            "LegacyPurchaseHandoffPreparePayload",
            "LegacyPurchaseHandoffPrepareResponse",
            "LegacyPurchaseHandoffContinuePayload",
            "LegacyPurchaseHandoffOperationResponse",
            "LegacyPurchaseHandoffBindResponse",
            "LegacyPurchaseHandoffErrorPayload"
        ] {
            #expect(
                liveLegacyRemoteService.contains("private struct \(payload)")
            )
        }
        for operation in ["prepare", "bind", "complete", "cancel"] {
            #expect(liveLegacyRemoteService.contains("\"\(operation)\""))
        }
        for forbiddenDependency in [
            "import Supabase", "functions.invoke", "KeychainManager",
            "RevenueCatManager", "EntitlementManager", "MerianLog"
        ] {
            #expect(!legacyRemoteService.contains(forbiddenDependency))
        }
        for coordinatorOwner in [
            sessionDependencies,
            sessionCoordinator,
            readinessCoordinator,
            handoffPreparationCoordinator,
            profileService
        ] {
            for forbiddenDependency in [
                "import Supabase", "RevenueCatManager", "EntitlementManager",
                "KeychainManager", "MerianLog", ".shared"
            ] {
                #expect(!coordinatorOwner.contains(forbiddenDependency))
            }
        }
        #expect(sessionCoordinator.contains("Task<PurchasePrincipalBinding?, Never>"))
        #expect(sessionCoordinator.contains("private struct ResolutionKey"))
        #expect(
            sessionDependencies.contains(
                "func loadAndPublishPendingState() throws -> Bool"
            )
        )
        #expect(sessionDependencies.contains("let pending = try loadPending()"))
        #expect(sessionDependencies.contains("setPending(pending)"))
        #expect(
            sessionCoordinator.contains(
                "dependencies.handoff.setPending(true)"
            )
        )
        #expect(readinessCoordinator.contains("let sessionCoordinator:"))

        for deterministicOwner in [models, wireModels, policies] {
            for forbiddenDependency in [
                "import Supabase",
                "import Security",
                "KeychainManager",
                "functions.invoke",
                "Task {"
            ] {
                #expect(!deterministicOwner.contains(forbiddenDependency))
            }
        }
        for store in [capabilityStore, secureStateStore, secureStore] {
            #expect(!store.contains("import Supabase"))
            #expect(!store.contains("functions.invoke"))
        }
        #expect(secureRandom.contains("SecRandomCopyBytes"))

        for file in try swiftFiles(below: purchaseRoot) {
            let lineCount = try source(at: file).split(
                separator: "\n",
                omittingEmptySubsequences: false
            ).count
            #expect(
                lineCount <= 250,
                "\(file.lastPathComponent) has \(lineCount) lines"
            )
        }
        let resolverLineCount = resolver.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).count
        #expect(resolverLineCount <= 300)

        let legacyRemoteServiceTests = try source(
            at: root.appendingPathComponent(
                "apps/ios/MerianTests/Core/Security/PurchaseIdentity/LegacyPurchaseHandoffRemoteServiceTests.swift"
            )
        )
        let sessionCoordinatorTests = try source(
            at: root.appendingPathComponent(
                "apps/ios/MerianTests/Core/Security/PurchaseIdentity/PurchaseIdentitySessionCoordinatorTests.swift"
            )
        )
        let readinessCoordinatorTests = try source(
            at: root.appendingPathComponent(
                "apps/ios/MerianTests/Core/Security/PurchaseIdentity/PurchaseIdentityReadinessCoordinatorTests.swift"
            )
        )
        let handoffPreparationCoordinatorTests = try source(
            at: root.appendingPathComponent(
                "apps/ios/MerianTests/Core/Security/PurchaseIdentity/PurchaseIdentityHandoffPreparationCoordinatorTests.swift"
            )
        )
        let profileServiceTests = try source(
            at: root.appendingPathComponent(
                "apps/ios/MerianTests/Core/Security/PurchaseIdentity/LegacyPurchaseIdentityProfileServiceTests.swift"
            )
        )
        let aggregateTests = try source(
            at: root.appendingPathComponent(
                "apps/ios/MerianTests/Core/Network/SupabaseManagerTests.swift"
            )
        )
        for testName in [
            "testInjectedOperationsPreserveTypedHandoffInputs",
            "testTerminalProofClassifierRejectsTransientAndUnknownFailures"
        ] {
            #expect(legacyRemoteServiceTests.contains("func \(testName)("))
        }
        #expect(
            sessionCoordinatorTests.contains(
                "@Suite(\"Purchase Identity Session Coordinator\")"
            )
        )
        #expect(
            sessionCoordinatorTests.contains(
                "sameContextSharesOneResolutionTask"
            )
        )
        #expect(
            sessionCoordinatorTests.contains(
                "supersededResolutionCannotPublishOverTheNewerTask"
            )
        )
        #expect(
            readinessCoordinatorTests.contains(
                "staleGenerationAfterEntitlementFailsFinalFence"
            )
        )
        #expect(
            handoffPreparationCoordinatorTests.contains(
                "stableRotationPersistsDraftBeforeRemoteAndPreparedAfter"
            )
        )
        #expect(
            handoffPreparationCoordinatorTests.contains(
                "cancellationAfterRemoteStillPersistsPreparedCheckpoint"
            )
        )
        #expect(
            profileServiceTests.contains(
                "injectedFetchPreservesTheExactAccountAndProjection"
            )
        )
        #expect(
            !aggregateTests.contains(
                "testPendingSignOutPurchaseProofIsDiscardedOnlyForTerminalCodes"
            )
        )
    }

    private static let ownerPaths: Set<String> = [
        "Coordinators/PurchaseIdentityHandoffPreparationCoordinator.swift",
        "Coordinators/PurchaseIdentityReadinessCoordinator.swift",
        "Coordinators/PurchaseIdentitySessionCoordinationDependencies.swift",
        "Coordinators/PurchaseIdentitySessionCoordinator.swift",
        "Models/PurchaseIdentityHandoffModels.swift",
        "Models/PurchaseIdentitySessionModels.swift",
        "Models/PurchasePrincipalModels.swift",
        "Models/PurchasePrincipalWireModels.swift",
        "Policies/PurchasePrincipalPolicies.swift",
        "Services/LegacyPurchaseHandoffRemoteService+Live.swift",
        "Services/LegacyPurchaseHandoffRemoteService.swift",
        "Services/LegacyPurchaseIdentityProfileService+Live.swift",
        "Services/LegacyPurchaseIdentityProfileService.swift",
        "Services/PurchasePrincipalRemoteService+Live.swift",
        "Services/PurchasePrincipalRemoteService.swift",
        "Services/PurchasePrincipalSecureRandom.swift",
        "Stores/PurchaseIdentityHandoffStore.swift",
        "Stores/PurchasePrincipalCapabilityStore.swift",
        "Stores/PurchasePrincipalSecureStateStore.swift",
        "Stores/PurchasePrincipalSecureStore.swift"
    ]

    private func source(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func swiftFiles(below root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw CocoaError(.fileReadUnknown)
        }
        return try enumerator.compactMap { item in
            guard let url = item as? URL,
                  url.pathExtension == "swift",
                  try url.resourceValues(forKeys: [.isRegularFileKey])
                    .isRegularFile == true else {
                return nil
            }
            return url
        }
    }

    private func containsDeclaration(
        _ declaration: String,
        in source: String
    ) -> Bool {
        let escapedDeclaration = NSRegularExpression.escapedPattern(
            for: declaration
        )
        let pattern =
            #"(?m)^\s*(?:(?:private|fileprivate|internal|package|public|final)\s+)*"#
            + escapedDeclaration
            + #"(?:\s*[:{])"#
        return source.range(of: pattern, options: .regularExpression) != nil
    }

    private func occurrenceCount(of value: String, in source: String) -> Int {
        source.components(separatedBy: value).count - 1
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        while candidate.path != "/" {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("project.yml").path
            ) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
