import SwiftData

extension ModelContext {
    func preferredGoalHint(scanId: String) -> FieldTripPreferredGoal? {
        var descriptor = FetchDescriptor<ActiveOfflineQueuedScanGoalHint>(
            predicate: #Predicate { $0.scanId == scanId }
        )
        descriptor.fetchLimit = 1
        guard let hint = try? fetch(descriptor).first else { return nil }
        return FieldTripPreferredGoal(
            userFieldTripId: hint.userFieldTripId,
            itemId: hint.itemId
        )
    }

    func deletePreferredGoalHint(scanId: String) {
        var descriptor = FetchDescriptor<ActiveOfflineQueuedScanGoalHint>(
            predicate: #Predicate { $0.scanId == scanId }
        )
        descriptor.fetchLimit = 1
        if let hint = try? fetch(descriptor).first {
            delete(hint)
        }
    }
}
