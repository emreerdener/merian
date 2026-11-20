import Foundation
import SwiftData

/// Prepared fresh-video boundary. Discovery is not selection, and constructing access starts no work.
@MainActor
struct CaptureVideoReanalysisAccess {
    struct Configuration {
        let resume: CaptureVideoResumeAccess.Configuration
        let files: FileIOActor
        let temporaryDirectory: () throws -> URL
        let prepareLifetime: () throws -> Void
        let startup: (ModelContainer) throws -> NativeReleaseStartupAdmission
        var borrowing: ((ModelContainer) throws -> SharedMediaNativeOriginalDrain.LocalBorrow)?
    }
    struct Opened {
        let session: CaptureVideoReanalysisSession
        let choices: [ObservationReanalysisLocalVideoInput.Choice]
        let isCurrent: @MainActor () -> Bool
        let submit: (@escaping @MainActor @Sendable () -> Bool) async throws -> CaptureVideoResumeAccess.Admission
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
            let authSession = lease.session
            let current: @MainActor @Sendable () -> Bool = {
                currentOwner() == target.ownerID && generation() == expectedGeneration &&
                    sessionIsCurrent(authSession) && containerIsCurrent(container)
            }
            guard authSession.userID == target.ownerID, current(), account.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
            let source = try ObservationReanalysisSource.captureForVideo(observationID: target.observationID,
                analysisID: target.analysisID, ownerID: target.ownerID, container: container)
            let choices = try ObservationReanalysisLocalVideoInput.choices(source: source, container: container)
            guard !choices.isEmpty else { throw ObservationHistoryError.unavailable }
            let store = try ObservationReanalysisFileStore(documents: documents())
            let directory = try configuration.temporaryDirectory()
            try configuration.prepareLifetime()
            let startup = try configuration.startup(container)
            let borrowing = try configuration.borrowing?(container)
            guard current(), account.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
            let session = CaptureVideoReanalysisSession(source: source, generation: presentationGeneration, container: container)
            let producer = ObservationVideoPreparationProducer(files: store, ownership: ownership, account: account)
            return Opened(session: session, choices: choices, isCurrent: current, submit: { presentationIsCurrent in
                try await session.submit(generation: presentationGeneration, files: configuration.files,
                    temporaryDirectory: directory, startup: startup, borrowing: borrowing, producer: producer, isCurrentAccount: current,
                    isCurrentPresentation: presentationIsCurrent, start: { ready in
                        guard current() else { return .unavailable }
                        return configuration.resume.start(ready, authSession, expectedGeneration, container, store)
                    })
            })
        })
    }
}
