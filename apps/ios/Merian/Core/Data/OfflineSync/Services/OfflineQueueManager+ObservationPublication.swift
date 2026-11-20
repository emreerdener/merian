import Foundation
import SwiftData

extension OfflineQueueManager {
    func syncObservationPublications() async {
        guard isOnline, !isCurrentNetworkConstrained, let context = modelContext,
              let owner = CloudDeletionAccountWork.currentAccountID else { return }
        let scheduler = OfflineJobScheduler.shared
        await publicationDeliveryOwner.run(didFinish: { [weak self] in
            guard let self else { return }
            self.publicationDeliveryDidFinish(ownerID: owner, context: context, currentOwnerID: CloudDeletionAccountWork.currentAccountID)
            scheduler.scheduleNextPersistedWake(using: self)
        }) { [weak self] in
            guard let self else { return }
            await ObservationPublicationDeliveryService().drain(container: context.container,
                isAvailable: { self.modelContext === context && self.isOnline && !self.isCurrentNetworkConstrained &&
                    CloudDeletionAccountWork.currentAccountID == owner },
                didStart: { scheduler.publicationDrainDidStart(using: self) },
                requestRetry: { scheduler.schedulePublicationRetry(using: self) })
        }
    }
}
