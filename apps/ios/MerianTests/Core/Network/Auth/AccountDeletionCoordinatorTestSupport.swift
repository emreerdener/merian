import Foundation
@testable import Merian

final class AccountDeletionSecureStoreStub:
    AccountDeletionRecoverySecureStore {
    struct Failure: Error {}

    var values: [String: Data] = [:]
    var readError: Error?
    var removalError: Error?
    var acceptsWrites = true
    private(set) var removals: [String] = []
    private var generation = 0

    func dataOrThrow(forKey key: String) throws -> Data? {
        if let readError { throw readError }
        return values[key]
    }

    func set(
        _ data: Data,
        forKey key: String,
        accessibility _: KeychainManager.Accessibility
    ) -> Bool {
        guard acceptsWrites else { return false }
        values[key] = data
        return true
    }

    func removeObjectVerified(forKey key: String) throws {
        removals.append(key)
        if let removalError { throw removalError }
        values.removeValue(forKey: key)
    }

    func makeCapabilityStore() -> AccountDeletionRecoveryCapabilityStore {
        AccountDeletionRecoveryCapabilityStore(
            secureStore: self,
            generateCapability: { [self] in
                generation += 1
                return Data(repeating: UInt8(generation), count: 32)
            }
        )
    }
}

@MainActor
final class AccountDeletionCoordinatorHarness {
    let sourceIdentity = AuthTransitionSession(
        userID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        isAnonymous: false
    )
    let token = AuthTransitionToken(
        id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
        kind: .accountDeletion
    )

    var events: [String] = []
    var recoveryState: AccountDeletionLocalRecoveryState?
    var hasPendingPurchaseIdentityHandoff = false
    var transitionCanBegin = true
    var transitionIsOwned = false
    var sessionMatchesTransition = true
    var recorderSucceeds = true
    var resolutionSucceeds = true
    var adoptionSucceeds = true
    var signOutSucceeds = true
    var cachedSessionIsExpired = false
    var cachedSessionLoadError: Error?
    var currentCachedIdentity: AuthTransitionSession?
    var loadedCachedIdentity: AuthTransitionSession?
    private(set) var publishedIdentity: AuthTransitionSession?

    init() {
        currentCachedIdentity = sourceIdentity
        loadedCachedIdentity = sourceIdentity
    }

    func makeDependencies() -> AccountDeletionCoordinationDependencies {
        AccountDeletionCoordinationDependencies(
            hasPendingPurchaseIdentityHandoff: {
                self.hasPendingPurchaseIdentityHandoff
            },
            localState: AccountDeletionLocalStateBoundary(
                state: { self.recoveryState },
                isPending: { self.recoveryState != nil },
                recordCapabilityPreparationPending: {
                    self.record(
                        .capabilityPreparationPending,
                        event: "record-capability-preparation"
                    )
                },
                recordCapabilityPreparedPending: {
                    self.record(
                        .capabilityPreparedPending,
                        event: "record-capability-prepared"
                    )
                },
                recordIntakePending: {
                    self.record(
                        .capabilityIntakePending,
                        event: "record-intake"
                    )
                },
                recordCleanupPending: {
                    self.record(
                        .capabilityCleanupPending,
                        event: "record-cleanup"
                    )
                },
                recordCapabilityRetirementPending: {
                    self.record(
                        .capabilityRetirementPending,
                        event: "record-capability-retirement"
                    )
                },
                recordCapabilityRejectionRetirementPending: {
                    self.record(
                        .capabilityRejectionRetirementPending,
                        event: "record-rejection-retirement"
                    )
                },
                resolve: {
                    self.events.append("resolve")
                    guard self.resolutionSucceeds else { return false }
                    self.recoveryState = nil
                    return true
                }
            ),
            session: AccountDeletionSessionBoundary(
                beginTransition: { kind in
                    self.events.append("begin-\(Self.name(of: kind))")
                    guard self.transitionCanBegin else { return nil }
                    self.transitionIsOwned = true
                    return AuthTransitionToken(id: self.token.id, kind: kind)
                },
                finishTransition: { _ in
                    self.events.append("finish")
                    self.transitionIsOwned = false
                },
                updateTransition: { _, phase in
                    self.events.append("phase-\(phase.rawValue)")
                },
                ownsTransition: { _ in
                    self.transitionIsOwned
                },
                verifyExpectedSession: { _ in
                    self.events.append("verify-session")
                    guard self.sessionMatchesTransition else {
                        throw SupabaseAuthTransitionError.signOutSessionChanged
                    }
                },
                currentSessionMatchesTransition: { _ in
                    self.transitionIsOwned && self.sessionMatchesTransition
                },
                sourceSession: { _ in
                    self.sourceIdentity
                },
                loadCachedSession: {
                    self.events.append("load-cached-session")
                    if let cachedSessionLoadError =
                        self.cachedSessionLoadError {
                        throw cachedSessionLoadError
                    }
                    guard let identity = self.loadedCachedIdentity else {
                        throw AccountDeletionSecureStoreStub.Failure()
                    }
                    return AccountDeletionCachedSession(
                        identity: identity,
                        isExpired: self.cachedSessionIsExpired
                    )
                },
                currentCachedSession: {
                    self.currentCachedIdentity
                },
                adoptCachedSession: { identity, _ in
                    self.events.append("adopt-cached-session")
                    return self.adoptionSucceeds
                        && self.currentCachedIdentity == identity
                },
                publishCachedSession: { identity in
                    self.events.append("publish-cached-session")
                    self.publishedIdentity = identity
                },
                performVerifiedLocalSignOut: { _ in
                    self.events.append("sign-out")
                    if self.signOutSucceeds {
                        self.currentCachedIdentity = nil
                    }
                    return self.signOutSucceeds
                }
            ),
            diagnostics: AccountDeletionDiagnostics(
                reportAcknowledgementPending: { _ in
                    self.events.append("diagnose-acknowledgement")
                },
                reportAcceptedCleanupPending: {
                    self.events.append("diagnose-cleanup")
                },
                reportRecoveryProofUnavailable: {
                    self.events.append("diagnose-proof")
                },
                reportCapabilityRecoveryPending: { _ in
                    self.events.append("diagnose-recovery")
                }
            )
        )
    }

    private func record(
        _ state: AccountDeletionLocalRecoveryState,
        event: String
    ) -> Bool {
        events.append(event)
        guard recorderSucceeds else { return false }
        recoveryState = state
        return true
    }

    private static func name(of kind: AuthTransitionKind) -> String {
        switch kind {
        case .accountDeletion:
            "account-deletion"
        case .accountDeletionCleanup:
            "account-deletion-cleanup"
        default:
            "unexpected"
        }
    }
}
