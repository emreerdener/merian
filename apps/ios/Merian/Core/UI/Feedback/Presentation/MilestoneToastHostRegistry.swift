import Foundation
import Observation

/// Tracks nested visual hosts without retaining views. The most recently
/// mounted host owns presentation; removing it restores the previous host.
@MainActor
@Observable final class MilestoneToastHostRegistry {
    private(set) var hostIDs: [UUID] = []
    @ObservationIgnored private let maximumHostCount: Int

    init(maximumHostCount: Int = 8) {
        self.maximumHostCount = max(1, maximumHostCount)
    }

    var activeHostID: UUID? {
        hostIDs.last
    }

    func register(_ hostID: UUID) {
        guard activeHostID != hostID else { return }
        hostIDs.removeAll(where: { $0 == hostID })
        hostIDs.append(hostID)
        if hostIDs.count > maximumHostCount {
            hostIDs.removeFirst(hostIDs.count - maximumHostCount)
        }
    }

    func unregister(_ hostID: UUID) {
        hostIDs.removeAll(where: { $0 == hostID })
    }
}
