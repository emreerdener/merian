import Foundation
@testable import Merian

enum CloudDeletionTestSupport {
    static let accountID = UUID(uuidString: "00000000-0000-4000-8000-00000000d301")!
    static let otherAccountID = UUID(uuidString: "00000000-0000-4000-8000-00000000d302")!

    @MainActor
    static func accountWork(owner: UUID = accountID) -> CloudDeletionAccountWork {
        CloudDeletionAccountWork(
            begin: { AccountBoundWorkLease(id: UUID(), session: AuthTransitionSession(userID: owner, isAnonymous: false)) },
            isCurrent: { $0.session.userID == owner },
            finish: { _ in }
        )
    }

    @MainActor
    static func scheduler(owner: UUID = accountID) -> OfflineJobScheduler {
        OfflineJobScheduler(drainOperations: .init(
            reconcileFunding: { _ in }, syncPendingScans: { _ in },
            replayInference: { _ in }, replayFieldTripProgress: { _ in },
            syncPendingDeletions: { _ in }, syncCollections: { _ in }
        ), deletionAccountID: { owner })
    }
}
