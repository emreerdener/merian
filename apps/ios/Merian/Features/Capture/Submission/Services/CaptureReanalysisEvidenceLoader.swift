import Foundation
import SwiftData
import UIKit

/// All-or-nothing staging from private verified bytes. The caller commits only the returned complete capture.
@MainActor
struct CaptureReanalysisEvidenceLoader {
    var account = ObservationHistoryCloudClient.live
    var loadPhoto: (ObservationReanalysisSource, ObservationHistoryPhotoReference, ModelContainer) async throws -> Data = { source, photo, container in
        try await ObservationHistoryPhotoLoader().load(observationID: source.observationID.uuidString,
            analysisID: source.analysisID, mediaID: photo.mediaID, container: container)
    }

    func load(_ selection: CaptureReanalysisEvidenceSelection, container: ModelContainer,
              isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> StagedCapture {
        let source = selection.source
        let lease = try account.begin(source.ownerID)
        defer { account.finish(lease) }
        let validate: @MainActor () throws -> Void = {
            try Task.checkCancellation()
            guard lease.session.userID == source.ownerID, account.isCurrent(lease), isCurrent() else { throw ObservationHistoryError.accountChanged }
            try source.validate(container: container)
        }
        try validate()
        var capture = StagedCapture()
        for (index, item) in selection.evidence.enumerated() {
            let order = Date(timeIntervalSince1970: TimeInterval(index))
            switch item {
            case let .description(text):
                capture.observationContexts.append(.init(context: .init(freeText: text), addedAt: order))
            case let .photo(photo):
                let bytes = try await loadPhoto(source, photo, container)
                try validate()
                let preview = try await DetachedWork.value(category: .imagePreparation) {
                    // Validate the actual container as well as the exact immutable reference, even for injected loaders.
                    _ = try ObservationReanalysisPhotoPreparation.prepare(bytes: bytes, mediaID: photo.mediaID, original: photo)
                    guard let image = ImageDownsampler.downsampledSendableImage(data: bytes, maxSize: 1024) else {
                        throw ObservationHistoryError.invalidSnapshot
                    }
                    return image
                }
                try validate()
                let image = UIImage(cgImage: preview.cgImage)
                capture.images.append(.init(compressedData: bytes, displayData: bytes, uiImage: image,
                    original: .init(image: image), addedAt: order,
                    reanalysisProvenance: .original(analysisID: source.analysisID, photo: photo)))
            }
        }
        try validate()
        return capture
    }
}
