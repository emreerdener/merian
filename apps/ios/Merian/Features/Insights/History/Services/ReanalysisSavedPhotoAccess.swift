import Foundation
import SwiftData

/// Local verified original bytes become one bounded display image, never a path or export.
@MainActor
enum ReanalysisSavedPhotoAccess {
    struct Preview: Sendable {
        let image: ImageDownsampler.SendableImage
        let index: Int
        let count: Int
        let validate: @MainActor @Sendable () throws -> Void
    }

    static func read(identity: OfflineQueueWork.Reanalysis, index: Int, container: ModelContainer,
                     files: ObservationReanalysisFileStore, ownership: ObservationReanalysisPreparationOwner,
                     account: ObservationHistoryCloudClient,
                     isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> Preview {
        try await ownership.perform(identity) { owned in
            let lease = try account.begin(identity.ownerID)
            defer { account.finish(lease) }
            let current: @MainActor @Sendable () -> Bool = { isCurrent() && owned() && account.isCurrent(lease) }
            let saved = try snapshot(identity, container: container, isCurrent: current)
            let validate: @MainActor @Sendable () throws -> Void = {
                guard try snapshot(identity, container: container, isCurrent: current) == saved else {
                    throw ObservationHistoryError.resultConflict
                }
            }
            let photos = try await files.readPhotos(draft: saved.draft, validateBeforeRead: validate, validateBeforeReturn: validate)
            guard photos.indices.contains(index) else { throw ObservationHistoryError.unavailable }
            // Complete-cohort verification precedes the display conversion. Only one raster survives.
            let bytes = photos[index].bytes
            let image = try await DetachedWork.value(category: .inferenceRequestPreparation) {
                try Task.checkCancellation()
                guard let image = ImageDownsampler.downsampledSendableImage(data: bytes,
                    maxSize: ImagePreparationPolicy.displayMaxDimension) else { throw ObservationHistoryError.unavailable }
                try Task.checkCancellation()
                return image
            }
            try validate()
            return Preview(image: image, index: index, count: photos.count, validate: {
                guard try snapshot(identity, container: container, isCurrent: isCurrent) == saved else {
                    throw ObservationHistoryError.resultConflict
                }
            })
        }
    }

    private struct Snapshot: Sendable, Equatable {
        let metadata: String
        let draft: ObservationReanalysisDraft
    }

    private static func snapshot(_ identity: OfflineQueueWork.Reanalysis, container: ModelContainer,
                                 isCurrent: () -> Bool) throws -> Snapshot {
        try ObservationReanalysisPersistence.transaction(identity, container: container, isCurrent: isCurrent,
            save: { _ in throw ObservationHistoryError.resultConflict }) { context in
                try ObservationReanalysisPersistence.requireNoResultCollision(identity, context: context)
                guard let (row, job) = try ObservationReanalysisPersistence.pair(identity, context: context),
                      let metadata = job.metadataJSON, metadata.utf8.count <= 1_400_000 else {
                    throw ObservationHistoryError.unavailable
                }
                let data = Data(metadata.utf8)
                let draft: ObservationReanalysisDraft
                if (try? ObservationReanalysisAdmissionWork.decode(data)) != nil {
                    let admission = try ObservationReanalysisAdmissionStore.snapshot(identity, context: context)
                    guard admission.metadata == metadata else { throw ObservationHistoryError.resultConflict }
                    draft = admission.work.preparation.draft
                } else if let pending = try? ObservationReanalysisPreparationIntent.decode(data) {
                    draft = pending.draft
                    try ObservationReanalysisPersistence.validatePending(pending, row: row, job: job, context: context)
                } else if let intent = try? ObservationReanalysisIntent.decode(data) {
                    draft = try .init(identity: intent.identity, evidence: intent.request.evidence)
                    _ = try ObservationReanalysisPersistence.restoreDraft(draft, row: row, job: job)
                } else if let submission = try? ObservationReanalysisSubmissionIntent.decode(data) {
                    draft = submission.draft
                    _ = try ObservationReanalysisPersistence.restoreDraft(draft, row: row, job: job)
                } else {
                    draft = try ObservationReanalysisDraft.decode(data)
                    _ = try ObservationReanalysisPersistence.restoreDraft(draft, row: row, job: job)
                }
                guard draft.identity == identity, draft.evidence.contains(where: { if case .image = $0 { return true }; return false }),
                      draft.evidence.allSatisfy({ evidence in
                          switch evidence {
                          case .image, .description: true
                          }
                      }) else {
                    throw ObservationHistoryError.unavailable
                }
                return Snapshot(metadata: metadata, draft: draft)
            }
    }
}
