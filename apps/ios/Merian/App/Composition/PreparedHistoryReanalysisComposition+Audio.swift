import Foundation
import SwiftData

extension PreparedHistoryReanalysisComposition {
    /// Explicit presentation factory only; no route or ordinary installation invokes it.
    @MainActor
    func openSavedAudioRequests(ownerID: UUID, observationID: UUID, container: ModelContainer,
                                isPresented: @escaping @MainActor () -> Bool) throws -> CaptureAudioSavedRequestsModel {
        guard isPresented(), let audioStatus, let audioCapture else { throw ObservationHistoryError.unavailable }
        let opened = try audioStatus.open(ownerID, observationID, container)
        return CaptureAudioSavedRequestsModel(status: opened, openResume: { identity in
            guard identity.ownerID == ownerID, identity.observationID == observationID else { throw ObservationHistoryError.unavailable }
            return try audioCapture.openResume(identity, container)
        }, isPresented: isPresented)
    }

    /// App-owned assembly. This does not install access, start work or capture a presentation predicate.
    @MainActor
    static func audioConfiguration(in dependencies: AppDIContainer, cloud: ObservationHistoryCloudClient,
                                   client: MerianNetworkClient) -> CaptureAudioReanalysisAccess.Configuration {
        let manager = dependencies.supabaseManager, queue = dependencies.offlineQueueManager
        return .init(authorize: { owner, validate in
            try await client.prepareBoundObservationReanalysisAuthorization(processor: .gemini,
                expectedAuthUserID: owner, validateAttempt: validate)
        }, start: { key, proof, container, files in
            guard queue.modelContext?.container === container else { return .unavailable }
            return queue.requestAudioExecution(key, proof: proof, account: cloud,
                service: .init(dependencies: .live(files: files, client: client)), erasure: queue.reanalysisErasureOwner,
                isCurrentAccount: { session, generation in
                    manager.allowsUnownedAccountBoundWork && manager.authSessionGeneration == generation &&
                        manager.currentUser?.id == session.userID && manager.currentUser?.isAnonymous == session.isAnonymous &&
                        manager.client.auth.currentSession?.user.id == session.userID &&
                        manager.client.auth.currentSession?.user.isAnonymous == session.isAnonymous
                }, didComplete: { dependencies.appEventPublisher.send(.scanLibraryChanged) })
        })
    }
}
