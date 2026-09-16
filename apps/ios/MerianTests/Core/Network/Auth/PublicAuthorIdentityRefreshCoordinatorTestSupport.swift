import Foundation
@testable import Merian

enum PublicAuthorIdentityRefreshTestError: Error {
    case remote
}

actor PublicAuthorIdentityRefreshTestGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitUntilBlocked() async {
        while !isOpen && continuations.isEmpty {
            await Task.yield()
        }
    }

    func open() {
        isOpen = true
        let pending = continuations
        continuations.removeAll(keepingCapacity: false)
        pending.forEach { $0.resume() }
    }
}

@MainActor
final class PublicAuthorIdentityRefreshHarness {
    let firstUserID = UUID(
        uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
    )!
    let secondUserID = UUID(
        uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
    )!
    let transition = AuthTransitionToken(
        id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
        kind: .oauth(.apple)
    )

    var events: [String] = []
    var isTestExecution = false
    var hasActiveTransition = false
    var publishedUserID: UUID?
    var transitionMatches = true
    var allowsAccountWork = true
    var accountWorkIsCurrent = true
    var remoteError: Error?
    private(set) var beginLeaseCount = 0
    private(set) var finishLeaseCount = 0
    private(set) var remoteRefreshCount = 0
    private(set) var publishedChanges: [(String?, String)] = []
    private(set) var reportedFailureCount = 0

    func dependencies(
        label: String,
        mergeGate: PublicAuthorIdentityRefreshTestGate? = nil,
        refreshGate: PublicAuthorIdentityRefreshTestGate? = nil
    ) -> PublicAuthorIdentityRefreshDependencies {
        PublicAuthorIdentityRefreshDependencies(
            session: .init(
                isTestExecution: {
                    self.isTestExecution
                },
                hasActiveTransition: {
                    self.hasActiveTransition
                },
                currentPublishedUserID: {
                    self.publishedUserID
                },
                transitionOwnsExpectedUser: { transition, userID in
                    self.transitionMatches
                        && transition == self.transition
                        && self.publishedUserID == userID
                },
                beginUnownedAccountWork: { userID in
                    self.events.append("begin-\(label)")
                    self.beginLeaseCount += 1
                    guard self.allowsAccountWork else { return nil }
                    return AccountBoundWorkLease(
                        id: UUID(),
                        session: AuthTransitionSession(
                            userID: userID,
                            isAnonymous: false
                        )
                    )
                },
                finishAccountWork: { _ in
                    self.events.append("finish-\(label)")
                    self.finishLeaseCount += 1
                },
                accountWorkIsCurrent: { _ in
                    self.accountWorkIsCurrent
                }
            ),
            operations: .init(
                completePendingGhostMerges: { userID in
                    self.events.append(
                        "merge-\(label)-\(userID.uuidString.lowercased())"
                    )
                    if let mergeGate {
                        await mergeGate.wait()
                    }
                },
                refreshRemoteIdentity: {
                    self.events.append("refresh-\(label)")
                    self.remoteRefreshCount += 1
                    if let refreshGate {
                        await refreshGate.wait()
                    }
                    if let remoteError = self.remoteError {
                        throw remoteError
                    }
                }
            ),
            events: .init(
                publishIdentityChanged: { previousUserID, currentUserID in
                    self.events.append("publish-\(label)-\(currentUserID)")
                    self.publishedChanges.append(
                        (previousUserID, currentUserID)
                    )
                }
            ),
            diagnostics: .init(
                reportRefreshFailure: { _ in
                    self.events.append("diagnose-\(label)")
                    self.reportedFailureCount += 1
                }
            )
        )
    }

    func session(
        userID: UUID? = nil,
        isAnonymous: Bool = false
    ) -> AuthTransitionSession {
        AuthTransitionSession(
            userID: userID ?? firstUserID,
            isAnonymous: isAnonymous
        )
    }
}
