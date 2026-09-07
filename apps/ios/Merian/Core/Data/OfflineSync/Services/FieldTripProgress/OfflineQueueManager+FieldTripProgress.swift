import Foundation
import SwiftData

// MARK: - Field Trip Progress

extension OfflineQueueManager {

    /// Removes the durable Capture preference only after the server has
    /// acknowledged the atomic Field Trip progress mutation (or a terminal
    /// response). Until then the row is a small, process-independent outbox.
    func acknowledgeFieldTripProgress(scanId: String) {
        guard let context = modelContext else { return }
        context.deletePreferredGoalHint(scanId: scanId)
        do {
            try context.save()
        } catch {
            context.rollback()
            MerianLog.data.error(
                "acknowledgeFieldTripProgress: failed to remove goal hint for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
        }
    }

    /// Replays Field Trip progress preferences left behind by a process exit
    /// after scan persistence but before the progress endpoint acknowledged.
    func replayPendingFieldTripProgress() async {
        guard isOnline, let context = modelContext else { return }
        let hints: [(String, FieldTripPreferredGoal)]
        do {
            let queuedScanIds = Set(
                try context.fetch(FetchDescriptor<OfflineQueuedScan>()).map(\.id)
            )
            hints = try context.fetch(FetchDescriptor<ActiveOfflineQueuedScanGoalHint>())
                .filter { !queuedScanIds.contains($0.scanId) }
                .map {
                    (
                        $0.scanId,
                        FieldTripPreferredGoal(
                            userFieldTripId: $0.userFieldTripId,
                            itemId: $0.itemId
                        )
                    )
                }
        } catch {
            MerianLog.data.error(
                "replayPendingFieldTripProgress: failed to read durable goal hints: \(error, privacy: .private)"
            )
            return
        }

        for (scanId, preferredGoal) in hints {
            await AppDIContainer.shared.scanMilestoneCoordinator.processCompletedScan(
                scanId: scanId,
                speciesData: nil,
                modelContainer: context.container,
                preferredGoal: preferredGoal
            )
        }
    }
}
