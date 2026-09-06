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
            "Auth", "Endpoints", "Inference", "Media", "Recovery", "Transport"
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

    @Test func authFoundationHasFocusedOwnersAndRehomedTests() throws {
        let authRoot = try networkRoot().appendingPathComponent("Auth")
        let prefix = authRoot.path + "/"
        let actualPaths = try Set(swiftFiles(below: authRoot).map {
            String($0.path.dropFirst(prefix.count))
        })
        #expect(actualPaths == Self.authFoundationPaths)

        let aggregate = try networkSource("SupabaseManager.swift")
        let models = try networkSource(
            "Auth/Models/SupabaseAuthTransitionModels.swift"
        )
        let presentationPolicy = try networkSource(
            "Auth/Policies/AccountPresentationPolicy.swift"
        )
        let transitionPolicy = try networkSource(
            "Auth/Policies/AuthTransitionPolicy.swift"
        )
        let deletionPolicy = try networkSource(
            "Auth/Policies/AccountDeletionTransitionPolicy.swift"
        )
        let coordinators = try networkSource(
            "Auth/Coordinators/AuthTransitionCoordinators.swift"
        )
        let deletionWorkflow = try networkSource(
            "Auth/Coordinators/AccountDeletionWorkflow.swift"
        )
        let purchaseSignOutWorkflow = try networkSource(
            "Auth/Coordinators/PurchaseIdentitySignOutWorkflow.swift"
        )
        let ghostMergePolicy = try networkSource(
            "Auth/Policies/GhostProfileMergePolicy.swift"
        )
        let ghostMergeWorkflow = try networkSource(
            "Auth/Coordinators/GhostProfileMergeWorkflow.swift"
        )

        for declaration in [
            "enum SupabaseAuthTransitionError",
            "enum AuthTransitionProvider",
            "enum AuthTransitionKind",
            "enum AuthTransitionPhase",
            "enum AuthSessionAdoption",
            "struct AuthTransitionSession",
            "struct AuthTransitionToken",
            "struct AuthTransitionState",
            "struct AccountBoundWorkLease"
        ] {
            #expect(models.contains(declaration))
            #expect(!aggregate.contains(declaration))
        }
        for signature in [
            "enum SupabaseAuthTransitionError: LocalizedError",
            "enum AuthTransitionProvider: String, Equatable, Sendable",
            "enum AuthTransitionKind: Equatable, Sendable",
            "enum AuthTransitionPhase: String, Equatable, Sendable",
            "enum AuthSessionAdoption: Equatable",
            "struct AuthTransitionSession: Equatable, Sendable",
            "struct AuthTransitionToken: Equatable, Sendable",
            "struct AuthTransitionState: Equatable, Sendable",
            "struct AccountBoundWorkLease: Equatable, Sendable"
        ] {
            #expect(models.contains(signature))
        }
        #expect(
            presentationPolicy.contains("enum AccountPresentationPolicy")
        )
        #expect(!aggregate.contains("enum AccountPresentationPolicy"))
        #expect(
            transitionPolicy.contains("@MainActor\nenum AuthTransitionPolicy")
        )
        let transitionPolicyFunctionNames: Set<String> = [
            "allowsAuthTransitionDuringAccountDeletionRecovery",
            "allowsAuthenticatedRequest",
            "shouldDeferAuthListenerSideEffects",
            "shouldAcceptAppleSignInCallback",
            "shouldClearOAuthSessionAfterFailure",
            "allowsOAuthMetadataMutation",
            "acceptsAuthenticationCallbackTarget",
            "acceptsLinkedIdentityUpgrade",
            "authSessionAdoption",
            "shouldDeferExternalIdentityLink",
            "shouldRestoreSourceIdentityAfterFailedSignOut"
        ]
        #expect(
            try staticFunctionNames(in: transitionPolicy)
                == transitionPolicyFunctionNames
        )
        for name in transitionPolicyFunctionNames {
            #expect(transitionPolicy.contains("func \(name)("))
            #expect(!aggregate.contains("func \(name)("))
        }
        #expect(
            transitionPolicy.contains(
                "nonisolated static func shouldRestoreSourceIdentityAfterFailedSignOut"
            )
        )
        #expect(
            deletionPolicy.contains(
                "@MainActor\nenum AccountDeletionTransitionPolicy"
            )
        )
        let deletionPolicyFunctionNames: Set<String> = [
            "canRestoreDeferredBarrierSession",
            "isDefinitiveIntakeRejection",
            "isAcceptedExpiredRecovery",
            "isUnknownRecovery"
        ]
        #expect(
            try staticFunctionNames(in: deletionPolicy)
                == deletionPolicyFunctionNames
        )
        for name in deletionPolicyFunctionNames {
            #expect(!aggregate.contains("func \(name)("))
        }
        #expect(
            deletionPolicy.contains(
                "nonisolated static func canRestoreDeferredBarrierSession"
            )
        )
        #expect(
            deletionWorkflow.contains("@MainActor\nenum AccountDeletionWorkflow")
        )
        let deletionWorkflowFunctionNames: Set<String> = [
            "restoreDeferredBarrierSession",
            "performDurableIntake",
            "performPreparedIntake",
            "performAcceptedCleanup",
            "performRecoveryRetirement",
            "retireRejectedRecoveryProof",
            "retireDefinitiveIntakeRejectionProof",
            "performDefinitiveIntakeRejectionRetirement",
            "performPendingLocalCleanup"
        ]
        #expect(
            try staticFunctionNames(in: deletionWorkflow)
                == deletionWorkflowFunctionNames
        )
        #expect(
            !deletionWorkflow.contains("= { true }"),
            "Deletion cleanup stages must remain explicit at every call site"
        )
        for name in deletionWorkflowFunctionNames {
            #expect(!aggregate.contains("func \(name)("))
        }
        for legacyName in [
            "canRestoreDeferredDeletionBarrierSession",
            "performDeferredDeletionBarrierSessionRestoration",
            "performDurableAccountDeletionIntake",
            "performPreparedAccountDeletionIntake",
            "isDefinitiveAccountDeletionIntakeRejection",
            "isAcceptedExpiredAccountDeletionRecovery",
            "isUnknownAccountDeletionRecovery",
            "performAcceptedAccountDeletionCleanup",
            "performAccountDeletionRecoveryRetirement",
            "performRejectedAccountDeletionRecoveryProofRetirement",
            "performRejectedAccountDeletionRecoveryRetirement",
            "performDefinitiveAccountDeletionIntakeRejectionProofRetirement",
            "performDefinitiveAccountDeletionIntakeRejectionRetirement",
            "performPendingAccountDeletionLocalCleanup"
        ] {
            #expect(!aggregate.contains("func \(legacyName)("))
        }
        #expect(
            purchaseSignOutWorkflow.contains(
                "@MainActor\nenum PurchaseIdentitySignOutWorkflow"
            )
        )
        let purchaseSignOutWorkflowFunctionNames: Set<String> = [
            "performUserSignOutTransition",
            "performPurchaseSafeSignOutTransition",
            "finalizeSignOutPurchaseHandoff"
        ]
        #expect(
            try staticFunctionNames(in: purchaseSignOutWorkflow)
                == purchaseSignOutWorkflowFunctionNames
        )
        for name in purchaseSignOutWorkflowFunctionNames {
            #expect(!aggregate.contains("static func \(name)("))
        }
        #expect(ghostMergePolicy.contains("enum GhostProfileMergePolicy"))
        let ghostMergePolicyFunctionNames: Set<String> = [
            "enqueuing",
            "shouldDiscardPendingHandoff"
        ]
        #expect(
            try staticFunctionNames(in: ghostMergePolicy)
                == ghostMergePolicyFunctionNames
        )
        for name in ghostMergePolicyFunctionNames {
            #expect(!aggregate.contains("static func \(name)("))
        }
        #expect(
            ghostMergeWorkflow.contains(
                "@MainActor\nenum GhostProfileMergeWorkflow"
            )
        )
        #expect(
            try staticFunctionNames(in: ghostMergeWorkflow)
                == ["finalizeHandoff"]
        )
        #expect(!aggregate.contains("static func finalizeHandoff("))
        for declaration in [
            "struct AccountBoundWorkCoordinator",
            "struct AuthTransitionCoordinator",
            "final class AuthTransitionSingleFlight"
        ] {
            #expect(coordinators.contains(declaration))
            #expect(!aggregate.contains(declaration))
        }

        for source in [
            models,
            presentationPolicy,
            transitionPolicy,
            deletionPolicy,
            coordinators,
            deletionWorkflow,
            purchaseSignOutWorkflow,
            ghostMergePolicy,
            ghostMergeWorkflow
        ] {
            for forbiddenToken in [
                "import AuthenticationServices", "import GoogleSignIn",
                "import RevenueCat", "import Supabase", ".shared",
                "Task.detached", "@unchecked Sendable", "nonisolated(unsafe)"
            ] {
                #expect(
                    !source.contains(forbiddenToken),
                    "Auth foundation acquired a forbidden construct: \(forbiddenToken)"
                )
            }
        }
        #expect(!models.contains("Task {"))
        #expect(!presentationPolicy.contains("Task {"))
        #expect(!transitionPolicy.contains("Task {"))
        #expect(!deletionPolicy.contains("Task {"))
        #expect(!deletionWorkflow.contains("Task {"))
        #expect(!purchaseSignOutWorkflow.contains("Task {"))
        #expect(!ghostMergePolicy.contains("Task {"))
        #expect(!ghostMergeWorkflow.contains("Task {"))
        #expect(!purchaseSignOutWorkflow.contains("MerianLog"))
        #expect(!ghostMergeWorkflow.contains("MerianLog"))
        #expect(
            coordinators.components(separatedBy: "Task {").count == 2,
            "Auth foundation must retain exactly one structured task owner"
        )
        #expect(
            coordinators.contains(
                "@MainActor\nfinal class AuthTransitionSingleFlight"
            )
        )
        #expect(coordinators.contains("private var task: Task<Bool, Never>?"))
        #expect(coordinators.contains("let task = Task { @MainActor in"))

        let foundationTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/AuthTransitionFoundationTests.swift"
        )
        let aggregateTests = try source(
            "apps/ios/MerianTests/Core/Network/SupabaseManagerTests.swift"
        )
        let policyTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/AuthTransitionPolicyTests.swift"
        )
        let deletionPolicyTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/AccountDeletionTransitionPolicyTests.swift"
        )
        let deletionIntakeTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/AccountDeletionIntakeWorkflowTests.swift"
        )
        let deletionCleanupTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/AccountDeletionCleanupWorkflowTests.swift"
        )
        let purchaseSignOutTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/PurchaseIdentitySignOutWorkflowTests.swift"
        )
        let ghostMergePolicyTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/GhostProfileMergePolicyTests.swift"
        )
        let ghostMergeErrorAdapterTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/GhostProfileMergeEndpointErrorAdapterTests.swift"
        )
        let ghostMergeWorkflowTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/GhostProfileMergeWorkflowTests.swift"
        )
        #expect(
            foundationTests.contains("private actor AuthTransitionTestGate")
        )
        #expect(!foundationTests.contains("SupabaseManagerTestGate"))
        for name in [
            "testBackgroundAccountWorkQuiescenceFailurePreservesProductLanguage",
            "testAuthTransitionCoordinatorSerializesAllSessionMutations",
            "testDoubleSignOutCallsShareOneTransitionOperationAndResult",
            "testSimultaneousAppleGoogleAndSignOutStartsHaveExactlyOneOwner",
            "testAuthTransitionCoordinatorRejectsStaleCallbacksAndSessions",
            "testAuthTransitionCoordinatorAdvancesOnlyForExpectedSignedOutEvent",
            "testAccountBoundWorkLeasesRemainSessionBoundUntilEveryLeaseFinishes",
            "testAccountPresentationPolicyShowsOnlyAnonymousUsersAsGuests"
        ] {
            #expect(foundationTests.contains("func \(name)("))
            #expect(!aggregateTests.contains("func \(name)("))
        }
        for name in [
            "testAuthSessionAdoptionDistinguishesRefreshFromSignOut",
            "testAppleCallbackRequiresMatchingControllerAndTransition",
            "testOAuthFailureClearsOnlyAChangedOrObservedSession",
            "testOAuthMetadataMutationRequiresTheExactTransitionSessionBeforeAndAfterUpdate",
            "testActiveTransitionOwnsListenerSideEffectsAndAuthenticatedRequests",
            "testFallbackAuthenticationCallbackNeverReplacesAnAnonymousOrDifferentAccount",
            "testLinkedIdentityUpgradeRequiresSameUUIDAndPermanentDestination",
            "testEveryDeletionRecoveryPhaseAdmitsOnlyItsOwnedTransition",
            "testEveryExternalIdentityLinkWaitsForPurchaseHandoffBinding",
            "testFailedSignOutRestoresOnlyTheExactUnfencedSourceAccount",
            "testNilSessionAndOwnerlessPolicyBoundariesRemainExplicit"
        ] {
            #expect(policyTests.contains("func \(name)("))
            #expect(!aggregateTests.contains("func \(name)("))
        }
        for name in [
            "testAccountDeletionTreatsOtherHTTPFailuresAsAmbiguous",
            "testOnlyMatchedExpiredRecoveryProvesDeletionWasAccepted",
            "testOnlyExactUnknownRecoveryIsClassified",
            "testDeletionBarrierRestoresOnlyTheExactCachedSourceSession"
        ] {
            #expect(deletionPolicyTests.contains("func \(name)("))
            #expect(!aggregateTests.contains("func \(name)("))
        }
        for name in [
            "testAccountDeletionRejectsPreflightCancellationBeforePersistence",
            "testAccountDeletionCancellationAfterPersistenceRetainsIntentWithoutDispatch",
            "testAccountDeletionPersistsIntentBeforeRequestAndRetainsAmbiguousFailure",
            "testAccountDeletionClearsIntentOnlyAfterDefinitiveClientRejection",
            "testAccountDeletionDoesNotDispatchWhenIntentPersistenceFails",
            "testAccountDeletionVerifiesTransitionContextAfterReceipt",
            "testAccountDeletionKeepsIntentWhenFailureContextIsStale",
            "testPreparedAccountDeletionPersistsMarkersBeforeCommit",
            "testPreparedAccountDeletionCancellationAfterPreparationStopsBeforeCommit",
            "testPreparedAccountDeletionCancellationAfterMarkersStopsBeforeCommit",
            "testPreparedAccountDeletionStopsBeforeCommitWhenPreparationCannotBecomeDurable",
            "testPreparedAccountDeletionRejectsStaleCommitContext",
            "testPreparedAccountDeletionRejectsStalePreparationFailureContext",
            "testPreparedAccountDeletionRejectsStaleCommitFailureContext"
        ] {
            #expect(deletionIntakeTests.contains("func \(name)("))
            #expect(!aggregateTests.contains("func \(name)("))
        }
        for name in [
            "testAcceptedAccountDeletionPersistsRecoveryBeforeSignOutAndClearsLast",
            "testAccountDeletionAcknowledgementFailureRetainsProofAndMarker",
            "testAccountDeletionRetirementReverifiesCleanupAndClearsProofBeforeMarker",
            "testRejectedAccountDeletionRetiresOnlyProof",
            "testDefinitiveDeletionRejectionPersistsRetirementBeforeProofRemoval",
            "testAccountDeletionKeepsRecoveryPendingWhenMarkerRemovalFails",
            "testFailedAccountDeletionPurgeLeavesRecoveryMarkerPending",
            "testAcceptedAccountDeletionDoesNotEraseLocalStateWhenRecoveryPersistenceFails",
            "testDeletionBarrierAdoptsCachedSessionBeforeMarkerRemovalAndPublication",
            "testDeletionBarrierKeepsMarkerWhenAdoptedSessionCannotBeRevalidated",
            "testDeletionBarrierDoesNotPublishWhenMarkerRemovalFails",
            "testPendingAccountDeletionSignsOutBeforePurgeAndResolvesLast"
        ] {
            #expect(deletionCleanupTests.contains("func \(name)("))
            #expect(!aggregateTests.contains("func \(name)("))
        }
        for name in [
            "testUserSignOutTransitionInitializesOneAnonymousSessionAfterSignOut",
            "testUserSignOutTransitionPropagatesAnonymousSessionFailure",
            "testUserSignOutTransitionRejectsPreflightCancellation",
            "testPurchaseSafeSignOutPersistsBeforeClosingAndCompletingIdentity",
            "testPurchaseSafeSignOutNeverClosesSessionWhenPreparationFails",
            "testPurchaseSafeSignOutRejectsPreflightCancellation",
            "testPurchaseSafeSignOutPropagatesDurableCompletionFailure",
            "testSignOutPurchaseFinalizationClearsProofOnlyAfterEveryCheck",
            "testSignOutPurchaseFinalizationRetainsProofAfterSyncFailure",
            "testSignOutPurchaseFinalizationRetainsProofAfterCancellation",
            "testSignOutPurchaseFinalizationRejectsPreflightCancellationBeforeBinding",
            "testSignOutPurchaseFinalizationRefusesStaleSessionBeforeProviderLink"
        ] {
            #expect(purchaseSignOutTests.contains("func \(name)("))
            #expect(!aggregateTests.contains("func \(name)("))
        }
        for name in [
            "replacementKeepsUnrelatedProofsInStableOrder",
            "terminalServerCodesAloneDiscardDurableProof"
        ] {
            #expect(ghostMergePolicyTests.contains("func \(name)("))
            #expect(!aggregateTests.contains("func \(name)("))
        }
        #expect(
            ghostMergeErrorAdapterTests.contains(
                "func testPendingMergeProofIsDiscardedOnlyForTerminalServerCodes("
            )
        )
        #expect(
            !aggregateTests.contains(
                "func testPendingMergeProofIsDiscardedOnlyForTerminalServerCodes("
            )
        )
        for name in [
            "testGhostHandoffClearsQueueOnlyAfterServerAndLocalCompletion",
            "testGhostHandoffRetainsQueueWhenServerOrLocalCompletionFails",
            "testGhostHandoffRemovalFailureRemainsRetryable",
            "testGhostHandoffRejectsPreflightCancellationBeforeServerWork",
            "testGhostHandoffRetainsProofAfterEachAsyncPhaseCancellation",
            "testGhostHandoffSessionFenceFailureStopsBeforeProviderWork"
        ] {
            #expect(ghostMergeWorkflowTests.contains("func \(name)("))
            #expect(!aggregateTests.contains("func \(name)("))
        }
    }

    @Test func ghostProfileMergeQueueHasOneSecureStorageOwner() throws {
        let manager = try networkSource("SupabaseManager.swift")
        let ghostMergeRoot = try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Core/Security/GhostProfileMerge"
        )
        let prefix = ghostMergeRoot.path + "/"
        let actualPaths = try Set(swiftFiles(below: ghostMergeRoot).map {
            String($0.path.dropFirst(prefix.count))
        })
        let models = try source(
            "apps/ios/Merian/Core/Security/GhostProfileMerge/Models/GhostProfileMergeModels.swift"
        )
        let store = try source(
            "apps/ios/Merian/Core/Security/GhostProfileMerge/Stores/GhostProfileMergeStore.swift"
        )
        let storeTests = try source(
            "apps/ios/MerianTests/Core/Security/GhostProfileMerge/GhostProfileMergeStoreTests.swift"
        )

        #expect(
            actualPaths == [
                "Models/GhostProfileMergeModels.swift",
                "Stores/GhostProfileMergeStore.swift"
            ]
        )
        for declaration in [
            "struct PendingGhostProfileMerge",
            "struct PendingGhostProfileMergeQueue"
        ] {
            #expect(models.contains(declaration))
            #expect(!manager.contains(declaration))
        }
        #expect(
            models.contains(
                "struct PendingGhostProfileMerge: Codable, Equatable, Sendable"
            )
        )
        #expect(
            models.contains(
                "struct PendingGhostProfileMergeQueue: Codable, Equatable, Sendable"
            )
        )
        #expect(
            models.components(separatedBy: "private enum CodingKeys").count
                == 3
        )
        for method in [
            "loadPendingHandoffs",
            "persistPendingHandoffs",
            "clearPendingHandoff",
            "clearPendingHandoffs"
        ] {
            #expect(store.contains("func \(method)("))
        }
        #expect(store.contains("struct Dependencies"))
        #expect(store.contains("@MainActor\nstruct GhostProfileMergeStore"))
        #expect(store.contains("enum GhostProfileMergeStoreError"))
        #expect(store.contains(".whenUnlockedThisDeviceOnly"))
        #expect(store.contains("try dependencies.loadData(key) == encoded"))
        #expect(store.contains("value.utf16.count"))
        #expect(store.contains("0x80...0x9F"))
        #expect(store.contains(#"^[A-Za-z0-9_-]{43}$"#))
        #expect(!store.contains("Date()"))
        #expect(store.contains("(20...40).contains(value.utf8.count)"))
        #expect(store.contains("DateUtilities.iso8601FractionalFormatter"))
        #expect(store.contains("DateUtilities.iso8601Formatter"))
        #expect(!store.contains("SupabaseAuthTransitionError"))
        #expect(manager.contains("GhostProfileMergeStore("))
        #expect(manager.contains("dependencies: .live(keychain: keychain)"))
        #expect(store.contains("KeychainKeys.pendingGhostProfileMerge"))
        #expect(!manager.contains("KeychainKeys.pendingGhostProfileMerge"))
        for forbiddenToken in [
            "import AuthenticationServices", "import GoogleSignIn",
            "import RevenueCat", "import Supabase", ".shared",
            "Task {", "Task.detached", "MerianLog"
        ] {
            #expect(
                !models.contains(forbiddenToken),
                "Ghost merge models acquired \(forbiddenToken)"
            )
            #expect(
                !store.contains(forbiddenToken),
                "Ghost merge store acquired \(forbiddenToken)"
            )
        }
        #expect(lineCount(models) <= 600)
        #expect(lineCount(store) <= 600)
        for testName in [
            "absentQueueRemainsAbsent",
            "queueRoundTripsWithDeviceOnlyAccessibility",
            "persistedFieldNamesRemainByteCompatible",
            "legacyRecordMigratesToVersionedQueue",
            "failedLegacyMigrationPreservesReadableProof",
            "malformedOrUnsupportedQueueFailsClosed",
            "invalidProofsAreRejectedBeforeSecureStorage",
            "serverOwnsExpiryClassification",
            "failedOrUnverifiedWriteFailsClosed",
            "clearingUsesExactCaseInsensitiveIdentifiers",
            "secureStoreFailuresPropagateWithoutBecomingAbsence"
        ] {
            #expect(storeTests.contains("@Test func \(testName)("))
        }
    }

    @Test func purchaseIdentityJournalsRetainOneSecureStorageOwner() throws {
        let manager = try networkSource("SupabaseManager.swift")
        let models = try source(
            "apps/ios/Merian/Core/Security/PurchaseIdentity/Models/PurchaseIdentityHandoffModels.swift"
        )
        let store = try source(
            "apps/ios/Merian/Core/Security/PurchaseIdentity/Stores/PurchaseIdentityHandoffStore.swift"
        )
        let storeTests = try source(
            "apps/ios/MerianTests/Core/Security/PurchaseIdentity/PurchaseIdentityHandoffStoreTests.swift"
        )

        for declaration in [
            "struct PendingSignOutPurchaseHandoff",
            "struct LegacyPrincipalRotation",
            "enum PrincipalRotationLocalState",
            "struct ServerPrincipalRotation",
            "enum PendingPurchasePrincipalAuthRotation"
        ] {
            #expect(models.contains(declaration))
            #expect(!manager.contains(declaration))
        }
        #expect(
            models.components(separatedBy: "private enum CodingKeys").count
                == 4
        )
        for method in [
            "loadPendingSignOutPurchaseHandoff",
            "persistPendingSignOutPurchaseHandoff",
            "clearPendingSignOutPurchaseHandoff",
            "loadPendingPurchasePrincipalAuthRotation",
            "persistPendingPurchasePrincipalAuthRotation",
            "clearPendingPurchasePrincipalAuthRotation"
        ] {
            #expect(store.contains("func \(method)("))
        }
        #expect(store.contains("struct Dependencies"))
        #expect(store.contains("@MainActor\nstruct PurchaseIdentityHandoffStore"))
        #expect(store.contains("enum PurchaseIdentityHandoffStoreError"))
        #expect(store.contains(".whenUnlockedThisDeviceOnly"))
        #expect(store.contains("try dependencies.loadData(key) == data"))
        #expect(!store.contains("SupabaseAuthTransitionError"))
        #expect(manager.contains("dependencies: .live(keychain: keychain)"))
        for keyOwner in [
            "KeychainKeys.pendingSignOutPurchaseHandoff",
            "KeychainKeys.pendingPurchasePrincipalAuthRotation"
        ] {
            #expect(store.contains(keyOwner))
            #expect(!manager.contains(keyOwner))
        }
        for forbiddenToken in [
            "import AuthenticationServices", "import GoogleSignIn",
            "import RevenueCat", "import Supabase", ".shared",
            "Task {", "Task.detached", "MerianLog"
        ] {
            #expect(
                !models.contains(forbiddenToken),
                "Purchase handoff models acquired \(forbiddenToken)"
            )
            #expect(
                !store.contains(forbiddenToken),
                "Purchase handoff store acquired \(forbiddenToken)"
            )
        }
        #expect(lineCount(models) <= 600)
        #expect(lineCount(store) <= 600)
        for testName in [
            "absentJournalsRemainAbsent",
            "legacyTransferRoundTripsWithDeviceOnlyAccessibility",
            "persistedJournalFieldNamesRemainByteCompatible",
            "malformedLegacyTransferFailsClosed",
            "failedOrUnverifiedLegacyTransferWriteFailsClosed",
            "invalidJournalsAreRejectedBeforeSecureStorage",
            "preparingServerRotationRoundTripsWithoutManufacturedExpiry",
            "preparedServerRotationRequiresServerExpiry",
            "preparingServerRotationRejectsAnExpiry",
            "legacyClientOnlyRotationRemainsReadable",
            "malformedStableRotationFailsClosed",
            "clearingEachJournalUsesItsExactVerifiedKey",
            "secureStoreFailuresPropagateWithoutBecomingAbsence"
        ] {
            #expect(storeTests.contains("@Test func \(testName)("))
        }
    }

    @Test func liveAuthRecoveryReusesTheExactSessionCoordinator() throws {
        let manager = try networkSource("SupabaseManager.swift")
        let telemetryLink = try sourceSection(
            beginningWith: "    private func ensureTelemetryLinkedWhenSafe(",
            endingBefore: "\n    /// Repairs a fail-closed purchase-identity",
            in: manager
        )
        let ordinaryRefresh = try sourceSection(
            beginningWith: "    private func refreshActiveSessionForRetry(",
            endingBefore: "\n    /// Refreshes the JWT for an authenticated request",
            in: manager
        )
        let failedSignOutRestoration = try sourceSection(
            beginningWith:
                "    private func restoreSourceIdentityAfterFailedSignOutIfPossible(",
            endingBefore:
                "\n    private func abandonPendingSignOutPurchaseHandoffIfSourceRestored(",
            in: manager
        )

        #expect(!telemetryLink.contains("ownsAuthTransition(transition)"))
        #expect(
            telemetryLink.components(
                separatedBy: "currentSessionMatchesAuthTransition(transition)"
            ).count == 3
        )
        try expectOrder(
            [
                "let expectedSession = activeAuthTransition?.expectedSession",
                "let session = try await client.auth.refreshSession()",
                "transitionSession(from: session.user) == expectedSession",
                "adoptAuthTransitionSession(",
                "currentSessionMatchesAuthTransition(transition)"
            ],
            in: ordinaryRefresh
        )
        try expectOrder(
            [
                "shouldRestoreSourceIdentityAfterFailedSignOut(",
                "adoptAuthTransitionSession(session.user, for: transition)",
                "currentSessionMatchesAuthTransition(transition)",
                "currentUser = session.user",
                "ensureTelemetryLinkedWhenSafe("
            ],
            in: failedSignOutRestoration
        )
    }

    @Test func liveAuthTaskCompletionsCannotPublishAcrossGenerations() throws {
        let manager = try networkSource("SupabaseManager.swift")
        let listener = try sourceSection(
            beginningWith: "    private func setupAuthStateListener() {",
            endingBefore: "\n    private func linkLegacyRevenueCatIdentity(",
            in: manager
        )
        let ghostBootstrap = try sourceSection(
            beginningWith: "    private func performGhostSessionInitialization(",
            endingBefore: "\n    // MARK: - Session Utilities",
            in: manager
        )
        let stableRotation = try sourceSection(
            beginningWith:
                "    private func completePendingPurchasePrincipalAuthRotationIfNeeded(",
            endingBefore:
                "\n    private func performPendingSignOutPurchaseHandoff(",
            in: manager
        )
        let compatibilityHandoff = try sourceSection(
            beginningWith:
                "    private func performPendingSignOutPurchaseHandoff(",
            endingBefore:
                "\n    /// Re-reads the device proof before any operation",
            in: manager
        )
        let anonymousSessionFence = try sourceSection(
            beginningWith:
                "    private func activeAnonymousSessionMatches(",
            endingBefore:
                "\n    private func verifyActiveAnonymousSession(",
            in: manager
        )
        let publicAuthorSchedule = try sourceSection(
            beginningWith:
                "    private func schedulePublicAuthorIdentityRefreshIfNeeded(",
            endingBefore:
                "\n    private func publishPublicAuthorIdentityChanged(",
            in: manager
        )
        let googleSignIn = try sourceSection(
            beginningWith: "    func signInWithGoogle() async {",
            endingBefore: "\n    // MARK: - Apple Sign-In",
            in: manager
        )
        let compactListener = listener.components(
            separatedBy: .whitespacesAndNewlines
        ).filter { !$0.isEmpty }.joined(separator: " ")

        #expect(
            compactListener.components(
                separatedBy:
                    "hasCurrentPublishedSession( session.user, expectedAuthGeneration: eventAuthGeneration )"
            ).count >= 5
        )
        #expect(
            ghostBootstrap.components(
                separatedBy: "hasCurrentPublishedSession("
            ).count == 3
        )
        #expect(
            stableRotation.components(
                separatedBy: "activeAnonymousSessionMatches("
            ).count >= 5
        )
        #expect(
            anonymousSessionFence.contains("!Task.isCancelled")
        )
        #expect(
            anonymousSessionFence.contains("isAuthenticated")
        )
        #expect(
            anonymousSessionFence.contains("return activeAuthTransition == nil")
        )
        #expect(
            stableRotation.components(
                separatedBy: "try Task.checkCancellation()"
            ).count >= 7
        )
        try expectOrder(
            [
                "verifyFinalDestinationSession:",
                "expectedAuthGeneration: expectedAuthGeneration",
                "clearPendingHandoff:"
            ],
            in: compatibilityHandoff
        )
        try expectOrder(
            [
                "let taskId = UUID()",
                "publicAuthorIdentityRefreshTaskId = taskId",
                "taskId: taskId",
                "if publicAuthorIdentityRefreshTaskId == taskId",
                "lastPublicAuthorIdentityRefreshUserId = userId"
            ],
            in: publicAuthorSchedule
        )
        #expect(
            publicAuthorSchedule.contains(
                "publicAuthorIdentityRefreshTaskUserId == userId"
            )
        )
        try expectOrder(
            [
                "try Task.checkCancellation()",
                "GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)",
                "try Task.checkCancellation()",
                "verifiedExpectedSessionIfPresent(for: transition)"
            ],
            in: googleSignIn
        )
    }

    @Test func directIdentityLinkRetiresRecoveryOnlyAfterExactUpgradeAdoption() throws {
        let manager = try networkSource("SupabaseManager.swift")
        let oauthFinalization = try sourceSection(
            beginningWith: "    private func finalizeOAuthLogin(",
            endingBefore: "\n    private func registerAppleRevocationCredential(",
            in: manager
        )
        let directIdentityLink = try sourceSection(
            beginningWith:
                "            do {\n                try Task.checkCancellation()\n                _ = try await client.auth.linkIdentityWithIdToken(",
            endingBefore: "\n            } catch {",
            in: oauthFinalization
        )

        #expect(
            directIdentityLink.components(
                separatedBy: "clearPendingGhostProfileMerges("
            ).count == 2
        )

        try expectOrder(
            [
                "linkIdentityWithIdToken(",
                "let linkedSession = try await client.auth.session",
                "acceptsLinkedIdentityUpgrade(",
                "adoptAuthTransitionSession(",
                "linkedSession.user,",
                "currentSessionMatchesAuthTransition(transition)",
                "clearPendingGhostProfileMerges("
            ],
            in: directIdentityLink
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

    private static let authFoundationPaths: Set<String> = [
        "Coordinators/AccountDeletionWorkflow.swift",
        "Coordinators/AuthTransitionCoordinators.swift",
        "Coordinators/GhostProfileMergeWorkflow.swift",
        "Coordinators/PurchaseIdentitySignOutWorkflow.swift",
        "Models/SupabaseAuthTransitionModels.swift",
        "Policies/AccountDeletionTransitionPolicy.swift",
        "Policies/AccountPresentationPolicy.swift",
        "Policies/AuthTransitionPolicy.swift",
        "Policies/GhostProfileMergePolicy.swift"
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

    private func staticFunctionNames(in source: String) throws -> Set<String> {
        let modifiers =
            #"private|fileprivate|internal|package|public|open|nonisolated|final|dynamic|override"#
        let pattern =
            #"(?m)^    (?:(?:\#(modifiers))\s+)*static\s+func\s+"#
                + #"([A-Za-z0-9_]+)\("#
        let expression = try NSRegularExpression(pattern: pattern)
        return try Set(expression.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).map { match in
            let range = try #require(Range(match.range(at: 1), in: source))
            return String(source[range])
        })
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

    private func sourceSection(
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
            let match = try #require(
                source.range(of: token, range: position..<source.endIndex)
            )
            position = match.upperBound
        }
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
