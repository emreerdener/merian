import Foundation

/// Keeps the request's originating account stable through deletion admission
/// and acknowledgement. A payload account is never sent as server authority.
@MainActor
struct CloudDeletionAccountWork {
    var begin: () throws -> AccountBoundWorkLease
    var isCurrent: (AccountBoundWorkLease) -> Bool
    var finish: (AccountBoundWorkLease) -> Void

    static let live = Self(
        begin: { try SupabaseManager.shared.beginUnownedAccountBoundWork() },
        isCurrent: { SupabaseManager.shared.isAccountBoundWorkLeaseCurrent($0) },
        finish: { SupabaseManager.shared.finishAccountBoundWork($0) }
    )

    static var currentAccountID: UUID? {
        let manager = SupabaseManager.shared
        return manager.allowsUnownedAccountBoundWork ? manager.currentUser?.id : nil
    }

    /// Synchronous enqueue callers commit on the same main-actor turn. Unknown
    /// account context deliberately produces a held, unproven request.
    static func captureRequestAccount(using client: HistoricalSyncCloudClient) -> UUID? {
        guard let lease = try? client.beginAccountWork() else { return nil }
        defer { client.finishAccountWork(lease) }
        return client.isAccountWorkCurrent(lease) ? lease.session.userID : nil
    }
}
