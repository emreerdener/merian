import Foundation
import SwiftData

extension OfflineQueueManager {
    func syncObservationPublications() async {
        guard isOnline, !isCurrentNetworkConstrained, let context = modelContext else { return }
        let scheduler = OfflineJobScheduler.shared
        await publicationDeliveryOwner.run { [weak self] in
            guard let self else { return }
            await ObservationPublicationDeliveryService().drain(container: context.container,
                isAvailable: { self.modelContext === context && self.isOnline && !self.isCurrentNetworkConstrained },
                didStart: { scheduler.publicationDrainDidStart(using: self) },
                requestRetry: { scheduler.schedulePublicationRetry(using: self) })
        }
        scheduler.scheduleNextPersistedWake(using: self)
    }
}
