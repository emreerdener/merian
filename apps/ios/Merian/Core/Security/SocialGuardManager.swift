import Foundation
import Observation
import os

@MainActor
@Observable final class SocialGuardManager {
    static let shared = SocialGuardManager()
    private init() {}

    // MARK: - State

    var blockedUserIds: Set<String> = []

    // MARK: - Actions

    func blockUser(targetUserId: String) async {
        // Optimistically update local state.
        blockedUserIds.insert(targetUserId)
        HapticManager.shared.triggerErrorThump()

        let success = await syncBlockWithBackend(targetUserId: targetUserId)

        if !success {
            // Revert on failure.
            blockedUserIds.remove(targetUserId)
            MerianLog.general.debug("Block failed; reverted local state for user \(targetUserId, privacy: .private)")
        } else {
            MerianLog.general.debug("Block succeeded for user \(targetUserId, privacy: .private)")
        }
    }

    // MARK: - Private

    private func syncBlockWithBackend(targetUserId: String) async -> Bool {
        do {
            try await MerianNetworkClient.shared.blockUser(targetUserId: targetUserId)
            return true
        } catch {
            return false
        }
    }
}
