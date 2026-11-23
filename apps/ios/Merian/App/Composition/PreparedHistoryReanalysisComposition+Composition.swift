import Foundation
import SwiftData

extension PreparedHistoryReanalysisComposition {
    /// Uses the existing retained queue owners and authenticated transport. Constructing this starts no work.
    @MainActor
    static func compositionConfiguration(in dependencies: AppDIContainer, cloud: ObservationHistoryCloudClient,
                                         client: MerianNetworkClient) -> CaptureReanalysisAccess.CompositionStart {
        let queue = dependencies.offlineQueueManager
        return { ready, session, generation, container, files in
            guard queue.modelContext?.container === container else { return false }
            let current = preparedAccountScope(in: dependencies)
            do { try ObservationCompositionResumeSubmission.validate(ready, container: container, isCurrent: { current(session, generation) }) } catch { return false }
            let submission = ObservationCompositionSubmissionService(
                reservation: .live(files: files, transport: client.sourceReservationTransport()),
                upload: .live(files: files, transport: client.compositionEvidenceTransport()),
                authorize: { owner, validate in
                    try await client.prepareBoundObservationReanalysisAuthorization(processor: .gemini,
                        expectedAuthUserID: owner, validateAttempt: validate)
                })
            let execution = ObservationCompositionExecutionService(dependencies: .live(client: client, account: cloud))
            let changed = {
                guard let context = queue.modelContext, context.container === container, current(session, generation) else { return }
                queue.reanalysisExecutionDidFinish(ownerID: session.userID, context: context, currentOwnerID: session.userID)
                dependencies.appEventPublisher.send(.scanLibraryChanged)
            }
            switch ready.route {
            case let .reservation(snapshot):
                return Self.compositionStarted(queue.requestCompositionSourceSubmission(.init(snapshot: snapshot, session: session,
                    generation: generation, container: ObjectIdentifier(container)), proof: ready.proof,
                    account: cloud, submission: submission, execution: execution, erasure: queue.reanalysisErasureOwner,
                    isCurrentAccount: current, didChange: changed))
            case let .upload(snapshot):
                return Self.compositionStarted(queue.requestCompositionUploadSubmission(.init(snapshot: snapshot, session: session,
                    generation: generation, container: ObjectIdentifier(container),
                    route: snapshot.work.receipt?.state == .ready ? .bindReady : .upload), proof: ready.proof,
                    account: cloud, submission: submission, execution: execution, erasure: queue.reanalysisErasureOwner,
                    isCurrentAccount: current, didChange: changed))
            case let .execution(snapshot):
                return Self.compositionStarted(queue.requestCompositionExecution(.init(snapshot: snapshot, session: session,
                    generation: generation, container: ObjectIdentifier(container)), proof: ready.proof,
                    account: cloud, service: execution, erasure: queue.reanalysisErasureOwner,
                    isCurrentAccount: current, didComplete: changed))
            }
        }
    }
    @MainActor
    static func compositionContinuation(in dependencies: AppDIContainer, cloud: ObservationHistoryCloudClient,
                                        client: MerianNetworkClient) -> ReanalysisStatusAccess.CompositionContinuation {
        let start = compositionConfiguration(in: dependencies, cloud: cloud, client: client)
        let queue = dependencies.offlineQueueManager
        return { identity, outcomeOnly, container, isCurrent in
            guard queue.modelContext?.container === container else { throw ObservationHistoryError.accountChanged }
            let lease = try cloud.begin(identity.ownerID)
            defer { cloud.finish(lease) }
            let generation = dependencies.supabaseManager.authSessionGeneration
            let accountCurrent = preparedAccountScope(in: dependencies)
            let current: @MainActor @Sendable () -> Bool = {
                isCurrent() && cloud.isCurrent(lease) && accountCurrent(lease.session, generation)
                    && queue.modelContext?.container === container
            }
            let files = try ObservationReanalysisFileStore(documents: FileManager.default.url(for: .documentDirectory,
                in: .userDomainMask, appropriateFor: nil, create: false))
            let producer = ObservationCompositionProducer(files: files, ownership: queue.reanalysisPreparationOwner, account: cloud)
            // A displayed outcome action cannot drift into an unconsumed dispatch after an await.
            if outcomeOnly {
                let saved = try await ObservationCompositionResumeReader(ownership: producer.ownership, account: cloud)
                    .read(identity, container: container, isCurrent: current)
                guard case let .execution(snapshot) = saved.state, snapshot.work.consumed else { throw ObservationHistoryError.unavailable }
            }
            guard let ready = try await ObservationCompositionResumeSubmission(producer: producer)
                .resume(identity, container: container, isCurrent: current) else { return false }
            if outcomeOnly {
                guard case let .execution(snapshot) = ready.route, snapshot.work.consumed else { throw ObservationHistoryError.unavailable }
            }
            guard current() else { throw ObservationHistoryError.accountChanged }
            return start(ready, lease.session, generation, container, files)
        }
    }

    private static func compositionStarted(_ admission: ObservationCompositionReservationOwner.Admission) -> Bool {
        switch admission {
        case .started, .coalesced: return true
        case .unavailable: return false
        }
    }
    private static func compositionStarted(_ admission: ObservationCompositionUploadOwner.Admission) -> Bool {
        switch admission {
        case .started, .coalesced: return true
        case .unavailable: return false
        }
    }
    private static func compositionStarted(_ admission: ObservationCompositionExecutionOwner.Admission) -> Bool {
        switch admission {
        case .started, .coalesced: return true
        case .unavailable: return false
        }
    }
}
