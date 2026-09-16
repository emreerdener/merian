import Foundation
@testable import Merian

enum GhostProfileMergeCoordinatorTestError: Error, Equatable {
    case queue
    case remote
    case provider
    case localEvidence
    case targetEvidence
    case terminal
    case session
}

actor GhostProfileMergeCoordinatorTestGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var released = false

    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitUntilWaiterCount(_ expectedCount: Int) async {
        while !released && continuations.count < expectedCount {
            await Task.yield()
        }
    }

    func release() {
        released = true
        let pending = continuations
        continuations.removeAll(keepingCapacity: false)
        pending.forEach { $0.resume() }
    }
}

@MainActor
final class GhostProfileMergeCoordinatorHarness {
    let source = AuthTransitionSession(
        userID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        isAnonymous: true
    )
    let target = AuthTransitionSession(
        userID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
        isAnonymous: false
    )
    let replacementTarget = AuthTransitionSession(
        userID: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
        isAnonymous: false
    )
    let transition = AuthTransitionToken(
        id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
        kind: .oauth(.google)
    )

    var events: [String] = []
    var currentIdentity: AuthTransitionSession?
    var activeTransitionID: UUID?
    var transitionMatches = true
    var isSigningOut = false
    var queue: [PendingGhostProfileMerge] = []
    var queueLoadError: Error?
    var queuePersistError: Error?
    var queueClearError: Error?
    var prepareError: Error?
    var prepareGate: GhostProfileMergeCoordinatorTestGate?
    var completeGate: GhostProfileMergeCoordinatorTestGate?
    var completionErrorsByHandoffID: [String: Error] = [:]
    var providerSyncError: Error?
    var localEvidenceError: Error?
    var targetEvidenceSyncError: Error?
    var targetEvidenceMatches = true
    var terminalErrors: [GhostProfileMergeCoordinatorTestError] = [.terminal]
    private(set) var analyticsIsSuppressed = false
    private(set) var prepareCount = 0
    private(set) var completeCount = 0
    private(set) var persistCount = 0
    private(set) var clearCount = 0
    private(set) var targetEvidenceSyncCount = 0

    func makeDependencies() -> GhostProfileMergeDependencies {
        GhostProfileMergeDependencies(
            session: .init(
                isSigningOut: {
                    self.isSigningOut
                },
                currentPublishedSession: {
                    self.currentIdentity
                },
                currentSDKSession: {
                    self.currentIdentity
                },
                currentSessionMatchesTransition: { transition in
                    self.transitionMatches
                        && self.activeTransitionID == transition.id
                },
                beginUnownedAccountWork: { expectedUserID in
                    self.events.append("begin-lease")
                    guard self.currentIdentity?.userID == expectedUserID else {
                        return nil
                    }
                    return AccountBoundWorkLease(
                        id: UUID(),
                        session: self.currentIdentity!
                    )
                },
                finishAccountWork: { _ in
                    self.events.append("finish-lease")
                },
                loadSDKSession: {
                    self.events.append("load-session")
                    guard let currentIdentity = self.currentIdentity else {
                        throw GhostProfileMergeCoordinatorTestError.session
                    }
                    return currentIdentity
                }
            ),
            queue: .init(
                load: {
                    self.events.append("load-queue")
                    if let queueLoadError = self.queueLoadError {
                        throw queueLoadError
                    }
                    return GhostProfileMergeQueueSnapshot(
                        handoffs: self.queue,
                        legacyMigrationWasDeferred: false
                    )
                },
                persist: { handoffs in
                    self.events.append("persist-queue")
                    self.persistCount += 1
                    if let queuePersistError = self.queuePersistError {
                        throw queuePersistError
                    }
                    self.queue = handoffs
                },
                clear: { handoffID in
                    self.events.append("clear-\(handoffID)")
                    if let queueClearError = self.queueClearError {
                        throw queueClearError
                    }
                    self.clearCount += 1
                    self.queue.removeAll {
                        $0.handoffId.caseInsensitiveCompare(handoffID)
                            == .orderedSame
                    }
                },
                clearSource: { sourceUserID in
                    self.events.append("clear-source")
                    if let queueClearError = self.queueClearError {
                        throw queueClearError
                    }
                    self.queue.removeAll {
                        $0.ghostUserId.caseInsensitiveCompare(sourceUserID)
                            == .orderedSame
                    }
                    return self.queue
                }
            ),
            operations: .init(
                prepare: { _, _ in
                    self.events.append("prepare-remote")
                    self.prepareCount += 1
                    let gate = self.prepareGate
                    self.prepareGate = nil
                    if let gate {
                        await gate.wait()
                    }
                    if let prepareError = self.prepareError {
                        throw prepareError
                    }
                    return GhostProfileMergePreparation(
                        handoffID:
                            "11111111-1111-1111-1111-111111111111",
                        handoffSecret:
                            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
                        expiresAt: "2026-09-14T00:10:00Z"
                    )
                },
                complete: { handoff in
                    self.events.append("complete-\(handoff.handoffId)")
                    self.completeCount += 1
                    let gate = self.completeGate
                    self.completeGate = nil
                    if let gate {
                        await gate.wait()
                    }
                    if let error = self.completionErrorsByHandoffID[
                        handoff.handoffId
                    ] {
                        throw error
                    }
                },
                synchronizeProviderPurchases: {
                    self.events.append("synchronize-provider")
                    if let providerSyncError = self.providerSyncError {
                        throw providerSyncError
                    }
                },
                rebindAndSynchronizeLocalEvidence: { source, target in
                    self.events.append(
                        "rebind-\(source.uuidString.lowercased())-\(target.uuidString.lowercased())"
                    )
                    if let localEvidenceError = self.localEvidenceError {
                        throw localEvidenceError
                    }
                },
                synchronizeTargetEvidence: { _ in
                    self.events.append("synchronize-target-evidence")
                    self.targetEvidenceSyncCount += 1
                    if let targetEvidenceSyncError =
                        self.targetEvidenceSyncError {
                        throw targetEvidenceSyncError
                    }
                },
                targetEvidenceMatches: { targetUserID in
                    self.targetEvidenceMatches
                        && self.currentIdentity?.userID == targetUserID
                },
                isTerminalHandoffError: { error in
                    guard let error = error as?
                        GhostProfileMergeCoordinatorTestError else {
                        return false
                    }
                    return self.terminalErrors.contains(error)
                }
            ),
            setAnalyticsSuppressed: { isSuppressed in
                self.events.append("suppressed-\(isSuppressed)")
                self.analyticsIsSuppressed = isSuppressed
            },
            diagnose: { diagnostic, _ in
                self.events.append("diagnose-\(diagnostic)")
            }
        )
    }

    func makeHandoff(
        id: String = "11111111-1111-1111-1111-111111111111",
        sourceUserID: UUID? = nil
    ) -> PendingGhostProfileMerge {
        PendingGhostProfileMerge(
            ghostUserId: (sourceUserID ?? source.userID).uuidString.lowercased(),
            provider: "google",
            providerSubject: "provider-subject",
            handoffId: id,
            handoffSecret:
                "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            expiresAt: "2026-09-14T00:10:00Z"
        )
    }
}
