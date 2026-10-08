import Foundation

extension PreparedHistoryReanalysisComposition {
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
