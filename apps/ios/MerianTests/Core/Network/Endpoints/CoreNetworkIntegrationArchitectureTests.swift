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
            "Auth", "Endpoints", "Inference", "Media", "Models", "Recovery",
            "Transport"
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
        let authFiles = try swiftFiles(below: authRoot)
        let actualPaths = Set(authFiles.map {
            String($0.path.dropFirst(prefix.count))
        })
        #expect(actualPaths == Self.authFoundationPaths)
        let allNetworkSources = try networkSources()

        let aggregate = try networkSource("SupabaseManager.swift")
        let purchaseIdentityFiles = try swiftFiles(
            below: repositoryRoot().appendingPathComponent(
                "apps/ios/Merian/Core/Security/PurchaseIdentity"
            )
        )
        let authProductionLineCount = try totalLineCount(in: authFiles)
        let purchaseIdentityProductionLineCount = try totalLineCount(
            in: purchaseIdentityFiles
        )
        let facadeLineCount = lineCount(aggregate)
        #expect(
            authProductionLineCount <= 7_734,
            "Auth production grew beyond its post-consolidation budget"
        )
        #expect(
            purchaseIdentityProductionLineCount <= 2_016,
            "Purchase Identity production grew beyond its reviewed budget"
        )
        #expect(
            facadeLineCount <= 3_461,
            "SupabaseManager grew beyond its post-consolidation budget"
        )
        #expect(
            authProductionLineCount
                + purchaseIdentityProductionLineCount
                + facadeLineCount <= 13_211,
            "The Auth facade extraction surfaces grew in aggregate"
        )
        let models = try networkSource(
            "Auth/Models/SupabaseAuthTransitionModels.swift"
        )
        let presentationPolicy = try networkSource(
            "Auth/Policies/AccountPresentationPolicy.swift"
        )
        let transitionPolicy = try networkSource(
            "Auth/Policies/AuthTransitionPolicy.swift"
        )
        let lifecycleModels = try networkSource(
            "Auth/Models/AuthSessionLifecycleModels.swift"
        )
        let lifecycleDependencies = try networkSource(
            "Auth/Coordinators/AuthSessionLifecycleCoordinationDependencies.swift"
        )
        let lifecycleCoordinator = try networkSource(
            "Auth/Coordinators/AuthSessionLifecycleCoordinator.swift"
        )
        let lifecycleReconciliationCoordinator = try networkSource(
            "Auth/Coordinators/AuthLifecycleReplayCoordinator.swift"
        )
        let lifecycleLiveProvider = try networkSource(
            "Auth/Services/AuthSessionLifecycleLiveProvider.swift"
        )
        let lifecycleLiveAdapter = try networkSource(
            "Auth/Services/AuthSessionLifecycleLiveProvider+Live.swift"
        )
        let lifecycleLiveDiagnostics = try networkSource(
            "Auth/Services/AuthSessionLifecycleLiveDiagnostics.swift"
        )
        let historicalSessionSyncLiveService = try networkSource(
            "Auth/Services/AuthHistoricalSessionSyncLiveService.swift"
        )
        let historicalSessionSyncLiveAdapter = try networkSource(
            "Auth/Services/AuthHistoricalSessionSyncLiveService+Live.swift"
        )
        let bootstrapDependencies = try networkSource(
            "Auth/Coordinators/AuthSessionBootstrapCoordinationDependencies.swift"
        )
        let bootstrapCoordinator = try networkSource(
            "Auth/Coordinators/AuthSessionBootstrapCoordinator.swift"
        )
        let bootstrapLiveService = try networkSource(
            "Auth/Services/AuthSessionBootstrapLiveService.swift"
        )
        let bootstrapLiveAdapter = try networkSource(
            "Auth/Services/AuthSessionBootstrapLiveService+Live.swift"
        )
        let bootstrapLiveDiagnostics = try networkSource(
            "Auth/Services/AuthSessionBootstrapLiveDiagnostics.swift"
        )
        let recoveryDependencies = try networkSource(
            "Auth/Coordinators/AuthSessionRecoveryCoordinationDependencies.swift"
        )
        let recoveryCoordinator = try networkSource(
            "Auth/Coordinators/AuthSessionRecoveryCoordinator.swift"
        )
        let authSessionService = try networkSource(
            "Auth/Services/SupabaseAuthSessionService.swift"
        )
        let authSessionLiveAdapter = try networkSource(
            "Auth/Services/SupabaseAuthSessionService+Live.swift"
        )
        let localSignOutCoordinator = try networkSource(
            "Auth/Coordinators/AuthLocalSignOutCoordinator.swift"
        )
        let authenticationCallbackDependencies = try networkSource(
            "Auth/Coordinators/AuthenticationCallbackCoordinationDependencies.swift"
        )
        let authenticationCallbackCoordinator = try networkSource(
            "Auth/Coordinators/AuthenticationCallbackCoordinator.swift"
        )
        let authenticationCallbackDiagnostics = try networkSource(
            "Auth/Services/AuthenticationCallbackLiveDiagnostics.swift"
        )
        let oauthModels = try networkSource(
            "Auth/Models/OAuthSignInModels.swift"
        )
        let oauthIdentityTokenPolicy = try networkSource(
            "Auth/Policies/OAuthIdentityTokenPolicy.swift"
        )
        let oauthWorkflow = try networkSource(
            "Auth/Coordinators/OAuthSignInWorkflow.swift"
        )
        let oauthDependencies = try networkSource(
            "Auth/Coordinators/OAuthSignInCoordinationDependencies.swift"
        )
        let oauthCoordinator = try networkSource(
            "Auth/Coordinators/OAuthSignInCoordinator.swift"
        )
        let oauthProviderDependencies = try networkSource(
            "Auth/Coordinators/OAuthProviderSignInCoordinationDependencies.swift"
        )
        let oauthProviderCoordinator = try networkSource(
            "Auth/Coordinators/OAuthProviderSignInCoordinator.swift"
        )
        let googleAuthorizationProvider = try networkSource(
            "Auth/Services/GoogleOAuthAuthorizationLiveProvider.swift"
        )
        let appleAuthorizationProvider = try networkSource(
            "Auth/Services/AppleOAuthAuthorizationLiveProvider.swift"
        )
        let appleCredentialRegistrationService = try networkSource(
            "Auth/Services/AppleOAuthCredentialRegistrationService.swift"
        )
        let appleCredentialRegistrationLiveService = try networkSource(
            "Auth/Services/AppleOAuthCredentialRegistrationService+Live.swift"
        )
        let oauthPresentationResolver = try networkSource(
            "Auth/Services/OAuthPresentationContextResolver.swift"
        )
        let oauthProviderDiagnostics = try networkSource(
            "Auth/Services/OAuthProviderSignInLiveDiagnostics.swift"
        )
        let deletionPolicy = try networkSource(
            "Auth/Policies/AccountDeletionTransitionPolicy.swift"
        )
        let coordinators = try networkSource(
            "Auth/Coordinators/AuthTransitionCoordinators.swift"
        )
        let runtimeState = try networkSource(
            "Auth/Coordinators/AuthRuntimeState.swift"
        )
        let deletionWorkflow = try networkSource(
            "Auth/Coordinators/AccountDeletionWorkflow.swift"
        )
        let deletionCoordinator = try networkSource(
            "Auth/Coordinators/AccountDeletionCoordinator.swift"
        )
        let deletionDependencies = try networkSource(
            "Auth/Coordinators/AccountDeletionCoordinationDependencies.swift"
        )
        let deletionRecoveryCoordinator = try networkSource(
            "Auth/Coordinators/AccountDeletionRecoveryCoordinator.swift"
        )
        let purchaseSignOutWorkflow = try networkSource(
            "Auth/Coordinators/PurchaseIdentitySignOutWorkflow.swift"
        )
        let purchaseSignOutDependencies = try networkSource(
            "Auth/Coordinators/PurchaseIdentitySignOutCoordinationDependencies.swift"
        )
        let purchaseSignOutCoordinator = try networkSource(
            "Auth/Coordinators/PurchaseIdentitySignOutCoordinator.swift"
        )
        let purchaseHandoffDependencies = try networkSource(
            "Auth/Coordinators/PurchaseIdentityHandoffCoordinationDependencies.swift"
        )
        let purchaseHandoffCoordinator = try networkSource(
            "Auth/Coordinators/PurchaseIdentityHandoffCoordinator.swift"
        )
        let purchaseSourceHandoffDependencies = try networkSource(
            "Auth/Coordinators/PurchaseIdentitySourceHandoffCoordinationDependencies.swift"
        )
        let purchaseSourceHandoffCoordinator = try networkSource(
            "Auth/Coordinators/PurchaseIdentitySourceHandoffCoordinator.swift"
        )
        let purchaseHandoffAuthJournal = try networkSource(
            "Auth/Services/PurchaseIdentityHandoffAuthJournal.swift"
        )
        let purchaseHandoffPreparationCoordinator = try source(
            "apps/ios/Merian/Core/Security/PurchaseIdentity/Coordinators/PurchaseIdentityHandoffPreparationCoordinator.swift"
        )
        let lifecycleAssembly = try sourceSection(
            beginningWith:
                "    private func authSessionLifecycleDependencies(",
            endingBefore: "\n    private func beginAccountSession(",
            in: aggregate
        )
        let lifecycleLiveAssembly = try sourceSection(
            beginningWith:
                "    private func authSessionLifecycleLiveDependencies()",
            endingBefore:
                "\n    private func authSessionLifecycleDependencies(",
            in: aggregate
        )
        let managerDeinitialization = try sourceSection(
            beginningWith: "    isolated deinit {",
            endingBefore:
                "\n\n    func bindAppRouteSessionController(",
            in: aggregate
        )
        let bootstrapAssembly = try sourceSection(
            beginningWith:
                "    private func authSessionBootstrapDependencies()",
            endingBefore: "\n    // MARK: - Session Utilities",
            in: aggregate
        )
        let recoveryAssembly = try sourceSection(
            beginningWith:
                "    private func authSessionRecoveryDependencies()",
            endingBefore:
                "\n    /// Builds authenticated REST headers",
            in: aggregate
        )
        let oauthAssembly = try sourceSection(
            beginningWith:
                "    private func oauthSignInDependencies()",
            endingBefore:
                "\n    private func adoptOAuthSignInSession(",
            in: aggregate
        )
        let oauthProviderAssembly = try sourceSection(
            beginningWith:
                "    private func oauthProviderSignInDependencies()",
            endingBefore:
                "\n    private func oauthSignInDependencies()",
            in: aggregate
        )
        let appleCredentialRegistrationAssembly = try sourceSection(
            beginningWith:
                "    private func registerAppleRevocationCredential(",
            endingBefore:
                "\n    private func installOAuthSessionReplacingCurrentAccount(",
            in: aggregate
        )
        let oauthSessionReplacementAssembly = try sourceSection(
            beginningWith:
                "    private func installOAuthSessionReplacingCurrentAccount(",
            endingBefore:
                "\n    private func reconcileOAuthSessionReplacement(",
            in: aggregate
        )
        let authenticationCallbackFacade = try sourceSection(
            beginningWith:
                "    func handleAuthenticationCallbackURL(_ url: URL) async {",
            endingBefore:
                "\n    private func authenticationCallbackDependencies(",
            in: aggregate
        )
        let authenticationCallbackAssembly = try sourceSection(
            beginningWith:
                "    private func authenticationCallbackDependencies(",
            endingBefore: "\n    // MARK: - Google Sign-In",
            in: aggregate
        )
        let googleSignIn = try sourceSection(
            beginningWith: "    func signInWithGoogle() async {",
            endingBefore: "\n    // MARK: - Apple Sign-In",
            in: aggregate
        )
        let appleSignIn = try sourceSection(
            beginningWith: "    func startAppleSignIn() {",
            endingBefore: "\n    // MARK: - Private OAuth Helpers",
            in: aggregate
        )
        let purchaseSignOutAssembly = try sourceSection(
            beginningWith:
                "    private func purchaseIdentitySignOutDependencies()",
            endingBefore:
                "\n    private func authLocalSignOutDependencies(",
            in: aggregate
        )
        let localSignOutFacade = try sourceSection(
            beginningWith:
                "    private func performLocalSignOut(\n        ownedBy transition: AuthTransitionToken,",
            endingBefore:
                "\n    /// Replaces the active account with a fresh anonymous identity.",
            in: aggregate
        )
        let localSignOutAssembly = try sourceSection(
            beginningWith:
                "    private func authLocalSignOutDependencies(",
            endingBefore:
                "\n    /// Returns the JWT access token from the active session.",
            in: aggregate
        )
        let purchaseHandoffAssembly = try sourceSection(
            beginningWith:
                "    private func purchaseIdentityHandoffDependencies()",
            endingBefore:
                "\n    private func purchaseIdentitySourceHandoffCoordinator()",
            in: aggregate
        )
        let purchaseSourceHandoffAssembly = try sourceSection(
            beginningWith:
                "    private func purchaseIdentitySourceHandoffCoordinator()",
            endingBefore:
                "\n    /// Publishes the aggregate durable handoff fence",
            in: aggregate
        )
        let pendingStableResolution = try sourceSection(
            beginningWith:
                "    private func resolvePendingStableRotation(",
            endingBefore:
                "\n    private func resolvePendingLegacyHandoff(",
            in: purchaseSignOutCoordinator
        )
        let ghostMergePolicy = try networkSource(
            "Auth/Policies/GhostProfileMergePolicy.swift"
        )
        let ghostMergeWorkflow = try networkSource(
            "Auth/Coordinators/GhostProfileMergeWorkflow.swift"
        )
        let ghostMergeDependencies = try networkSource(
            "Auth/Coordinators/GhostProfileMergeCoordinationDependencies.swift"
        )
        let ghostMergeCoordinator = try networkSource(
            "Auth/Coordinators/GhostProfileMergeCoordinator.swift"
        )
        let publicAuthorRefreshDependencies = try networkSource(
            "Auth/Coordinators/PublicAuthorIdentityRefreshCoordinationDependencies.swift"
        )
        let publicAuthorRefreshCoordinator = try networkSource(
            "Auth/Coordinators/PublicAuthorIdentityRefreshCoordinator.swift"
        )
        let publicAuthorRefreshLiveEffects = try networkSource(
            "SupabasePublicAuthorIdentityRefreshLiveEffects.swift"
        )
        let appleRevocationDependencies = try networkSource(
            "Auth/Coordinators/AppleCredentialRevocationCoordinationDependencies.swift"
        )
        let appleRevocationCoordinator = try networkSource(
            "Auth/Coordinators/AppleCredentialRevocationCoordinator.swift"
        )
        let appleRevocationLiveProvider = try networkSource(
            "AppleCredentialRevocationLiveProvider.swift"
        )
        let appleRevocationDiagnostics = try networkSource(
            "AppleCredentialRevocationLiveDiagnostics.swift"
        )
        let appleRevocationAssembly = try sourceSection(
            beginningWith:
                "    private func appleCredentialRevocationDependencies()",
            endingBefore:
                "\n    private func authSessionLifecycleLiveDependencies()",
            in: aggregate
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
        for declaration in [
            "enum AuthSessionLifecycleOrigin",
            "struct AuthSessionLifecycleEvent",
            "enum AuthSessionLifecycleDiagnostic"
        ] {
            #expect(lifecycleModels.contains(declaration))
            #expect(!aggregate.contains(declaration))
        }
        for declaration in [
            "struct AuthSessionLifecycleStateBoundary",
            "struct AuthSessionLifecycleDurabilityBoundary",
            "struct AuthSessionLifecycleIdentityBoundary",
            "struct AuthSessionLifecycleDependencies"
        ] {
            #expect(lifecycleDependencies.contains(declaration))
        }
        #expect(
            lifecycleCoordinator.contains(
                "@MainActor\nstruct AuthSessionLifecycleCoordinator"
            )
        )
        #expect(lifecycleCoordinator.contains("func handle("))
        #expect(
            lifecycleReconciliationCoordinator.contains(
                "@MainActor\nfinal class AuthLifecycleReplayCoordinator"
            )
        )
        #expect(
            lifecycleReconciliationCoordinator.contains(
                "private var task: Task<Void, Never>?"
            )
        )
        #expect(
            lifecycleReconciliationCoordinator.components(
                separatedBy: "Task {"
            ).count == 2,
            "Lifecycle reconciliation must retain one replacement-safe task owner"
        )
        #expect(
            lifecycleReconciliationCoordinator.contains(
                "Task { @MainActor [weak self] in"
            )
        )
        #expect(
            lifecycleLiveProvider.contains(
                "final class AuthSessionLifecycleLiveProvider"
            )
        )
        #expect(
            lifecycleLiveProvider.contains(
                "private var listenerTask: Task<Void, Never>?"
            )
        )
        #expect(
            lifecycleLiveProvider.contains(
                "private let replayCoordinator = AuthLifecycleReplayCoordinator()"
            )
        )
        #expect(
            lifecycleLiveProvider.contains(
                "listenerTask?.cancel()\n        replayCoordinator.cancel()"
            ),
            "Replacing the live listener must discard its deferred replay obligation"
        )
        #expect(
            lifecycleLiveProvider.contains(
                "guard let operation = self?.makeOperation("
            ),
            "The listener may retain its provider only while preparing one synchronous operation"
        )
        #expect(
            !lifecycleLiveProvider.contains("guard let self else"),
            "The SDK listener and replay task must not retain their provider across suspension"
        )
        #expect(
            lifecycleLiveProvider.contains(
                ").handle(event)\n        guard !Task.isCancelled else { return }"
            ),
            "A canceled listener must not resume deferred credential work"
        )
        #expect(
            lifecycleLiveAdapter.contains(
                "client.auth.authStateChanges"
            )
        )
        #expect(
            lifecycleLiveAdapter.contains(
                "client.auth.currentSession"
            )
        )
        #expect(
            historicalSessionSyncLiveService.contains(
                "private var tasks: [UUID: Task<Void, Never>] = [:]"
            )
        )
        #expect(
            historicalSessionSyncLiveService.contains(
                "guard !Task.isCancelled, isCurrentSession() else { return }"
            )
        )
        #expect(
            historicalSessionSyncLiveAdapter.contains(
                "UserDefaultsKeys.lastHistoricalSyncDate"
            )
        )
        #expect(
            historicalSessionSyncLiveAdapter.contains(
                "syncHistoricalScansDown(modelContext: context)"
            )
        )
        #expect(
            lifecycleLiveDiagnostics.contains(
                "enum AuthSessionLifecycleLiveDiagnostics"
            )
        )
        #expect(
            !lifecycleAssembly.contains("[self]"),
            "Lifecycle replay dependencies must not retain SupabaseManager across suspension"
        )
        #expect(
            lifecycleAssembly.contains("[weak self]"),
            "Lifecycle replay dependencies must release with their facade owner"
        )
        #expect(
            !lifecycleLiveAssembly.contains("[self]")
        )
        #expect(
            lifecycleLiveAssembly.contains("[weak self]")
        )
        #expect(
            aggregate.contains(
                "authSessionLifecycleLiveProvider.authTransitionWillBegin()"
            )
        )
        #expect(
            aggregate.contains(
                ".scheduleCurrentSessionReconciliation("
            )
        )
        #expect(
            !aggregate.contains(
                "private func setupAuthStateListener()"
            )
        )
        #expect(!aggregate.contains("authListenerTask"))
        #expect(!aggregate.contains("authLifecycleReplayCoordinator"))
        #expect(!aggregate.contains("await AuthSessionLifecycleCoordinator("))
        #expect(
            !aggregate.contains(
                "switch sessionAdoption {"
            )
        )
        try expectOrder(
            [
                "accountDeletionCleanupPending()",
                "publishDeletionBarrier()",
                "shouldDeferAuthListenerSideEffects(",
                "synchronizeDurableFences()",
                "switch event.adoption"
            ],
            in: lifecycleCoordinator
        )
        let deletionBarrier = try sourceSection(
            beginningWith: "    private func publishDeletionBarrier() {",
            endingBefore: "\n    private func publishAwaitingRefresh(",
            in: lifecycleCoordinator
        )
        try expectOrder(
            [
                "clearPublishedSession()",
                "clearPurchasePrincipalBinding()",
                "beginPurchaseIdentityResolution()",
                "clearEntitlementSession()"
            ],
            in: deletionBarrier
        )
        try expectOrder(
            [
                "ensureTelemetryLinked(session)",
                "isCurrentPublishedSession(",
                "beginEntitlementSession(session)",
                "isCurrentPublishedSession(",
                "scheduleHistoricalSync("
            ],
            in: lifecycleCoordinator
        )
        try expectOrder(
            [
                "publishSignedOut(origin: event.origin)",
                "handleSupabaseSignOut()",
                "isCurrentLifecycleSession(",
                "finishSignedOutPublication()"
            ],
            in: lifecycleCoordinator
        )
        #expect(
            lifecycleAssembly.contains(
                "hasCurrentPublishedSession("
            )
        )
        for declaration in [
            "struct AuthSessionBootstrapSnapshot",
            "struct AuthSessionBootstrapStateBoundary",
            "struct AuthSessionBootstrapTransitionBoundary",
            "struct AuthSessionBootstrapWorkBoundary",
            "struct AuthSessionBootstrapOperationBoundary",
            "enum AuthSessionBootstrapDiagnostic",
            "struct AuthSessionBootstrapDependencies"
        ] {
            #expect(bootstrapDependencies.contains(declaration))
            #expect(!aggregate.contains(declaration))
        }
        #expect(
            bootstrapCoordinator.contains(
                "@MainActor\nfinal class AuthSessionBootstrapCoordinator"
            )
        )
        #expect(
            bootstrapCoordinator.contains(
                "private var task: Task<AuthTransitionSession?, Never>?"
            )
        )
        #expect(
            bootstrapCoordinator.contains(
                "private var taskTransition: AuthTransitionToken?"
            )
        )
        #expect(
            bootstrapCoordinator.contains(
                "let task: Task<AuthTransitionSession?, Never> = Task {"
            )
        )
        #expect(
            bootstrapCoordinator.components(
                separatedBy:
                    "let task: Task<AuthTransitionSession?, Never> = Task {"
            ).count == 2,
            "Session bootstrap must retain one keyed task owner"
        )
        #expect(
            bootstrapCoordinator.components(
                separatedBy: """
                await session.ensurePurchaseIdentityReady(transition)
                            guard !Task.isCancelled,
                                  session.isCurrentPublishedSession(transition) else {
                """
            ).count == 3,
            "Every loaded or created session must reject cancellation after purchase readiness"
        )
        #expect(
            aggregate.contains(
                "authSessionBootstrapCoordinator.initialize("
            )
        )
        for token in [
            "authSessionBootstrapLiveService.currentSession()",
            "authSessionBootstrapLiveService.loadSession()",
            ".createAnonymousSession()",
            ".isSessionMissingError(error)",
            "AuthSessionBootstrapLiveDiagnostics.report("
        ] {
            #expect(bootstrapAssembly.contains(token))
        }
        for forbiddenToken in [
            "client.auth.session",
            "client.auth.currentSession",
            "client.auth.signInAnonymously()",
            "AuthError",
            "MerianLog.auth"
        ] {
            #expect(!bootstrapAssembly.contains(forbiddenToken))
        }
        #expect(
            bootstrapLiveService.contains(
                "struct AuthSessionBootstrapLiveSession"
            )
        )
        #expect(
            bootstrapLiveService.contains(
                "struct AuthSessionBootstrapLiveService"
            )
        )
        #expect(
            bootstrapLiveService.contains(
                "case .sessionMissing = authError"
            )
        )
        for token in [
            "client.auth.session",
            "client.auth.currentSession",
            "client.auth.signInAnonymously()"
        ] {
            #expect(bootstrapLiveAdapter.contains(token))
        }
        #expect(
            bootstrapLiveDiagnostics.contains(
                "enum AuthSessionBootstrapLiveDiagnostics"
            )
        )
        #expect(bootstrapLiveDiagnostics.contains("MerianLog.auth"))
        #expect(!bootstrapCoordinator.contains("AuthError"))
        #expect(!bootstrapCoordinator.contains("signInAnonymously"))
        for retiredManagerMember in [
            "private var ghostSessionTask:",
            "private var ghostSessionTaskId:",
            "private var ghostSessionTaskAuthTransitionId:",
            "private func performGhostSessionInitialization("
        ] {
            #expect(!aggregate.contains(retiredManagerMember))
        }
        try expectOrder(
            [
                "await dependencies.state.awaitSignOutCompletion()",
                "guard !Task.isCancelled else { return nil }",
                "if let task",
                "activeTransition == taskTransition",
                "dependencies.operations.currentSDKSession()",
                ".beginAnonymousBootstrap()",
                "let task: Task<AuthTransitionSession?, Never> = Task {"
            ],
            in: bootstrapCoordinator
        )
        try expectOrder(
            [
                "await dependencies.transition.awaitAccountWorkQuiescence()",
                "loadSDKSession()",
                "dependencies.transition.adopt(",
                "session.publish()",
                "session.schedulePublicAuthorIdentityRefresh()",
                "await session.ensurePurchaseIdentityReady(transition)",
                "session.isCurrentPublishedSession(transition)"
            ],
            in: bootstrapCoordinator
        )
        try expectOrder(
            [
                "isSessionMissingError(error)",
                "createAnonymousSession()",
                "dependencies.transition.adopt(",
                "session.publish()",
                "await session.ensurePurchaseIdentityReady(transition)",
                "session.isCurrentPublishedSession(transition)"
            ],
            in: bootstrapCoordinator
        )
        for declaration in [
            "enum AuthSessionRecoveryEntryPolicy",
            "enum AuthSessionLocalClearOutcome",
            "struct AuthSessionRecoverySession",
            "struct AuthSessionRecoveryStateBoundary",
            "struct AuthSessionRecoveryTransitionBoundary",
            "struct AuthSessionRecoveryOperationBoundary",
            "enum AuthSessionRecoveryDiagnostic",
            "struct AuthSessionRecoveryDependencies"
        ] {
            #expect(recoveryDependencies.contains(declaration))
            #expect(!aggregate.contains(declaration))
        }
        #expect(
            recoveryCoordinator.contains(
                "@MainActor\nstruct AuthSessionRecoveryCoordinator"
            )
        )
        for entryPoint in [
            "func refreshActiveSessionForRetry() async -> Bool",
            "func refreshExpectedSessionForAuthenticatedRequest(",
            "func resetGhostSessionForRetry() async -> Bool",
            "func clearLocalSessionAfterAuthFailure() async",
            "func clearLocalSessionAfterAuthFailure("
        ] {
            #expect(recoveryCoordinator.contains(entryPoint))
        }
        try expectOrder(
            [
                "let expectedSession = dependencies.transition.expectedSession(",
                "await dependencies.transition.awaitAccountWorkQuiescence()",
                "dependencies.transition.expectedSession(transition)\n                == expectedSession",
                "dependencies.transition.currentSessionMatches(transition)",
                "hasPendingPurchaseIdentityHandoff()",
                "performLocalSDKSignOut()"
            ],
            in: recoveryCoordinator
        )
        #expect(
            aggregate.components(
                separatedBy: "AuthSessionRecoveryCoordinator("
            ).count == 6
        )
        for token in [
            "supabaseAuthSessionService",
            ".refreshRecoverySession()",
            ".loadRecoverySession()",
            "supabaseAuthSessionService.signOutLocal()",
            "AuthSessionRecoveryLiveDiagnostics.report("
        ] {
            #expect(recoveryAssembly.contains(token))
        }
        for forbiddenToken in [
            "client.auth.refreshSession()",
            "client.auth.session",
            "client.auth.signOut(scope: .local)",
            "MerianLog.auth"
        ] {
            #expect(!recoveryAssembly.contains(forbiddenToken))
        }
        #expect(
            authSessionService.contains(
                "struct AuthSessionRecoveryLiveSession"
            )
        )
        #expect(
            authSessionService.contains(
                "struct SupabaseAuthSessionService"
            )
        )
        for token in [
            "client.auth.refreshSession()",
            "client.auth.session"
        ] {
            #expect(authSessionLiveAdapter.contains(token))
        }
        #expect(
            authSessionLiveAdapter.contains(
                "client.auth.signOut(scope: .local)"
            )
        )
        #expect(
            authSessionLiveAdapter.contains(
                "enum AuthSessionRecoveryLiveDiagnostics"
            )
        )
        #expect(authSessionLiveAdapter.contains("MerianLog.auth"))
        #expect(!recoveryCoordinator.contains("import Supabase"))
        #expect(!recoveryCoordinator.contains("client.auth"))
        for declaration in [
            "struct AuthLocalSignOutPreparation",
            "struct AuthLocalSignOutStateBoundary",
            "struct AuthLocalSignOutTransitionBoundary",
            "struct AuthLocalSignOutOperationBoundary",
            "enum AuthLocalSignOutDiagnostic",
            "struct AuthLocalSignOutDependencies"
        ] {
            #expect(localSignOutCoordinator.contains(declaration))
            #expect(!aggregate.contains(declaration))
        }
        #expect(
            localSignOutCoordinator.contains(
                "@MainActor\nfinal class AuthLocalSignOutCoordinator"
            )
        )
        #expect(
            localSignOutCoordinator.contains(
                "private var task: Task<Void, Never>?"
            )
        )
        #expect(
            localSignOutCoordinator.components(
                separatedBy: "Task {"
            ).count == 2,
            "Local sign-out must retain one task owner"
        )
        let localSignOutCancellation = try sourceSection(
            beginningWith: "    func cancel() {",
            endingBefore: "\n    private func clearTaskIfCurrent(",
            in: localSignOutCoordinator
        )
        #expect(localSignOutCancellation.contains("task?.cancel()"))
        #expect(!localSignOutCancellation.contains("task = nil"))
        #expect(!localSignOutCancellation.contains("taskID = nil"))
        try expectOrder(
            [
                "dependencies.transition.owns(transition)",
                "await dependencies.transition.awaitAccountWorkQuiescence()",
                "let preparation = dependencies.state.begin()",
                "dependencies.transition.updateForSessionInstallation(transition)",
                "dependencies.transition.adoptSignedOutSession(transition)",
                "await preparation.awaitCancelledBootstrap()",
                "dependencies.operations.signOutSDKSession()",
                "dependencies.operations.finishExternalSignOut()",
                "dependencies.diagnose(.completed, nil)"
            ],
            in: localSignOutCoordinator
        )
        #expect(
            localSignOutFacade.contains(
                "authLocalSignOutCoordinator.signOut("
            )
        )
        for token in [
            "prepareLocalSignOutState()",
            "authRuntimeState.finishSignOut()",
            "AuthLocalSignOutLiveDiagnostics.report("
        ] {
            #expect(localSignOutAssembly.contains(token))
        }
        #expect(!localSignOutAssembly.contains("{ [self]"))
        #expect(
            localSignOutAssembly.components(
                separatedBy: "[weak self]"
            ).count == 7,
            "Local sign-out task dependencies must not retain the facade"
        )
        #expect(!aggregate.contains("private var signOutTask:"))
        #expect(
            authSessionService.contains(
                "struct SupabaseAuthSessionService"
            )
        )
        #expect(
            authSessionLiveAdapter.contains(
                "client.auth.signOut(scope: .local)"
            )
        )
        #expect(
            authSessionLiveAdapter.contains(
                "enum AuthLocalSignOutLiveDiagnostics"
            )
        )
        #expect(authSessionLiveAdapter.contains("MerianLog.auth"))
        for forbiddenToken in [
            "import Supabase", ".shared", "MerianLog"
        ] {
            #expect(!localSignOutCoordinator.contains(forbiddenToken))
        }
        for retiredManagerHelper in [
            "private func refreshActiveSessionForRetry(",
            "let session = try await client.auth.refreshSession()\n            guard ownsAuthTransition",
            "guard await PurchaseIdentitySignOutCoordinator(\n            dependencies: purchaseIdentitySignOutDependencies()\n        ).resetGhostSessionForRetry",
            "private func clearLocalSessionAfterAuthFailure(\n        ownedBy transition: AuthTransitionToken\n    ) async {\n        guard ownsAuthTransition"
        ] {
            #expect(!aggregate.contains(retiredManagerHelper))
        }
        for declaration in [
            "struct OAuthSignInCredentials",
            "struct AppleOAuthCredentialRegistration",
            "struct OAuthProviderAuthorization",
            "enum GoogleOAuthAuthorizationOutcome",
            "enum AppleOAuthAuthorizationError",
            "enum OAuthProviderSignInDiagnostic",
            "struct OAuthSignInSession: Equatable, Sendable",
            "struct OAuthSignInCompletion: Equatable, Sendable",
            "enum OAuthSessionReplacementDisposition: Equatable, Sendable",
            "struct OAuthProfileMetadata: Equatable, Sendable",
            "enum OAuthSignInWorkflowError: LocalizedError"
        ] {
            #expect(oauthModels.contains(declaration))
            #expect(!aggregate.contains(declaration))
        }
        let appleCredentialRegistration = try sourceSection(
            beginningWith: "struct AppleOAuthCredentialRegistration",
            endingBefore: "\n\nstruct OAuthProviderAuthorization",
            in: oauthModels
        )
        #expect(!appleCredentialRegistration.contains("identityToken"))
        #expect(
            oauthIdentityTokenPolicy.contains(
                "enum OAuthIdentityTokenPolicy"
            )
        )
        #expect(
            try staticFunctionNames(in: oauthIdentityTokenPolicy)
                == ["providerSubject"]
        )
        #expect(
            oauthWorkflow.contains("@MainActor\nenum OAuthSignInWorkflow")
        )
        #expect(
            try staticFunctionNames(in: oauthWorkflow)
                == ["registerAppleCredential", "replacingSession"]
        )
        for declaration in [
            "struct OAuthSignInSessionBoundary",
            "struct OAuthSignInMergeBoundary",
            "struct OAuthSignInCompletionBoundary",
            "struct OAuthSignInCoordinationDependencies"
        ] {
            #expect(oauthDependencies.contains(declaration))
        }
        #expect(
            oauthCoordinator.contains("@MainActor\nstruct OAuthSignInCoordinator")
        )
        for declaration in [
            "struct OAuthProviderSignInTransitionBoundary",
            "struct OAuthProviderAuthorizationBoundary",
            "struct OAuthProviderSignInCompletionBoundary",
            "struct OAuthProviderSignInDiagnostics",
            "struct OAuthProviderSignInDependencies"
        ] {
            #expect(oauthProviderDependencies.contains(declaration))
        }
        #expect(
            oauthProviderCoordinator.contains(
                "@MainActor\nfinal class OAuthProviderSignInCoordinator"
            )
        )
        #expect(
            oauthProviderCoordinator.contains(
                "private var appleCompletionTask: Task<Void, Never>?"
            )
        )
        #expect(
            oauthProviderCoordinator.components(
                separatedBy: "Task {"
            ).count == 2,
            "Provider sign-in must retain one Apple completion task owner"
        )
        #expect(
            oauthProviderCoordinator.contains(
                "guard appleCompletionTaskID == completedTaskID else { return }"
            )
        )
        try expectOrder(
            [
                "func cancel()",
                "let task = appleCompletionTask",
                "appleCompletionTask = nil",
                "appleCompletionTaskID = nil",
                "task?.cancel()"
            ],
            in: oauthProviderCoordinator
        )
        #expect(
            oauthProviderCoordinator.contains(
                "pendingAppleAuthorization = nil\n            attempt.transitionBoundary.finish(attempt.transition)\n            attempt.diagnostics.report(.appleStaleCallback, nil)"
            )
        )
        #expect(
            googleAuthorizationProvider.contains(
                "GIDSignIn.sharedInstance.signIn("
            )
        )
        for provider in [
            googleAuthorizationProvider,
            appleAuthorizationProvider
        ] {
            #expect(provider.contains("init()"))
            #expect(provider.contains("init(dependencies:"))
            #expect(!provider.contains("Dependencies?"))
            #expect(!provider.contains("dependencies ?? .live"))
        }
        #expect(
            appleAuthorizationProvider.contains(
                "ASAuthorizationControllerDelegate"
            )
        )
        #expect(
            appleAuthorizationProvider.contains(
                "private var activeAttempt: Attempt?"
            )
        )
        #expect(appleAuthorizationProvider.contains("SecRandomCopyBytes("))
        #expect(appleAuthorizationProvider.contains("SHA256.hash("))
        #expect(oauthPresentationResolver.contains("UIApplication.shared"))
        #expect(oauthProviderDiagnostics.contains("MerianLog.auth"))
        #expect(
            appleCredentialRegistrationService.contains(
                "struct AppleOAuthCredentialRegistrationService"
            )
        )
        #expect(
            appleCredentialRegistrationService.contains(
                "receipt.success"
            )
        )
        #expect(
            appleCredentialRegistrationService.contains(
                "receipt.status == \"registered\""
            )
        )
        for wireToken in [
            "private struct AppleOAuthCredentialRegistrationPayload",
            "private struct AppleOAuthCredentialRegistrationResponse",
            "registration_id:",
            "authorization_code:",
            "identity_token:",
            "\"register-apple-revocation-token\""
        ] {
            #expect(
                appleCredentialRegistrationLiveService.contains(wireToken)
            )
            #expect(!aggregate.contains(wireToken))
        }
        #expect(
            appleCredentialRegistrationLiveService.contains(
                "static func live(client: SupabaseClient) -> Self"
            )
        )
        #expect(
            appleCredentialRegistrationLiveService.contains(
                ".uuidString.lowercased()"
            )
        )
        #expect(
            appleCredentialRegistrationLiveService.components(
                separatedBy: "client.functions.invoke("
            ).count == 2,
            "Apple credential registration must retain one live transport invocation"
        )
        #expect(
            aggregate.contains(
                "appleOAuthCredentialRegistrationService = .live(client: client)"
            )
        )
        #expect(
            aggregate.contains(
                "supabaseAuthSessionService = .live(client: client)"
            )
        )
        #expect(
            appleCredentialRegistrationAssembly.contains(
                "appleOAuthCredentialRegistrationService.register("
            )
        )
        #expect(
            !appleCredentialRegistrationAssembly.contains(
                "client.functions.invoke("
            )
        )
        try expectOrder(
            [
                "guard self.currentSessionMatchesAuthTransition(transition)",
                "appleOAuthCredentialRegistrationService.register(",
                "guard self.currentSessionMatchesAuthTransition(transition)"
            ],
            in: appleCredentialRegistrationAssembly
        )
        for providerNeutralOwner in [
            authenticationCallbackDependencies,
            authenticationCallbackCoordinator,
            oauthProviderDependencies,
            oauthProviderCoordinator,
            appleCredentialRegistrationService
        ] {
            for forbiddenToken in [
                "import AuthenticationServices",
                "import CryptoKit",
                "import GoogleSignIn",
                "import Supabase",
                "import UIKit",
                "MerianLog"
            ] {
                #expect(!providerNeutralOwner.contains(forbiddenToken))
            }
        }
        #expect(
            authenticationCallbackFacade.contains(
                "AuthenticationCallbackCoordinator("
            )
        )
        for forbiddenToken in [
            "client.auth.session(from:",
            "AuthTransitionPolicy.",
            "RevenueCatManager.shared",
            "EntitlementManager.shared",
            "KeychainManager.shared",
            "MerianLog"
        ] {
            #expect(!authenticationCallbackFacade.contains(forbiddenToken))
        }
        for requiredToken in [
            "AuthenticationCallbackTransitionBoundary(",
            "AuthenticationCallbackSessionBoundary(",
            "AuthenticationCallbackCompletionBoundary(",
            ".installCallbackSession(from: url)",
            "supabaseAuthSessionService.currentSession().map(",
            "installAndAdopt:",
            "RevenueCatManager.shared",
            "EntitlementManager.shared.beginSession(",
            "KeychainManager.shared.set(",
            "entryPolicy: .completeMutatedOAuthSession",
            "diagnostics: .live"
        ] {
            #expect(authenticationCallbackAssembly.contains(requiredToken))
        }
        #expect(
            !authenticationCallbackAssembly.contains(
                "client.auth.currentSession"
            )
        )
        try expectOrder(
            [
                ".installCallbackSession(from: url)",
                "didMutateSession()",
                "adoptAuthTransitionSession(",
                "return installed"
            ],
            in: authenticationCallbackAssembly
        )
        for requiredToken in [
            "OAuthSignInWorkflow.replacingSession(",
            "AuthTransitionPolicy.acceptsAuthenticationCallbackTarget(",
            "AuthTransitionPolicy.shouldClearOAuthSessionAfterFailure(",
            "await session.ensurePurchaseIdentityReady(transition)",
            "await session.beginEntitlementSession(transition)",
            "dependencies.completion.markAuthenticatedOAuth("
        ] {
            #expect(authenticationCallbackCoordinator.contains(requiredToken))
        }
        try expectOrder(
            [
                ".verifyExpectedSessionIfPresent(transition)",
                "try Task.checkCancellation()",
                ".installingSession",
                "OAuthSignInWorkflow.replacingSession(",
                "AuthTransitionPolicy.acceptsAuthenticationCallbackTarget(",
                "dependencies.transition.currentSessionMatches(transition)",
                "session.publish()",
                ".bindingPurchases",
                "await session.ensurePurchaseIdentityReady(transition)",
                "session.purchaseIdentityIsReady()",
                "await session.beginEntitlementSession(transition)",
                "verifyExpectedSession(",
                ".finalizing",
                "markAuthenticatedOAuth("
            ],
            in: authenticationCallbackCoordinator
        )
        for requiredCopy in [
            "Ignored an authentication callback while another identity transition is pending.",
            "Ignored an authentication callback that cannot replace the current signed-out profile.",
            "Authentication callback failed; kind="
        ] {
            #expect(authenticationCallbackDiagnostics.contains(requiredCopy))
            #expect(!aggregate.contains(requiredCopy))
        }
        for forbiddenToken in [
            "import Supabase",
            ".shared",
            "SupabaseManager",
            "Task {",
            "Task.detached",
            "URLSession"
        ] {
            #expect(!authenticationCallbackDiagnostics.contains(forbiddenToken))
        }
        for forbiddenToken in [
            "import AuthenticationServices",
            "import CryptoKit",
            "import GoogleSignIn",
            "import UIKit",
            "MerianLog",
            "SupabaseManager",
            "Task {",
            "Task.detached",
            "URLSession"
        ] {
            #expect(
                !appleCredentialRegistrationLiveService.contains(
                    forbiddenToken
                )
            )
        }
        for forbiddenToken in [
            ".shared",
            "SupabaseManager",
            "Task {",
            "Task.detached",
            "URLSession"
        ] {
            #expect(
                !appleCredentialRegistrationService.contains(
                    forbiddenToken
                )
            )
        }
        #expect(
            authSessionService.contains(
                "@MainActor\nstruct SupabaseAuthSessionService"
            )
        )
        for requiredToken in [
            "func readSession() async throws -> Session",
            "func currentSession() -> Session?",
            "func linkIdentity(",
            "func installSession(",
            "func installCallbackSession(from url: URL)",
            "func updateProfileMetadata(",
            "func signInSession(from session: Session)",
            "OpenIDConnectCredentials(",
            "UserAttributes(data: values)"
        ] {
            #expect(authSessionService.contains(requiredToken))
            #expect(!aggregate.contains(requiredToken))
        }
        for requiredToken in [
            "static func live(client: SupabaseClient) -> Self",
            "client.auth.session",
            "client.auth.currentSession",
            "client.auth.linkIdentityWithIdToken(",
            "client.auth.signInWithIdToken(",
            "client.auth.session(from: url)",
            "client.auth.update(user: attributes)"
        ] {
            #expect(authSessionLiveAdapter.contains(requiredToken))
        }
        for token in [
            "client.auth.linkIdentityWithIdToken(",
            "client.auth.signInWithIdToken(",
            "client.auth.session(from: url)",
            "client.auth.update(user: attributes)"
        ] {
            expectOwners(
                containing: token,
                in: allNetworkSources,
                equal: [
                    "Auth/Services/SupabaseAuthSessionService+Live.swift"
                ]
            )
        }
        expectOwners(
            containing: "client.auth.authStateChanges",
            in: allNetworkSources,
            equal: [
                "Auth/Services/AuthSessionLifecycleLiveProvider+Live.swift"
            ]
        )
        #expect(
            lifecycleLiveAdapter.components(
                separatedBy: "client.auth.authStateChanges"
            ).count == 2
        )
        expectOwners(
            containing: "client.auth.signInAnonymously()",
            in: allNetworkSources,
            equal: [
                "Auth/Services/AuthSessionBootstrapLiveService+Live.swift"
            ]
        )
        #expect(
            bootstrapLiveAdapter.components(
                separatedBy: "client.auth.signInAnonymously()"
            ).count == 2
        )
        expectOwners(
            containing: "client.auth.refreshSession()",
            in: allNetworkSources,
            equal: [
                "Auth/Services/SupabaseAuthSessionService+Live.swift"
            ]
        )
        #expect(
            authSessionLiveAdapter.components(
                separatedBy: "client.auth.refreshSession()"
            ).count == 2
        )
        expectOwners(
            containing: "client.auth.session(from:",
            in: allNetworkSources,
            equal: [
                "Auth/Services/SupabaseAuthSessionService+Live.swift"
            ]
        )
        #expect(
            authSessionLiveAdapter.components(
                separatedBy: "client.auth.session(from:"
            ).count == 2
        )
        #expect(!aggregate.contains("client.auth.session(from:"))
        expectOwners(
            containing: "client.auth.signOut(scope: .local)",
            in: allNetworkSources,
            equal: [
                "Auth/Services/SupabaseAuthSessionService+Live.swift"
            ]
        )
        #expect(
            authSessionLiveAdapter.components(
                separatedBy: "client.auth.signOut(scope: .local)"
            ).count == 2
        )
        for token in [
            "OpenIDConnectCredentials(",
            "UserAttributes(data: values)"
        ] {
            expectOwners(
                containing: token,
                in: allNetworkSources,
                equal: ["Auth/Services/SupabaseAuthSessionService.swift"]
            )
        }
        for retiredFacadeToken in [
            "private func oauthSignInSession(",
            "private func supabaseOAuthCredentials(",
            "OpenIDConnectCredentials(",
            "UserAttributes(data:"
        ] {
            #expect(!aggregate.contains(retiredFacadeToken))
        }
        for forbiddenToken in [
            ".shared",
            "SupabaseManager",
            "Task {",
            "Task.detached",
            "URLSession",
            "MerianLog"
        ] {
            #expect(!authSessionService.contains(forbiddenToken))
        }
        for forbiddenToken in [
            ".shared",
            "SupabaseManager",
            "Task {",
            "Task.detached",
            "URLSession"
        ] {
            #expect(!authSessionLiveAdapter.contains(forbiddenToken))
        }
        #expect(
            authSessionLiveAdapter.components(
                separatedBy: "client.auth.linkIdentityWithIdToken("
            ).count == 2
        )
        #expect(
            authSessionLiveAdapter.components(
                separatedBy: "client.auth.signInWithIdToken("
            ).count == 2
        )
        #expect(
            authSessionLiveAdapter.components(
                separatedBy: "client.auth.update(user: attributes)"
            ).count == 2
        )
        #expect(oauthCoordinator.contains("private func installSession("))
        #expect(
            oauthCoordinator.contains(
                "guard transition.kind == .oauth(credentials.provider) else"
            )
        )
        #expect(
            oauthDependencies.contains(
                "typealias OAuthSessionMutationObserver = @MainActor () -> Void"
            )
        )
        #expect(
            oauthDependencies.contains(
                "OAuthSessionMutationObserver\n    ) async throws -> OAuthSignInSession"
            )
        )
        #expect(oauthDependencies.contains("let replaceAndAdoptSession:"))
        try expectOrder(
            [
                "supabaseAuthSessionService.installSession(",
                "didMutateSession()",
                "adoptOAuthSignInSession(",
                "return session"
            ],
            in: oauthSessionReplacementAssembly
        )
        #expect(
            oauthCoordinator.components(
                separatedBy: "didMutateSession()"
            ).count == 2,
            "Only direct identity linking may report mutation from the coordinator; replacement reports at the live SDK boundary"
        )
        for replacementForwarding in [
            "transition,\n                        didMutateSession\n                    )",
            "transition,\n                    didMutateSession\n                )"
        ] {
            #expect(
                oauthCoordinator.contains(replacementForwarding),
                "Both OAuth replacement branches must forward the mutation observer"
            )
        }
        for retiredManagerHelper in [
            "private func finalizeOAuthLogin(",
            "static func performAppleCredentialRegistrationWithRetry(",
            "static func performOAuthSessionReplacement<Value>(",
            "static func oauthProviderSubject(from:",
            "private func updateGoogleUserMetadataIfAvailable(",
            "private func updateAppleUserMetadataIfAvailable(",
            "private func formattedAppleDisplayName("
        ] {
            #expect(!aggregate.contains(retiredManagerHelper))
        }
        try expectOrder(
            [
                "OAuthSignInSessionBoundary(",
                "OAuthSignInMergeBoundary(",
                "OAuthSignInCompletionBoundary("
            ],
            in: oauthAssembly
        )
        #expect(
            googleSignIn.contains(
                "oauthProviderSignInCoordinator.signInWithGoogle("
            )
        )
        #expect(
            appleSignIn.contains(
                "oauthProviderSignInCoordinator.startAppleSignIn("
            )
        )
        for retiredProviderOwner in [
            "import AuthenticationServices",
            "import CryptoKit",
            "import GoogleSignIn",
            "GIDSignIn.sharedInstance",
            "ASAuthorizationControllerDelegate",
            "ASAuthorizationControllerPresentationContextProviding",
            "ASWebAuthenticationPresentationContextProviding",
            "SecRandomCopyBytes(",
            "SHA256.hash(",
            "private struct AppleSignInAttempt",
            "private func completeAppleSignIn("
        ] {
            #expect(!aggregate.contains(retiredProviderOwner))
        }
        try expectOrder(
            [
                "OAuthProviderSignInTransitionBoundary(",
                "OAuthProviderAuthorizationBoundary(",
                "OAuthProviderSignInCompletionBoundary(",
                "diagnostics: .live"
            ],
            in: oauthProviderAssembly
        )
        #expect(
            oauthProviderAssembly.contains(
                "registerProviderCredential: registration"
            )
        )
        #expect(
            oauthProviderAssembly.contains(
                "registerAppleRevocationCredential("
            )
        )
        #expect(
            !oauthProviderAssembly.contains("credential.identityToken")
        )
        try expectOrder(
            [
                "let identityToken = authorization.credentials.idToken",
                "registration = {",
                "identityToken: identityToken"
            ],
            in: oauthProviderAssembly
        )
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
            deletionCoordinator.contains(
                "@MainActor\nstruct AccountDeletionCoordinator"
            )
        )
        #expect(
            deletionDependencies.contains(
                "struct AccountDeletionCoordinationDependencies"
            )
        )
        #expect(
            deletionCoordinator.contains("func deleteCurrentAccount(")
        )
        #expect(
            deletionRecoveryCoordinator.contains(
                "@MainActor\nstruct AccountDeletionRecoveryCoordinator"
            )
        )
        #expect(
            deletionRecoveryCoordinator.contains(
                "func resumePendingLocalCleanup("
            )
        )
        #expect(aggregate.contains("AccountDeletionCoordinator("))
        #expect(
            aggregate.contains("AccountDeletionRecoveryCoordinator(")
        )
        #expect(aggregate.contains("accountDeletionDependencies()"))
        for managerHelper in [
            "private func restoreDeferredCachedSessionAndResolveDeletionBarrier",
            "private func resumeCapabilityBackedAccountDeletionV2",
            "private func resumeCapabilityBackedAccountDeletion("
        ] {
            #expect(!aggregate.contains(managerHelper))
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
        #expect(
            purchaseSignOutDependencies.contains(
                "struct PurchaseSignOutDependencies"
            )
        )
        #expect(
            purchaseSignOutCoordinator.contains(
                "@MainActor\nstruct PurchaseIdentitySignOutCoordinator"
            )
        )
        for entryPoint in [
            "func transitionToGhostSession() async -> Bool",
            "func resetGhostSessionForRetry(\n        ownedBy transition:",
            "func retryPendingHandoff() async -> Bool"
        ] {
            #expect(purchaseSignOutCoordinator.contains(entryPoint))
        }
        #expect(
            purchaseSignOutCoordinator.contains(
                "transition.kind == .recovery else { return false }"
            )
        )
        #expect(
            pendingStableResolution.contains(
                "catch {\n            dependencies.journal.setHandoffPending(true)"
            )
        )
        #expect(aggregate.contains("PurchaseIdentitySignOutCoordinator("))
        #expect(
            aggregate.contains("purchaseIdentitySignOutDependencies()")
        )
        #expect(
            !aggregate.contains(
                "private func performTransitionToGhostSession("
            )
        )
        try expectOrder(
            [
                "final class AuthTransitionSingleFlight",
                "func run(",
                "guard !Task.isCancelled else { return false }",
                "if let task"
            ],
            in: coordinators
        )
        try expectOrder(
            [
                "func deleteCurrentAccount(",
                "try Task.checkCancellation()",
                "hasPendingPurchaseIdentityHandoff()",
                "beginTransition("
            ],
            in: deletionCoordinator
        )
        try expectOrder(
            [
                "static func performPurchaseSafeSignOutTransition(",
                "try Task.checkCancellation()",
                "try await prepareAndPersistHandoff()",
                "try Task.checkCancellation()",
                "await performSignOut()",
                "try Task.checkCancellation()",
                "let initialized = await initializeAnonymousSession()",
                "try Task.checkCancellation()",
                "guard initialized else { return false }",
                "try await completeHandoff()"
            ],
            in: purchaseSignOutWorkflow
        )
        try expectOrder(
            [
                "func retryPendingHandoff() async -> Bool",
                "guard !Task.isCancelled else { return false }",
                "beginTransition(.recovery)",
                "await dependencies.session.awaitAccountBoundWorkQuiescence()",
                "loadSDKSession()",
                "completePendingHandoff("
            ],
            in: purchaseSignOutCoordinator
        )
        try expectOrder(
            [
                "private func initializeAnonymousSessionAndCompletePendingHandoff(",
                ".initializeAnonymousSession(transition)",
                "!Task.isCancelled",
                "ownsTransition(transition)",
                "currentSessionMatchesTransition(",
                "completePendingHandoff("
            ],
            in: purchaseSignOutCoordinator
        )
        #expect(
            purchaseSourceHandoffDependencies.contains(
                "struct SourceHandoffDependencies"
            )
        )
        #expect(
            purchaseSourceHandoffCoordinator.contains(
                "@MainActor\nstruct PurchaseIdentitySourceHandoffCoordinator"
            )
        )
        #expect(
            purchaseHandoffAuthJournal.contains(
                "@MainActor\nstruct PurchaseIdentityHandoffAuthJournal"
            )
        )
        #expect(
            purchaseHandoffPreparationCoordinator.contains(
                "@MainActor\nstruct PurchaseHandoffPreparationCoordinator"
            )
        )
        try expectOrder(
            [
                "func prepareLegacyHandoff(",
                "currentSessionMatchesTransition(",
                "loadSDKSession()",
                "try Task.checkCancellation()",
                "prepareLegacyHandoff(sourceUUID)",
                "loadSDKSession()",
                "try Task.checkCancellation()",
                "currentSessionMatchesTransition(transition)"
            ],
            in: purchaseSourceHandoffCoordinator
        )
        try expectOrder(
            [
                "func prepareStableRotation(",
                "persistStableRotation(draft)",
                "try Task.checkCancellation()",
                ".prepareStableRotation(",
                "persistStableRotation(prepared)",
                "try Task.checkCancellation()"
            ],
            in: purchaseHandoffPreparationCoordinator
        )
        try expectOrder(
            [
                "func prepareLegacyHandoff(sourceUserID:",
                ".prepareLegacyHandoff()",
                "let pending = PendingSignOutPurchaseHandoff(",
                "persistLegacyHandoff(pending)",
                "try Task.checkCancellation()"
            ],
            in: purchaseHandoffPreparationCoordinator
        )
        #expect(
            purchaseSignOutAssembly.contains(
                "purchaseIdentitySourceHandoffCoordinator()"
            )
        )
        #expect(
            purchaseSourceHandoffAssembly.contains(
                "PurchaseHandoffPreparationCoordinator("
            )
        )
        for retiredManagerHelper in [
            "private func prepareSignOutPurchaseHandoff(",
            "private func prepareAndPersistPendingPurchasePrincipalAuthRotation(",
            "private func abandonPendingPurchasePrincipalRotationIfSourceRestored(",
            "private func restoreSourceIdentityAfterFailedSignOutIfPossible(",
            "private func abandonPendingSignOutPurchaseHandoffIfSourceRestored("
        ] {
            #expect(!aggregate.contains(retiredManagerHelper))
        }
        #expect(
            purchaseHandoffDependencies.contains(
                "struct PurchaseIdentityHandoffDependencies"
            )
        )
        #expect(
            purchaseHandoffCoordinator.contains(
                "@MainActor\nfinal class PurchaseIdentityHandoffCoordinator"
            )
        )
        #expect(
            purchaseHandoffCoordinator.contains(
                "func completePendingHandoff("
            )
        )
        #expect(
            purchaseHandoffCoordinator.contains(
                "private struct CompletionKey: Equatable"
            )
        )
        #expect(
            purchaseHandoffCoordinator.contains(
                "let transition: AuthTransitionToken?"
            )
        )
        try expectOrder(
            [
                "let key = CompletionKey(",
                "transition: transition",
                "if let task",
                "if activeKey == key",
                "cancel()"
            ],
            in: purchaseHandoffCoordinator
        )
        #expect(
            aggregate.contains(
                "purchaseIdentityHandoffCoordinator.completePendingHandoff("
            )
        )
        #expect(aggregate.contains("purchaseIdentityHandoffDependencies()"))
        for retiredManagerHelper in [
            "private func completePendingPurchasePrincipalAuthRotationIfNeeded(",
            "private func performPendingSignOutPurchaseHandoff(",
            "private func verifyActiveAnonymousSession(",
            "private func cancelSignOutPurchaseHandoffTask("
        ] {
            #expect(!aggregate.contains(retiredManagerHelper))
        }
        for retiredTaskField in [
            "signOutPurchaseHandoffTask:",
            "signOutPurchaseHandoffTaskId:",
            "signOutPurchaseHandoffTargetUserId:",
            "signOutPurchaseHandoffAuthGeneration:"
        ] {
            #expect(!aggregate.contains(retiredTaskField))
        }
        try expectOrder(
            [
                "claimStableRotation:",
                ".claimSignoutRotation(",
                "applyStableBinding:",
                ".linkResolvedPurchasePrincipal(",
                "bindLegacyHandoff:",
                "remoteService.bind(",
                "synchronizeLegacyPurchases:",
                ".synchronizePurchasesAfterIdentityHandoff(",
                "completeLegacyHandoff:",
                "remoteService.complete(",
                "refreshEntitlement:"
            ],
            in: purchaseHandoffAssembly
        )
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
            "struct GhostProfileMergeSessionBoundary",
            "struct GhostProfileMergeQueueBoundary",
            "struct GhostProfileMergeOperationBoundary",
            "struct GhostProfileMergeDependencies"
        ] {
            #expect(ghostMergeDependencies.contains(declaration))
        }
        #expect(
            ghostMergeCoordinator.contains(
                "@MainActor\nfinal class GhostProfileMergeCoordinator"
            )
        )
        #expect(ghostMergeCoordinator.contains("func prepare("))
        #expect(
            ghostMergeCoordinator.contains("func completePendingHandoffs(")
        )
        #expect(
            aggregate.contains(
                "ghostProfileMergeCoordinator.completePendingHandoffs("
            )
        )
        for retiredManagerHelper in [
            "private func prepareGhostProfileMerge(",
            "private func completePendingGhostProfileMergeIfNeeded(",
            "private func performPendingGhostProfileMerge(",
            "private func loadPendingGhostProfileMergeQueue(",
            "private func persistPendingGhostProfileMergeQueue(",
            "private func clearPendingGhostProfileMerge(",
            "private func clearPendingGhostProfileMerges(",
            "private func cancelGhostProfileMergeTask(",
            "nonisolated static func requiresProviderBoundGhostMerge(",
            "nonisolated static func shouldDiscardPendingGhostProfileMerge("
        ] {
            #expect(!aggregate.contains(retiredManagerHelper))
        }
        #expect(
            ghostMergeCoordinator.contains(
                "guard transition.kind == .oauth(provider) else"
            )
        )
        try expectOrder(
            [
                "let preparation = try await dependencies.operations.prepare(",
                "let existing = try loadQueue(",
                "GhostProfileMergePolicy.enqueuing(",
                "try persistQueue(updated",
                "dependencies.setAnalyticsSuppressed(true)",
                "try Task.checkCancellation()"
            ],
            in: ghostMergeCoordinator
        )
        try expectOrder(
            [
                "let key = CompletionKey(",
                "transition: transition",
                "if let task",
                "if activeKey == key",
                "cancel()"
            ],
            in: ghostMergeCoordinator
        )
        for declaration in [
            "struct PublicAuthorRefreshSessionBoundary",
            "struct PublicAuthorRefreshOperationBoundary",
            "struct PublicAuthorRefreshEventBoundary",
            "struct PublicAuthorRefreshDiagnostics",
            "struct PublicAuthorIdentityRefreshDependencies"
        ] {
            #expect(publicAuthorRefreshDependencies.contains(declaration))
            #expect(!aggregate.contains(declaration))
        }
        #expect(
            publicAuthorRefreshCoordinator.contains(
                "@MainActor\nfinal class PublicAuthorIdentityRefreshCoordinator"
            )
        )
        #expect(
            publicAuthorRefreshCoordinator.contains(
                "private var task: Task<Void, Never>?"
            )
        )
        #expect(
            publicAuthorRefreshCoordinator.components(
                separatedBy: "Task {"
            ).count == 2,
            "Public-author refresh must retain one keyed task owner"
        )
        #expect(
            publicAuthorRefreshCoordinator.contains(
                "let task = Task { @MainActor [weak self] in"
            )
        )
        #expect(
            publicAuthorRefreshLiveEffects.contains(
                "enum SupabasePublicAuthorRefreshLiveEffects"
            )
        )
        #expect(publicAuthorRefreshLiveEffects.contains("MerianLog.auth"))
        #expect(
            publicAuthorRefreshLiveEffects.contains(
                "AppDIContainer.shared.appEventPublisher.send("
            )
        )
        #expect(
            aggregate.contains(
                "publicAuthorIdentityRefreshCoordinator.scheduleIfNeeded("
            )
        )
        #expect(
            aggregate.contains("publicAuthorIdentityRefreshDependencies()")
        )
        for retiredManagerMember in [
            "publicAuthorIdentityRefreshTask:",
            "publicAuthorIdentityRefreshTaskId:",
            "publicAuthorIdentityRefreshTaskUserId:",
            "lastPublicAuthorIdentityRefreshUserId:"
        ] {
            #expect(!aggregate.contains(retiredManagerMember))
        }
        for retiredManagerHelper in [
            "private func refreshPublicAuthorIdentity(",
            "private func refreshPublicAuthorIdentityForRestoredSession(",
            "private func cancelPublicAuthorIdentityRefreshTask(",
            "private func publishPublicAuthorIdentityChanged("
        ] {
            #expect(!aggregate.contains(retiredManagerHelper))
        }
        for declaration in [
            "struct AccountBoundWorkCoordinator",
            "struct AuthTransitionCoordinator",
            "final class AuthTransitionSingleFlight"
        ] {
            #expect(coordinators.contains(declaration))
            #expect(!aggregate.contains(declaration))
        }
        #expect(
            runtimeState.contains(
                "@MainActor\n@Observable\nfinal class AuthRuntimeState"
            )
        )
        #expect(
            aggregate.contains(
                "private let authRuntimeState = AuthRuntimeState()"
            )
        )
        for runtimeOwner in [
            "private var transitionCoordinator = AuthTransitionCoordinator()",
            "private var analyticsGenerations: [UUID: UInt] = [:]",
            "private var accountWorkCoordinator =",
            "private var accountWorkDrainWaiters:",
            "private(set) var sessionGeneration: UInt64 = 0",
            "private(set) var isSigningOut = false"
        ] {
            #expect(runtimeState.contains(runtimeOwner))
        }
        for retiredFacadeStorage in [
            "private var authTransitionCoordinator",
            "private var authTransitionAnalyticsGenerations",
            "private var accountBoundWorkCoordinator",
            "private var accountBoundWorkDrainWaiters",
            "private var authSessionGeneration: UInt64 = 0",
            "private(set) var isSigningOut = false"
        ] {
            #expect(!aggregate.contains(retiredFacadeStorage))
        }
        for requiredCancellation in [
            "authSessionLifecycleLiveProvider.cancel()",
            "authHistoricalSessionSyncLiveService.cancel()",
            "authSessionBootstrapCoordinator.cancel()",
            "ghostProfileMergeCoordinator.cancel()",
            "purchaseIdentityHandoffCoordinator.cancel()",
            "purchaseIdentitySessionCoordinator.cancelResolution()",
            "authLocalSignOutCoordinator.cancel()",
            "publicAuthorIdentityRefreshCoordinator.cancel()",
            "appleCredentialRevocationCoordinator.cancel()",
            "appleCredentialRevocationLiveProvider.stopObserving()",
            "oauthProviderSignInCoordinator.cancel()",
            "appleOAuthAuthorizationLiveProvider.cancel()"
        ] {
            #expect(managerDeinitialization.contains(requiredCancellation))
        }
        try expectOrder(
            [
                "dependencies.advanceAuthGeneration()",
                "dependencies.authContextWillChange()",
                "dependencies.observeAuthSession(state.session)",
                "dependencies.accountDeletionCleanupPending()",
                "replayCoordinator.observeLifecycleEvent("
            ],
            in: lifecycleLiveProvider
        )
        for declaration in [
            "struct AppleCredentialRevocationIdentity",
            "enum AppleCredentialRevocationLookupResult",
            "enum AppleCredentialRevocationDiagnostic",
            "struct AppleCredentialRevocationSessionBoundary",
            "enum AppleCredentialRevocationClearOutcome",
            "struct AppleRevocationOperationBoundary",
            "struct AppleCredentialRevocationDependencies"
        ] {
            #expect(appleRevocationDependencies.contains(declaration))
            #expect(!aggregate.contains(declaration))
        }
        #expect(
            appleRevocationCoordinator.contains(
                "@MainActor\nfinal class AppleCredentialRevocationCoordinator"
            )
        )
        #expect(
            appleRevocationCoordinator.contains(
                "private var task: Task<Void, Never>?"
            )
        )
        #expect(
            appleRevocationCoordinator.components(
                separatedBy: "Task {"
            ).count == 2,
            "Apple credential revalidation must retain one task owner"
        )
        #expect(
            appleRevocationCoordinator.contains(
                "guard self?.attemptIsCurrent("
            )
        )
        #expect(
            appleRevocationCoordinator.contains(
                "task = Task { @MainActor [weak self] in"
            ),
            "The retained task must keep the coordinator weak across provider and recovery suspension"
        )
        #expect(
            appleRevocationCoordinator.contains(
                "contextGeneration == attempt.contextGeneration"
            )
        )
        #expect(
            appleRevocationDependencies.contains(
                "clearLocalSessionIfCurrent: @MainActor (\n        AppleCredentialRevocationIdentity\n    ) async -> AppleCredentialRevocationClearOutcome"
            )
        )
        try expectOrder(
            [
                "case .deferred:",
                "if self.attemptIsCurrent(",
                "self.deferAttemptIfCurrent(taskID)",
                "self.rejectAttemptIfCurrent("
            ],
            in: appleRevocationCoordinator
        )
        #expect(
            appleRevocationCoordinator.contains(
                "guard taskID == completedTaskID else { return }"
            )
        )
        #expect(
            appleRevocationLiveProvider.contains(
                "ASAuthorizationAppleIDProvider.credentialRevokedNotification"
            )
        )
        #expect(
            appleRevocationLiveProvider.contains(
                "private final class AppleRevocationObserverRegistration {"
            )
        )
        #expect(!appleRevocationLiveProvider.contains("@unchecked Sendable"))
        #expect(
            appleRevocationLiveProvider.contains(
                "private var observerRegistration: AppleRevocationObserverRegistration?"
            )
        )
        #expect(appleRevocationLiveProvider.contains("queue: .main"))
        #expect(
            appleRevocationLiveProvider.contains("MainActor.assumeIsolated")
        )
        #expect(
            !appleRevocationLiveProvider.contains(
                "private var observer: NSObjectProtocol?"
            )
        )
        #expect(appleRevocationLiveProvider.contains("getCredentialState("))
        #expect(
            appleRevocationDiagnostics.contains(
                "enum AppleCredentialRevocationLiveDiagnostics"
            )
        )
        #expect(appleRevocationDiagnostics.contains("MerianLog.auth"))
        #expect(
            aggregate.contains(
                "appleCredentialRevocationCoordinator"
            )
        )
        #expect(
            aggregate.contains(
                "appleCredentialRevocationDependencies()"
            )
        )
        #expect(
            appleRevocationAssembly.contains(
                "let liveProvider = appleCredentialRevocationLiveProvider"
            )
        )
        #expect(
            appleRevocationAssembly.contains(
                "lookupCredentialState: { providerSubject in"
            )
        )
        #expect(
            appleRevocationAssembly.contains(
                "clearLocalSessionIfCurrent: { [weak self] expectedIdentity in"
            )
        )
        #expect(
            appleRevocationAssembly.contains(
                "self.appleCredentialRevocationIdentity()\n                            == expectedIdentity"
            )
        )
        for requiredToken in [
            "case .cleared:\n                        return .cleared",
            "case .rejected, .blockedByPurchaseHandoff:\n                        return .deferred",
            "private func publishPurchaseIdentityHandoffPending(",
            "appleCredentialRevocationCoordinator.resumeDeferredIfNeeded("
        ] {
            #expect(aggregate.contains(requiredToken))
        }
        #expect(
            aggregate.components(
                separatedBy:
                    "RevenueCatManager.shared.setPurchaseIdentityHandoffPending"
            ).count == 2,
            "Purchase-handoff projection and Apple replay must share one facade helper"
        )
        #expect(
            !appleRevocationAssembly.contains(
                "lookupCredentialState: { [weak self]"
            ),
            "Provider lookup suspension must not promote the manager"
        )
        for retiredManagerMember in [
            "appleCredentialRevocationObserver:",
            "pendingAppleCredentialRevalidation"
        ] {
            #expect(!aggregate.contains(retiredManagerMember))
        }
        for retiredManagerHelper in [
            "revalidateAppleCredentialAfterRevocationNotification",
            "shouldClearLocalSessionAfterAppleCredentialState"
        ] {
            #expect(!aggregate.contains(retiredManagerHelper))
        }
        #expect(
            !aggregate.contains(
                "ASAuthorizationAppleIDProvider.credentialRevokedNotification"
            )
        )
        #expect(!aggregate.contains("getCredentialState("))

        for source in [
            models,
            lifecycleModels,
            lifecycleDependencies,
            lifecycleCoordinator,
            lifecycleReconciliationCoordinator,
            bootstrapDependencies,
            bootstrapCoordinator,
            recoveryDependencies,
            recoveryCoordinator,
            localSignOutCoordinator,
            oauthModels,
            oauthIdentityTokenPolicy,
            oauthWorkflow,
            oauthDependencies,
            oauthCoordinator,
            presentationPolicy,
            transitionPolicy,
            deletionPolicy,
            coordinators,
            runtimeState,
            deletionWorkflow,
            deletionDependencies,
            deletionCoordinator,
            deletionRecoveryCoordinator,
            purchaseSignOutWorkflow,
            purchaseSignOutDependencies,
            purchaseSignOutCoordinator,
            purchaseHandoffDependencies,
            purchaseHandoffCoordinator,
            ghostMergePolicy,
            ghostMergeWorkflow,
            ghostMergeDependencies,
            ghostMergeCoordinator,
            publicAuthorRefreshDependencies,
            publicAuthorRefreshCoordinator,
            appleRevocationDependencies,
            appleRevocationCoordinator
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
        #expect(!lifecycleModels.contains("Task {"))
        #expect(!lifecycleDependencies.contains("Task {"))
        #expect(!lifecycleCoordinator.contains("Task {"))
        #expect(!lifecycleCoordinator.contains("MerianLog"))
        #expect(!lifecycleReconciliationCoordinator.contains("MerianLog"))
        #expect(!bootstrapDependencies.contains("Task {"))
        #expect(!bootstrapDependencies.contains("MerianLog"))
        #expect(!bootstrapCoordinator.contains("MerianLog"))
        #expect(!recoveryDependencies.contains("Task {"))
        #expect(!recoveryDependencies.contains("MerianLog"))
        #expect(!recoveryCoordinator.contains("Task {"))
        #expect(!recoveryCoordinator.contains("MerianLog"))
        #expect(!localSignOutCoordinator.contains("MerianLog"))
        #expect(!oauthModels.contains("Task {"))
        #expect(!oauthIdentityTokenPolicy.contains("Task {"))
        #expect(!oauthWorkflow.contains("Task {"))
        #expect(!oauthDependencies.contains("Task {"))
        #expect(!oauthCoordinator.contains("Task {"))
        #expect(!oauthCoordinator.contains("MerianLog"))
        #expect(!presentationPolicy.contains("Task {"))
        #expect(!transitionPolicy.contains("Task {"))
        #expect(!runtimeState.contains("Task {"))
        #expect(!runtimeState.contains("MerianLog"))
        #expect(!deletionPolicy.contains("Task {"))
        #expect(!deletionWorkflow.contains("Task {"))
        #expect(!deletionDependencies.contains("Task {"))
        #expect(!deletionCoordinator.contains("Task {"))
        #expect(!deletionRecoveryCoordinator.contains("Task {"))
        #expect(!deletionCoordinator.contains("MerianLog"))
        #expect(!deletionRecoveryCoordinator.contains("MerianLog"))
        #expect(!deletionDependencies.contains("MerianLog"))
        #expect(!purchaseSignOutWorkflow.contains("Task {"))
        #expect(!purchaseSignOutDependencies.contains("Task {"))
        #expect(!purchaseSignOutCoordinator.contains("Task {"))
        #expect(!purchaseHandoffDependencies.contains("Task {"))
        #expect(!ghostMergePolicy.contains("Task {"))
        #expect(!ghostMergeWorkflow.contains("Task {"))
        #expect(!ghostMergeDependencies.contains("Task {"))
        #expect(!purchaseSignOutWorkflow.contains("MerianLog"))
        #expect(!purchaseSignOutDependencies.contains("MerianLog"))
        #expect(!purchaseSignOutCoordinator.contains("MerianLog"))
        #expect(!purchaseHandoffDependencies.contains("MerianLog"))
        #expect(!purchaseHandoffCoordinator.contains("MerianLog"))
        #expect(!ghostMergeWorkflow.contains("MerianLog"))
        #expect(!ghostMergeDependencies.contains("MerianLog"))
        #expect(!ghostMergeCoordinator.contains("MerianLog"))
        #expect(!publicAuthorRefreshDependencies.contains("MerianLog"))
        #expect(!publicAuthorRefreshCoordinator.contains("MerianLog"))
        #expect(!appleRevocationDependencies.contains("Task {"))
        #expect(!appleRevocationDependencies.contains("MerianLog"))
        #expect(!appleRevocationCoordinator.contains("MerianLog"))
        #expect(
            coordinators.components(separatedBy: "Task {").count == 2,
            "Auth transition coordinators must retain one sign-out task owner"
        )
        #expect(
            coordinators.contains(
                "@MainActor\nfinal class AuthTransitionSingleFlight"
            )
        )
        #expect(coordinators.contains("private var task: Task<Bool, Never>?"))
        #expect(coordinators.contains("let task = Task { @MainActor in"))
        #expect(
            purchaseHandoffCoordinator.components(
                separatedBy: "Task {"
            ).count == 2,
            "Purchase handoff completion must retain one keyed task owner"
        )
        #expect(
            purchaseHandoffCoordinator.contains(
                "private var task: Task<Bool, Never>?"
            )
        )
        #expect(
            purchaseHandoffCoordinator.contains(
                "let task = Task { @MainActor [weak self] in"
            )
        )
        #expect(
            ghostMergeCoordinator.components(
                separatedBy: "Task {"
            ).count == 2,
            "Ghost merge completion must retain one keyed task owner"
        )
        #expect(
            ghostMergeCoordinator.contains(
                "private var task: Task<Bool, Never>?"
            )
        )
        #expect(
            ghostMergeCoordinator.contains(
                "let task = Task { @MainActor [weak self] in"
            )
        )

        let foundationTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/AuthTransitionFoundationTests.swift"
        )
        let runtimeStateTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/AuthRuntimeStateTests.swift"
        )
        let aggregateTests = try source(
            "apps/ios/MerianTests/Core/Network/SupabaseManagerTests.swift"
        )
        let lifecycleCoordinatorTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/AuthSessionLifecycleCoordinatorTests.swift"
        )
        let lifecycleReconciliationTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/AuthLifecycleReplayCoordinatorTests.swift"
        )
        let lifecycleLiveProviderTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/AuthSessionLifecycleLiveProviderTests.swift"
        )
        let historicalSessionSyncTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/AuthHistoricalSessionSyncLiveServiceTests.swift"
        )
        let bootstrapCoordinatorTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/AuthSessionBootstrapCoordinatorTests.swift"
        )
        let bootstrapLiveServiceTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/AuthSessionBootstrapLiveServiceTests.swift"
        )
        let recoveryCoordinatorTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/AuthSessionRecoveryCoordinatorTests.swift"
        )
        let localSignOutCoordinatorTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/AuthLocalSignOutCoordinatorTests.swift"
        )
        let oauthIdentityTokenPolicyTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/OAuthIdentityTokenPolicyTests.swift"
        )
        let oauthModelsTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/OAuthSignInModelsTests.swift"
        )
        let oauthWorkflowTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/OAuthSignInWorkflowTests.swift"
        )
        let oauthCoordinatorTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/OAuthSignInCoordinatorTests.swift"
        )
        let oauthCancellationTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/OAuthSignInCancellationTests.swift"
        )
        let oauthProviderCoordinatorTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/OAuthProviderSignInCoordinatorTests.swift"
        )
        let googleAuthorizationProviderTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/GoogleOAuthAuthorizationLiveProviderTests.swift"
        )
        let appleAuthorizationProviderTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/AppleOAuthAuthorizationLiveProviderTests.swift"
        )
        let appleCredentialRegistrationServiceTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/AppleOAuthCredentialRegistrationServiceTests.swift"
        )
        let authSessionServiceTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/SupabaseAuthSessionServiceTests.swift"
        )
        let authenticationCallbackSupport = try source(
            "apps/ios/MerianTests/Core/Network/Auth/AuthenticationCallbackCoordinatorTestSupport.swift"
        )
        let authenticationCallbackTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/AuthenticationCallbackCoordinatorTests.swift"
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
        let deletionCoordinatorTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/AccountDeletionCoordinatorTests.swift"
        )
        let deletionRecoveryCoordinatorTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/AccountDeletionRecoveryCoordinatorTests.swift"
        )
        let purchaseSignOutTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/PurchaseIdentitySignOutWorkflowTests.swift"
        )
        let purchaseSignOutCoordinatorTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/PurchaseIdentitySignOutCoordinatorTests.swift"
        )
        let purchaseHandoffCoordinatorTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/PurchaseIdentityHandoffCoordinatorTests.swift"
        )
        let ghostMergePolicyTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/GhostProfileMergePolicyTests.swift"
        )
        let ghostMergeCoordinatorTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/GhostProfileMergeCoordinatorTests.swift"
        )
        let publicAuthorRefreshSupport = try source(
            "apps/ios/MerianTests/Core/Network/Auth/PublicAuthorIdentityRefreshCoordinatorTestSupport.swift"
        )
        let publicAuthorRefreshTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/PublicAuthorIdentityRefreshCoordinatorTests.swift"
        )
        let appleRevocationSupport = try source(
            "apps/ios/MerianTests/Core/Network/Auth/AppleCredentialRevocationCoordinatorTestSupport.swift"
        )
        let appleRevocationTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/AppleCredentialRevocationCoordinatorTests.swift"
        )
        let appleRevocationLiveProviderTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/AppleCredentialRevocationLiveProviderTests.swift"
        )
        let ghostMergeRemoteServiceTests = try source(
            "apps/ios/MerianTests/Core/Security/GhostProfileMerge/GhostProfileMergeRemoteServiceTests.swift"
        )
        let ghostMergeWorkflowTests = try source(
            "apps/ios/MerianTests/Core/Network/Auth/GhostProfileMergeWorkflowTests.swift"
        )
        for name in [
            "testDeletionCleanupBarrierStopsBeforeDurableOrSessionEffects",
            "testActiveTransitionDefersBeforeDurableRecovery",
            "testDeferredSignOutReplaysAfterTransitionFinishes",
            "testDurableFenceReadsFailClosedIndependently",
            "testAnonymousHandoffCompletesBeforeEntitlement",
            "testIdentityChangeResetsIdentityStateBeforePublication",
            "testRestoredSourceAbandonsHandoffBeforeRelinkingAndSyncing",
            "testStaleSessionAfterTelemetryStopsBeforeEntitlementAndSync",
            "testTransitionOverlapAfterTelemetryStopsBeforeEntitlement",
            "testStaleSessionAfterEntitlementStopsBeforeHistoricalSync",
            "testAwaitingRefreshPublishesKnownAccountWithoutIdentityWork",
            "testSigningOutIgnoresAuthenticatedAndRefreshEvents",
            "testSignedOutFinishesPublicationAfterPurchaseSignOut",
            "testStaleSignOutPostflightCannotCancelNewSessionWork",
            "testInconsistentEventFailsClosedBeforeSessionPublication"
        ] {
            #expect(lifecycleCoordinatorTests.contains("func \(name)("))
            #expect(!aggregateTests.contains("func \(name)("))
        }
        for name in [
            "testReplacementCancelsStaleLifecycleReplay",
            "testCoordinatorDeinitDoesNotAwaitSuspendedReplay",
            "testNewTransitionCancelsReplayAndCarriesDeferredObligation",
            "testNewStableEventClearsDeferredReplayObligation",
            "testStableTransitionWithoutDeferredEventDoesNotScheduleReplay"
        ] {
            #expect(lifecycleReconciliationTests.contains("func \(name)("))
        }
        for name in [
            "testSDKStateMapsInitialExpiredSessionWithoutLosingIdentity",
            "testListenerPreservesContextInvalidationAndProjectionOrder",
            "testDeferredEventReplaysCurrentSnapshotAfterTransition",
            "testReplayRejectsSnapshotReplacedBeforeTaskRuns",
            "testRestartClearsDeferredReplayFromReplacedListener",
            "testRestartCancelsTrailingEffectFromSuspendedListener",
            "testProviderDeinitCancelsSuspendedListenerWithoutSelfRetention"
        ] {
            #expect(lifecycleLiveProviderTests.contains("func \(name)("))
        }
        for name in [
            "testSyncPreservesStampPreferencesFenceAndScanOrder",
            "testSessionDriftAfterPreferenceSyncStopsHistoricalScan",
            "testServiceDeinitCancelsSuspendedSyncWithoutSelfRetention"
        ] {
            #expect(historicalSessionSyncTests.contains("func \(name)("))
        }
        for name in [
            "testTestAndDeletionGatesStopBeforeSignOutOrSessionWork",
            "testAlreadyCancelledCallerStopsBeforeSignOutOrSessionWork",
            "testSignOutCompletesBeforeTransitionOrSessionResolution",
            "testCallerCancellationWhileAwaitingSignOutStopsBeforeSessionWork",
            "testQuiescenceFailureStopsBeforeSessionResolution",
            "testPublishedSessionReusesAccountWorkLeaseWithoutTransition",
            "testStaleAccountWorkLeaseRejectsPublishedSessionAfterReadiness",
            "testOwnerlessCallersShareOneAnonymousBootstrapTask",
            "testDifferentTransitionCannotJoinActiveBootstrap",
            "testOwnerlessCallerRejectsReplacedAnonymousTransitionTask",
            "testSessionMissingCreatesAndPublishesAnonymousIdentity",
            "testNetworkSessionFailurePreservesIdentityWithoutAnonymousSignIn",
            "testAnonymousCreationFailureReportsWithoutPublishing",
            "testCancellationAfterSessionLoadStopsBeforeAnonymousCreation",
            "testTransitionChangeAfterSessionLoadStopsBeforePublication",
            "testCanceledPredecessorCannotClearReplacementTaskState",
            "testResolvedSessionSchedulesRefreshBeforePurchaseReadiness",
            "testCancellationDuringExistingSessionReadinessRejectsCompletion",
            "testCancellationDuringAnonymousReadinessRejectsCompletion",
            "testSessionReplacementDuringPurchaseReadinessRejectsCompletion"
        ] {
            #expect(bootstrapCoordinatorTests.contains("func \(name)("))
            #expect(!aggregateTests.contains("func \(name)("))
        }
        for name in [
            "testCurrentAndLoadedSessionsProjectIdentityAndExpiry",
            "testAnonymousCreationProjectsFreshIdentity",
            "testMissingSessionClassifierRecognizesSDKAndCompatibilityErrors",
            "testMissingSessionClassifierRejectsUnrelatedError",
            "testLoadedSessionPreservesSDKFailure"
        ] {
            #expect(bootstrapLiveServiceTests.contains("func \(name)("))
        }
        for name in [
            "testOrdinaryRefreshPublishesBeforePurchaseReadiness",
            "testCancelledOrdinaryRefreshStopsBeforeTransition",
            "testExpectedSessionDriftDuringQuiescenceStopsBeforeRefresh",
            "testCancellationDuringRefreshStopsBeforePublication",
            "testTransitionOwnedRefreshSkipsIdentityFollowUp",
            "testTransitionOwnedRefreshRejectsDifferentIdentity",
            "testAnonymousResetRejectsPendingPurchaseHandoff",
            "testAnonymousResetRestoresPurchaseAndEntitlementReadiness",
            "testCancellationDuringPurchaseReadinessStopsBeforeEntitlement",
            "testAnonymousResetRejectsUnreadyPurchaseIdentity",
            "testAnonymousResetRejectsFinalSessionReplacement",
            "testLocalClearPreservesSessionWhilePurchaseHandoffIsPending",
            "testLocalClearCompletesAfterSDKSignOutFailure",
            "testLocalClearCompletesWhenCancelledDuringSDKSignOut",
            "testOwnedLocalClearDoesNotFinishCallersTransition",
            "testMutatedOAuthCleanupStartsForCancelledTransitionOwner",
            "testLocalClearRejectsSessionReplacementDuringQuiescence"
        ] {
            #expect(recoveryCoordinatorTests.contains("func \(name)("))
            #expect(!aggregateTests.contains("func \(name)("))
        }
        for name in [
            "testRefreshedAndLoadedSessionsProjectIdentityAndUser",
            "testRefreshFailurePropagates",
            "testLoadFailurePropagates"
        ] {
            #expect(authSessionServiceTests.contains("func \(name)("))
        }
        for name in [
            "testSignOutPreservesStateTransitionAndEffectOrder",
            "testConcurrentSignOutCallsShareOneRetainedTask",
            "testSDKFailureStillCompletesExternalAndLocalCleanup",
            "testFailedQuiescenceStopsBeforeLocalStateMutation",
            "testTransitionLossAfterBootstrapStopsBeforeSDKMutation",
            "testCancellationWhileAwaitingBootstrapStopsBeforeSDKMutation",
            "testCancellationRetainsTaskUntilDeferredCleanupFinishes",
            "testCancellationAfterSDKMutationStillCompletesExternalCleanup",
            "testFacadeClosesRequestGateBeforeSDKInvalidation"
        ] {
            #expect(localSignOutCoordinatorTests.contains("func \(name)("))
            #expect(!aggregateTests.contains("func \(name)("))
        }
        for name in [
            "testSignOutDelegatesExactlyOnce",
            "testSignOutFailurePropagates"
        ] {
            #expect(authSessionServiceTests.contains("func \(name)("))
        }
        #expect(
            !aggregateTests.contains(
                "testSignOutClosesAuthenticatedRequestGateBeforeRemoteInvalidation"
            )
        )
        #expect(
            recoveryCoordinatorTests.components(
                separatedBy: "    func test"
            ).count == 19
        )
        #expect(
            publicAuthorRefreshSupport.contains(
                "actor PublicAuthorIdentityRefreshTestGate"
            )
        )
        for name in [
            "testSchedulingGatesRejectTestsTransitionsAndAnonymousSessions",
            "testScheduledRefreshPreservesMergeLeaseRefreshAndPublishOrder",
            "testSameActiveUserSharesTheExistingScheduledAttempt",
            "testStaleScheduledUserCannotReplaceCurrentUserRefresh",
            "testCancellationBeforeScheduledTaskStartsDoesNotOpenLease",
            "testCanceledPredecessorCannotClearReplacementTaskState",
            "testCancelDuringMergeStopsBeforeRemoteRefreshAndPublication",
            "testStaleOuterLeaseAfterMergeStopsBeforeRemoteRefresh",
            "testRemoteFailureRollsBackBothLeasesAndReportsWithoutPublishing",
            "testStaleLeaseAfterRemoteRefreshStopsBeforePublication",
            "testPublishedUserDriftAfterRemoteRefreshStopsPublication",
            "testTransitionOwnedRefreshUsesExactSessionWithoutAccountLease",
            "testTransitionOwnedRefreshRejectsStaleSessionBeforeRemoteWork",
            "testAlreadyCancelledDirectRefreshDoesNotOpenLease",
            "testCancellationDuringDirectRefreshRejectsSuccessfulPostflight",
            "testCancelledRemoteFailureDoesNotReportDiagnostic",
            "testOwnerlessRefreshUsesOneLeaseAndRevalidatesIt",
            "testClearingCompletedUserAllowsTheSameUserToRefreshAgain"
        ] {
            #expect(publicAuthorRefreshTests.contains("func \(name)("))
            #expect(!aggregateTests.contains("func \(name)("))
        }
        #expect(
            publicAuthorRefreshTests.components(
                separatedBy: "    func test"
            ).count == 19
        )
        #expect(
            appleRevocationSupport.contains(
                "actor AppleRevocationLookupController"
            )
        )
        for name in [
            "testNotificationWithoutAppleIdentityPerformsNoLookup",
            "testActiveTransitionDefersLookupUntilStableSessionResumes",
            "testAuthorizedCredentialPreservesCurrentSession",
            "testEveryUnauthorizedCredentialStateFailsClosed",
            "testLookupFailureFailsClosedWithDistinctDiagnostic",
            "testSameIdentityGenerationChangeRejectsStaleLookup",
            "testIdentityChangeRejectsPredecessorAndRevalidatesCurrentUser",
            "testTransitionStartingDuringLookupDefersFreshAttempt",
            "testIdentityChangeAtClearBoundaryRejectsStaleClearAndRevalidates",
            "testTransitionAtClearBoundaryDefersUntilStableRevalidation",
            "testRecoveryDeferralWaitsForExplicitStableResume",
            "testContextChangeDuringDeferredClearReplaysWithoutLostWakeup",
            "testOverlappingNotificationsQueueOnlyOneFollowUpLookup",
            "testCancellationBeforeTaskStartsPerformsNoLookup",
            "testCancellationDuringLookupRejectsUnsafeResult",
            "testCoordinatorDeinitDoesNotAwaitLookupCompletion",
            "testUnsafeResultClearsOnceDespiteOverlappingNotification"
        ] {
            #expect(appleRevocationTests.contains("func \(name)("))
            #expect(!aggregateTests.contains("func \(name)("))
        }
        #expect(
            appleRevocationTests.components(
                separatedBy: "    func test"
            ).count == 18
        )
        for name in [
            "testCredentialStateMappingFailsClosedWithoutClearingAuthorizedState",
            "testStartingAndStoppingObservationOwnsExactlyOneRegistration",
            "testProviderDeinitRemovesObservationRegistration",
            "testBackgroundNotificationEntersMainActorHandler"
        ] {
            #expect(
                appleRevocationLiveProviderTests.contains("func \(name)(")
            )
        }
        #expect(
            appleRevocationLiveProviderTests.components(
                separatedBy: "    func test"
            ).count == 5
        )
        #expect(
            !aggregateTests.contains(
                "testAppleCredentialRevocationStateFailsClosedWithoutClearingAuthorizedState"
            )
        )
        for name in [
            "testProviderSubjectReadsBase64URLJWTSubject",
            "testProviderSubjectRejectsMalformedOrUnsafeClaims"
        ] {
            #expect(oauthIdentityTokenPolicyTests.contains("func \(name)("))
            #expect(!aggregateTests.contains("func \(name)("))
        }
        for name in [
            "testProfileMetadataTrimsValuesAndDropsEmptyFields",
            "testMissingAppleNameProducesEmptyMetadata"
        ] {
            #expect(oauthModelsTests.contains("func \(name)("))
        }
        for name in [
            "testOAuthSessionReplacementSuspendsBeforeInstallingAndReconcilesSuccess",
            "testOAuthSessionReplacementReconcilesActualSessionOnFailure",
            "testOAuthSessionReplacementRejectsPreflightCancellation",
            "testOAuthSessionReplacementCancellationAfterSuppressionRestoresSourceWithoutInstalling",
            "testOAuthSessionReplacementCancellationAfterInstallationFailsClosed",
            "testAppleCredentialRegistrationRetriesTheSameDurableRequest",
            "testAppleCredentialRegistrationRejectsCancellationAfterInvoke",
            "testAppleCredentialRegistrationStopsAfterBoundedRetry"
        ] {
            #expect(oauthWorkflowTests.contains("func \(name)("))
            #expect(!aggregateTests.contains("func \(name)("))
        }
        for name in [
            "testExistingAccountUsesReplacementAndSharedCompletionOrder",
            "testAnonymousDirectLinkRetiresGhostProofAfterSameUUIDAdoption",
            "testIdentityConflictPersistsGhostProofBeforeReplacement",
            "testRequiredProviderCredentialPrecedesMetadataAndPurchaseBinding",
            "testProviderCredentialFailureStopsBeforeMetadataAndPurchaseBinding",
            "testAppleRequiresCredentialRegistrationBeforeSessionMutation",
            "testGoogleRejectsCredentialRegistrationBeforeSessionMutation",
            "testProviderMustMatchOwnedTransitionBeforeSessionMutation",
            "testMetadataFailureContinuesWithoutPublicAuthorRefresh",
            "testPendingPurchaseHandoffStopsBeforeProviderMutation",
            "testProviderReadinessFailureStopsBeforeEntitlementAndFinalCommit",
            "testCancelledAnonymousUpgradeDoesNotReachProviderMutation"
        ] {
            #expect(oauthCoordinatorTests.contains("func \(name)("))
        }
        for name in [
            "testCancellationDuringReplacementAdoptsExactTargetBeforeStoppingCompletion",
            "testCancellationDuringAppleRegistrationStopsBeforeMetadata",
            "testCancellationDuringMetadataStopsBeforePublication",
            "testCancellationDuringTelemetryStopsBeforeEntitlement",
            "testCancellationDuringEntitlementStopsBeforeFinalization",
            "testCancellationDuringAuthorRefreshStopsBeforeFinalCommit"
        ] {
            #expect(oauthCancellationTests.contains("func \(name)("))
        }
        for name in [
            "testRejectedGoogleTransitionDoesNotPresentProvider",
            "testRejectedAppleTransitionDoesNotStartAuthorization",
            "testGoogleSuccessPreservesAdmissionVerificationAndCompletionOrder",
            "testGooglePresentationFailureStopsBeforeSessionVerification",
            "testGoogleMissingTokenRevalidatesSessionBeforeStopping",
            "testGoogleProviderFailureRunsRecoveryAndFinishesTransition",
            "testGoogleCompletionFailureReportsObservedSessionMutation",
            "testAppleStartOwnsTransitionSynchronouslyAndCompletesInTask",
            "testAppleBootstrapFailureFinishesSynchronously",
            "testAppleProviderFailureDoesNotRunSessionRecovery",
            "testAppleStaleCallbackCannotCompleteReplacementTransition",
            "testCancellingPendingAppleAuthorizationReleasesAndFinishesIt",
            "testAppleCompletionFailureRunsRecoveryWithMutationEvidence",
            "testCancellingAppleCompletionTaskRunsFailureRecovery"
        ] {
            #expect(oauthProviderCoordinatorTests.contains("func \(name)("))
            #expect(!aggregateTests.contains("func \(name)("))
        }
        #expect(
            oauthProviderCoordinatorTests.components(
                separatedBy: "    func test"
            ).count == 15
        )
        for name in [
            "testMissingPresentationContextStopsBeforeGoogleSDK",
            "testGoogleResponseMapsToProviderNeutralAuthorization",
            "testMissingGoogleIdentityTokenRemainsAProviderOutcome",
            "testPreflightCancellationStopsBeforeGoogleSDK",
            "testCancellationAfterGoogleReturnRejectsMappedAuthorization"
        ] {
            #expect(googleAuthorizationProviderTests.contains("func \(name)("))
        }
        #expect(
            googleAuthorizationProviderTests.components(
                separatedBy: "    func test"
            ).count == 6
        )
        for name in [
            "testStartConfiguresAndRetainsTheExactAuthorizationController",
            "testNonceFailureStopsBeforeRequestConstruction",
            "testMissingAnchorStopsBeforeRequestConstruction",
            "testOverlappingStartCannotReplaceTheRetainedAttempt",
            "testProviderFailureCompletesAndReleasesTheMatchingAttempt",
            "testStaleControllerCannotConsumeTheActiveAttempt",
            "testCancellationRejectsALateDelegateCallback",
            "testAuthorizationMapsAppleCredentialAndRegistrationValues",
            "testAuthorizationRejectsMissingAndMalformedCredentialData",
            "testNonceAndHashUtilitiesPreserveTheAppleContract"
        ] {
            #expect(appleAuthorizationProviderTests.contains("func \(name)("))
        }
        #expect(
            appleAuthorizationProviderTests.components(
                separatedBy: "    func test"
            ).count == 11
        )
        for name in [
            "testRegistrationForwardsExactValuesAndAcceptsRegisteredReceipt",
            "testRegistrationRejectsEveryNonRegisteredReceipt",
            "testRegistrationPreservesTransportFailure"
        ] {
            #expect(
                appleCredentialRegistrationServiceTests.contains(
                    "func \(name)("
                )
            )
            #expect(!aggregateTests.contains("func \(name)("))
        }
        #expect(
            appleCredentialRegistrationServiceTests.components(
                separatedBy: "    func test"
            ).count == 4
        )
        for name in [
            "testReadAndCurrentSessionExposeInjectedSDKState",
            "testAppleLinkMapsExactOpenIDCredentials",
            "testGoogleInstallMapsCredentialsAndReturnsSDKSession",
            "testCallbackInstallForwardsExactURLAndReturnsSDKSession",
            "testCallbackInstallPreservesSDKFailure",
            "testSessionProjectionPreservesIdentityAndAnonymity",
            "testMetadataUpdateBuildsCanonicalAliases",
            "testEmptyMetadataSkipsSDKUpdate",
            "testMetadataUpdatePreservesSDKFailure"
        ] {
            #expect(authSessionServiceTests.contains("func \(name)("))
        }
        #expect(
            authSessionServiceTests.components(
                separatedBy: "    func test"
            ).count == 15
        )
        #expect(
            authenticationCallbackSupport.contains(
                "final class AuthenticationCallbackCoordinatorHarness"
            )
        )
        for name in [
            "testSuccessfulCallbackPreservesCompletionOrder",
            "testPendingPurchaseHandoffRejectsBeforeTransition",
            "testActiveTransitionRejectsOverlappingCallback",
            "testCancellationAfterPreflightStopsBeforeInstallation",
            "testAnonymousSourceRejectsBeforeSessionVerification",
            "testDifferentLinkedTargetClearsMutatedSession",
            "testExactLinkedSourceMayRefreshTheSameAccount",
            "testInstallationFailurePreservesExactSourceSession",
            "testInstallationFailureAfterMutationClearsChangedSession",
            "testSignOutDuringInstallationCannotRepublishSession",
            "testCancellationDuringInstallationClearsMutatedSession",
            "testCancellationDuringPurchaseReadinessStopsEntitlement",
            "testCancellationDuringEntitlementStopsFinalCommit",
            "testUnreadyPurchaseIdentityStopsEntitlementAndFinalCommit",
            "testFinalSessionDriftClearsMutatedSession"
        ] {
            #expect(authenticationCallbackTests.contains("func \(name)("))
            #expect(!aggregateTests.contains("func \(name)("))
        }
        #expect(
            authenticationCallbackTests.components(
                separatedBy: "    func test"
            ).count == 16
        )
        for name in [
            "testStableSourceUsesPreparedRotationBeforeLocalSignOut",
            "testLegacySourceUsesCompatibilityPreparation",
            "testUnreadableJournalFailsClosedBeforeReadingSession",
            "testPendingStableRotationCompletesAgainstExistingAnonymousSession",
            "testPendingProofCancellationDuringAnonymousInitializationStopsCompletion",
            "testPendingRotationCannotReplaceAnUnrelatedLinkedSession",
            "testStableJournalRereadFailureRestoresFailClosedReadiness",
            "testPendingLegacySourceIsAbandonedBeforePreparingReplacement",
            "testPendingLegacyHandoffCannotReplaceUnrelatedLinkedSession",
            "testFailedStablePreparationRestoresOnlyItsSourceSession",
            "testKnownLinkedIdentityRefusesUnverifiedSDKSession",
            "testAnonymousSessionUsesOrdinaryReplacementWithoutPurchaseProof",
            "testRetryRequiresExactAnonymousRecoverySession",
            "testRetryStopsBeforeSessionLoadWhenQuiescenceFails",
            "testCanceledTransitionDoesNotBegin",
            "testRetryRejectsLinkedOrStaleRecoverySession",
            "testRecoveryOwnedResetRequiresRecoveryTokenAndPreservesOwnership"
        ] {
            #expect(purchaseSignOutCoordinatorTests.contains("func \(name)("))
        }
        for name in [
            "testAlreadyCanceledCallerDoesNotStartCompletion",
            "testStableRotationClearsProofAfterExactSessionAndEntitlementChecks",
            "testLegacyHandoffPreservesCompatibilityCompletionOrder",
            "testSameDestinationGenerationAndOwnerShareOneCompletionTask",
            "testNewGenerationCancelsStaleCompletionBeforeProofRemoval",
            "testTransitionOwnerReplacesOwnerlessForSameDestinationAndGeneration",
            "testCanceledLegacyCompletionCannotRetireProofAfterReplacement",
            "testStaleAnonymousSessionRetainsLegacyProof",
            "testTerminalLegacyErrorDiscardsProofButTransientErrorRetainsIt",
            "testUnreadableSelectionFailsClosedBeforeSessionOrProviderWork",
            "testRestoredSourceAbandonsLegacyProofWithoutBindingDestination"
        ] {
            #expect(
                purchaseHandoffCoordinatorTests.contains("func \(name)(")
            )
        }
        #expect(
            foundationTests.contains("private actor AuthTransitionTestGate")
        )
        #expect(!foundationTests.contains("SupabaseManagerTestGate"))
        for name in [
            "testBackgroundAccountWorkQuiescenceFailurePreservesProductLanguage",
            "testAuthTransitionCoordinatorSerializesAllSessionMutations",
            "testDoubleSignOutCallsShareOneTransitionOperationAndResult",
            "testCanceledSingleFlightCallerDoesNotStartOperation",
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
            "testTransitionMutationPublishesObservation",
            "testTransitionOwnsGenerationAnalyticsAndCompletion",
            "testUnexpectedAuthEventInvalidatesTheTransitionGeneration",
            "testAccountWorkLeaseRequiresBothExactSessionProjections",
            "testAccountWorkDrainWaitsForEveryLease",
            "testSignOutStateInvalidatesTheSessionGeneration"
        ] {
            #expect(runtimeStateTests.contains("func \(name)("))
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
            "testFreshV2DeletionSequencesLiveEffectsAndRetiresProofLast",
            "testFreshDeletionRejectsPendingPurchaseBeforeTransition",
            "testFreshDeletionRejectsPreflightCancellationBeforeTransition",
            "testFreshDeletionRejectsExistingRecoveryBeforeTransition"
        ] {
            #expect(deletionCoordinatorTests.contains("func \(name)("))
        }
        for name in [
            "testRecoveryWithoutMarkerIsANoOp",
            "testV2NonCommitRetiresProofThenRestoresExactCachedSession",
            "testV2AcceptedRecoveryCompletesErasureAndAcknowledgement",
            "testV2NonCommitRefusesToPublishAChangedCachedSession",
            "testV2AcknowledgementFailureRetainsCleanupAndProof",
            "testMixedV2EnvelopeChecksLegacyDomainBeforeRestoration",
            "testRetirementRecoveryReverifiesCleanupBeforeProofRemoval",
            "testLookupWithoutProofRestoresSessionWithoutNetworkReplay",
            "testPreparedMarkerWithoutProofCancelsWithoutDestructiveReplay",
            "testPreCapabilityIntakeKeepsV1ProofAcrossAmbiguousReplay",
            "testLegacyIntakeReplaysAuthenticatedRequestAndAcknowledges"
        ] {
            #expect(
                deletionRecoveryCoordinatorTests.contains("func \(name)(")
            )
        }
        for name in [
            "testUserSignOutTransitionInitializesOneAnonymousSessionAfterSignOut",
            "testUserSignOutTransitionPropagatesAnonymousSessionFailure",
            "testUserSignOutTransitionRejectsPreflightCancellation",
            "testUserSignOutCancellationStopsBeforeAnonymousInitialization",
            "testPurchaseSafeSignOutPersistsBeforeClosingAndCompletingIdentity",
            "testPurchaseSafeSignOutNeverClosesSessionWhenPreparationFails",
            "testPurchaseSafeSignOutRejectsPreflightCancellation",
            "testPurchaseSafeSignOutCancellationAfterPreparationStopsBeforeSignOut",
            "testPurchaseSafeSignOutCancellationAfterSignOutStopsBeforeInitialization",
            "testPurchaseSafeSignOutCancellationAfterInitializationStopsBeforeCompletion",
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
            ghostMergeRemoteServiceTests.contains(
                "func testPendingMergeProofIsDiscardedOnlyForTerminalServerCodes("
            )
        )
        #expect(
            !aggregateTests.contains(
                "func testPendingMergeProofIsDiscardedOnlyForTerminalServerCodes("
            )
        )
        for name in [
            "testPreparationPersistsReturnedProofBeforeHonoringCancellation",
            "testPreparationReplacesOnlyMatchingSourceProofInStableOrder",
            "testPreparationRejectsProviderTransitionMismatchBeforeRemoteWork",
            "testPreparationRejectsChangedSessionBeforePersistingProof",
            "testSameTargetAndOwnerShareOneCompletionTask",
            "testDifferentTargetCancelsStaleTaskBeforeProofRemoval",
            "testTransitionOwnerReplacesOwnerlessTaskForSameTarget",
            "testUnreadableQueueFailsClosedBeforeSessionOrRemoteWork",
            "testTransientFailureRetainsProofAndSuppression",
            "testTerminalFailureSynchronizesTargetBeforeClearingProof",
            "testCanceledTerminalResponseCannotSynchronizeOrClearProof",
            "testRetryableHandoffDoesNotBlockLaterHandoffCompletion",
            "testEmptyQueueReopensAnalyticsWithoutSessionOrRemoteWork",
            "testClearingSourcePreservesSuppressionForUnrelatedProofs"
        ] {
            #expect(ghostMergeCoordinatorTests.contains("func \(name)("))
        }
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
        let remoteService = try source(
            "apps/ios/Merian/Core/Security/GhostProfileMerge/Services/GhostProfileMergeRemoteService.swift"
        )
        let liveRemoteService = try source(
            "apps/ios/Merian/Core/Security/GhostProfileMerge/Services/GhostProfileMergeRemoteService+Live.swift"
        )
        let storeTests = try source(
            "apps/ios/MerianTests/Core/Security/GhostProfileMerge/GhostProfileMergeStoreTests.swift"
        )
        let remoteServiceTests = try source(
            "apps/ios/MerianTests/Core/Security/GhostProfileMerge/GhostProfileMergeRemoteServiceTests.swift"
        )

        #expect(
            actualPaths == [
                "Models/GhostProfileMergeModels.swift",
                "Services/GhostProfileMergeRemoteService+Live.swift",
                "Services/GhostProfileMergeRemoteService.swift",
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
        #expect(manager.contains("GhostProfileMergeRemoteService"))
        #expect(manager.contains("dependencies: .live(keychain: keychain)"))
        #expect(store.contains("KeychainKeys.pendingGhostProfileMerge"))
        #expect(!manager.contains("KeychainKeys.pendingGhostProfileMerge"))
        #expect(
            remoteService.contains("struct GhostProfileMergeRemoteService")
        )
        #expect(
            liveRemoteService.contains(
                "extension GhostProfileMergeRemoteService"
            )
        )
        #expect(liveRemoteService.contains("import Supabase"))
        #expect(
            liveRemoteService.components(
                separatedBy: "\"merge-ghost-profile\""
            ).count == 4
        )
        for endpointDTO in [
            "GhostProfileMergePreparePayload",
            "GhostProfileMergePrepareResponse",
            "GhostProfileMergeCompletePayload",
            "GhostProfileIdentityRefreshPayload",
            "GhostProfileMergeErrorPayload"
        ] {
            #expect(liveRemoteService.contains("private struct \(endpointDTO)"))
            #expect(!manager.contains(endpointDTO))
        }
        #expect(!manager.contains("\"merge-ghost-profile\""))
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
            #expect(
                !remoteService.contains(forbiddenToken),
                "Ghost merge service boundary acquired \(forbiddenToken)"
            )
        }
        #expect(lineCount(models) <= 600)
        #expect(lineCount(store) <= 600)
        #expect(lineCount(remoteService) <= 600)
        #expect(lineCount(liveRemoteService) <= 600)
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
        for testName in [
            "testTypedOperationsForwardExactProviderAndHandoffValues",
            "testProviderBoundMergeFallbackOnlyAcceptsIdentityConflict",
            "testPendingMergeProofIsDiscardedOnlyForTerminalServerCodes"
        ] {
            #expect(remoteServiceTests.contains("func \(testName)("))
        }
    }

    @Test func purchaseIdentityJournalsRetainOneSecureStorageOwner() throws {
        let manager = try networkSource("SupabaseManager.swift")
        let authJournal = try networkSource(
            "Auth/Services/PurchaseIdentityHandoffAuthJournal.swift"
        )
        let preparationCoordinator = try source(
            "apps/ios/Merian/Core/Security/PurchaseIdentity/Coordinators/PurchaseIdentityHandoffPreparationCoordinator.swift"
        )
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
        #expect(
            authJournal.contains(
                "struct PurchaseIdentityHandoffAuthJournal"
            )
        )
        #expect(authJournal.contains("throw SupabaseAuthTransitionError"))
        #expect(!authJournal.contains("KeychainKeys."))
        #expect(!preparationCoordinator.contains("KeychainKeys."))
        #expect(
            preparationCoordinator.contains("persistStableRotation(draft)")
        )
        #expect(
            preparationCoordinator.contains(
                "persistStableRotation(prepared)"
            )
        )
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
        let recoveryCoordinator = try networkSource(
            "Auth/Coordinators/AuthSessionRecoveryCoordinator.swift"
        )
        let purchaseIdentitySessionCoordinator = try source(
            "apps/ios/Merian/Core/Security/PurchaseIdentity/Coordinators/PurchaseIdentitySessionCoordinator.swift"
        )
        let purchaseIdentitySessionLiveService = try source(
            "apps/ios/Merian/Core/Security/PurchaseIdentity/Services/PurchaseIdentitySessionLiveService.swift"
        )
        let purchaseIdentitySessionLiveAdapter = try source(
            "apps/ios/Merian/Core/Security/PurchaseIdentity/Services/PurchaseIdentitySessionLiveService+Live.swift"
        )
        let sourceHandoffCoordinator = try networkSource(
            "Auth/Coordinators/PurchaseIdentitySourceHandoffCoordinator.swift"
        )
        let purchaseIdentityReadiness = try sourceSection(
            beginningWith: "    private func ensurePurchaseIdentityReady(",
            endingBefore: "\n    /// Repairs a fail-closed purchase-identity",
            in: manager
        )
        let purchaseIdentityDependencies = try sourceSection(
            beginningWith:
                "    private func purchaseIdentitySessionDependencies()",
            endingBefore: "\n    // MARK: - Auth Session Bootstrap",
            in: manager
        )
        let ordinaryRefresh = try sourceSection(
            beginningWith: "    private func refreshActiveSession(",
            endingBefore: "\n}",
            in: recoveryCoordinator
        )
        let anonymousReset = try sourceSection(
            beginningWith: "    func resetGhostSessionForRetry() async -> Bool {",
            endingBefore: "\n    /// Begins and owns terminal local cleanup",
            in: recoveryCoordinator
        )
        let stableSignOutAbandonment = try sourceSection(
            beginningWith:
                "    func abandonStableRotationIfSourceRestored(",
            endingBefore:
                "\n    func abandonLegacyHandoffIfSourceRestored(",
            in: sourceHandoffCoordinator
        )
        let legacySignOutAbandonment = try sourceSection(
            beginningWith:
                "    func abandonLegacyHandoffIfSourceRestored(",
            endingBefore:
                "\n    func restoreSourceIdentityAfterFailedSignOut(",
            in: sourceHandoffCoordinator
        )
        let failedSignOutRestoration = try sourceSection(
            beginningWith:
                "    func restoreSourceIdentityAfterFailedSignOut(",
            endingBefore:
                "\n    private func loadPendingState()",
            in: sourceHandoffCoordinator
        )

        #expect(
            !purchaseIdentityReadiness.contains(
                "ownsAuthTransition(transition)"
            )
        )
        #expect(
            purchaseIdentityReadiness.components(
                separatedBy: "currentSessionMatchesAuthTransition(transition)"
            ).count == 2
        )
        #expect(
            purchaseIdentityReadiness.contains(
                "purchaseIdentitySessionCoordinator.ensureIdentity("
            )
        )
        #expect(
            purchaseIdentityReadiness.contains("isAdmissionCurrent:")
        )
        #expect(
            purchaseIdentityDependencies.contains(
                "purchaseIdentitySessionLiveService.dependencies("
            )
        )
        for relocatedLiveToken in [
            "PurchaseIdentitySessionProviderBoundary(",
            "PurchaseIdentityEntitlementBoundary(",
            "RevenueCatManager.shared",
            "EntitlementManager.shared",
            "Purchase identity resolution failed"
        ] {
            #expect(!purchaseIdentityDependencies.contains(relocatedLiveToken))
            #expect(
                purchaseIdentitySessionLiveAdapter.contains(
                    relocatedLiveToken
                ) || purchaseIdentitySessionLiveService.contains(
                    relocatedLiveToken
                )
            )
        }
        #expect(
            !manager.contains(
                "private func linkLegacyPurchaseProviderIdentity("
            )
        )
        try expectOrder(
            [
                "guard await resolveAndLink(",
                "guard isAdmissionCurrent() else { return false }",
                "lastLinkedUserID = context.userID"
            ],
            in: purchaseIdentitySessionCoordinator
        )
        try expectOrder(
            [
                "let expected = dependencies.transition.expectedSession(",
                "await dependencies.transition.awaitAccountWorkQuiescence()",
                "let session = try await dependencies.operations.refreshSDKSession()",
                "session.identity == expected",
                "session.adopt(transition)",
                "dependencies.transition.currentSessionMatches("
            ],
            in: ordinaryRefresh
        )
        try expectOrder(
            [
                "guard !Task.isCancelled",
                "dependencies.transition.beginRecovery()",
                "dependencies.state.hasPendingPurchaseIdentityHandoff()",
                "dependencies.operations.resetAnonymousSession(transition)",
                "let session = try await dependencies.operations.loadSDKSession()",
                "try Task.checkCancellation()",
                "await session.ensurePurchaseIdentityReady(transition)",
                "try Task.checkCancellation()",
                "session.purchaseIdentityIsReady()",
                "await session.beginEntitlementSession(transition)",
                "try Task.checkCancellation()",
                "let verifiedSession = try await dependencies.operations",
                "try Task.checkCancellation()"
            ],
            in: anonymousReset
        )
        try expectOrder(
            [
                "guard !Task.isCancelled",
                "beginSourceOperation(",
                "try? await dependencies.session.loadSDKSession()",
                "!Task.isCancelled",
                ".cancelStableRotation(rotation)",
                "sourceOperationIsCurrent(operation)",
                "!Task.isCancelled",
                "loadSDKSession()",
                "try dependencies.journal.clearStableRotation()"
            ],
            in: stableSignOutAbandonment
        )
        try expectOrder(
            [
                "guard !Task.isCancelled",
                "dependencies.session.ownsTransition(transition)",
                "dependencies.session.loadSDKSession()",
                "purchaseContinuityPending = try hasPendingHandoff()",
                "shouldRestoreSourceIdentityAfterFailedSignOut(",
                "guard !Task.isCancelled",
                "dependencies.session.adoptSourceSession(",
                "currentSessionMatchesTransition(",
                "setHandoffPending(false)",
                "publishRestoredSource(sourceUserID)",
                "ensurePurchaseIdentityReady(",
                "guard !Task.isCancelled",
                "restoredSourceIsCurrent(",
                "beginEntitlementSession("
            ],
            in: failedSignOutRestoration
        )
        try expectOrder(
            [
                "guard !Task.isCancelled",
                "beginSourceOperation(",
                "try? await dependencies.session.loadSDKSession()",
                "!Task.isCancelled",
                "cancelLegacyHandoff(pending)",
                "sourceOperationIsCurrent(operation)",
                "!Task.isCancelled",
                "try dependencies.journal.clearLegacyHandoff()"
            ],
            in: legacySignOutAbandonment
        )
    }

    @Test func liveAuthTaskCompletionsCannotPublishAcrossGenerations() throws {
        let manager = try networkSource("SupabaseManager.swift")
        let lifecycleCoordinator = try networkSource(
            "Auth/Coordinators/AuthSessionLifecycleCoordinator.swift"
        )
        let handoffCoordinator = try networkSource(
            "Auth/Coordinators/PurchaseIdentityHandoffCoordinator.swift"
        )
        let bootstrapCoordinator = try networkSource(
            "Auth/Coordinators/AuthSessionBootstrapCoordinator.swift"
        )
        let publicAuthorCoordinator = try networkSource(
            "Auth/Coordinators/PublicAuthorIdentityRefreshCoordinator.swift"
        )
        let appleRevocationCoordinator = try networkSource(
            "Auth/Coordinators/AppleCredentialRevocationCoordinator.swift"
        )
        let oauthProviderCoordinator = try networkSource(
            "Auth/Coordinators/OAuthProviderSignInCoordinator.swift"
        )
        let googleAuthorizationProvider = try networkSource(
            "Auth/Services/GoogleOAuthAuthorizationLiveProvider.swift"
        )
        let lifecycleLiveProvider = try networkSource(
            "Auth/Services/AuthSessionLifecycleLiveProvider.swift"
        )
        let lifecycleAssembly = try sourceSection(
            beginningWith:
                "    private func authSessionLifecycleDependencies(",
            endingBefore: "\n    private func beginAccountSession(",
            in: manager
        )
        let stableRotation = try sourceSection(
            beginningWith:
                "    private func completeStableRotation(",
            endingBefore:
                "\n    private func completeLegacyHandoff(",
            in: handoffCoordinator
        )
        let compatibilityHandoff = try sourceSection(
            beginningWith:
                "    private func completeLegacyHandoff(",
            endingBefore:
                "\n    private func verifyActiveAnonymousSession(",
            in: handoffCoordinator
        )
        let anonymousSessionFence = try sourceSection(
            beginningWith:
                "    private func activeAnonymousSessionMatches(",
            endingBefore:
                "\n    private func persistOAuthProfileMetadata(",
            in: manager
        )
        let handoffSessionVerifier = try sourceSection(
            beginningWith:
                "    private func verifyActiveAnonymousSession(",
            endingBefore: "\n}",
            in: handoffCoordinator
        )
        let publicAuthorSchedule = try sourceSection(
            beginningWith:
                "    func scheduleIfNeeded(",
            endingBefore:
                "\n    @discardableResult\n    func refresh(",
            in: publicAuthorCoordinator
        )
        let publicAuthorOperation = try sourceSection(
            beginningWith:
                "    private func performScheduledRefresh(",
            endingBefore:
                "\n    private func clearTaskIfCurrent(",
            in: publicAuthorCoordinator
        )
        let googleSignIn = try sourceSection(
            beginningWith: "    func signInWithGoogle(",
            endingBefore: "\n    func startAppleSignIn(",
            in: oauthProviderCoordinator
        )
        #expect(
            lifecycleCoordinator.components(
                separatedBy: "isCurrentPublishedSession("
            ).count == 3
        )
        #expect(
            lifecycleAssembly.components(
                separatedBy: "hasCurrentPublishedSession("
            ).count >= 3
        )
        #expect(
            lifecycleLiveProvider.components(
                separatedBy: "snapshotIsCurrent("
            ).count == 4
        )
        #expect(
            bootstrapCoordinator.components(
                separatedBy: "isCurrentPublishedSession("
            ).count == 3
        )
        #expect(
            bootstrapCoordinator.components(
                separatedBy: "dependencies.transition.allows(transition)"
            ).count >= 4
        )
        #expect(
            bootstrapCoordinator.components(
                separatedBy: "!Task.isCancelled"
            ).count >= 5
        )
        #expect(
            stableRotation.components(
                separatedBy: "activeAnonymousSessionMatches("
            ).count >= 3
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
            ).count >= 5
        )
        #expect(
            handoffCoordinator.components(
                separatedBy: "guard !Task.isCancelled"
            ).count >= 9
        )
        try expectOrder(
            [
                "try dependencies.journal.clearStableRotation()",
                "dependencies.journal.setHandoffPending(legacyPending)",
                "dependencies.operations.recordLinkedUser(",
                "await dependencies.operations.refreshCustomerInfo()"
            ],
            in: stableRotation
        )
        #expect(
            handoffSessionVerifier.contains("try Task.checkCancellation()")
        )
        #expect(
            handoffSessionVerifier.contains(
                "activeAnonymousSessionMatches("
            )
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
                "session.userID != lastCompletedUserID",
                "session.userID != activeUserID",
                "cancel()",
                "let taskID = UUID()",
                "taskID: taskID",
                "self.taskID = taskID",
                "activeUserID = session.userID"
            ],
            in: publicAuthorSchedule
        )
        #expect(
            publicAuthorSchedule.contains(
                "currentPublishedUserID()\n                == session.userID"
            )
        )
        #expect(
            publicAuthorCoordinator.components(
                separatedBy: "!Task.isCancelled"
            ).count == 9
        )
        try expectOrder(
            [
                "guard !Task.isCancelled",
                ".beginUnownedAccountWork(expectedUserID)",
                "completePendingGhostMerges(",
                "accountWorkIsCurrent(accountWorkLease)",
                "guard await refresh(",
                "currentPublishedUserID() == expectedUserID",
                "lastCompletedUserID = expectedUserID",
                "publishIdentityChanged("
            ],
            in: publicAuthorOperation
        )
        #expect(
            publicAuthorCoordinator.contains(
                "guard taskID == completedTaskID else { return }"
            )
        )
        #expect(
            appleRevocationCoordinator.contains(
                "contextGeneration == attempt.contextGeneration"
            )
        )
        #expect(
            appleRevocationCoordinator.contains(
                "guard self.taskID == taskID else { return }"
            )
        )
        #expect(
            appleRevocationCoordinator.contains(
                "guard taskID == completedTaskID else { return }"
            )
        )
        try expectOrder(
            [
                "try Task.checkCancellation()",
                "dependencies.signIn(viewController)",
                "try Task.checkCancellation()"
            ],
            in: googleAuthorizationProvider
        )
        try expectOrder(
            [
                ".authorizeWithGoogle()",
                ".verifyExpectedSessionIfPresent(transition)",
                "dependencies.completion.complete("
            ],
            in: googleSignIn
        )
    }

    @Test func authReplacementClosesPaidStateBeforePublishingNewSession() throws {
        let manager = try networkSource("SupabaseManager.swift")
        let coordinator = try networkSource(
            "Auth/Coordinators/AuthSessionLifecycleCoordinator.swift"
        )
        let lifecycleAssembly = try sourceSection(
            beginningWith:
                "    private func authSessionLifecycleDependencies(",
            endingBefore: "\n    private func beginAccountSession(",
            in: manager
        )
        let authenticatedAdoption = try sourceSection(
            beginningWith:
                "    private func handleAuthenticatedSession(",
            endingBefore: "\n}",
            in: coordinator
        )
        let livePublication = try sourceSection(
            beginningWith: "                publishSDKSession:",
            endingBefore: "\n                clearPublishedSession:",
            in: lifecycleAssembly
        )

        #expect(
            authenticatedAdoption.contains(
                "dependencies.state.publishedSession() != session"
            )
        )
        try expectOrder(
            [
                "clearPurchasePrincipalBinding()",
                "clearLinkedUser()",
                "beginPurchaseIdentityResolution()",
                "clearEntitlementSession()",
                "publishSDKSession(session)"
            ],
            in: authenticatedAdoption
        )
        try expectOrder(
            [
                "transitionSession(from: sdkUser) == session",
                "currentUser = sdkUser",
                "isAuthenticated = true"
            ],
            in: livePublication
        )
        #expect(
            lifecycleAssembly.contains(
                "clearPurchasePrincipalBinding: { [weak self] in\n                    self?.purchaseIdentitySessionCoordinator.clearBinding()"
            )
        )
        #expect(
            lifecycleAssembly.contains(
                "clearLinkedUser: { [weak self] in\n                    self?.purchaseIdentitySessionCoordinator.clearLinkedUser()"
            )
        )
        #expect(
            lifecycleAssembly.contains(
                "beginPurchaseIdentityResolution()"
            )
        )
        #expect(
            lifecycleAssembly.contains(
                "EntitlementManager.shared.handleSignOut()"
            )
        )
    }

    @Test func scanAdmissionUsesTheFixedPinnedNoRetryBridge() throws {
        let admission = try source(
            "apps/ios/Merian/Core/Security/ScanAdmissionManager.swift"
        )
        let client = try networkSource("MerianNetworkClient.swift")
        let pinnedTransport = try networkSource(
            "Transport/PinnedNetworkTransport.swift"
        )

        #expect(!admission.contains("URLSession("))
        #expect(!admission.contains("previewSessionConfiguration"))
        #expect(
            admission.contains("performPinnedScanAdmissionPreviewRequest(")
        )
        #expect(admission.contains("retryEnabled: false"))
        #expect(
            client.contains(
                ".appendingPathComponent(\"get_my_scan_admission_preview\")"
            )
        )
        #expect(
            client.contains(
                "request.value(forHTTPHeaderField: \"Authorization\")"
            )
        )
        #expect(client.contains("request.httpMethod == \"POST\""))
        #expect(!pinnedTransport.contains("withThrowingTaskGroup("))
        #expect(
            pinnedTransport.contains(
                "private final class PinnedNetworkDataTaskState: Sendable"
            )
        )
        #expect(pinnedTransport.contains("OSAllocatedUnfairLock(initialState:"))
        #expect(pinnedTransport.contains("withTaskCancellationHandler"))
        #expect(pinnedTransport.contains("withCheckedThrowingContinuation"))
        #expect(pinnedTransport.contains("deadlineQueue.asyncAfter"))
        #expect(
            pinnedTransport.contains(
                "boundedRequest.cachePolicy = .reloadIgnoringLocalCacheData"
            )
        )
    }

    @Test func directIdentityLinkRetiresRecoveryOnlyAfterExactUpgradeAdoption() throws {
        let coordinator = try networkSource(
            "Auth/Coordinators/OAuthSignInCoordinator.swift"
        )
        let directIdentityLink = try sourceSection(
            beginningWith:
                "            do {\n                try Task.checkCancellation()\n                try await dependencies.session.linkIdentity(credentials)",
            endingBefore: "\n            } catch {",
            in: coordinator
        )

        #expect(
            directIdentityLink.components(
                separatedBy: "clearGhostMerges("
            ).count == 2
        )

        try expectOrder(
            [
                "linkIdentity(credentials)",
                "readSDKSession()",
                "acceptsLinkedIdentityUpgrade(",
                "adoptSession(",
                "linkedSession,",
                "currentSessionMatchesTransition(",
                "clearGhostMerges("
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
                "Auth/Services/AuthHistoricalSessionSyncLiveService+Live.swift",
                "Endpoints/MerianNetworkClient+Inference.swift",
                "Recovery/MerianNetworkClient+OwnedScanRecovery.swift",
                "SupabasePublicAuthorIdentityRefreshLiveEffects.swift",
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
                "Recovery/MerianNetworkClient+OwnedScanRecovery.swift"
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
        #expect(executor.contains(
            "request.allowsUnauthorizedSessionRecovery"
        ))
        #expect(client.contains(
            "allowsUnauthorizedSessionRecovery: Bool = true"
        ))
        let unauthorizedRecoveryOptOutOwners = Set(
            try networkSources().compactMap { path, source in
                source.contains("allowsUnauthorizedSessionRecovery: false")
                    ? path
                    : nil
            }
        )
        #expect(unauthorizedRecoveryOptOutOwners == [
            "Endpoints/MerianNetworkClient+Collections.swift",
            "Endpoints/MerianNetworkClient+ScanLifecycle.swift"
        ])
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
            "unauthorizedRecoveryCanBeDeferredToDurableRetryOwner",
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
            "injectedSessionOwnsTestDispatch",
            "boundedDispatchUsesThePinnedSessionWithoutCaching",
            "boundedDispatchCancelsANonCompletingRequestAtItsDeadline"
        ] {
            #expect(pinnedTransportTests.contains("func \(name)("))
            #expect(!aggregateTests.contains("func \(name)("))
        }
        #expect(pinnedTransportTests.contains("systemTrustIsValid: false"))
    }

    private static let endpointOwnerFilenames: Set<String> = [
        "MerianNetworkClient+AccountDeletion.swift",
        "MerianNetworkClient+CommunityIdentification.swift",
        "MerianNetworkClient+Collections.swift",
        "MerianNetworkClient+ExploreBrowsing.swift",
        "MerianNetworkClient+ExploreInteractions.swift",
        "MerianNetworkClient+ExplorePostManagement.swift",
        "MerianNetworkClient+ExploreReactions.swift",
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
        "MerianNetworkClient+SpeciesDiscoverySearch.swift",
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
        "Coordinators/AccountDeletionCoordinationDependencies.swift",
        "Coordinators/AccountDeletionCoordinator.swift",
        "Coordinators/AccountDeletionRecoveryCoordinator.swift",
        "Coordinators/AccountDeletionWorkflow.swift",
        "Coordinators/AppleCredentialRevocationCoordinationDependencies.swift",
        "Coordinators/AppleCredentialRevocationCoordinator.swift",
        "Coordinators/AuthenticationCallbackCoordinationDependencies.swift",
        "Coordinators/AuthenticationCallbackCoordinator.swift",
        "Coordinators/AuthLocalSignOutCoordinator.swift",
        "Coordinators/AuthSessionBootstrapCoordinationDependencies.swift",
        "Coordinators/AuthSessionBootstrapCoordinator.swift",
        "Coordinators/AuthSessionLifecycleCoordinationDependencies.swift",
        "Coordinators/AuthSessionLifecycleCoordinator.swift",
        "Coordinators/AuthLifecycleReplayCoordinator.swift",
        "Coordinators/AuthSessionRecoveryCoordinationDependencies.swift",
        "Coordinators/AuthSessionRecoveryCoordinator.swift",
        "Coordinators/AuthRuntimeState.swift",
        "Coordinators/AuthTransitionCoordinators.swift",
        "Coordinators/GhostProfileMergeCoordinationDependencies.swift",
        "Coordinators/GhostProfileMergeCoordinator.swift",
        "Coordinators/GhostProfileMergeWorkflow.swift",
        "Coordinators/OAuthProviderSignInCoordinationDependencies.swift",
        "Coordinators/OAuthProviderSignInCoordinator.swift",
        "Coordinators/OAuthSignInCoordinationDependencies.swift",
        "Coordinators/OAuthSignInCoordinator.swift",
        "Coordinators/OAuthSignInWorkflow.swift",
        "Coordinators/PurchaseIdentityHandoffCoordinationDependencies.swift",
        "Coordinators/PurchaseIdentityHandoffCoordinator.swift",
        "Coordinators/PurchaseIdentitySignOutCoordinationDependencies.swift",
        "Coordinators/PurchaseIdentitySignOutCoordinator.swift",
        "Coordinators/PurchaseIdentitySignOutWorkflow.swift",
        "Coordinators/PurchaseIdentitySourceHandoffCoordinationDependencies.swift",
        "Coordinators/PurchaseIdentitySourceHandoffCoordinator.swift",
        "Coordinators/PublicAuthorIdentityRefreshCoordinationDependencies.swift",
        "Coordinators/PublicAuthorIdentityRefreshCoordinator.swift",
        "Models/AuthSessionLifecycleModels.swift",
        "Models/OAuthSignInModels.swift",
        "Models/SupabaseAuthTransitionModels.swift",
        "Policies/AccountDeletionTransitionPolicy.swift",
        "Policies/AccountPresentationPolicy.swift",
        "Policies/AuthTransitionPolicy.swift",
        "Policies/GhostProfileMergePolicy.swift",
        "Policies/OAuthIdentityTokenPolicy.swift",
        "Services/AppleOAuthAuthorizationLiveProvider.swift",
        "Services/AppleOAuthCredentialRegistrationService+Live.swift",
        "Services/AppleOAuthCredentialRegistrationService.swift",
        "Services/AuthHistoricalSessionSyncLiveService+Live.swift",
        "Services/AuthHistoricalSessionSyncLiveService.swift",
        "Services/AuthSessionLifecycleLiveDiagnostics.swift",
        "Services/AuthSessionLifecycleLiveProvider+Live.swift",
        "Services/AuthSessionLifecycleLiveProvider.swift",
        "Services/AuthSessionBootstrapLiveDiagnostics.swift",
        "Services/AuthSessionBootstrapLiveService+Live.swift",
        "Services/AuthSessionBootstrapLiveService.swift",
        "Services/AuthenticationCallbackLiveDiagnostics.swift",
        "Services/GoogleOAuthAuthorizationLiveProvider.swift",
        "Services/OAuthPresentationContextResolver.swift",
        "Services/OAuthProviderSignInLiveDiagnostics.swift",
        "Services/PurchaseIdentityHandoffAuthJournal.swift",
        "Services/SupabaseAuthSessionService+Live.swift",
        "Services/SupabaseAuthSessionService.swift"
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
        "get-explore-post-reactors",
        "get-explore-reactions",
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
                + #"([A-Za-z0-9_]+)(?:<[^>\n]+>)?\("#
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

    private func totalLineCount(in files: [URL]) throws -> Int {
        try files.reduce(into: 0) { total, file in
            let source = try String(contentsOf: file, encoding: .utf8)
            total += lineCount(source)
        }
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
