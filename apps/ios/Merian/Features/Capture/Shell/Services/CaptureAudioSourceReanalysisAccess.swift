import Foundation
import SwiftData

/// Prepared only. Fresh opening freezes a source; resume opening freezes account scope without an idle lease.
@MainActor
struct CaptureAudioSourceReanalysisAccess {
    typealias Admission = CaptureAudioReanalysisSession.SourceAdmission
    typealias SourceStart = (ObservationSourceReservationOwner.Key, ObservationAudioPreparation.Verified, ModelContainer, ObservationReanalysisFileStore) -> ObservationSourceReservationOwner.Admission
    struct Configuration {
        // No presentation predicate crosses this boundary into retained queue execution.
        let start: (ObservationAudioExecutionOwner.Key, ObservationAudioPreparation.Verified, ModelContainer, ObservationReanalysisFileStore) -> ObservationAudioExecutionOwner.Admission
        let sourceStart: SourceStart
    }
    struct Opened {
        let session: CaptureAudioReanalysisSession
        let isCurrent: @MainActor () -> Bool
        let submit: (@escaping @MainActor @Sendable () -> Bool) async throws -> Admission
    }
    struct Resumed {
        let resume: (@escaping @MainActor @Sendable () -> Bool) async throws -> Admission
    }
    let open: (HistoricalReanalysisTarget, ModelContainer, UUID) throws -> Opened
    let openSourceResume: (OfflineQueueWork.Reanalysis, ModelContainer) throws -> Resumed

    static func prepared(account: ObservationHistoryCloudClient, ownership: ObservationReanalysisPreparationOwner,
                         configuration: Configuration,
                         currentOwner: @escaping @MainActor @Sendable () -> UUID?,
                         generation: @escaping @MainActor @Sendable () -> UInt64,
                         sessionIsCurrent: @escaping @MainActor @Sendable (AuthTransitionSession) -> Bool,
                         containerIsCurrent: @escaping @MainActor @Sendable (ModelContainer) -> Bool,
                         documents: @escaping @MainActor () throws -> URL) -> Self {
        let resume: (OfflineQueueWork.Reanalysis, ModelContainer) throws -> Resumed = { identity, container in
            guard currentOwner() == identity.ownerID, containerIsCurrent(container) else { throw ObservationHistoryError.accountChanged }
            let expectedGeneration = generation(), lease = try account.begin(identity.ownerID)
            defer { account.finish(lease) }
            guard lease.session.userID == identity.ownerID, account.isCurrent(lease), sessionIsCurrent(lease.session) else {
                throw ObservationHistoryError.accountChanged
            }
            let authSession = lease.session
            let current: @MainActor @Sendable () -> Bool = {
                currentOwner() == identity.ownerID && generation() == expectedGeneration &&
                    sessionIsCurrent(authSession) && containerIsCurrent(container)
            }
            let files = try ObservationReanalysisFileStore(documents: documents())
            guard current(), account.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
            let reader = ObservationAudioSourceResumeReader(ownership: ownership, account: account)
            return Resumed(resume: { presentationIsCurrent in
                try Task.checkCancellation()
                guard current(), presentationIsCurrent() else { throw ObservationHistoryError.accountChanged }
                let saved = try await reader.read(identity, container: container, isCurrent: current)
                try Task.checkCancellation()
                guard current(), presentationIsCurrent() else { throw ObservationHistoryError.accountChanged }
                guard let admission = ObservationAudioSourceSubmissionService.admission(for: saved.snapshot) else { return .unavailable }
                return Admission(configuration.sourceStart(.init(snapshot: saved.snapshot, admission: admission, session: authSession,
                    generation: expectedGeneration, container: ObjectIdentifier(container)), saved.proof, container, files))
            })
        }
        return Self(open: { target, container, presentationGeneration in
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
            let source = try ObservationReanalysisSource.captureForAudio(observationID: target.observationID,
                analysisID: target.analysisID, ownerID: target.ownerID, container: container)
            let files = try ObservationReanalysisFileStore(documents: documents())
            guard current(), account.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
            let session = CaptureAudioReanalysisSession(source: source, generation: presentationGeneration, container: container)
            let producer = ObservationAudioPreparationProducer(files: files, ownership: ownership, account: account)
            return Opened(session: session, isCurrent: current, submit: { presentationIsCurrent in
                return try await session.submitSource(generation: presentationGeneration, preparation: .init(producer: producer),
                    isCurrentAccount: current, isCurrentPresentation: presentationIsCurrent, start: { saved, proof in
                        guard current() else { return .unavailable }
                        switch saved {
                        case let .source(snapshot):
                            guard let admission = ObservationAudioSourceSubmissionService.admission(for: snapshot) else { return .unavailable }
                            return Admission(configuration.sourceStart(.init(snapshot: snapshot, admission: admission, session: authSession,
                                generation: expectedGeneration, container: ObjectIdentifier(container)), proof, container, files))
                        case let .execution(snapshot):
                            return Admission(configuration.start(.init(snapshot: snapshot, session: authSession,
                                generation: expectedGeneration, container: ObjectIdentifier(container)), proof, container, files))
                        }
                    })
            })
        }, openSourceResume: resume)
    }
}
