import Foundation
import SwiftData

extension PreparedHistoryReanalysisComposition {
    @MainActor
    func openVideoHost(target: HistoricalReanalysisTarget, container: ModelContainer) throws -> CaptureVideoReanalysisHost {
        guard let videoCapture, let audioHostOwner else { throw ObservationHistoryError.unavailable }
        return try audioHostOwner.openVideo(target: target, container: container) {
            try CaptureVideoReanalysisHost(opened: videoCapture.open(target, container, UUID()))
        }
    }

    @MainActor
    static func freshVideoConfiguration(in dependencies: AppDIContainer, cloud: ObservationHistoryCloudClient,
                                        client: MerianNetworkClient) -> CaptureVideoReanalysisAccess.Configuration {
        .init(resume: videoConfiguration(in: dependencies, cloud: cloud, client: client),
              files: .shared, temporaryDirectory: { FileManager.default.temporaryDirectory },
              prepareLifetime: { try dependencies.prepareReanalysisHostLifetimeForFeature() },
              startup: { try dependencies.reanalysisStartupForFeature(container: $0) },
              borrowing: { try dependencies.reanalysisBorrowForFeature(container: $0) })
    }

    /// Explicit saved-child presentation only. Ordinary app routes remain uninstalled.
    @MainActor
    func openSavedVideoRequests(ownerID: UUID, observationID: UUID, container: ModelContainer,
                                isPresented: @escaping @MainActor () -> Bool) throws -> CaptureVideoSavedRequestsModel {
        guard isPresented(), let videoStatus, let videoResume else { throw ObservationHistoryError.unavailable }
        let opened = try videoStatus.open(ownerID, observationID, container)
        return CaptureVideoSavedRequestsModel(status: opened, openResume: { identity in
            guard identity.ownerID == ownerID, identity.observationID == observationID else { throw ObservationHistoryError.unavailable }
            return try videoResume.openResume(identity, container)
        }, isPresented: isPresented)
    }

    /// Uses the existing retained queue owners and authenticated transport. Constructing this starts no work.
    @MainActor
    static func videoConfiguration(in dependencies: AppDIContainer, cloud: ObservationHistoryCloudClient,
                                   client: MerianNetworkClient) -> CaptureVideoResumeAccess.Configuration {
        let queue = dependencies.offlineQueueManager
        return .init(start: { ready, session, generation, container, files in
            guard queue.modelContext?.container === container else { return .unavailable }
            let current = preparedAccountScope(in: dependencies)
            do { try ObservationVideoResumeSubmission.validate(ready, container: container, isCurrent: { current(session, generation) }) } catch { return .unavailable }
            let submission = ObservationVideoSubmissionService(
                reservation: .live(files: files, transport: client.sourceReservationTransport()),
                upload: .live(files: files, transport: client.videoEvidenceTransport()),
                authorize: { owner, validate in
                    try await client.prepareBoundObservationReanalysisAuthorization(processor: .gemini,
                        expectedAuthUserID: owner, validateAttempt: validate)
                })
            let execution = ObservationVideoExecutionService(dependencies: .live(client: client, account: cloud))
            let changed = { dependencies.appEventPublisher.send(.scanLibraryChanged) }
            switch ready.route {
            case let .reservation(snapshot):
                return .init(queue.requestVideoSourceSubmission(.init(snapshot: snapshot, session: session,
                    generation: generation, container: ObjectIdentifier(container)), proof: ready.proof,
                    account: cloud, submission: submission, execution: execution, erasure: queue.reanalysisErasureOwner,
                    isCurrentAccount: current, didChange: changed))
            case let .upload(snapshot):
                return .init(queue.requestVideoUploadSubmission(.init(snapshot: snapshot, session: session,
                    generation: generation, container: ObjectIdentifier(container),
                    route: snapshot.work.receipt?.state == .ready ? .bindReady : .upload), proof: ready.proof,
                    account: cloud, submission: submission, execution: execution, erasure: queue.reanalysisErasureOwner,
                    isCurrentAccount: current, didChange: changed))
            case let .execution(snapshot):
                return .init(queue.requestVideoExecution(.init(snapshot: snapshot, session: session,
                    generation: generation, container: ObjectIdentifier(container)), proof: ready.proof,
                    account: cloud, service: execution, erasure: queue.reanalysisErasureOwner,
                    isCurrentAccount: current, didComplete: changed))
            }
        }, recover: { key, proof, container, _ in
            guard key.snapshot.work.consumed, queue.modelContext?.container === container else { throw ObservationHistoryError.unavailable }
            let current = preparedAccountScope(in: dependencies)
            let admission = queue.requestVideoExecution(key, proof: proof, account: cloud,
                service: .init(dependencies: .live(client: client, account: cloud)), erasure: queue.reanalysisErasureOwner,
                isCurrentAccount: current, didComplete: { dependencies.appEventPublisher.send(.scanLibraryChanged) })
            switch admission {
            case .unavailable: throw ObservationHistoryError.unavailable
            case .started, .coalesced: break
            }
            guard let exit = queue.videoExecutionOwner.captureActualExit(key) else { throw ObservationHistoryError.unavailable }
            await exit.wait()
            return try ObservationReanalysisRecoveredResult.contains(key.snapshot.work.preparation.identity, container: container,
                isCurrent: { current(key.session, key.generation) && queue.modelContext?.container === container },
                decode: { try ObservationReanalysisResult.decode($0, matching: key.snapshot.work.request) })
        })
    }
}

extension CaptureVideoResumeAccess.Admission {
    init(_ value: ObservationVideoReservationOwner.Admission) {
        switch value {
        case .started: self = .started
        case .coalesced: self = .coalesced
        case .unavailable: self = .unavailable
        }
    }
    init(_ value: ObservationVideoUploadOwner.Admission) {
        switch value {
        case .started: self = .started
        case .coalesced: self = .coalesced
        case .unavailable: self = .unavailable
        }
    }
    init(_ value: ObservationVideoExecutionOwner.Admission) {
        switch value {
        case .started: self = .started
        case .coalesced: self = .coalesced
        case .unavailable: self = .unavailable
        }
    }
}
