import Foundation
import SwiftData

/// Prepared only. Opening freezes an explicit source and account scope without retaining an idle lease.
@MainActor
struct CaptureAudioReanalysisAccess {
    struct Configuration {
        let authorize: @MainActor @Sendable (UUID, @escaping ObservationAudioSubmissionBinding.Validate) async throws -> IdentificationDispatchAuthorization
        // No presentation predicate crosses this boundary into retained queue execution.
        let start: (ObservationAudioExecutionOwner.Key, ObservationAudioPreparation.Verified, ModelContainer, ObservationReanalysisFileStore) -> ObservationAudioExecutionOwner.Admission
    }
    struct Opened {
        let session: CaptureAudioReanalysisSession
        let submit: (@escaping @MainActor @Sendable () -> Bool) async throws -> ObservationAudioExecutionOwner.Admission
    }
    let open: (HistoricalReanalysisTarget, ModelContainer, UUID) throws -> Opened

    static func prepared(account: ObservationHistoryCloudClient, ownership: ObservationReanalysisPreparationOwner,
                         configuration: Configuration,
                         currentOwner: @escaping @MainActor @Sendable () -> UUID?,
                         generation: @escaping @MainActor @Sendable () -> UInt64,
                         sessionIsCurrent: @escaping @MainActor @Sendable (AuthTransitionSession) -> Bool,
                         containerIsCurrent: @escaping @MainActor @Sendable (ModelContainer) -> Bool,
                         documents: @escaping @MainActor () throws -> URL) -> Self {
        Self(open: { target, container, presentationGeneration in
            guard currentOwner() == target.ownerID, containerIsCurrent(container) else { throw ObservationHistoryError.accountChanged }
            let expectedGeneration = generation(), lease = try account.begin(target.ownerID)
            defer { account.finish(lease) }
            guard lease.session.userID == target.ownerID, account.isCurrent(lease), sessionIsCurrent(lease.session) else {
                throw ObservationHistoryError.accountChanged
            }
            let authSession = lease.session
            let current: @MainActor @Sendable () -> Bool = {
                currentOwner() == target.ownerID && generation() == expectedGeneration &&
                    sessionIsCurrent(authSession) && containerIsCurrent(container)
            }
            let source = try ObservationReanalysisSource.capture(observationID: target.observationID,
                analysisID: target.analysisID, ownerID: target.ownerID, container: container)
            let files = try ObservationReanalysisFileStore(documents: documents())
            guard current(), account.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
            let session = CaptureAudioReanalysisSession(source: source, generation: presentationGeneration, container: container)
            let producer = ObservationAudioPreparationProducer(files: files, ownership: ownership, account: account)
            let binding = ObservationAudioSubmissionBinding(ownership: ownership, account: account, authorize: configuration.authorize)
            return Opened(session: session, submit: { presentationIsCurrent in
                try await session.submit(generation: presentationGeneration, producer: producer, binding: binding,
                    isCurrentAccount: current, isCurrentPresentation: presentationIsCurrent, start: { snapshot, proof in
                        guard current() else { return .unavailable }
                        return configuration.start(.init(snapshot: snapshot, session: authSession,
                            generation: expectedGeneration, container: ObjectIdentifier(container)), proof, container, files)
                    })
            })
        })
    }
}
