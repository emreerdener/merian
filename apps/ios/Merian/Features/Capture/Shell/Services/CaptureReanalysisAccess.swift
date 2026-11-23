import Foundation
import SwiftData

/// Explicit opt-in boundary. Live Capture dependencies remain nil until activation is qualified.
@MainActor
struct CaptureReanalysisAccess {
    typealias CompositionStart = (ObservationCompositionResumeSubmission.Ready, AuthTransitionSession, UInt64, ModelContainer, ObservationReanalysisFileStore) -> Bool
    let open: (HistoricalReanalysisTarget, ModelContainer) throws -> CaptureReanalysisEditor

    static func prepared(ownership: ObservationReanalysisPreparationOwner, account: ObservationHistoryCloudClient? = nil,
                         photos: ObservationHistoryPhotoLoader? = nil,
                         retainedOwner: (@MainActor () async throws -> SharedMediaNativeOriginalOwner)? = nil,
                         audioHost: CaptureWorkspaceAudioReanalysis.HostFactory? = nil,
                         videoHost: CaptureWorkspaceVideoReanalysis.HostFactory? = nil,
                         compositionStart: CompositionStart? = nil,
                         documents: @escaping @MainActor () throws -> URL = {
                             try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                         },
                         isCurrentOwner: @escaping @MainActor () -> UUID?,
                         generation: @escaping @MainActor () -> UInt64,
                         sessionIsCurrent: @escaping @MainActor (AuthTransitionSession) -> Bool = { _ in true },
                         requestSubmitted: @escaping @MainActor (UUID) -> Void,
                         requestCleanup: @escaping @MainActor () -> Void) -> Self {
        let account = account ?? .live
        let photos = photos ?? ObservationHistoryPhotoLoader(account: account, resolve: account.resolvePhoto)
        let loadPhoto: (ObservationReanalysisSource, ObservationHistoryPhotoReference, ModelContainer) async throws -> Data = { source, photo, container in
            try await photos.load(observationID: source.observationID.uuidString, analysisID: source.analysisID, mediaID: photo.mediaID, container: container)
        }
        return Self(open: { target, container in
            guard isCurrentOwner() == target.ownerID else { throw ObservationHistoryError.accountChanged }
            let expectedGeneration = generation()
            let lease = try account.begin(target.ownerID)
            defer { account.finish(lease) }
            guard lease.session.userID == target.ownerID, account.isCurrent(lease), sessionIsCurrent(lease.session) else { throw ObservationHistoryError.accountChanged }
            let source = try ObservationReanalysisSource.capture(observationID: target.observationID,
                analysisID: target.analysisID, ownerID: target.ownerID, container: container)
            let session = lease.session
            let current: @MainActor @Sendable () -> Bool = {
                isCurrentOwner() == target.ownerID && generation() == expectedGeneration && sessionIsCurrent(session)
            }
            guard current() else { throw ObservationHistoryError.accountChanged }
            let documents = try documents()
            let audio = try audioHost.map { factory in
                CaptureWorkspaceAudioReanalysis(source: try .capture(observationID: target.observationID,
                    analysisID: target.analysisID, ownerID: target.ownerID, container: container), container: container,
                    loader: .init(account: account), files: .init(documents: documents, temporaryDirectory: FileManager.default.temporaryDirectory),
                    documents: documents, makeHost: factory, current: current)
            }
            let video = try videoHost.map { factory in
                CaptureWorkspaceVideoReanalysis(source: try .capture(observationID: target.observationID,
                    analysisID: target.analysisID, ownerID: target.ownerID, container: container), container: container,
                    loader: .init(account: account), files: .init(documents: documents, temporaryDirectory: FileManager.default.temporaryDirectory),
                    makeHost: factory, current: current)
            }
            let composition = compositionStart.map { start in
                CaptureWorkspaceCompositionReanalysis(source: source, container: container,
                    producer: .init(files: .init(documents: documents), ownership: ownership, account: account),
                    files: .init(documents: documents, temporaryDirectory: FileManager.default.temporaryDirectory),
                    current: current, start: { ready, container, files in
                        guard current() else { return false }
                        return start(ready, session, expectedGeneration, container, files)
                    })
            }
            return CaptureReanalysisEditor(source: source, container: container, account: account,
                loader: CaptureReanalysisEvidenceLoader(account: account, retainedOwner: retainedOwner, loadPhoto: loadPhoto),
                producer: ObservationReanalysisProducer(files: ObservationReanalysisFileStore(documents: documents), ownership: ownership, account: account, loadOriginal: loadPhoto),
                isCurrent: current, requestSubmitted: requestSubmitted, requestCleanup: requestCleanup, workspaceAudio: audio, workspaceVideo: video, workspaceComposition: composition)
        })
    }
}
