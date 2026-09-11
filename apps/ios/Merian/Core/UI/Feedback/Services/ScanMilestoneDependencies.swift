import Foundation
import SwiftData

extension ScanMilestoneCoordinator {
    @MainActor
    struct Dependencies {
        let currentAccountID: () -> String?
        let acknowledgeFieldTripProgress: (_ scanID: String) -> Void
        let saveFirstFieldTripAchievement: (
            _ progress: FirstFieldTripAchievementProgress,
            _ accountID: String
        ) -> Void
        let evaluateAchievementsForNotifications: (
            _ awards: [AwardPayload]
        ) -> [AwardPayload]

        static let live = Self(
            currentAccountID: {
                SupabaseManager.shared.currentUser?.id.uuidString
            },
            acknowledgeFieldTripProgress: { scanID in
                OfflineQueueManager.shared.acknowledgeFieldTripProgress(
                    scanId: scanID
                )
            },
            saveFirstFieldTripAchievement: { progress, accountID in
                FirstFieldTripAchievementProgressStore.save(
                    progress,
                    accountId: accountID
                )
            },
            evaluateAchievementsForNotifications: { awards in
                GamificationManager.shared.evaluateAchievementsForNotifications(
                    awards: awards
                )
            }
        )
    }
}

@MainActor
enum ScanMilestoneLiveServices {
    static func fieldTripsAvailable() -> Bool {
        FeatureFlags.isEnabled(.fieldTrips)
    }

    static func resolveProgress(
        scanID: String,
        preferredGoal: FieldTripPreferredGoal?
    ) async -> ScanMilestoneCoordinator.ProgressResolution {
        do {
            var isPersisted = false
            let retryDelaysMilliseconds = [0, 250, 500, 1_000, 2_000, 4_000]
            for delay in retryDelaysMilliseconds {
                if delay > 0 {
                    try await Task.sleep(for: .milliseconds(delay))
                }
                try Task.checkCancellation()
                let status = try await MerianNetworkClient.shared
                    .checkScanStatusDetails(scanId: scanID)
                if status.isFound {
                    isPersisted = true
                    break
                }
                if status.jobStatus == .failed {
                    return .terminalFailure
                }
            }
            guard isPersisted else {
                MerianLog.general.debug(
                    "Field trip progress deferred because remote scan persistence is not complete."
                )
                return .retryableFailure
            }

            return .success(
                try await MerianNetworkClient.shared.applyFieldTripProgress(
                    scanId: scanID,
                    preferredGoal: preferredGoal
                )
            )
        } catch is CancellationError {
            return .retryableFailure
        } catch {
            MerianLog.general.debug(
                "Field trip progress update failed: \(error, privacy: .private)"
            )
            return .retryableFailure
        }
    }

    static func resolveAchievements(
        modelContainer: ModelContainer?
    ) async -> [AwardPayload] {
        guard let modelContainer else { return [] }

        let profileActor = OfflineQueueManager.shared.resolvedProfileDbActor(
            container: modelContainer
        )
        let updatedAwards = await profileActor.calculateAwards()
        return GamificationManager.shared.evaluateAchievementsForNotifications(
            awards: updatedAwards
        )
    }
}
