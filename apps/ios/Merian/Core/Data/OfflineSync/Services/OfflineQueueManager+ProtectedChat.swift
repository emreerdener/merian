import Foundation
import SwiftData

extension OfflineQueueManager {
    /// Explicit foreground admission only. The generic scheduler never starts or retries chat.
    @discardableResult
    func requestProtectedChatDelivery(_ intent: ProtectedInsightChatIntent,
                                      admission: ProtectedInsightChatDeliveryService.Admission,
                                      service: ProtectedInsightChatDeliveryService,
                                      currentOwnerID: @escaping @MainActor @Sendable () -> UUID?) -> Bool {
        guard isOnline, !isCurrentNetworkConstrained, let context = modelContext,
              currentOwnerID() == intent.ownerID else { return false }
        return protectedChatDeliveryOwner.start(operation: { [weak self] tokenCurrent, dispatchAllowed in
            guard let self else { return }
            let current: @MainActor @Sendable () -> Bool = {
                tokenCurrent() && self.modelContext === context && currentOwnerID() == intent.ownerID
            }
            let dispatch: @MainActor @Sendable () -> Bool = {
                current() && dispatchAllowed() && self.isOnline && !self.isCurrentNetworkConstrained
            }
            do {
                _ = try await service.deliver(intent, admission: admission, container: context.container,
                                              isCurrent: current, permitsDispatch: dispatch)
            } catch {
                // Failed scope or persistence leaves the original durable operation untouched.
                // The actual-exit generation lets its current owner read status; it never schedules a retry.
            }
        }, didFinish: { [weak self] in
            self?.protectedChatDeliveryDidFinish(ownerID: intent.ownerID, context: context, currentOwnerID: currentOwnerID())
        })
    }
}
