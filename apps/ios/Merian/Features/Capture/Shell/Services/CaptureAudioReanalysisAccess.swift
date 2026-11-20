import Foundation
import SwiftData

/// Prepared only. Fresh opening freezes a source; resume opening freezes account scope without an idle lease.
@MainActor
struct CaptureAudioReanalysisAccess {
    struct Preview: Sendable {
        let bytes: Data
        let validate: @MainActor @Sendable () throws -> Void
    }
    struct Configuration {
        let authorize: @MainActor @Sendable (UUID, @escaping ObservationAudioSubmissionBinding.Validate) async throws -> IdentificationDispatchAuthorization
        // No presentation predicate crosses this boundary into retained queue execution.
        let start: (ObservationAudioExecutionOwner.Key, ObservationAudioPreparation.Verified, ModelContainer, ObservationReanalysisFileStore) -> ObservationAudioExecutionOwner.Admission
        var recover: ((ObservationAudioExecutionOwner.Key, ObservationAudioPreparation.Verified, ModelContainer, ObservationReanalysisFileStore) async throws -> Bool)?
    }
    struct Opened {
        let session: CaptureAudioReanalysisSession
        let isCurrent: @MainActor () -> Bool
        let submit: (@escaping @MainActor @Sendable () -> Bool) async throws -> ObservationAudioExecutionOwner.Admission
    }
    struct Resumed {
        let resume: (@escaping @MainActor @Sendable () -> Bool) async throws -> ObservationAudioExecutionOwner.Admission
        var recovery: AnalysisRecoveryCheckingModel.Access?
        var preview: ((@escaping @MainActor @Sendable () -> Bool) async throws -> Preview)?
    }
    let open: (HistoricalReanalysisTarget, ModelContainer, UUID) throws -> Opened
    let openResume: (OfflineQueueWork.Reanalysis, ModelContainer) throws -> Resumed

    static func previewPlayer(_ bytes: Data, validate: @escaping () -> Bool) -> CaptureSavedAudioPreviewModel {
        CaptureSavedAudioPreviewModel(driver: AudioPlaybackFileDriver(data: bytes), validate: validate)
    }

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
            let source = try ObservationReanalysisSource.captureForAudio(observationID: target.observationID,
                analysisID: target.analysisID, ownerID: target.ownerID, container: container)
            let files = try ObservationReanalysisFileStore(documents: documents())
            guard current(), account.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
            let session = CaptureAudioReanalysisSession(source: source, generation: presentationGeneration, container: container)
            let producer = ObservationAudioPreparationProducer(files: files, ownership: ownership, account: account)
            let binding = ObservationAudioSubmissionBinding(ownership: ownership, account: account, authorize: configuration.authorize)
            return Opened(session: session, isCurrent: current, submit: { presentationIsCurrent in
                try await session.submit(generation: presentationGeneration, producer: producer, binding: binding,
                    isCurrentAccount: current, isCurrentPresentation: presentationIsCurrent, start: { snapshot, proof in
                        guard current() else { return .unavailable }
                        return configuration.start(.init(snapshot: snapshot, session: authSession,
                            generation: expectedGeneration, container: ObjectIdentifier(container)), proof, container, files)
                    })
            })
        }, openResume: { identity, container in
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
            let service = ObservationAudioResumeSubmission(producer: .init(files: files, ownership: ownership, account: account),
                authorize: configuration.authorize)
            var resumed = Resumed(resume: { presentationIsCurrent in
                try Task.checkCancellation()
                guard current(), presentationIsCurrent() else { throw ObservationHistoryError.accountChanged }
                let saved = try await service.resume(identity, container: container, isCurrent: current)
                try Task.checkCancellation()
                guard current(), presentationIsCurrent() else { throw ObservationHistoryError.accountChanged }
                guard try ObservationAudioExecutionStore.read(saved.proof, container: container, isCurrent: current) == saved.snapshot else {
                    throw ObservationHistoryError.resultConflict
                }
                guard current(), presentationIsCurrent() else { throw ObservationHistoryError.accountChanged }
                return configuration.start(.init(snapshot: saved.snapshot, session: authSession,
                    generation: expectedGeneration, container: ObjectIdentifier(container)), saved.proof, container, files)
            })
            resumed.preview = { presentationIsCurrent in
                try await ownership.perform(identity) { owned in
                    let lease = try account.begin(identity.ownerID)
                    defer { account.finish(lease) }
                    let valid: @MainActor @Sendable () -> Bool = {
                        current() && owned() && account.isCurrent(lease) && presentationIsCurrent()
                    }
                    let saved = try await ObservationAudioResumeStore.read(identity, container: container, isCurrent: valid)
                    let validate: @MainActor @Sendable () throws -> Void = {
                        guard valid() else { throw ObservationHistoryError.accountChanged }
                        if case .unprepared = try ObservationAudioExecutionStore.admissionState(saved.proof, container: container, isCurrent: valid) {
                            throw ObservationHistoryError.unavailable
                        }
                    }
                    let bytes = try await files.readAudio(preparation: saved.proof.preparation,
                        validateBeforeRead: validate, validateBeforeReturn: validate)
                    try validate()
                    return Preview(bytes: bytes, validate: {
                        guard current(), presentationIsCurrent() else { throw ObservationHistoryError.accountChanged }
                        if case .unprepared = try ObservationAudioExecutionStore.admissionState(saved.proof, container: container, isCurrent: current) {
                            throw ObservationHistoryError.unavailable
                        }
                    })
                }
            }
            if let recover = configuration.recover {
                var ready: ObservationAudioResumeSubmission.Ready?
                resumed.recovery = .init(isCurrent: current, reserve: {
                    let saved = try await ownership.perform(identity) { owned in
                        let lease = try account.begin(identity.ownerID)
                        defer { account.finish(lease) }
                        return try await ObservationAudioResumeStore.read(identity, container: container, isCurrent: {
                            current() && owned() && account.isCurrent(lease)
                        })
                    }
                    guard case let .bound(snapshot) = saved.state, snapshot.work.consumedAttempt != nil else {
                        throw ObservationHistoryError.unavailable
                    }
                    ready = .init(proof: saved.proof, snapshot: snapshot)
                    let budget = AnalysisRecoveryCheckingModel.Access.prepared(identity: identity, container: container,
                        isCurrent: current, validateOperation: {
                            guard try ObservationAudioExecutionStore.read(saved.proof, container: container, isCurrent: current) == snapshot else {
                                throw ObservationHistoryError.resultConflict
                            }
                        }, check: { false })
                    return try await budget.reserve()
                }, check: {
                    guard current(), let ready, ready.snapshot.work.consumedAttempt != nil else { throw ObservationHistoryError.unavailable }
                    return try await recover(.init(snapshot: ready.snapshot, session: authSession,
                        generation: expectedGeneration, container: ObjectIdentifier(container)), ready.proof, container, files)
                })
            }
            return resumed
        })
    }
}
