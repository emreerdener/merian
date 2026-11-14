import Foundation
import SwiftData

/// Explicit saved video only. Opening freezes scope without holding an idle account lease.
@MainActor
struct CaptureVideoResumeAccess {
    enum Admission: Equatable { case started, coalesced, unavailable }
    struct Preview: Sendable {
        let bytes: Data
        let validate: @MainActor @Sendable () throws -> Void
    }
    struct Configuration {
        // Queue execution receives account scope, never presentation lifetime.
        let start: (ObservationVideoResumeSubmission.Ready, AuthTransitionSession, UInt64,
                    ModelContainer, ObservationReanalysisFileStore) -> Admission
        var recover: ((ObservationVideoExecutionOwner.Key, ObservationVideoPreparation.Verified,
                       ModelContainer, ObservationReanalysisFileStore) async throws -> Bool)?
    }
    struct Resumed {
        let resume: (@escaping @MainActor @Sendable () -> Bool) async throws -> Admission
        var recovery: AnalysisRecoveryCheckingModel.Access?
        var preview: ((@escaping @MainActor @Sendable () -> Bool) async throws -> Preview)?
    }
    let openResume: (OfflineQueueWork.Reanalysis, ModelContainer) throws -> Resumed

    static func prepared(account: ObservationHistoryCloudClient, ownership: ObservationReanalysisPreparationOwner,
                         configuration: Configuration,
                         currentOwner: @escaping @MainActor @Sendable () -> UUID?,
                         generation: @escaping @MainActor @Sendable () -> UInt64,
                         sessionIsCurrent: @escaping @MainActor @Sendable (AuthTransitionSession) -> Bool,
                         containerIsCurrent: @escaping @MainActor @Sendable (ModelContainer) -> Bool,
                         documents: @escaping @MainActor () throws -> URL) -> Self {
        Self(openResume: { identity, container in
            guard currentOwner() == identity.ownerID, containerIsCurrent(container) else { throw ObservationHistoryError.accountChanged }
            let expectedGeneration = generation(), lease = try account.begin(identity.ownerID)
            defer { account.finish(lease) }
            let session = lease.session
            let current: @MainActor @Sendable () -> Bool = {
                currentOwner() == identity.ownerID && generation() == expectedGeneration &&
                    sessionIsCurrent(session) && containerIsCurrent(container)
            }
            guard session.userID == identity.ownerID, current(), account.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
            let files = try ObservationReanalysisFileStore(documents: documents())
            let service = ObservationVideoResumeSubmission(producer: .init(files: files, ownership: ownership, account: account))
            guard current(), account.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
            var resumed = Resumed(resume: { presentationIsCurrent in
                try Task.checkCancellation()
                guard current(), presentationIsCurrent() else { throw ObservationHistoryError.accountChanged }
                guard let ready = try await service.resume(identity, container: container, isCurrent: current) else { return .unavailable }
                try Task.checkCancellation()
                guard current(), presentationIsCurrent() else { throw ObservationHistoryError.accountChanged }
                try ObservationVideoResumeSubmission.validate(ready, container: container, isCurrent: current)
                return configuration.start(ready, session, expectedGeneration, container, files)
            })
            resumed.preview = { presented in
                try await ownership.perform(identity) { owned in
                    let previewLease = try account.begin(identity.ownerID)
                    defer { account.finish(previewLease) }
                    let active: @MainActor @Sendable () -> Bool = {
                        current() && presented() && owned() && account.isCurrent(previewLease)
                    }
                    let saved = try await ObservationVideoResumeStore().read(identity, container: container, isCurrent: active)
                    let check: @MainActor @Sendable () throws -> Void = {
                        try ObservationVideoResumeStore.validate(saved, container: container, isCurrent: active)
                    }
                    let cohort = try await files.readVideo(preparation: saved.proof.preparation,
                        validateBeforeRead: check, validateBeforeReturn: check)
                    try check()
                    guard let original = cohort.first,
                          original.artifact == saved.proof.preparation.request.manifest.provenance.source else {
                        throw ObservationHistoryError.unavailable
                    }
                    return Preview(bytes: original.bytes, validate: {
                        try ObservationVideoResumeStore.validate(saved, container: container,
                            isCurrent: { current() && presented() })
                    })
                }
            }
            if let recover = configuration.recover {
                var ready: ObservationVideoResumeStore.Saved?
                resumed.recovery = .init(isCurrent: current, reserve: {
                    let saved = try await ObservationVideoResumeReader(ownership: ownership, account: account)
                        .read(identity, container: container, isCurrent: current)
                    guard case let .execution(snapshot) = saved.state, snapshot.work.consumed else { throw ObservationHistoryError.unavailable }
                    ready = saved
                    let budget = AnalysisRecoveryCheckingModel.Access.prepared(identity: identity, container: container,
                        isCurrent: current, validateOperation: {
                            try ObservationVideoResumeStore.validate(saved, container: container, isCurrent: current)
                        }, check: { false })
                    return try await budget.reserve()
                }, check: {
                    guard current(), let ready, case let .execution(snapshot) = ready.state, snapshot.work.consumed else {
                        throw ObservationHistoryError.unavailable
                    }
                    return try await recover(.init(snapshot: snapshot, session: session,
                        generation: expectedGeneration, container: ObjectIdentifier(container)), ready.proof, container, files)
                })
            }
            return resumed
        })
    }
}
