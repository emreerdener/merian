import Foundation
import SwiftData

/// Prepares immutable private files and saves a held child; never admits inference or funding.
@MainActor
struct ObservationReanalysisProducer {
    let files: ObservationReanalysisFileStore
    var account = ObservationHistoryCloudClient.live
    var loadOriginal: (ObservationReanalysisSource, ObservationHistoryPhotoReference, ModelContainer) async throws -> Data = { source, photo, container in
        try await ObservationHistoryPhotoLoader().load(observationID: source.observationID.uuidString,
            analysisID: source.analysisID, mediaID: photo.mediaID, container: container)
    }

    func stage(_ plan: ObservationReanalysisPreparationPlan, container: ModelContainer,
               isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> ObservationReanalysisPersistence.DraftState {
        let source = plan.source
        let lease = try account.begin(source.ownerID)
        defer { account.finish(lease) }
        let validate: @MainActor @Sendable () throws -> Void = {
            try Task.checkCancellation()
            guard lease.session.userID == source.ownerID, account.isCurrent(lease), isCurrent() else { throw ObservationHistoryError.accountChanged }
            try source.validate(container: container)
        }
        try validate()
        var evidence: [ObservationReanalysisRequest.Evidence] = [], photos: [Data] = [], totalBytes = 0
        for item in plan.items {
            switch item {
            case let .description(text): evidence.append(.description(text))
            case let .photo(mediaID, input):
                let bytes: Data, original: ObservationHistoryPhotoReference?
                switch input {
                case let .original(reference):
                    bytes = try await loadOriginal(source, reference, container); original = reference
                    try validate()
                case let .added(data), let .edited(_, data): bytes = data; original = nil
                }
                let prepared = try await DetachedWork.value(category: .inferenceRequestPreparation) {
                    try ObservationReanalysisPhotoPreparation.prepare(bytes: bytes, mediaID: mediaID, original: original)
                }
                try validate()
                guard prepared.bytes.count <= ObservationEvidenceUpload.maximumBytes - totalBytes else { throw MerianError.invalidResponse }
                totalBytes += prepared.bytes.count
                evidence.append(.image(prepared.reference)); photos.append(prepared.bytes)
            }
        }
        let draft = try ObservationReanalysisDraft(identity: .init(observationID: source.observationID, sourceAnalysisID: source.analysisID,
            analysisID: plan.analysisID, ownerID: source.ownerID), evidence: evidence)
        return try await files.persist(draft: draft, photos: photos) {
            // No suspension or fallible post-save work inside the filesystem ownership fence.
            try validate()
            return try ObservationReanalysisPersistence.stageDraft(draft, container: container,
                isCurrent: { account.isCurrent(lease) && isCurrent() }, validateSource: { try source.validate(context: $0) })
        }
    }
}
