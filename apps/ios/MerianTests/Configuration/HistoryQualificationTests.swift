import Foundation
@testable import Merian
import os
import Supabase
import Testing

@Suite("History qualification boundaries")
struct HistoryQualificationTests {
    private let account = UUID(uuidString: "00000000-0000-4000-8000-000000000250")!

    private var info: [String: Any] {
        [
            "MERIAN_HISTORY_QUALIFICATION": "1",
            "MERIAN_HISTORY_APPROVAL_ID": "00000000-0000-4000-8000-000000000251",
            "MERIAN_HISTORY_APPROVED_PROJECT": "abcdefghijklmnopqrst",
            "MERIAN_HISTORY_APPROVED_HOST": "abcdefghijklmnopqrst.supabase.co",
            "SUPABASE_URL": "https://abcdefghijklmnopqrst.supabase.co",
            "MERIAN_APP_GROUP_IDENTIFIER": "group.app.merian.shared",
            "MERIAN_KEYCHAIN_NAMESPACE": "app.merian.shared",
            "MERIAN_AUTH_NAMESPACE": "Merian.HistoryQualification.Auth",
            "MERIAN_HISTORY_OPERATION_SCOPE": "capture-history-v1",
            "MERIAN_HISTORY_ACCOUNT_FINGERPRINTS": MerianEnvironment.HistoryQualificationScope.fingerprint(account)
        ]
    }

    private func scope(_ values: [String: Any]? = nil, compiled: Bool = true,
                       bundle: String = "app.merian.Merian") throws -> MerianEnvironment.HistoryQualificationScope {
        try MerianEnvironment.validateHistoryQualification(info: values ?? info, bundleID: bundle, compiledMarker: compiled)
    }

    @Test func exactSyntheticScopeAdmitsOnlyApprovedAccount() throws {
        let result = try scope()
        #expect(result.permits(accountID: account))
        #expect(!result.permits(accountID: UUID()))
        #expect(result.host == "abcdefghijklmnopqrst.supabase.co")
    }

    @Test @MainActor func emptyQualifiedSDKSessionReachesLibraryRecoveryWithoutNetworkOrLegacySession() async throws {
        let backing = QualificationMemoryStorage()
        let legacy = try sessionData(account: account)
        try backing.store(key: "supabase.auth.token", value: legacy)
        let storage = QualificationAuthStorage(storage: backing, scope: try scope())
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QualificationStartupNoNetworkProtocol.self]
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel() }
        QualificationStartupNoNetworkProtocol.requests.withLock { $0 = 0 }
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://qualification-startup.invalid")!,
            supabaseKey: "synthetic-key",
            options: .init(auth: .init(storage: storage,
                storageKey: QualificationAuthStorage.sessionKey,
                autoRefreshToken: false, emitLocalSessionAsInitialSession: true),
                global: .init(session: transport))
        )
        let runtime = AuthRuntimeState()
        let lifecycle = AuthSessionLifecycleCoordinatorHarness(userID: account)
        lifecycle.isTestExecution = true
        lifecycle.currentAuthGeneration = 0
        lifecycle.publishedSession = nil
        let provider = AuthSessionLifecycleLiveProvider.live(client: client)
        defer { provider.cancel() }
        provider.start(dependencies: .init(
            advanceAuthGeneration: {
                lifecycle.currentAuthGeneration = runtime.advanceSessionGeneration()
                return lifecycle.currentAuthGeneration
            },
            authContextWillChange: {}, observeAuthSession: { runtime.observeAuthEvent(session: $0) },
            accountDeletionCleanupPending: { false }, hasActiveTransition: { false },
            reconciliationContextIsCurrent: { $0 == runtime.sessionGeneration },
            makeLifecycleDependencies: { _ in lifecycle.dependencies() },
            resumeDeferredCredentialRevocation: {}
        ))
        let joined = try await provider.waitForInitialSignedOutForTesting(timeout: .seconds(5))
        #expect(joined, "The actual pinned SDK must deliver initial signed-out state to the live listener")
        #expect(runtime.sessionGeneration == 1)
        #expect(LibraryAccountRecoveryPresentation.resolve(recoveryRequired: true,
            authSessionGeneration: runtime.sessionGeneration,
            hasCachedSessionAwaitingRefresh: false, activeTransitionKind: nil) == .recoveryRequired)
        #expect(QualificationStartupNoNetworkProtocol.requests.withLock { $0 } == 0)
        #expect(try backing.retrieve(key: "supabase.auth.token") == legacy)
        #expect(try backing.retrieve(key: QualificationAuthStorage.sessionKey) == nil)
    }

    @Test @MainActor func ordinaryBuildCannotBeEnabledByBundledValues() {
        #expect(throws: MerianEnvironment.HistoryQualificationFailure.compiledMarker) { try scope(compiled: false) }
        #expect(throws: MerianEnvironment.HistoryQualificationFailure.namespace) { try scope(bundle: "app.merian.historyqualification") }
        #expect(!MerianEnvironment.isHistoryQualificationBuild)
        #expect(!PreparedHistoryReanalysisComposition.isAppInstallationQualified)
    }

    @Test func everyRequiredFieldIsMandatory() {
        for key in info.keys {
            var values = info
            values.removeValue(forKey: key)
            #expect(throws: (any Error).self) { try scope(values) }
        }
    }

    @Test(arguments: ["http://abcdefghijklmnopqrst.supabase.co", "https://different.supabase.co",
                      "https://abcdefghijklmnopqrst.supabase.co:443", "https://abcdefghijklmnopqrst.supabase.co/path",
                      "https://abcdefghijklmnopqrst.supabase.co?x=1", "https://abcdefghijklmnopqrst.supabase.co#x",
                      "https://user:password@abcdefghijklmnopqrst.supabase.co"])
    func refusesTargetVariations(url: String) {
        var values = info
        values["SUPABASE_URL"] = url
        #expect(throws: MerianEnvironment.HistoryQualificationFailure.target) { try scope(values) }
    }

    @Test(arguments: ["", " ", "not-a-fingerprint", String(repeating: "A", count: 64), ","])
    func refusesMalformedAccountScope(value: String) {
        var values = info
        values["MERIAN_HISTORY_ACCOUNT_FINGERPRINTS"] = value
        #expect(throws: MerianEnvironment.HistoryQualificationFailure.accounts) { try scope(values) }
    }

    @Test func refusesDuplicateAccountsAndOtherOperationOrNamespaces() {
        for (key, value) in [
            ("MERIAN_HISTORY_ACCOUNT_FINGERPRINTS", Array(repeating: MerianEnvironment.HistoryQualificationScope.fingerprint(account), count: 2).joined(separator: ",")),
            ("MERIAN_HISTORY_OPERATION_SCOPE", "delete-account"),
            ("MERIAN_APP_GROUP_IDENTIFIER", "group.app.merian.historyqualification"),
            ("MERIAN_KEYCHAIN_NAMESPACE", "app.merian.historyqualification"),
            ("MERIAN_AUTH_NAMESPACE", "supabase.gotrue.swift"),
            ("MERIAN_HISTORY_QUALIFICATION", "0"),
            ("MERIAN_HISTORY_APPROVAL_ID", "00000000-0000-0000-0000-000000000000"),
            ("MERIAN_HISTORY_APPROVED_PROJECT", "otherabcdefghijklmn")
        ] {
            var values = info
            values[key] = value
            #expect(throws: (any Error).self) { try scope(values) }
        }
    }

    @Test func storageRejectsUnapprovedAnonymousAndMalformedSessionsWithoutErasing() throws {
        let backing = QualificationMemoryStorage()
        let storage = QualificationAuthStorage(storage: backing, scope: try scope())
        for data in [try sessionData(account: UUID()), try sessionData(account: account, anonymous: true), Data("invalid".utf8)] {
            try backing.store(key: QualificationAuthStorage.sessionKey, value: data)
            #expect(throws: MerianEnvironment.HistoryQualificationFailure.accounts) { try storage.retrieve(key: QualificationAuthStorage.sessionKey) }
            #expect(throws: MerianEnvironment.HistoryQualificationFailure.accounts) { try storage.remove(key: QualificationAuthStorage.sessionKey) }
            #expect(throws: MerianEnvironment.HistoryQualificationFailure.accounts) { try storage.store(key: QualificationAuthStorage.sessionKey, value: data) }
            #expect(try backing.retrieve(key: QualificationAuthStorage.sessionKey) == data)
        }
    }

    @Test func approvedSessionRoundTripsAndLegacyKeysRemainUntouched() throws {
        let backing = QualificationMemoryStorage()
        let storage = QualificationAuthStorage(storage: backing, scope: try scope())
        let data = try sessionData(account: account)
        try backing.store(key: QualificationAuthStorage.sessionKey, value: data)
        try storage.store(key: QualificationAuthStorage.sessionKey, value: data)
        #expect(try storage.retrieve(key: QualificationAuthStorage.sessionKey) == data)
        try storage.remove(key: QualificationAuthStorage.sessionKey)
        #expect(try backing.retrieve(key: QualificationAuthStorage.sessionKey) == nil)
        for key in ["supabase.session", "supabase.auth.token", "history-qualification-session-code-verifier"] {
            try backing.store(key: key, value: data)
            #expect(try storage.retrieve(key: key) == nil)
            try storage.remove(key: key)
            #expect(try backing.retrieve(key: key) == data)
            #expect(throws: QualificationAuthStorage.SettlementFailure.notAccepted) { try storage.store(key: key, value: data) }
        }
    }

    @Test func qualificationTransactionNeverRewritesPrimarySDKSession() throws {
        let backing = QualificationFaultStorage()
        let primaryKey = "sb-abcdefghijklmnopqrst-auth-token"
        let original = try sessionData(account: account)
        try backing.store(key: primaryKey, value: original)
        let storage = QualificationAuthStorage(storage: backing, scope: try scope())
        #expect(try storage.retrieve(key: QualificationAuthStorage.sessionKey) == nil)
        #expect(try storage.retrieve(key: primaryKey) == nil)
        let attempt = UUID()
        try storage.begin(attempt)
        #expect(throws: (any Error).self) { try storage.store(key: QualificationAuthStorage.sessionKey, value: original) }
        #expect(try backing.retrieve(key: primaryKey) == original)
        try storage.abandon(attempt)
        let acceptedAttempt = UUID()
        try storage.begin(acceptedAttempt)
        try storage.accept(JSONDecoder().decode(Session.self, from: original), attempt: acceptedAttempt,
                           evidence: identityEvidence(), at: Date(timeIntervalSince1970: 1800000100))
        let restarted = QualificationAuthStorage(storage: backing, scope: try scope())
        #expect(try restarted.retrieve(key: QualificationAuthStorage.sessionKey) != nil)
        try restarted.store(key: QualificationAuthStorage.sessionKey, value: original)
        try restarted.remove(key: QualificationAuthStorage.sessionKey)
        let retained = try #require(try backing.retrieve(key: primaryKey))
        #expect(retained == original)
        #expect(try JSONDecoder().decode(Session.self, from: retained).user.id == account)
    }

    @Test func qualificationGuardsPrecedeClientIdentityAndDeletionEffects() throws {
        struct Boundary {
            let path: String
            let guardText: String
            let effect: String
        }
        let pairs: [Boundary] = [
            Boundary(path: "App/MerianApp.swift", guardText: "MerianEnvironment.requireHistoryQualificationConfiguration()", effect: "let dependencies = AppDIContainer.shared"),
            Boundary(path: "Core/AppDIContainer.swift", guardText: "MerianEnvironment.requireHistoryQualificationConfiguration()", effect: "return AppDIContainer(bindGlobalManagers: true)"),
            Boundary(path: "Core/Network/MerianSupabaseClientFactory.swift", guardText: "MerianEnvironment.requireHistoryQualificationConfiguration()", effect: "return SupabaseClient("),
            Boundary(path: "Core/Network/Auth/Coordinators/AuthenticationCallbackCoordinator.swift", guardText: "!MerianEnvironment.isHistoryQualificationBuild", effect: "dependencies.transition.begin()"),
            Boundary(path: "Core/Network/Auth/Coordinators/AccountDeletionCoordinator.swift", guardText: "MerianEnvironment.requireQualificationDeletionPermission()", effect: "recoveryCapabilityStore.prepare()"),
            Boundary(path: "Core/Network/Auth/Coordinators/AccountDeletionRecoveryCoordinator.swift", guardText: "!MerianEnvironment.isHistoryQualificationBuild", effect: "dependencies.localState.state()")
        ]
        for pair in pairs {
            let source = try DatabaseActorTestSupport.loadRepositorySource(at: "apps/ios/Merian/" + pair.path)
            let boundary = try #require(source.range(of: pair.guardText))
            let operation = try #require(source.range(of: pair.effect))
            #expect(boundary.lowerBound < operation.lowerBound)
        }
        let provider = try DatabaseActorTestSupport.loadRepositorySource(at: "apps/ios/Merian/Core/Network/Auth/Coordinators/OAuthProviderSignInCoordinator.swift")
        #expect(provider.components(separatedBy: "guard !MerianEnvironment.isHistoryQualificationBuild,").count == 2)
        #expect(provider.contains("guard MerianEnvironment.permitsQualificationGooglePresentation,"))
        let live = try DatabaseActorTestSupport.loadRepositorySource(at: "apps/ios/Merian/Core/Network/Auth/Services/SupabaseAuthSessionService+Live.swift")
        #expect(live.components(separatedBy: "try MerianEnvironment.requireQualificationIdentityExchangePermission()").count == 3)
        let install = try #require(live.range(of: "installSession: { credentials in"))
        let installBody = String(live[install.upperBound...])
        let exchangeGuard = try #require(installBody.range(of: "requireQualificationGoogleExchange"))
        let exchangeCall = try #require(installBody.range(of: "signInWithIdToken"))
        #expect(exchangeGuard.lowerBound < exchangeCall.lowerBound)
        #expect(installBody.contains("preservingExactBytes: true"))
        let manager = try DatabaseActorTestSupport.loadRepositorySource(at: "apps/ios/Merian/Core/Network/SupabaseManager.swift")
        let start = try #require(manager.range(of: "private func installOAuthSessionReplacingCurrentAccount("))
        let body = String(manager[start.upperBound...])
        var last = body.startIndex
        for marker in ["try Task.checkCancellation()", "currentSessionMatchesAuthTransition(transition)", "beginQualificationExchange", "supabaseAuthSessionService.installSession(", "requireQualificationGoogleAccount", "adoptAuthTransitionSession", "barrier.accept", "didMutateSession()"] {
            let found = try #require(body.range(of: marker, range: last..<body.endIndex))
            last = found.upperBound
        }
    }

    @Test func ancillaryHostedServicesRefuseBeforeConfigurationOrIdentityMutation() throws {
        for (path, start, effect) in [
            ("Core/Analytics/PostHogManager.swift", "private func configure()", "var configurationContext:"),
            ("Core/Security/RevenueCatManager.swift", "private func linkIdentity(", "let normalizedAccountKind =")
        ] {
            let source = try DatabaseActorTestSupport.loadRepositorySource(at: "apps/ios/Merian/" + path)
            let method = try #require(source.range(of: start))
            let body = String(source[method.upperBound...])
            let boundary = try #require(body.range(of: "MerianEnvironment.allowsAncillaryHostedIntegrations"))
            let operation = try #require(body.range(of: effect))
            #expect(boundary.lowerBound < operation.lowerBound)
        }
    }

    @Test(arguments: [false, true])
    func pendingExchangeContainsRejectedAndLateSDKWrites(hasSource: Bool) throws {
        let backing = QualificationFaultStorage()
        let storage = QualificationAuthStorage(storage: backing, scope: try scope())
        let prior = hasSource ? try sessionData(account: account) : nil
        if let prior { try backing.store(key: QualificationAuthStorage.sessionKey, value: prior) }
        let attempt = UUID()
        try storage.begin(attempt)
        let candidate = try sessionData(account: account, token: "candidate")
        #expect(throws: (any Error).self) { try storage.store(key: QualificationAuthStorage.sessionKey, value: candidate) }
        #expect(throws: (any Error).self) { try storage.remove(key: QualificationAuthStorage.sessionKey) }
        // A fresh wrapper models restart/current-session reconciliation.
        #expect(try QualificationAuthStorage(storage: backing, scope: scope()).retrieve(key: QualificationAuthStorage.sessionKey) == prior)
        backing.failWrites(.before)
        #expect(throws: (any Error).self) { try storage.abandon(attempt) }
        #expect(try storage.retrieve(key: QualificationAuthStorage.sessionKey) == prior)
        backing.failWrites(nil)
        try storage.abandon(attempt)
        #expect(try storage.retrieve(key: QualificationAuthStorage.sessionKey) == prior)
    }

    @Test(arguments: [false, true])
    func cancellationDoesNotRetireBarrierBeforeSDKTaskExits(hasSource: Bool) async throws {
        let backing = QualificationFaultStorage()
        let storage = QualificationAuthStorage(storage: backing, scope: try scope())
        let prior = hasSource ? try sessionData(account: account) : nil
        if let prior { try backing.store(key: QualificationAuthStorage.sessionKey, value: prior) }
        let attempt = UUID()
        try storage.begin(attempt)
        let candidate = try sessionData(account: account, token: "late")
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in stream { break }
            // The SDK may finish storing after cancellation; storage must still refuse.
            #expect(throws: (any Error).self) { try storage.store(key: QualificationAuthStorage.sessionKey, value: candidate) }
        }
        task.cancel()
        continuation.yield(())
        await task.value
        try storage.abandon(attempt) // Only after the operation actually exits.
        #expect(try storage.retrieve(key: QualificationAuthStorage.sessionKey) == prior)
    }

    @Test(arguments: [false, true])
    func expiryAndRejectedAdoptionNeverPromoteSDKCandidate(hasSource: Bool) throws {
        let backing = QualificationFaultStorage()
        let storage = QualificationAuthStorage(storage: backing, scope: try scope())
        let prior = hasSource ? try sessionData(account: account) : nil
        if let prior { try backing.store(key: QualificationAuthStorage.sessionKey, value: prior) }
        let attempt = UUID()
        try storage.begin(attempt)
        let candidate = try JSONDecoder().decode(Session.self, from: sessionData(account: account, token: "rejected"))
        let evidence = try identityEvidence()
        #expect(throws: (any Error).self) { try storage.accept(candidate, attempt: attempt, evidence: evidence, at: evidence.refusalExpiresAt) }
        #expect(try storage.retrieve(key: QualificationAuthStorage.sessionKey) == prior)
        // Rejected adoption never calls accept; failed cleanup retains the pending barrier.
        backing.failWrites(.before)
        #expect(throws: (any Error).self) { try storage.abandon(attempt) }
        #expect(try QualificationAuthStorage(storage: backing, scope: scope()).retrieve(key: QualificationAuthStorage.sessionKey) == prior)
    }

    @Test(arguments: [false, true])
    func commitDistinguishesWriteBeforeAndAfterPersistence(written: Bool) throws {
        let backing = QualificationFaultStorage()
        let storage = QualificationAuthStorage(storage: backing, scope: try scope())
        let prior = try sessionData(account: account)
        try backing.store(key: QualificationAuthStorage.sessionKey, value: prior)
        let attempt = UUID()
        try storage.begin(attempt)
        let candidate = try JSONDecoder().decode(Session.self, from: sessionData(account: account, token: "accepted"))
        backing.failWrites(written ? .after : .before)
        if written {
            try storage.accept(candidate, attempt: attempt, evidence: identityEvidence(), at: Date(timeIntervalSince1970: 1800000100))
            let stored = try #require(try storage.retrieve(key: QualificationAuthStorage.sessionKey))
            #expect(try JSONDecoder().decode(Session.self, from: stored).accessToken == "accepted")
        } else {
            #expect(throws: QualificationAuthStorage.SettlementFailure.notAccepted) {
                try storage.accept(candidate, attempt: attempt, evidence: identityEvidence(), at: Date(timeIntervalSince1970: 1800000100))
            }
            #expect(try storage.retrieve(key: QualificationAuthStorage.sessionKey) == prior)
        }
    }

    @Test func unknownCommitUsesExactDurableReceiptOnSubsequentRead() throws {
        let backing = QualificationFaultStorage()
        let storage = QualificationAuthStorage(storage: backing, scope: try scope())
        let attempt = UUID()
        try storage.begin(attempt)
        let candidate = try JSONDecoder().decode(Session.self, from: sessionData(account: account, token: "accepted"))
        backing.failWrites(.after, unreadableAfterWrite: 2)
        #expect(throws: QualificationAuthStorage.SettlementFailure.unresolved) {
            try storage.accept(candidate, attempt: attempt, evidence: identityEvidence(), at: Date(timeIntervalSince1970: 1800000100))
        }
        backing.failWrites(nil)
        let restarted = QualificationAuthStorage(storage: backing, scope: try scope())
        let stored = try #require(try restarted.retrieve(key: QualificationAuthStorage.sessionKey))
        #expect(try JSONDecoder().decode(Session.self, from: stored).accessToken == "accepted")
        // Expired exchange evidence does not revoke an already accepted stored session.
        let refreshed = try sessionData(account: account, token: "refreshed")
        try restarted.store(key: QualificationAuthStorage.sessionKey, value: refreshed)
        #expect(try restarted.retrieve(key: QualificationAuthStorage.sessionKey) == refreshed)
        let envelope = try #require(try backing.retrieve(key: QualificationAuthStorage.sessionKey))
        var raw = try #require(try JSONSerialization.jsonObject(with: envelope) as? [String: Any])
        var receipt = try #require(raw["receipt"] as? [String: Any])
        receipt["digest"] = String(repeating: "0", count: 64)
        raw["receipt"] = receipt
        try backing.store(key: QualificationAuthStorage.sessionKey, value: JSONSerialization.data(withJSONObject: raw))
        #expect(throws: (any Error).self) { try restarted.retrieve(key: QualificationAuthStorage.sessionKey) }
    }

    @Test func staleAttemptCannotSettleOrAbandonSuccessor() throws {
        let backing = QualificationFaultStorage()
        let storage = QualificationAuthStorage(storage: backing, scope: try scope())
        let old = UUID(), next = UUID()
        try storage.begin(old)
        try storage.abandon(old)
        try storage.begin(next)
        try storage.abandon(old)
        let candidate = try JSONDecoder().decode(Session.self, from: sessionData(account: account))
        #expect(throws: (any Error).self) { try storage.accept(candidate, attempt: old, evidence: identityEvidence(), at: Date(timeIntervalSince1970: 1800000100)) }
        #expect(throws: (any Error).self) { try storage.remove(key: QualificationAuthStorage.sessionKey) }
        try storage.accept(candidate, attempt: next, evidence: identityEvidence(), at: Date(timeIntervalSince1970: 1800000100))
        try storage.abandon(old)
        #expect(try storage.retrieve(key: QualificationAuthStorage.sessionKey) != nil)
    }

    private func identityEvidence() throws -> MerianEnvironment.HistoryQualificationIdentityEvidence {
        let scope = try scope()
        return .init(approvalID: scope.approvalID, host: scope.host, provider: "google",
            accountFingerprint: MerianEnvironment.HistoryQualificationScope.fingerprint(account),
            subjectFingerprint: String(repeating: "b", count: 64), mappingEvidenceDigest: String(repeating: "c", count: 64),
            refusalEvidenceDigest: String(repeating: "d", count: 64), mappingObservedAt: Date(timeIntervalSince1970: 1800000000),
            mappingExpiresAt: Date(timeIntervalSince1970: 1800000300), refusalObservedAt: Date(timeIntervalSince1970: 1800000000),
            refusalExpiresAt: Date(timeIntervalSince1970: 1800000200))
    }

    private func sessionData(account: UUID, anonymous: Bool = false, token: String = "synthetic-access") throws -> Data {
        try JSONEncoder().encode(Session(accessToken: token, tokenType: "bearer", expiresIn: 3600,
            expiresAt: Date.distantFuture.timeIntervalSince1970, refreshToken: "synthetic-refresh",
            user: User(id: account, appMetadata: [:], userMetadata: [:], aud: "authenticated",
                       createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0), isAnonymous: anonymous)))
    }
}

private struct QualificationMemoryStorage: AuthLocalStorage {
    private let values = OSAllocatedUnfairLock(initialState: [String: Data]())
    func store(key: String, value: Data) throws { values.withLock { $0[key] = value } }
    func retrieve(key: String) throws -> Data? { values.withLock { $0[key] } }
    func remove(key: String) throws { values.withLock { _ = $0.removeValue(forKey: key) } }
}

private final class QualificationStartupNoNetworkProtocol: URLProtocol, @unchecked Sendable {
    static let requests = OSAllocatedUnfairLock(initialState: 0)
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.withLock { $0 += 1 }
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

struct QualificationFaultStorage: AuthLocalStorage {
    enum WriteFailure { case before, after }
    enum Failure: Error { case injected }
    private struct State {
        var values: [String: Data] = [:]
        var writeFailure: WriteFailure?
        var unreadableAfterWrite = 0
        var remainingUnreadable = 0
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    func failWrites(_ failure: WriteFailure?, unreadableAfterWrite: Int = 0) {
        state.withLock { $0.writeFailure = failure; $0.unreadableAfterWrite = unreadableAfterWrite }
    }
    func store(key: String, value: Data) throws {
        try state.withLock {
            if $0.writeFailure == .before { throw Failure.injected }
            $0.values[key] = value
            $0.remainingUnreadable = $0.unreadableAfterWrite
            if $0.writeFailure == .after { throw Failure.injected }
        }
    }
    func retrieve(key: String) throws -> Data? {
        try state.withLock {
            if $0.remainingUnreadable > 0 { $0.remainingUnreadable -= 1; throw Failure.injected }
            return $0.values[key]
        }
    }
    func remove(key: String) throws { state.withLock { _ = $0.values.removeValue(forKey: key) } }
}
