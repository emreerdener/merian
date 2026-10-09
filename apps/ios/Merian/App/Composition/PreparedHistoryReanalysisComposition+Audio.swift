import Foundation
import SwiftData

extension PreparedHistoryReanalysisComposition {
    /// Parent retains this candidate across sheet dismissal; ordinary routes remain uninstalled.
    @MainActor
    func openAudioHost(target: HistoricalReanalysisTarget, container: ModelContainer) throws -> CaptureAudioReanalysisHost {
        guard let audioCapture, let audioHostOwner else { throw ObservationHistoryError.unavailable }
        return try audioHostOwner.open(target: target, container: container) {
            try CaptureAudioReanalysisHost(opened: audioCapture.open(target, container, UUID()))
        }
    }

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
        let queue = dependencies.offlineQueueManager
        return .init(authorize: { owner, validate in
            try await client.prepareBoundObservationReanalysisAuthorization(processor: .gemini,
                expectedAuthUserID: owner, validateAttempt: validate)
        }, start: { key, proof, container, files in
            guard queue.modelContext?.container === container else { return .unavailable }
            return queue.requestAudioExecution(key, proof: proof, account: cloud,
                service: .init(dependencies: .live(files: files, client: client)), erasure: queue.reanalysisErasureOwner,
                isCurrentAccount: audioAccountScope(in: dependencies), didComplete: { dependencies.appEventPublisher.send(.scanLibraryChanged) })
        })
    }

    /// Separate source boundary; constructing it never installs an ordinary Capture route.
    @MainActor
    static func audioSourceConfiguration(in dependencies: AppDIContainer, cloud: ObservationHistoryCloudClient,
                                         client: MerianNetworkClient) -> CaptureAudioSourceReanalysisAccess.Configuration {
        .init(start: audioConfiguration(in: dependencies, cloud: cloud, client: client).start,
              sourceStart: audioSourceStart(in: dependencies, cloud: cloud, client: client))
    }

    /// Source-enabled handoff factory for inert Capture composition; ordinary routes remain uninstalled.
    @MainActor
    static func audioSourceStart(in dependencies: AppDIContainer, cloud: ObservationHistoryCloudClient,
                                 client: MerianNetworkClient) -> (ObservationSourceReservationOwner.Key, ObservationAudioPreparation.Verified,
                                                                ModelContainer, ObservationReanalysisFileStore) -> ObservationSourceReservationOwner.Admission {
        let queue = dependencies.offlineQueueManager
        return { key, proof, container, files in
            guard queue.modelContext?.container === container else { return .unavailable }
            return queue.requestAudioSourceSubmission(key, proof: proof, account: cloud,
                source: .live(client: client), execution: .init(dependencies: .live(files: files, client: client)),
                erasure: queue.reanalysisErasureOwner, isCurrentAccount: audioAccountScope(in: dependencies), didChange: { dependencies.appEventPublisher.send(.scanLibraryChanged) })
        }
    }

    @MainActor
    private static func audioAccountScope(in dependencies: AppDIContainer) -> @MainActor @Sendable (AuthTransitionSession, UInt64) -> Bool {
        let manager = dependencies.supabaseManager
        return { session, generation in
            manager.allowsUnownedAccountBoundWork && manager.authSessionGeneration == generation &&
                manager.currentUser?.id == session.userID && manager.currentUser?.isAnonymous == session.isAnonymous &&
                manager.client.auth.currentSession?.user.id == session.userID &&
                manager.client.auth.currentSession?.user.isAnonymous == session.isAnonymous
        }
    }

}
